#!/usr/bin/env swift

import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let campaignDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
private let mastersDirectory = campaignDirectory.appending(path: "masters")
private let exportsDirectory = campaignDirectory
    .appending(path: "exports")
    .appending(path: "app-store-concepts")

private let canvasSize = NSSize(width: 2880, height: 1800)

private struct Palette {
    let backgroundTop: NSColor
    let backgroundBottom: NSColor
    let primaryText: NSColor
    let secondaryText: NSColor
    let accent: NSColor
}

private struct CampaignFrame {
    let source: String
    let slug: String
    let sequence: String
    let headline: String
    let supporting: String
    let palette: Palette
}

private let warm = Palette(
    backgroundTop: .hex("ECE2D5"),
    backgroundBottom: .hex("D8C9B8"),
    primaryText: .hex("2A211B"),
    secondaryText: .hex("6D5C50"),
    accent: .hex("B65C2B")
)

private let pearl = Palette(
    backgroundTop: .hex("F0F2F0"),
    backgroundBottom: .hex("DDE3E2"),
    primaryText: .hex("1E292C"),
    secondaryText: .hex("647174"),
    accent: .hex("B65C2B")
)

private let dark = Palette(
    backgroundTop: .hex("11171D"),
    backgroundBottom: .hex("080B0E"),
    primaryText: .hex("F5F1E9"),
    secondaryText: .hex("A9B0B4"),
    accent: .hex("C66C36")
)

private let frames = [
    CampaignFrame(
        source: "hero-window-warm-city.png",
        slug: "lean-back",
        sequence: "01 / TALKIE",
        headline: "Lean\nback.",
        supporting: "Take your eyes off the screen.\nLet the thought keep moving.",
        palette: warm
    ),
    CampaignFrame(
        source: "hero-window-pearl-lake.png",
        slug: "eyes-off-screen",
        sequence: "02 / TALKIE",
        headline: "Take your\neyes off\nthe screen.",
        supporting: "Talkie listens while you look\nsomewhere else.",
        palette: pearl
    ),
    CampaignFrame(
        source: "hero-dark-studio.png",
        slug: "speak-ideas-into-existence",
        sequence: "03 / TALKIE",
        headline: "Speak your\nideas into\nexistence.",
        supporting: "Capture the thought. Shape it.\nKeep moving.",
        palette: dark
    ),
]

private let cleanMasters: [(source: String, slug: String, palette: Palette)] = [
    ("hero-window-warm-city.png", "warm-city", warm),
    ("hero-window-pearl-lake.png", "pearl-lake", pearl),
    ("hero-dark-studio.png", "dark-studio", dark),
]

private func registerCampaignFonts() {
    let repoRoot = campaignDirectory
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    let fontPaths = [
        "apps/macos/Talkie/Resources/Fonts/Geist-Regular.otf",
        "apps/macos/Talkie/Resources/Fonts/Geist-Medium.otf",
        "apps/macos/Talkie/Resources/Fonts/GeistMono-Regular.otf",
    ]

    for path in fontPaths {
        let url = repoRoot.appending(path: path)
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

private func font(named name: String, size: CGFloat, fallbackWeight: NSFont.Weight) -> NSFont {
    NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: fallbackWeight)
}

private func makeContext() throws -> CGContext {
    let width = Int(canvasSize.width)
    let height = Int(canvasSize.height)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw RenderError.bitmapCreationFailed
    }

    return context
}

private func drawBackground(_ palette: Palette) {
    NSGradient(starting: palette.backgroundTop, ending: palette.backgroundBottom)?
        .draw(in: NSRect(origin: .zero, size: canvasSize), angle: -90)
}

private func drawImageCard(_ image: NSImage, in rect: NSRect, radius: CGFloat = 36) {
    NSGraphicsContext.saveGraphicsState()

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 42
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()

    NSColor.black.withAlphaComponent(0.12).setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()

    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    image.draw(
        in: rect,
        from: NSRect(origin: .zero, size: image.size),
        operation: .copy,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )

    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.18).setStroke()
    let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
    border.lineWidth = 1
    border.stroke()
}

private func drawText(
    _ string: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor,
    tracking: CGFloat = 0,
    lineHeight: CGFloat? = nil,
    alignment: NSTextAlignment = .left
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    if let lineHeight {
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
    }

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: tracking,
        .paragraphStyle: paragraph,
    ]

    NSAttributedString(string: string, attributes: attributes).draw(
        with: rect,
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
}

private func writePNG(_ context: CGContext, to url: URL) throws {
    guard
        let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        throw RenderError.pngEncodingFailed
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw RenderError.pngEncodingFailed
    }
}

private func renderCampaignFrame(_ frame: CampaignFrame) throws {
    let sourceURL = mastersDirectory.appending(path: frame.source)
    guard let image = NSImage(contentsOf: sourceURL) else {
        throw RenderError.missingSource(sourceURL.path)
    }

    let bitmapContext = try makeContext()
    let context = NSGraphicsContext(cgContext: bitmapContext, flipped: false)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    drawBackground(frame.palette)

    let imageRect = NSRect(x: 800, y: 165, width: 1960, height: 1470)
    drawImageCard(image, in: imageRect)

    frame.palette.accent.setFill()
    NSBezierPath(roundedRect: NSRect(x: 100, y: 1492, width: 112, height: 8), xRadius: 4, yRadius: 4).fill()

    drawText(
        frame.sequence,
        in: NSRect(x: 100, y: 1535, width: 590, height: 68),
        font: font(named: "GeistMono-Regular", size: 36, fallbackWeight: .regular),
        color: frame.palette.secondaryText,
        tracking: 8,
        lineHeight: 48
    )

    drawText(
        frame.headline,
        in: NSRect(x: 94, y: 650, width: 620, height: 760),
        font: font(named: "Geist", size: frame.slug == "lean-back" ? 154 : 126, fallbackWeight: .regular),
        color: frame.palette.primaryText,
        tracking: -2.5,
        lineHeight: frame.slug == "lean-back" ? 154 : 132
    )

    drawText(
        frame.supporting,
        in: NSRect(x: 100, y: 350, width: 610, height: 210),
        font: font(named: "Geist", size: 42, fallbackWeight: .regular),
        color: frame.palette.secondaryText,
        tracking: -0.4,
        lineHeight: 58
    )

    NSGraphicsContext.restoreGraphicsState()

    try writePNG(bitmapContext, to: exportsDirectory.appending(path: "\(frame.sequence.prefix(2))-\(frame.slug)-2880x1800.png"))
}

private func renderCleanMaster(source: String, slug: String, palette: Palette) throws {
    let sourceURL = mastersDirectory.appending(path: source)
    guard let image = NSImage(contentsOf: sourceURL) else {
        throw RenderError.missingSource(sourceURL.path)
    }

    let bitmapContext = try makeContext()
    let context = NSGraphicsContext(cgContext: bitmapContext, flipped: false)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    drawBackground(palette)
    drawImageCard(image, in: NSRect(x: 260, y: 45, width: 2360, height: 1770), radius: 28)

    NSGraphicsContext.restoreGraphicsState()
    try writePNG(bitmapContext, to: exportsDirectory.appending(path: "clean-\(slug)-2880x1800.png"))
}

private enum RenderError: LocalizedError {
    case bitmapCreationFailed
    case graphicsContextCreationFailed
    case missingSource(String)
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .bitmapCreationFailed:
            "Could not create the 2880x1800 bitmap."
        case .graphicsContextCreationFailed:
            "Could not create an AppKit graphics context."
        case .missingSource(let path):
            "Missing campaign master: \(path)"
        case .pngEncodingFailed:
            "Could not encode the campaign export as PNG."
        }
    }
}

private extension NSColor {
    static func hex(_ value: String) -> NSColor {
        let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let rgb = UInt64(cleaned, radix: 16) ?? 0
        return NSColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

do {
    try FileManager.default.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
    registerCampaignFonts()

    for master in cleanMasters {
        try renderCleanMaster(source: master.source, slug: master.slug, palette: master.palette)
    }

    for frame in frames {
        try renderCampaignFrame(frame)
    }

    print("Rendered \(cleanMasters.count + frames.count) campaign assets to \(exportsDirectory.path)")
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
