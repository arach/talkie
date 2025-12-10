//
//  EngineService.swift
//  TalkieEngine
//
//  XPC service implementation that hosts WhisperKit and FluidAudio (Parakeet)
//

import Foundation
import WhisperKit
import FluidAudio
import AVFoundation
import os

private let logger = Logger(subsystem: "jdi.talkie.engine", category: "EngineService")

/// XPC service implementation
@MainActor
final class EngineService: NSObject, TalkieEngineProtocol {

    // MARK: - Whisper State
    private var whisperKit: WhisperKit?
    private var currentWhisperModelId: String?

    // MARK: - Parakeet State
    private var asrManager: AsrManager?
    private var currentParakeetModelId: String?

    // MARK: - Shared State
    private var isTranscribing = false
    private var isWarmingUp = false
    private var downloadedWhisperModels: Set<String> = []
    private var downloadedParakeetModels: Set<String> = []

    // Stats tracking
    private let startedAt = Date()
    private var totalTranscriptions = 0

    // Download state
    private var isDownloading = false
    private var currentDownloadModelId: String?
    private var downloadProgress: Double = 0
    private var downloadedBytes: Int64 = 0
    private var totalDownloadBytes: Int64?
    private var downloadTask: Task<Void, Never>?

    override init() {
        super.init()
        refreshDownloadedModels()
        logger.info("EngineService initialized (PID: \(ProcessInfo.processInfo.processIdentifier))")
    }

    // MARK: - Model Directories

    private var whisperModelsBaseURL: URL {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = supportDir.appendingPathComponent("Talkie/WhisperModels")
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        return modelsDir
    }

    private var parakeetModelsBaseURL: URL {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = supportDir.appendingPathComponent("Talkie/ParakeetModels")
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        return modelsDir
    }

    private func whisperModelPath(for modelId: String) -> String {
        whisperModelsBaseURL
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
            .appendingPathComponent(modelId)
            .path
    }

    private func parakeetModelPath(for modelId: String) -> String {
        parakeetModelsBaseURL
            .appendingPathComponent(modelId)
            .path
    }

    private func refreshDownloadedModels() {
        // Refresh Whisper models
        let knownWhisperModels = [
            "openai_whisper-tiny",
            "openai_whisper-base",
            "openai_whisper-small",
            "distil-whisper_distil-large-v3"
        ]
        downloadedWhisperModels = Set(knownWhisperModels.filter {
            FileManager.default.fileExists(atPath: whisperModelPath(for: $0))
        })

        // Refresh Parakeet models
        let knownParakeetModels = ["v2", "v3"]
        downloadedParakeetModels = Set(knownParakeetModels.filter {
            let markerPath = parakeetModelsBaseURL
                .appendingPathComponent($0)
                .appendingPathComponent(".marker")
            return FileManager.default.fileExists(atPath: markerPath.path)
        })

        logger.info("Downloaded Whisper models: \(self.downloadedWhisperModels)")
        logger.info("Downloaded Parakeet models: \(self.downloadedParakeetModels)")
    }

    // MARK: - Model ID Parsing

    private func parseModelId(_ fullId: String) -> (family: String, modelId: String) {
        let parts = fullId.split(separator: ":", maxSplits: 1)
        if parts.count == 2 {
            return (String(parts[0]), String(parts[1]))
        }
        // Default to whisper for backwards compatibility
        return ("whisper", fullId)
    }

    // MARK: - TalkieEngineProtocol

    nonisolated func transcribe(
        audioData: Data,
        modelId: String,
        reply: @escaping (String?, String?) -> Void
    ) {
        Task { @MainActor in
            await self.doTranscribe(audioData: audioData, modelId: modelId, reply: reply)
        }
    }

    private func doTranscribe(
        audioData: Data,
        modelId: String,
        reply: @escaping (String?, String?) -> Void
    ) async {
        guard !isTranscribing else {
            reply(nil, "Already transcribing")
            return
        }

        isTranscribing = true
        defer { isTranscribing = false }

        let (family, actualModelId) = parseModelId(modelId)
        let audioSizeKB = audioData.count / 1024
        logger.info("Transcribing \(audioSizeKB) KB with \(family):\(actualModelId)")

        do {
            let transcript: String
            if family == "parakeet" {
                transcript = try await transcribeWithParakeet(audioData: audioData, modelId: actualModelId)
            } else {
                transcript = try await transcribeWithWhisper(audioData: audioData, modelId: actualModelId)
            }

            totalTranscriptions += 1
            logger.info("Transcribed #\(self.totalTranscriptions): \(transcript.prefix(50))...")
            reply(transcript, nil)

        } catch {
            logger.error("Transcription failed: \(error.localizedDescription)")
            reply(nil, error.localizedDescription)
        }
    }

    // MARK: - Whisper Transcription

    private func transcribeWithWhisper(audioData: Data, modelId: String) async throws -> String {
        // Load model if needed
        if whisperKit == nil || currentWhisperModelId != modelId {
            logger.info("Loading Whisper model: \(modelId)")

            let localPath = whisperModelPath(for: modelId)
            if FileManager.default.fileExists(atPath: localPath) {
                // Model already downloaded - load from local folder
                logger.info("Loading from local folder: \(localPath)")
                whisperKit = try await WhisperKit(modelFolder: localPath, verbose: false)
            } else {
                // Model not downloaded - download it
                logger.info("Model not found locally, downloading...")
                whisperKit = try await WhisperKit(
                    model: modelId,
                    downloadBase: whisperModelsBaseURL,
                    verbose: false
                )
            }
            currentWhisperModelId = modelId
            downloadedWhisperModels.insert(modelId)
        }

        guard let whisper = whisperKit else {
            throw EngineError.modelNotLoaded
        }

        // Write audio to temp file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        try audioData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Transcribe
        let startTime = Date()
        let results = try await whisper.transcribe(audioPath: tempURL.path)
        let elapsed = Date().timeIntervalSince(startTime)

        let transcript = results.map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        logger.info("Whisper transcribed in \(String(format: "%.1f", elapsed))s")
        return transcript
    }

    // MARK: - Parakeet Transcription

    private func transcribeWithParakeet(audioData: Data, modelId: String) async throws -> String {
        let asrVersion: AsrModelVersion = modelId == "v2" ? .v2 : .v3

        // Load model if needed
        if asrManager == nil || currentParakeetModelId != modelId {
            logger.info("Loading Parakeet model: \(modelId)")

            let models = try await AsrModels.downloadAndLoad(version: asrVersion)
            asrManager = AsrManager(config: .default)
            try await asrManager?.initialize(models: models)
            currentParakeetModelId = modelId

            // Mark as downloaded
            let markerPath = parakeetModelsBaseURL
                .appendingPathComponent(modelId)
            try? FileManager.default.createDirectory(at: markerPath, withIntermediateDirectories: true)
            try? "downloaded".write(to: markerPath.appendingPathComponent(".marker"), atomically: true, encoding: .utf8)
            downloadedParakeetModels.insert(modelId)
        }

        guard let manager = asrManager else {
            throw EngineError.modelNotLoaded
        }

        // Write audio to temp file and convert to samples
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        try audioData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Convert to audio samples
        let startTime = Date()
        let samples = try await loadAudioSamples(from: tempURL)
        let result = try await manager.transcribe(samples)
        let elapsed = Date().timeIntervalSince(startTime)

        let transcript = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("Parakeet transcribed in \(String(format: "%.1f", elapsed))s")
        return transcript
    }

    /// Load audio samples from file for Parakeet
    private func loadAudioSamples(from url: URL) async throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw EngineError.audioConversionFailed
        }

        // Convert to target format
        let converter = AVAudioConverter(from: file.processingFormat, to: format)!

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            do {
                let tempBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: inNumPackets)!
                try file.read(into: tempBuffer)
                outStatus.pointee = .haveData
                return tempBuffer
            } catch {
                outStatus.pointee = .endOfStream
                return nil
            }
        }

        converter.convert(to: buffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            throw error
        }

        // Convert buffer to float array
        guard let floatData = buffer.floatChannelData?[0] else {
            throw EngineError.audioConversionFailed
        }

        return Array(UnsafeBufferPointer(start: floatData, count: Int(buffer.frameLength)))
    }

    // MARK: - Model Preloading

    nonisolated func preloadModel(_ modelId: String, reply: @escaping (String?) -> Void) {
        Task { @MainActor in
            await self.doPreloadModel(modelId, reply: reply)
        }
    }

    private func doPreloadModel(_ modelId: String, reply: @escaping (String?) -> Void) async {
        guard !isWarmingUp else {
            reply("Already warming up")
            return
        }

        isWarmingUp = true
        defer { isWarmingUp = false }

        let (family, actualModelId) = parseModelId(modelId)
        logger.info("Preloading \(family) model: \(actualModelId)")

        do {
            if family == "parakeet" {
                let asrVersion: AsrModelVersion = actualModelId == "v2" ? .v2 : .v3
                let models = try await AsrModels.downloadAndLoad(version: asrVersion)
                asrManager = AsrManager(config: .default)
                try await asrManager?.initialize(models: models)
                currentParakeetModelId = actualModelId
                downloadedParakeetModels.insert(actualModelId)

                // Mark as downloaded
                let markerPath = parakeetModelsBaseURL.appendingPathComponent(actualModelId)
                try? FileManager.default.createDirectory(at: markerPath, withIntermediateDirectories: true)
                try? "downloaded".write(to: markerPath.appendingPathComponent(".marker"), atomically: true, encoding: .utf8)

                logger.info("Parakeet model \(actualModelId) preloaded")
            } else {
                // Check if model is already downloaded locally
                let localPath = whisperModelPath(for: actualModelId)
                if FileManager.default.fileExists(atPath: localPath) {
                    // Model already downloaded - load from local folder
                    logger.info("Loading Whisper from local folder: \(localPath)")
                    whisperKit = try await WhisperKit(modelFolder: localPath, verbose: false)
                } else {
                    // Model not downloaded - download it
                    logger.info("Whisper model not found locally, downloading...")
                    whisperKit = try await WhisperKit(
                        model: actualModelId,
                        downloadBase: whisperModelsBaseURL,
                        verbose: false
                    )
                }
                currentWhisperModelId = actualModelId
                downloadedWhisperModels.insert(actualModelId)

                // Warmup with silent audio
                logger.info("Running Whisper warmup inference...")
                let silentAudio = [Float](repeating: 0.0, count: 16000)
                _ = try? await whisperKit?.transcribe(audioArray: silentAudio)

                logger.info("Whisper model \(actualModelId) preloaded and warmed up")
            }

            reply(nil)

        } catch {
            logger.error("Failed to preload model: \(error.localizedDescription)")
            reply(error.localizedDescription)
        }
    }

    nonisolated func unloadModel(reply: @escaping () -> Void) {
        Task { @MainActor in
            self.whisperKit = nil
            self.currentWhisperModelId = nil
            self.asrManager = nil
            self.currentParakeetModelId = nil
            logger.info("All models unloaded")
            reply()
        }
    }

    nonisolated func getStatus(reply: @escaping (Data?) -> Void) {
        Task { @MainActor in
            // Combine downloaded models from both families
            var allDownloaded: [String] = []
            for model in self.downloadedWhisperModels {
                allDownloaded.append("whisper:\(model)")
            }
            for model in self.downloadedParakeetModels {
                allDownloaded.append("parakeet:\(model)")
            }

            // Determine loaded model ID
            var loadedId: String?
            if let whisperModel = self.currentWhisperModelId {
                loadedId = "whisper:\(whisperModel)"
            } else if let parakeetModel = self.currentParakeetModelId {
                loadedId = "parakeet:\(parakeetModel)"
            }

            let status = EngineStatus(
                pid: ProcessInfo.processInfo.processIdentifier,
                version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                startedAt: self.startedAt,
                bundleId: Bundle.main.bundleIdentifier ?? "jdi.talkie.engine",
                loadedModelId: loadedId,
                isTranscribing: self.isTranscribing,
                isWarmingUp: self.isWarmingUp,
                downloadedModels: allDownloaded,
                totalTranscriptions: self.totalTranscriptions,
                memoryUsageMB: self.getMemoryUsageMB()
            )
            let data = try? JSONEncoder().encode(status)
            reply(data)
        }
    }

    private func getMemoryUsageMB() -> Int? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Int(info.resident_size / 1024 / 1024)
    }

    nonisolated func ping(reply: @escaping (Bool) -> Void) {
        logger.info("[XPC] ping received, responding true")
        reply(true)
    }

    // MARK: - Model Download Management

    /// Known models with metadata
    private static let knownWhisperModels: [(id: String, displayName: String, size: String, description: String)] = [
        ("openai_whisper-tiny", "Tiny", "~75 MB", "Fastest, basic quality"),
        ("openai_whisper-base", "Base", "~150 MB", "Fast, good quality"),
        ("openai_whisper-small", "Small", "~500 MB", "Balanced speed/quality"),
        ("distil-whisper_distil-large-v3", "Distil Large v3", "~1.5 GB", "Best quality, slower")
    ]

    private static let knownParakeetModels: [(id: String, displayName: String, size: String, description: String)] = [
        ("v2", "Parakeet V2", "~200 MB", "English only, highest accuracy"),
        ("v3", "Parakeet V3", "~250 MB", "25 languages, fast")
    ]

    nonisolated func downloadModel(_ modelId: String, reply: @escaping (String?) -> Void) {
        Task { @MainActor in
            await self.doDownloadModel(modelId, reply: reply)
        }
    }

    private func doDownloadModel(_ modelId: String, reply: @escaping (String?) -> Void) async {
        guard !isDownloading else {
            reply("Already downloading a model")
            return
        }

        let (family, actualModelId) = parseModelId(modelId)

        // Check if already downloaded
        if family == "parakeet" && downloadedParakeetModels.contains(actualModelId) {
            logger.info("Parakeet model \(actualModelId) already downloaded")
            reply(nil)
            return
        } else if family == "whisper" && downloadedWhisperModels.contains(actualModelId) {
            logger.info("Whisper model \(actualModelId) already downloaded")
            reply(nil)
            return
        }

        isDownloading = true
        currentDownloadModelId = modelId
        downloadProgress = 0
        downloadedBytes = 0
        totalDownloadBytes = nil

        logger.info("Starting download for \(family) model: \(actualModelId)")

        downloadTask = Task {
            do {
                if family == "parakeet" {
                    // Download Parakeet model
                    let asrVersion: AsrModelVersion = actualModelId == "v2" ? .v2 : .v3
                    let _ = try await AsrModels.downloadAndLoad(version: asrVersion)

                    await MainActor.run {
                        // Mark as downloaded
                        let markerPath = self.parakeetModelsBaseURL.appendingPathComponent(actualModelId)
                        try? FileManager.default.createDirectory(at: markerPath, withIntermediateDirectories: true)
                        try? "downloaded".write(to: markerPath.appendingPathComponent(".marker"), atomically: true, encoding: .utf8)

                        self.downloadedParakeetModels.insert(actualModelId)
                        self.isDownloading = false
                        self.currentDownloadModelId = nil
                        self.downloadProgress = 1.0
                        logger.info("Parakeet model \(actualModelId) downloaded successfully")
                    }
                } else {
                    // Download Whisper model using model name and downloadBase
                    logger.info("Downloading Whisper model \(actualModelId)...")
                    let _ = try await WhisperKit(
                        model: actualModelId,
                        downloadBase: self.whisperModelsBaseURL,
                        verbose: false
                    )

                    await MainActor.run {
                        self.downloadedWhisperModels.insert(actualModelId)
                        self.isDownloading = false
                        self.currentDownloadModelId = nil
                        self.downloadProgress = 1.0
                        logger.info("Whisper model \(actualModelId) downloaded successfully to \(self.whisperModelPath(for: actualModelId))")
                    }
                }
                reply(nil)

            } catch {
                await MainActor.run {
                    self.isDownloading = false
                    self.currentDownloadModelId = nil
                    logger.error("Failed to download model \(actualModelId): \(error.localizedDescription)")
                }
                reply(error.localizedDescription)
            }
        }
    }

    nonisolated func getDownloadProgress(reply: @escaping (Data?) -> Void) {
        Task { @MainActor in
            guard self.isDownloading, let modelId = self.currentDownloadModelId else {
                reply(nil)
                return
            }

            let progress = DownloadProgress(
                modelId: modelId,
                progress: self.downloadProgress,
                downloadedBytes: self.downloadedBytes,
                totalBytes: self.totalDownloadBytes,
                isDownloading: self.isDownloading
            )
            let data = try? JSONEncoder().encode(progress)
            reply(data)
        }
    }

    nonisolated func cancelDownload(reply: @escaping () -> Void) {
        Task { @MainActor in
            if let task = self.downloadTask {
                task.cancel()
                self.downloadTask = nil
            }
            self.isDownloading = false
            self.currentDownloadModelId = nil
            self.downloadProgress = 0
            logger.info("Download cancelled")
            reply()
        }
    }

    nonisolated func getAvailableModels(reply: @escaping (Data?) -> Void) {
        logger.info("[XPC] getAvailableModels called")
        Task { @MainActor in
            var models: [ModelInfo] = []

            logger.info("[Models] Building model list - Whisper downloaded: \(self.downloadedWhisperModels), Parakeet downloaded: \(self.downloadedParakeetModels)")

            // Add Whisper models
            for model in Self.knownWhisperModels {
                let fullId = "whisper:\(model.id)"
                models.append(ModelInfo(
                    id: fullId,
                    family: "whisper",
                    modelId: model.id,
                    displayName: "Whisper \(model.displayName)",
                    sizeDescription: model.size,
                    description: model.description,
                    isDownloaded: self.downloadedWhisperModels.contains(model.id),
                    isLoaded: self.currentWhisperModelId == model.id
                ))
            }

            // Add Parakeet models
            for model in Self.knownParakeetModels {
                let fullId = "parakeet:\(model.id)"
                models.append(ModelInfo(
                    id: fullId,
                    family: "parakeet",
                    modelId: model.id,
                    displayName: model.displayName,
                    sizeDescription: model.size,
                    description: model.description,
                    isDownloaded: self.downloadedParakeetModels.contains(model.id),
                    isLoaded: self.currentParakeetModelId == model.id
                ))
            }

            logger.info("[Models] Returning \(models.count) models to client")

            do {
                let data = try JSONEncoder().encode(models)
                logger.info("[Models] Encoded \(data.count) bytes of model data")
                reply(data)
            } catch {
                logger.error("[Models] Failed to encode models: \(error.localizedDescription)")
                reply(nil)
            }
        }
    }
}

// MARK: - Engine Errors

enum EngineError: LocalizedError {
    case modelNotLoaded
    case audioConversionFailed
    case transcriptionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Model not loaded"
        case .audioConversionFailed:
            return "Failed to convert audio format"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        }
    }
}
