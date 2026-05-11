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
            let view = PickerView()
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
    }

    private func dismiss() {
        NSCursor.arrow.set()
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

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        NSCursor.crosshair.set()
    }

    override func removeFromSuperview() {
        NSCursor.arrow.set()
        super.removeFromSuperview()
    }

    override func draw(_ dirtyRect: NSRect) {
        // Soft backdrop across the whole screen so users see this isn't the normal desktop
        NSColor(white: 0, alpha: 0.18).setFill()
        bounds.fill()

        guard let start = dragStart, let current = dragCurrent else { return }
        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        guard rect.width > 2, rect.height > 2 else { return }

        // Punch out selection area (draw over backdrop with clear-ish fill)
        NSColor(white: 1, alpha: 0.05).setFill()
        rect.fill()

        let border = NSBezierPath(rect: rect)
        NSColor.white.withAlphaComponent(0.94).setStroke()
        border.lineWidth = 1
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

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        dragCurrent = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
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

    private func complete() {
        guard !completed else { return }
        completed = true
        onDismiss?()
    }
}
