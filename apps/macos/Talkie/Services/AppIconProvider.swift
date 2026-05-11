//
//  AppIconProvider.swift
//  Talkie
//
//  Provides app icons from bundle identifiers with caching
//  Shared logic from TalkieAgent
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - App Icon Provider

final class AppIconProvider {
    static let shared = AppIconProvider()

    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        // Keep icon cache intentionally small for idle-memory discipline.
        cache.countLimit = 24
        cache.totalCostLimit = 3 * 1024 * 1024
        return cache
    }()

    private init() {}

    /// Get icon for a bundle identifier, cached
    func icon(forBundleIdentifier bundleID: String, size: NSSize = NSSize(width: 20, height: 20)) -> NSImage {
        let normalizedSize = normalizedIconSize(size)
        let key = "\(bundleID)-\(Int(normalizedSize.width))x\(Int(normalizedSize.height))" as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        // Resolve the app URL from the bundle ID
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let sourceIcon = NSWorkspace.shared.icon(forFile: appURL.path)
            let icon = renderedIcon(from: sourceIcon, size: normalizedSize)
            cache.setObject(icon.image, forKey: key, cost: icon.cost)
            return icon.image
        }

        // Fallback: generic app icon per size (shared across unknown bundle IDs).
        let fallbackKey = "__fallback__-\(Int(normalizedSize.width))x\(Int(normalizedSize.height))" as NSString
        if let fallback = cache.object(forKey: fallbackKey) {
            cache.setObject(fallback, forKey: key, cost: iconCost(for: normalizedSize))
            return fallback
        }

        let sourceFallback = NSWorkspace.shared.icon(for: UTType.application)
        let fallback = renderedIcon(from: sourceFallback, size: normalizedSize)
        cache.setObject(fallback.image, forKey: fallbackKey, cost: fallback.cost)
        cache.setObject(fallback.image, forKey: key, cost: fallback.cost)
        return fallback.image
    }

    /// Check if an app is installed by bundle identifier
    func isAppInstalled(bundleIdentifier: String) -> Bool {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    /// Check if an app is installed by path
    func isAppInstalled(atPath path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }

    func clearCache() {
        cache.removeAllObjects()
    }

    private func normalizedIconSize(_ size: NSSize) -> NSSize {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        return NSSize(width: width, height: height)
    }

    private func iconCost(for size: NSSize) -> Int {
        let scale = max(1.0, NSScreen.main?.backingScaleFactor ?? 2.0)
        let pixelWidth = max(1, Int((size.width * scale).rounded(.up)))
        let pixelHeight = max(1, Int((size.height * scale).rounded(.up)))
        return pixelWidth * pixelHeight * 4
    }

    private func renderedIcon(from source: NSImage, size: NSSize) -> (image: NSImage, cost: Int) {
        let scale = max(1.0, NSScreen.main?.backingScaleFactor ?? 2.0)
        let pixelWidth = max(1, Int((size.width * scale).rounded(.up)))
        let pixelHeight = max(1, Int((size.height * scale).rounded(.up)))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            source.size = size
            return (source, iconCost(for: size))
        }

        rep.size = size

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            source.size = size
            return (source, iconCost(for: size))
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: source.size),
            operation: .copy,
            fraction: 1.0
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return (image, pixelWidth * pixelHeight * 4)
    }
}

// MARK: - SwiftUI View

struct AppIconView: View {
    let bundleIdentifier: String
    var size: CGFloat = 20

    var body: some View {
        let nsImage = AppIconProvider.shared.icon(
            forBundleIdentifier: bundleIdentifier,
            size: NSSize(width: size, height: size)
        )
        Image(nsImage: nsImage)
            .interpolation(.high)
            .antialiased(true)
            .cornerRadius(4)
    }
}

#Preview {
    VStack(spacing: 12) {
        AppIconView(bundleIdentifier: "com.apple.Safari", size: 32)
        AppIconView(bundleIdentifier: "com.apple.Terminal", size: 32)
        AppIconView(bundleIdentifier: "com.microsoft.VSCode", size: 32)
    }
    .padding()
}
