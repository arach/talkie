//
//  EngineService.swift
//  TalkieEngine
//
//  XPC service implementation that hosts WhisperKit
//

import Foundation
import WhisperKit
import os

private let logger = Logger(subsystem: "jdi.talkie.engine", category: "EngineService")

/// XPC service implementation
@MainActor
final class EngineService: NSObject, TalkieEngineProtocol {

    private var whisperKit: WhisperKit?
    private var currentModelId: String?
    private var isTranscribing = false
    private var isWarmingUp = false
    private var downloadedModels: Set<String> = []

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

    // MARK: - Model Directory

    private var modelsBaseURL: URL {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = supportDir.appendingPathComponent("Talkie/WhisperModels")
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        return modelsDir
    }

    private func modelPath(for modelId: String) -> String {
        modelsBaseURL
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
            .appendingPathComponent(modelId)
            .path
    }

    private func refreshDownloadedModels() {
        let knownModels = [
            "openai_whisper-tiny",
            "openai_whisper-base",
            "openai_whisper-small",
            "distil-whisper_distil-large-v3"
        ]
        downloadedModels = Set(knownModels.filter {
            FileManager.default.fileExists(atPath: modelPath(for: $0))
        })
        logger.info("Downloaded models: \(self.downloadedModels)")
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

        let audioSizeKB = audioData.count / 1024
        logger.info("Transcribing \(audioSizeKB) KB with model \(modelId)")

        do {
            // Load model if needed
            if whisperKit == nil || currentModelId != modelId {
                logger.info("Loading model: \(modelId)")
                whisperKit = try await WhisperKit(
                    model: modelId,
                    downloadBase: modelsBaseURL,
                    verbose: false
                )
                currentModelId = modelId
                downloadedModels.insert(modelId)
            }

            guard let whisper = whisperKit else {
                reply(nil, "Model not loaded")
                return
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

            totalTranscriptions += 1
            logger.info("Transcribed #\(self.totalTranscriptions) in \(String(format: "%.1f", elapsed))s: \(transcript.prefix(50))...")
            reply(transcript, nil)

        } catch {
            logger.error("Transcription failed: \(error.localizedDescription)")
            reply(nil, error.localizedDescription)
        }
    }

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

        logger.info("Preloading model: \(modelId)")

        do {
            whisperKit = try await WhisperKit(
                model: modelId,
                downloadBase: modelsBaseURL,
                verbose: false
            )
            currentModelId = modelId
            downloadedModels.insert(modelId)

            // Warmup with silent audio
            logger.info("Running warmup inference...")
            let silentAudio = [Float](repeating: 0.0, count: 16000)
            _ = try? await whisperKit?.transcribe(audioArray: silentAudio)

            logger.info("Model \(modelId) preloaded and warmed up")
            reply(nil)

        } catch {
            logger.error("Failed to preload model: \(error.localizedDescription)")
            reply(error.localizedDescription)
        }
    }

    nonisolated func unloadModel(reply: @escaping () -> Void) {
        Task { @MainActor in
            self.whisperKit = nil
            self.currentModelId = nil
            logger.info("Model unloaded")
            reply()
        }
    }

    nonisolated func getStatus(reply: @escaping (Data?) -> Void) {
        Task { @MainActor in
            let status = EngineStatus(
                pid: ProcessInfo.processInfo.processIdentifier,
                version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                startedAt: self.startedAt,
                bundleId: Bundle.main.bundleIdentifier ?? "jdi.talkie.engine",
                loadedModelId: self.currentModelId,
                isTranscribing: self.isTranscribing,
                isWarmingUp: self.isWarmingUp,
                downloadedModels: Array(self.downloadedModels),
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
        reply(true)
    }

    // MARK: - Model Download Management

    /// Known Whisper models with metadata
    private static let knownModels: [(id: String, displayName: String, size: String)] = [
        ("openai_whisper-tiny", "Tiny", "~75 MB"),
        ("openai_whisper-base", "Base", "~150 MB"),
        ("openai_whisper-small", "Small", "~500 MB"),
        ("openai_whisper-medium", "Medium", "~1.5 GB"),
        ("openai_whisper-large-v3", "Large v3", "~3.0 GB"),
        ("distil-whisper_distil-large-v3", "Distil Large v3", "~1.5 GB")
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

        // Check if already downloaded
        if downloadedModels.contains(modelId) {
            logger.info("Model \(modelId) already downloaded")
            reply(nil)
            return
        }

        isDownloading = true
        currentDownloadModelId = modelId
        downloadProgress = 0
        downloadedBytes = 0
        totalDownloadBytes = nil

        logger.info("Starting download for model: \(modelId)")

        downloadTask = Task {
            do {
                // WhisperKit downloads models during initialization
                // We create a temporary instance just to trigger the download
                let _ = try await WhisperKit(
                    model: modelId,
                    downloadBase: modelsBaseURL,
                    verbose: false
                )

                await MainActor.run {
                    self.downloadedModels.insert(modelId)
                    self.isDownloading = false
                    self.currentDownloadModelId = nil
                    self.downloadProgress = 1.0
                    logger.info("Model \(modelId) downloaded successfully")
                }
                reply(nil)

            } catch {
                await MainActor.run {
                    self.isDownloading = false
                    self.currentDownloadModelId = nil
                    logger.error("Failed to download model \(modelId): \(error.localizedDescription)")
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
        Task { @MainActor in
            let models = Self.knownModels.map { model in
                ModelInfo(
                    id: model.id,
                    displayName: model.displayName,
                    sizeDescription: model.size,
                    isDownloaded: self.downloadedModels.contains(model.id),
                    isLoaded: self.currentModelId == model.id
                )
            }
            let data = try? JSONEncoder().encode(models)
            reply(data)
        }
    }
}
