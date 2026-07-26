//
//  CameraBubblePanel.swift
//  Talkie
//
//  Floating camera preview panel with shared placement and geometry preferences.
//

import AppKit
import SwiftUI
import TalkieKit

private let legacyCameraPositionKey = "cameraBubblePosition"

@MainActor
final class CameraBubblePanel {
    private var panel: NSPanel?
    private var moveObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var lastAppliedOrigin: NSPoint?

    var isVisible: Bool { panel != nil }

    private var dimensions: CGSize {
        let service = CameraCaptureService.shared
        return service.bubbleShape.dimensions(for: service.bubbleSize)
    }

    func show() {
        guard panel == nil else { return }
        migrateLegacyPositionIfNeeded()
        let size = dimensions
        let hostingView = makeHostingView()
        hostingView.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.sharingType = .none
        position(panel)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        self.panel = panel
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.saveCustomPositionIfNeeded() }
        }
        settingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(CameraBubbleSettingsBridge.settingsDidChange),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshLayout() }
        }
    }

    func refreshLayout() {
        guard let panel else { return }
        panel.contentView = makeHostingView()
        panel.setContentSize(dimensions)
        position(panel)
    }

    func dismiss() {
        guard let panel else { return }
        saveCustomPositionIfNeeded()
        removeObservers()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.panel = nil
        })
    }

    private func makeHostingView() -> NSHostingView<CameraBubbleView> {
        NSHostingView(rootView: CameraBubbleView())
    }

    private func position(_ panel: NSPanel) {
        let size = dimensions
        let placement = CameraCaptureService.shared.bubblePlacement
        let requestedOrigin = placement == .custom ? storedCustomOrigin() : nil
        let screen = screen(for: requestedOrigin, size: size)
        let origin = CameraBubbleLayout.origin(
            for: placement,
            requested: requestedOrigin,
            size: size,
            visibleFrame: screen.visibleFrame
        )
        lastAppliedOrigin = origin
        panel.setFrameOrigin(origin)
    }

    private func screen(for origin: NSPoint?, size: CGSize) -> NSScreen {
        if let origin {
            let center = NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
            if let match = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
                return match
            }
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private func storedCustomOrigin() -> NSPoint? {
        if let dict = TalkieSharedSettings.dictionary(forKey: AgentSettingsKey.cameraBubbleCustomPosition),
           let x = dict["x"] as? Double,
           let y = dict["y"] as? Double {
            return NSPoint(x: x, y: y)
        }
        if let legacy = UserDefaults.standard.dictionary(forKey: legacyCameraPositionKey),
           let x = legacy["x"] as? Double,
           let y = legacy["y"] as? Double {
            let origin = NSPoint(x: x, y: y)
            persist(origin)
            return origin
        }
        return nil
    }

    private func migrateLegacyPositionIfNeeded() {
        guard TalkieSharedSettings.object(forKey: AgentSettingsKey.cameraBubblePlacement) == nil,
              TalkieSharedSettings.object(forKey: AgentSettingsKey.cameraBubbleCustomPosition) == nil,
              let legacy = UserDefaults.standard.dictionary(forKey: legacyCameraPositionKey),
              let x = legacy["x"] as? Double,
              let y = legacy["y"] as? Double else { return }
        persist(NSPoint(x: x, y: y))
        TalkieSharedSettings.set(CameraBubblePlacement.custom.rawValue, forKey: AgentSettingsKey.cameraBubblePlacement)
    }

    private func saveCustomPositionIfNeeded() {
        guard let panel else { return }
        if let lastAppliedOrigin,
           abs(lastAppliedOrigin.x - panel.frame.origin.x) < 0.5,
           abs(lastAppliedOrigin.y - panel.frame.origin.y) < 0.5 {
            self.lastAppliedOrigin = nil
            return
        }
        persist(panel.frame.origin)
        TalkieSharedSettings.set(CameraBubblePlacement.custom.rawValue, forKey: AgentSettingsKey.cameraBubblePlacement)
        CameraBubbleSettingsBridge.notifyChanged()
    }

    private func persist(_ origin: NSPoint) {
        TalkieSharedSettings.set(
            ["x": Double(origin.x), "y": Double(origin.y)],
            forKey: AgentSettingsKey.cameraBubbleCustomPosition
        )
    }

    private func removeObservers() {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
        if let settingsObserver {
            DistributedNotificationCenter.default().removeObserver(settingsObserver)
            self.settingsObserver = nil
        }
    }
}
