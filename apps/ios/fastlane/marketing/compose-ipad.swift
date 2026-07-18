#!/usr/bin/env swift

import AppKit
import Foundation

private let canvasSize = NSSize(width: 2752, height: 2064)
private let scriptURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
private let repoURL = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private let screenshotURL = repoURL
    .appending(path: "apps/ios/fastlane/screenshots/iPad Pro 13-inch (M5)")
private let backgroundURL = scriptURL
    .appending(path: "source/backgrounds/graphite-instrument-panel.png")
private let outputURL = scriptURL.appending(path: "output-ipad")
private let iconURL = repoURL.appending(
    path: "apps/ios/Talkie iOS/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
)

private let foreground = NSColor(
    srgbRed: 0.955,
    green: 0.929,
    blue: 0.855,
    alpha: 1
)
private let secondary = NSColor(
    srgbRed: 0.706,
    green: 0.722,
    blue: 0.742,
    alpha: 1
)
private let accent = NSColor(
    srgbRed: 0.956,
    green: 0.572,
    blue: 0.133,
    alpha: 1
)

private struct Panel {
    let number: String
    let screenshot: String
    let headline: String
    let subtitle: String
    let output: String
}

private let panels = [
    Panel(
        number: "01",
        screenshot: "01_Home.png",
        headline: "Voice into action.",
        subtitle: "Capture a thought, shape it with AI, and keep moving.",
        output: "01-voice-into-action-ipad.png"
    ),
    Panel(
        number: "02",
        screenshot: "02_Recording.png",
        headline: "Talk at full speed.",
        subtitle: "A focused recorder and live transcript keep up with the thought.",
        output: "02-talk-at-full-speed-ipad.png"
    ),
    Panel(
        number: "03",
        screenshot: "state-dictating.png",
        headline: "Finished writing, faster.",
        subtitle: "Dictate straight into the page, then keep shaping the result.",
        output: "03-finished-writing-ipad.png"
    ),
    Panel(
        number: "04",
        screenshot: "state-home-ask-ready.png",
        headline: "Ask Talkie anything.",
        subtitle: "Start on Home, ask in plain language, and carry the thought into AI.",
        output: "04-ask-talkie-anything-ipad.png"
    ),
    Panel(
        number: "05",
        screenshot: "state-diff.png",
        headline: "Approve every AI edit.",
        subtitle: "See exactly what changed before it reaches the page.",
        output: "05-approve-every-edit-ipad.png"
    ),
    Panel(
        number: "06",
        screenshot: "05_Keyboard.png",
        headline: "Dictate anywhere.",
        subtitle: "Bring Talkie to Messages, Notes, Mail, and every other text field.",
        output: "06-dictate-anywhere-ipad.png"
    ),
]

private enum CompositionError: Error, CustomStringConvertible {
    case missingImage(URL)
    case unexpectedScreenshotSize(URL, NSSize)
    case bitmapCreation
    case contextCreation
    case pngEncoding

    var description: String {
        switch self {
        case let .missingImage(url):
            "Missing image: \(url.path)"
        case let .unexpectedScreenshotSize(url, size):
            "Expected a 2752x2064 landscape iPad screenshot at \(url.path), got \(Int(size.width))x\(Int(size.height))"
        case .bitmapCreation:
            "Could not create bitmap canvas"
        case .contextCreation:
            "Could not create drawing context"
        case .pngEncoding:
            "Could not encode PNG"
        }
    }
}

private func image(at url: URL) throws -> NSImage {
    guard let image = NSImage(contentsOf: url) else {
        throw CompositionError.missingImage(url)
    }
    return image
}

private func pixelSize(of image: NSImage) -> NSSize {
    image.representations.reduce(.zero) { result, representation in
        let candidate = NSSize(
            width: representation.pixelsWide,
            height: representation.pixelsHigh
        )
        return candidate.width * candidate.height > result.width * result.height
            ? candidate
            : result
    }
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

private func drawAspectFill(_ image: NSImage, in rect: NSRect, fraction: CGFloat = 1) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: rect).addClip()
    image.draw(
        in: aspectFillRect(imageSize: image.size, destination: rect),
        from: .zero,
        operation: .sourceOver,
        fraction: fraction,
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
        properties: [.compressionFactor: 0.94]
    ) else {
        throw CompositionError.pngEncoding
    }
    try data.write(to: url, options: .atomic)
}

private func compose(
    _ panel: Panel,
    background: NSImage,
    icon: NSImage
) throws {
    let screenshotPath = screenshotURL.appending(path: panel.screenshot)
    let screenshot = try image(at: screenshotPath)
    let screenshotPixelSize = pixelSize(of: screenshot)
    guard screenshotPixelSize == canvasSize else {
        throw CompositionError.unexpectedScreenshotSize(screenshotPath, screenshotPixelSize)
    }

    let rep = try withCanvas(size: canvasSize) {
        drawAspectFill(background, in: NSRect(origin: .zero, size: canvasSize))

        let headerWash = NSGradient(colors: [
            NSColor(white: 0.015, alpha: 0.96),
            NSColor(white: 0.015, alpha: 0.82),
            NSColor(white: 0.015, alpha: 0.08),
        ])
        headerWash?.draw(
            in: NSRect(x: 0, y: 1490, width: canvasSize.width, height: 574),
            angle: 90
        )

        let frameRect = NSRect(x: 346, y: 84, width: 2060, height: 1546)
        NSColor(white: 0.01, alpha: 0.92).setFill()
        NSColor(srgbRed: 0.746, green: 0.544, blue: 0.250, alpha: 0.62).setStroke()
        let frame = NSBezierPath(
            roundedRect: frameRect,
            xRadius: 50,
            yRadius: 50
        )
        frame.lineWidth = 4
        frame.fill()
        frame.stroke()

        drawRoundedImage(
            screenshot,
            in: NSRect(x: 374, y: 112, width: 2004, height: 1503),
            radius: 30
        )

        accent.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 374, y: 1618, width: 2004, height: 10),
            xRadius: 5,
            yRadius: 5
        ).fill()

        drawRoundedImage(icon, in: NSRect(x: 150, y: 1880, width: 92, height: 92), radius: 21)

        let labelFont = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)
        let headlineFont = NSFont.systemFont(ofSize: 118, weight: .semibold)
        let bodyFont = NSFont.systemFont(ofSize: 42, weight: .regular)

        drawText(
            "TALKIE  /  VOICE INTO ACTION",
            in: NSRect(x: 278, y: 1901, width: 880, height: 52),
            font: labelFont,
            color: secondary,
            lineHeight: 38,
            kern: 5
        )
        drawText(
            "\(panel.number) / 06",
            in: NSRect(x: 2330, y: 1901, width: 270, height: 52),
            font: labelFont,
            color: secondary,
            lineHeight: 38,
            kern: 5,
            alignment: .right
        )
        drawText(
            panel.headline,
            in: NSRect(x: 346, y: 1720, width: 2050, height: 150),
            font: headlineFont,
            color: foreground,
            lineHeight: 126
        )
        drawText(
            panel.subtitle,
            in: NSRect(x: 354, y: 1644, width: 1980, height: 64),
            font: bodyFont,
            color: secondary,
            lineHeight: 52
        )
    }

    try writePNG(rep, to: outputURL.appending(path: panel.output))
}

private func makeContactSheet() throws {
    let tileSize = NSSize(width: 516, height: 387)
    let columns = 3
    let rows = 2
    let size = NSSize(
        width: tileSize.width * CGFloat(columns),
        height: tileSize.height * CGFloat(rows)
    )
    let rep = try withCanvas(size: size) {
        NSColor(white: 0.018, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        for (index, panel) in panels.enumerated() {
            let panelImage = try image(at: outputURL.appending(path: panel.output))
            let column = index % columns
            let row = rows - 1 - index / columns
            drawAspectFill(
                panelImage,
                in: NSRect(
                    x: CGFloat(column) * tileSize.width + 8,
                    y: CGFloat(row) * tileSize.height + 8,
                    width: tileSize.width - 16,
                    height: tileSize.height - 16
                )
            )
        }
    }
    try writePNG(rep, to: scriptURL.appending(path: "contact-sheet-ipad.png"))
}

do {
    try FileManager.default.createDirectory(
        at: outputURL,
        withIntermediateDirectories: true
    )
    for existingOutput in try FileManager.default.contentsOfDirectory(
        at: outputURL,
        includingPropertiesForKeys: nil
    ) where existingOutput.pathExtension == "png" {
        try FileManager.default.removeItem(at: existingOutput)
    }
    let background = try image(at: backgroundURL)
    let icon = try image(at: iconURL)

    for panel in panels {
        try autoreleasepool {
            try compose(panel, background: background, icon: icon)
        }
    }
    try makeContactSheet()
    print("Created six 2752x2064 iPad App Store screenshots in \(outputURL.path)")
    print("Contact sheet: \(scriptURL.appending(path: "contact-sheet-ipad.png").path)")
} catch {
    fputs("iPad marketing composition failed: \(error)\n", stderr)
    exit(1)
}
