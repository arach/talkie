#if os(macOS)
import AppKit
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Shared screenshot capture runtime.
///
/// This deliberately preserves Talkie's capture-facing interface so the caller
/// can move from Talkie.app to TalkieAgent without changing asset shape:
/// `captureStandalone(mode:preselectedRegion:)` returns PNG bytes, dimensions,
/// and the same contextual metadata fields the tray manifest already stores.
@MainActor
public final class ScreenshotCaptureService {
    public static let shared = ScreenshotCaptureService()

    private let log = Log(.system)
    private var lastPermissionCheckAt: Date = .distantPast
    private var lastPermissionCheckResult = false
    private let permissionCacheInterval: TimeInterval = 30
    private let captureHotPathLoggingEnabled = ProcessInfo.processInfo.environment["CAPTURE_PERF"] == "1"

    private init() {}

    public func captureStandalone(
        mode: CaptureMode,
        preselectedRegion: CGRect? = nil
    ) async -> CaptureResult? {
        guard await hasScreenRecordingPermission() else {
            log.warning(
                "Standalone screenshot blocked: Screen Recording permission missing",
                detail: "mode=\(mode.rawValue)"
            )
            showPermissionAlert()
            return nil
        }

        // Snapshot the active app before any selection overlay steals focus —
        // region/fullscreen captures otherwise carry no app context at all.
        let contextApp = Self.frontmostContextApp()

        let image: CGImage
        var windowTitle: String?
        var appName: String?
        var appBundleID: String?
        var displayName: String?
        var captureRect: CGRect?

        switch mode {
        case .fullscreen:
            guard let result = await captureFullscreen() else {
                if captureHotPathLoggingEnabled {
                    log.info("Standalone screenshot capture cancelled or failed")
                }
                return nil
            }
            image = result.image
            displayName = result.displayName
            captureRect = result.rect
        case .region:
            guard let result = await captureRegion(preselectedRect: preselectedRegion) else {
                if captureHotPathLoggingEnabled {
                    log.info("Standalone screenshot capture cancelled or failed")
                }
                return nil
            }
            image = result.image
            captureRect = result.rect
        case .window:
            guard let result = await captureWindow() else {
                if captureHotPathLoggingEnabled {
                    log.info("Standalone screenshot capture cancelled or failed")
                }
                return nil
            }
            image = result.image
            windowTitle = result.windowTitle
            appName = result.appName
            appBundleID = result.appBundleID
        }

        // Region/fullscreen (and window captures missing owner info) fall back
        // to the frontmost app captured before the overlay appeared.
        if appName == nil { appName = contextApp.name }
        if appBundleID == nil { appBundleID = contextApp.bundleID }
        let capturedAt = Date()

        async let encodedData = encodePNG(image)
        async let previewImage = previewThumbnail(for: image)

        guard let data = await encodedData else {
            log.error("Failed to encode standalone screenshot as PNG")
            return nil
        }
        let thumbnail = await previewImage

        if captureHotPathLoggingEnabled {
            log.info("Standalone screenshot captured: \(image.width)x\(image.height) mode=\(mode.rawValue)")
        }
        return CaptureResult(
            data: data,
            image: image,
            previewImage: thumbnail,
            capturedAt: capturedAt,
            width: image.width,
            height: image.height,
            windowTitle: windowTitle,
            appName: appName,
            appBundleID: appBundleID,
            displayName: displayName,
            captureRect: captureRect
        )
    }

    // MARK: - Fullscreen Capture

    private func captureFullscreen() async -> (image: CGImage, displayName: String?, rect: CGRect)? {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else {
            log.error("Fullscreen capture failed: no screen available")
            return nil
        }

        let image = await captureScreenRegion(screenRect: screen.frame)
        guard let image else {
            log.error("Fullscreen capture failed: unable to create display image")
            return nil
        }

        return (image: image, displayName: screen.localizedName, rect: screen.frame)
    }

    // MARK: - Region Capture

    private func captureRegion(preselectedRect: CGRect? = nil) async -> (image: CGImage, rect: CGRect)? {
        // The freeze still (if any) is consumed by this region capture; release
        // it on exit so a stale frame can't leak into the next capture.
        defer { CaptureFreezeStore.shared.clear() }

        let selectedRect: CGRect
        if let preselectedRect {
            selectedRect = preselectedRect
        } else {
            let overlay = ScreenCaptureOverlay()
            guard let rect = await overlay.selectRegion(freezesDesktop: true) else {
                return nil
            }
            selectedRect = rect
        }

        // Freeze-first: crop from the still captured before the overlay stole
        // focus, so a menu/popover that closed when the crosshair appeared is
        // still in the shot. Falls back to a live read when there's no still
        // (capture failed or the mouse crossed displays).
        if let frozen = await CaptureFreezeStore.shared.crop(screenRect: selectedRect) {
            return (image: frozen, rect: selectedRect)
        }

        let image = await captureScreenRegion(screenRect: selectedRect)
        guard let image else {
            log.error("Region capture failed: unable to capture selected rect")
            return nil
        }

        return (image: image, rect: selectedRect)
    }

    // MARK: - Window Capture

    private func captureWindow() async -> (image: CGImage, windowTitle: String?, appName: String?, appBundleID: String?)? {
        let overlay = ScreenCaptureOverlay()
        guard let windowID = await overlay.selectWindow() else {
            return nil
        }

        // Query window metadata while the window is still around.
        let meta = windowMetadata(for: windowID)

        let image = await captureWindowImage(windowID: windowID)
        guard let image else {
            log.error("Window capture failed: unable to capture window \(windowID)")
            return nil
        }

        return (image: image, windowTitle: meta.title, appName: meta.appName, appBundleID: meta.appBundleID)
    }

    // MARK: - Permission

    public func hasScreenRecordingPermission() async -> Bool {
        // Fast path: CoreGraphics preflight is synchronous and much cheaper
        // than fetching shareable content.
        let now = Date()
        if now.timeIntervalSince(lastPermissionCheckAt) < permissionCacheInterval {
            return lastPermissionCheckResult
        }

        let hasPermission = CGPreflightScreenCaptureAccess()
        lastPermissionCheckAt = now
        lastPermissionCheckResult = hasPermission
        return hasPermission
    }

    public func requestPermission() async -> Bool {
        _ = CGRequestScreenCaptureAccess()
        return CGPreflightScreenCaptureAccess()
    }

    public func captureWindowImage(windowID: CGWindowID) async -> CGImage? {
        do {
            let content = try await SCShareableContent.current
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                log.error("Window capture failed: no ScreenCaptureKit window for id \(windowID)")
                return nil
            }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            config.width = max(1, Int((filter.contentRect.width * scale).rounded(.toNearestOrAwayFromZero)))
            config.height = max(1, Int((filter.contentRect.height * scale).rounded(.toNearestOrAwayFromZero)))
            config.scalesToFit = false
            config.showsCursor = false
            config.capturesAudio = false

            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
        } catch {
            log.error("Window capture failed: \(error.localizedDescription)")
            return nil
        }
    }

    public func captureScreenRegion(screenRect: CGRect) async -> CGImage? {
        let midPoint = NSPoint(x: screenRect.midX, y: screenRect.midY)
        guard let nsScreen = NSScreen.screens.first(where: { NSMouseInRect(midPoint, $0.frame, false) })
                ?? NSScreen.main else {
            log.error("Region capture failed: no screen found for region \(String(describing: screenRect))")
            return nil
        }

        guard let directDisplayIDValue = nsScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            log.error("Region capture failed: no display ID for screen")
            return nil
        }

        let screenFrame = nsScreen.frame
        let displayLocalRect = CGRect(
            x: screenRect.origin.x - screenFrame.origin.x,
            y: screenFrame.height - (screenRect.origin.y - screenFrame.origin.y) - screenRect.height,
            width: screenRect.width,
            height: screenRect.height
        )

        do {
            let directDisplayID = CGDirectDisplayID(directDisplayIDValue.uint32Value)
            let content = try await SCShareableContent.current
            guard let display = content.displays.first(where: { $0.displayID == directDisplayID })
                  ?? content.displays.first else {
                log.error("Region capture failed: no ScreenCaptureKit display available")
                return nil
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            let scale = nsScreen.backingScaleFactor
            config.width = max(1, Int((screenRect.width * scale).rounded(.toNearestOrAwayFromZero)))
            config.height = max(1, Int((screenRect.height * scale).rounded(.toNearestOrAwayFromZero)))
            config.sourceRect = displayLocalRect
            config.scalesToFit = false
            config.showsCursor = false
            config.capturesAudio = false

            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
        } catch {
            log.error("Region capture failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "Talkie needs Screen Recording permission to capture screenshots. Please enable it in System Settings → Privacy & Security → Screen Recording."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Helpers

    /// Query window title, app name, and owning app's bundle id from a
    /// CGWindowID. The bundle id is resolved from the window's owner PID so
    /// the UI can disambiguate same-named apps and resolve an icon.
    private func windowMetadata(for windowID: CGWindowID) -> (title: String?, appName: String?, appBundleID: String?) {
        guard let infoList = CGWindowListCreateDescriptionFromArray([windowID] as CFArray) as? [[String: Any]],
              let info = infoList.first else {
            return (nil, nil, nil)
        }
        let title = info[kCGWindowName as String] as? String
        let appName = info[kCGWindowOwnerName as String] as? String
        var bundleID: String?
        if let pid = info[kCGWindowOwnerPID as String] as? pid_t {
            bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }
        return (title, appName, bundleID)
    }

    /// The app the user was working in when capture was invoked, resolved
    /// from the frontmost application. Region/fullscreen captures have no
    /// window owner, so this is the only "what was on screen" signal. The
    /// current process is excluded so a capture triggered from Agent UI doesn't
    /// record Agent as the source.
    private static func frontmostContextApp() -> (name: String?, bundleID: String?) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return (nil, nil)
        }
        return (app.localizedName, app.bundleIdentifier)
    }

    /// Encode a CGImage as PNG off-main to avoid UI hitches during direct hotkey captures.
    private func encodePNG(_ image: CGImage) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            Self.pngData(from: image)
        }.value
    }

    private func previewThumbnail(for image: CGImage) async -> CGImage {
        await Task.detached(priority: .userInitiated) {
            Self.downscaledImage(from: image, maxPixelLength: 440) ?? image
        }.value
    }

    nonisolated private static func pngData(from image: CGImage) -> Data? {
        autoreleasepool {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                data,
                UTType.png.identifier as CFString,
                1,
                nil
            ) else {
                return nil
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                return nil
            }
            return data as Data
        }
    }

    nonisolated private static func downscaledImage(from image: CGImage, maxPixelLength: CGFloat) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let longestEdge = max(width, height)
        guard longestEdge > 0 else { return nil }

        let scale = min(1, maxPixelLength / longestEdge)
        let targetWidth = max(Int((width * scale).rounded(.toNearestOrEven)), 1)
        let targetHeight = max(Int((height * scale).rounded(.toNearestOrEven)), 1)

        let alphaInfo: CGImageAlphaInfo = image.alphaInfo == .none ? .noneSkipLast : .premultipliedLast
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: alphaInfo.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage()
    }
}
#endif
