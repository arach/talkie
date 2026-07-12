#!/usr/bin/env swift

import AppKit
import Foundation

private let canvasSize = NSSize(width: 1320, height: 2868)
private let scriptURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
private let repoURL = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private let rawURL = repoURL
    .appending(path: "apps/ios/fastlane/screenshots/raw/en-US")
private let backgroundURL = scriptURL.appending(path: "source/backgrounds")
private let outputURL = scriptURL.appending(path: "output")
private let iconURL = repoURL.appending(
    path: "apps/ios/Talkie iOS/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
)

private enum Theme {
    case light
    case dark

    var foreground: NSColor {
        switch self {
        case .light: NSColor(srgbRed: 0.094, green: 0.078, blue: 0.059, alpha: 1)
        case .dark: NSColor(srgbRed: 0.969, green: 0.929, blue: 0.827, alpha: 1)
        }
    }

    var secondary: NSColor {
        switch self {
        case .light: NSColor(srgbRed: 0.365, green: 0.318, blue: 0.255, alpha: 1)
        case .dark: NSColor(srgbRed: 0.804, green: 0.749, blue: 0.620, alpha: 1)
        }
    }

    var frame: NSColor {
        switch self {
        case .light: NSColor(srgbRed: 0.129, green: 0.114, blue: 0.090, alpha: 1)
        case .dark: NSColor(srgbRed: 0.831, green: 0.635, blue: 0.290, alpha: 1)
        }
    }

    var wash: NSColor {
        switch self {
        case .light: NSColor(srgbRed: 1, green: 0.973, blue: 0.906, alpha: 0.54)
        case .dark: NSColor(white: 0, alpha: 0.26)
        }
    }
}

private struct Panel {
    let number: String
    let background: String
    let screenshot: String
    let headline: String
    let subtitle: String
    let theme: Theme
    let output: String
}

private let panels = [
    Panel(
        number: "01",
        background: "ivory-waveform.png",
        screenshot: "iPhone 17 Pro Max-01_Home.png",
        headline: "Catch every thought\nwhile it’s alive.",
        subtitle: "One tap. A clean voice memo. Nothing lost.",
        theme: .light,
        output: "01-catch-every-thought.png"
    ),
    Panel(
        number: "02",
        background: "charcoal-waveform.png",
        screenshot: "iPhone 17 Pro Max-02_Recording.png",
        headline: "Talk naturally.\nTalkie keeps up.",
        subtitle: "A focused recorder that stays out of your way.",
        theme: .dark,
        output: "02-talk-naturally.png"
    ),
    Panel(
        number: "03",
        background: "paper-waveform.png",
        screenshot: "iPhone 17 Pro Max-state-dictating.png",
        headline: "Turn speech into\nfinished writing.",
        subtitle: "Dictate, shape, and refine without leaving the page.",
        theme: .light,
        output: "03-finished-writing.png"
    ),
    Panel(
        number: "04",
        background: "charcoal-waveform.png",
        screenshot: "iPhone 17 Pro Max-state-diff.png",
        headline: "See every edit.\nKeep the final say.",
        subtitle: "Review AI changes before they touch your words.",
        theme: .dark,
        output: "04-review-every-edit.png"
    ),
    Panel(
        number: "05",
        background: "ivory-waveform.png",
        screenshot: "iPhone 17 Pro Max-04_Settings.png",
        headline: "Private by design.\nFlexible by default.",
        subtitle: "Choose your engines, voice, and connections.",
        theme: .light,
        output: "05-private-and-flexible.png"
    ),
    Panel(
        number: "06",
        background: "paper-waveform.png",
        screenshot: "iPhone 17 Pro Max-05_Keyboard.png",
        headline: "Your voice works\nwherever you type.",
        subtitle: "Bring Talkie into any text field with its custom keyboard.",
        theme: .light,
        output: "06-voice-anywhere.png"
    ),
]

private enum CompositionError: Error, CustomStringConvertible {
    case missingImage(URL)
    case bitmapCreation
    case contextCreation
    case pngEncoding

    var description: String {
        switch self {
        case let .missingImage(url): "Missing image: \(url.path)"
        case .bitmapCreation: "Could not create bitmap canvas"
        case .contextCreation: "Could not create drawing context"
        case .pngEncoding: "Could not encode PNG"
        }
    }
}

private func image(at url: URL) throws -> NSImage {
    guard let image = NSImage(contentsOf: url) else {
        throw CompositionError.missingImage(url)
    }
    return image
}

private func bitmap(size: NSSize) throws -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CompositionError.bitmapCreation
    }
    rep.size = size
    return rep
}

private func withCanvas(
    size: NSSize,
    draw: () throws -> Void
) throws -> NSBitmapImageRep {
    let rep = try bitmap(size: size)
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw CompositionError.contextCreation
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    try draw()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

private func aspectFillRect(imageSize: NSSize, destination: NSRect) -> NSRect {
    let scale = max(
        destination.width / imageSize.width,
        destination.height / imageSize.height
    )
    let width = imageSize.width * scale
    let height = imageSize.height * scale
    return NSRect(
        x: destination.midX - width / 2,
        y: destination.midY - height / 2,
        width: width,
        height: height
    )
}

private func drawAspectFill(_ image: NSImage, in rect: NSRect) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: rect).addClip()
    image.draw(
        in: aspectFillRect(imageSize: image.size, destination: rect),
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    NSGraphicsContext.restoreGraphicsState()
}

private func drawRoundedImage(_ image: NSImage, in rect: NSRect, radius: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    drawAspectFill(image, in: rect)
    NSGraphicsContext.restoreGraphicsState()
}

private func drawText(
    _ text: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor,
    lineHeight: CGFloat,
    kern: CGFloat = 0,
    alignment: NSTextAlignment = .left
) {
    let style = NSMutableParagraphStyle()
    style.minimumLineHeight = lineHeight
    style.maximumLineHeight = lineHeight
    style.alignment = alignment
    style.lineBreakMode = .byWordWrapping

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: style,
        .kern: kern,
    ]
    NSAttributedString(string: text, attributes: attributes).draw(in: rect)
}

private func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(
        using: .png,
        properties: [.compressionFactor: 0.92]
    ) else {
        throw CompositionError.pngEncoding
    }
    try data.write(to: url, options: .atomic)
}

private func compose(_ panel: Panel, icon: NSImage) throws {
    let background = try image(at: backgroundURL.appending(path: panel.background))
    let screenshot = try image(at: rawURL.appending(path: panel.screenshot))

    let rep = try withCanvas(size: canvasSize) {
        drawAspectFill(background, in: NSRect(origin: .zero, size: canvasSize))

        panel.theme.wash.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 2218, width: 1320, height: 650)).fill()

        panel.theme.frame.setFill()
        NSColor(white: 1, alpha: 0.2).setStroke()
        let framePath = NSBezierPath(
            roundedRect: NSRect(x: 171, y: 54, width: 978, height: 2070),
            xRadius: 84,
            yRadius: 84
        )
        framePath.lineWidth = 2
        framePath.fill()
        framePath.stroke()

        drawRoundedImage(
            screenshot,
            in: NSRect(x: 195, y: 78, width: 930, height: 2020),
            radius: 68
        )
        drawRoundedImage(icon, in: NSRect(x: 104, y: 2700, width: 80, height: 80), radius: 18)

        let mono = NSFont.monospacedSystemFont(ofSize: 27, weight: .medium)
        let headline = NSFont(name: "NewYork-Regular", size: 114)
            ?? NSFont.systemFont(ofSize: 114, weight: .bold)
        let body = NSFont.systemFont(ofSize: 39, weight: .regular)

        drawText(
            "TALKIE  /  VOICE + AI",
            in: NSRect(x: 208, y: 2711, width: 650, height: 48),
            font: mono,
            color: panel.theme.secondary,
            lineHeight: 34,
            kern: 3.5
        )
        drawText(
            "\(panel.number) / 06",
            in: NSRect(x: 1000, y: 2711, width: 216, height: 48),
            font: mono,
            color: panel.theme.secondary,
            lineHeight: 34,
            kern: 3.5,
            alignment: .right
        )
        drawText(
            panel.headline,
            in: NSRect(x: 104, y: 2382, width: 1112, height: 286),
            font: headline,
            color: panel.theme.foreground,
            lineHeight: 116
        )
        drawText(
            panel.subtitle,
            in: NSRect(x: 108, y: 2255, width: 1080, height: 108),
            font: body,
            color: panel.theme.secondary,
            lineHeight: 48
        )
    }

    try writePNG(rep, to: outputURL.appending(path: panel.output))
}

private func makeContactSheet() throws {
    let tileSize = NSSize(width: 236, height: 494)
    let size = NSSize(width: tileSize.width * CGFloat(panels.count), height: tileSize.height)
    let rep = try withCanvas(size: size) {
        NSColor(srgbRed: 0.09, green: 0.078, blue: 0.059, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        for (index, panel) in panels.enumerated() {
            let image = try image(at: outputURL.appending(path: panel.output))
            drawAspectFill(
                image,
                in: NSRect(
                    x: CGFloat(index) * tileSize.width + 8,
                    y: 8,
                    width: tileSize.width - 16,
                    height: tileSize.height - 16
                )
            )
        }
    }
    try writePNG(rep, to: scriptURL.appending(path: "contact-sheet.png"))
}

do {
    try FileManager.default.createDirectory(
        at: outputURL,
        withIntermediateDirectories: true
    )
    let icon = try image(at: iconURL)
    for panel in panels {
        try autoreleasepool {
            try compose(panel, icon: icon)
        }
    }
    try makeContactSheet()
    print("Created six 1320x2868 App Store screenshots in \(outputURL.path)")
    print("Contact sheet: \(scriptURL.appending(path: "contact-sheet.png").path)")
} catch {
    fputs("Marketing composition failed: \(error)\n", stderr)
    exit(1)
}
