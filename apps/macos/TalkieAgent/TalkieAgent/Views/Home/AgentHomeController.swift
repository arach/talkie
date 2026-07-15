//
//  AgentHomeController.swift
//  TalkieAgent
//

import AppKit
import SwiftUI
import TalkieKit

private let agentHomeControllerLog = Log(.ui)

/// Deep-link targets that external entry points (the status-bar menu, XPC)
/// can navigate Agent Home into. `AgentHomeShellView` maps these onto its
/// private section enum — keeping the section model file-local while still
/// allowing "open the Logs tab" from outside the shell.
enum AgentHomeRoute: String, Sendable {
    case home
    case history
    case libraryCaptures
    case conversations
    case permissions
    case logs
}

@MainActor
final class AgentHomeController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = AgentHomeController()

    private let appPresentationClaim = "agent-home"
    private var window: NSWindow?

    @Published var isShowingSettings = false

    /// Set by `show(section:)`; the shell observes this, applies it to its
    /// selection, then clears it back to nil.
    @Published var pendingSection: AgentHomeRoute?

    var isVisible: Bool {
        window?.isVisible == true
    }

    private override init() {}

    func show() {
        show(openingSettings: false)
    }

    func showSettings() {
        show(openingSettings: true)
    }

    /// Open Agent Home and deep-link to a specific primary tab (e.g. the
    /// status-bar menu's "Permissions" / "Logs" entries).
    func show(section: AgentHomeRoute) {
        pendingSection = section
        show(openingSettings: false)
    }

    private func show(openingSettings: Bool) {
        agentHomeControllerLog.info("Showing Agent Home")
        AgentAppPresentationController.shared.retainRegularPresentation(for: appPresentationClaim)
        isShowingSettings = openingSettings

        if let window {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = AgentHomeShellView(
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )
        .frame(minWidth: 680, minHeight: 500)

        let hostingView = NSHostingView(rootView: view)
        let homeWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 1160),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Keep native window controls, but let the centered in-content pill
        // carry product identity instead of duplicating a left-aligned title.
        homeWindow.title = "Talkie Agent"
        homeWindow.titleVisibility = .hidden
        homeWindow.titlebarAppearsTransparent = true
        homeWindow.toolbarStyle = .unifiedCompact
        homeWindow.backgroundColor = .clear
        homeWindow.isOpaque = false
        homeWindow.minSize = NSSize(width: 680, height: 500)
        homeWindow.contentView = hostingView
        homeWindow.isMovableByWindowBackground = false
        homeWindow.isReleasedWhenClosed = false
        homeWindow.delegate = self
        // Versioned autosave key: the previous key restored a stale, undersized
        // frame (smaller than minSize), which clipped the settings layout. Bumping
        // the key discards old saved frames so the window opens at its real default.
        homeWindow.setFrameAutosaveName("TalkieAgent.AgentHome.command-center.v5")
        homeWindow.center()
        homeWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = homeWindow
    }

    func dismiss() {
        agentHomeControllerLog.info("Dismissing Agent Home")
        isShowingSettings = false
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === window else { return }

        // Keep the app presentation claim so Dock reopen can bring Agent Home back.
        isShowingSettings = false
        window = nil
    }
}
