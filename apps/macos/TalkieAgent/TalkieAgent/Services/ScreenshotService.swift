import AppKit
import ScreenCaptureKit
import TalkieKit

/// Service for capturing screenshots of windows and screens
/// Requires Screen Recording permission (Privacy & Security > Screen Recording)
@available(macOS 14.0, *)
actor ScreenshotService {
    static let shared = ScreenshotService()

    private let log = Log(.system)

    // MARK: - Window Screenshots

    /// Capture a specific window by finding it in shareable content
    func captureWindow(windowID: CGWindowID) async -> NSImage? {
        log.info("Capturing window \(windowID)")

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                log.error("Window \(windowID) not found in shareable content")
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

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            log.info("Captured window \(windowID): \(image.width)x\(image.height)")
            return NSImage(cgImage: image, size: filter.contentRect.size)
        } catch {
            log.error("Failed to capture window \(windowID): \(error)")
            return nil
        }
    }

    /// Capture all windows for a specific app by bundle ID
    func captureApp(bundleId: String) async -> [NSImage] {
        log.info("Capturing all windows for \(bundleId)")

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            let appWindows = content.windows.filter { window in
                window.owningApplication?.bundleIdentifier == bundleId
            }

            var images: [NSImage] = []
            for window in appWindows {
                if let image = await captureWindow(windowID: window.windowID) {
                    images.append(image)
                }
            }

            log.info("Captured \(images.count) windows for \(bundleId)")
            return images
        } catch {
            log.error("Failed to capture app \(bundleId): \(error)")
            return []
        }
    }

    /// Find and capture terminal windows that might be running Claude
    func captureTerminalWindows() async -> [(windowID: CGWindowID, bundleId: String, title: String, image: NSImage)] {
        log.info("Capturing terminal windows")

        let terminalBundleIds = Set([
            "com.mitchellh.ghostty",
            "com.googlecode.iterm2",
            "com.apple.Terminal",
            "dev.warp.Warp-Stable",
            "com.github.wez.wezterm"
        ])

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            var results: [(windowID: CGWindowID, bundleId: String, title: String, image: NSImage)] = []

            for window in content.windows {
                guard let bundleId = window.owningApplication?.bundleIdentifier,
                      terminalBundleIds.contains(bundleId) else {
                    continue
                }

                // Skip tiny windows
                if window.frame.width < 100 || window.frame.height < 100 {
                    continue
                }

                let title = window.title ?? "Untitled"

                if let image = await captureWindow(windowID: window.windowID) {
                    results.append((windowID: window.windowID, bundleId: bundleId, title: title, image: image))
                }
            }

            log.info("Captured \(results.count) terminal windows")
            return results
        } catch {
            log.error("Failed to capture terminal windows: \(error)")
            return []
        }
    }

    // MARK: - Full Screen

    /// Capture the main display
    func captureMainDisplay(maxDimension: Int? = nil) async -> NSImage? {
        log.info("Capturing main display")

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            guard let display = content.displays.first else {
                log.error("No displays found")
                return nil
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            let nativeWidth = max(Int(display.width), 1)
            let nativeHeight = max(Int(display.height), 1)
            let scale: Double
            if let maxDimension, maxDimension > 0 {
                scale = min(1.0, Double(maxDimension) / Double(max(nativeWidth, nativeHeight)))
            } else {
                scale = 1.0
            }
            config.width = max(1, Int((Double(nativeWidth) * scale).rounded(.toNearestOrAwayFromZero)))
            config.height = max(1, Int((Double(nativeHeight) * scale).rounded(.toNearestOrAwayFromZero)))
            config.showsCursor = false
            config.capturesAudio = false

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            log.info("Captured display: \(image.width)x\(image.height)")
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        } catch {
            log.error("Failed to capture display: \(error)")
            return nil
        }
    }

    // MARK: - Window Discovery

    /// Get list of all visible windows with metadata
    func listWindows() async -> [WindowInfo] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            return content.windows.compactMap { window -> WindowInfo? in
                // Skip windows without apps or very small windows
                guard let app = window.owningApplication else { return nil }

                return WindowInfo(
                    windowID: window.windowID,
                    pid: app.processID,
                    bundleId: app.bundleIdentifier,
                    appName: app.applicationName,
                    title: window.title,
                    layer: Int(window.windowLayer),
                    bounds: window.frame,
                    isOnScreen: window.isOnScreen
                )
            }.filter { $0.layer == 0 } // Only normal windows
        } catch {
            log.error("Failed to list windows: \(error)")
            return []
        }
    }

    /// Find windows that likely contain Claude Code sessions
    func findClaudeWindows() async -> [WindowInfo] {
        let terminalBundleIds = Set([
            "com.mitchellh.ghostty",
            "com.googlecode.iterm2",
            "com.apple.Terminal",
            "dev.warp.Warp-Stable",
            "com.github.wez.wezterm"
        ])

        let windows = await listWindows()
        return windows.filter { window in
            guard let bundleId = window.bundleId else { return false }
            return terminalBundleIds.contains(bundleId)
        }
    }

    // MARK: - Image Encoding

    /// Convert NSImage to JPEG data
    func encodeAsJPEG(_ image: NSImage, quality: CGFloat = 0.8, maxDimension: CGFloat? = nil) -> Data? {
        guard let bitmap = bitmapRepresentation(for: image, maxDimension: maxDimension) else {
            return nil
        }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// Convert NSImage to PNG data
    func encodeAsPNG(_ image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func bitmapRepresentation(for image: NSImage, maxDimension: CGFloat?) -> NSBitmapImageRep? {
        guard let tiffData = image.tiffRepresentation,
              let sourceBitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        guard let maxDimension, maxDimension > 0 else {
            return sourceBitmap
        }

        let sourceWidth = max(CGFloat(sourceBitmap.pixelsWide), 1)
        let sourceHeight = max(CGFloat(sourceBitmap.pixelsHigh), 1)
        let scale = min(1.0, maxDimension / max(sourceWidth, sourceHeight))
        guard scale < 0.999 else {
            return sourceBitmap
        }

        let targetWidth = max(Int((sourceWidth * scale).rounded(.toNearestOrAwayFromZero)), 1)
        let targetHeight = max(Int((sourceHeight * scale).rounded(.toNearestOrAwayFromZero)), 1)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetWidth,
            pixelsHigh: targetHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return sourceBitmap
        }

        bitmap.size = NSSize(width: CGFloat(targetWidth), height: CGFloat(targetHeight))

        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current = context
        context?.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: CGFloat(targetWidth), height: CGFloat(targetHeight)),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        context?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    // MARK: - Permission Check

    /// Check if we have screen recording permission
    func hasScreenRecordingPermission() async -> Bool {
        let granted = CGPreflightScreenCaptureAccess()
        log.debug(
            "Screen recording permission preflight",
            detail: "\(permissionLogContext), granted=\(granted)"
        )
        return granted
    }

    /// Request screen recording permission by triggering the system prompt
    func requestPermission() async -> Bool {
        let before = CGPreflightScreenCaptureAccess()
        log.info(
            "Requesting screen recording permission",
            detail: "\(permissionLogContext), before=\(before)"
        )

        let requestGranted = before || CGRequestScreenCaptureAccess()
        let after = CGPreflightScreenCaptureAccess()

        log.info(
            "Screen recording permission request completed",
            detail: "\(permissionLogContext), before=\(before), requestGranted=\(requestGranted), after=\(after)"
        )
        return after
    }

    private var permissionLogContext: String {
        "bundle=\(Bundle.main.bundleIdentifier ?? "unknown"), executable=\(Bundle.main.executableURL?.path ?? "unknown")"
    }
}

// MARK: - Types

struct WindowInfo: Identifiable, Sendable {
    let windowID: CGWindowID
    let pid: pid_t
    let bundleId: String?
    let appName: String
    let title: String?
    let layer: Int
    let bounds: CGRect?
    let isOnScreen: Bool

    var id: CGWindowID { windowID }
}
