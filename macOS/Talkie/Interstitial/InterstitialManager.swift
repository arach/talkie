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

    private init() {}

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

        // Fetch utterance from LiveDataStore
        NSLog("[Interstitial] Refreshing LiveDataStore...")
        LiveDataStore.shared.refresh()

        NSLog("[Interstitial] LiveDataStore has \(LiveDataStore.shared.utterances.count) utterances")
        NSLog("[Interstitial] Database path: \(LiveDataStore.shared.databasePath)")

        guard let utterance = LiveDataStore.shared.utterance(id: utteranceId) else {
            NSLog("[Interstitial] ERROR: Utterance \(utteranceId) not found in shared database")
            logger.error("Utterance \(utteranceId) not found in shared database. Database has \(LiveDataStore.shared.utterances.count) utterances.")
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

        let width: CGFloat = 520
        let height: CGFloat = 360
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled, .closable],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hostingView
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

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
        isPolishing = false
        polishError = nil

        logger.info("Interstitial dismissed")
    }

    // MARK: - Actions

    func copyAndDismiss() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(editedText, forType: .string)
        logger.info("Copied to clipboard: \(self.editedText.count) chars")
        dismiss()
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

    // MARK: - LLM Polish

    func polishText() async {
        guard !isPolishing else { return }

        isPolishing = true
        polishError = nil

        logger.info("Polishing text...")

        do {
            let registry = LLMProviderRegistry.shared

            // Try to get a provider
            guard let resolved = await registry.resolveProviderAndModel() else {
                polishError = "No LLM provider configured"
                isPolishing = false
                logger.warning("No LLM provider available")
                return
            }

            let prompt = """
            Improve this transcribed speech. Fix grammar, remove filler words (um, uh, like), \
            and make it clearer while preserving the original meaning and tone. \
            Return only the improved text, nothing else.

            Text to improve:
            \(editedText)
            """

            let options = GenerationOptions(
                temperature: 0.3,
                maxTokens: 2048
            )

            let polished = try await resolved.provider.generate(
                prompt: prompt,
                model: resolved.modelId,
                options: options
            )

            editedText = polished.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.info("Polish complete: \(self.editedText.count) chars")

        } catch {
            polishError = error.localizedDescription
            logger.error("Polish failed: \(error.localizedDescription)")
        }

        isPolishing = false
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
