//
//  VisionOCRService.swift
//  Talkie
//
//  Vision-framework OCR wrapper for running text extraction on screenshot files
//  already stored on disk (attached to TalkieObjects or in the tray).
//
//  Supports two-pass recognition: fast scan to detect text presence,
//  then accurate pass with language correction for high-quality results.
//

import AppKit
import CoreGraphics
import Foundation
import Vision
import TalkieKit

private let log = Log(.system)

enum VisionOCRError: Error {
    case requestFailed(Error)
    case noTextFound
    case imageLoadFailed
}

enum VisionOCRQuality: Sendable {
    /// Quick detection — lower accuracy, no language correction. ~50-100ms.
    case fast
    /// Full accuracy with language correction. ~200-500ms.
    case accurate
}

@MainActor
final class VisionOCRService {
    static let shared = VisionOCRService()
    private init() {}

    /// Recognize text in the image at `url`. Returns joined lines in reading order.
    func recognizeText(atURL url: URL, quality: VisionOCRQuality = .accurate) async throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw VisionOCRError.imageLoadFailed
        }
        return try await recognizeText(in: image, quality: quality)
    }

    /// Recognize text in the given CGImage. Joins observations top-to-bottom, left-to-right.
    func recognizeText(in image: CGImage, quality: VisionOCRQuality = .accurate) async throws -> String {
        let recognitionLevel: VNRequestTextRecognitionLevel = quality == .fast ? .fast : .accurate
        let useLangCorrection = quality == .accurate

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: VisionOCRError.requestFailed(error))
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: VisionOCRError.noTextFound)
                    return
                }

                let sorted = observations.sorted { lhs, rhs in
                    let yDelta = rhs.boundingBox.midY - lhs.boundingBox.midY
                    if abs(yDelta) > 0.01 {
                        return yDelta < 0
                    }
                    return lhs.boundingBox.minX < rhs.boundingBox.minX
                }

                let lines = sorted.compactMap { $0.topCandidates(1).first?.string }
                let joined = lines.joined(separator: "\n")
                if joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continuation.resume(throwing: VisionOCRError.noTextFound)
                } else {
                    continuation.resume(returning: joined)
                }
            }
            request.recognitionLevel = recognitionLevel
            request.usesLanguageCorrection = useLangCorrection

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                log.error("OCR perform failed: \(error.localizedDescription)")
                continuation.resume(throwing: VisionOCRError.requestFailed(error))
            }
        }
    }
}
