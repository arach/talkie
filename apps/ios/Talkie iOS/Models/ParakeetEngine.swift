//
//  ParakeetEngine.swift
//  Talkie iOS
//
//  On-device transcription using NVIDIA Parakeet via FluidAudio.
//  Models are downloaded to app storage and loaded from there.
//
//  To enable: Add FluidAudio SPM dependency to the project:
//  https://github.com/FluidInference/FluidAudio.git (from: "0.13.6")
//

import Foundation
import AVFoundation
import FluidAudio
import TalkieMobileKit

// MARK: - Parakeet Model Options

enum ParakeetModel: String, CaseIterable, Codable {
    case v2 = "v2"  // English only, highest accuracy
    case v3 = "v3"  // 25 languages, multilingual

    var displayName: String {
        switch self {
        case .v2: return "Parakeet V2 (English)"
        case .v3: return "Parakeet V3 (Multilingual)"
        }
    }

    var description: String {
        switch self {
        case .v2: return "English only, fastest, highest accuracy"
        case .v3: return "25 languages, multilingual"
        }
    }

    /// Short description for UI
    var shortDescription: String {
        switch self {
        case .v2: return "English • Fastest"
        case .v3: return "Multilingual • 25 languages"
        }
    }

    var sizeDescription: String {
        switch self {
        case .v2: return "~200 MB"
        case .v3: return "~250 MB"
        }
    }

    var asrVersion: AsrModelVersion {
        switch self {
        case .v2: return .v2
        case .v3: return .v3
        }
    }

    /// HuggingFace repo ID for this model
    var huggingFaceRepo: String {
        switch self {
        case .v2: return "FluidInference/parakeet-tdt-0.6b-v2-coreml"
        case .v3: return "FluidInference/parakeet-tdt-0.6b-v3-coreml"
        }
    }

    /// Required model files
    static let requiredFiles = [
        "Preprocessor.mlmodelc",
        "Encoder.mlmodelc",
        "Decoder.mlmodelc",
        "JointDecision.mlmodelc",
        "parakeet_vocab.json"
    ]
}

// MARK: - Parakeet Model Manager

/// Manages Parakeet model download and initialization for iOS.
/// Models are stored in FluidAudio's cache and loaded from there.
@MainActor
class ParakeetModelManager: ObservableObject {
    static let shared = ParakeetModelManager()

    enum ModelState: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case loading
        case ready
        case error(String)

        var isUsable: Bool {
            self == .ready
        }
    }

    @Published var state: ModelState = .notDownloaded
    @Published var currentModel: ParakeetModel?
    @Published private(set) var downloadedModels: Set<ParakeetModel> = []
    @Published var isWarmedUp: Bool = false {
        didSet {
            // Broadcast model warmth to keyboard extension via bridge
            KeyboardBridge.shared.setModelWarm(isWarmedUp)
        }
    }

    /// Human-readable description of current model state
    var statusDescription: String {
        switch state {
        case .notDownloaded: return "not available"
        case .downloading: return "preparing"
        case .downloaded: return "not loaded"
        case .loading: return "loading"
        case .ready: return isWarmedUp ? "ready" : "warming up"
        case .error(let msg): return "error: \(msg)"
        }
    }

    /// Whether the model is ready for immediate transcription
    var isReady: Bool {
        state == .ready && isWarmedUp
    }

    private var asrManager: AsrManager?

    /// User's preferred model (persisted)
    var preferredModel: ParakeetModel {
        get {
            let raw = TalkieAppConfigurationStore.shared.configuration.transcription.preferredParakeetModel
            return ParakeetModel(rawValue: raw) ?? .v3
        }
        set {
            TalkieAppConfigurationStore.shared.update { configuration in
                configuration.transcription.preferredParakeetModel = newValue.rawValue
            }
            TalkieAppSettings.shared.preferredParakeetModel = newValue
        }
    }

    private init() {
        downloadedModels = Set(ParakeetModel.allCases.filter { modelsExist(for: $0) })
        if downloadedModels.isEmpty {
            state = .notDownloaded
        } else {
            state = .downloaded
        }
    }

    // MARK: - Model Storage Paths

    /// Directory for a specific model version (FluidAudio's cache)
    func modelDirectory(for model: ParakeetModel) -> URL {
        AsrModels.defaultCacheDirectory(for: model.asrVersion)
    }

    /// Check if models exist in FluidAudio's cache
    func modelsExist(for model: ParakeetModel) -> Bool {
        let cacheDir = AsrModels.defaultCacheDirectory(for: model.asrVersion)
        return AsrModels.modelsExist(at: cacheDir)
    }

    func isModelDownloaded(_ model: ParakeetModel) -> Bool {
        modelsExist(for: model)
    }

    // MARK: - Download

    /// Download model files via FluidAudio (it manages its own cache)
    func downloadModel(_ model: ParakeetModel) async throws {
        state = .downloading(progress: 0)
        AppLogger.transcription.info("Downloading Parakeet model \(model.rawValue)")

        do {
            state = .downloading(progress: 0.5)

            // FluidAudio handles download and caching from HuggingFace
            let models = try await AsrModels.downloadAndLoad(version: model.asrVersion)

            downloadedModels.insert(model)
            state = .downloaded

            AppLogger.transcription.info("Parakeet model \(model.rawValue) downloaded")

            // Release models object - we'll reload when needed
            _ = models

        } catch {
            state = .error(error.localizedDescription)
            AppLogger.transcription.error("Download failed: \(error)")
            throw error
        }
    }

    // MARK: - Load

    /// Load model into memory for transcription
    func loadModel(_ model: ParakeetModel) async throws {
        state = .loading
        AppLogger.transcription.info("Loading Parakeet model: \(model.rawValue)")

        do {
            let models: AsrModels

            if modelsExist(for: model) {
                // Load from FluidAudio's cache
                AppLogger.transcription.info("Loading Parakeet from cache")
                models = try await AsrModels.loadFromCache(version: model.asrVersion)
            } else {
                // Download first, then load
                AppLogger.transcription.info("Downloading and loading Parakeet model")
                models = try await AsrModels.downloadAndLoad(version: model.asrVersion)
                downloadedModels.insert(model)
            }

            // Initialize ASR manager
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            self.asrManager = manager
            self.currentModel = model

            state = .ready
            isWarmedUp = false
            AppLogger.transcription.info("Parakeet model \(model.rawValue) ready")

            // Warmup: Prime CoreML on background thread to avoid blocking UI
            let warmupManager = manager
            Task.detached(priority: .userInitiated) {
                await Self.performWarmup(manager: warmupManager) { warmedUp in
                    await MainActor.run {
                        self.isWarmedUp = warmedUp
                    }
                }
            }

        } catch {
            state = .error(error.localizedDescription)
            AppLogger.transcription.error("Load failed: \(error)")
            throw error
        }
    }

    /// Download and load in one step
    func downloadAndLoad(_ model: ParakeetModel) async throws {
        if !isModelDownloaded(model) {
            try await downloadModel(model)
        }
        try await loadModel(model)
    }

    // MARK: - Proactive Preheat

    /// Proactively load and warm the preferred model for keyboard dictation.
    /// Call early (e.g., when entering ready mode or when recording starts) so
    /// the model is warm by the time transcription is needed.
    /// Fire-and-forget safe — logs errors but doesn't throw.
    func preheatForKeyboard() {
        // Already warm — nothing to do
        if state == .ready && isWarmedUp {
            AppLogger.transcription.debug("Parakeet preheat: already warm")
            return
        }

        // Model is loaded but warmup is in progress — just wait
        if state == .ready && !isWarmedUp {
            AppLogger.transcription.debug("Parakeet preheat: model loaded, warmup in progress")
            return
        }

        // Already in the process of loading — let it finish
        if state == .loading {
            AppLogger.transcription.debug("Parakeet preheat: already loading")
            return
        }

        // Check disk directly — don't rely on cached state from init
        if !modelsExist(for: preferredModel) {
            AppLogger.transcription.debug("Parakeet preheat: no models on disk")
            return
        }

        // Currently downloading — let it finish
        if case .downloading = state {
            AppLogger.transcription.debug("Parakeet preheat: download in progress")
            return
        }

        let model = preferredModel
        let stateDesc: String = {
            if case .error(let msg) = self.state { return "error(\(msg))" }
            return "\(self.state)"
        }()
        AppLogger.transcription.info("Parakeet preheat: starting load+warmup for \(model.rawValue) (was \(stateDesc))")

        // Set state synchronously BEFORE creating the Task to prevent duplicate loads.
        // Without this, multiple calls can pass the guard checks above before the first
        // Task executes and sets state to .loading inside loadModel().
        state = .loading

        Task { @MainActor in
            do {
                try await self.downloadAndLoad(model)
            } catch {
                AppLogger.transcription.warning("Parakeet preheat failed: \(error.localizedDescription)")
            }
        }
    }

    /// Wait for the model to become ready and warmed up, with timeout.
    /// Returns true if model is ready (and ideally warmed), false if timed out or errored.
    func waitForReady(timeout: TimeInterval = 15) async -> Bool {
        if state == .ready && isWarmedUp { return true }

        let start = CFAbsoluteTimeGetCurrent()
        while CFAbsoluteTimeGetCurrent() - start < timeout {
            try? await Task.sleep(nanoseconds: 500_000_000) // Check every 0.5s
            if state == .ready && isWarmedUp { return true }
            if case .error = state { return false }
            if state == .notDownloaded { return false }
        }

        // Timed out — if ready but not warmed, still usable
        if state == .ready {
            AppLogger.transcription.info("Parakeet preheat: timed out waiting for warmup but model is ready")
            return true
        }
        AppLogger.transcription.warning("Parakeet preheat: timed out (state=\(state))")
        return false
    }

    /// Warmup the model - runs off main actor to avoid blocking UI
    private static func performWarmup(manager: AsrManager, completion: @escaping (Bool) async -> Void) async {
        AppLogger.transcription.info("Warming up Parakeet model (background)...")
        let warmupStart = CFAbsoluteTimeGetCurrent()

        // Generate 2 seconds of near-silence with tiny noise (16kHz = 32000 samples)
        // Pure silence or very short audio can cause CoreML shape errors
        let warmupSamples = (0..<32000).map { _ in Float.random(in: -0.0001...0.0001) }

        do {
            // Run transcription - this is the heavy Neural Engine work
            _ = try await manager.transcribe(warmupSamples)
            let warmupTime = CFAbsoluteTimeGetCurrent() - warmupStart
            AppLogger.transcription.info("Parakeet warmup complete in \(String(format: "%.2f", warmupTime))s")
            await completion(true)
        } catch {
            AppLogger.transcription.warning("Parakeet warmup skipped: \(error.localizedDescription)")
            await completion(true) // Mark as warmed up anyway
        }
    }

    /// Unload the current model to free memory
    func unloadModel() {
        asrManager = nil
        currentModel = nil
        isWarmedUp = false
        state = downloadedModels.isEmpty ? .notDownloaded : .downloaded
        AppLogger.transcription.info("Parakeet model unloaded")
    }

    /// Delete a downloaded model
    func deleteModel(_ model: ParakeetModel) throws {
        let modelDir = modelDirectory(for: model)
        if FileManager.default.fileExists(atPath: modelDir.path) {
            try FileManager.default.removeItem(at: modelDir)
        }

        downloadedModels.remove(model)

        if currentModel == model {
            unloadModel()
        }

        AppLogger.transcription.info("Deleted Parakeet model: \(model.rawValue)")
    }

    // MARK: - Transcription

    /// Transcribe audio samples (must be ready)
    func transcribe(_ samples: [Float]) async throws -> String {
        guard let manager = asrManager, state == .ready else {
            throw ParakeetError.modelNotReady
        }

        let result = try await manager.transcribe(samples)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Parakeet Errors

enum ParakeetError: LocalizedError {
    case modelNotDownloaded
    case modelNotReady
    case audioConversionFailed
    case transcriptionFailed(Error)
    case downloadFailed(Error)

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded:
            return "Parakeet model not downloaded"
        case .modelNotReady:
            return "Parakeet model not loaded or ready"
        case .audioConversionFailed:
            return "Failed to convert audio format"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .downloadFailed(let error):
            return "Download failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Parakeet Transcription Engine

/// TranscriptionEngine implementation using Parakeet
class ParakeetEngine: TranscriptionEngine {
    var engineName: String { "Parakeet-TDT" }

    private var model: ParakeetModel?

    /// Initialize with optional explicit model, or use user's preferred model
    init(model: ParakeetModel? = nil) {
        self.model = model
    }

    func transcribe(audioURL: URL) async throws -> String {
        // Get the model to use (explicit or user preference)
        let targetModel = await MainActor.run {
            model ?? ParakeetModelManager.shared.preferredModel
        }

        // Check if model needs loading (access MainActor properties)
        let needsLoad = await MainActor.run {
            let manager = ParakeetModelManager.shared
            return manager.state != .ready || manager.currentModel != targetModel
        }

        if needsLoad {
            try await ParakeetModelManager.shared.downloadAndLoad(targetModel)
        }

        // Load audio and convert to 16kHz mono samples
        let samples = try loadAudioSamples(from: audioURL)

        // Transcribe
        return try await ParakeetModelManager.shared.transcribe(samples)
    }

    /// Load audio file and convert to 16kHz mono Float32 samples
    private func loadAudioSamples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let targetFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!

        guard let buffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw ParakeetError.audioConversionFailed
        }

        let converter = AVAudioConverter(from: file.processingFormat, to: targetFormat)!

        var conversionError: NSError?
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

        converter.convert(to: buffer, error: &conversionError, withInputFrom: inputBlock)

        if let error = conversionError {
            throw error
        }

        guard let floatData = buffer.floatChannelData?[0] else {
            throw ParakeetError.audioConversionFailed
        }

        return Array(UnsafeBufferPointer(start: floatData, count: Int(buffer.frameLength)))
    }
}
