//
//  WallpaperLuminanceSampler.swift
//  Talkie
//
//  Picks one of three Palette schemes (PEARL / SLATE / AMBER) by sampling
//  the region of the screen where the capture HUD is about to appear and
//  measuring its perceived brightness.
//
//  Falls back to NSApp.effectiveAppearance when sampling can't run (e.g.,
//  Screen Recording permission revoked mid-session). Never throws.
//

import AppKit
import CoreImage
import TalkieKit

@MainActor
enum WallpaperLuminanceSampler {

    /// Returns the trio palette that best contrasts with the wallpaper
    /// region under the HUD. PEARL for light, SLATE for mid, AMBER for dark.
    static func samplePalette(for screenRect: CGRect) async -> Palette {
        if let image = await ScreenshotCaptureService.shared.captureScreenRegion(screenRect: screenRect),
           let brightness = averageBrightness(of: image) {
            return classify(brightness: brightness)
        }
        return appearanceFallback()
    }

    // MARK: - Classification

    /// Three-bucket split. Boundaries chosen so plain Sonoma defaults
    /// (light gradients ≈ 0.78, dark photos ≈ 0.12) land cleanly, and the
    /// SLATE band only catches genuinely mid-tone wallpapers.
    static func classify(brightness: CGFloat) -> Palette {
        switch brightness {
        case ..<0.33:   return .amber
        case 0.33..<0.67: return .slate
        default:        return .pearl
        }
    }

    // MARK: - Pixel average

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Mean perceived brightness (BT.709 luma) of a CGImage. Uses the
    /// GPU-accelerated `CIAreaAverage` filter which collapses the whole
    /// image to a single pixel, then reads the RGB back.
    private static func averageBrightness(of cgImage: CGImage) -> CGFloat? {
        let ci = CIImage(cgImage: cgImage)
        let extent = ci.extent
        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )

        let r = CGFloat(pixel[0]) / 255.0
        let g = CGFloat(pixel[1]) / 255.0
        let b = CGFloat(pixel[2]) / 255.0
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    // MARK: - Fallback

    private static func appearanceFallback() -> Palette {
        let name = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return name == .darkAqua ? .amber : .pearl
    }
}
