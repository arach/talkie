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
        preselectedRegion: CGRect? = nil,
        preselectedRegionBehavior: RegionCaptureBehavior = .visibleContent
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
        var captureMode = mode.rawValue

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
            guard let result = await captureRegion(
                preselectedRect: preselectedRegion,
                preselectedBehavior: preselectedRegionBehavior
            ) else {
                if captureHotPathLoggingEnabled {
                    log.info("Standalone screenshot capture cancelled or failed")
                }
                return nil
            }
            image = result.image
            captureRect = result.selection.rect
            captureMode = result.selection.behavior.captureModeValue
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
            captureMode: captureMode,
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

    private func captureRegion(
        preselectedRect: CGRect? = nil,
        preselectedBehavior: RegionCaptureBehavior = .visibleContent
    ) async -> (image: CGImage, selection: CaptureRegionSelection)? {
        // The freeze still (if any) is consumed by this region capture; release
        // it on exit so a stale frame can't leak into the next capture.
        defer { CaptureFreezeStore.shared.clear() }

        let selection: CaptureRegionSelection
        if let preselectedRect {
            selection = CaptureRegionSelection(rect: preselectedRect, behavior: preselectedBehavior)
        } else {
            let overlay = ScreenCaptureOverlay()
            guard let selected = await overlay.selectRegionSelection(
                freezesDesktop: true,
                allowsScrollingCapture: true
            ) else {
                return nil
            }
            selection = selected
        }

        if selection.behavior == .scrollingContent {
            // A frozen selection still cannot participate in a scrolling
            // sequence. Start from the live pixels after the overlay closes.
            CaptureFreezeStore.shared.clear()
            guard let image = await captureScrollingRegion(screenRect: selection.rect) else {
                log.error("Scrolling region capture failed")
                return nil
            }
            return (image: image, selection: selection)
        }

        // Freeze-first: crop from the still captured before the overlay stole
        // focus, so a menu/popover that closed when the crosshair appeared is
        // still in the shot. Falls back to a live read when there's no still
        // (capture failed or the mouse crossed displays).
        if let frozen = await CaptureFreezeStore.shared.crop(screenRect: selection.rect) {
            return (image: frozen, selection: selection)
        }

        let image = await captureScreenRegion(screenRect: selection.rect)
        guard let image else {
            log.error("Region capture failed: unable to capture selected rect")
            return nil
        }

        return (image: image, selection: selection)
    }

    // MARK: - Scrolling Region Capture

    private func captureScrollingRegion(screenRect: CGRect) async -> CGImage? {
        let progressOverlay = ScrollingCaptureProgressOverlay(screenRect: screenRect)
        progressOverlay.show()
        defer { progressOverlay.dismiss() }

        let originalPointer = CGEvent(source: nil)?.location
        if let target = quartzPoint(forCocoaPoint: CGPoint(x: screenRect.midX, y: screenRect.midY)) {
            CGWarpMouseCursorPosition(target)
        }
        defer {
            if let originalPointer {
                CGWarpMouseCursorPosition(originalPointer)
            }
        }

        let stopSignal = ScrollingCaptureStopSignal()
        let escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in stopSignal.requestStop() }
        }
        defer {
            if let escapeMonitor {
                NSEvent.removeMonitor(escapeMonitor)
            }
        }

        // Generic scroll views do not expose a portable content offset, so
        // drive a few large upward scrolls to clamp at their beginning.
        let boundaryDistance = max(Int(screenRect.height * 12), 12_000)
        for _ in 0..<3 {
            guard postScroll(deltaY: boundaryDistance) else { break }
            try? await Task.sleep(for: .milliseconds(70))
        }
        try? await Task.sleep(for: .milliseconds(350))

        guard let firstFrame = await captureScreenRegion(
            screenRect: screenRect,
            excludingWindowIDs: progressOverlay.excludedWindowIDs
        ) else {
            return nil
        }
        progressOverlay.markViewportCaptured(1)
        var stitcher = ScrollingCaptureStitcher(firstFrame: firstFrame)
        let pageDistance = max(Int(screenRect.height * 0.62), 80)

        for viewportIndex in 2...40 {
            if stopSignal.isStopped { break }
            guard await postEasedScroll(deltaY: -pageDistance) else { break }
            try? await Task.sleep(for: .milliseconds(290))
            guard !stopSignal.isStopped,
                  let nextFrame = await captureScreenRegion(
                    screenRect: screenRect,
                    excludingWindowIDs: progressOverlay.excludedWindowIDs
                  ) else {
                break
            }

            var appendResult = stitcher.append(nextFrame)
            if appendResult == .unaligned {
                // Lazy content and momentum can still be settling at the first
                // read. Give it one quiet retry before ending at the last
                // verified seam rather than producing a corrupted composite.
                try? await Task.sleep(for: .milliseconds(250))
                if let settledFrame = await captureScreenRegion(
                    screenRect: screenRect,
                    excludingWindowIDs: progressOverlay.excludedWindowIDs
                ) {
                    appendResult = stitcher.append(settledFrame)
                }
            }

            switch appendResult {
            case .appended:
                progressOverlay.markViewportCaptured(viewportIndex)
                continue
            case .unchanged, .unaligned, .sizeChanged, .reachedPixelLimit:
                return stitcher.makeImage()
            }
        }

        return stitcher.makeImage()
    }

    private func postEasedScroll(deltaY: Int) async -> Bool {
        let deltas = ScrollingCaptureMotion.easeOutDeltas(totalDistance: deltaY)
        guard !deltas.isEmpty else { return false }

        for (index, delta) in deltas.enumerated() {
            guard postScroll(deltaY: delta) else { return false }
            if index < deltas.count - 1 {
                try? await Task.sleep(for: .milliseconds(15))
            }
        }
        return true
    }

    private func postScroll(deltaY: Int) -> Bool {
        let bounded = min(max(deltaY, Int(Int32.min)), Int(Int32.max))
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 1,
                wheel1: Int32(bounded),
                wheel2: 0,
                wheel3: 0
              ) else {
            return false
        }
        event.post(tap: .cghidEventTap)
        return true
    }

    private func quartzPoint(forCocoaPoint point: CGPoint) -> CGPoint? {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }),
              let displayIDValue = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayBounds = CGDisplayBounds(CGDirectDisplayID(displayIDValue.uint32Value))
        return CGPoint(
            x: displayBounds.minX + point.x - screen.frame.minX,
            y: displayBounds.minY + screen.frame.maxY - point.y
        )
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
        var granted = CGPreflightScreenCaptureAccess()

        if !granted {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                granted = true
            } catch {
                granted = CGPreflightScreenCaptureAccess()
                log.warning(
                    "ScreenCaptureKit permission probe failed",
                    detail: "error=\(error.localizedDescription), granted=\(granted)"
                )
            }
        }

        return granted
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

    public func captureScreenRegion(
        screenRect: CGRect,
        excludingWindowIDs: [CGWindowID] = []
    ) async -> CGImage? {
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

            let excludedIDs = Set(excludingWindowIDs)
            let excludedWindows = content.windows.filter { excludedIDs.contains($0.windowID) }
            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
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

@MainActor
private final class ScrollingCaptureStopSignal {
    private(set) var isStopped = false

    func requestStop() {
        isStopped = true
    }
}
#endif
