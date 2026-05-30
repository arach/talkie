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

    var isVisible: Bool {
        window?.isVisible == true
    }

    private override init() {}

    func show() {
        agentHomeControllerLog.info("Showing Agent Home")
        AgentAppPresentationController.shared.retainRegularPresentation(for: appPresentationClaim)

        if let window {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = AgentHomeView(
            onDismiss: { [weak self] in
                self?.dismiss()
            },
            onOpenSettings: {
                NotificationCenter.default.post(name: .showSettingsFromXPC, object: nil)
            }
        )
        .frame(minWidth: 860, minHeight: 580)

        let hostingView = NSHostingView(rootView: view)
        let homeWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        homeWindow.title = "Talkie Agent"
        homeWindow.minSize = NSSize(width: 780, height: 520)
        homeWindow.contentView = hostingView
        homeWindow.titlebarAppearsTransparent = true
        homeWindow.titleVisibility = .hidden
        homeWindow.isMovableByWindowBackground = true
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
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === window else { return }

        // Keep the app presentation claim so Dock reopen can bring Agent Home back.
        window = nil
    }
}
