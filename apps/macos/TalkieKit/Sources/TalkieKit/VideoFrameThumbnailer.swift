//
//  VideoFrameThumbnailer.swift
//  TalkieKit
//
//  Small shared helper for showing at least one real video frame in capture
//  previews.
//

#if os(macOS)
import AppKit
import AVFoundation
import CoreMedia
import Foundation

public enum VideoFrameThumbnailer {
    public static func thumbnail(for url: URL, maxSize: CGFloat = 180) -> NSImage? {
        let generator = makeGenerator(for: url, maxSize: maxSize)

        for time in previewTimes {
            if let image = try? generator.copyCGImage(at: time, actualTime: nil) {
                return nsImage(from: image)
            }
        }

        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        for time in previewTimes {
            if let image = try? generator.copyCGImage(at: time, actualTime: nil) {
                return nsImage(from: image)
            }
        }

        return nil
    }

    public static func thumbnailAsync(for url: URL, maxSize: CGFloat = 180) async -> NSImage? {
        let generator = makeGenerator(for: url, maxSize: maxSize)

        for time in previewTimes {
            if let result = try? await generator.image(at: time) {
                return nsImage(from: result.image)
            }
        }

        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        for time in previewTimes {
            if let result = try? await generator.image(at: time) {
                return nsImage(from: result.image)
            }
        }

        return nil
    }

    private static var previewTimes: [CMTime] {
        [
            .zero,
            CMTime(seconds: 0.05, preferredTimescale: 600),
            CMTime(seconds: 0.2, preferredTimescale: 600),
            CMTime(seconds: 0.5, preferredTimescale: 600),
        ]
    }

    private static func makeGenerator(for url: URL, maxSize: CGFloat) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSize, height: maxSize)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .positiveInfinity
        return generator
    }

    private static func nsImage(from cgImage: CGImage) -> NSImage {
        NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
#endif
