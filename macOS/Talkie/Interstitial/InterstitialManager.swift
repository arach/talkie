//
//  InterstitialManager.swift
//  Talkie
//
//  Manages the floating interstitial editor panel for quick text editing and LLM polish
//  Triggered via talkie://interstitial/{id} URL from TalkieLive (Shift-click to stop)
//

import SwiftUI
import AppKit
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Interstitial")

/// View state for the interstitial panel
enum InterstitialViewState {
    case editing      // Normal text editing mode
    case reviewing    // Diff review mode after polish
}

@MainActor
final class InterstitialManager: ObservableObject {
    static let shared = InterstitialManager()

    private var panel: NSPanel?
    private var localEventMonitor: Any?

    @Published var isVisible: Bool = false
    @Published var currentUtteranceId: Int64?
    @Published var editedText: String = ""
    @Published var isPolishing: Bool = false
    @Published var polishError: String?
    @Published private(set) var originalText: String = ""

    // View state (editing vs reviewing diff)
    @Published var viewState: InterstitialViewState = .editing
    @Published private(set) var prePolishText: String = ""  // Text before last polish

    /// Computed diff between pre-polish and current edited text
    var currentDiff: TextDiff? {
        guard viewState == .reviewing, !prePolishText.isEmpty else { return nil }
        return DiffEngine.diff(original: prePolishText, proposed: editedText)
    }

    // MARK: - Edit History (in-memory micro-history)

    /// A snapshot of an edit in the session
    struct EditSnapshot: Identifiable {
        let id = UUID()
        let timestamp: Date
        let instruction: String      // What prompt/instruction was used
        let textBefore: String       // Text before this edit
        let textAfter: String        // Text after this edit
        let changeCount: Int         // Number of changes in the diff

        var timeAgo: String {
            let seconds = Int(Date().timeIntervalSince(timestamp))
            if seconds < 60 { return "\(seconds)s ago" }
            let minutes = seconds / 60
            return "\(minutes)m ago"
        }

        var shortInstruction: String {
            let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count <= 30 { return trimmed }
            return String(trimmed.prefix(27)) + "..."
        }
    }

    @Published private(set) var editHistory: [EditSnapshot] = []
    @Published var previewingSnapshot: EditSnapshot? = nil  // Currently previewing (not applied)

    /// Preview a snapshot (doesn't change anything, just for viewing)
    func previewSnapshot(_ snapshot: EditSnapshot) {
        previewingSnapshot = snapshot
    }

    /// Stop previewing, return to normal view
    func dismissPreview() {
        previewingSnapshot = nil
    }

    /// Actually restore from a snapshot (user explicitly chose to)
    /// This creates a NEW history entry, doesn't delete anything
    func restoreFromSnapshot(_ snapshot: EditSnapshot) {
        let currentText = editedText

        // Record this restoration as a new edit
        let restorationSnapshot = EditSnapshot(
            timestamp: Date(),
            instruction: "Restored to: \(snapshot.shortInstruction)",
            textBefore: currentText,
            textAfter: snapshot.textAfter,
            changeCount: DiffEngine.diff(original: currentText, proposed: snapshot.textAfter).changeCount
        )
        editHistory.append(restorationSnapshot)

        // Apply the restoration
        editedText = snapshot.textAfter
        previewingSnapshot = nil
        viewState = .editing

        logger.info("Restored from snapshot: \(snapshot.shortInstruction)")
    }

    /// Clear all history (called on dismiss)
    private func clearHistory() {
        editHistory.removeAll()
        previewingSnapshot = nil
    }

    // Voice guidance state
    @Published var isRecordingInstruction: Bool = false
    @Published var isTranscribingInstruction: Bool = false
    @Published var voiceInstruction: String?
    @Published var audioLevel: Float = 0

    // LLM Settings (exposed for visibility/control)
    @Published var showLLMSettings: Bool = false
    @Published var llmTemperature: Double = 0.3
    @Published var llmMaxTokens: Int = 2048
    @Published var llmProviderId: String?
    @Published var llmModelId: String?

    // Editable system prompt (the "magic" instructions for the LLM)
    @Published var systemPrompt: String = """
        You are helping edit transcribed speech. Apply the user's instruction to transform the text.
        Return only the transformed text, nothing else. Preserve the original meaning unless asked otherwise.
        """

    // Last generation info (for transparency)
    @Published private(set) var lastUsedProvider: String?
    @Published private(set) var lastUsedModel: String?
    @Published private(set) var lastPrompt: String?
    @Published private(set) var lastTokenCount: Int?

    private init() {
        // Initialize with registry defaults if available
        Task { @MainActor in
            if let resolved = await LLMProviderRegistry.shared.resolveProviderAndModel() {
                llmProviderId = resolved.provider.id
                llmModelId = resolved.modelId
            }
        }
    }

    // MARK: - Show/Dismiss

    func show(utteranceId: Int64) {
        NSLog("[Interstitial] show() called with utteranceId: \(utteranceId)")
        logger.info("=== INTERSTITIAL SHOW REQUEST ===")
        logger.info("Utterance ID: \(utteranceId)")

        // If already showing, dismiss first
        if panel != nil {
            NSLog("[Interstitial] Dismissing existing panel")
            dismiss()
        }

        // Fetch utterance from UtteranceStore/LiveDatabase
        NSLog("[Interstitial] Refreshing UtteranceStore...")
        UtteranceStore.shared.refresh()

        NSLog("[Interstitial] UtteranceStore has \(UtteranceStore.shared.utterances.count) utterances")
        NSLog("[Interstitial] Database path: \(LiveDatabase.databaseURL.path)")

        guard let utterance = LiveDatabase.fetch(id: utteranceId) else {
            NSLog("[Interstitial] ERROR: Utterance \(utteranceId) not found in shared database")
            logger.error("Utterance \(utteranceId) not found in shared database. Database has \(UtteranceStore.shared.utterances.count) utterances.")
            return
        }

        NSLog("[Interstitial] Found utterance: \"\(utterance.text.prefix(50))...\"")

        currentUtteranceId = utteranceId
        originalText = utterance.text
        editedText = utterance.text

        logger.info("Showing interstitial for utterance \(utteranceId): \"\(utterance.text.prefix(40))...\"")

        createAndShowPanel()
        NSLog("[Interstitial] Panel created and shown")
    }

    private func createAndShowPanel() {
        let view = InterstitialEditorView(manager: self)
        let hostingView = NSHostingView(rootView: view)

        let width: CGFloat = 580
        let height: CGFloat = 420
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        // Set min/max size constraints
        panel.minSize = NSSize(width: 480, height: 340)
        panel.maxSize = NSSize(width: 900, height: 700)

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hostingView
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.becomesKeyOnlyIfNeeded = false

        // Center on screen, slightly above center
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - width / 2
            let y = screenFrame.midY - height / 2 + 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.panel = panel
        self.isVisible = true

        setupEventMonitors()
    }

    private func setupEventMonitors() {
        // Local monitor for Escape key to dismiss
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.dismiss()
                return nil
            }
            return event
        }
    }

    func dismiss() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }

        panel?.orderOut(nil)
        panel = nil
        isVisible = false
        currentUtteranceId = nil
        editedText = ""
        originalText = ""
        prePolishText = ""
        viewState = .editing
        isPolishing = false
        polishError = nil
        voiceInstruction = nil
        clearHistory()  // Clear in-memory history on dismiss

        logger.info("Interstitial dismissed")
    }

    // MARK: - Actions

    func copyAndDismiss() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(editedText, forType: .string)
        logger.info("Copied to clipboard: \(self.editedText.count) chars")
        dismiss()
    }

    /// Copy to clipboard without dismissing - user controls when to exit
    func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(editedText, forType: .string)
        logger.info("Copied to clipboard: \(self.editedText.count) chars")
    }

    func pasteAndDismiss() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(editedText, forType: .string)
        dismiss()

        // Simulate paste after panel dismisses
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.simulatePaste()
        }
        logger.info("Pasting text: \(self.editedText.count) chars")
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)

        // Cmd down
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)

        // V down
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)

        // V up
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand
        vUp?.post(tap: .cghidEventTap)

        // Cmd up
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        cmdUp?.post(tap: .cghidEventTap)
    }

    func openInDestination(_ target: QuickOpenTarget) {
        QuickOpenService.shared.open(content: editedText, in: target)
        dismiss()
    }

    func resetText() {
        editedText = originalText
    }

    // MARK: - Voice Guidance

    /// Start recording voice instruction
    func startVoiceInstruction() {
        guard !isRecordingInstruction else { return }

        do {
            try EphemeralTranscriber.shared.startCapture()
            isRecordingInstruction = true
            voiceInstruction = nil
            logger.info("Started voice instruction capture")

            // Monitor audio level
            Task {
                while isRecordingInstruction {
                    audioLevel = EphemeralTranscriber.shared.audioLevel
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                }
            }
        } catch {
            polishError = error.localizedDescription
            logger.error("Failed to start voice capture: \(error.localizedDescription)")
        }
    }

    /// Stop recording and use voice as LLM instruction
    func stopVoiceInstruction() async {
        guard isRecordingInstruction else { return }

        isRecordingInstruction = false
        isTranscribingInstruction = true
        audioLevel = 0

        do {
            let instruction = try await EphemeralTranscriber.shared.stopAndTranscribe()
            isTranscribingInstruction = false

            if !instruction.isEmpty {
                voiceInstruction = instruction
                logger.info("Voice instruction: \(instruction)")

                // Auto-trigger polish with the voice instruction
                await polishText(instruction: instruction)
            }
        } catch {
            isTranscribingInstruction = false
            polishError = error.localizedDescription
            logger.error("Voice instruction failed: \(error.localizedDescription)")
        }
    }

    /// Cancel voice recording without using it
    func cancelVoiceInstruction() {
        EphemeralTranscriber.shared.cancel()
        isRecordingInstruction = false
        isTranscribingInstruction = false
        audioLevel = 0
    }

    // MARK: - LLM Polish

    func polishText(instruction: String? = nil) async {
        guard !isPolishing else { return }

        isPolishing = true
        polishError = nil

        // Save pre-polish text for diff comparison
        prePolishText = editedText

        logger.info("Polishing text with instruction: \(instruction ?? "default")")

        do {
            let registry = LLMProviderRegistry.shared

            // Use user-selected provider/model or fall back to registry resolution
            let resolved: (provider: LLMProvider, modelId: String)
            if let providerId = llmProviderId,
               let provider = registry.provider(for: providerId),
               let modelId = llmModelId {
                resolved = (provider, modelId)
            } else if let fallback = await registry.resolveProviderAndModel() {
                resolved = fallback
            } else {
                polishError = "No LLM provider configured"
                isPolishing = false
                logger.warning("No LLM provider available")
                return
            }

            // Build the prompt using system prompt + instruction + text
            let userInstruction: String
            if let instruction = instruction, !instruction.isEmpty {
                // Check if this is a full prompt template (multi-line or long)
                let isFullPrompt = instruction.contains("\n") || instruction.count > 100
                if isFullPrompt {
                    // Full prompt from smart action - use as instruction
                    userInstruction = instruction
                } else {
                    // Short instruction (typed or voice)
                    userInstruction = instruction
                }
            } else {
                // Default polish instruction
                userInstruction = "Fix grammar, remove filler words (um, uh, like), and make it clearer while preserving the original meaning and tone."
            }

            // Compose full prompt: system + instruction + text
            let prompt = """
            \(systemPrompt)

            Instruction: \(userInstruction)

            Text:
            \(editedText)
            """

            // Use user's settings
            let options = GenerationOptions(
                temperature: llmTemperature,
                maxTokens: llmMaxTokens
            )

            // Track what we're using (for transparency)
            lastUsedProvider = resolved.provider.name
            lastUsedModel = resolved.modelId
            lastPrompt = prompt
            lastTokenCount = prompt.split(separator: " ").count * 2 // Rough estimate

            let polished = try await resolved.provider.generate(
                prompt: prompt,
                model: resolved.modelId,
                options: options
            )

            editedText = polished.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.info("Polish complete: \(self.editedText.count) chars via \(resolved.provider.name)/\(resolved.modelId)")

            // Switch to review mode to show diff
            viewState = .reviewing

        } catch {
            polishError = error.localizedDescription
            prePolishText = ""  // Clear on error
            logger.error("Polish failed: \(error.localizedDescription)")
        }

        isPolishing = false
    }

    // MARK: - Diff Review Actions

    /// Accept the polished changes and return to editing mode
    func acceptChanges() {
        // Record to history before clearing prePolishText
        if !prePolishText.isEmpty {
            let diff = DiffEngine.diff(original: prePolishText, proposed: editedText)
            let instruction = voiceInstruction ?? "Polish"

            let snapshot = EditSnapshot(
                timestamp: Date(),
                instruction: instruction,
                textBefore: prePolishText,
                textAfter: editedText,
                changeCount: diff.changeCount
            )
            editHistory.append(snapshot)
            logger.info("Recorded edit to history: \(instruction.prefix(30))... (\(diff.changeCount) changes)")
        }

        viewState = .editing
        prePolishText = ""
        voiceInstruction = nil  // Clear after recording
        logger.info("Accepted polish changes")
    }

    /// Reject the polished changes, revert to pre-polish text
    func rejectChanges() {
        editedText = prePolishText
        viewState = .editing
        prePolishText = ""
        voiceInstruction = nil
        logger.info("Rejected polish changes, reverted to pre-polish text")
    }

    // MARK: - Open in Talkie (Promote to Memo)

    func openInTalkie() {
        guard let utteranceId = currentUtteranceId else {
            dismiss()
            return
        }

        // TODO: Create VoiceMemo in Core Data from the utterance
        // For now, just activate Talkie and dismiss
        logger.info("Opening utterance \(utteranceId) in Talkie (promotion not yet implemented)")

        dismiss()

        // Activate Talkie's main window
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            if !window.title.isEmpty || window.identifier?.rawValue.contains("main") == true {
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
    }
}
