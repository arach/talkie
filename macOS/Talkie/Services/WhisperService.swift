//
//  WhisperService.swift
//  Talkie
//
//  Speech-to-text transcription - uses TalkieEngine XPC service
//

import Foundation
import os
import Observation
import TalkieKit

private let logger = Logger(subsystem: "jdi.talkie.core", category: "WhisperService")

// MARK: - Whisper Model Options

enum WhisperModel: String, CaseIterable, Codable {
    case tiny = "openai_whisper-tiny"
    case base = "openai_whisper-base"
    case small = "openai_whisper-small"
    case distilLargeV3 = "distil-whisper_distil-large-v3"

    var displayName: String {
        switch self {
        case .tiny: return "Tiny (~40MB)"
        case .base: return "Base (~75MB)"
        case .small: return "Small (~250MB)"
        case .distilLargeV3: return "Large V3 (~750MB)"
        }
    }

    var description: String {
        switch self {
        case .tiny: return "Fastest, basic quality"
        case .base: return "Fast, good quality"
        case .small: return "Balanced speed/quality"
        case .distilLargeV3: return "Best quality, slower"
        }
    }
}

// MARK: - Whisper Service (XPC-only)

@MainActor
@Observable
class WhisperService {
    static let shared = WhisperService()

    var isTranscribing = false
    var loadedModel: WhisperModel?
    var downloadProgress: Float = 0
    var isDownloading = false
    var lastError: String?

    /// Cached set of downloaded models - queried from TalkieEngine
    private(set) var downloadedModels: Set<WhisperModel> = []

    private init() {
        Task {
            await refreshDownloadedModels()
        }
    }

    /// Force reset the transcription state if it gets stuck
    func resetTranscriptionState() {
        logger.warning("Force resetting transcription state (was: \(self.isTranscribing))")
        isTranscribing = false
        lastError = nil
    }

    /// Refresh the cached downloaded models state from TalkieEngine
    func refreshDownloadedModels() async {
        // TODO: Query TalkieEngine for downloaded models via XPC
        // For now, assume models are managed by TalkieEngine
        logger.debug("Refreshing downloaded models from TalkieEngine")
    }

    // MARK: - Model Management

    /// Check if a model is downloaded (queries TalkieEngine)
    func isModelDownloaded(_ model: WhisperModel) -> Bool {
        downloadedModels.contains(model)
    }

    /// Download a model via TalkieEngine
    func downloadModel(_ model: WhisperModel) async throws {
        guard !isModelDownloaded(model) else {
            logger.info("Model \(model.rawValue) already downloaded")
            return
        }

        isDownloading = true
        downloadProgress = 0
        lastError = nil

        defer {
            isDownloading = false
        }

        logger.info("Requesting model download from TalkieEngine: \(model.rawValue)")
        await SystemEventManager.shared.log(.workflow, "Downloading Whisper model", detail: model.displayName)

        // TODO: Request download from TalkieEngine via XPC
        // For now, simulate
        try await Task.sleep(for: .milliseconds(500))
        downloadedModels.insert(model)
        downloadProgress = 1.0

        logger.info("Model \(model.rawValue) download requested")
    }

    // MARK: - Transcription

    /// Transcribe audio data to text via TalkieEngine XPC
    /// - Parameters:
    ///   - audioData: Audio data to transcribe
    ///   - model: Whisper model to use
    ///   - priority: Task priority (default: .medium)
    func transcribe(
        audioData: Data,
        model: WhisperModel = .small,
        priority: TranscriptionPriority = .medium
    ) async throws -> String {
        isTranscribing = true
        lastError = nil

        defer {
            isTranscribing = false
        }

        let engine = EngineClient.shared

        // Ensure connected
        let connected = await engine.ensureConnected()
        guard connected else {
            lastError = "TalkieEngine not available"
            throw WhisperError.engineNotAvailable
        }

        logger.info("[Engine] Transcribing \(audioData.count / 1024)KB via TalkieEngine (priority: \(priority.displayName))")
        await SystemEventManager.shared.log(.transcribe, "Using TalkieEngine", detail: model.displayName)

        do {
            // Use family prefix format expected by TalkieEngine (e.g., "whisper:openai_whisper-small")
            let transcript = try await engine.transcribe(
                audioData: audioData,
                modelId: "whisper:\(model.rawValue)",
                priority: priority
            )
            logger.info("[Engine] Transcription complete: \(transcript.prefix(100))...")
            await SystemEventManager.shared.log(.transcribe, "Transcription complete", detail: "\(transcript.count) chars")
            return transcript
        } catch {
            lastError = error.localizedDescription
            logger.error("[Engine] Transcription failed: \(error.localizedDescription)")
            await SystemEventManager.shared.log(.error, "Transcription failed", detail: error.localizedDescription)
            throw WhisperError.transcriptionFailed(error)
        }
    }

    /// Unload the current model (signals TalkieEngine)
    func unloadModel() {
        loadedModel = nil
        logger.info("Whisper model unload requested")
        // TODO: Signal TalkieEngine to unload model via XPC
    }

    /// Delete a downloaded model via TalkieEngine
    func deleteModel(_ model: WhisperModel) throws {
        downloadedModels.remove(model)

        if loadedModel == model {
            unloadModel()
        }

        logger.info("Model deletion requested: \(model.rawValue)")
        // TODO: Signal TalkieEngine to delete model via XPC
    }
}

// MARK: - Errors

enum WhisperError: LocalizedError {
    case alreadyTranscribing
    case modelNotLoaded
    case modelLoadFailed(Error)
    case transcriptionFailed(Error)
    case noAudioData
    case engineNotAvailable

    var errorDescription: String? {
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
        case .engineNotAvailable:
            return "TalkieEngine is not available"
        }
    }
}
