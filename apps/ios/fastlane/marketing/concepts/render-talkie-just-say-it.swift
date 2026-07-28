#!/usr/bin/env swift

import AppKit
import CoreImage
import CoreText
import Foundation

private enum RenderError: Error, CustomStringConvertible {
    case missingImage(URL)
    case unexpectedPlateSize(CGSize)
    case unexpectedScreenshotAspect(CGSize)
    case filterFailure(String)
    case renderFailure
    case bitmapContextFailure
    case missingFont(URL)
    case pngEncoding

    var description: String {
        switch self {
        case let .missingImage(url):
            "Missing image: \(url.path)"
        case let .unexpectedPlateSize(size):
            "Expected a 1448x1086 concept plate, got \(Int(size.width))x\(Int(size.height))"
        case let .unexpectedScreenshotAspect(size):
            "Expected a 4:3 landscape screenshot, got \(Int(size.width))x\(Int(size.height))"
        case let .filterFailure(name):
            "Core Image filter failed: \(name)"
        case .renderFailure:
            "Could not render the projected concept"
        case .bitmapContextFailure:
            "Could not create the typography canvas"
        case let .missingFont(url):
            "Could not load font: \(url.path)"
        case .pngEncoding:
            "Could not encode the finished concept as PNG"
        }
    }
}

private enum CopyMode: String {
    case tagline
    case brand
    case none

    init(argument: String?) {
        self = argument.flatMap(Self.init(rawValue:)) ?? .tagline
    }
}

private let scriptURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
private let fastlaneURL = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
private let iosURL = fastlaneURL.deletingLastPathComponent()
private let newsreaderURL = iosURL.appending(
    path: "Talkie iOS/Resources/Fonts/Newsreader.ttf"
)

private let defaultPlateURL = scriptURL.appending(path: "talkie-just-say-it-plate.png")
private let defaultScreenshotURL = fastlaneURL.appending(
    path: "screenshots/iPad Pro 13-inch (M5)/state-home-ask-ready.png"
)
private let defaultOutputURL = scriptURL.appending(path: "talkie-just-say-it.png")

private func argumentURL(at index: Int, default defaultURL: URL) -> URL {
    guard CommandLine.arguments.indices.contains(index) else { return defaultURL }
    return URL(fileURLWithPath: CommandLine.arguments[index])
}

private func image(at url: URL) throws -> CIImage {
    guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
        throw RenderError.missingImage(url)
    }
    return image
}

private func roundedImage(_ image: CIImage, radius: CGFloat) throws -> CIImage {
    guard let maskFilter = CIFilter(name: "CIRoundedRectangleGenerator") else {
        throw RenderError.filterFailure("CIRoundedRectangleGenerator")
    }
    maskFilter.setValue(CIVector(cgRect: image.extent), forKey: "inputExtent")
    maskFilter.setValue(radius, forKey: "inputRadius")
    maskFilter.setValue(CIColor.white, forKey: "inputColor")
    guard let mask = maskFilter.outputImage?.cropped(to: image.extent) else {
        throw RenderError.filterFailure("CIRoundedRectangleGenerator.outputImage")
    }

    let transparent = CIImage(color: .clear).cropped(to: image.extent)
    guard let blend = CIFilter(name: "CIBlendWithAlphaMask") else {
        throw RenderError.filterFailure("CIBlendWithAlphaMask")
    }
    blend.setValue(image, forKey: kCIInputImageKey)
    blend.setValue(transparent, forKey: kCIInputBackgroundImageKey)
    blend.setValue(mask, forKey: kCIInputMaskImageKey)
    guard let output = blend.outputImage?.cropped(to: image.extent) else {
        throw RenderError.filterFailure("CIBlendWithAlphaMask.outputImage")
    }
    return output
}

private func perspectiveProjection(_ image: CIImage) throws -> CIImage {
    guard let transform = CIFilter(name: "CIPerspectiveTransform") else {
        throw RenderError.filterFailure("CIPerspectiveTransform")
    }

    // Measured at the inner edge of the blank glass in the re-composed plate.
    // Core Image coordinates use a bottom-left origin.
    transform.setValue(image, forKey: kCIInputImageKey)
    transform.setValue(CIVector(x: 620, y: 642), forKey: "inputTopLeft")
    transform.setValue(CIVector(x: 1253, y: 642), forKey: "inputTopRight")
    transform.setValue(CIVector(x: 1268, y: 187), forKey: "inputBottomRight")
    transform.setValue(CIVector(x: 590, y: 187), forKey: "inputBottomLeft")

    guard let output = transform.outputImage else {
        throw RenderError.filterFailure("CIPerspectiveTransform.outputImage")
    }
    return output
}

private func noCopyReframe(_ image: CIImage) -> CIImage {
    // With no headline occupying the negative space, return the screen to hero
    // scale. Scale around the canvas's lower-right corner so the product keeps
    // its asymmetric editorial placement while moving slightly inward.
    let scale: CGFloat = 1.22
    let transform = CGAffineTransform(
        a: scale,
        b: 0,
        c: 0,
        d: scale,
        tx: image.extent.width * (1 - scale),
        ty: 0
    )
    return image.transformed(by: transform).cropped(to: image.extent)
}

private func drawLine(
    _ text: String,
    in context: CGContext,
    origin: CGPoint,
    font: CTFont,
    color: NSColor,
    tracking: CGFloat
) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: tracking,
    ]
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: attributes)
    )
    context.textPosition = origin
    CTLineDraw(line, context)
}

private func drawCenteredLine(
    _ text: String,
    in context: CGContext,
    centerX: CGFloat,
    baselineY: CGFloat,
    font: CTFont,
    color: NSColor,
    tracking: CGFloat
) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: tracking,
    ]
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: attributes)
    )
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    context.textPosition = CGPoint(x: centerX - width / 2, y: baselineY)
    CTLineDraw(line, context)
}

private func newsreader(size: CGFloat) throws -> CTFont {
    guard
        let provider = CGDataProvider(url: newsreaderURL as CFURL),
        let font = CGFont(provider)
    else {
        throw RenderError.missingFont(newsreaderURL)
    }
    return CTFontCreateWithGraphicsFont(font, size, nil, nil)
}

private func mono(size: CGFloat, weight: NSFont.Weight) -> CTFont {
    let font = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    return CTFontCreateWithName(font.fontName as CFString, size, nil)
}

private func addTypography(to image: CGImage, copyMode: CopyMode) throws -> NSBitmapImageRep {
    let width = image.width
    let height = image.height
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw RenderError.bitmapContextFailure
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)

    switch copyMode {
    case .tagline:
        drawLine(
            "TALKIE:",
            in: context,
            origin: CGPoint(x: 118, y: 916),
            font: mono(size: 16, weight: .semibold),
            color: NSColor(srgbRed: 0.71, green: 0.65, blue: 0.60, alpha: 1),
            tracking: 4.0
        )
        drawLine(
            "Just say it.",
            in: context,
            origin: CGPoint(x: 113, y: 811),
            font: try newsreader(size: 78),
            color: NSColor(srgbRed: 0.92, green: 0.90, blue: 0.87, alpha: 1),
            tracking: -1.1
        )
    case .brand:
        drawCenteredLine(
            "TALKIE",
            in: context,
            centerX: 818,
            baselineY: 858,
            font: mono(size: 60, weight: .regular),
            color: NSColor(srgbRed: 0.969, green: 0.953, blue: 0.925, alpha: 1),
            tracking: 12.0
        )
    case .none:
        break
    }

    guard let output = context.makeImage() else {
        throw RenderError.renderFailure
    }
    return NSBitmapImageRep(cgImage: output)
}

do {
    let plateURL = argumentURL(at: 1, default: defaultPlateURL)
    let screenshotURL = argumentURL(at: 2, default: defaultScreenshotURL)
    let outputURL = argumentURL(at: 3, default: defaultOutputURL)
    let copyMode = CopyMode(
        argument: CommandLine.arguments.indices.contains(4) ? CommandLine.arguments[4] : nil
    )

    let plate = try image(at: plateURL)
    guard plate.extent.size == CGSize(width: 1448, height: 1086) else {
        throw RenderError.unexpectedPlateSize(plate.extent.size)
    }

    let screenshot = try image(at: screenshotURL)
    let aspect = screenshot.extent.width / screenshot.extent.height
    guard abs(aspect - (4 / 3)) < 0.002 else {
        throw RenderError.unexpectedScreenshotAspect(screenshot.extent.size)
    }

    let roundedScreenshot = try roundedImage(screenshot, radius: 72)
    let projectedScreenshot = try perspectiveProjection(roundedScreenshot)
    let composition = projectedScreenshot.composited(over: plate).cropped(to: plate.extent)
    let framedComposition = copyMode == .tagline ? composition : noCopyReframe(composition)

    let imageContext = CIContext(options: [
        .cacheIntermediates: false,
        .useSoftwareRenderer: false,
    ])
    guard let cgImage = imageContext.createCGImage(framedComposition, from: framedComposition.extent) else {
        throw RenderError.renderFailure
    }
    let rendered = try addTypography(to: cgImage, copyMode: copyMode)
    guard let data = rendered.representation(using: .png, properties: [.compressionFactor: 0.96]) else {
        throw RenderError.pngEncoding
    }
    try data.write(to: outputURL, options: .atomic)
    print("Rendered \(copyMode.rawValue) Talkie promo to \(outputURL.path)")
} catch {
    fputs("Talkie promo render failed: \(error)\n", stderr)
    exit(1)
}
