//
//  ConsoleScreenshotGenerator.swift
//  Talkie
//
//  Captures the Console screen to a PNG for UI review.
//

import AppKit
import SwiftUI

@MainActor
final class ConsoleScreenshotGenerator {
    static let shared = ConsoleScreenshotGenerator()

    private init() {}

    func captureLoaderFrame(to outputURL: URL, size: CGSize = CGSize(width: 1500, height: 980)) async -> URL? {
        try? FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let window = createRenderWindow(size: size)
        window.title = "Console"
        window.contentView = NSHostingView(rootView: rootView.frame(width: size.width, height: size.height))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let delay = snapshotDelay
        try? await Task.sleep(for: delay)

        defer { window.close() }

        guard let screenshot = captureWindow(window),
              let tiffData = screenshot.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return nil
        }

        do {
            try pngData.write(to: outputURL)
            return outputURL
        } catch {
            print("❌ Failed to write console screenshot: \(error)")
            return nil
        }
    }

    private var rootView: some View {
        AppNavigation(initialSection: .systemConsole)
            .environment(SettingsManager.shared)
            .environment(EngineClient.shared)
            .environment(AgentSettings.shared)
            .environment(CloudKitSyncManager.shared)
            .environment(SystemEventManager.shared)
            .environment(RelativeTimeTicker.shared)
            .tint(SettingsManager.shared.accentColor.color)
    }

    private func createRenderWindow(size: CGSize) -> NSWindow {
        let rect = NSRect(origin: CGPoint(x: 0, y: 0), size: size)
        let window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func captureWindow(_ window: NSWindow) -> NSImage? {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        if let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            [.boundsIgnoreFraming]
        ) {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }

        return captureContentOnly(window)
    }

    private func captureContentOnly(_ window: NSWindow) -> NSImage? {
        guard let contentView = window.contentView else { return nil }

        let bounds = contentView.bounds
        guard let bitmapRep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }

        contentView.cacheDisplay(in: bounds, to: bitmapRep)

        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmapRep)
        return image
    }

    private var snapshotDelay: Duration {
        if let value = ProcessInfo.processInfo.environment["TALKIE_CONSOLE_SNAPSHOT_DELAY_SECONDS"],
           let seconds = Double(value),
           seconds > 0 {
            return .seconds(seconds)
        }

        return .seconds(1.4)
    }
}
