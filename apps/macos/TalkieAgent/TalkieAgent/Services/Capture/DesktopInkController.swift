//
//  DesktopInkController.swift
//  TalkieAgent
//
//  A persistent on-screen ink layer you draw on *before* snapping — the marks
//  end up baked into the screenshot. Think Epic Pen: scribble straight over
//  your live apps, flip to "arrange" to move windows under the ink, draw more,
//  then capture.
//
//  It reuses the screen-recording markup kit wholesale (LiveCaptureMarkupOverlay
//  + overlay.html), so the tools are identical to what users already know — no
//  new drawing UX. This controller only owns the lifecycle the desktop case
//  needs: show/hide, the draw <-> arrange (passthrough) toggle, and exposing the
//  current layers + the screen they're normalized to for the bake-on-snap step.
//

import AppKit
import TalkieKit

@MainActor
final class DesktopInkController {
    static let shared = DesktopInkController()
    private init() {}

    private let overlay = LiveCaptureMarkupOverlayController()

    /// Fired when the user taps the screenshot button in the ink toolbar. The
    /// host (AppDelegate) runs region selection and bakes the strokes in.
    var onCaptureRequested: (() -> Void)?

    private(set) var isActive = false

    /// Screen the ink overlay currently covers. Layer geometry is normalized to
    /// this frame; the bake-on-snap step rebases it to the captured region.
    private(set) var overlayScreenFrame: CGRect = .zero

    /// Layers drawn so far (empty when nothing has been inked).
    var currentLayers: [CaptureMarkupLayer] { overlay.layers }
    var hasInk: Bool { !overlay.layers.isEmpty }

    /// Toggle the ink layer on/off. On = draw mode over the screen under the
    /// cursor, reusing the live-markup toolbar. Off = dismiss and clear.
    func toggle() {
        if isActive {
            hide(clear: true)
        } else {
            show()
        }
    }

    func show() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        overlay.passthrough = false
        overlay.persistsLayersOnDone = true
        overlay.showsCaptureAction = true
        // Keep drawing/selecting after each stroke; arrange mode is explicit.
        overlay.onLayersChanged = nil
        overlay.onCancel = { [weak self] in
            self?.isActive = false
        }
        overlay.onCapture = { [weak self] in
            self?.onCaptureRequested?()
        }
        overlay.show(on: screen, targetRect: screen.frame)
        overlayScreenFrame = screen.frame
        isActive = true
    }

    func hide(clear: Bool) {
        overlay.dismiss(discardLayers: clear)
        if clear { overlayScreenFrame = .zero }
        isActive = false
    }

    /// Flip between draw (strokes capture clicks) and arrange (clicks fall
    /// through so you can move the real windows under your ink). No-op unless
    /// the ink layer is showing.
    func togglePassthrough() {
        guard isActive else { return }
        overlay.passthrough.toggle()
        if !overlay.passthrough {
            overlay.setTool("ink")
        }
    }

    /// Step the ink overlay aside so a screenshot's selection UI is reachable.
    /// Layers stay alive for the bake. Pair with `endCaptureYield()`.
    func beginCaptureYield() {
        guard isActive else { return }
        overlay.yieldForCapture()
    }

    /// Bring the ink overlay back after a capture that left the strokes in
    /// place (e.g. the shot was cancelled or missed the inked screen).
    func endCaptureYield() {
        guard isActive else { return }
        overlay.resumeAfterCapture()
    }
}
