//
//  ParakeetService.swift
//  TalkieServices
//
//  Local speech-to-text transcription using FluidAudio (Parakeet)
//

import Foundation
import FluidAudio
import AVFoundation
import TalkieCore
import os

private let logger = Logger(subsystem: "live.talkie.services", category: "ParakeetService")

// MARK: - Parakeet Model Options

public enum ParakeetModel: String, CaseIterable, Codable, Sendable {
    case v2 = "v2"
    case v3 = "v3"

    public var displayName: String {
        switch self {
        case .v2: return "Parakeet V2 (English)"
        case .v3: return "Parakeet V3 (Multilingual)"
        }
    }

    public var description: String {
        switch self {
        case .v2: return "English only, highest accuracy"
        case .v3: return "25 languages, fast"
        }
    }

    public var asrVersion: AsrModelVersion {
        switch self {
        case .v2: return .v2
        case .v3: return .v3
        }
    }
}

// MARK: - Parakeet Service

@MainActor
public final class ParakeetService: ObservableObject {
    public static let shared = ParakeetService()

    @Published public var isTranscribing = false
    @Published public var loadedModel: ParakeetModel?
    @Published public var downloadProgress: Float = 0
    @Published public var isDownloading = false
    @Published public var lastError: String?

    @Published public private(set) var downloadedModels: Set<ParakeetModel> = []

    private var asrManager: AsrManager?
    private var currentModelVersion: ParakeetModel?

    private init() {
        refreshDownloadedModels()
    }

    public func resetTranscriptionState() {
        logger.warning("Force resetting Parakeet transcription state (was: \(self.isTranscribing))")
        isTranscribing = false
        lastError = nil
    }

    public func refreshDownloadedModels() {
        downloadedModels = Set(ParakeetModel.allCases.filter { checkModelExists($0) })
        logger.debug("Refreshed downloaded Parakeet models: \(self.downloadedModels.map { $0.rawValue })")
    }

    // MARK: - Model Management

    public func isModelDownloaded(_ model: ParakeetModel) -> Bool {
        downloadedModels.contains(model)
    }

    private func checkModelExists(_ model: ParakeetModel) -> Bool {
        let modelPath = getParakeetModelPath(for: model)
        return FileManager.default.fileExists(atPath: modelPath)
    }

    private func getParakeetModelPath(for model: ParakeetModel) -> String {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return supportDir
            .appendingPathComponent("Talkie/ParakeetModels")
            .appendingPathComponent(model.rawValue)
            .path
    }

    private func getModelsBaseURL() -> URL {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = supportDir.appendingPathComponent("Talkie/ParakeetModels")
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        return modelsDir
    }

    public func downloadModel(_ model: ParakeetModel) async throws {
        isDownloading = true
        downloadProgress = 0
        lastError = nil

        defer {
            isDownloading = false
        }

        logger.info("Downloading Parakeet model: \(model.rawValue)")

        do {
            _ = try await AsrModels.downloadAndLoad(version: model.asrVersion)

            let markerPath = getModelsBaseURL().appendingPathComponent(model.rawValue)
            try? FileManager.default.createDirectory(at: markerPath, withIntermediateDirectories: true)
            try? "downloaded".write(to: markerPath.appendingPathComponent(".marker"), atomically: true, encoding: .utf8)

            downloadProgress = 1.0
            downloadedModels.insert(model)
            logger.info("Model \(model.rawValue) downloaded successfully")
        } catch {
            lastError = error.localizedDescription
            logger.error("Failed to download model: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Transcription

    public func transcribe(audioData: Data, model: ParakeetModel = .v3) async throws -> String {
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
                throw ParakeetError.modelLoadFailed(error)
            }
        }

        guard let manager = asrManager else {
            throw ParakeetError.modelNotLoaded
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        do {
            try audioData.write(to: tempURL)

            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }

            logger.info("Processing audio: \(audioData.count / 1024) KB")

            let samples = try await loadAudioSamples(from: tempURL)
            let result = try await manager.transcribe(samples)

            let transcript = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

            logger.info("Parakeet transcription complete: \(transcript.prefix(100))...")

            return transcript
        } catch {
            lastError = "Transcription failed: \(error.localizedDescription)"
            logger.error("Transcription failed: \(error.localizedDescription)")
            throw ParakeetError.transcriptionFailed(error)
        }
    }

    private func loadAudioSamples(from url: URL) async throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw ParakeetError.audioConversionFailed
        }

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

        guard let floatData = buffer.floatChannelData?[0] else {
            throw ParakeetError.audioConversionFailed
        }

        return Array(UnsafeBufferPointer(start: floatData, count: Int(buffer.frameLength)))
    }

    public func unloadModel() {
        asrManager = nil
        currentModelVersion = nil
        loadedModel = nil
        logger.info("Parakeet model unloaded")
    }

    public func deleteModel(_ model: ParakeetModel) throws {
        let modelPath = getParakeetModelPath(for: model)

        if FileManager.default.fileExists(atPath: modelPath) {
            try FileManager.default.removeItem(atPath: modelPath)
        }

        downloadedModels.remove(model)

        if loadedModel == model {
            unloadModel()
        }

        logger.info("Deleted Parakeet model: \(model.rawValue)")
    }
}

// MARK: - TranscriptionService Conformance

public struct ParakeetTranscriptionService: TranscriptionService {
    private let model: ParakeetModel

    public init(model: ParakeetModel = .v3) {
        self.model = model
    }

    public func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        let text = try await ParakeetService.shared.transcribe(audioData: request.audioData, model: model)
        return Transcript(text: text, confidence: nil)
    }
}

// MARK: - Errors

public enum ParakeetError: LocalizedError {
    case alreadyTranscribing
    case modelNotLoaded
    case modelLoadFailed(Error)
    case transcriptionFailed(Error)
    case noAudioData
    case audioConversionFailed

    public var errorDescription: String? {
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
