//
//  AgentHomeController.swift
//  TalkieAgent
//

import AppKit
import SwiftUI
import TalkieKit

private let agentHomeControllerLog = Log(.ui)

@MainActor
final class AgentHomeController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = AgentHomeController()

    private let appPresentationClaim = "agent-home"
    private var window: NSWindow?

    @Published var isShowingSettings = false

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
        .frame(minWidth: 1_020, minHeight: 640)

        let hostingView = NSHostingView(rootView: view)
        let homeWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        // Native title bar is the only top chrome (no custom OpsShell titlebar).
        homeWindow.title = "Talkie Agent"
        homeWindow.minSize = NSSize(width: 1_020, height: 640)
        homeWindow.contentView = hostingView
        homeWindow.isMovableByWindowBackground = false
        homeWindow.isReleasedWhenClosed = false
        homeWindow.delegate = self
        homeWindow.setFrameAutosaveName("TalkieAgent.AgentHome")
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
