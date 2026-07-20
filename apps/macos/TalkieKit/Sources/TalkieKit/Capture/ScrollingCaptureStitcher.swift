#if os(macOS)
import CoreGraphics
import Foundation

/// Matches consecutive captures of one viewport and assembles only the newly
/// revealed rows. The matcher samples the whole content area so it works with
/// browsers and ordinary AppKit/SwiftUI scroll views without app integration.
struct ScrollingCaptureStitcher {
    enum AppendResult: Equatable {
        case appended(displacement: Int)
        case unchanged
        case unaligned
        case sizeChanged
        case reachedPixelLimit
    }

    private(set) var pixelHeight: Int
    let pixelWidth: Int

    private var previousFrame: CGImage
    private var segments: [CGImage]
    private let maximumPixelCount: Int

    init(firstFrame: CGImage, maximumPixelCount: Int = 50_000_000) {
        previousFrame = firstFrame
        segments = [firstFrame]
        pixelWidth = firstFrame.width
        pixelHeight = firstFrame.height
        self.maximumPixelCount = maximumPixelCount
    }

    mutating func append(_ frame: CGImage) -> AppendResult {
        guard frame.width == previousFrame.width,
              frame.height == previousFrame.height else {
            return .sizeChanged
        }

        switch VerticalScrollFrameMatcher.match(previous: previousFrame, current: frame) {
        case .unchanged:
            return .unchanged
        case .unaligned:
            return .unaligned
        case .displacement(let displacement):
            guard pixelWidth <= maximumPixelCount / max(pixelHeight + displacement, 1) else {
                return .reachedPixelLimit
            }

            let newRows = CGRect(
                x: 0,
                y: frame.height - displacement,
                width: frame.width,
                height: displacement
            )
            guard let segment = frame.cropping(to: newRows) else {
                return .unaligned
            }

            segments.append(segment)
            previousFrame = frame
            pixelHeight += displacement
            return .appended(displacement: displacement)
        }
    }

    func makeImage() -> CGImage? {
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .none
        var top = pixelHeight
        for segment in segments {
            top -= segment.height
            context.draw(
                segment,
                in: CGRect(x: 0, y: top, width: segment.width, height: segment.height)
            )
        }
        return context.makeImage()
    }
}

enum VerticalScrollFrameMatch: Equatable {
    case unchanged
    case displacement(Int)
    case unaligned
}

enum VerticalScrollFrameMatcher {
    private struct Candidate {
        let displacement: Int
        let score: Double
    }

    /// Finds how many pixel rows the document moved upward between frames.
    /// A content row at `previous[y]` should reappear at
    /// `current[y + displacement]`. Pixel buffers use Quartz's bottom-up row
    /// order, so this is the bitmap-space form of content moving upward.
    static func match(previous: CGImage, current: CGImage) -> VerticalScrollFrameMatch {
        guard previous.width == current.width,
              previous.height == current.height,
              previous.width >= 8,
              previous.height >= 16,
              let previousPixels = PixelBuffer(image: previous),
              let currentPixels = PixelBuffer(image: current) else {
            return .unaligned
        }

        let unchangedScore = score(
            previous: previousPixels,
            current: currentPixels,
            displacement: 0
        )
        if unchangedScore <= 0.8 {
            return .unchanged
        }

        let maximumDisplacement = max(1, Int(Double(previous.height) * 0.82))
        let coarseStep = max(1, maximumDisplacement / 96)
        var best: Candidate?

        var displacement = 1
        while displacement <= maximumDisplacement {
            consider(
                Candidate(
                    displacement: displacement,
                    score: score(
                        previous: previousPixels,
                        current: currentPixels,
                        displacement: displacement
                    )
                ),
                best: &best
            )
            displacement += coarseStep
        }

        guard let coarseBest = best else { return .unaligned }
        let refinementStart = max(1, coarseBest.displacement - coarseStep)
        let refinementEnd = min(maximumDisplacement, coarseBest.displacement + coarseStep)
        for refinedDisplacement in refinementStart...refinementEnd {
            consider(
                Candidate(
                    displacement: refinedDisplacement,
                    score: score(
                        previous: previousPixels,
                        current: currentPixels,
                        displacement: refinedDisplacement
                    )
                ),
                best: &best
            )
        }

        guard let best,
              best.score <= 28,
              best.score + 1.0 < unchangedScore * 0.78 else {
            return .unaligned
        }
        return .displacement(best.displacement)
    }

    private static func consider(_ candidate: Candidate, best: inout Candidate?) {
        guard candidate.score.isFinite else { return }
        if best == nil || candidate.score < best!.score {
            best = candidate
        }
    }

    private static func score(
        previous: PixelBuffer,
        current: PixelBuffer,
        displacement: Int
    ) -> Double {
        let overlapHeight = previous.height - displacement
        let headerInset = max(1, previous.height / 10)
        let footerInset = max(1, previous.height / 40)
        let startY = min(headerInset, max(0, overlapHeight - 1))
        let endY = overlapHeight - footerInset
        guard endY > startY + 3 else { return .infinity }

        let horizontalInset = max(1, previous.width / 20)
        let startX = horizontalInset
        let endX = previous.width - horizontalInset
        guard endX > startX + 3 else { return .infinity }

        let xStep = max(1, (endX - startX) / 44)
        let yStep = max(1, (endY - startY) / 44)
        var total = 0.0
        var count = 0

        var y = startY
        while y < endY {
            var x = startX
            while x < endX {
                total += previous.colorDifference(
                    x: x,
                    y: y,
                    other: current,
                    otherX: x,
                    otherY: y + displacement
                )
                count += 1
                x += xStep
            }
            y += yStep
        }

        guard count > 0 else { return .infinity }
        return total / Double(count)
    }
}

private struct PixelBuffer {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(image: CGImage) {
        let imageWidth = image.width
        let imageHeight = image.height
        var storage = [UInt8](repeating: 0, count: imageWidth * imageHeight * 4)
        let didDraw = storage.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: imageWidth,
                    height: imageHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: imageWidth * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue
                  ) else {
                return false
            }
            context.interpolationQuality = .none
            context.translateBy(x: 0, y: CGFloat(imageHeight))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            return true
        }
        guard didDraw else { return nil }
        width = imageWidth
        height = imageHeight
        bytes = storage
    }

    func colorDifference(
        x: Int,
        y: Int,
        other: PixelBuffer,
        otherX: Int,
        otherY: Int
    ) -> Double {
        let offset = (y * width + x) * 4
        let otherOffset = (otherY * other.width + otherX) * 4
        let red = abs(Int(bytes[offset]) - Int(other.bytes[otherOffset]))
        let green = abs(Int(bytes[offset + 1]) - Int(other.bytes[otherOffset + 1]))
        let blue = abs(Int(bytes[offset + 2]) - Int(other.bytes[otherOffset + 2]))
        return Double(red + green + blue) / 3
    }
}
#endif
