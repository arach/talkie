//
//  TalkieObjectMetadata.swift
//  TalkieKit
//
//  Metadata and assets structs for TalkieObject.
//  Shared across all targets: main app, Agent, CLI.
//

import Foundation

// MARK: - TalkieObject Assets (consolidated media/attachment blob)

public struct TalkieObjectAssets: Codable, Sendable {
    public var segments: TimedTranscription?
    public var screenshots: [RecordingScreenshot]?
    public var clips: [RecordingClip]?
    public var attachments: [RecordingAttachment]?
    /// Receipts for text that was seen/offered from non-user sources (OCR, paste, dictation).
    /// Canonical `TalkieObject.text` is user-owned and never auto-filled from these.
    public var textProvenance: [ProvenanceSegment]?

    public var isEmpty: Bool {
        segments == nil
        && (screenshots ?? []).isEmpty
        && (clips ?? []).isEmpty
        && (attachments ?? []).isEmpty
        && (textProvenance ?? []).isEmpty
    }

    public init(
        segments: TimedTranscription? = nil,
        screenshots: [RecordingScreenshot]? = nil,
        clips: [RecordingClip]? = nil,
        attachments: [RecordingAttachment]? = nil,
        textProvenance: [ProvenanceSegment]? = nil
    ) {
        self.segments = segments
        self.screenshots = screenshots
        self.clips = clips
        self.attachments = attachments
        self.textProvenance = textProvenance
    }

    public static func from(json: String?) -> TalkieObjectAssets? {
        guard let json = json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TalkieObjectAssets.self, from: data)
    }

    public func toJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Provenance Segment

/// A receipt for text that was offered to a TalkieObject from a non-user source.
/// Segments are for "how did this get here" tracking — never auto-applied to canonical text.
public struct ProvenanceSegment: Codable, Sendable, Identifiable, Equatable {
    public enum Source: String, Codable, Sendable {
        case ocr
        case paste
        case dictation
        case userEdit       // explicit user revision captured as a receipt
        case workflow       // output of a workflow / AI routine
    }

    public var id: UUID
    public var source: Source
    public var originalText: String
    /// When the text was produced (OCR completed, paste received, etc.).
    public var timestamp: Date
    /// If the user promoted this segment into canonical text, when that happened.
    public var appliedAt: Date?
    /// Optional pointer to the asset that produced this text (e.g. screenshot filename for OCR).
    public var sourceAssetId: String?
    /// Free-form source detail (OCR engine name, workflow id, etc.). Kept loose on purpose.
    public var sourceDetail: String?

    public init(
        id: UUID = UUID(),
        source: Source,
        originalText: String,
        timestamp: Date = Date(),
        appliedAt: Date? = nil,
        sourceAssetId: String? = nil,
        sourceDetail: String? = nil
    ) {
        self.id = id
        self.source = source
        self.originalText = originalText
        self.timestamp = timestamp
        self.appliedAt = appliedAt
        self.sourceAssetId = sourceAssetId
        self.sourceDetail = sourceDetail
    }
}

// MARK: - Recording Metadata (JSON blob for dictation context)

public struct RecordingMetadata: Codable, Hashable, Sendable {
    public var app: AppContext?
    public var endApp: AppContext?
    public var context: RichContext?
    public var performance: PerformanceMetrics?
    public var routing: RoutingInfo?
    public var audio: AudioMetrics?
    public var refinement: RefinementInfo?
    public var selection: SelectionInfo?
    public var serviceCalls: [ServiceCallRecord]?

    public init(
        app: AppContext? = nil,
        endApp: AppContext? = nil,
        context: RichContext? = nil,
        performance: PerformanceMetrics? = nil,
        routing: RoutingInfo? = nil,
        audio: AudioMetrics? = nil,
        refinement: RefinementInfo? = nil,
        selection: SelectionInfo? = nil,
        serviceCalls: [ServiceCallRecord]? = nil
    ) {
        self.app = app
        self.endApp = endApp
        self.context = context
        self.performance = performance
        self.routing = routing
        self.audio = audio
        self.refinement = refinement
        self.selection = selection
        self.serviceCalls = serviceCalls
    }

    /// Decode from JSON string
    public static func from(json: String?) -> RecordingMetadata? {
        guard let json = json,
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(RecordingMetadata.self, from: data)
    }

    /// Encode to JSON string
    public func toJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

public struct AppContext: Codable, Hashable, Sendable {
    public var bundleId: String?
    public var name: String?
    public var windowTitle: String?

    public init(bundleId: String? = nil, name: String? = nil, windowTitle: String? = nil) {
        self.bundleId = bundleId
        self.name = name
        self.windowTitle = windowTitle
    }
}

public struct RichContext: Codable, Hashable, Sendable {
    public var browserURL: String?
    public var terminalWorkingDir: String?
    public var documentURL: String?

    public init(browserURL: String? = nil, terminalWorkingDir: String? = nil, documentURL: String? = nil) {
        self.browserURL = browserURL
        self.terminalWorkingDir = terminalWorkingDir
        self.documentURL = documentURL
    }
}

public struct PerformanceMetrics: Codable, Hashable, Sendable {
    public var engineMs: Int?
    public var endToEndMs: Int?
    public var inAppMs: Int?
    public var sessionId: String?

    public init(engineMs: Int? = nil, endToEndMs: Int? = nil, inAppMs: Int? = nil, sessionId: String? = nil) {
        self.engineMs = engineMs
        self.endToEndMs = endToEndMs
        self.inAppMs = inAppMs
        self.sessionId = sessionId
    }
}

public struct RoutingInfo: Codable, Hashable, Sendable {
    public var mode: String?
    public var wasRouted: Bool?
    public var pasteTimestamp: Double?

    public init(mode: String? = nil, wasRouted: Bool? = nil, pasteTimestamp: Double? = nil) {
        self.mode = mode
        self.wasRouted = wasRouted
        self.pasteTimestamp = pasteTimestamp
    }
}

public struct AudioMetrics: Codable, Hashable, Sendable {
    public var peakAmplitude: Float?
    public var averageAmplitude: Float?

    public init(peakAmplitude: Float? = nil, averageAmplitude: Float? = nil) {
        self.peakAmplitude = peakAmplitude
        self.averageAmplitude = averageAmplitude
    }
}

// MARK: - Service Call Record

/// Structured trace of any outbound API call — LLM, TTS, webhook, etc.
/// Reusable primitive across all features that talk to external services.
public struct ServiceCallRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: String                // "llm", "tts", "webhook"
    public var provider: String            // "openai", "groq", "elevenlabs", "apple"
    public var model: String?              // "gpt-4o-mini", "llama-3.3-70b-versatile", "tts-1"
    public var endpoint: String?           // "chat/completions", "audio/speech"
    public var messages: [ServiceCallMessage]?  // System + user messages (for LLM calls)
    public var inputText: String?          // Raw input (for TTS calls)
    public var response: String?           // Output text (truncated if needed)
    public var latencyMs: Int?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var status: String              // "success", "error", "timeout"
    public var error: String?
    public var timestamp: Date

    public init(
        id: UUID = UUID(),
        kind: String,
        provider: String,
        model: String? = nil,
        endpoint: String? = nil,
        messages: [ServiceCallMessage]? = nil,
        inputText: String? = nil,
        response: String? = nil,
        latencyMs: Int? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        status: String = "success",
        error: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.provider = provider
        self.model = model
        self.endpoint = endpoint
        self.messages = messages
        self.inputText = inputText
        self.response = response
        self.latencyMs = latencyMs
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.status = status
        self.error = error
        self.timestamp = timestamp
    }
}

/// A single message in an LLM conversation (system, user, assistant)
public struct ServiceCallMessage: Codable, Hashable, Sendable {
    public var role: String     // "system", "user", "assistant"
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

// MARK: - Selection Info (for readouts)

public struct SelectionInfo: Codable, Hashable, Sendable {
    public var inputText: String?           // Original selected text
    public var mode: String?                // "verbatim", "summary", "explanation"
    public var voiceId: String?             // TTS voice used
    public var delivery: String?            // "speak", "paste", "clipboard", "save"
    public var llmPrompt: String?           // Prompt sent to LLM (nil if verbatim)
    public var llmResponse: String?         // LLM output (nil if verbatim)
    public var llmModel: String?            // Model used for processing
    public var llmProvider: String?         // Provider used
    public var processingMs: Int?           // LLM processing time
    public var endToEndMs: Int?             // Total time from hotkey to speech complete
    public var contextRuleName: String?     // Matched context rule name, if any

    public init(
        inputText: String? = nil,
        mode: String? = nil,
        voiceId: String? = nil,
        delivery: String? = nil,
        llmPrompt: String? = nil,
        llmResponse: String? = nil,
        llmModel: String? = nil,
        llmProvider: String? = nil,
        processingMs: Int? = nil,
        endToEndMs: Int? = nil,
        contextRuleName: String? = nil
    ) {
        self.inputText = inputText
        self.mode = mode
        self.voiceId = voiceId
        self.delivery = delivery
        self.llmPrompt = llmPrompt
        self.llmResponse = llmResponse
        self.llmModel = llmModel
        self.llmProvider = llmProvider
        self.processingMs = processingMs
        self.endToEndMs = endToEndMs
        self.contextRuleName = contextRuleName
    }
}
