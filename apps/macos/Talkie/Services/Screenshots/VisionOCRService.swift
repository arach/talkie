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

    /// Recognize text with bounding boxes for markup anchoring.
    func recognizeTextWithGeometry(
        atURL url: URL,
        quality: VisionOCRQuality = .accurate
    ) async throws -> OCRGeometryResult {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw VisionOCRError.imageLoadFailed
        }
        return try await recognizeTextWithGeometry(in: image, quality: quality)
    }

    /// Recognize text in the given CGImage. Joins observations top-to-bottom, left-to-right.
    func recognizeText(in image: CGImage, quality: VisionOCRQuality = .accurate) async throws -> String {
        let geometry = try await recognizeTextWithGeometry(in: image, quality: quality)
        return geometry.fullText
    }

    func recognizeTextWithGeometry(
        in image: CGImage,
        quality: VisionOCRQuality = .accurate
    ) async throws -> OCRGeometryResult {
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

                let sorted = Self.sortObservations(observations)
                let mapped = sorted.compactMap { observation -> OCRTextObservation? in
                    guard let string = observation.topCandidates(1).first?.string else { return nil }
                    let box = observation.boundingBox
                    return OCRTextObservation(
                        text: string,
                        boundingBox: CaptureMarkupRect(
                            x: box.origin.x,
                            y: box.origin.y,
                            width: box.width,
                            height: box.height
                        ),
                        confidence: observation.topCandidates(1).first?.confidence ?? 0
                    )
                }

                let lines = mapped.map(\.text)
                let joined = lines.joined(separator: "\n")
                if joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continuation.resume(throwing: VisionOCRError.noTextFound)
                    return
                }

                let clusteredLines = Self.clusterLines(mapped)
                let anchors = Self.buildAnchors(from: mapped)
                continuation.resume(
                    returning: OCRGeometryResult(
                        imageWidth: Double(image.width),
                        imageHeight: Double(image.height),
                        observations: mapped,
                        fullText: joined,
                        lines: clusteredLines,
                        anchors: anchors
                    )
                )
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

    private static func sortObservations(_ observations: [VNRecognizedTextObservation]) -> [VNRecognizedTextObservation] {
        observations.sorted { lhs, rhs in
            let yDelta = rhs.boundingBox.midY - lhs.boundingBox.midY
            if abs(yDelta) > 0.01 {
                return yDelta < 0
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
    }

    private static func clusterLines(_ observations: [OCRTextObservation]) -> [OCRTextLine] {
        guard !observations.isEmpty else { return [] }

        let heights = observations.map(\.boundingBox.height).sorted()
        let medianHeight = heights[heights.count / 2]
        let yTolerance = max(0.012, min(0.04, medianHeight * 0.65))

        var rows: [[OCRTextObservation]] = []
        for observation in observations {
            if let lastIndex = rows.indices.last,
               let averageMidY = rows[lastIndex].averageVisionMidY,
               abs(averageMidY - observation.boundingBox.midY) <= yTolerance {
                rows[lastIndex].append(observation)
            } else {
                rows.append([observation])
            }
        }

        return rows.map { row in
            let sortedRow = row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            return OCRTextLine(
                text: sortedRow.map(\.text).joined(separator: " "),
                boundingBox: Self.unionMarkupRect(for: sortedRow),
                observationIDs: sortedRow.map(\.id),
                confidence: sortedRow.averageConfidence
            )
        }
    }

    private static func buildAnchors(
        from observations: [OCRTextObservation],
        limit: Int = 48
    ) -> [String: CaptureMarkupRect] {
        struct TokenCandidate {
            var key: String
            var rect: CaptureMarkupRect
            var readingIndex: Int
            var score: Double
        }

        let stopWords: Set<String> = [
            "THE", "AND", "FOR", "WITH", "FROM", "THIS", "THAT", "YOU", "YOUR",
            "ARE", "WAS", "WERE", "HAVE", "HAS", "HAD", "NOT", "BUT", "CAN",
            "ALL", "ANY", "NEW", "EDIT", "VIEW", "FILE", "OPEN", "SAVE"
        ]

        var candidates: [TokenCandidate] = []
        var frequencies: [String: Int] = [:]
        var readingIndex = 0

        for observation in observations {
            for token in tokenRanges(in: observation.text) {
                let key = token.text.uppercased()
                guard key.count >= 2, !stopWords.contains(key) else { continue }
                frequencies[key, default: 0] += 1
                candidates.append(
                    TokenCandidate(
                        key: key,
                        rect: estimatedMarkupRect(for: token.range, in: observation),
                        readingIndex: readingIndex,
                        score: tokenScore(key)
                    )
                )
                readingIndex += 1
            }
        }

        var firstCandidatesByKey: [String: TokenCandidate] = [:]
        for candidate in candidates where firstCandidatesByKey[candidate.key] == nil {
            var scored = candidate
            if frequencies[candidate.key] == 1 {
                scored.score += 8
            }
            firstCandidatesByKey[candidate.key] = scored
        }

        let selected = firstCandidatesByKey.values.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.readingIndex < rhs.readingIndex
        }.prefix(limit)

        return Dictionary(uniqueKeysWithValues: selected.map { ($0.key, $0.rect) })
    }

    private static func tokenScore(_ token: String) -> Double {
        var score = Double(min(token.count, 16))
        if token.contains(where: \.isNumber) { score += 3 }
        if token.contains(where: \.isLetter), token == token.uppercased() { score += 2 }
        if token.count >= 6 { score += 2 }
        return score
    }

    private static func tokenRanges(in text: String) -> [(text: String, range: Range<String.Index>)] {
        var results: [(String, Range<String.Index>)] = []
        var start: String.Index?
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if character.isLetter || character.isNumber {
                if start == nil {
                    start = index
                }
            } else if let tokenStart = start {
                results.append((String(text[tokenStart..<index]), tokenStart..<index))
                start = nil
            }
            index = text.index(after: index)
        }

        if let tokenStart = start {
            results.append((String(text[tokenStart..<text.endIndex]), tokenStart..<text.endIndex))
        }

        return results
    }

    private static func estimatedMarkupRect(
        for range: Range<String.Index>,
        in observation: OCRTextObservation
    ) -> CaptureMarkupRect {
        let text = observation.text
        let totalCharacters = max(text.count, 1)
        let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
        let tokenCharacters = text.distance(from: range.lowerBound, to: range.upperBound)
        let leftRatio = Double(startOffset) / Double(totalCharacters)
        let widthRatio = Double(max(tokenCharacters, 1)) / Double(totalCharacters)

        var rect = observation.markupRect
        rect.x += rect.width * leftRatio
        rect.width *= widthRatio
        return rect
    }

    private static func unionMarkupRect(for observations: [OCRTextObservation]) -> CaptureMarkupRect {
        guard let first = observations.first?.markupRect else {
            return CaptureMarkupRect(x: 0, y: 0, width: 0, height: 0)
        }
        return observations.dropFirst().reduce(first) { partial, observation in
            let rect = observation.markupRect
            let minX = min(partial.x, rect.x)
            let minY = min(partial.y, rect.y)
            let maxX = max(partial.x + partial.width, rect.x + rect.width)
            let maxY = max(partial.y + partial.height, rect.y + rect.height)
            return CaptureMarkupRect(
                x: minX,
                y: minY,
                width: maxX - minX,
                height: maxY - minY
            )
        }
    }
}

private extension Array where Element == OCRTextObservation {
    var averageVisionMidY: Double? {
        guard !isEmpty else { return nil }
        return reduce(0) { $0 + $1.boundingBox.midY } / Double(count)
    }

    var averageConfidence: Float {
        guard !isEmpty else { return 0 }
        return reduce(Float(0)) { $0 + $1.confidence } / Float(count)
    }
}

private extension CaptureMarkupRect {
    var minX: Double { x }
    var midY: Double { y + height / 2 }
}

// MARK: - Augmenter conformances
//
// Co-located with `VisionOCRService` because new .swift files can't be
// added to the Talkie xcodeproj without manual Xcode-side work
// (Services/ is a `<group>`, not a synchronized root). When the
// project gets converted to file-system-sync groups, split these into
// `Services/Augmenters/OCRAugmenter.swift` and
// `Services/Augmenters/WindowMetaAugmenter.swift`. See TLK-022.

/// OCR with geometry. Wraps the existing `VisionOCRService` and writes
/// the full `OCRGeometryResult` (observations + line-clustering + token
/// anchors) into the TK sidecar. Markup agents and the studio compare
/// page consume this for "circle the RUN button" style localization.
final class OCRAugmenter: Augmenter {
    let kind: TKAugmenterKind = .ocr
    let version: String = "vision-v1"
    let supportedAssetKinds: Set<TKSidecarAssetKind> = [.image]

    func run(_ task: AugmentationTask) async throws -> TKAugmentation? {
        let result: OCRGeometryResult
        do {
            result = try await VisionOCRService.shared.recognizeTextWithGeometry(
                atURL: task.assetURL,
                quality: .accurate
            )
        } catch VisionOCRError.noTextFound {
            // No text in the image — write an empty-result sentinel
            // so the (kind, version) pair lands in the sidecar.
            // Without this marker the catch-up sweep would re-run OCR
            // on text-free images (wallpapers, blank canvases) on
            // every launch indefinitely. Use the actual image
            // dimensions so the sentinel describes the asset
            // correctly even when observations are empty.
            let dims = Self.imageDimensions(for: task.assetURL)
            let empty = OCRGeometryResult(
                imageWidth: dims.width,
                imageHeight: dims.height,
                observations: [],
                fullText: ""
            )
            let data = try TKAugmentationData(encoding: empty)
            return TKAugmentation(kind: kind, version: version, data: data)
        }
        let data = try TKAugmentationData(encoding: result)
        return TKAugmentation(kind: kind, version: version, data: data)
    }

    private static func imageDimensions(for url: URL) -> (width: Double, height: Double) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return (0, 0)
        }
        return (Double(image.width), Double(image.height))
    }
}

/// Window context at capture time. Pulls from `TKAugmentationContext`
/// (captured synchronously at the protected-path save site) rather than
/// re-querying — by the time the augmenter runs the user has likely
/// switched windows, so live AppKit queries would return the wrong
/// answer. The capture site is responsible for stuffing the right keys
/// into context.
final class WindowMetaAugmenter: Augmenter {
    let kind: TKAugmenterKind = .windowMeta
    let version: String = "ctx-v1"
    let supportedAssetKinds: Set<TKSidecarAssetKind> = [.image]

    struct Payload: Codable {
        let windowTitle: String?
        let appName: String?
        let appBundleID: String?
        let displayName: String?
        let captureMode: String?
        let imageWidth: Int?
        let imageHeight: Int?
        let backingScale: Double?
    }

    func run(_ task: AugmentationTask) async throws -> TKAugmentation? {
        let payload = Payload(
            windowTitle: task.context["window.title"],
            appName:     task.context["window.app"],
            appBundleID: task.context["window.bundleId"],
            displayName: task.context["screen.name"],
            captureMode: task.context["capture.mode"],
            imageWidth:  task.context["asset.width"].flatMap(Int.init),
            imageHeight: task.context["asset.height"].flatMap(Int.init),
            backingScale: task.context["screen.backingScale"].flatMap(Double.init)
        )

        // If literally nothing is set, the augmenter has nothing to
        // contribute — return nil so the sidecar stays uncluttered.
        let anySet = [
            payload.windowTitle, payload.appName, payload.appBundleID,
            payload.displayName, payload.captureMode
        ].contains(where: { $0 != nil })
        guard anySet || payload.imageWidth != nil else { return nil }

        let data = try TKAugmentationData(encoding: payload)
        return TKAugmentation(kind: kind, version: version, data: data)
    }
}
