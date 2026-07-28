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

private enum MarketingTheme: String {
    case graphite
    case mineral

    var backgroundFilename: String {
        switch self {
        case .graphite: "graphite-instrument-panel.png"
        case .mineral: "mineral-instrument-panel-v7.png"
        }
    }

    var usesHeaderWash: Bool {
        self == .graphite
    }

    var outputDirectory: String {
        switch self {
        case .graphite: "output-ipad"
        case .mineral: "output-ipad-mineral"
        }
    }

    var contactSheetFilename: String {
        switch self {
        case .graphite: "contact-sheet-ipad.png"
        case .mineral: "contact-sheet-ipad-mineral.png"
        }
    }

    var foreground: NSColor {
        switch self {
        case .graphite:
            NSColor(srgbRed: 0.955, green: 0.929, blue: 0.855, alpha: 1)
        case .mineral:
            NSColor(srgbRed: 0.105, green: 0.165, blue: 0.180, alpha: 1)
        }
    }

    var secondary: NSColor {
        switch self {
        case .graphite:
            NSColor(srgbRed: 0.706, green: 0.722, blue: 0.742, alpha: 1)
        case .mineral:
            NSColor(srgbRed: 0.255, green: 0.335, blue: 0.345, alpha: 1)
        }
    }

    var accent: NSColor {
        switch self {
        case .graphite:
            NSColor(srgbRed: 0.956, green: 0.572, blue: 0.133, alpha: 1)
        case .mineral:
            NSColor(srgbRed: 0.690, green: 0.365, blue: 0.165, alpha: 1)
        }
    }

    var headerWashColors: [NSColor] {
        switch self {
        case .graphite:
            [
                NSColor(white: 0.015, alpha: 0.96),
                NSColor(white: 0.015, alpha: 0.82),
                NSColor(white: 0.015, alpha: 0.08),
            ]
        case .mineral:
            [
                NSColor(srgbRed: 0.775, green: 0.825, blue: 0.825, alpha: 0.96),
                NSColor(srgbRed: 0.775, green: 0.825, blue: 0.825, alpha: 0.84),
                NSColor(srgbRed: 0.775, green: 0.825, blue: 0.825, alpha: 0.08),
            ]
        }
    }

    var frameFill: NSColor {
        switch self {
        case .graphite: NSColor(white: 0.01, alpha: 0.92)
        case .mineral: NSColor(srgbRed: 0.145, green: 0.210, blue: 0.220, alpha: 0.88)
        }
    }

    var frameStroke: NSColor {
        switch self {
        case .graphite:
            NSColor(srgbRed: 0.746, green: 0.544, blue: 0.250, alpha: 0.62)
        case .mineral:
            NSColor(srgbRed: 0.600, green: 0.365, blue: 0.190, alpha: 0.72)
        }
    }

    var contactSheetBackground: NSColor {
        switch self {
        case .graphite: NSColor(white: 0.018, alpha: 1)
        case .mineral: NSColor(srgbRed: 0.665, green: 0.725, blue: 0.730, alpha: 1)
        }
    }
}

private let selectedTheme: MarketingTheme = {
    let arguments = CommandLine.arguments
    guard let themeIndex = arguments.firstIndex(of: "--theme") else {
        return .mineral
    }

    guard arguments.indices.contains(themeIndex + 1),
          let theme = MarketingTheme(rawValue: arguments[themeIndex + 1]) else {
        fputs("Invalid --theme value (expected mineral or graphite)\n", stderr)
        exit(2)
    }

    return theme
}()

private let backgroundURL = scriptURL
    .appending(path: "source/backgrounds/" + selectedTheme.backgroundFilename)
private let outputURL = scriptURL.appending(path: selectedTheme.outputDirectory)
private let iconURL = repoURL.appending(
    path: "apps/ios/Talkie iOS/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
)

private let foreground = selectedTheme.foreground
private let secondary = selectedTheme.secondary
private let accent = selectedTheme.accent

private enum PanelPresentation {
    case studio
    case instrument
}

private struct Panel {
    let number: String
    let screenshot: String
    let headline: String
    let subtitle: String
    let output: String
    let presentation: PanelPresentation
}

private let panels = [
    Panel(
        number: "01",
        screenshot: "01_Home.png",
        headline: "Voice into action.",
        subtitle: "Capture a thought, shape it with AI, and keep moving.",
        output: "01-voice-into-action-ipad.png",
        presentation: .studio
    ),
    Panel(
        number: "02",
        screenshot: "02_Recording.png",
        headline: "Talk at full speed.",
        subtitle: "A focused recorder and live transcript keep up with the thought.",
        output: "02-talk-at-full-speed-ipad.png",
        presentation: .studio
    ),
    Panel(
        number: "03",
        screenshot: "state-dictating.png",
        headline: "Finished writing, faster.",
        subtitle: "Dictate straight into the page, then keep shaping the result.",
        output: "03-finished-writing-ipad.png",
        presentation: .studio
    ),
    Panel(
        number: "04",
        screenshot: "state-home-ask-ready.png",
        headline: "Ask Talkie anything.",
        subtitle: "Start on Home, ask in plain language, and carry the thought into AI.",
        output: "04-ask-talkie-anything-ipad.png",
        presentation: .instrument
    ),
    Panel(
        number: "05",
        screenshot: "state-diff.png",
        headline: "Approve every AI edit.",
        subtitle: "See exactly what changed before it reaches the page.",
        output: "05-approve-every-edit-ipad.png",
        presentation: .studio
    ),
    Panel(
        number: "06",
        screenshot: "05_Keyboard.png",
        headline: "Dictate anywhere.",
        subtitle: "Bring Talkie to Messages, Notes, Mail, and every other text field.",
        output: "06-dictate-anywhere-ipad.png",
        presentation: .studio
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

private func drawMineralStudioBackground() {
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.920, green: 0.905, blue: 0.875, alpha: 1),
        NSColor(srgbRed: 0.815, green: 0.840, blue: 0.820, alpha: 1),
        NSColor(srgbRed: 0.690, green: 0.755, blue: 0.748, alpha: 1),
    ])
    gradient?.draw(
        in: NSRect(origin: .zero, size: canvasSize),
        angle: 90
    )

    // A broad editorial glow replaces the previous perimeter rule. It keeps
    // the field dimensional while allowing the product and caption to float.
    let glow = NSGradient(colors: [
        NSColor(white: 1, alpha: 0.20),
        NSColor(white: 1, alpha: 0),
    ])
    glow?.draw(
        in: NSRect(x: 120, y: 1140, width: 2512, height: 924),
        relativeCenterPosition: NSPoint(x: 0, y: 0.22)
    )
}

private func drawMineralCaptionCard(_ panel: Panel, icon: NSImage) {
    let cardRect = NSRect(x: 152, y: 1790, width: 2448, height: 242)
    let card = NSBezierPath(
        roundedRect: cardRect,
        xRadius: 28,
        yRadius: 28
    )

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -9)
    shadow.set()
    NSColor(srgbRed: 0.925, green: 0.910, blue: 0.880, alpha: 0.98).setFill()
    card.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    card.addClip()
    NSGradient(colors: [
        NSColor(srgbRed: 0.955, green: 0.945, blue: 0.920, alpha: 0.98),
        NSColor(srgbRed: 0.875, green: 0.890, blue: 0.865, alpha: 0.98),
    ])?.draw(in: cardRect, angle: 0)
    NSGraphicsContext.restoreGraphicsState()

    NSColor(white: 1, alpha: 0.48).setStroke()
    card.lineWidth = 1.5
    card.stroke()

    let innerEdge = NSBezierPath(
        roundedRect: cardRect.insetBy(dx: 2, dy: 2),
        xRadius: 26,
        yRadius: 26
    )
    NSColor(srgbRed: 0.190, green: 0.265, blue: 0.270, alpha: 0.12).setStroke()
    innerEdge.lineWidth = 1
    innerEdge.stroke()

    drawRoundedImage(icon, in: NSRect(x: 192, y: 1950, width: 52, height: 52), radius: 12)

    let labelFont = NSFont.monospacedSystemFont(ofSize: 20, weight: .medium)
    let headlineFont = NSFont.systemFont(ofSize: 76, weight: .semibold)
    let bodyFont = NSFont.systemFont(ofSize: 28, weight: .regular)

    drawText(
        "TALKIE  /  VOICE INTO ACTION",
        in: NSRect(x: 268, y: 1962, width: 920, height: 30),
        font: labelFont,
        color: secondary,
        lineHeight: 26,
        kern: 3.2
    )
    drawText(
        "\(panel.number) / 06",
        in: NSRect(x: 2220, y: 1962, width: 324, height: 30),
        font: labelFont,
        color: secondary,
        lineHeight: 26,
        kern: 3.2,
        alignment: .right
    )
    drawText(
        panel.headline,
        in: NSRect(x: 192, y: 1878, width: 2352, height: 78),
        font: headlineFont,
        color: foreground,
        lineHeight: 82
    )
    drawText(
        panel.subtitle,
        in: NSRect(x: 196, y: 1832, width: 2348, height: 34),
        font: bodyFont,
        color: secondary,
        lineHeight: 32
    )
}

private func drawMineralDevice(
    screenshot: NSImage,
    frameRect: NSRect,
    screenshotRect: NSRect
) {
    let outerBody = NSBezierPath(
        roundedRect: frameRect,
        xRadius: 40,
        yRadius: 40
    )

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
    shadow.shadowBlurRadius = 38
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor(srgbRed: 0.130, green: 0.190, blue: 0.195, alpha: 1).setFill()
    outerBody.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    outerBody.addClip()
    NSGradient(colors: [
        NSColor(srgbRed: 0.420, green: 0.475, blue: 0.465, alpha: 1),
        NSColor(srgbRed: 0.155, green: 0.230, blue: 0.235, alpha: 1),
    ])?.draw(in: frameRect, angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    NSColor(white: 1, alpha: 0.42).setStroke()
    outerBody.lineWidth = 2
    outerBody.stroke()

    let bezelRect = frameRect.insetBy(dx: 7, dy: 7)
    let bezel = NSBezierPath(
        roundedRect: bezelRect,
        xRadius: 34,
        yRadius: 34
    )
    NSColor(srgbRed: 0.055, green: 0.105, blue: 0.112, alpha: 0.98).setFill()
    bezel.fill()
    NSColor(srgbRed: 0.665, green: 0.400, blue: 0.220, alpha: 0.58).setStroke()
    bezel.lineWidth = 1.5
    bezel.stroke()

    drawRoundedImage(screenshot, in: screenshotRect, radius: 20)

    let screenEdge = NSBezierPath(
        roundedRect: screenshotRect,
        xRadius: 20,
        yRadius: 20
    )
    NSColor(white: 1, alpha: 0.22).setStroke()
    screenEdge.lineWidth = 1.25
    screenEdge.stroke()

    let cameraCenter = NSPoint(x: frameRect.midX, y: screenshotRect.maxY + 11)
    NSColor(srgbRed: 0.025, green: 0.050, blue: 0.055, alpha: 0.9).setFill()
    NSBezierPath(
        ovalIn: NSRect(
            x: cameraCenter.x - 3.5,
            y: cameraCenter.y - 3.5,
            width: 7,
            height: 7
        )
    ).fill()
    NSColor(white: 1, alpha: 0.24).setFill()
    NSBezierPath(
        ovalIn: NSRect(
            x: cameraCenter.x - 1.2,
            y: cameraCenter.y + 0.2,
            width: 2.2,
            height: 2.2
        )
    ).fill()
}

private func drawMachinedKnob(at center: NSPoint) {
    let outerRect = NSRect(x: center.x - 37, y: center.y - 37, width: 74, height: 74)
    let outer = NSBezierPath(ovalIn: outerRect)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 13
    shadow.shadowOffset = NSSize(width: 0, height: -5)
    shadow.set()
    NSColor(srgbRed: 0.440, green: 0.455, blue: 0.430, alpha: 1).setFill()
    outer.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    outer.addClip()
    NSGradient(colors: [
        NSColor(srgbRed: 0.810, green: 0.790, blue: 0.735, alpha: 1),
        NSColor(srgbRed: 0.320, green: 0.365, blue: 0.360, alpha: 1),
    ])?.draw(in: outerRect, angle: 112)
    NSGraphicsContext.restoreGraphicsState()

    // Fine radial grooves imply a machined encoder without turning it into
    // decorative retro hardware.
    for index in 0..<24 {
        let angle = CGFloat(index) * (.pi * 2 / 24)
        let innerRadius: CGFloat = 31
        let outerRadius: CGFloat = 35
        let groove = NSBezierPath()
        groove.move(to: NSPoint(
            x: center.x + cos(angle) * innerRadius,
            y: center.y + sin(angle) * innerRadius
        ))
        groove.line(to: NSPoint(
            x: center.x + cos(angle) * outerRadius,
            y: center.y + sin(angle) * outerRadius
        ))
        NSColor(srgbRed: 0.070, green: 0.115, blue: 0.118, alpha: 0.34).setStroke()
        groove.lineWidth = 1.2
        groove.stroke()
    }

    let faceRect = outerRect.insetBy(dx: 9, dy: 9)
    let face = NSBezierPath(ovalIn: faceRect)
    NSGraphicsContext.saveGraphicsState()
    face.addClip()
    NSGradient(colors: [
        NSColor(srgbRed: 0.735, green: 0.730, blue: 0.690, alpha: 1),
        NSColor(srgbRed: 0.385, green: 0.430, blue: 0.420, alpha: 1),
    ])?.draw(in: faceRect, relativeCenterPosition: NSPoint(x: -0.24, y: 0.30))
    NSGraphicsContext.restoreGraphicsState()

    NSColor(white: 1, alpha: 0.54).setStroke()
    outer.lineWidth = 1.4
    outer.stroke()
    NSColor(srgbRed: 0.060, green: 0.110, blue: 0.112, alpha: 0.58).setStroke()
    face.lineWidth = 1.5
    face.stroke()

    let indexMark = NSBezierPath(
        roundedRect: NSRect(x: center.x - 2, y: center.y + 18, width: 4, height: 10),
        xRadius: 2,
        yRadius: 2
    )
    NSColor(srgbRed: 0.735, green: 0.405, blue: 0.215, alpha: 0.94).setFill()
    indexMark.fill()
}

private func drawInstrumentControls() {
    let y: CGFloat = 962
    let horizontalInset: CGFloat = 202
    drawMachinedKnob(at: NSPoint(x: horizontalInset, y: y))
    drawMachinedKnob(at: NSPoint(x: canvasSize.width - horizontalInset, y: y))
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
        let isMineral = selectedTheme == .mineral
        let usesInstrument = !isMineral || panel.presentation == .instrument

        if isMineral, !usesInstrument {
            drawMineralStudioBackground()
        } else if isMineral {
            // The caption remains on the studio field while the symmetrical
            // enclosure begins below it as a separate physical object.
            NSColor(srgbRed: 0.920, green: 0.905, blue: 0.875, alpha: 1).setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()
            drawAspectFill(
                background,
                in: NSRect(x: 0, y: -56, width: canvasSize.width, height: canvasSize.height)
            )
        } else {
            drawAspectFill(background, in: NSRect(origin: .zero, size: canvasSize))
        }

        if selectedTheme.usesHeaderWash {
            let headerWash = NSGradient(colors: selectedTheme.headerWashColors)
            headerWash?.draw(
                in: NSRect(x: 0, y: 1490, width: canvasSize.width, height: 574),
                angle: 90
            )
        }

        // Both mineral presentations share one large product window. Only the
        // Ask Talkie hero receives the physical chassis; the remaining panels
        // use a quiet studio field and a slim floating edge.
        let frameRect = isMineral
            ? NSRect(x: 256, y: 66, width: 2240, height: 1692)
            : NSRect(x: 404, y: 160, width: 1944, height: 1472)
        let screenshotRect = isMineral
            ? NSRect(x: 280, y: 90, width: 2192, height: 1644)
            : NSRect(x: 432, y: 188, width: 1888, height: 1416)

        if isMineral {
            // The real 2752x2064 capture is placed in an exact 4:3 aperture.
            // Equal insets preserve the iPad silhouette around that screen.
            drawMineralDevice(
                screenshot: screenshot,
                frameRect: frameRect,
                screenshotRect: screenshotRect
            )
            if usesInstrument {
                drawInstrumentControls()
            }
            drawMineralCaptionCard(panel, icon: icon)
        } else {
            selectedTheme.frameFill.setFill()
            selectedTheme.frameStroke.setStroke()
            let frame = NSBezierPath(
                roundedRect: frameRect,
                xRadius: 50,
                yRadius: 50
            )
            frame.lineWidth = 4
            frame.fill()
            frame.stroke()

            drawRoundedImage(screenshot, in: screenshotRect, radius: 28)

            accent.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 432, y: 1620, width: 1888, height: 10),
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
        selectedTheme.contactSheetBackground.setFill()
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
    try writePNG(rep, to: scriptURL.appending(path: selectedTheme.contactSheetFilename))
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
    print("Created six 2752x2064 \(selectedTheme.rawValue) iPad App Store screenshots in \(outputURL.path)")
    print("Contact sheet: \(scriptURL.appending(path: selectedTheme.contactSheetFilename).path)")
} catch {
    fputs("iPad marketing composition failed: \(error)\n", stderr)
    exit(1)
}
