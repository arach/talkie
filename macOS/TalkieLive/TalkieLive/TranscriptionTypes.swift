//
//  TranscriptionTypes.swift
//  TalkieLive
//
//  Transcription types (inlined from TalkieCore for standalone build)
//

import Foundation
import SwiftUI

// MARK: - Transcription Types

public struct TranscriptionRequest {
    public let audioPath: String  // Path to audio file - caller owns the file
    public let languageHint: String?
    public let isLive: Bool

    public init(audioPath: String, languageHint: String? = nil, isLive: Bool = false) {
        self.audioPath = audioPath
        self.languageHint = languageHint
        self.isLive = isLive
    }
}

public struct Transcript {
    public let text: String
    public let confidence: Float?

    public init(text: String, confidence: Float? = nil) {
        self.text = text
        self.confidence = confidence
    }
}

public protocol TranscriptionService: Sendable {
    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript
}

// MARK: - Whisper Model Options

public enum WhisperModel: String, CaseIterable, Codable, Sendable {
    case tiny = "openai_whisper-tiny"
    case base = "openai_whisper-base"
    case small = "openai_whisper-small"
    case distilLargeV3 = "distil-whisper_distil-large-v3"

    public var displayName: String {
        switch self {
        case .tiny: return "Tiny (~40MB)"
        case .base: return "Base (~75MB)"
        case .small: return "Small (~250MB)"
        case .distilLargeV3: return "Large V3 (~750MB)"
        }
    }

    public var description: String {
        switch self {
        case .tiny: return "Fastest, basic quality"
        case .base: return "Fast, good quality"
        case .small: return "Balanced speed/quality"
        case .distilLargeV3: return "Best quality, slower"
        }
    }
}

// MARK: - Whisper Service (Stub for standalone build)
// TODO: Replace with XPC calls to TalkieEngine

@MainActor
public final class WhisperService: ObservableObject {
    public static let shared = WhisperService()

    @Published public var isTranscribing = false
    @Published public var loadedModel: WhisperModel?
    @Published public var downloadProgress: Float = 0
    @Published public var isDownloading = false
    @Published public var lastError: String?

    @Published public private(set) var downloadedModels: Set<WhisperModel> = []
    @Published public private(set) var isWarmingUp = false
    @Published public private(set) var warmupStartTime: Date?

    private init() {
        // In standalone mode, models are managed by TalkieEngine
        // This stub just provides the UI bindings
    }

    public func resetTranscriptionState() {
        isTranscribing = false
        lastError = nil
    }

    public func refreshDownloadedModels() {
        // TODO: Query TalkieEngine via XPC
    }

    public func isModelDownloaded(_ model: WhisperModel) -> Bool {
        downloadedModels.contains(model)
    }

    public func downloadModel(_ model: WhisperModel) async throws {
        // TODO: Send download request to TalkieEngine via XPC
        isDownloading = true
        defer { isDownloading = false }

        // Simulate for now
        try await Task.sleep(nanoseconds: 500_000_000)
        downloadedModels.insert(model)
    }

    public func transcribe(audioData: Data, model: WhisperModel = .small) async throws -> String {
        // TODO: Send to TalkieEngine via XPC
        isTranscribing = true
        defer { isTranscribing = false }

        throw WhisperError.modelNotLoaded
    }

    public func preloadModel(_ model: WhisperModel) async throws {
        // TODO: Send preload request to TalkieEngine via XPC
    }

    public func unloadModel() {
        loadedModel = nil
    }

    public func deleteModel(_ model: WhisperModel) throws {
        // TODO: Send delete request to TalkieEngine via XPC
        downloadedModels.remove(model)
        if loadedModel == model {
            unloadModel()
        }
    }
}

// MARK: - Errors

public enum WhisperError: LocalizedError {
    case alreadyTranscribing
    case modelNotLoaded
    case modelLoadFailed(Error)
    case transcriptionFailed(Error)
    case noAudioData

    public var errorDescription: String? {
        switch self {
        case .alreadyTranscribing:
            return "A transcription is already in progress"
        case .modelNotLoaded:
            return "Whisper model is not loaded"
        case .modelLoadFailed(let error):
            return "Failed to load model: \(error.localizedDescription)"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .noAudioData:
            return "No audio data available"
        }
    }
}
