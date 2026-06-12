//
//  RegionPickerOverlay.swift
//  TalkieAgent
//
//  Minimal drag-rectangle region picker used as the visual entry for OCR
//  fallback when AX + clipboard selection capture fails.
//
//  Slimmed adaptation of Talkie's ScreenCaptureOverlay — region mode only,
//  no window-pick mode, no rich-UI feature flag.
//

import AppKit

@MainActor
final class RegionPickerOverlay {
    private var overlayWindow: NSWindow?

    /// Present the overlay on the screen under the cursor and resolve with a
    /// screen-coordinate CGRect (bottom-left origin, same as NSEvent.mouseLocation).
    /// Returns nil if the user escapes or drags a sub-threshold rectangle.
    func pickRegion() async -> CGRect? {
        await withCheckedContinuation { continuation in
            let view = PickerView(frame: .zero)
            var resumed = false
            view.onRegionSelected = { rect in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: rect)
            }
            view.onCancelled = {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: nil)
            }
            showOverlay(with: view)
        }
    }

    private func showOverlay(with view: PickerView) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]

        let window = Panel(
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
        view.activateCursor()
        Task { @MainActor [weak view] in
            view?.activateCursor()
        }
    }

    private func dismiss() {
        (overlayWindow?.contentView as? PickerView)?.deactivateCursor()
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }
}

private final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class PickerView: NSView {
    var onRegionSelected: ((CGRect) -> Void)?
    var onCancelled: (() -> Void)?
    var onDismiss: (() -> Void)?

    var screenOrigin: CGPoint = .zero

    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private var completed = false
    private var didPushCursor = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTrackingArea()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        activateCursor()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }

    override func removeFromSuperview() {
        deactivateCursor()
        super.removeFromSuperview()
    }

    override func draw(_ dirtyRect: NSRect) {
        clearDirtyRect(dirtyRect)

        guard let start = dragStart, let current = dragCurrent else { return }
        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        guard rect.width > 2, rect.height > 2 else { return }

        let border = NSBezierPath(rect: rect.insetBy(dx: 0.75, dy: 0.75))
        NSColor(calibratedRed: 0.96, green: 0.66, blue: 0.34, alpha: 0.95).setStroke()
        border.lineWidth = 1.5
        border.stroke()

        let label = "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor(white: 0, alpha: 0.6),
        ]
        let size = label.size(withAttributes: attrs)
        let point = NSPoint(x: rect.midX - size.width / 2, y: rect.maxY + 6)
        label.draw(at: point, withAttributes: attrs)
    }

    private func clearDirtyRect(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        dirtyRect.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.crosshair.set()
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        dragCurrent = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil else { return }
        NSCursor.crosshair.set()
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.crosshair.set()
        guard let start = dragStart, let current = dragCurrent else {
            complete()
            onCancelled?()
            return
        }

        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        guard rect.width > 5, rect.height > 5 else {
            complete()
            onCancelled?()
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

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // escape
            complete()
            onCancelled?()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseEntered(with event: NSEvent) {
        activateCursor()
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
            NSCursor.crosshair.set()
        } else {
            NSCursor.crosshair.push()
            didPushCursor = true
        }
    }

    func deactivateCursor() {
        guard didPushCursor else { return }
        didPushCursor = false
        NSCursor.pop()
    }

    private func complete() {
        guard !completed else { return }
        completed = true
        onDismiss?()
    }
}
