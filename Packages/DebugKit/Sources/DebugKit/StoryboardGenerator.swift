//
//  StoryboardGenerator.swift
//  DebugKit
//
//  Generic storyboard generator for multi-screen flows
//

import SwiftUI
import AppKit

// MARK: - Storyboard Generator

@MainActor
public class StoryboardGenerator<StepType: RawRepresentable & CaseIterable & Hashable>
    where StepType.RawValue == Int {

    public struct Configuration {
        public let screenSize: CGSize
        public let arrowWidth: CGFloat
        public let arrowSpacing: CGFloat
        public let showLayoutGrid: Bool
        public let layoutZones: [LayoutZone]
        public let gridSpacing: CGFloat

        public init(
            screenSize: CGSize = CGSize(width: 680, height: 560),
            arrowWidth: CGFloat = 60,
            arrowSpacing: CGFloat = 20,
            showLayoutGrid: Bool = true,
            layoutZones: [LayoutZone] = [],
            gridSpacing: CGFloat = 8
        ) {
            self.screenSize = screenSize
            self.arrowWidth = arrowWidth
            self.arrowSpacing = arrowSpacing
            self.showLayoutGrid = showLayoutGrid
            self.layoutZones = layoutZones
            self.gridSpacing = gridSpacing
        }

        public static var `default`: Configuration {
            Configuration()
        }
    }

    private let config: Configuration
    private let viewBuilder: (StepType) -> AnyView

    public init(
        config: Configuration = .default,
        viewBuilder: @escaping (StepType) -> AnyView
    ) {
        self.config = config
        self.viewBuilder = viewBuilder
    }

    /// Generate storyboard and save to file
    public func generate(outputPath: String? = nil) async {
        print("🎬 Generating storyboard...")

        // Create hidden window for rendering
        let window = createRenderWindow()

        var screenshots: [NSImage] = []

        // Capture each step
        for step in StepType.allCases {
            print("  📸 Capturing step \(step.rawValue + 1)/\(StepType.allCases.count)...")

            // Create view for this step
            let view = createStepView(for: step)
            window.contentView = NSHostingView(rootView: view)
            window.makeKeyAndOrderFront(nil)

            // Wait for rendering
            try? await Task.sleep(for: .milliseconds(500))

            // Capture screenshot
            if let screenshot = captureWindow(window) {
                screenshots.append(screenshot)
            }
        }

        window.close()

        // Composite screenshots
        print("  🎨 Compositing \(screenshots.count) screenshots...")
        guard let composite = createComposite(screenshots: screenshots) else {
            print("❌ Failed to create composite")
            exit(1)
        }

        // Save to file
        let finalPath = saveStoryboard(composite, to: outputPath)
        print("✅ Storyboard saved to: \(finalPath)")

        exit(0)
    }

    /// Generate storyboard in-app and return the image
    public func generateImage() async -> NSImage? {
        let window = createRenderWindow()
        var screenshots: [NSImage] = []

        for step in StepType.allCases {
            let view = createStepView(for: step)
            window.contentView = NSHostingView(rootView: view)
            window.makeKeyAndOrderFront(nil)

            try? await Task.sleep(for: .milliseconds(300))

            if let screenshot = captureWindow(window) {
                screenshots.append(screenshot)
            }
        }

        window.close()

        return createComposite(screenshots: screenshots)
    }

    // MARK: - Private Helpers

    private func createRenderWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: config.screenSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return window
    }

    private func createStepView(for step: StepType) -> some View {
        ZStack {
            // The actual view
            viewBuilder(step)

            // Layout grid overlay
            if config.showLayoutGrid {
                LayoutGridOverlay(
                    zones: config.layoutZones,
                    showGrid: true,
                    gridSpacing: config.gridSpacing,
                    opacity: 0.8
                )
            }
        }
        .frame(width: config.screenSize.width, height: config.screenSize.height)
    }

    private func captureWindow(_ window: NSWindow) -> NSImage? {
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

    private func createComposite(screenshots: [NSImage]) -> NSImage? {
        guard !screenshots.isEmpty else { return nil }

        let totalWidth = CGFloat(screenshots.count) * config.screenSize.width +
                        CGFloat(screenshots.count - 1) * (config.arrowWidth + config.arrowSpacing * 2)
        let totalHeight = config.screenSize.height

        let composite = NSImage(size: NSSize(width: totalWidth, height: totalHeight))

        composite.lockFocus()

        var xOffset: CGFloat = 0

        for (index, screenshot) in screenshots.enumerated() {
            // Draw screenshot
            screenshot.draw(in: NSRect(
                x: xOffset,
                y: 0,
                width: config.screenSize.width,
                height: config.screenSize.height
            ))
            xOffset += config.screenSize.width

            // Draw arrow (except after last screenshot)
            if index < screenshots.count - 1 {
                xOffset += config.arrowSpacing
                drawArrow(at: NSRect(
                    x: xOffset,
                    y: config.screenSize.height / 2 - 20,
                    width: config.arrowWidth,
                    height: 40
                ))
                xOffset += config.arrowWidth + config.arrowSpacing
            }
        }

        composite.unlockFocus()
        return composite
    }

    private func drawArrow(at rect: NSRect) {
        let path = NSBezierPath()
        let midY = rect.midY

        // Arrow shaft
        path.move(to: NSPoint(x: rect.minX, y: midY))
        path.line(to: NSPoint(x: rect.maxX - 15, y: midY))

        // Arrow head
        path.move(to: NSPoint(x: rect.maxX - 15, y: midY - 10))
        path.line(to: NSPoint(x: rect.maxX, y: midY))
        path.line(to: NSPoint(x: rect.maxX - 15, y: midY + 10))

        NSColor.white.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 3
        path.stroke()
    }

    private func saveStoryboard(_ image: NSImage, to customPath: String?) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "storyboard-\(timestamp).png"

        let fileURL: URL
        if let customPath = customPath {
            fileURL = URL(fileURLWithPath: customPath)
        } else {
            let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
            fileURL = desktopURL.appendingPathComponent(filename)
        }

        if let tiffData = image.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
            try? pngData.write(to: fileURL)
        }

        return fileURL.path
    }
}
