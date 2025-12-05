//
//  ParakeetService.swift
//  Talkie
//
//  Local speech-to-text transcription using FluidAudio (Parakeet)
//

import Foundation
import FluidAudio
import AVFoundation
import os

private let logger = Logger(subsystem: "jdi.talkie-os-mac", category: "ParakeetService")

// MARK: - Parakeet Model Options

enum ParakeetModel: String, CaseIterable, Codable {
    case v2 = "v2"  // English only, higher accuracy
    case v3 = "v3"  // 25 languages, multilingual

    var displayName: String {
        switch self {
        case .v2: return "Parakeet V2 (English)"
        case .v3: return "Parakeet V3 (Multilingual)"
        }
    }

    var description: String {
        switch self {
        case .v2: return "English only, highest accuracy"
        case .v3: return "25 languages, fast"
        }
    }

    var asrVersion: AsrModelVersion {
        switch self {
        case .v2: return .v2
        case .v3: return .v3
        }
    }
}

// MARK: - Parakeet Service

@MainActor
class ParakeetService: ObservableObject {
    static let shared = ParakeetService()

    @Published var isTranscribing = false
    @Published var loadedModel: ParakeetModel?
    @Published var downloadProgress: Float = 0
    @Published var isDownloading = false
    @Published var lastError: String?

    /// Cached set of downloaded models - updated on download/delete
    @Published private(set) var downloadedModels: Set<ParakeetModel> = []

    private var asrManager: AsrManager?
    private var currentModelVersion: ParakeetModel?

    private init() {
        refreshDownloadedModels()
    }

    /// Force reset the transcription state if it gets stuck
    func resetTranscriptionState() {
        logger.warning("Force resetting Parakeet transcription state (was: \(self.isTranscribing))")
        isTranscribing = false
        lastError = nil
    }

    /// Refresh the cached downloaded models state
    func refreshDownloadedModels() {
        downloadedModels = Set(ParakeetModel.allCases.filter { checkModelExists($0) })
        logger.debug("Refreshed downloaded Parakeet models: \(self.downloadedModels.map { $0.rawValue })")
    }

    // MARK: - Model Management

    /// Check if a model is downloaded locally (uses cached state)
    func isModelDownloaded(_ model: ParakeetModel) -> Bool {
        downloadedModels.contains(model)
    }

    /// Actually check filesystem for model existence (used internally)
    private func checkModelExists(_ model: ParakeetModel) -> Bool {
        let modelPath = getParakeetModelPath(for: model)
        return FileManager.default.fileExists(atPath: modelPath)
    }

    /// Get Parakeet model storage path
    private func getParakeetModelPath(for model: ParakeetModel) -> String {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return supportDir
            .appendingPathComponent("Talkie/ParakeetModels")
            .appendingPathComponent(model.rawValue)
            .path
    }

    /// Get URL for model storage base
    private func getModelsBaseURL() -> URL {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = supportDir.appendingPathComponent("Talkie/ParakeetModels")
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        return modelsDir
    }

    /// Download a model if not already present
    func downloadModel(_ model: ParakeetModel) async throws {
        isDownloading = true
        downloadProgress = 0
        lastError = nil

        defer {
            isDownloading = false
        }

        logger.info("Downloading Parakeet model: \(model.rawValue)")
        await SystemEventManager.shared.log(.workflow, "Downloading Parakeet model", detail: model.displayName)

        do {
            // FluidAudio handles model download automatically
            let models = try await AsrModels.downloadAndLoad(version: model.asrVersion)

            // Mark download location
            let markerPath = getModelsBaseURL().appendingPathComponent(model.rawValue)
            try? FileManager.default.createDirectory(at: markerPath, withIntermediateDirectories: true)
            try? "downloaded".write(to: markerPath.appendingPathComponent(".marker"), atomically: true, encoding: .utf8)

            downloadProgress = 1.0
            downloadedModels.insert(model) // Update cached state
            logger.info("Model \(model.rawValue) downloaded successfully")
            await SystemEventManager.shared.log(.workflow, "Parakeet model ready", detail: model.displayName)
        } catch {
            lastError = error.localizedDescription
            logger.error("Failed to download model: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Transcription

    /// Transcribe audio data to text
    func transcribe(audioData: Data, model: ParakeetModel = .v3) async throws -> String {
        // Wait for any ongoing transcription
        let maxWaitTime: TimeInterval = 60
        let startTime = Date()

        while isTranscribing {
            if Date().timeIntervalSince(startTime) > maxWaitTime {
                logger.warning("Timeout waiting for previous transcription")
                throw ParakeetError.alreadyTranscribing
            }
            logger.debug("Waiting for previous transcription to complete...")
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        isTranscribing = true
        lastError = nil

        defer {
            isTranscribing = false
        }

        logger.info("Starting Parakeet transcription with model: \(model.rawValue)")
        await SystemEventManager.shared.log(.transcribe, "Parakeet transcription started", detail: model.displayName)

        // Load model if needed or if different model requested
        if asrManager == nil || currentModelVersion != model {
            logger.info("Loading Parakeet model: \(model.rawValue)")

            do {
                let models = try await AsrModels.downloadAndLoad(version: model.asrVersion)
                asrManager = AsrManager(config: .default)
                try await asrManager?.initialize(models: models)
                currentModelVersion = model
                loadedModel = model
            } catch {
                lastError = "Failed to load model: \(error.localizedDescription)"
                logger.error("Failed to load Parakeet model: \(error.localizedDescription)")
                await SystemEventManager.shared.log(.error, "Model load failed", detail: error.localizedDescription)
                throw ParakeetError.modelLoadFailed(error)
            }
        }

        guard let manager = asrManager else {
            throw ParakeetError.modelNotLoaded
        }

        // Write audio data to temporary file and convert to samples
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        do {
            try audioData.write(to: tempURL)

            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }

            // Convert to audio samples
            await SystemEventManager.shared.log(.transcribe, "Processing audio", detail: "\(audioData.count / 1024) KB")

            let samples = try await loadAudioSamples(from: tempURL)
            let result = try await manager.transcribe(samples)

            let transcript = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

            logger.info("Parakeet transcription complete: \(transcript.prefix(100))...")
            await SystemEventManager.shared.log(.transcribe, "Transcription complete", detail: "\(transcript.count) chars")

            return transcript
        } catch {
            lastError = "Transcription failed: \(error.localizedDescription)"
            logger.error("Transcription failed: \(error.localizedDescription)")
            await SystemEventManager.shared.log(.error, "Transcription failed", detail: error.localizedDescription)
            throw ParakeetError.transcriptionFailed(error)
        }
    }

    /// Load audio samples from file
    private func loadAudioSamples(from url: URL) async throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw ParakeetError.audioConversionFailed
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
            throw ParakeetError.audioConversionFailed
        }

        return Array(UnsafeBufferPointer(start: floatData, count: Int(buffer.frameLength)))
    }

    /// Unload the current model to free memory
    func unloadModel() {
        asrManager = nil
        currentModelVersion = nil
        loadedModel = nil
        logger.info("Parakeet model unloaded")
    }

    /// Delete a downloaded model
    func deleteModel(_ model: ParakeetModel) throws {
        let modelPath = getParakeetModelPath(for: model)

        if FileManager.default.fileExists(atPath: modelPath) {
            try FileManager.default.removeItem(atPath: modelPath)
        }

        // Update cached state
        downloadedModels.remove(model)

        // Unload if this was the loaded model
        if loadedModel == model {
            unloadModel()
        }

        logger.info("Deleted Parakeet model: \(model.rawValue)")
    }
}

// MARK: - Errors

enum ParakeetError: LocalizedError {
    case alreadyTranscribing
    case modelNotLoaded
    case modelLoadFailed(Error)
    case transcriptionFailed(Error)
    case noAudioData
    case audioConversionFailed

    var errorDescription: String? {
        switch self {
        case .alreadyTranscribing:
            return "A transcription is already in progress"
        case .modelNotLoaded:
            return "Parakeet model is not loaded"
        case .modelLoadFailed(let error):
            return "Failed to load model: \(error.localizedDescription)"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .noAudioData:
            return "No audio data available"
        case .audioConversionFailed:
            return "Failed to convert audio format"
        }
    }
}
