//
//  LLMVisionContent.swift
//  TalkieKit
//

import Foundation

public enum LLMContentPart: Sendable {
    case text(String)
    case imageJPEG(Data)
    case imagePNG(Data)
}

public struct LLMVisionRequest: Sendable {
    public var parts: [LLMContentPart]
    public var options: LLMGenerationOptions

    public init(parts: [LLMContentPart], options: LLMGenerationOptions = .default) {
        self.parts = parts
        self.options = options
    }

    public static func describeImage(
        jpegData: Data,
        prompt: String,
        options: LLMGenerationOptions = LLMGenerationOptions(maxTokens: 1024)
    ) -> LLMVisionRequest {
        LLMVisionRequest(
            parts: [.text(prompt), .imageJPEG(jpegData)],
            options: options
        )
    }
}

public protocol LLMVisionProvider: LLMProvider {
    func generateVision(
        request: LLMVisionRequest,
        model: String
    ) async throws -> String
}

public extension LLMProvider {
    var supportsVision: Bool { self is any LLMVisionProvider }

    func generateVisionIfAvailable(
        request: LLMVisionRequest,
        model: String
    ) async throws -> String {
        guard let vision = self as? any LLMVisionProvider else {
            throw LLMError.generationFailed("Provider \(id) does not support vision")
        }
        return try await vision.generateVision(request: request, model: model)
    }
}

public struct ScreenshotRegionDescription: Codable, Sendable, Equatable {
    public var role: String
    /// Normalized rect in 0…1 coordinates (origin top-left), if the model can localize it.
    public var bbox: CaptureMarkupRect?
    public var textSummary: String
    public var anchorTokens: [String]

    public init(
        role: String,
        bbox: CaptureMarkupRect? = nil,
        textSummary: String,
        anchorTokens: [String] = []
    ) {
        self.role = role
        self.bbox = bbox
        self.textSummary = textSummary
        self.anchorTokens = anchorTokens
    }

    enum CodingKeys: String, CodingKey {
        case role
        case bbox
        case textSummary
        case text_summary
        case anchorTokens
        case anchor_tokens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        bbox = try container.decodeIfPresent(CaptureMarkupRect.self, forKey: .bbox)
        textSummary = try container.decodeIfPresent(String.self, forKey: .textSummary)
            ?? container.decodeIfPresent(String.self, forKey: .text_summary)
            ?? ""
        anchorTokens = try container.decodeIfPresent([String].self, forKey: .anchorTokens)
            ?? container.decodeIfPresent([String].self, forKey: .anchor_tokens)
            ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encodeIfPresent(bbox, forKey: .bbox)
        try container.encode(textSummary, forKey: .text_summary)
        try container.encode(anchorTokens, forKey: .anchorTokens)
    }
}

public struct ScreenshotDescription: Codable, Sendable, Equatable {
    public var regions: [ScreenshotRegionDescription]
    public var primaryFocus: String
    public var rawResponse: String?

    public init(
        regions: [ScreenshotRegionDescription] = [],
        primaryFocus: String,
        rawResponse: String? = nil
    ) {
        self.regions = regions
        self.primaryFocus = primaryFocus
        self.rawResponse = rawResponse
    }

    public var contextString: String {
        var parts = ["Primary focus: \(primaryFocus)"]
        if !regions.isEmpty {
            let regionLines = regions.map { region in
                let bboxText: String
                if let bbox = region.bbox {
                    bboxText = " bbox={x:\(bbox.x),y:\(bbox.y),w:\(bbox.width),h:\(bbox.height)}"
                } else {
                    bboxText = ""
                }
                let anchors = region.anchorTokens.isEmpty ? "" : " anchors=\(region.anchorTokens.joined(separator: ","))"
                return "- \(region.role)\(bboxText)\(anchors): \(region.textSummary)"
            }
            parts.append("Regions:\n\(regionLines.joined(separator: "\n"))")
        }
        return parts.joined(separator: "\n")
    }
}

@MainActor
public enum LLMVisionService {
    public static func describeScreenshot(
        jpegData: Data,
        ocrSummary: String?,
        ocrAnchors: [String: CaptureMarkupRect]? = nil,
        model: String? = nil
    ) async throws -> String {
        let description = try await describeScreenshotStructured(
            jpegData: jpegData,
            ocrSummary: ocrSummary,
            ocrAnchors: ocrAnchors,
            model: model
        )
        return description.contextString
    }

    public static func describeScreenshotStructured(
        jpegData: Data,
        ocrSummary: String?,
        ocrAnchors: [String: CaptureMarkupRect]? = nil,
        model: String? = nil
    ) async throws -> ScreenshotDescription {
        let request = LLMVisionRequest.describeImage(
            jpegData: jpegData,
            prompt: structuredPrompt(ocrSummary: ocrSummary, ocrAnchors: ocrAnchors),
            options: LLMGenerationOptions(temperature: 0.2, maxTokens: 1536)
        )

        let providerOrder = ["gemini", "openai"]
        for providerId in providerOrder {
            guard let provider = LLMProviderRegistry.shared.provider(for: providerId),
                  await provider.isAvailable,
                  provider.supportsVision else { continue }
            let modelId = model ?? LLMProviderRegistry.shared.defaultModelId(for: providerId)
            let raw = try await provider.generateVisionIfAvailable(request: request, model: modelId)
            return decodeStructuredDescription(raw)
        }
        throw LLMError.providerNotAvailable("vision")
    }

    public static func describeScreenshotStructured(
        jpegData: Data,
        ocrGeometry: OCRGeometryResult,
        model: String? = nil
    ) async throws -> ScreenshotDescription {
        try await describeScreenshotStructured(
            jpegData: jpegData,
            ocrSummary: ocrGeometry.fullText,
            ocrAnchors: ocrGeometry.anchors,
            model: model
        )
    }

    private static func structuredPrompt(
        ocrSummary: String?,
        ocrAnchors: [String: CaptureMarkupRect]?
    ) -> String {
        let anchorsJSON = encodedAnchors(ocrAnchors)
        return """
        Describe this screenshot for an annotation agent. Return ONLY valid JSON, no markdown fences.

        Schema:
        {
          "primaryFocus": "<one sentence describing what the screenshot is mainly showing>",
          "regions": [
            {
              "role": "header|body|sidebar|toolbar|dialog|form|table|list|media|footer|other",
              "bbox": {"x": 0.0, "y": 0.0, "width": 0.0, "height": 0.0},
              "text_summary": "<short text/UI summary for this region>",
              "anchorTokens": ["<OCR TOKEN FROM MAP>"]
            }
          ]
        }

        Coordinates are normalized 0..1 with origin top-left. Prefer approximate bboxes over omitting them.
        Only cite anchorTokens that appear in the OCR anchor map below. Do not invent labels or anchors.

        OCR excerpt:
        \(ocrSummary ?? "(none)")

        OCR anchor map (token -> normalized top-left bbox):
        \(anchorsJSON)
        """
    }

    private static func encodedAnchors(_ anchors: [String: CaptureMarkupRect]?) -> String {
        guard let anchors, !anchors.isEmpty else { return "{}" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(anchors),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private static func decodeStructuredDescription(_ raw: String) -> ScreenshotDescription {
        let cleaned = stripJSONFences(raw)
        if let data = cleaned.data(using: .utf8),
           var description = try? JSONDecoder().decode(ScreenshotDescription.self, from: data) {
            description.rawResponse = raw
            return description
        }
        return ScreenshotDescription(primaryFocus: raw, rawResponse: raw)
    }

    private static func stripJSONFences(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count >= 2,
               String(lines.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```"),
               String(lines.last ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
                text = lines.dropFirst().dropLast().joined(separator: "\n")
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
