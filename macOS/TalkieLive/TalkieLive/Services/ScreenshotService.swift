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
            config.width = Int(window.frame.width) * 2  // Retina
            config.height = Int(window.frame.height) * 2
            config.showsCursor = false
            config.capturesAudio = false

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            log.info("Captured window \(windowID): \(image.width)x\(image.height)")
            return NSImage(cgImage: image, size: NSSize(width: window.frame.width, height: window.frame.height))
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
    func captureMainDisplay() async -> NSImage? {
        log.info("Capturing main display")

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            guard let display = content.displays.first else {
                log.error("No displays found")
                return nil
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(display.width) * 2
            config.height = Int(display.height) * 2
            config.showsCursor = false
            config.capturesAudio = false

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            log.info("Captured display: \(image.width)x\(image.height)")
            return NSImage(cgImage: image, size: NSSize(width: display.width, height: display.height))
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
    func encodeAsJPEG(_ image: NSImage, quality: CGFloat = 0.8) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
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

    // MARK: - Permission Check

    /// Check if we have screen recording permission
    func hasScreenRecordingPermission() async -> Bool {
        do {
            // Attempting to get shareable content will fail without permission
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            log.warning("Screen recording permission check failed: \(error)")
            return false
        }
    }

    /// Request screen recording permission by triggering the system prompt
    func requestPermission() async {
        log.info("Requesting screen recording permission")
        // Attempting to capture will trigger the permission prompt
        _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
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
