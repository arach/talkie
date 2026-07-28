#!/usr/bin/env swift

import AppKit
import CoreImage
import Foundation

private enum ProjectionError: Error, CustomStringConvertible {
    case missingImage(URL)
    case unexpectedPlateSize(CGSize)
    case unexpectedScreenshotAspect(CGSize)
    case filterFailure(String)
    case renderFailure
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
        case .pngEncoding:
            "Could not encode the projected concept as PNG"
        }
    }
}

private let scriptURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
private let fastlaneURL = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private let defaultPlateURL = scriptURL.appending(path: "talkie-instrument-clean-plate.png")
private let defaultScreenshotURL = fastlaneURL.appending(
    path: "screenshots/iPad Pro 13-inch (M5)/state-home-ask-ready.png"
)
private let defaultOutputURL = scriptURL.appending(path: "talkie-instrument-clean-real-screen.png")

private func argumentURL(at index: Int, default defaultURL: URL) -> URL {
    guard CommandLine.arguments.indices.contains(index) else { return defaultURL }
    return URL(fileURLWithPath: CommandLine.arguments[index])
}

private func image(at url: URL) throws -> CIImage {
    guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
        throw ProjectionError.missingImage(url)
    }
    return image
}

private func roundedImage(_ image: CIImage, radius: CGFloat) throws -> CIImage {
    guard let maskFilter = CIFilter(name: "CIRoundedRectangleGenerator") else {
        throw ProjectionError.filterFailure("CIRoundedRectangleGenerator")
    }
    maskFilter.setValue(CIVector(cgRect: image.extent), forKey: "inputExtent")
    maskFilter.setValue(radius, forKey: "inputRadius")
    maskFilter.setValue(CIColor.white, forKey: "inputColor")
    guard let mask = maskFilter.outputImage?.cropped(to: image.extent) else {
        throw ProjectionError.filterFailure("CIRoundedRectangleGenerator.outputImage")
    }

    let transparent = CIImage(color: .clear).cropped(to: image.extent)
    guard let blend = CIFilter(name: "CIBlendWithAlphaMask") else {
        throw ProjectionError.filterFailure("CIBlendWithAlphaMask")
    }
    blend.setValue(image, forKey: kCIInputImageKey)
    blend.setValue(transparent, forKey: kCIInputBackgroundImageKey)
    blend.setValue(mask, forKey: kCIInputMaskImageKey)
    guard let output = blend.outputImage?.cropped(to: image.extent) else {
        throw ProjectionError.filterFailure("CIBlendWithAlphaMask.outputImage")
    }
    return output
}

private func perspectiveProjection(_ image: CIImage) throws -> CIImage {
    guard let transform = CIFilter(name: "CIPerspectiveTransform") else {
        throw ProjectionError.filterFailure("CIPerspectiveTransform")
    }

    // Core Image uses a bottom-left origin. These four points are measured at
    // the inner edge of the photographed glass, leaving the black bezel and
    // physical highlights untouched.
    transform.setValue(image, forKey: kCIInputImageKey)
    transform.setValue(CIVector(x: 265, y: 895), forKey: "inputTopLeft")
    transform.setValue(CIVector(x: 1179, y: 895), forKey: "inputTopRight")
    transform.setValue(CIVector(x: 1199, y: 185), forKey: "inputBottomRight")
    transform.setValue(CIVector(x: 248, y: 185), forKey: "inputBottomLeft")

    guard let output = transform.outputImage else {
        throw ProjectionError.filterFailure("CIPerspectiveTransform.outputImage")
    }
    return output
}

private func writePNG(_ image: CIImage, to url: URL) throws {
    let context = CIContext(options: [
        .cacheIntermediates: false,
        .useSoftwareRenderer: false,
    ])
    guard let cgImage = context.createCGImage(image, from: image.extent) else {
        throw ProjectionError.renderFailure
    }
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    guard let data = bitmap.representation(using: .png, properties: [.compressionFactor: 0.96]) else {
        throw ProjectionError.pngEncoding
    }
    try data.write(to: url, options: .atomic)
}

do {
    let plateURL = argumentURL(at: 1, default: defaultPlateURL)
    let screenshotURL = argumentURL(at: 2, default: defaultScreenshotURL)
    let outputURL = argumentURL(at: 3, default: defaultOutputURL)

    let plate = try image(at: plateURL)
    guard plate.extent.size == CGSize(width: 1448, height: 1086) else {
        throw ProjectionError.unexpectedPlateSize(plate.extent.size)
    }

    let screenshot = try image(at: screenshotURL)
    let aspect = screenshot.extent.width / screenshot.extent.height
    guard abs(aspect - (4 / 3)) < 0.002 else {
        throw ProjectionError.unexpectedScreenshotAspect(screenshot.extent.size)
    }

    // The 72-pixel source radius becomes roughly 24 pixels after projection,
    // matching the photographed glass corners without softening UI content.
    let roundedScreenshot = try roundedImage(screenshot, radius: 72)
    let projectedScreenshot = try perspectiveProjection(roundedScreenshot)
    let composition = projectedScreenshot.composited(over: plate).cropped(to: plate.extent)

    try writePNG(composition, to: outputURL)
    print("Projected \(screenshotURL.lastPathComponent) into \(outputURL.path)")
} catch {
    fputs("Talkie concept projection failed: \(error)\n", stderr)
    exit(1)
}
