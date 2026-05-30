//
//  OCRTextObservation.swift
//  TalkieKit
//
//  OCR geometry for markup anchoring (normalized Vision coordinates).
//

import CoreGraphics
import Foundation

public struct OCRTextObservation: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var text: String
    /// Normalized bounding box, origin bottom-left (Vision convention).
    public var boundingBox: CaptureMarkupRect
    public var confidence: Float

    public init(
        id: String = UUID().uuidString,
        text: String,
        boundingBox: CaptureMarkupRect,
        confidence: Float = 1
    ) {
        self.id = id
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }

    /// Top-left normalized rect for markup (0…1, origin top-left).
    public var markupRect: CaptureMarkupRect {
        CaptureMarkupRect(
            x: boundingBox.x,
            y: 1 - boundingBox.y - boundingBox.height,
            width: boundingBox.width,
            height: boundingBox.height
        )
    }
}

public struct OCRTextLine: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var text: String
    /// Normalized rect for markup anchoring (origin top-left).
    public var boundingBox: CaptureMarkupRect
    public var observationIDs: [String]
    public var confidence: Float

    public init(
        id: String = UUID().uuidString,
        text: String,
        boundingBox: CaptureMarkupRect,
        observationIDs: [String] = [],
        confidence: Float = 1
    ) {
        self.id = id
        self.text = text
        self.boundingBox = boundingBox
        self.observationIDs = observationIDs
        self.confidence = confidence
    }
}

public struct OCRGeometryResult: Codable, Sendable {
    public var imageWidth: Double
    public var imageHeight: Double
    public var observations: [OCRTextObservation]
    public var fullText: String
    public var lines: [OCRTextLine]?
    /// Distinctive OCR token → normalized markup rect (origin top-left).
    public var anchors: [String: CaptureMarkupRect]?

    public init(
        imageWidth: Double,
        imageHeight: Double,
        observations: [OCRTextObservation],
        fullText: String,
        lines: [OCRTextLine]? = nil,
        anchors: [String: CaptureMarkupRect]? = nil
    ) {
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.observations = observations
        self.fullText = fullText
        self.lines = lines
        self.anchors = anchors
    }

    enum CodingKeys: String, CodingKey {
        case imageWidth
        case imageHeight
        case observations
        case fullText
        case lines
        case anchors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imageWidth = try container.decode(Double.self, forKey: .imageWidth)
        imageHeight = try container.decode(Double.self, forKey: .imageHeight)
        observations = try container.decode([OCRTextObservation].self, forKey: .observations)
        fullText = try container.decode(String.self, forKey: .fullText)
        lines = try container.decodeIfPresent([OCRTextLine].self, forKey: .lines)
        anchors = try container.decodeIfPresent([String: CaptureMarkupRect].self, forKey: .anchors)
    }

    public func anchor(matching query: String) -> CaptureMarkupRect? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let anchors {
            for token in Self.anchorQueryTokens(in: trimmed) {
                if let rect = anchors[token] {
                    return rect
                }
            }
        }
        if trimmed.localizedCaseInsensitiveContains("first word"),
           let first = observations.first {
            return firstWordRect(in: first)
        }
        if let match = observations.first(where: { $0.text.localizedStandardContains(trimmed) }) {
            return match.markupRect
        }
        return nil
    }

    private func firstWordRect(in observation: OCRTextObservation) -> CaptureMarkupRect {
        let parts = observation.text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count > 1 else { return observation.markupRect }
        let ratio = Double(parts[0].count) / Double(max(observation.text.count, 1))
        var rect = observation.markupRect
        rect.width *= ratio
        return rect
    }

    private static func anchorQueryTokens(in text: String) -> [String] {
        text
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0).uppercased() }
            .filter { !$0.isEmpty }
    }
}
