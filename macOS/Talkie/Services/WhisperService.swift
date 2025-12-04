//
//  WhisperService.swift
//  Talkie
//
//  Local speech-to-text transcription using WhisperKit
//

import Foundation
import WhisperKit
import os

private let logger = Logger(subsystem: "jdi.talkie-os-mac", category: "WhisperService")

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

// MARK: - Whisper Service

@MainActor
class WhisperService: ObservableObject {
    static let shared = WhisperService()

    @Published var isTranscribing = false
    @Published var loadedModel: WhisperModel?
    @Published var downloadProgress: Float = 0
    @Published var isDownloading = false
    @Published var lastError: String?

    /// Cached set of downloaded models - updated on download/delete
    @Published private(set) var downloadedModels: Set<WhisperModel> = []

    private var whisperKit: WhisperKit?
    private var currentModelId: String?

    private init() {
        refreshDownloadedModels()
    }

    /// Refresh the cached downloaded models state
    func refreshDownloadedModels() {
        downloadedModels = Set(WhisperModel.allCases.filter { checkModelExists($0) })
        logger.debug("Refreshed downloaded models: \(self.downloadedModels.map { $0.rawValue })")
    }

    // MARK: - Model Management

    /// Check if a model is downloaded locally (uses cached state)
    func isModelDownloaded(_ model: WhisperModel) -> Bool {
        downloadedModels.contains(model)
    }

    /// Actually check filesystem for model existence (used internally)
    private func checkModelExists(_ model: WhisperModel) -> Bool {
        let modelPath = getWhisperKitModelPath(for: model)
        return FileManager.default.fileExists(atPath: modelPath)
    }

    /// Get WhisperKit model storage path (matches WhisperKit's internal structure)
    private func getWhisperKitModelPath(for model: WhisperModel) -> String {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return supportDir
            .appendingPathComponent("Talkie/WhisperModels/models/argmaxinc/whisperkit-coreml")
            .appendingPathComponent(model.rawValue)
            .path
    }

    /// Get URL for model storage base
    private func getModelsBaseURL() -> URL {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = supportDir.appendingPathComponent("Talkie/WhisperModels")
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        return modelsDir
    }

    /// Download a model if not already present
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

        logger.info("Downloading Whisper model: \(model.rawValue)")
        await SystemEventManager.shared.log(.workflow, "Downloading Whisper model", detail: model.displayName)

        do {
            // Ensure base directory exists
            let baseURL = getModelsBaseURL()
            logger.info("Download base: \(baseURL.path)")

            // WhisperKit handles model download automatically during initialization
            _ = try await WhisperKit(
                model: model.rawValue,
                downloadBase: baseURL,
                verbose: true
            )

            downloadProgress = 1.0
            downloadedModels.insert(model) // Update cached state
            logger.info("Model \(model.rawValue) downloaded successfully to \(baseURL.path)")
            await SystemEventManager.shared.log(.workflow, "Whisper model ready", detail: model.displayName)
        } catch {
            lastError = error.localizedDescription
            logger.error("Failed to download model: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Transcription

    /// Transcribe audio data to text
    /// - Parameters:
    ///   - audioData: Raw audio data (m4a, wav, etc.)
    ///   - model: Which Whisper model to use
    /// - Returns: Transcribed text
    func transcribe(audioData: Data, model: WhisperModel = .small) async throws -> String {
        // Wait for any ongoing transcription (up to 60 seconds)
        let maxWaitTime: TimeInterval = 60
        let startTime = Date()

        while isTranscribing {
            if Date().timeIntervalSince(startTime) > maxWaitTime {
                logger.warning("Timeout waiting for previous transcription")
                throw WhisperError.alreadyTranscribing
            }
            logger.debug("Waiting for previous transcription to complete...")
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }

        isTranscribing = true
        lastError = nil

        defer {
            isTranscribing = false
        }

        logger.info("Starting transcription with model: \(model.rawValue)")
        await SystemEventManager.shared.log(.transcribe, "Transcription started", detail: model.displayName)

        // Load model if needed or if different model requested
        if whisperKit == nil || currentModelId != model.rawValue {
            logger.info("Loading Whisper model: \(model.rawValue)")

            do {
                whisperKit = try await WhisperKit(
                    model: model.rawValue,
                    downloadBase: getModelsBaseURL(),
                    verbose: false
                )
                currentModelId = model.rawValue
                loadedModel = model
            } catch {
                lastError = "Failed to load model: \(error.localizedDescription)"
                logger.error("Failed to load Whisper model: \(error.localizedDescription)")
                await SystemEventManager.shared.log(.error, "Model load failed", detail: error.localizedDescription)
                throw WhisperError.modelLoadFailed(error)
            }
        }

        guard let whisper = whisperKit else {
            throw WhisperError.modelNotLoaded
        }

        // Write audio data to temporary file (WhisperKit needs a file path)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        do {
            try audioData.write(to: tempURL)

            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }

            // Transcribe
            await SystemEventManager.shared.log(.transcribe, "Processing audio", detail: "\(audioData.count / 1024) KB")
            let results = try await whisper.transcribe(audioPath: tempURL.path)

            // Combine all segments into full transcript
            let transcript = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

            logger.info("Transcription complete: \(transcript.prefix(100))...")
            await SystemEventManager.shared.log(.transcribe, "Transcription complete", detail: "\(transcript.count) chars")

            return transcript
        } catch {
            lastError = "Transcription failed: \(error.localizedDescription)"
            logger.error("Transcription failed: \(error.localizedDescription)")
            await SystemEventManager.shared.log(.error, "Transcription failed", detail: error.localizedDescription)
            throw WhisperError.transcriptionFailed(error)
        }
    }

    /// Unload the current model to free memory
    func unloadModel() {
        whisperKit = nil
        currentModelId = nil
        loadedModel = nil
        logger.info("Whisper model unloaded")
    }

    /// Delete a downloaded model
    func deleteModel(_ model: WhisperModel) throws {
        let modelPath = getWhisperKitModelPath(for: model)

        if FileManager.default.fileExists(atPath: modelPath) {
            try FileManager.default.removeItem(atPath: modelPath)
        }

        // Update cached state
        downloadedModels.remove(model)

        // Unload if this was the loaded model
        if loadedModel == model {
            unloadModel()
        }

        logger.info("Deleted Whisper model: \(model.rawValue)")
    }
}

// MARK: - Errors

enum WhisperError: LocalizedError {
    case alreadyTranscribing
    case modelNotLoaded
    case modelLoadFailed(Error)
    case transcriptionFailed(Error)
    case noAudioData

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
        }
    }
}
