//
//  AppIconProvider.swift
//  TalkieLive
//
//  Provides app icons from bundle identifiers with caching
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - App Icon Provider

final class AppIconProvider {
    static let shared = AppIconProvider()

    private let cache = NSCache<NSString, NSImage>()

    private init() {}

    func icon(forBundleIdentifier bundleID: String, size: NSSize = NSSize(width: 20, height: 20)) -> NSImage {
        let key = "\(bundleID)-\(Int(size.width))x\(Int(size.height))" as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        // Resolve the app URL from the bundle ID
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = size
            cache.setObject(icon, forKey: key)
            return icon
        }

        // Fallback: generic app icon
        let fallback = NSWorkspace.shared.icon(for: UTType.application)
        fallback.size = size
        cache.setObject(fallback, forKey: key)
        return fallback
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
