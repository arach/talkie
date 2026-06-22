#if os(macOS)
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
import ScreenCaptureKit

private enum OverlayMode {
    case region
    case window
}

@MainActor
public final class ScreenCaptureOverlay {
    private var overlayWindow: NSWindow?
    private var overlayView: OverlayView?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    public init() {}

    public func selectRegion(
        freezesDesktop: Bool = false,
        onModeSwitch: ((CaptureBarMode) -> Void)? = nil
    ) async -> CGRect? {
        let prearmedCursor = CursorLease(cursor: OverlayView.cursor(for: .region))
        prearmedCursor.activate()

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]

        // Freeze-first: grab (or await) a full-display still before the overlay
        // becomes key. Taking key focus dismisses menus/popovers, so the still
        // must be ready before showOverlay().
        var frozenBackground: NSImage?
        if freezesDesktop {
            if !CaptureFreezeStore.shared.isPrimed {
                CaptureFreezeStore.shared.prime(for: screen)
            }
            frozenBackground = await CaptureFreezeStore.shared.displayImage(forScreenFrame: screen.frame)
        }

        return await withCheckedContinuation { continuation in
            let view = OverlayView(mode: .region)
            var didResume = false
            let resume: (CGRect?) -> Void = { result in
                guard !didResume else { return }
                didResume = true
                prearmedCursor.deactivate()
                continuation.resume(returning: result)
            }
            view.onRegionSelected = { resume($0) }
            view.onCancelled = { resume(nil) }
            view.onModeSwitch = onModeSwitch
            view.frozenSnapshot = frozenBackground
            showOverlay(with: view, on: screen)
            prearmedCursor.deactivate()
        }
    }

    public func cancel() {
        overlayView?.cancel()
    }

    public func selectWindow() async -> CGWindowID? {
        let prearmedCursor = CursorLease(cursor: OverlayView.cursor(for: .window))
        prearmedCursor.activate()

        return await withCheckedContinuation { continuation in
            let view = OverlayView(mode: .window)
            var didResume = false
            let resume: (CGWindowID?) -> Void = { result in
                guard !didResume else { return }
                didResume = true
                prearmedCursor.deactivate()
                continuation.resume(returning: result)
            }
            view.onWindowSelected = { resume($0) }
            view.onCancelled = { resume(nil) }
            showOverlay(with: view)
            prearmedCursor.deactivate()
        }
    }

    private func showOverlay(with view: OverlayView, on targetScreen: NSScreen? = nil) {
        let mouse = NSEvent.mouseLocation
        let screen = targetScreen
            ?? NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
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
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.sharingType = .none
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
        installKeyMonitors()
        view.activateCursor()
        Task { @MainActor [weak view] in
            view?.activateCursor()
        }
    }

    private func dismiss() {
        removeKeyMonitors()
        overlayView?.releaseTransientResources()
        overlayWindow?.orderOut(nil)
        overlayWindow?.contentView = nil
        overlayWindow = nil
        overlayView = nil
    }

    private func installKeyMonitors() {
        removeKeyMonitors()
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                _ = self?.handleKeyEvent(event)
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                return self.handleKeyEvent(event) ? nil : event
            }
        }
    }

    private func removeKeyMonitors() {
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        overlayView?.handleControlKey(event) ?? false
    }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class CursorLease {
    private let cursor: NSCursor
    private var isActive = false

    init(cursor: NSCursor) {
        self.cursor = cursor
    }

    func activate() {
        guard !isActive else {
            cursor.set()
            return
        }
        cursor.push()
        cursor.set()
        isActive = true
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        NSCursor.pop()
    }

    deinit {
        deactivate()
    }
}

private final class OverlayView: NSView {
    private struct WindowCandidate: Sendable {
        let id: CGWindowID
        let frameCG: CGRect
        let snapFrameCocoa: CGRect
        let highlightFrameCocoa: CGRect
    }

    let mode: OverlayMode

    var onRegionSelected: ((CGRect) -> Void)?
    var onWindowSelected: ((CGWindowID) -> Void)?
    var onCancelled: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onModeSwitch: ((CaptureBarMode) -> Void)?

    var screenOrigin: CGPoint = .zero

    /// Pre-captured still of the desktop the overlay is sitting on. When
    /// present (region mode), it's painted as the view background so the
    /// user crops a frozen image — windows can't reflow under them, the
    /// menu bar clock can't tick mid-drag. Loaded just after the overlay is
    /// armed; nil falls back to live-desktop behavior.
    var frozenSnapshot: NSImage?

    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private var lastDragDrawRect: NSRect = .zero
    private var suppressWindowSnapping = false
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
    private let windowSnapDistance: CGFloat = 12
    private var richCaptureUIEnabled: Bool { false }
    private var selectionAccent: NSColor {
        NSColor(calibratedRed: 0.96, green: 0.66, blue: 0.34, alpha: 1)
    }
    private var overlayCursor: NSCursor {
        Self.cursor(for: mode)
    }

    fileprivate static func cursor(for mode: OverlayMode) -> NSCursor {
        mode == .region ? regionCursor : cameraCursor
    }

    private static let regionCursor: NSCursor = {
        let size = NSSize(width: 28, height: 28)
        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        let image = NSImage(size: size)
        image.lockFocus()

        func strokeCrosshair(color: NSColor, lineWidth: CGFloat) {
            color.setStroke()
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round

            path.move(to: NSPoint(x: center.x, y: 3))
            path.line(to: NSPoint(x: center.x, y: 10))
            path.move(to: NSPoint(x: center.x, y: 18))
            path.line(to: NSPoint(x: center.x, y: 25))
            path.move(to: NSPoint(x: 3, y: center.y))
            path.line(to: NSPoint(x: 10, y: center.y))
            path.move(to: NSPoint(x: 18, y: center.y))
            path.line(to: NSPoint(x: 25, y: center.y))
            path.stroke()

            let ring = NSBezierPath(ovalIn: NSRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6))
            ring.lineWidth = lineWidth
            ring.stroke()
        }

        strokeCrosshair(color: NSColor.black.withAlphaComponent(0.55), lineWidth: 3)
        strokeCrosshair(color: NSColor.white.withAlphaComponent(0.96), lineWidth: 1.2)

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: center)
    }()

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
        refreshWindowCandidatesForCurrentScreen(forceRefresh: false)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }

    override func removeFromSuperview() {
        releaseTransientResources()
        super.removeFromSuperview()
    }

    func releaseTransientResources() {
        pendingWindowHoverUpdate = false
        windowCandidatesRefreshTask?.cancel()
        windowCandidatesRefreshTask = nil
        frozenSnapshot = nil
        windowCandidates.removeAll(keepingCapacity: false)
        highlightedWindowID = nil
        highlightedWindowFrame = nil
        dragStart = nil
        dragCurrent = nil
        lastDragDrawRect = .zero
        suppressWindowSnapping = false
        deactivateCursor()
    }

    override func draw(_ dirtyRect: NSRect) {
        clearDirtyRect(dirtyRect)
        paintFrozenSnapshot()
        switch mode {
        case .region:
            drawRegionSelection()
        case .window:
            drawWindowHighlight()
        }
    }

    private func clearDirtyRect(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        dirtyRect.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    func installFrozenSnapshot(_ snapshot: NSImage?) {
        guard mode == .region, !completed, dragStart == nil, dragCurrent == nil else { return }
        frozenSnapshot = snapshot
        if snapshot != nil {
            needsDisplay = true
        }
    }

    /// Paints the frozen desktop snapshot as the view background for
    /// the region-selection session once it is available. If the user
    /// starts dragging before the snapshot returns, region mode keeps the
    /// live desktop rather than changing the background mid-drag. Window
    /// mode keeps live behaviour because it relies on hovering real windows,
    /// not cropping pixels.
    private func paintFrozenSnapshot() {
        guard mode == .region, let snapshot = frozenSnapshot else { return }
        snapshot.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
    }

    private func drawRegionSelection() {
        guard let start = dragStart, let current = dragCurrent else { return }
        let selection = regionSelection(start: start, current: current)
        let rect = selection.rect
        guard rect.width > 2, rect.height > 2 else { return }

        let border = NSBezierPath(rect: rect.insetBy(dx: 0.75, dy: 0.75))
        selectionAccent.withAlphaComponent(selection.didSnap ? 0.95 : 0.88).setStroke()
        border.lineWidth = selection.didSnap ? 2 : 1.5
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

    private func regionSelection(
        start: NSPoint,
        current: NSPoint,
        allowsWindowSnapping: Bool? = nil
    ) -> (rect: NSRect, didSnap: Bool) {
        let rawRect = Self.dragRect(start: start, current: current)
        let shouldSnap = allowsWindowSnapping ?? !suppressWindowSnapping
        guard shouldSnap, rawRect.width > 2, rawRect.height > 2 else {
            return (rawRect, false)
        }

        return snappedRegionSelection(for: rawRect)
    }

    private func snappedRegionSelection(for rawRect: NSRect) -> (rect: NSRect, didSnap: Bool) {
        guard !windowCandidates.isEmpty else { return (rawRect, false) }

        var bestLeft: (value: CGFloat, distance: CGFloat)?
        var bestRight: (value: CGFloat, distance: CGFloat)?
        var bestBottom: (value: CGFloat, distance: CGFloat)?
        var bestTop: (value: CGFloat, distance: CGFloat)?

        func consider(_ target: CGFloat, for edge: CGFloat, best: inout (value: CGFloat, distance: CGFloat)?) {
            let distance = abs(target - edge)
            guard distance <= windowSnapDistance else { return }
            if let currentBest = best {
                guard distance < currentBest.distance else { return }
            }
            best = (target, distance)
        }

        for candidate in windowCandidates {
            guard let frame = localSnapFrame(for: candidate) else { continue }

            let overlapsSelectionVertically = frame.maxY >= rawRect.minY - windowSnapDistance
                && frame.minY <= rawRect.maxY + windowSnapDistance
            if overlapsSelectionVertically {
                consider(frame.minX, for: rawRect.minX, best: &bestLeft)
                consider(frame.maxX, for: rawRect.minX, best: &bestLeft)
                consider(frame.minX, for: rawRect.maxX, best: &bestRight)
                consider(frame.maxX, for: rawRect.maxX, best: &bestRight)
            }

            let overlapsSelectionHorizontally = frame.maxX >= rawRect.minX - windowSnapDistance
                && frame.minX <= rawRect.maxX + windowSnapDistance
            if overlapsSelectionHorizontally {
                consider(frame.minY, for: rawRect.minY, best: &bestBottom)
                consider(frame.maxY, for: rawRect.minY, best: &bestBottom)
                consider(frame.minY, for: rawRect.maxY, best: &bestTop)
                consider(frame.maxY, for: rawRect.maxY, best: &bestTop)
            }
        }

        let left = bestLeft?.value ?? rawRect.minX
        let right = bestRight?.value ?? rawRect.maxX
        let bottom = bestBottom?.value ?? rawRect.minY
        let top = bestTop?.value ?? rawRect.maxY
        guard right - left > 5, top - bottom > 5 else { return (rawRect, false) }

        let snappedRect = NSRect(x: left, y: bottom, width: right - left, height: top - bottom).standardized
        let didSnap = bestLeft != nil || bestRight != nil || bestBottom != nil || bestTop != nil
        return (snappedRect, didSnap)
    }

    private func localSnapFrame(for candidate: WindowCandidate) -> NSRect? {
        let screenRect = NSRect(origin: screenOrigin, size: bounds.size)
        let clippedFrame = candidate.snapFrameCocoa.intersection(screenRect)
        guard !clippedFrame.isNull, clippedFrame.width > 4, clippedFrame.height > 4 else { return nil }
        return NSRect(
            x: clippedFrame.minX - screenOrigin.x,
            y: clippedFrame.minY - screenOrigin.y,
            width: clippedFrame.width,
            height: clippedFrame.height
        ).standardized
    }

    private static func dragRect(start: NSPoint, current: NSPoint) -> NSRect {
        NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        ).standardized
    }

    private func drawWindowHighlight() {
        guard let frame = highlightedWindowFrame else { return }

        let local = NSRect(
            x: frame.origin.x - screenOrigin.x,
            y: frame.origin.y - screenOrigin.y,
            width: frame.width,
            height: frame.height
        )
        drawRegionBackdrop(excluding: local)

        let fill = NSBezierPath(roundedRect: local, xRadius: 6, yRadius: 6)
        selectionAccent.withAlphaComponent(0.07).setFill()
        fill.fill()

        let border = NSBezierPath(roundedRect: local, xRadius: 6, yRadius: 6)
        selectionAccent.withAlphaComponent(0.82).setStroke()
        border.lineWidth = 1
        border.stroke()
    }

    private func drawRegionBackdrop(excluding rect: NSRect) {
        NSColor(white: 0, alpha: 0.16).setFill()

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
        refreshWindowCandidatesForCurrentScreen(forceRefresh: true)
        suppressWindowSnapping = event.modifierFlags.contains(.option)
        dragStart = point
        dragCurrent = point
        lastDragDrawRect = dragInvalidationRect(
            for: point,
            current: point,
            allowsWindowSnapping: !suppressWindowSnapping
        )
        // Full-view invalidate so the frozen snapshot paints across the
        // whole desktop on the first draw of the drag. Without this the
        // snapshot would only paint inside the small drag-region rect.
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .region, let start = dragStart else { return }
        overlayCursor.set()
        refreshWindowCandidatesForCurrentScreen(forceRefresh: false)
        let previousRect = lastDragDrawRect
        let nextPoint = convert(event.locationInWindow, from: nil)
        suppressWindowSnapping = event.modifierFlags.contains(.option)
        dragCurrent = nextPoint
        let nextRect = dragInvalidationRect(
            for: start,
            current: nextPoint,
            allowsWindowSnapping: !suppressWindowSnapping
        )
        lastDragDrawRect = nextRect
        invalidateDragRegion(previous: previousRect, current: nextRect)
    }

    override func mouseUp(with event: NSEvent) {
        guard mode == .region, let start = dragStart, let current = dragCurrent else { return }
        overlayCursor.set()
        refreshWindowCandidatesForCurrentScreen(forceRefresh: false)
        suppressWindowSnapping = event.modifierFlags.contains(.option)

        let rect = regionSelection(start: start, current: current).rect
        guard rect.width > 5, rect.height > 5 else {
            dragStart = nil
            dragCurrent = nil
            suppressWindowSnapping = false
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

    override func flagsChanged(with event: NSEvent) {
        guard mode == .region, let start = dragStart, let current = dragCurrent else {
            super.flagsChanged(with: event)
            return
        }

        overlayCursor.set()
        let previousRect = lastDragDrawRect
        suppressWindowSnapping = event.modifierFlags.contains(.option)
        let nextRect = dragInvalidationRect(
            for: start,
            current: current,
            allowsWindowSnapping: !suppressWindowSnapping
        )
        lastDragDrawRect = nextRect
        invalidateDragRegion(previous: previousRect, current: nextRect)
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
                    highlightedWindowFrame = candidate.highlightFrameCocoa
                }
                return candidate.id
            }
        }

        return nil
    }

    private func refreshWindowCandidatesForCurrentScreen(forceRefresh: Bool) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        refreshWindowCandidatesIfNeeded(primaryHeight: primaryHeight, forceRefresh: forceRefresh)
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
            candidates.append(
                WindowCandidate(
                    id: windowID,
                    frameCG: frameCG,
                    snapFrameCocoa: frameCocoa.standardized,
                    highlightFrameCocoa: Self.trimmedWindowHighlightFrame(frameCocoa)
                )
            )
        }

        return candidates
    }

    nonisolated private static func trimmedWindowHighlightFrame(_ frame: CGRect) -> CGRect {
        let horizontalInset = min(6, frame.width * 0.04)
        let verticalInset = min(20, frame.height * 0.08)
        return frame.insetBy(dx: horizontalInset, dy: verticalInset).standardized
    }

    func handleControlKey(_ event: NSEvent) -> Bool {
        if let onModeSwitch, event.isCaptureModeSwitchArrow {
            onModeSwitch(event.keyCode == 123 ? .screenshot : .video)
            return true
        }

        if event.keyCode == 53 {
            cancel()
            return true
        }

        return false
    }

    override func keyDown(with event: NSEvent) {
        if handleControlKey(event) {
            return
        }
        super.keyDown(with: event)
    }

    public func cancel() {
        complete()
        onCancelled?()
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
        overlayCursor.set()
        if didPushCursor {
            return
        }
        overlayCursor.push()
        didPushCursor = true
    }

    func deactivateCursor() {
        guard didPushCursor else { return }
        didPushCursor = false
        NSCursor.pop()
    }

    private func dragInvalidationRect(
        for start: NSPoint,
        current: NSPoint,
        allowsWindowSnapping: Bool = true
    ) -> NSRect {
        let rect = regionSelection(
            start: start,
            current: current,
            allowsWindowSnapping: allowsWindowSnapping
        ).rect
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

private extension NSEvent {
    var isCaptureModeSwitchArrow: Bool {
        guard keyCode == 123 || keyCode == 124 else { return false }
        let synthesizedArrowFlags: NSEvent.ModifierFlags = [.numericPad, .function]
        let activeModifiers = modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(synthesizedArrowFlags)
        let hyperModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        return activeModifiers.isEmpty || activeModifiers.isSuperset(of: hyperModifiers)
    }
}

#endif
