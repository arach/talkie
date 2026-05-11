//
//  CameraBubblePanel.swift
//  Talkie
//
//  Floating NSPanel hosting the circular camera preview bubble.
//  Always-on-top, draggable, invisible to ScreenCaptureKit.
//  Follows ChordHUDPanel.swift pattern.
//

import AppKit
import SwiftUI

private let kPositionKey = "cameraBubblePosition"

@MainActor
final class CameraBubblePanel {

    private var panel: NSPanel?
    private var moveObserver: NSObjectProtocol?

    var isVisible: Bool { panel != nil }

    /// Current bubble size from settings
    private var bubbleSize: CGFloat { CameraCaptureService.shared.bubbleSize.points }

    // MARK: - Show

    func show() {
        guard panel == nil else { return }

        let size = bubbleSize

        let hostingView = NSHostingView(rootView: CameraBubbleView())
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
        p.sharingType = .none  // Don't capture ourselves

        positionPanel(p)

        p.alphaValue = 0
        p.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
        }

        self.panel = p

        // Track drag to persist position
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: p,
            queue: .main
        ) { [weak self] _ in
            self?.savePosition()
        }
    }

    // MARK: - Dismiss

    func dismiss() {
        guard let p = panel else { return }
        savePosition()

        if let observer = moveObserver {
            NotificationCenter.default.removeObserver(observer)
            moveObserver = nil
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            p.orderOut(nil)
            self?.panel = nil
        })
    }

    // MARK: - Positioning

    private func positionPanel(_ p: NSPanel) {
        // Restore last drag position, or default to bottom-right
        if let dict = UserDefaults.standard.dictionary(forKey: kPositionKey),
           let x = dict["x"] as? CGFloat,
           let y = dict["y"] as? CGFloat {
            p.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            let screen = NSScreen.main ?? NSScreen.screens[0]
            let x = screen.visibleFrame.maxX - bubbleSize - 24
            let y = screen.visibleFrame.minY + 80
            p.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    private func savePosition() {
        guard let p = panel else { return }
        let origin = p.frame.origin
        UserDefaults.standard.set(["x": origin.x, "y": origin.y], forKey: kPositionKey)
    }
}
