//
//  InterstitialPanelController.swift
//  TalkieAgent
//
//  Manages the floating interstitial editor panel for quick text editing and LLM polish
//  Triggered directly from AgentController (no URL scheme needed)
//

import SwiftUI
import AppKit
import TalkieKit

private let log = Log(.ui)

@MainActor
public final class InterstitialPanelController: ObservableObject {
    public static let shared = InterstitialPanelController()

    private var panel: NSPanel?
    private var localEventMonitor: Any?

    /// Shared state for the interstitial editor
    let state = InterstitialState()

    /// Voice command capture (for LLM instructions like "make this professional")
    let voiceCommand = InterstitialVoiceCommand()

    /// Dictation capture (for verbatim text input)
    let dictation = InterstitialVoiceCommand()  // Same class, different usage

    /// Parent note ID for segment tracking (created on first dictation segment)
    private var parentNoteId: UUID?

    /// Running count of segments in the current session
    private var segmentCount: Int = 0

    private init() {}

    // MARK: - Show/Dismiss

    /// Show interstitial editor for a dictation
    /// - Parameters:
    ///   - dictationId: The dictation record to load
    ///   - contextPrompt: Optional LLM prompt from a context rule (auto-triggers polish)
    ///   - contextRuleName: Optional name of the context rule that triggered this
    public func show(dictationId: UUID, contextPrompt: String? = nil, contextRuleName: String? = nil) {
        log.info("Showing interstitial for dictation \(dictationId.uuidString.prefix(8))")

        // If already showing, dismiss first
        if panel != nil {
            dismiss()
        }

        // Fetch dictation from UnifiedDatabase
        guard let dictation = UnifiedDatabase.fetch(id: dictationId) else {
            log.error("Dictation \(dictationId.uuidString.prefix(8)) not found in database")
            return
        }

        // Build metadata dictionary from parsedMetadata for state.load
        let parsed = dictation.parsedMetadata
        var metadata: [String: String] = [:]
        if let bundleId = parsed.app?.bundleId {
            metadata["sourceAppBundleID"] = bundleId
        }
        // Pass through context rule prompt if provided
        if let contextPrompt {
            metadata["contextPrompt"] = contextPrompt
        }
        if let contextRuleName {
            metadata["contextRuleName"] = contextRuleName
        }

        // Load state
        state.load(
            dictationId: dictationId,
            text: dictation.text,
            metadata: metadata.isEmpty ? nil : metadata
        )
        state.isVisible = true

        createAndShowPanel()
        log.info("Interstitial panel created for dictation \(dictationId.uuidString.prefix(8))")

        // Auto-trigger polish if a context rule prompt is present
        if let prompt = state.contextPrompt, !prompt.isEmpty {
            let ruleName = state.contextRuleName ?? "Context Rule"
            log.info("Auto-applying context prompt from rule: \(ruleName)")
            Task { @MainActor in
                // Brief delay for panel animation to complete
                try? await Task.sleep(for: .milliseconds(300))
                await state.polishText(instruction: prompt)
            }
        }
    }

    /// Show interstitial editor with empty text - quick path to scratchpad mode
    /// Called when Shift+hover on the pill in idle state
    public func showEmpty() {
        log.info("Showing empty interstitial (scratchpad mode)")

        // If already showing, just bring to front
        if panel != nil {
            log.debug("Panel already exists, bringing to front")
            panel?.makeKeyAndOrderFront(nil)
            return
        }

        // Reset and prepare empty state
        state.reset()
        state.isVisible = true
        state.editedText = ""
        state.originalText = ""

        createAndShowPanel()
        log.info("Empty interstitial panel created")
    }

    private func createAndShowPanel() {
        let view = InterstitialPanelView(
            state: state,
            onDismiss: { [weak self] in self?.dismiss() },
            onCopy: { [weak self] in self?.copyAndDismiss() },
            onReplaceSelection: { [weak self] in self?.replaceSelectionAndDismiss() }
        )

        let hostingView = NSHostingView(rootView: view)

        let width: CGFloat = 580
        let height: CGFloat = 420
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

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

        self.panel = panel
        setupEventMonitors()
    }

    private func setupEventMonitors() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }

            // Escape to dismiss (with confirmation if content exists)
            if event.keyCode == 53 {
                self.requestDismiss()
                return nil
            }

            // Command+Enter to replace selection and return to source app
            if event.keyCode == 36 && event.modifierFlags.contains(.command) {
                if self.state.hasSelectionContext {
                    self.replaceSelectionAndDismiss()
                    return nil
                }
            }

            return event
        }
    }

    /// Request dismiss - shows confirmation if there's content
    public func requestDismiss() {
        let text = state.editedText.trimmingCharacters(in: .whitespacesAndNewlines)

        // If empty, just dismiss
        if text.isEmpty {
            dismiss()
            return
        }

        // Check user preference for dismiss confirmation
        let askOnDismiss = TalkieSharedSettings.bool(forKey: AgentSettingsKey.askOnInterstitialDismiss)
        if !askOnDismiss {
            dismiss()
            return
        }

        // Show confirmation dialog
        state.showDismissConfirmation = true
    }

    public func dismiss() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }

        panel?.orderOut(nil)
        panel = nil
        state.reset()
        parentNoteId = nil
        segmentCount = 0

        log.info("Interstitial dismissed")
    }

    /// Disable future dismiss confirmations
    public func dontAskAgainAndDismiss() {
        TalkieSharedSettings.set(false, forKey: AgentSettingsKey.askOnInterstitialDismiss)
        log.info("User disabled interstitial dismiss confirmation")
        dismiss()
    }

    // MARK: - Actions

    public func copyAndDismiss() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(state.editedText, forType: .string)
        log.info("Copied to clipboard: \(state.editedText.count) chars")
        dismiss()
    }

    public func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(state.editedText, forType: .string)
        log.info("Copied to clipboard: \(state.editedText.count) chars")
    }

    public func replaceSelectionAndDismiss() {
        guard let bundleID = state.sourceAppBundleID else {
            log.warning("replaceSelectionAndDismiss: No source app bundle ID")
            return
        }

        // Verify source app is still running
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first != nil else {
            log.warning("Source app no longer running: \(bundleID) - copying to clipboard")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(state.editedText, forType: .string)
            dismiss()
            return
        }

        let text = state.editedText
        log.info("Replacing selection in \(bundleID): \(text.count) chars")
        dismiss()

        // Paste via TalkieAgent's TextInserter
        Task {
            let success = await TextInserter.shared.insert(text, intoAppWithBundleID: bundleID)
            if !success {
                // Fallback: copy to clipboard
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                log.warning("TextInserter failed - copied to clipboard")
            }
        }
    }

    // MARK: - Bounce to Notes

    /// Send text to Talkie's Notes screen and dismiss
    public func bounceToCompose() {
        let text = state.editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Copy to pasteboard as backup
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        // Send to Talkie via URL scheme
        TalkieNotifier.shared.sendURL("compose", params: ["text": text])

        // Activate Talkie main app
        let talkieBundleIDs = ["jdi.talkie.core", "jdi.talkie.core.dev"]
        if let talkieApp = NSWorkspace.shared.runningApplications.first(where: { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return talkieBundleIDs.contains(bundleID)
        }) {
            talkieApp.activate()
        }

        log.info("Bounced \(text.count) chars to Talkie Notes")
        dismiss()
    }

    // MARK: - Voice Command (LLM instructions)

    public func startVoiceCommand() {
        guard !state.isRecordingCommand else { return }

        do {
            try voiceCommand.startCapture()
            state.isRecordingCommand = true
            state.voiceCommand = nil
            log.info("Started voice command capture")

            // Monitor audio level
            Task {
                while state.isRecordingCommand {
                    state.commandAudioLevel = voiceCommand.audioLevel
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        } catch {
            state.polishError = error.localizedDescription
            log.error("Failed to start voice command", error: error)
        }
    }

    public func stopVoiceCommand() async {
        guard state.isRecordingCommand else { return }

        state.isRecordingCommand = false
        state.isTranscribingCommand = true
        state.commandAudioLevel = 0

        do {
            let command = try await voiceCommand.stopAndTranscribe()
            state.isTranscribingCommand = false

            if !command.isEmpty {
                state.voiceCommand = command
                log.info("Voice command: \(command)")

                // Auto-trigger polish with the voice command
                await state.polishText(instruction: command)
            }
        } catch {
            state.isTranscribingCommand = false
            state.polishError = error.localizedDescription
            log.error("Voice command failed", error: error)
        }
    }

    public func cancelVoiceCommand() {
        voiceCommand.cancel()
        state.isRecordingCommand = false
        state.isTranscribingCommand = false
        state.commandAudioLevel = 0
    }

    // MARK: - Dictation (verbatim text input)

    public func startDictation() {
        guard !state.isRecordingDictation else { return }

        do {
            try dictation.startCapture()
            state.isRecordingDictation = true
            log.info("Started dictation capture")

            // Monitor audio level
            Task {
                while state.isRecordingDictation {
                    state.dictationAudioLevel = dictation.audioLevel
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        } catch {
            state.polishError = error.localizedDescription
            log.error("Failed to start dictation", error: error)
        }
    }

    public func stopDictation() async {
        guard state.isRecordingDictation else { return }

        state.isRecordingDictation = false
        state.isTranscribingDictation = true
        state.dictationAudioLevel = 0

        do {
            let result = try await dictation.stopAndTranscribePersistent()
            state.isTranscribingDictation = false

            if !result.text.isEmpty {
                // Ensure parentId exists (create note recording on first segment)
                if parentNoteId == nil {
                    let noteId = UUID()
                    let noteRecording = LiveRecording(
                        text: "",
                        duration: 0,
                        transcriptionStatus: "success"
                    )
                    var note = noteRecording
                    note.type = "note"
                    note.source = "mac"
                    note.sourceDeviceId = nil
                    UnifiedDatabase.store(note)
                    // Use the note's generated ID as parent
                    parentNoteId = note.id
                    segmentCount = 0
                    log.info("Created parent note: \(note.id.uuidString.prefix(8))")
                }

                guard let noteId = parentNoteId else { return }

                // Copy audio to persistent storage
                let segmentId = UUID()
                let audioFilename = "\(segmentId.uuidString).m4a"
                let destURL = AudioStorage.audioDirectory.appendingPathComponent(audioFilename)
                do {
                    try FileManager.default.moveItem(at: result.audioURL, to: destURL)
                } catch {
                    // Fallback to copy if move fails (cross-filesystem)
                    try? FileManager.default.copyItem(at: result.audioURL, to: destURL)
                    try? FileManager.default.removeItem(at: result.audioURL)
                }

                // Store segment in database
                UnifiedDatabase.storeSegment(
                    text: result.text,
                    duration: 0,  // Duration not tracked for ephemeral captures
                    audioFilename: audioFilename,
                    transcriptionModel: LiveSettings.shared.selectedModelId,
                    parentId: noteId,
                    segmentIndex: segmentCount
                )
                segmentCount += 1

                // Append transcribed text to the editor (existing behavior)
                if state.editedText.isEmpty {
                    state.editedText = result.text
                } else if state.editedText.hasSuffix(" ") || state.editedText.hasSuffix("\n") {
                    state.editedText += result.text
                } else {
                    state.editedText += " " + result.text
                }
                log.info("Dictation segment saved: \(result.text.count) chars, segment \(segmentCount - 1)")
            }
        } catch {
            state.isTranscribingDictation = false
            state.polishError = error.localizedDescription
            log.error("Dictation failed", error: error)
        }
    }

    public func cancelDictation() {
        dictation.cancel()
        state.isRecordingDictation = false
        state.isTranscribingDictation = false
        state.dictationAudioLevel = 0
    }
}
