//
//  ScreenshotCaptureService.swift
//  Talkie
//
//  Captures screenshots during memo recording.
//  Supports fullscreen, region (drag), and window (click) capture modes.
//

import Foundation
import AppKit
import ImageIO
import ScreenCaptureKit
import TalkieKit
import UniformTypeIdentifiers

enum ScreenshotCapturePreset: String, CaseIterable, Codable {
    case agent
    case balanced
    case archive

    var label: String {
        switch self {
        case .agent: return "Agent"
        case .balanced: return "Balanced"
        case .archive: return "Archive"
        }
    }

    var detail: String {
        // Note: the saved screenshot is always full-resolution (for markup /
        // preview). This preset only governs the downscaled copy sent to AI
        // workflows (VLM description, OCR, markup agent).
        switch self {
        case .agent: return "Smallest AI payloads. Sends a 1280px copy to models."
        case .balanced: return "Sharper AI input (2200px). Larger model payloads."
        case .archive: return "Full-resolution AI input. Largest model payloads."
        }
    }

    /// Max edge of the image handed to AI workflows. `nil` = send full size.
    /// The stored canonical screenshot is unaffected (always full-res).
    var maxPixelLength: CGFloat? {
        switch self {
        case .agent: return 1280
        case .balanced: return 2200
        case .archive: return nil
        }
    }

    var sizeSummary: String {
        switch self {
        case .agent: return "AI image ≤ 1280 px"
        case .balanced: return "AI image ≤ 2200 px"
        case .archive: return "AI image full size"
        }
    }
}

enum CaptureMode: String, Sendable {
    case region      // User drags to select rectangle
    case fullscreen  // Entire display under cursor
    case window      // User clicks a window
}

/// Result of a screenshot capture, including image data and contextual metadata.
struct CaptureResult {
    let data: Data
    let image: CGImage
    let previewImage: CGImage
    let capturedAt: Date
    let width: Int
    let height: Int
    let windowTitle: String?
    let appName: String?
    let appBundleID: String?
    let displayName: String?
}

@MainActor
final class ScreenshotCaptureService {
    static let shared = ScreenshotCaptureService()
    private let log = Log(.system)
    private var lastPermissionCheckAt: Date = .distantPast
    private var lastPermissionCheckResult = false
    private let permissionCacheInterval: TimeInterval = 30
    private let captureHotPathLoggingEnabled = ProcessInfo.processInfo.environment["CAPTURE_PERF"] == "1"
    private var didPrewarmPipeline = false
    private var capturePreset: ScreenshotCapturePreset { SettingsManager.shared.screenshotCapturePreset }
    private init() {}

    // MARK: - Public API

    /// Capture a screenshot and save it to storage.
    ///
    /// - Parameters:
    ///   - mode: Capture mode (region, fullscreen, window)
    ///   - recordingId: The recording this screenshot belongs to
    ///   - recordingStartTime: When the recording started (for calculating timestamp offset)
    /// - Returns: Screenshot metadata, or nil if capture was cancelled or failed
    func capture(
        mode: CaptureMode,
        recordingId: UUID,
        recordingStartTime: Date,
        preselectedRegion: CGRect? = nil
    ) async -> RecordingScreenshot? {
        // Check permission first
        CapturePerformanceMonitor.shared.mark("permission.check.begin")
        guard await hasScreenRecordingPermission() else {
            CapturePerformanceMonitor.shared.mark("permission.check.denied")
            log.warning(
                "Screenshot capture blocked: Screen Recording permission missing",
                detail: "mode=\(mode.rawValue), recordingId=\(recordingId.uuidString)"
            )
            showPermissionAlert()
            return nil
        }
        CapturePerformanceMonitor.shared.mark("permission.check.complete")

        // Snapshot the active app before any selection overlay steals focus —
        // region/fullscreen captures otherwise carry no app context at all.
        let contextApp = Self.frontmostContextApp()

        let image: CGImage
        var windowTitle: String?
        var appName: String?
        var appBundleID: String?
        var displayName: String?

        switch mode {
        case .fullscreen:
            guard let result = await captureFullscreen() else {
                if captureHotPathLoggingEnabled {
                    log.info("Screenshot capture cancelled or failed")
                }
                CapturePerformanceMonitor.shared.mark("capture.cancelled")
                return nil
            }
            image = result.image
            displayName = result.displayName
        case .region:
            guard let result = await captureRegion(preselectedRect: preselectedRegion) else {
                if captureHotPathLoggingEnabled {
                    log.info("Screenshot capture cancelled or failed")
                }
                CapturePerformanceMonitor.shared.mark("capture.cancelled")
                return nil
            }
            image = result
        case .window:
            guard let result = await captureWindow() else {
                if captureHotPathLoggingEnabled {
                    log.info("Screenshot capture cancelled or failed")
                }
                CapturePerformanceMonitor.shared.mark("capture.cancelled")
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
        let timestampMs = Int(capturedAt.timeIntervalSince(recordingStartTime) * 1000)
        CapturePerformanceMonitor.shared.mark("capture.image.complete")

        // Canonical screenshot is stored at full resolution so markup /
        // preview stay crisp. Downscaling now happens only on the AI path.
        let storedImage = image
        let previewImage = await previewThumbnail(for: image)

        // Show floating preview
        CapturePerformanceMonitor.shared.mark("preview.show.begin")
        let previewID = ScreenshotPreviewPanel.shared.show(
            thumbnail: previewImage,
            sourceWidth: image.width,
            sourceHeight: image.height
        )
        CapturePerformanceMonitor.shared.mark("preview.show.complete")

        // Convert to PNG data
        CapturePerformanceMonitor.shared.mark("encode.begin")
        guard let data = await encodePNG(storedImage) else {
            CapturePerformanceMonitor.shared.mark("encode.failed")
            log.error("Failed to encode screenshot as PNG")
            return nil
        }
        CapturePerformanceMonitor.shared.mark("encode.complete")

        // Save to permanent storage
        CapturePerformanceMonitor.shared.mark("storage.save.begin")
        guard let savedURL = ScreenshotStorage.save(
            data,
            recordingId: recordingId,
            timestampMs: timestampMs,
            captureMode: mode.rawValue,
            width: storedImage.width,
            height: storedImage.height,
            windowTitle: windowTitle,
            appName: appName,
            displayName: displayName
        ) else {
            CapturePerformanceMonitor.shared.mark("storage.save.failed")
            return nil
        }
        CapturePerformanceMonitor.shared.mark("storage.save.complete")
        ScreenshotPreviewPanel.shared.attachFileURL(savedURL, to: previewID)

        let filename = savedURL.lastPathComponent
        if captureHotPathLoggingEnabled {
            log.info("Screenshot captured: \(filename) (\(storedImage.width)x\(storedImage.height)) mode=\(mode.rawValue) preset=\(capturePreset.rawValue)")
        }

        return RecordingScreenshot(
            filename: filename,
            timestampMs: timestampMs,
            captureMode: mode.rawValue,
            width: storedImage.width,
            height: storedImage.height,
            windowTitle: windowTitle,
            appName: appName,
            appBundleID: appBundleID,
            displayName: displayName
        )
    }

    /// Capture a standalone screenshot (not tied to a recording).
    /// Returns CaptureResult with PNG data, dimensions, and contextual metadata, or nil if cancelled/failed.
    func captureStandalone(mode: CaptureMode, preselectedRegion: CGRect? = nil) async -> CaptureResult? {
        CapturePerformanceMonitor.shared.mark("permission.check.begin")
        guard await hasScreenRecordingPermission() else {
            CapturePerformanceMonitor.shared.mark("permission.check.denied")
            log.warning(
                "Standalone screenshot blocked: Screen Recording permission missing",
                detail: "mode=\(mode.rawValue)"
            )
            showPermissionAlert()
            return nil
        }
        CapturePerformanceMonitor.shared.mark("permission.check.complete")

        // Snapshot the active app before any selection overlay steals focus —
        // region/fullscreen captures otherwise carry no app context at all.
        let contextApp = Self.frontmostContextApp()

        let image: CGImage
        var windowTitle: String?
        var appName: String?
        var appBundleID: String?
        var displayName: String?

        switch mode {
        case .fullscreen:
            guard let result = await captureFullscreen() else {
                if captureHotPathLoggingEnabled {
                    log.info("Standalone screenshot capture cancelled or failed")
                }
                CapturePerformanceMonitor.shared.mark("capture.cancelled")
                return nil
            }
            image = result.image
            displayName = result.displayName
        case .region:
            guard let result = await captureRegion(preselectedRect: preselectedRegion) else {
                if captureHotPathLoggingEnabled {
                    log.info("Standalone screenshot capture cancelled or failed")
                }
                CapturePerformanceMonitor.shared.mark("capture.cancelled")
                return nil
            }
            image = result
        case .window:
            guard let result = await captureWindow() else {
                if captureHotPathLoggingEnabled {
                    log.info("Standalone screenshot capture cancelled or failed")
                }
                CapturePerformanceMonitor.shared.mark("capture.cancelled")
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
        CapturePerformanceMonitor.shared.mark("capture.image.complete")

        // Canonical screenshot stored full-resolution; AI downscale is separate.
        let storedImage = image

        CapturePerformanceMonitor.shared.mark("encode.begin")
        async let encodedData = encodePNG(storedImage)
        async let previewImage = previewThumbnail(for: storedImage)

        guard let data = await encodedData else {
            CapturePerformanceMonitor.shared.mark("encode.failed")
            log.error("Failed to encode standalone screenshot as PNG")
            return nil
        }
        let thumbnail = await previewImage
        CapturePerformanceMonitor.shared.mark("encode.complete")

        if captureHotPathLoggingEnabled {
            log.info("Standalone screenshot captured: \(storedImage.width)x\(storedImage.height) mode=\(mode.rawValue) preset=\(capturePreset.rawValue)")
        }
        return CaptureResult(
            data: data,
            image: image,
            previewImage: thumbnail,
            capturedAt: capturedAt,
            width: storedImage.width,
            height: storedImage.height,
            windowTitle: windowTitle,
            appName: appName,
            appBundleID: appBundleID,
            displayName: displayName
        )
    }

    /// Warm local PNG encode path once without touching ScreenCaptureKit or TCC.
    func prewarmPipelineIfNeeded() {
        guard !didPrewarmPipeline else { return }
        didPrewarmPipeline = true

        Task.detached(priority: .utility) {
            if let image = Self.makePrewarmImage() {
                _ = Self.pngData(from: image)
            }
        }
        if captureHotPathLoggingEnabled {
            log.debug("Screenshot encode path prewarmed")
        }
    }

    // MARK: - Fullscreen Capture

    /// Capture the entire display under the mouse cursor.
    private func captureFullscreen() async -> (image: CGImage, displayName: String?)? {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else {
            log.error("Fullscreen capture failed: no screen available")
            return nil
        }

        CapturePerformanceMonitor.shared.mark("capture.fullscreen.read.begin")
        let image = await captureScreenRegion(screenRect: screen.frame)
        guard let image else {
            CapturePerformanceMonitor.shared.mark("capture.fullscreen.read.failed")
            log.error("Fullscreen capture failed: unable to create display image")
            return nil
        }
        CapturePerformanceMonitor.shared.mark("capture.fullscreen.read.complete")

        return (image: image, displayName: screen.localizedName)
    }

    // MARK: - Region Capture

    /// Show overlay for region selection, then crop the full display capture.
    private func captureRegion(preselectedRect: CGRect? = nil) async -> CGImage? {
        let selectedRect: CGRect
        if let preselectedRect {
            selectedRect = preselectedRect
        } else {
            let overlay = ScreenCaptureOverlay()
            CapturePerformanceMonitor.shared.mark("overlay.region.begin")
            guard let rect = await overlay.selectRegion() else {
                CapturePerformanceMonitor.shared.mark("overlay.region.cancelled")
                return nil
            }
            selectedRect = rect
        }
        CapturePerformanceMonitor.shared.mark("overlay.region.selected")

        CapturePerformanceMonitor.shared.mark("capture.region.read.begin")
        let image = await captureScreenRegion(screenRect: selectedRect)
        guard let image else {
            CapturePerformanceMonitor.shared.mark("capture.region.read.failed")
            log.error("Region capture failed: unable to capture selected rect")
            return nil
        }
        CapturePerformanceMonitor.shared.mark("capture.region.read.complete")

        return image
    }

    // MARK: - Window Capture

    /// Show overlay for window selection, then capture that window.
    private func captureWindow() async -> (image: CGImage, windowTitle: String?, appName: String?, appBundleID: String?)? {
        let overlay = ScreenCaptureOverlay()
        CapturePerformanceMonitor.shared.mark("overlay.window.begin")
        guard let windowID = await overlay.selectWindow() else {
            CapturePerformanceMonitor.shared.mark("overlay.window.cancelled")
            return nil
        }
        CapturePerformanceMonitor.shared.mark("overlay.window.selected")

        // Query window metadata while the window is still around
        let meta = windowMetadata(for: windowID)

        CapturePerformanceMonitor.shared.mark("capture.window.read.begin")
        let image = await captureWindowImage(windowID: windowID)
        guard let image else {
            CapturePerformanceMonitor.shared.mark("capture.window.read.failed")
            log.error("Window capture failed: unable to capture window \(windowID)")
            return nil
        }
        CapturePerformanceMonitor.shared.mark("capture.window.read.complete")

        return (image: image, windowTitle: meta.title, appName: meta.appName, appBundleID: meta.appBundleID)
    }

    // MARK: - Permission

    private func hasScreenRecordingPermission() async -> Bool {
        // Fast path: CoreGraphics preflight is synchronous and much cheaper than fetching shareable content.
        let now = Date()
        if now.timeIntervalSince(lastPermissionCheckAt) < permissionCacheInterval {
            return lastPermissionCheckResult
        }

        let hasPermission = CGPreflightScreenCaptureAccess()
        lastPermissionCheckAt = now
        lastPermissionCheckResult = hasPermission
        return hasPermission
    }

    func captureWindowImage(windowID: CGWindowID) async -> CGImage? {
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

    func captureScreenRegion(screenRect: CGRect) async -> CGImage? {
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
    /// window owner, so this is the only "what was on screen" signal. Talkie's
    /// own agent is excluded so a capture triggered from Talkie's UI doesn't
    /// record Talkie as the source.
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

    /// Max edge for the AI-bound copy of a screenshot, from the current
    /// capture preset (default `.agent` → 1280). `nil` means send full size.
    /// Reads UserDefaults directly so it's safe to call off the main actor
    /// from the various AI encoders.
    nonisolated static var aiMaxPixelLength: CGFloat? {
        let raw = UserDefaults.standard.string(forKey: "screenshotCapturePreset")
        let preset = raw.flatMap(ScreenshotCapturePreset.init(rawValue:)) ?? .agent
        return preset.maxPixelLength
    }

    /// Load a screenshot file and JPEG-encode it for an AI workflow,
    /// downscaling to `maxEdge` (long edge) first when the source is larger.
    /// The canonical on-disk PNG is untouched — this is the derived copy.
    nonisolated static func aiJPEGData(
        for url: URL,
        maxEdge: CGFloat? = ScreenshotCaptureService.aiMaxPixelLength,
        quality: CGFloat = 0.85
    ) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let image: CGImage?
        if let maxEdge {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(maxEdge.rounded())
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let cgImage = image else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            cgImage,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
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

    nonisolated private static func makePrewarmImage() -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context.makeImage()
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
final class CapturePerformanceMonitor {
    static let shared = CapturePerformanceMonitor()

    private struct Mark {
        let name: String
        let atNs: UInt64
    }

    private struct Session {
        let id: UInt64
        let trigger: String
        var mode: String
        let startedAtNs: UInt64
        var marks: [Mark]
        var frameIntervalsNs: [UInt64]
        var droppedFrameEstimate: Int
        var hitchCount: Int
        var maxFrameIntervalNs: UInt64
        var lastTickNs: UInt64?
        var timer: DispatchSourceTimer?
    }

    private let log = Log(.ui)
    private let isEnabled: Bool = {
        let env = ProcessInfo.processInfo.environment["CAPTURE_PERF"]
        if env == "0" { return false }
        if env == "1" { return true }
        return UserDefaults.standard.bool(forKey: "capturePerfEnabled")
    }()
    private let expectedFrameIntervalNs: UInt64 = 16_666_667
    private let hitchThresholdNs: UInt64 = 33_333_334
    private let maxFrameSamples = 720

    private var activeSession: Session?
    private var nextSessionId: UInt64 = 0

    private init() {}

    func beginSession(trigger: String, mode: String) {
        guard isEnabled else { return }

        if let inFlight = activeSession {
            finish(session: inFlight, outcome: "interrupted")
            activeSession = nil
        }

        nextSessionId &+= 1
        let now = DispatchTime.now().uptimeNanoseconds

        var session = Session(
            id: nextSessionId,
            trigger: trigger,
            mode: mode,
            startedAtNs: now,
            marks: [Mark(name: "session.begin", atNs: now)],
            frameIntervalsNs: [],
            droppedFrameEstimate: 0,
            hitchCount: 0,
            maxFrameIntervalNs: 0,
            lastTickNs: nil,
            timer: nil
        )

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + .milliseconds(16),
            repeating: .milliseconds(16),
            leeway: .milliseconds(2)
        )
        timer.setEventHandler { [weak self] in
            self?.recordFrameSample()
        }
        session.timer = timer
        activeSession = session
        timer.resume()
    }

    func updateMode(_ mode: String) {
        guard isEnabled, var session = activeSession else { return }
        session.mode = mode
        activeSession = session
    }

    func mark(_ name: String) {
        guard isEnabled, var session = activeSession else { return }
        session.marks.append(Mark(name: name, atNs: DispatchTime.now().uptimeNanoseconds))
        activeSession = session
    }

    func endSession(outcome: String) {
        guard isEnabled, let session = activeSession else { return }
        finish(session: session, outcome: outcome)
        activeSession = nil
    }

    private func recordFrameSample() {
        guard isEnabled, var session = activeSession else { return }
        let now = DispatchTime.now().uptimeNanoseconds

        defer {
            session.lastTickNs = now
            activeSession = session
        }

        guard let lastTickNs = session.lastTickNs else { return }
        let deltaNs = now &- lastTickNs
        if deltaNs == 0 { return }

        if session.frameIntervalsNs.count < maxFrameSamples {
            session.frameIntervalsNs.append(deltaNs)
        }

        if deltaNs > session.maxFrameIntervalNs {
            session.maxFrameIntervalNs = deltaNs
        }
        if deltaNs > hitchThresholdNs {
            session.hitchCount += 1
        }

        let expectedFrames = Int(deltaNs / expectedFrameIntervalNs)
        if expectedFrames > 1 {
            session.droppedFrameEstimate += expectedFrames - 1
        }
    }

    private func finish(session: Session, outcome: String) {
        var completed = session
        completed.timer?.setEventHandler {}
        completed.timer?.cancel()
        completed.timer = nil

        let endedAtNs = DispatchTime.now().uptimeNanoseconds
        let totalNs = endedAtNs &- completed.startedAtNs
        let totalMs = toMilliseconds(totalNs)
        let fpsText = fpsString(from: completed.frameIntervalsNs)
        let p95Ms = percentile(completed.frameIntervalsNs, p: 0.95).map(toMilliseconds)
        let p99Ms = percentile(completed.frameIntervalsNs, p: 0.99).map(toMilliseconds)
        let maxMs = toMilliseconds(completed.maxFrameIntervalNs)
        let phaseSummary = phaseSummaryText(marks: completed.marks, endNs: endedAtNs)

        let p95Text = p95Ms.map(formatOneDecimal) ?? "n/a"
        let p99Text = p99Ms.map(formatOneDecimal) ?? "n/a"
        let maxText = formatOneDecimal(maxMs)
        let droppedRatioText = droppedRatioText(
            dropped: completed.droppedFrameEstimate,
            totalNs: totalNs
        )

        log.info(
            "CapturePerf session=\(completed.id) trigger=\(completed.trigger) mode=\(completed.mode) " +
            "outcome=\(outcome) totalMs=\(formatOneDecimal(totalMs)) fps=\(fpsText) " +
            "dropped~=\(completed.droppedFrameEstimate) (\(droppedRatioText)) hitches=\(completed.hitchCount) " +
            "p95Ms=\(p95Text) p99Ms=\(p99Text) maxMs=\(maxText) samples=\(completed.frameIntervalsNs.count) " +
            "phases=[\(phaseSummary)]"
        )
    }

    private func phaseSummaryText(marks: [Mark], endNs: UInt64) -> String {
        guard !marks.isEmpty else { return "none" }

        var parts: [String] = []
        parts.reserveCapacity(marks.count)

        for index in marks.indices {
            let current = marks[index]
            let nextNs = index + 1 < marks.count ? marks[index + 1].atNs : endNs
            let durationMs = toMilliseconds(nextNs &- current.atNs)
            parts.append("\(current.name)=\(formatOneDecimal(durationMs))ms")
        }

        return parts.joined(separator: ", ")
    }

    private func percentile(_ values: [UInt64], p: Double) -> UInt64? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * p).rounded(.toNearestOrAwayFromZero))
        return sorted[min(max(index, 0), sorted.count - 1)]
    }

    private func fpsString(from frameIntervalsNs: [UInt64]) -> String {
        guard !frameIntervalsNs.isEmpty else { return "n/a" }
        let totalNs = frameIntervalsNs.reduce(0, +)
        guard totalNs > 0 else { return "n/a" }
        let fps = Double(frameIntervalsNs.count) * 1_000_000_000 / Double(totalNs)
        return formatOneDecimal(fps)
    }

    private func droppedRatioText(dropped: Int, totalNs: UInt64) -> String {
        let expectedFrames = Double(totalNs) / Double(expectedFrameIntervalNs)
        guard expectedFrames > 0 else { return "n/a" }
        let ratio = (Double(dropped) / expectedFrames) * 100
        return "\(formatOneDecimal(ratio))%"
    }

    private func toMilliseconds(_ nanoseconds: UInt64) -> Double {
        Double(nanoseconds) / 1_000_000
    }

    private func formatOneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
