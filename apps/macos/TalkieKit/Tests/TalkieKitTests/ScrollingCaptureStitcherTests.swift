#if os(macOS)
import CoreGraphics
import Testing
@testable import TalkieKit

@Test("Scrolling capture detects an unchanged viewport")
func scrollingCaptureDetectsUnchangedViewport() throws {
    let image = try patternedImage(width: 64, height: 120)
    #expect(VerticalScrollFrameMatcher.match(previous: image, current: image) == .unchanged)
}

@Test("Scrolling region metadata remains a screen capture")
func scrollingRegionMetadataIsRecognized() {
    #expect(RegionCaptureBehavior.scrollingContent.captureModeValue == "scrolling-region")
    #expect(RecordingVisualContext.isScreenCaptureMode("scrolling-region"))
}

@Test("Scrolling capture finds the exact vertical displacement")
func scrollingCaptureFindsVerticalDisplacement() throws {
    let document = try patternedImage(width: 64, height: 260)
    let first = try #require(document.cropping(to: CGRect(x: 0, y: 0, width: 64, height: 120)))
    let second = try #require(document.cropping(to: CGRect(x: 0, y: 73, width: 64, height: 120)))

    #expect(VerticalScrollFrameMatcher.match(previous: first, current: second) == .displacement(73))
}

@Test("Scrolling capture ignores a fixed header while matching content")
func scrollingCaptureIgnoresStickyHeader() throws {
    let document = try patternedImage(width: 96, height: 260)
    let firstContent = try #require(document.cropping(to: CGRect(x: 0, y: 0, width: 96, height: 120)))
    let secondContent = try #require(document.cropping(to: CGRect(x: 0, y: 68, width: 96, height: 120)))
    let first = try imageWithStickyHeader(firstContent, height: 12)
    let second = try imageWithStickyHeader(secondContent, height: 12)

    #expect(VerticalScrollFrameMatcher.match(previous: first, current: second) == .displacement(68))
}

@Test("Scrolling capture stitches without duplicated or missing rows")
func scrollingCaptureStitchesExactDocument() throws {
    let document = try patternedImage(width: 64, height: 260)
    let first = try #require(document.cropping(to: CGRect(x: 0, y: 0, width: 64, height: 120)))
    let second = try #require(document.cropping(to: CGRect(x: 0, y: 70, width: 64, height: 120)))
    let third = try #require(document.cropping(to: CGRect(x: 0, y: 140, width: 64, height: 120)))

    var stitcher = ScrollingCaptureStitcher(firstFrame: first)
    #expect(stitcher.append(second) == .appended(displacement: 70))
    #expect(stitcher.append(third) == .appended(displacement: 70))

    let stitched = try #require(stitcher.makeImage())
    #expect(stitched.width == document.width)
    #expect(stitched.height == document.height)
    #expect(try rgbaBytes(from: stitched) == rgbaBytes(from: document))
}

@Test("Scrolling capture stops before exceeding its pixel budget")
func scrollingCaptureHonorsPixelBudget() throws {
    let document = try patternedImage(width: 64, height: 190)
    let first = try #require(document.cropping(to: CGRect(x: 0, y: 0, width: 64, height: 120)))
    let second = try #require(document.cropping(to: CGRect(x: 0, y: 70, width: 64, height: 120)))
    var stitcher = ScrollingCaptureStitcher(
        firstFrame: first,
        maximumPixelCount: 64 * 150
    )

    #expect(stitcher.append(second) == .reachedPixelLimit)
    #expect(stitcher.pixelHeight == 120)
}

@Test("Scrolling capture ease-out motion lands on the exact distance")
func scrollingCaptureMotionLandsExactly() {
    let deltas = ScrollingCaptureMotion.easeOutDeltas(totalDistance: -517)
    #expect(deltas.reduce(0, +) == -517)
    #expect(deltas.allSatisfy { $0 < 0 })
}

@Test("Scrolling capture ease-out motion decelerates")
func scrollingCaptureMotionDecelerates() {
    let deltas = ScrollingCaptureMotion.easeOutDeltas(totalDistance: 720)
    let magnitudes = deltas.map(abs)
    #expect(magnitudes.count > 3)
    #expect((magnitudes.first ?? 0) > (magnitudes.last ?? 0))
    #expect(zip(magnitudes, magnitudes.dropFirst()).allSatisfy { $0.0 >= $0.1 })
}

private func patternedImage(width: Int, height: Int) throws -> CGImage {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * width + x) * 4
            bytes[offset] = UInt8((x * 19 + y * 7 + (y / 11) * 31) % 256)
            bytes[offset + 1] = UInt8((x * 5 + y * 23 + (x / 7) * 17) % 256)
            bytes[offset + 2] = UInt8((x * 29 + y * 3 + (x * y) % 43) % 256)
            bytes[offset + 3] = 255
        }
    }

    let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
    return try #require(CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ))
}

private func rgbaBytes(from image: CGImage) throws -> [UInt8] {
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let didDraw = bytes.withUnsafeMutableBytes { rawBuffer -> Bool in
        guard let baseAddress = rawBuffer.baseAddress,
              let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
              ) else {
            return false
        }
        context.interpolationQuality = .none
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    #expect(didDraw)
    return bytes
}

private func imageWithStickyHeader(_ image: CGImage, height headerHeight: Int) throws -> CGImage {
    let width = image.width
    let height = image.height
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(red: 0.08, green: 0.12, blue: 0.18, alpha: 1)
    context.fill(CGRect(x: 0, y: height - headerHeight, width: width, height: headerHeight))
    return try #require(context.makeImage())
}
#endif
