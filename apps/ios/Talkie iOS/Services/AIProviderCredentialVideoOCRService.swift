//
//  AIProviderCredentialVideoOCRService.swift
//  Talkie iOS
//
//  Samples selected videos and runs local OCR for credential capture.
//

import AVFoundation
import UIKit

enum AIProviderCredentialVideoOCRService {
    struct Result {
        let recognizedText: String
        let framesScanned: Int
    }

    enum VideoOCRError: LocalizedError {
        case couldNotLoadVideo
        case noFramesFound
        case noTextFound

        var errorDescription: String? {
            switch self {
            case .couldNotLoadVideo:
                return "Could not load this video."
            case .noFramesFound:
                return "No readable frames were found in this video."
            case .noTextFound:
                return "No text was found in the sampled video frames."
            }
        }
    }

    static func extractCredentialText(from data: Data) async throws -> Result {
        let tempURL = URL.temporaryDirectory
            .appending(path: "talkie-credential-video-\(UUID().uuidString).mov")

        do {
            try data.write(to: tempURL, options: [.atomic])
            defer { try? FileManager.default.removeItem(at: tempURL) }
            return try await extractCredentialText(from: tempURL)
        } catch let error as VideoOCRError {
            throw error
        } catch {
            throw VideoOCRError.couldNotLoadVideo
        }
    }

    static func extractCredentialText(from url: URL) async throws -> Result {
        let frames = try await sampleFrames(from: url)

        guard !frames.isEmpty else {
            throw VideoOCRError.noFramesFound
        }

        var recognizedPages: [String] = []
        recognizedPages.reserveCapacity(frames.count)

        for frame in frames {
            do {
                let result = try await ScreenshotOCRService.extractText(from: frame)
                if !result.text.isEmpty {
                    recognizedPages.append(result.text)
                }
            } catch {
                AppLogger.ai.debug("Video OCR skipped frame: \(error.localizedDescription)")
            }
        }

        let recognizedText = recognizedPages
            .map(normalizedText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        guard !recognizedText.isEmpty else {
            throw VideoOCRError.noTextFound
        }

        AppLogger.ai.info("Video OCR extracted \(recognizedText.count) characters from \(frames.count) frame(s)")
        return Result(recognizedText: recognizedText, framesScanned: frames.count)
    }

    private static func sampleFrames(from url: URL, maxFrames: Int = 18) async throws -> [UIImage] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        guard durationSeconds.isFinite, durationSeconds >= 0 else {
            throw VideoOCRError.couldNotLoadVideo
        }

        let frameCount = max(1, min(maxFrames, Int(ceil(max(durationSeconds, 1) * 2))))
        let times = sampleTimes(duration: duration, durationSeconds: durationSeconds, frameCount: frameCount)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.15, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.15, preferredTimescale: 600)

        var frames: [UIImage] = []
        frames.reserveCapacity(times.count)

        for time in times {
            do {
                let cgImage = try await generateCGImage(from: generator, at: time)
                frames.append(UIImage(cgImage: cgImage))
            } catch {
                AppLogger.ai.debug("Video OCR could not sample frame: \(error.localizedDescription)")
            }
        }

        return frames
    }

    private static func generateCGImage(
        from generator: AVAssetImageGenerator,
        at time: CMTime
    ) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let image else {
                    continuation.resume(throwing: VideoOCRError.noFramesFound)
                    return
                }

                continuation.resume(returning: image)
            }
        }
    }

    private static func sampleTimes(
        duration: CMTime,
        durationSeconds: Double,
        frameCount: Int
    ) -> [CMTime] {
        guard frameCount > 1 else {
            return [.zero]
        }

        let timescale = duration.timescale == 0 ? 600 : duration.timescale
        return (0..<frameCount).map { index in
            let fraction = Double(index) / Double(frameCount - 1)
            return CMTime(
                seconds: durationSeconds * fraction,
                preferredTimescale: timescale
            )
        }
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
