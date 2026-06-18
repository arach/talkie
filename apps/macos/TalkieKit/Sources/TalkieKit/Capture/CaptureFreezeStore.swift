//
//  CaptureFreezeStore.swift
//  TalkieKit
//
//  Holds a "freeze-first" still of the display for region screenshots.
//
//  The region selection overlay must become key to receive the drag, and
//  taking key focus dismisses any open menu / popover / tooltip — so by the
//  time the crosshair is up, the thing the user wanted to capture is gone.
//  Fullscreen capture never has this problem because it grabs pixels at the
//  instant it's triggered.
//
//  This store reproduces that "grab now" behavior for region selection:
//  prime a full-display still *before* the overlay (or even the HUD bar)
//  appears, then both paint it under the crosshair and crop the saved image
//  from it. Transient windows that would vanish on focus change survive in
//  the still.
//

import AppKit
import ScreenCaptureKit

@MainActor
public final class CaptureFreezeStore {
    public static let shared = CaptureFreezeStore()

    public struct Frozen: Sendable {
        public let image: CGImage
        /// The screen the still covers, in global Cocoa (bottom-left) coords.
        public let screenFrame: CGRect
        public let scale: CGFloat
    }

    private var task: Task<Frozen?, Never>?

    private init() {}

    /// Whether a still has already been primed for the current capture.
    public var isPrimed: Bool { task != nil }

    /// Begin grabbing a full-display still for the screen under the mouse.
    /// Safe to call before any overlay/bar appears so transient windows are
    /// still on screen. The actual pixel grab is awaited (see `current()`)
    /// before the overlay takes key focus, guaranteeing the menu/popover is
    /// captured.
    public func prime(forMouseAt mouse: NSPoint = NSEvent.mouseLocation) {
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        prime(for: screen)
    }

    public func prime(for screen: NSScreen?) {
        guard let screen else { return }
        task?.cancel()
        task = Task { await Self.capture(for: screen) }
    }

    /// Awaits the in-flight (or finished) still. Multiple consumers can await
    /// the same primed still — the underlying grab runs once. Returns nil if
    /// nothing was primed or the grab failed (callers fall back to live read).
    public func current() async -> Frozen? {
        guard let task else { return nil }
        return await task.value
    }

    public func clear() {
        task?.cancel()
        task = nil
    }

    /// The primed still rendered for overlay display, but only when it matches
    /// the overlay's screen (the user didn't cross displays between priming and
    /// selecting). Mismatch returns nil so the overlay keeps live behavior.
    public func displayImage(forScreenFrame screenFrame: CGRect) async -> NSImage? {
        guard let frozen = await current(), frozen.screenFrame == screenFrame else { return nil }
        return NSImage(cgImage: frozen.image, size: frozen.screenFrame.size)
    }

    /// Crop the frozen still to a region given in global Cocoa screen coords.
    /// Returns nil when there is no still, the screen doesn't match, or the
    /// rect falls outside the still — caller then does a live read.
    public func crop(screenRect: CGRect) async -> CGImage? {
        guard let frozen = await current() else { return nil }
        let frame = frozen.screenFrame
        guard NSMouseInRect(NSPoint(x: screenRect.midX, y: screenRect.midY), frame, false) else {
            return nil
        }

        // Cocoa (bottom-left) → image (top-left). Same flip captureScreenRegion
        // uses for its display-local source rect.
        let localTopLeft = CGRect(
            x: screenRect.origin.x - frame.origin.x,
            y: frame.height - (screenRect.origin.y - frame.origin.y) - screenRect.height,
            width: screenRect.width,
            height: screenRect.height
        )
        let pixelRect = CGRect(
            x: (localTopLeft.origin.x * frozen.scale).rounded(.toNearestOrAwayFromZero),
            y: (localTopLeft.origin.y * frozen.scale).rounded(.toNearestOrAwayFromZero),
            width: (localTopLeft.width * frozen.scale).rounded(.toNearestOrAwayFromZero),
            height: (localTopLeft.height * frozen.scale).rounded(.toNearestOrAwayFromZero)
        )
        let bounds = CGRect(x: 0, y: 0, width: frozen.image.width, height: frozen.image.height)
        let clamped = pixelRect.intersection(bounds)
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else { return nil }
        return frozen.image.cropping(to: clamped)
    }

    private static func capture(for screen: NSScreen) async -> Frozen? {
        guard let directDisplayIDValue = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let directDisplayID = CGDirectDisplayID(directDisplayIDValue.uint32Value)
        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first(where: { $0.displayID == directDisplayID })
                  ?? content.displays.first else {
                return nil
            }

            // Exclude Talkie's own floating chrome (HUD bar, selection overlay)
            // so an already-visible bar isn't baked into the still even when the
            // grab lands after the bar appears. Layer 0 windows (normal app
            // windows) are kept so the still still shows real content.
            let ownBundleID = Bundle.main.bundleIdentifier
            let ownChrome = content.windows.filter {
                $0.owningApplication?.bundleIdentifier == ownBundleID && $0.windowLayer > 0
            }

            let filter = SCContentFilter(display: display, excludingWindows: ownChrome)
            let config = SCStreamConfiguration()
            let scale = screen.backingScaleFactor
            config.width = max(1, Int((screen.frame.width * scale).rounded(.toNearestOrAwayFromZero)))
            config.height = max(1, Int((screen.frame.height * scale).rounded(.toNearestOrAwayFromZero)))
            config.scalesToFit = false
            config.showsCursor = false
            config.capturesAudio = false
            let cg = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            return Frozen(image: cg, screenFrame: screen.frame, scale: scale)
        } catch {
            return nil
        }
    }
}
