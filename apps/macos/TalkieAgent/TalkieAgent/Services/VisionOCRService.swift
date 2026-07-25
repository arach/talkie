//
//  VisionOCRService.swift
//  TalkieAgent
//
//  Vision-framework OCR wrapper used by the selection capture OCR fallback tier.
//

import AppKit
import Foundation
import CoreGraphics
import ScreenCaptureKit
import Vision
import TalkieKit

private let log = Log(.system)

enum VisionOCRError: Error {
    case requestFailed(Error)
    case noTextFound
}

@MainActor
final class VisionOCRService {
    static let shared = VisionOCRService()
    private init() {}

    /// Recognize text in the given CGImage. Joins observations with newlines in
    /// top-to-bottom reading order.
    func recognizeText(in image: CGImage) async throws -> String {
        let geometry = try await recognizeTextWithGeometry(in: image)
        return geometry.fullText
    }

    /// Recognize text with normalized bounding boxes so markup can place
    /// privacy blur layers directly over the detected text.
    func recognizeTextWithGeometry(in image: CGImage) async throws -> OCRGeometryResult {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: VisionOCRError.requestFailed(error))
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: VisionOCRError.noTextFound)
                    return
                }

                // Sort top-to-bottom by y, then left-to-right by x.
                // Vision returns normalized bounds with origin at bottom-left, so higher y = closer to top.
                let sorted = observations.sorted { lhs, rhs in
                    let yDelta = rhs.boundingBox.midY - lhs.boundingBox.midY
                    if abs(yDelta) > 0.01 {
                        return yDelta < 0
                    }
                    return lhs.boundingBox.minX < rhs.boundingBox.minX
                }

                let mapped = sorted.compactMap { observation -> OCRTextObservation? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let box = observation.boundingBox
                    return OCRTextObservation(
                        text: candidate.string,
                        boundingBox: CaptureMarkupRect(
                            x: box.origin.x,
                            y: box.origin.y,
                            width: box.width,
                            height: box.height
                        ),
                        confidence: candidate.confidence
                    )
                }
                let joined = mapped.map(\.text).joined(separator: "\n")
                if joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continuation.resume(throwing: VisionOCRError.noTextFound)
                } else {
                    continuation.resume(
                        returning: OCRGeometryResult(
                            imageWidth: Double(image.width),
                            imageHeight: Double(image.height),
                            observations: mapped,
                            fullText: joined
                        )
                    )
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                log.error("OCR perform failed: \(error.localizedDescription)")
                continuation.resume(throwing: VisionOCRError.requestFailed(error))
            }
        }
    }

    /// Capture the pixels inside `screenRect` (Cocoa screen coords, bottom-left origin)
    /// and return a CGImage. Returns nil if capture fails or region is empty.
    ///
    /// Uses ScreenCaptureKit (CGWindowListCreateImage is unavailable on macOS 15+).
    /// Requires Screen Recording permission for the host process.
    func captureScreenRegion(_ screenRect: CGRect) async -> CGImage? {
        guard screenRect.width > 1, screenRect.height > 1 else { return nil }

        // 1. Figure out which display contains the region (by its midpoint)
        let midPoint = NSPoint(x: screenRect.midX, y: screenRect.midY)
        guard let nsScreen = NSScreen.screens.first(where: { NSMouseInRect(midPoint, $0.frame, false) })
                ?? NSScreen.main else {
            log.error("OCR capture: no screen found for region \(String(describing: screenRect))")
            return nil
        }

        let screenFrame = nsScreen.frame
        // Convert Cocoa screen rect (bottom-left origin, global coords) to
        // display-local CG rect (top-left origin, in points within the screen).
        let displayLocalRect = CGRect(
            x: screenRect.origin.x - screenFrame.origin.x,
            y: screenFrame.height - (screenRect.origin.y - screenFrame.origin.y) - screenRect.height,
            width: screenRect.width,
            height: screenRect.height
        )

        // 2. Resolve SCDisplay by CGDirectDisplayID
        guard let directDisplayIDValue = nsScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            log.error("OCR capture: no NSScreenNumber on NSScreen")
            return nil
        }
        let directDisplayID = CGDirectDisplayID(directDisplayIDValue.uint32Value)

        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first(where: { $0.displayID == directDisplayID })
                  ?? content.displays.first else {
                log.error("OCR capture: no SCDisplay available")
                return nil
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            // Use point-scaled pixel dimensions (retina backing) for the config size
            let scale = nsScreen.backingScaleFactor
            config.width = Int(screenRect.width * scale)
            config.height = Int(screenRect.height * scale)
            config.sourceRect = displayLocalRect
            config.scalesToFit = false
            config.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            return image
        } catch {
            log.error("OCR capture failed: \(error.localizedDescription)")
            return nil
        }
    }
}
