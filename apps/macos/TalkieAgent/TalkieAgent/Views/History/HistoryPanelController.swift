//
//  HistoryPanelController.swift
//  TalkieAgent
//
//  Lightweight history panel for quick access to recent dictations
//

import SwiftUI
import AppKit
import TalkieKit

private let log = Log(.ui)

@MainActor
final class HistoryPanelController: ObservableObject {
    static let shared = HistoryPanelController()

    private var panel: NSPanel?
    private var localEventMonitor: Any?

    @Published var dictations: [LiveRecording] = []

    private init() {}

    // MARK: - Show/Dismiss

    func show() {
        log.info("Showing history panel")

        // If already showing, just bring to front
        if panel != nil {
            panel?.makeKeyAndOrderFront(nil)
            refresh()
            return
        }

        refresh()
        createAndShowPanel()
    }

    func refresh() {
        dictations = UnifiedDatabase.recentDictations(limit: 50)
        log.debug("Loaded \(dictations.count) dictations for history")
    }

    func dismiss() {
        log.info("Dismissing history panel")
        removeEventMonitors()
        panel?.close()
        panel = nil
    }

    // MARK: - Actions

    func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        SoundManager.shared.playPasted()
        log.info("Copied dictation to clipboard")
    }

    func openInTalkie() {
        let scheme = TalkieEnvironment.current.talkieURLScheme
        guard let url = URL(string: "\(scheme)://agent/recent") else { return }
        TalkieAppOpener.open(url)
        dismiss()
    }

    // MARK: - Panel Creation

    private func createAndShowPanel() {
        let view = HistoryPanelView(
            controller: self,
            onDismiss: { [weak self] in self?.dismiss() }
        )

        let hostingView = NSHostingView(rootView: view)

        let width: CGFloat = 480
        let height: CGFloat = 520
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.minSize = NSSize(width: 380, height: 400)
        panel.maxSize = NSSize(width: 700, height: 800)
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

        // Center on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - width / 2
            let y = screenFrame.midY - height / 2 + 40
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
        setupEventMonitors()
    }

    private func setupEventMonitors() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }

            // Escape to dismiss
            if event.keyCode == 53 {
                self.dismiss()
                return nil
            }

            return event
        }
    }

    private func removeEventMonitors() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
}
