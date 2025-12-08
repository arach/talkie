//
//  WhisperService.swift
//  TalkieServices
//
//  Local speech-to-text transcription using WhisperKit
//

import Foundation
import WhisperKit
import TalkieCore
import AVFoundation
import os

private let logger = Logger(subsystem: "live.talkie.services", category: "WhisperService")

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

// MARK: - Whisper Service

@MainActor
public final class WhisperService: ObservableObject {
    public static let shared = WhisperService()

    @Published public var isTranscribing = false
    @Published public var loadedModel: WhisperModel?
    @Published public var downloadProgress: Float = 0
    @Published public var isDownloading = false
    @Published public var lastError: String?

    @Published public private(set) var downloadedModels: Set<WhisperModel> = []

    private var whisperKit: WhisperKit?
    private var currentModelId: String?

    private init() {
        refreshDownloadedModels()
    }

    public func resetTranscriptionState() {
        logger.warning("Force resetting transcription state (was: \(self.isTranscribing))")
        isTranscribing = false
        lastError = nil
    }

    public func refreshDownloadedModels() {
        downloadedModels = Set(WhisperModel.allCases.filter { checkModelExists($0) })
        logger.debug("Refreshed downloaded models: \(self.downloadedModels.map { $0.rawValue })")
    }

    // MARK: - Model Management

    public func isModelDownloaded(_ model: WhisperModel) -> Bool {
        downloadedModels.contains(model)
    }

    private func checkModelExists(_ model: WhisperModel) -> Bool {
        let modelPath = getWhisperKitModelPath(for: model)
        return FileManager.default.fileExists(atPath: modelPath)
    }

    private func getWhisperKitModelPath(for model: WhisperModel) -> String {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return supportDir
            .appendingPathComponent("Talkie/WhisperModels/models/argmaxinc/whisperkit-coreml")
            .appendingPathComponent(model.rawValue)
            .path
    }

    private func getModelsBaseURL() -> URL {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = supportDir.appendingPathComponent("Talkie/WhisperModels")
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        return modelsDir
    }

    public func downloadModel(_ model: WhisperModel) async throws {
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

        do {
            let baseURL = getModelsBaseURL()
            logger.info("Download base: \(baseURL.path)")

            _ = try await WhisperKit(
                model: model.rawValue,
                downloadBase: baseURL,
                verbose: true
            )

            downloadProgress = 1.0
            downloadedModels.insert(model)
            logger.info("Model \(model.rawValue) downloaded successfully to \(baseURL.path)")
        } catch {
            lastError = error.localizedDescription
            logger.error("Failed to download model: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Transcription

    public func transcribe(audioData: Data, model: WhisperModel = .small) async throws -> String {
        let totalStart = Date()
        let maxWaitTime: TimeInterval = 60
        let startTime = Date()

        while isTranscribing {
            if Date().timeIntervalSince(startTime) > maxWaitTime {
                logger.warning("Timeout waiting for previous transcription")
                throw WhisperError.alreadyTranscribing
            }
            logger.debug("Waiting for previous transcription to complete...")
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        let waitTime = Date().timeIntervalSince(startTime)
        if waitTime > 0.1 {
            logger.info("⏳ Waited \(String(format: "%.1f", waitTime))s for previous transcription")
        }

        isTranscribing = true
        lastError = nil

        defer {
            isTranscribing = false
        }

        let audioSizeKB = audioData.count / 1024
        logger.info("🎤 Starting transcription: \(audioSizeKB) KB audio, model: \(model.rawValue)")

        // Track model loading time
        var modelLoadTime: TimeInterval = 0
        if whisperKit == nil || currentModelId != model.rawValue {
            let modelLoadStart = Date()
            logger.info("📦 Loading Whisper model: \(model.rawValue)")

            do {
                whisperKit = try await WhisperKit(
                    model: model.rawValue,
                    downloadBase: getModelsBaseURL(),
                    verbose: false
                )
                currentModelId = model.rawValue
                loadedModel = model
                modelLoadTime = Date().timeIntervalSince(modelLoadStart)
                logger.info("📦 Model loaded in \(String(format: "%.1f", modelLoadTime))s")
            } catch {
                lastError = "Failed to load model: \(error.localizedDescription)"
                logger.error("❌ Failed to load Whisper model: \(error.localizedDescription)")
                throw WhisperError.modelLoadFailed(error)
            }
        } else {
            logger.info("📦 Model already loaded: \(model.rawValue)")
        }

        guard let whisper = whisperKit else {
            throw WhisperError.modelNotLoaded
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        do {
            try audioData.write(to: tempURL)

            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }

            // Get audio duration for RTF calculation
            let audioDuration = getAudioDuration(url: tempURL)
            let durationStr = audioDuration.map { String(format: "%.1fs", $0) } ?? "?"
            logger.info("🔊 Audio file: \(audioSizeKB) KB, duration: \(durationStr)")

            let transcribeStart = Date()
            logger.info("⚙️ WhisperKit transcribe() starting...")

            let results = try await whisper.transcribe(audioPath: tempURL.path)

            let transcribeTime = Date().timeIntervalSince(transcribeStart)
            let totalTime = Date().timeIntervalSince(totalStart)

            let transcript = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            let wordCount = transcript.split(separator: " ").count

            // Calculate real-time factor (how many seconds to process 1 second of audio)
            let rtf: String
            if let duration = audioDuration, duration > 0 {
                let factor = transcribeTime / duration
                rtf = String(format: "%.2fx", factor)
            } else {
                rtf = "?"
            }

            logger.info("✅ Transcription complete:")
            logger.info("   📝 \(wordCount) words, \(transcript.count) chars")
            logger.info("   ⏱️ Transcribe: \(String(format: "%.1f", transcribeTime))s, Total: \(String(format: "%.1f", totalTime))s")
            logger.info("   📊 RTF: \(rtf) (lower is faster)")
            if modelLoadTime > 0 {
                logger.info("   📦 Model load: \(String(format: "%.1f", modelLoadTime))s")
            }
            logger.info("   💬 \"\(transcript.prefix(80))...\"")

            return transcript
        } catch {
            let totalTime = Date().timeIntervalSince(totalStart)
            lastError = "Transcription failed: \(error.localizedDescription)"
            logger.error("❌ Transcription failed after \(String(format: "%.1f", totalTime))s: \(error.localizedDescription)")
            throw WhisperError.transcriptionFailed(error)
        }
    }

    /// Get audio duration from file
    private func getAudioDuration(url: URL) -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        return duration.isFinite ? duration : nil
    }

    /// Pre-load a model into memory so transcription is instant
    public func preloadModel(_ model: WhisperModel) async throws {
        guard whisperKit == nil || currentModelId != model.rawValue else {
            logger.info("Model \(model.rawValue) already loaded")
            return
        }

        logger.info("Pre-loading Whisper model: \(model.rawValue)")

        do {
            whisperKit = try await WhisperKit(
                model: model.rawValue,
                downloadBase: getModelsBaseURL(),
                verbose: false
            )
            currentModelId = model.rawValue
            loadedModel = model
            logger.info("Model \(model.rawValue) pre-loaded and ready")
        } catch {
            lastError = "Failed to preload model: \(error.localizedDescription)"
            logger.error("Failed to preload Whisper model: \(error.localizedDescription)")
            throw WhisperError.modelLoadFailed(error)
        }
    }

    public func unloadModel() {
        whisperKit = nil
        currentModelId = nil
        loadedModel = nil
        logger.info("Whisper model unloaded")
    }

    public func deleteModel(_ model: WhisperModel) throws {
        let modelPath = getWhisperKitModelPath(for: model)

        if FileManager.default.fileExists(atPath: modelPath) {
            try FileManager.default.removeItem(atPath: modelPath)
        }

        downloadedModels.remove(model)

        if loadedModel == model {
            unloadModel()
        }

        logger.info("Deleted Whisper model: \(model.rawValue)")
    }
}

// MARK: - TranscriptionService Conformance

public struct WhisperTranscriptionService: TranscriptionService {
    private let model: WhisperModel

    public init(model: WhisperModel = .small) {
        self.model = model
    }

    public func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        let text = try await WhisperService.shared.transcribe(audioData: request.audioData, model: model)
        return Transcript(text: text, confidence: nil)
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
