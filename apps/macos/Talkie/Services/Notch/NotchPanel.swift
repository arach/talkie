//
//  NotchPanel.swift
//  Talkie
//
//  NSPanel management for the notch overlay.
//  Matches Agent's NotchOverlayController panel setup exactly.
//

import AppKit
import SwiftUI
import TalkieKit

private let log = Log(.ui)

/// NSHostingView that passes through clicks on transparent areas.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    var interactiveRectProvider: (() -> NSRect)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let interactiveRectProvider, !interactiveRectProvider().contains(point) {
            return nil
        }
        // Panel-level mouse passthrough already rejects hits outside the measured
        // interactive rect. Inside that rect, let SwiftUI resolve the event normally.
        return super.hitTest(point)
    }
}

/// NSPanel subclass that can become key — required for SwiftUI .onDrag and
/// AppKit beginDraggingSession to work in a nonactivatingPanel.
/// Without this, drag gestures are silently swallowed.
private final class DragCapablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private enum NotchMonitorEventSource {
    case local
    case global
}

private struct NotchPanelPerfAccumulator {
    private struct Sample {
        let durationMs: Double
    }

    private let windowSeconds: Double = 5
    private let maxSamples = 768
    private var windowStart: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private var localEvents = 0
    private var globalEvents = 0
    private var throttledLocalEvents = 0
    private var throttledGlobalEvents = 0
    private var updates = 0
    private var wakeups = 0
    private var screenChecks = 0
    private var screenMoves = 0
    private var samples: [Sample] = []

    mutating func recordEvent(source: NotchMonitorEventSource, throttled: Bool) {
        switch (source, throttled) {
        case (.local, false):
            localEvents += 1
        case (.local, true):
            throttledLocalEvents += 1
        case (.global, false):
            globalEvents += 1
        case (.global, true):
            throttledGlobalEvents += 1
        }
    }

    mutating func recordUpdate(
        durationMs: Double,
        wokePanel: Bool,
        didScreenCheck: Bool,
        didMoveScreen: Bool
    ) {
        updates += 1
        if wokePanel { wakeups += 1 }
        if didScreenCheck { screenChecks += 1 }
        if didMoveScreen { screenMoves += 1 }
        if samples.count < maxSamples {
            samples.append(Sample(durationMs: durationMs))
        }
    }

    mutating func flushIfNeeded(log: Log, force: Bool = false) {
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - windowStart
        guard force || elapsed >= windowSeconds else { return }

        let durations = samples.map(\.durationMs)
        let avgMs: Double
        if durations.isEmpty {
            avgMs = 0
        } else {
            avgMs = durations.reduce(0, +) / Double(durations.count)
        }
        let p95Ms = percentile(durations, p: 0.95) ?? 0
        let maxMs = durations.max() ?? 0
        let eventsPerSecond = elapsed > 0 ? Double(localEvents + globalEvents) / elapsed : 0

        log.info(
            "NotchPerf window=\(fmt(elapsed))s updates=\(updates) " +
            "events(local=\(localEvents),global=\(globalEvents),eps=\(fmt(eventsPerSecond))) " +
            "throttled(local=\(throttledLocalEvents),global=\(throttledGlobalEvents)) " +
            "updateMs(avg=\(fmt(avgMs)),p95=\(fmt(p95Ms)),max=\(fmt(maxMs))) " +
            "wakeups=\(wakeups) screenChecks=\(screenChecks) screenMoves=\(screenMoves)"
        )

        windowStart = now
        localEvents = 0
        globalEvents = 0
        throttledLocalEvents = 0
        throttledGlobalEvents = 0
        updates = 0
        wakeups = 0
        screenChecks = 0
        screenMoves = 0
        samples.removeAll(keepingCapacity: true)
    }

    private func percentile(_ values: [Double], p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * p).rounded(.toNearestOrAwayFromZero))
        return sorted[min(max(index, 0), sorted.count - 1)]
    }

    private func fmt(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }
}

@MainActor
final class NotchPanel {
    private var panel: NSPanel?
    private let notchInfo: NotchInfo
    private let composer: NotchComposer
    private var isHideAnimating = false
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var lastGlobalMouseUpdate: CFAbsoluteTime = 0
    private var lastLocalMouseUpdate: CFAbsoluteTime = 0
    private var lastScreenCheck: CFAbsoluteTime = 0
    private var pendingMousePassthroughUpdate = false
    private let notchPerfLoggingEnabled: Bool = {
        let env = ProcessInfo.processInfo.environment["CAPTURE_PERF"]
        if env == "0" { return false }
        if env == "1" { return true }
        return UserDefaults.standard.bool(forKey: "capturePerfEnabled")
    }()
    private var perfAccumulator = NotchPanelPerfAccumulator()

    // Panel height: notch area + room for pills below
    // Extra room for pills below notch + tray drawer expansion during recording
    private var panelHeight: CGFloat {
        notchInfo.notchHeight + 180
    }

    // Width budget to avoid clipping when notch wings are tuned wider.
    private var panelWidth: CGFloat {
        let maxSupportedPokeOut: CGFloat = 140
        let tunedNotchWidth = max(notchInfo.notchWidth - 4, 172)
        let desired = tunedNotchWidth + (maxSupportedPokeOut * 2) + 24
        return min(notchInfo.screenFrame.width, max(300, desired))
    }

    init(notchInfo: NotchInfo, composer: NotchComposer, startHidden: Bool = false) {
        self.notchInfo = notchInfo
        self.composer = composer
        if !startHidden {
            show()
        } else {
            // Create panel but keep it hidden — will show on first active intent
            createPanel(visible: false)
        }
    }

    // MARK: - Show / Hide

    func show() {
        guard panel == nil && !isHideAnimating else {
            panel?.orderFront(nil)
            return
        }
        createPanel(visible: true)
    }

    private func createPanel(visible: Bool) {
        guard panel == nil else { return }

        let composerView = NotchComposerView(composer: composer, notchInfo: notchInfo)
        let hostingView = ClickThroughHostingView(rootView: composerView)

        // Width adapts to tuned wing expansion, height = notch + room for pills.
        let size = NSSize(width: panelWidth, height: panelHeight)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.interactiveRectProvider = { [weak self] in
            self?.interactiveContentRect(in: size) ?? .zero
        }

        let p = DragCapablePanel(
            contentRect: hostingView.frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        p.contentView = hostingView
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isMovableByWindowBackground = false
        p.hasShadow = false
        p.ignoresMouseEvents = false
        p.sharingType = .readOnly

        // Position at notch — centered, flush with screen top
        let x = notchInfo.screenCenter - size.width / 2
        let y = notchInfo.screenFrame.maxY - size.height
        p.setFrameOrigin(NSPoint(x: x, y: y))

        if visible {
            p.alphaValue = 0
            p.orderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                p.animator().alphaValue = 1
            }
        } else {
            p.alphaValue = 0
            // Panel exists but is not ordered front — ready for showIfNeeded()
        }

        self.panel = p
        installMousePassthroughMonitoring()
        updateMousePassthrough()
        log.debug("NotchPanel: created at (\(Int(x)), \(Int(y))) size \(Int(size.width))×\(Int(size.height)) visible=\(visible)")
    }

    func showIfNeeded() {
        if panel == nil {
            show()
            return
        }
        guard let p = panel, !p.isVisible else { return }
        p.alphaValue = 0
        p.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
        }
        updateMousePassthrough()
    }

    func hideIfNeeded() {
        guard let p = panel, p.isVisible else { return }
        guard !isHideAnimating else { return }
        isHideAnimating = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel?.ignoresMouseEvents = true
            self?.isHideAnimating = false
        })
    }

    func captureOverlaySnapshot(metadataLines: [String] = []) {
        guard let panel else { return }
        capturePanelToClipboard(panel, metadataLines: metadataLines)
    }

    /// Reposition the panel for a new screen (tears down and recreates).
    func moveToScreen(_ newInfo: NotchInfo) {
        let wasVisible = panel?.isVisible ?? false
        panel?.orderOut(nil)
        panel = nil
        isHideAnimating = false

        // Recreate with updated notchInfo
        let composerView = NotchComposerView(composer: composer, notchInfo: newInfo)
        let hostingView = ClickThroughHostingView(rootView: composerView)

        let tunedNotchWidth = max(newInfo.notchWidth - 4, 172)
        let maxSupportedPokeOut: CGFloat = 140
        let desired = tunedNotchWidth + (maxSupportedPokeOut * 2) + 24
        let pw = min(newInfo.screenFrame.width, max(300, desired))
        let ph = newInfo.notchHeight + 180

        let size = NSSize(width: pw, height: ph)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.interactiveRectProvider = { [weak self] in
            self?.interactiveContentRect(in: size) ?? .zero
        }

        let p = DragCapablePanel(
            contentRect: hostingView.frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        p.contentView = hostingView
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isMovableByWindowBackground = false
        p.hasShadow = false
        p.ignoresMouseEvents = false
        p.sharingType = .readOnly

        let x = newInfo.screenCenter - size.width / 2
        let y = newInfo.screenFrame.maxY - size.height
        p.setFrameOrigin(NSPoint(x: x, y: y))

        if wasVisible {
            p.alphaValue = 1
            p.orderFront(nil)
        } else {
            p.alphaValue = 0
        }

        self.panel = p
        installMousePassthroughMonitoring()
        updateMousePassthrough()
        log.debug("NotchPanel: moved to screen at (\(Int(x)), \(Int(y))) size \(Int(size.width))×\(Int(size.height))")
    }

    private func interactiveContentRect(in panelSize: NSSize) -> NSRect {
        let measured = composer.interactiveContentSize
        let ns = NotchSettings.shared
        let atRest = composer.isAtRest
        let isVirtual = notchInfo.isVirtual

        // At rest on external/virtual: use per-monitor hover zone config.
        // At rest on laptop: always use full notch width (hardware landmark).
        // When expanded (any display): use measured SwiftUI content size.
        let width: CGFloat
        let height: CGFloat
        let padX: CGFloat
        let padY: CGFloat
        if atRest && isVirtual {
            let config = ns.hoverZoneConfig(for: notchInfo.displayID)
            width = min(panelSize.width, CGFloat(config.width))
            height = min(panelSize.height, CGFloat(config.height))
            padX = CGFloat(config.paddingX)
            padY = CGFloat(config.paddingY)
        } else {
            let fallbackHeight = max(8, notchInfo.notchHeight + 12)
            let fallbackWidth = max(180, max(notchInfo.notchWidth - 4, 172))
            width = min(panelSize.width, max(1, measured.width > 0 ? measured.width : fallbackWidth))
            height = min(panelSize.height, max(1, measured.height > 0 ? measured.height : fallbackHeight))
            padX = 18
            padY = 14
        }

        let originX = (panelSize.width - width) / 2
        let originY = panelSize.height - height
        let baseRect = NSRect(x: originX, y: originY, width: width, height: height)
        let expandedRect = baseRect.insetBy(dx: -padX, dy: -padY)
        return expandedRect.intersection(NSRect(origin: .zero, size: panelSize))
    }

    private func installMousePassthroughMonitoring() {
        guard localMouseMonitor == nil, globalMouseMonitor == nil else { return }

        let localMask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged
        ]

        // Global monitor includes .mouseMoved so we can detect hover zone entry
        // from any app. Throttled to avoid performance impact.
        let globalMask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged
        ]

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: localMask) { [weak self] event in
            self?.handleMonitorEvent(source: .local, type: event.type)
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: globalMask) { [weak self] event in
            guard let self else { return }
            DispatchQueue.main.async { [weak self] in
                self?.handleMonitorEvent(source: .global, type: event.type)
            }
        }
    }

    /// Whether the panel is currently hidden (at rest). Used to pick throttle interval.
    private var panelIsHidden: Bool {
        guard let panel else { return true }
        return !panel.isVisible || panel.alphaValue < 0.01
    }

    private func handleMonitorEvent(source: NotchMonitorEventSource, type: NSEvent.EventType) {
        let now = CFAbsoluteTimeGetCurrent()
        // Aggressive throttle when panel is hidden — hover zone detection doesn't need 60fps.
        // 200ms hidden, 16ms visible (matching display refresh).
        let throttleInterval: CFAbsoluteTime = panelIsHidden ? 0.050 : 0.016
        if type == .mouseMoved {
            switch source {
            case .local:
                if now - lastLocalMouseUpdate <= throttleInterval {
                    if notchPerfLoggingEnabled {
                        perfAccumulator.recordEvent(source: source, throttled: true)
                        perfAccumulator.flushIfNeeded(log: log)
                    }
                    return
                }
                lastLocalMouseUpdate = now
            case .global:
                if now - lastGlobalMouseUpdate <= throttleInterval {
                    if notchPerfLoggingEnabled {
                        perfAccumulator.recordEvent(source: source, throttled: true)
                        perfAccumulator.flushIfNeeded(log: log)
                    }
                    return
                }
                lastGlobalMouseUpdate = now
            }
        }

        if notchPerfLoggingEnabled {
            perfAccumulator.recordEvent(source: source, throttled: false)
        }
        scheduleMousePassthroughUpdate()
    }

    private func scheduleMousePassthroughUpdate() {
        guard !pendingMousePassthroughUpdate else { return }
        pendingMousePassthroughUpdate = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingMousePassthroughUpdate = false
            self.updateMousePassthrough()
        }
    }

    private func updateMousePassthrough() {
        let startedAt = CFAbsoluteTimeGetCurrent()
        var didScreenCheck = false
        var didMoveScreen = false
        var wokePanel = false

        // Follow cursor across screens — throttled to avoid constant panel recreation
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastScreenCheck > 0.3 {
            lastScreenCheck = now
            didScreenCheck = true
            didMoveScreen = composer.moveToActiveScreenIfNeeded()
        }

        guard let panel else { return }

        // Even when the panel is hidden (at rest), check the hover zone.
        // If the mouse enters the zone, show the panel so hover interaction works.
        let mouseLocation = NSEvent.mouseLocation
        let mouseInPanel = NSPoint(
            x: mouseLocation.x - panel.frame.minX,
            y: mouseLocation.y - panel.frame.minY
        )
        let interactiveRect = interactiveContentRect(in: panel.frame.size)

        let shouldCaptureMouse = interactiveRect.contains(mouseInPanel)

        if !panel.isVisible || panel.alphaValue < 0.01 {
            // Panel is hidden (at rest). If mouse enters hover zone, wake it up.
            if shouldCaptureMouse {
                showIfNeeded()
                wokePanel = true
            }
            if composer.mouseInHitZone != shouldCaptureMouse {
                composer.mouseInHitZone = shouldCaptureMouse
            }
            if notchPerfLoggingEnabled {
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
                perfAccumulator.recordUpdate(
                    durationMs: elapsedMs,
                    wokePanel: wokePanel,
                    didScreenCheck: didScreenCheck,
                    didMoveScreen: didMoveScreen
                )
                perfAccumulator.flushIfNeeded(log: log)
            }
            return
        }

        composer.updateDebugInteractiveRect(interactiveRect, panelSize: panel.frame.size)

        if panel.ignoresMouseEvents == shouldCaptureMouse {
            panel.ignoresMouseEvents = !shouldCaptureMouse
        }

        // Signal hover state to SwiftUI — this is the authoritative source,
        // replacing .onHover which can't be restricted by contentShape.
        if composer.mouseInHitZone != shouldCaptureMouse {
            composer.mouseInHitZone = shouldCaptureMouse
        }

        if notchPerfLoggingEnabled {
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            perfAccumulator.recordUpdate(
                durationMs: elapsedMs,
                wokePanel: wokePanel,
                didScreenCheck: didScreenCheck,
                didMoveScreen: didMoveScreen
            )
            perfAccumulator.flushIfNeeded(log: log)
        }
    }

    deinit {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if notchPerfLoggingEnabled {
            perfAccumulator.flushIfNeeded(log: log, force: true)
        }
    }
}
