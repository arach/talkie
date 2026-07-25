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

    func prewarm() {
        guard window == nil else { return }

        let start = CFAbsoluteTimeGetCurrent()
        _ = prepareWindow()
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        agentHomeControllerLog.info(
            "Agent Home prewarmed",
            detail: "durationMs=\(elapsedMs)"
        )
    }

    func show() {
        let start = CFAbsoluteTimeGetCurrent()
        let wasPrewarmed = window != nil

        agentHomeControllerLog.info("Showing Agent Home")
        AgentAppPresentationController.shared.retainRegularPresentation(for: appPresentationClaim)

        let homeWindow = prepareWindow()
        if homeWindow.isMiniaturized {
            homeWindow.deminiaturize(nil)
        }
        homeWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        agentHomeControllerLog.info(
            "Agent Home visible",
            detail: "prewarmed=\(wasPrewarmed) durationMs=\(elapsedMs)"
        )
    }

    private func prepareWindow() -> NSWindow {
        if let window { return window }

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

        window = homeWindow
        return homeWindow
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
