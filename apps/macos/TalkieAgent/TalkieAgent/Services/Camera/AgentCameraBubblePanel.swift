//
//  AgentCameraBubblePanel.swift
//  TalkieAgent
//
//  Capturable floating panel for the screen-recording camera bubble.
//

import AppKit
import SwiftUI

private let agentCameraPositionKey = "agentCameraBubblePosition"

@MainActor
final class AgentCameraBubblePanel {
    private var panel: NSPanel?
    private var moveObserver: NSObjectProtocol?

    var isVisible: Bool { panel != nil }

    private var bubbleSize: CGFloat { AgentCameraCaptureService.shared.bubbleSize }

    func show() {
        guard panel == nil else { return }

        let size = bubbleSize
        let hostingView = NSHostingView(rootView: AgentCameraBubbleView())
        hostingView.frame = NSRect(x: 0, y: 0, width: size, height: size)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentView = hostingView
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.sharingType = .readOnly

        positionPanel(p)

        p.alphaValue = 0
        p.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
        }

        panel = p
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: p,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.savePosition()
            }
        }
    }

    func dismiss() {
        guard let panel else { return }
        savePosition()

        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }

        panel.orderOut(nil)
        self.panel = nil
    }

    private func positionPanel(_ panel: NSPanel) {
        if let dict = UserDefaults.standard.dictionary(forKey: agentCameraPositionKey),
           let x = dict["x"] as? CGFloat,
           let y = dict["y"] as? CGFloat {
            panel.setFrameOrigin(NSPoint(x: x, y: y))
            return
        }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let x = screen.visibleFrame.maxX - bubbleSize - 24
        let y = screen.visibleFrame.minY + 80
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func savePosition() {
        guard let panel else { return }
        let origin = panel.frame.origin
        UserDefaults.standard.set(["x": origin.x, "y": origin.y], forKey: agentCameraPositionKey)
    }
}
