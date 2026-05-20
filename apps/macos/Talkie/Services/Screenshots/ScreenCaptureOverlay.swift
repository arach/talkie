//
//  ScreenCaptureOverlay.swift
//  Talkie
//
//  Clean V2 baseline for screenshot selection UX:
//  - Region mode: drag rectangle + size label
//  - Window mode: lightweight hover highlight + click select
//  - No magnifier/live preview/watermark
//

import AppKit

enum OverlayMode {
    case region
    case window
}

@MainActor
final class ScreenCaptureOverlay {
    private var overlayWindow: NSWindow?
    private var overlayView: OverlayView?

    func selectRegion() async -> CGRect? {
        await withCheckedContinuation { continuation in
            let view = OverlayView(mode: .region)
            var didResume = false
            let resume: (CGRect?) -> Void = { result in
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: result)
            }
            view.onRegionSelected = { resume($0) }
            view.onCancelled = { resume(nil) }
            showOverlay(with: view)
        }
    }

    func selectWindow() async -> CGWindowID? {
        await withCheckedContinuation { continuation in
            let view = OverlayView(mode: .window)
            var didResume = false
            let resume: (CGWindowID?) -> Void = { result in
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: result)
            }
            view.onWindowSelected = { resume($0) }
            view.onCancelled = { resume(nil) }
            showOverlay(with: view)
        }
    }

    private func showOverlay(with view: OverlayView) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]

        let window = OverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.animationBehavior = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.sharingType = .readOnly
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false

        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        view.screenOrigin = screen.frame.origin
        view.autoresizingMask = [.width, .height]
        view.onDismiss = { [weak self] in self?.dismiss() }

        window.contentView = view
        window.orderFrontRegardless()
        window.makeKey()
        window.makeFirstResponder(view)

        overlayWindow = window
        overlayView = view
        view.activateCursor()
        Task { @MainActor [weak view] in
            view?.activateCursor()
        }
    }

    private func dismiss() {
        overlayView?.deactivateCursor()
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        overlayView = nil
    }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class OverlayView: NSView {
    private struct WindowCandidate: Sendable {
        let id: CGWindowID
        let frameCG: CGRect
        let frameCocoa: CGRect
    }

    let mode: OverlayMode

    var onRegionSelected: ((CGRect) -> Void)?
    var onWindowSelected: ((CGWindowID) -> Void)?
    var onCancelled: (() -> Void)?
    var onDismiss: (() -> Void)?

    var screenOrigin: CGPoint = .zero

    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private var lastDragDrawRect: NSRect = .zero
    private var highlightedWindowID: CGWindowID?
    private var highlightedWindowFrame: CGRect?
    private var pendingWindowHoverUpdate = false
    private var lastWindowHoverUpdateAt: CFAbsoluteTime = 0
    private var windowCandidatesRefreshTask: Task<Void, Never>?
    private var windowCandidates: [WindowCandidate] = []
    private var windowCandidatesUpdatedAtNs: UInt64 = 0
    private var completed = false
    private var didPushCursor = false

    private let windowHoverUpdateInterval: CFAbsoluteTime = 1.0 / 90.0
    private let windowCacheRefreshIntervalNs: UInt64 = 1_200_000_000 // 1.2s
    private var richCaptureUIEnabled: Bool { FeatureFlags.shared.enableCaptureRichUI }
    private var overlayCursor: NSCursor {
        mode == .region ? .crosshair : Self.cameraCursor
    }
    private static let cameraCursor: NSCursor = {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(white: 0.12, alpha: 0.88).setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        if let symbol = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            let rendered = symbol.withSymbolConfiguration(config) ?? symbol
            rendered.isTemplate = true
            NSColor.white.set()
            rendered.draw(in: NSRect(x: 6, y: 6, width: 12, height: 12))
        }
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }()

    init(mode: OverlayMode) {
        self.mode = mode
        super.init(frame: .zero)
        setupTrackingArea()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: overlayCursor)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        activateCursor()
        if mode == .window {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            refreshWindowCandidatesIfNeeded(primaryHeight: primaryHeight, forceRefresh: false)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }

    override func removeFromSuperview() {
        pendingWindowHoverUpdate = false
        windowCandidatesRefreshTask?.cancel()
        windowCandidatesRefreshTask = nil
        deactivateCursor()
        super.removeFromSuperview()
    }

    override func draw(_ dirtyRect: NSRect) {
        switch mode {
        case .region:
            drawRegionSelection()
        case .window:
            drawWindowHighlight()
        }
    }

    private func drawRegionSelection() {
        guard let start = dragStart, let current = dragCurrent else { return }
        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        guard rect.width > 2, rect.height > 2 else { return }

        if richCaptureUIEnabled {
            drawRegionBackdrop(excluding: rect)
        }

        NSColor(white: 0, alpha: 0.12).setFill()
        rect.fill()

        let border = NSBezierPath(rect: rect)
        NSColor.white.withAlphaComponent(0.92).setStroke()
        border.lineWidth = 1
        border.stroke()

        if richCaptureUIEnabled {
            let crosshairLength: CGFloat = 6
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let crosshair = NSBezierPath()
            crosshair.move(to: NSPoint(x: center.x - crosshairLength, y: center.y))
            crosshair.line(to: NSPoint(x: center.x + crosshairLength, y: center.y))
            crosshair.move(to: NSPoint(x: center.x, y: center.y - crosshairLength))
            crosshair.line(to: NSPoint(x: center.x, y: center.y + crosshairLength))
            NSColor.white.withAlphaComponent(0.72).setStroke()
            crosshair.lineWidth = 1
            crosshair.stroke()
        }

        let label = "\(Int(rect.width)) x \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor(white: 0, alpha: 0.6),
        ]
        let size = label.size(withAttributes: attrs)
        let point = NSPoint(x: rect.midX - size.width / 2, y: rect.maxY + 6)
        label.draw(at: point, withAttributes: attrs)
    }

    private func drawWindowHighlight() {
        guard let frame = highlightedWindowFrame else { return }
        if richCaptureUIEnabled {
            NSColor(white: 0, alpha: 0.08).setFill()
            bounds.fill()
        }

        let local = NSRect(
            x: frame.origin.x - screenOrigin.x,
            y: frame.origin.y - screenOrigin.y,
            width: frame.width,
            height: frame.height
        )

        let fill = NSBezierPath(roundedRect: local, xRadius: 6, yRadius: 6)
        NSColor(white: 0.5, alpha: 0.24).setFill()
        fill.fill()

        let border = NSBezierPath(roundedRect: local, xRadius: 6, yRadius: 6)
        NSColor.white.withAlphaComponent(0.92).setStroke()
        border.lineWidth = 1.5
        border.stroke()
    }

    private func drawRegionBackdrop(excluding rect: NSRect) {
        NSColor(white: 0, alpha: 0.08).setFill()

        let top = NSRect(x: 0, y: rect.maxY, width: bounds.width, height: max(0, bounds.maxY - rect.maxY))
        let bottom = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, rect.minY))
        let left = NSRect(x: 0, y: rect.minY, width: max(0, rect.minX), height: rect.height)
        let right = NSRect(x: rect.maxX, y: rect.minY, width: max(0, bounds.maxX - rect.maxX), height: rect.height)

        top.fill()
        bottom.fill()
        left.fill()
        right.fill()
    }

    override func mouseDown(with event: NSEvent) {
        overlayCursor.set()
        guard mode == .region else {
            handleWindowClick()
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        dragCurrent = point
        lastDragDrawRect = dragInvalidationRect(for: point, current: point)
        invalidateDragRegion(previous: .zero, current: lastDragDrawRect)
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .region, dragStart != nil else { return }
        overlayCursor.set()
        let previousRect = lastDragDrawRect
        let nextPoint = convert(event.locationInWindow, from: nil)
        dragCurrent = nextPoint
        let nextRect = dragInvalidationRect(for: dragStart ?? nextPoint, current: nextPoint)
        lastDragDrawRect = nextRect
        invalidateDragRegion(previous: previousRect, current: nextRect)
    }

    override func mouseUp(with event: NSEvent) {
        guard mode == .region, let start = dragStart, let current = dragCurrent else { return }
        overlayCursor.set()

        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        guard rect.width > 5, rect.height > 5 else {
            dragStart = nil
            dragCurrent = nil
            let previousRect = lastDragDrawRect
            lastDragDrawRect = .zero
            invalidateDragRegion(previous: previousRect, current: .zero)
            return
        }

        let screenRect = CGRect(
            x: rect.origin.x + screenOrigin.x,
            y: rect.origin.y + screenOrigin.y,
            width: rect.width,
            height: rect.height
        )
        complete()
        onRegionSelected?(screenRect)
    }

    override func mouseMoved(with event: NSEvent) {
        overlayCursor.set()
        guard mode == .window else { return }
        scheduleWindowHoverUpdate()
    }

    override func mouseEntered(with event: NSEvent) {
        activateCursor()
    }

    private func handleWindowClick() {
        guard mode == .window else { return }
        let selectedID = highlightedWindowID ?? windowIDUnderCursor(forceRefresh: true)
        guard let selectedID else { return }
        complete()
        onWindowSelected?(selectedID)
    }

    private func updateWindowUnderCursor() {
        guard let windowID = windowIDUnderCursor(includeFrame: true, forceRefresh: false) else {
            if highlightedWindowID != nil {
                highlightedWindowID = nil
                highlightedWindowFrame = nil
                needsDisplay = true
            }
            return
        }

        if highlightedWindowID != windowID {
            highlightedWindowID = windowID
            needsDisplay = true
        }
    }

    private func scheduleWindowHoverUpdate() {
        guard !pendingWindowHoverUpdate else { return }
        pendingWindowHoverUpdate = true

        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastWindowHoverUpdateAt
        let delay = max(0, windowHoverUpdateInterval - elapsed)

        if delay == 0 {
            runWindowHoverUpdate()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.runWindowHoverUpdate()
        }
    }

    private func runWindowHoverUpdate() {
        guard pendingWindowHoverUpdate else { return }
        pendingWindowHoverUpdate = false
        lastWindowHoverUpdateAt = CFAbsoluteTimeGetCurrent()
        updateWindowUnderCursor()
    }

    private func windowIDUnderCursor(includeFrame: Bool = false, forceRefresh: Bool) -> CGWindowID? {
        let screenPoint = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let mouseYInCG = primaryHeight - screenPoint.y

        refreshWindowCandidatesIfNeeded(primaryHeight: primaryHeight, forceRefresh: forceRefresh)

        for candidate in windowCandidates {
            let frame = candidate.frameCG
            if screenPoint.x >= frame.minX, screenPoint.x <= frame.maxX,
               mouseYInCG >= frame.minY, mouseYInCG <= frame.maxY {
                if includeFrame {
                    highlightedWindowFrame = candidate.frameCocoa
                }
                return candidate.id
            }
        }

        return nil
    }

    private func refreshWindowCandidatesIfNeeded(primaryHeight: CGFloat, forceRefresh: Bool) {
        let nowNs = DispatchTime.now().uptimeNanoseconds
        if !forceRefresh, nowNs - windowCandidatesUpdatedAtNs < windowCacheRefreshIntervalNs {
            return
        }

        let overlayWindowID = window.map { CGWindowID($0.windowNumber) }

        if forceRefresh {
            windowCandidates = Self.buildWindowCandidates(primaryHeight: primaryHeight, overlayWindowID: overlayWindowID)
            windowCandidatesUpdatedAtNs = nowNs
            return
        }

        if windowCandidatesRefreshTask != nil {
            return
        }

        // Stamp refresh start time to avoid launching many refresh tasks while this one is in flight.
        windowCandidatesUpdatedAtNs = nowNs
        windowCandidatesRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let candidates = await Task.detached(priority: .utility) {
                Self.buildWindowCandidates(primaryHeight: primaryHeight, overlayWindowID: overlayWindowID)
            }.value

            guard !Task.isCancelled else { return }
            self.windowCandidates = candidates
            self.windowCandidatesUpdatedAtNs = DispatchTime.now().uptimeNanoseconds
            self.windowCandidatesRefreshTask = nil
        }
    }

    nonisolated private static func buildWindowCandidates(primaryHeight: CGFloat, overlayWindowID: CGWindowID?) -> [WindowCandidate] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var candidates: [WindowCandidate] = []
        candidates.reserveCapacity(16)

        for item in info {
            guard let layer = item[kCGWindowLayer as String] as? Int, layer == 0,
                  let windowID = item[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = item[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"] else { continue }

            if let overlayWindowID, windowID == overlayWindowID { continue }
            if w < 4 || h < 4 { continue }

            let frameCG = CGRect(x: x, y: y, width: w, height: h)
            let frameCocoa = CGRect(x: x, y: primaryHeight - y - h, width: w, height: h)
            candidates.append(WindowCandidate(id: windowID, frameCG: frameCG, frameCocoa: frameCocoa))
        }

        return candidates
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            complete()
            onCancelled?()
        }
    }

    private func setupTrackingArea() {
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    func activateCursor() {
        guard window != nil, !completed else { return }
        window?.invalidateCursorRects(for: self)
        if didPushCursor {
            overlayCursor.set()
        } else {
            overlayCursor.push()
            didPushCursor = true
        }
    }

    func deactivateCursor() {
        guard didPushCursor else { return }
        didPushCursor = false
        NSCursor.pop()
    }

    private func dragInvalidationRect(for start: NSPoint, current: NSPoint) -> NSRect {
        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        // Include border + size label area.
        return rect.insetBy(dx: -4, dy: -24)
    }

    private func invalidateDragRegion(previous: NSRect, current: NSRect) {
        if richCaptureUIEnabled {
            needsDisplay = true
            return
        }

        let dirty: NSRect
        if previous.isEmpty {
            dirty = current
        } else if current.isEmpty {
            dirty = previous
        } else {
            dirty = previous.union(current)
        }

        if dirty.isEmpty {
            needsDisplay = true
        } else {
            needsDisplay = false
            setNeedsDisplay(dirty)
        }
    }

    private func complete() {
        guard !completed else { return }
        completed = true
        onDismiss?()
    }
}
