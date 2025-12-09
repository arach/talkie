//
//  EngineService.swift
//  TalkieEngine
//
//  XPC service implementation that hosts WhisperKit
//

import Foundation
import WhisperKit
import os

private let logger = Logger(subsystem: "live.talkie.engine", category: "EngineService")

/// XPC service implementation
@MainActor
final class EngineService: NSObject, TalkieEngineProtocol {

    private var whisperKit: WhisperKit?
    private var currentModelId: String?
    private var isTranscribing = false
    private var isWarmingUp = false
    private var downloadedModels: Set<String> = []

    override init() {
        super.init()
        refreshDownloadedModels()
        logger.info("EngineService initialized")
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

            logger.info("Transcribed in \(String(format: "%.1f", elapsed))s: \(transcript.prefix(50))...")
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
                loadedModelId: self.currentModelId,
                isTranscribing: self.isTranscribing,
                isWarmingUp: self.isWarmingUp,
                downloadedModels: Array(self.downloadedModels)
            )
            let data = try? JSONEncoder().encode(status)
            reply(data)
        }
    }

    nonisolated func ping(reply: @escaping (Bool) -> Void) {
        reply(true)
    }
}
