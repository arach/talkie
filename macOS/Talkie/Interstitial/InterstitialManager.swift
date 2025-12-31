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
@Observable
final class InterstitialManager {
    static let shared = InterstitialManager()

    private var panel: NSPanel?
    private var localEventMonitor: Any?

    var isVisible: Bool = false
    var currentDictationId: Int64?
    var editedText: String = ""
    var isPolishing: Bool = false
    var polishError: String?
    private(set) var originalText: String = ""

    // Selection replacement context (for Command+Enter)
    private(set) var originalSelectedText: String?  // Text that was selected when auto-scratchpad triggered
    private(set) var sourceAppBundleID: String?     // Bundle ID of the app where recording started
    var hasSelectionContext: Bool { originalSelectedText != nil && sourceAppBundleID != nil }

    // View state (editing vs reviewing diff)
    var viewState: InterstitialViewState = .editing
    private(set) var prePolishText: String = ""  // Text before last polish

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

    private(set) var editHistory: [EditSnapshot] = []
    var previewingSnapshot: EditSnapshot? = nil  // Currently previewing (not applied)

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
    var isRecordingInstruction: Bool = false
    var isTranscribingInstruction: Bool = false
    var voiceInstruction: String?
    var audioLevel: Float = 0

    // LLM Settings (exposed for visibility/control)
    var showLLMSettings: Bool = false
    var llmTemperature: Double = 0.3
    var llmMaxTokens: Int = 2048
    var llmProviderId: String?
    var llmModelId: String?

    // Editable system prompt (the "magic" instructions for the LLM)
    var systemPrompt: String = """
        You are helping edit transcribed speech. Apply the user's instruction to transform the text.
        Return only the transformed text, nothing else. Preserve the original meaning unless asked otherwise.
        """

    // Last generation info (for transparency)
    private(set) var lastUsedProvider: String?
    private(set) var lastUsedModel: String?
    private(set) var lastPrompt: String?
    private(set) var lastTokenCount: Int?

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

    func show(dictationId: Int64) {
        NSLog("[Interstitial] show() called with dictationId: \(dictationId)")
        logger.info("=== INTERSTITIAL SHOW REQUEST ===")
        logger.info("Dictation ID: \(dictationId)")

        // If already showing, dismiss first
        if panel != nil {
            NSLog("[Interstitial] Dismissing existing panel")
            dismiss()
        }

        // Fetch dictation from DictationStore/LiveDatabase
        NSLog("[Interstitial] Refreshing DictationStore...")
        DictationStore.shared.refresh()

        NSLog("[Interstitial] DictationStore has \(DictationStore.shared.dictations.count) dictations")
        NSLog("[Interstitial] Database path: \(LiveDatabase.databaseURL.path)")

        guard let dictation = LiveDatabase.fetch(id: dictationId) else {
            NSLog("[Interstitial] ERROR: Dictation \(dictationId) not found in shared database")
            logger.error("Dictation \(dictationId) not found in shared database. Database has \(DictationStore.shared.dictations.count) dictations.")
            return
        }

        NSLog("[Interstitial] Found dictation: \"\(dictation.text.prefix(50))...\"")

        currentDictationId = dictationId
        originalText = dictation.text
        editedText = dictation.text

        // Read selection replacement context from metadata (for Command+Enter)
        originalSelectedText = dictation.metadata?["originalSelectedText"]
        sourceAppBundleID = dictation.metadata?["sourceAppBundleID"]
        if hasSelectionContext {
            let selectionCount = self.originalSelectedText?.count ?? 0
            let appID = self.sourceAppBundleID ?? "?"
            logger.info("Selection context: \(selectionCount) chars from \(appID)")
        }

        logger.info("Showing interstitial for dictation \(dictationId): \"\(dictation.text.prefix(40))...\"")

        createAndShowPanel()
        NSLog("[Interstitial] Panel created and shown")
    }

    private func createAndShowPanel() {
        let view = InterstitialEditorView(manager: self)
            .environment(SettingsManager.shared)
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
        // Don't activate the main app - just show the panel
        // NSApp.activate(ignoringOtherApps: true)

        self.panel = panel
        self.isVisible = true

        setupEventMonitors()
    }

    private func setupEventMonitors() {
        // Local monitor for keyboard shortcuts
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }

            // Escape to dismiss
            if event.keyCode == 53 {
                self.dismiss()
                return nil
            }

            // Command+Enter to replace selection and return to source app
            if event.keyCode == 36 && event.modifierFlags.contains(.command) {
                if self.hasSelectionContext {
                    self.replaceSelectionAndDismiss()
                    return nil
                }
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
        currentDictationId = nil
        editedText = ""
        originalText = ""
        prePolishText = ""
        viewState = .editing
        isPolishing = false
        polishError = nil
        voiceInstruction = nil
        originalSelectedText = nil
        sourceAppBundleID = nil
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
        let text = editedText
        logger.info("Pasting text via TalkieLive: \(text.count) chars")
        dismiss()

        // Route paste through TalkieLive (has accessibility permissions)
        ServiceManager.shared.live.pasteText(text, toAppWithBundleID: nil) { success in
            if !success {
                // Fallback: copy to clipboard so user can paste manually
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                logger.warning("TalkieLive paste failed - copied to clipboard")
            }
        }
    }

    /// Replace original selection in source app with edited text (Command+Enter)
    /// This activates the source app and pastes to replace the selection
    func replaceSelectionAndDismiss() {
        guard let bundleID = sourceAppBundleID else {
            logger.warning("replaceSelectionAndDismiss: No source app bundle ID")
            return
        }

        let text = editedText
        logger.info("Replacing selection in \(bundleID) with \(text.count) chars")
        dismiss()

        // Route paste through TalkieLive (handles app activation and paste robustly)
        ServiceManager.shared.live.pasteText(text, toAppWithBundleID: bundleID) { success in
            if !success {
                // Fallback: copy to clipboard so user can paste manually
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                logger.warning("TalkieLive paste failed - copied to clipboard")
            }
        }
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
                    try? await Task.sleep(for: .milliseconds(50)) // 50ms
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

    // MARK: - Save as Memo (Promote to Memo)

    func saveAsMemo() async {
        guard !editedText.isEmpty else { return }

        // Create a new memo from the interstitial text
        let memo = MemoModel(
            id: UUID(),
            createdAt: Date(),
            lastModified: Date(),
            title: extractTitle(from: editedText),
            duration: 0,  // No audio (or could link to dictation audio later)
            sortOrder: 0,
            transcription: editedText,
            notes: nil,
            summary: nil,
            tasks: nil,
            reminders: nil,
            audioFilePath: nil,
            waveformData: nil,
            isTranscribing: false,
            isProcessingSummary: false,
            isProcessingTasks: false,
            isProcessingReminders: false,
            autoProcessed: false,
            originDeviceId: "interstitial-\(currentDictationId ?? 0)",
            macReceivedAt: Date(),
            cloudSyncedAt: nil,
            pendingWorkflowIds: nil
        )

        do {
            let repository = LocalRepository()
            try await repository.saveMemo(memo)
            logger.info("Saved interstitial as memo: \(memo.id)")
            dismiss()

            // Activate Talkie's main window
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            polishError = "Failed to save: \(error.localizedDescription)"
            logger.error("Failed to save memo: \(error.localizedDescription)")
        }
    }

    func openInTalkie() {
        Task {
            await saveAsMemo()
        }
    }

    /// Extract a title from the first line or first few words
    private func extractTitle(from text: String) -> String {
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? text
        let words = firstLine.split(separator: " ").prefix(8).joined(separator: " ")
        if words.count > 50 {
            return String(words.prefix(47)) + "..."
        }
        return words
    }
}
