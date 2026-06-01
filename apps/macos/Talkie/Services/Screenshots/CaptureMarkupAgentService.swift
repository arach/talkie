//
//  CaptureMarkupAgentService.swift
//  Talkie
//
//  Agent loop for screenshot markup: OCR/VLM context → layer plan → sidecar.
//

import AppKit
import CoreGraphics
import Foundation
import TalkieKit

private let log = Log(.workflow)

enum CaptureMarkupAgentError: LocalizedError {
    case imageLoadFailed
    case planDecodeFailed
    case planEmpty
    case providerUnavailable
    case applyFailed

    var errorDescription: String? {
        switch self {
        case .imageLoadFailed: return "Could not load screenshot image."
        case .planDecodeFailed: return "Agent returned invalid markup plan JSON."
        case .planEmpty: return "Agent did not return any markup changes to apply."
        case .providerUnavailable:
            return "Configure an AI provider to run capture markup."
        case .applyFailed:
            return "Could not apply markup plan. The agent produced unsupported or no-op layer changes."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .providerUnavailable:
            return "Open Settings → AI Providers and add a Gemini, Anthropic, OpenAI, or Groq API key, then try Run again."
        case .planDecodeFailed:
            return "Try a shorter instruction, or switch to a model that supports JSON responses."
        case .planEmpty, .applyFailed:
            return "Try a more specific instruction, such as highlight the error row or arrow to the title."
        case .imageLoadFailed:
            return "Check that the screenshot still exists and is a readable PNG or JPEG file."
        }
    }
}

struct CaptureMarkupPlan: Codable, Sendable {
    var ops: [CaptureMarkupLayerOp]
    var summary: String?
}

/// Coarse phases of a markup run, surfaced to the Work Thread so the user
/// watches what the agent is doing instead of a bare "RUNNING" spinner.
/// These are the real async boundaries inside `plan()` + `runInstruction()`
/// — the run is not token-streamed, but each phase is genuine elapsed work.
enum CaptureMarkupRunPhase: Sendable {
    case reading                  // OCR geometry pass starting
    case read(detail: String)     // OCR done — e.g. "42 text regions"
    case describing               // VLM scene read starting
    case described                // scene read done
    case planning(model: String)  // LLM planning starting — provider · model
    case planned(detail: String)  // plan decoded — summary + op count
    case applying                 // ops applied to the document
}

@MainActor
final class CaptureMarkupAgentService {
    static let shared = CaptureMarkupAgentService()
    private init() {}

    func currentModelLabel(providerId: String? = nil, modelId: String? = nil) async -> String? {
        guard let providerInfo = await resolveProviderAndModel(providerId: providerId, modelId: modelId) else {
            return nil
        }
        return Self.modelLabel(provider: providerInfo.provider, modelId: providerInfo.modelId)
    }

    func describe(imageURL: URL) async throws -> String {
        guard let jpeg = try jpegData(for: imageURL) else {
            throw CaptureMarkupAgentError.imageLoadFailed
        }
        let ocr = try? await VisionOCRService.shared.recognizeTextWithGeometry(atURL: imageURL)
        return try await TalkieKit.LLMVisionService.describeScreenshot(
            jpegData: jpeg,
            ocrSummary: ocr?.fullText
        )
    }

    func plan(
        imageURL: URL,
        instruction: String,
        includedLayers: [CaptureMarkupLayer] = [],
        existing: CaptureMarkupDocument? = nil,
        providerId: String? = nil,
        modelId: String? = nil,
        onPhase: ((CaptureMarkupRunPhase) -> Void)? = nil
    ) async throws -> CaptureMarkupPlan {
        onPhase?(.reading)
        let geometry: OCRGeometryResult
        if let recognized = try? await VisionOCRService.shared.recognizeTextWithGeometry(atURL: imageURL) {
            geometry = recognized
        } else {
            geometry = try emptyGeometry(for: imageURL)
        }
        onPhase?(.read(detail: Self.regionDetail(geometry)))
        onPhase?(.describing)
        let description = try? await describe(imageURL: imageURL)
        onPhase?(.described)

        guard let providerInfo = await resolveProviderAndModel(providerId: providerId, modelId: modelId) else {
            throw CaptureMarkupAgentError.providerUnavailable
        }
        onPhase?(.planning(model: Self.modelLabel(provider: providerInfo.provider, modelId: providerInfo.modelId)))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let geometryJSON = String(data: try encoder.encode(geometry), encoding: .utf8) ?? "{}"
        let existingJSON: String
        if let existing, let data = try? encoder.encode(existing) {
            existingJSON = String(data: data, encoding: .utf8) ?? "{}"
        } else {
            existingJSON = "{}"
        }
        let includedLayersJSON: String
        if includedLayers.isEmpty {
            includedLayersJSON = "[]"
        } else if let data = try? encoder.encode(includedLayers),
                  let json = String(data: data, encoding: .utf8) {
            includedLayersJSON = json
        } else {
            includedLayersJSON = "[]"
        }

        let prompt = """
        You are a screenshot markup planner. Return ONLY valid JSON (no markdown fences).

        Schema:
        {
          "summary": "short explanation",
          "ops": [
            { "action": "add", "layer": { "id": "<uuid>", "kind": "rect|arrow|label|guide|highlight", ... } }
          ]
        }
        Escape every double-quote inside string values (for example, write \\\"TALKIE\\\"), and never include unescaped quotes within JSON strings.

        Normalized coordinates use 0..1 with origin top-left.
        Layer fields:
        - rect/highlight: frame {x,y,width,height}, color hex, optional label
        - arrow: from {x,y}, to {x,y}, color, optional label
        - label: frame, text
        - guide: orientation "h"|"v"|"both", interval pixels (default 50), color

        Use OCR observations to anchor text matches. Instruction:
        \(instruction)

        Tagged markup items for this message:
        \(includedLayersJSON)

        If tagged markup items are present, treat them as the explicit target
        for the instruction. You may modify, label, move around, point at, or
        add related marks near those tagged items.

        OCR geometry:
        \(geometryJSON)

        Scene description:
        \(description ?? "(none)")

        Existing document (apply as revision):
        \(existingJSON)
        """

        let system = """
        Emit structured markup operations for Talkie capture markup. \
        Prefer highlight rects around matched text, guide grids when asked, \
        arrows for callouts. Keep layers minimal and legible.
        """
        var options = GenerationOptions(maxTokens: 2048, systemPrompt: system)
        options.temperature = 0.2
        options.jsonMode = true

        let raw = try await providerInfo.provider.generate(
            prompt: prompt,
            model: providerInfo.modelId,
            options: options
        )
        log.debug("Markup plan raw response", detail: raw)

        let cleaned = Self.stripJSONFences(raw)
        do {
            let decoded = try Self.decodePlan(from: cleaned)
            onPhase?(.planned(detail: Self.planDetail(decoded)))
            return decoded
        } catch {
            log.error("Markup plan decode failed", detail: cleaned.prefix(400).description, error: error)
            let decodeError = String(describing: error)

            let retryPrompt = """
            Your previous response was not valid JSON: \(decodeError)

            Here is what you returned:
            \(raw)

            Return the same content as valid JSON, escaping all internal double-quotes as \\". \
            Schema unchanged. Return ONLY valid JSON with no markdown fences.
            """

            let retryRaw = try await providerInfo.provider.generate(
                prompt: retryPrompt,
                model: providerInfo.modelId,
                options: options
            )
            log.debug("Markup plan retry raw response", detail: retryRaw)

            let retryCleaned = Self.stripJSONFences(retryRaw)
            do {
                let decoded = try Self.decodePlan(from: retryCleaned)
                onPhase?(.planned(detail: Self.planDetail(decoded)))
                return decoded
            } catch {
                log.error("Markup plan retry decode failed", detail: retryCleaned.prefix(400).description, error: error)
                throw CaptureMarkupAgentError.planDecodeFailed
            }
        }
    }

    func applyPlan(
        imageURL: URL,
        plan: CaptureMarkupPlan,
        existing: CaptureMarkupDocument? = nil
    ) throws -> CaptureMarkupDocument {
        guard !plan.ops.isEmpty else {
            throw CaptureMarkupAgentError.planEmpty
        }

        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CaptureMarkupAgentError.imageLoadFailed
        }

        var document = existing ?? CaptureMarkupStorage.load(forImageURL: imageURL)
            ?? CaptureMarkupDocument(
                imageWidth: Double(image.width),
                imageHeight: Double(image.height)
            )
        let before = document.layers
        document.apply(ops: plan.ops)
        guard document.layers != before else {
            throw CaptureMarkupAgentError.applyFailed
        }
        try CaptureMarkupStorage.save(document, forImageURL: imageURL)
        return document
    }

    func renderPNG(imageURL: URL, document: CaptureMarkupDocument? = nil) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CaptureMarkupAgentError.imageLoadFailed
        }
        let doc = document ?? CaptureMarkupStorage.load(forImageURL: imageURL)
            ?? CaptureMarkupDocument(imageWidth: Double(image.width), imageHeight: Double(image.height))
        guard let data = CaptureMarkupRenderer.renderPNGData(image: image, document: doc) else {
            throw CaptureMarkupAgentError.imageLoadFailed
        }
        return data
    }

    /// Materialize the computed doc into a flat artifact and write it to the
    /// exports folder. The source capture and the sidecar are untouched —
    /// export reads the doc, never mutates it. Returns the written file URL.
    @discardableResult
    func exportArtifact(
        imageURL: URL,
        document: CaptureMarkupDocument? = nil,
        format: CaptureMarkupExportFormat,
        scale: Int
    ) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CaptureMarkupAgentError.imageLoadFailed
        }
        let doc = document ?? CaptureMarkupStorage.load(forImageURL: imageURL)
            ?? CaptureMarkupDocument(imageWidth: Double(image.width), imageHeight: Double(image.height))
        guard let data = CaptureMarkupRenderer.encodedData(
            image: image,
            document: doc,
            format: format,
            scale: CGFloat(scale)
        ) else {
            throw CaptureMarkupAgentError.imageLoadFailed
        }
        return try CaptureMarkupStorage.writeExport(
            data,
            forImageURL: imageURL,
            format: format,
            scale: scale
        )
    }

    func runInstruction(
        imageURL: URL,
        instruction: String,
        includedLayers: [CaptureMarkupLayer] = [],
        existing: CaptureMarkupDocument? = nil,
        openWebBay: Bool = true,
        providerId: String? = nil,
        modelId: String? = nil,
        onPhase: ((CaptureMarkupRunPhase) -> Void)? = nil
    ) async throws -> CaptureMarkupDocument {
        do {
            let currentDocument = existing ?? CaptureMarkupStorage.load(forImageURL: imageURL)
            let plan = try await plan(
                imageURL: imageURL,
                instruction: instruction,
                includedLayers: includedLayers,
                existing: currentDocument,
                providerId: providerId,
                modelId: modelId,
                onPhase: onPhase
            )
            onPhase?(.applying)
            let document = try applyPlan(
                imageURL: imageURL,
                plan: plan,
                existing: currentDocument
            )
            if openWebBay {
                CaptureMarkupCoordinator.shared.openSession(
                    imageURL: imageURL,
                    document: document,
                    instruction: instruction
                )
            }
            return document
        } catch {
            if openWebBay {
                CaptureMarkupCoordinator.shared.presentAgentError(error)
            }
            throw error
        }
    }

    private func jpegData(for imageURL: URL) throws -> Data? {
        // Downscaled, AI-bound copy. The stored screenshot stays full-res.
        ScreenshotCaptureService.aiJPEGData(for: imageURL)
    }

    private func emptyGeometry(for imageURL: URL) throws -> OCRGeometryResult {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CaptureMarkupAgentError.imageLoadFailed
        }

        return OCRGeometryResult(
            imageWidth: Double(image.width),
            imageHeight: Double(image.height),
            observations: [],
            fullText: "",
            lines: [],
            anchors: [:]
        )
    }

    private static func regionDetail(_ geometry: OCRGeometryResult) -> String {
        let n = geometry.observations.count
        return n > 0 ? "\(n) text region\(n == 1 ? "" : "s")" : "no text found"
    }

    private static func planDetail(_ plan: CaptureMarkupPlan) -> String {
        let n = plan.ops.count
        let ops = "\(n) op\(n == 1 ? "" : "s")"
        if let summary = plan.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            let trimmed = summary.count > 60 ? String(summary.prefix(57)) + "…" : summary
            return "\(trimmed) · \(ops)"
        }
        return ops
    }

    private static func modelLabel(provider: LLMProvider, modelId: String) -> String {
        "\(provider.name) · \(modelId)"
    }

    private func resolveProviderAndModel(
        providerId: String?,
        modelId: String?
    ) async -> (provider: LLMProvider, modelId: String)? {
        let registry = LLMProviderRegistry.shared
        let cleanProviderId = providerId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModelId = modelId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleanProviderId,
           !cleanProviderId.isEmpty,
           let provider = registry.provider(for: cleanProviderId),
           await provider.isAvailable {
            let resolvedModelId = (cleanModelId?.isEmpty == false ? cleanModelId : nil) ?? provider.defaultModelId
            if !resolvedModelId.isEmpty {
                return (provider, resolvedModelId)
            }
        }

        let curatedModels = LLMAgentModelPreferences.curatedModels(from: registry.allModels)
        for model in curatedModels {
            guard let provider = registry.provider(for: model.provider),
                  await provider.isAvailable else { continue }
            return (provider, model.id)
        }

        if LLMAgentModelPreferences.hasStoredConfiguration {
            return nil
        }

        return await registry.resolveProviderAndModel()
    }

    private static func stripJSONFences(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "")
            text = text.replacingOccurrences(of: "```", with: "")
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private static func decodePlan(from json: String) throws -> CaptureMarkupPlan {
        guard let data = json.data(using: .utf8) else {
            throw CaptureMarkupAgentError.planDecodeFailed
        }
        return try JSONDecoder().decode(CaptureMarkupPlan.self, from: data)
    }
}
