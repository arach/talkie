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
import Cocoa
import OSLog
import TalkieKit

// MARK: - AppLogger

/// Event categories for logging
enum EventType: String {
    case system = "system"
    case audio = "audio"
    case transcription = "transcription"
    case database = "database"
    case file = "file"
    case error = "error"
    case xpc = "xpc"
    case model = "model"
    case performance = "performance"
}

/// Unified logging that prints to console and writes to file for cross-app viewing
/// Uses TalkieKit's TalkieLogFileWriter for unified log format
final class AppLogger {
    static let shared = AppLogger()
    private let subsystem = "jdi.talkie.engine"

    /// File writer for cross-app log viewing in Talkie
    private let fileWriter = TalkieLogFileWriter(source: .talkieEngine)

    private init() {}

    /// Log a message - prints to console and writes to file for Talkie viewing
    /// Warnings and errors use critical mode (immediate flush), everything else is buffered
    func log(_ category: EventType, _ message: String, detail: String? = nil, level: OSLogEntryLog.Level = .info, file: String = #file, line: Int = #line) {
        let fullMessage = detail != nil ? "\(message): \(detail!)" : message

        // Format log line with file/line info for console
        let timestamp = Date().formatted(.dateTime.hour().minute().second().secondFraction(.fractional(2)))
        let filename = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        let levelStr = switch level {
        case .debug: "[DEBUG]"
        case .info: "[INFO]"
        case .notice: "[NOTICE]"
        case .error: "[ERROR]"
        case .fault: "[FAULT]"
        default: "[LOG]"
        }
        let logLine = "[\(timestamp)] \(levelStr) [\(category.rawValue)] \(fullMessage) ← \(filename):\(line)"

        // Log to console (visible in Xcode debugger and Console.app)
        autoreleasepool {
            NSLog("%@", logLine)
        }

        // Write to file for cross-app viewing in Talkie
        // Warnings and errors use critical mode (immediate flush) with file:line context
        let logType = mapEventType(category)
        let isCritical = level == .notice || level == .error || level == .fault
        let writeMode: LogWriteMode = isCritical ? .critical : .bestEffort

        // Add file:line context to warnings and errors for debugging
        let fileDetail: String?
        if isCritical {
            let baseDetail = detail ?? ""
            fileDetail = baseDetail.isEmpty ? "[\(filename):\(line)]" : "\(baseDetail) [\(filename):\(line)]"
        } else {
            fileDetail = detail
        }

        fileWriter.log(logType, message, detail: fileDetail, mode: writeMode)
    }

    /// Map local EventType to TalkieKit's LogEventType
    private func mapEventType(_ type: EventType) -> LogEventType {
        switch type {
        case .system: return .system
        case .audio: return .record
        case .transcription: return .transcribe
        case .database: return .system
        case .file: return .system
        case .error: return .error
        case .xpc: return .system
        case .model: return .system
        case .performance: return .system
        }
    }

    /// Convenience methods for common log levels
    func debug(_ category: EventType, _ message: String, detail: String? = nil) {
        log(category, message, detail: detail, level: .debug)
    }

    func info(_ category: EventType, _ message: String, detail: String? = nil) {
        log(category, message, detail: detail, level: .info)
    }

    func warning(_ category: EventType, _ message: String, detail: String? = nil) {
        log(category, message, detail: detail, level: .notice)
    }

    func error(_ category: EventType, _ message: String, detail: String? = nil) {
        log(category, message, detail: detail, level: .error)
    }
}

// Simple log helper - prints to console (readable) + system log
private func log(_ message: String) {
    print("[Engine] \(message)")
    AppLogger.shared.info(.transcription, "\(message)")
}

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
    private var activeTranscriptions = 0
    private var isTranscribing: Bool { activeTranscriptions > 0 }
    private var isWarmingUp = false
    private var isShuttingDown = false
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
        AppLogger.shared.info(.transcription, "EngineService initialized (PID: \(ProcessInfo.processInfo.processIdentifier))")
        EngineStatusManager.shared.log(.info, "Engine", "EngineService initialized (PID: \(ProcessInfo.processInfo.processIdentifier))")
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

        AppLogger.shared.info(.transcription, "Downloaded Whisper models: \(self.downloadedWhisperModels)")
        AppLogger.shared.info(.transcription, "Downloaded Parakeet models: \(self.downloadedParakeetModels)")
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

    /// Transcribe audio with priority control
    nonisolated func transcribe(
        audioPath: String,
        modelId: String,
        externalRefId: String?,
        priority: TranscriptionPriority,
        reply: @escaping (String?, String?) -> Void
    ) {
        Task(priority: priority.taskPriority) { @MainActor in
            await self.doTranscribe(audioPath: audioPath, modelId: modelId, externalRefId: externalRefId, reply: reply)
        }
    }

    private func doTranscribe(
        audioPath: String,
        modelId: String,
        externalRefId: String?,
        reply: @escaping (String?, String?) -> Void
    ) async {
        guard !isShuttingDown else {
            EngineStatusManager.shared.log(.warning, "Transcribe", "Rejected - engine is shutting down")
            reply(nil, "Engine is shutting down, please retry")
            return
        }

        // Create trace for step-level timing
        let trace = TranscriptionTrace()
        trace.externalRefId = externalRefId
        trace.begin("file_check")

        // Micro-timing for file operations
        let t0 = CFAbsoluteTimeGetCurrent()

        // Verify file exists
        let exists = FileManager.default.fileExists(atPath: audioPath)
        let t1 = CFAbsoluteTimeGetCurrent()
        let existsMs = Int((t1 - t0) * 1000)

        guard exists else {
            EngineStatusManager.shared.log(.error, "Transcribe", "File not found: \(audioPath)")
            reply(nil, "Audio file not found")
            return
        }

        // Get file size for metadata
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioPath)[.size] as? Int64) ?? 0
        let t2 = CFAbsoluteTimeGetCurrent()
        let attrMs = Int((t2 - t1) * 1000)

        // Log micro-timings if any are slow (>50ms)
        let totalMs = existsMs + attrMs
        if totalMs > 50 {
            EngineStatusManager.shared.log(.warning, "FileCheck", "Slow I/O: exists=\(existsMs)ms, attrs=\(attrMs)ms, total=\(totalMs)ms")
        }

        trace.end("\(fileSize) bytes • exists:\(existsMs)ms attrs:\(attrMs)ms")

        activeTranscriptions += 1
        EngineStatusManager.shared.isTranscribing = isTranscribing
        defer {
            activeTranscriptions -= 1
            EngineStatusManager.shared.isTranscribing = isTranscribing
        }

        let (family, actualModelId) = parseModelId(modelId)
        let fileName = URL(fileURLWithPath: audioPath).lastPathComponent
        AppLogger.shared.info(.transcription, "Transcribing \(fileName) with \(family):\(actualModelId)")
        EngineStatusManager.shared.log(.info, "Transcribe", "Starting \(fileName) with \(family):\(actualModelId)")

        trace.mark("start", metadata: "\(family):\(actualModelId)")

        do {
            let result: TranscriptionResult
            if family == "parakeet" {
                result = try await transcribeWithParakeet(audioPath: audioPath, modelId: actualModelId, trace: trace)
            } else {
                result = try await transcribeWithWhisper(audioPath: audioPath, modelId: actualModelId, trace: trace)
            }

            trace.mark("complete")

            // Log trace summary for E2E trace viewer correlation
            AppLogger.shared.log(.performance, "Trace complete", detail: trace.summary)

            totalTranscriptions += 1
            let elapsed = trace.elapsedSeconds
            let elapsedMs = trace.elapsedMs
            let wordCount = result.transcript.split(separator: " ").count
            AppLogger.shared.info(.transcription, "Transcribed #\(self.totalTranscriptions): \(result.transcript.prefix(50))...")
            let timeStr = elapsedMs < 1000 ? "\(elapsedMs)ms" : String(format: "%.2fs", elapsed)
            EngineStatusManager.shared.log(.info, "Transcribe", "✓ #\(totalTranscriptions) in \(timeStr) (\(wordCount) words)")
            EngineStatusManager.shared.totalTranscriptions = totalTranscriptions

            // Record metric with full trace
            EngineStatusManager.shared.recordMetric(
                elapsed: elapsed,
                audioDuration: result.audioDuration,
                wordCount: wordCount,
                transcript: result.transcript,
                trace: trace,
                modelId: modelId,
                audioFilename: fileName,
                audioSamples: result.sampleCount
            )
            reply(result.transcript, nil)

        } catch {
            trace.mark("error", metadata: error.localizedDescription)
            let elapsed = trace.elapsedSeconds
            let elapsedMs = trace.elapsedMs
            let timeStr = elapsedMs < 1000 ? "\(elapsedMs)ms" : String(format: "%.2fs", elapsed)
            AppLogger.shared.error(.transcription, "Transcription failed: \(error.localizedDescription)")
            EngineStatusManager.shared.log(.error, "Transcribe", "✗ Failed after \(timeStr): \(error.localizedDescription)")
            reply(nil, error.localizedDescription)
        }
    }

    /// Result from transcription methods (includes metadata for tracing)
    private struct TranscriptionResult {
        let transcript: String
        let audioDuration: Double?
        let sampleCount: Int?
    }

    // MARK: - Whisper Transcription

    private func transcribeWithWhisper(audioPath: String, modelId: String, trace: TranscriptionTrace) async throws -> TranscriptionResult {
        // Check if model needs loading
        trace.begin("model_check")
        let needsModelLoad = whisperKit == nil || currentWhisperModelId != modelId
        trace.end(needsModelLoad ? "needs load" : "already loaded")

        // Load model if needed
        if needsModelLoad {
            trace.begin("model_load")
            AppLogger.shared.info(.transcription, "Loading Whisper model: \(modelId)")
            EngineStatusManager.shared.log(.info, "Whisper", "Loading model: \(modelId)")

            let localPath = whisperModelPath(for: modelId)
            if FileManager.default.fileExists(atPath: localPath) {
                // Model already downloaded - load from local folder
                AppLogger.shared.info(.transcription, "Loading from local folder: \(localPath)")
                EngineStatusManager.shared.log(.debug, "Whisper", "Loading from local cache...")
                whisperKit = try await WhisperKit(modelFolder: localPath, verbose: false)
                trace.end("from cache")
            } else {
                // Model not downloaded - download it
                AppLogger.shared.info(.transcription, "Model not found locally, downloading...")
                EngineStatusManager.shared.log(.info, "Whisper", "Downloading model (not cached)...")
                whisperKit = try await WhisperKit(
                    model: modelId,
                    downloadBase: whisperModelsBaseURL,
                    verbose: false
                )
                trace.end("downloaded")
            }
            currentWhisperModelId = modelId
            downloadedWhisperModels.insert(modelId)
            EngineStatusManager.shared.currentModel = "whisper:\(modelId)"
            EngineStatusManager.shared.log(.info, "Whisper", "Model \(modelId) loaded")
        }

        guard let whisper = whisperKit else {
            throw EngineError.modelNotLoaded
        }

        // Transcribe directly from client's file
        trace.begin("inference")
        let results = try await whisper.transcribe(audioPath: audioPath)

        // Post-process
        let transcript = results.map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = transcript.split(separator: " ").count
        let charCount = transcript.count

        // End inference with result metadata for signpost
        let inferenceMs = trace.end("\(results.count) segments, \(charCount) chars, \(wordCount) words")

        // Alert on slow transcriptions (>5s inference)
        if inferenceMs > 5000 {
            AppLogger.shared.warning(.performance, "SLOW WHISPER INFERENCE: \(inferenceMs)ms")
            EngineStatusManager.shared.log(.warning, "Perf", "⚠️ Slow Whisper inference: \(inferenceMs)ms")
        }

        AppLogger.shared.info(.transcription, "Whisper transcribed: \(transcript.prefix(50))...")
        return TranscriptionResult(transcript: transcript, audioDuration: nil, sampleCount: nil)
    }

    // MARK: - Parakeet Transcription

    private func transcribeWithParakeet(audioPath: String, modelId: String, trace: TranscriptionTrace) async throws -> TranscriptionResult {
        // TranscriptionTrace now auto-emits os_signpost for each step - visible in Instruments
        let asrVersion: AsrModelVersion = modelId == "v2" ? .v2 : .v3

        // Check if model needs loading
        trace.begin("model_check")
        let needsModelLoad = asrManager == nil || currentParakeetModelId != modelId
        trace.end(needsModelLoad ? "needs load" : "already loaded")

        // Load model if needed
        if needsModelLoad {
            trace.begin("model_load")
            AppLogger.shared.info(.transcription, "Loading Parakeet model: \(modelId)")
            EngineStatusManager.shared.log(.info, "Parakeet", "Loading model: \(modelId)")

            let models = try await AsrModels.downloadAndLoad(version: asrVersion)
            EngineStatusManager.shared.log(.debug, "Parakeet", "Models downloaded, initializing ASR manager...")
            asrManager = AsrManager(config: .default)
            try await asrManager?.initialize(models: models)
            currentParakeetModelId = modelId

            // Mark as downloaded
            let markerPath = parakeetModelsBaseURL
                .appendingPathComponent(modelId)
            try? FileManager.default.createDirectory(at: markerPath, withIntermediateDirectories: true)
            try? "downloaded".write(to: markerPath.appendingPathComponent(".marker"), atomically: true, encoding: .utf8)
            downloadedParakeetModels.insert(modelId)
            EngineStatusManager.shared.currentModel = "parakeet:\(modelId)"
            EngineStatusManager.shared.log(.info, "Parakeet", "Model \(modelId) loaded and ready")
            trace.end("initialized")
        }

        guard let manager = asrManager else {
            throw EngineError.modelNotLoaded
        }

        // Load and convert audio to 16kHz mono samples
        trace.begin("audio_load")
        let audioURL = URL(fileURLWithPath: audioPath)
        var samples = try await loadAudioSamples(from: audioURL)
        let originalSampleCount = samples.count
        // Calculate audio duration: samples at 16kHz
        let audioDuration = Double(originalSampleCount) / 16000.0
        trace.end("\(originalSampleCount) samples (\(String(format: "%.1f", audioDuration))s)")

        // Fade the last ~300ms of audio to silence to help the decoder flush final tokens
        // Exponential fade prevents mistranscription while keeping speech-like features
        // to keep the decoder engaged during final token generation
        trace.begin("audio_pad")
        let fadeDuration = 4800  // 300ms at 16kHz
        let fadeSource = min(fadeDuration, samples.count)
        let tailSegment = Array(samples.suffix(fadeSource))
        // Apply exponential fade to silence
        let fadedSegment = tailSegment.enumerated().map { index, sample in
            let progress = Float(index) / Float(tailSegment.count)
            let fadeMultiplier = exp(-5.0 * progress)  // Exponential decay
            return sample * fadeMultiplier
        }
        samples.append(contentsOf: fadedSegment)
        trace.end("+\(fadedSegment.count) samples (fade tail)")

        // Run inference - trace captures timing with mach_absolute_time
        trace.begin("inference")
        let result = try await manager.transcribe(samples)

        // Post-process: trim and dedupe trailing repeated words (from echo-tail padding)
        let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let transcript = dedupeTrailingWords(trimmed)
        let wordCount = transcript.split(separator: " ").count
        let charCount = transcript.count

        // End inference with result metadata for signpost
        let inferenceMs = trace.end("\(charCount) chars, \(wordCount) words")

        // Alert on slow transcriptions (>5s inference)
        if inferenceMs > 5000 {
            let rtf = Double(inferenceMs) / 1000.0 / audioDuration
            AppLogger.shared.warning(.performance, "SLOW INFERENCE: \(inferenceMs)ms for \(String(format: "%.1f", audioDuration))s audio (RTF: \(String(format: "%.2f", rtf)))")
            EngineStatusManager.shared.log(.warning, "Perf", "⚠️ Slow inference: \(inferenceMs)ms (\(String(format: "%.1fx", audioDuration * 1000 / Double(inferenceMs))) realtime)")
        }

        AppLogger.shared.info(.transcription, "Parakeet transcribed: \(transcript.prefix(50))... (\(samples.count) samples)")
        return TranscriptionResult(transcript: transcript, audioDuration: audioDuration, sampleCount: originalSampleCount)
    }

    /// Load audio file and convert to 16kHz mono Float32 samples
    private func loadAudioSamples(from url: URL) async throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let targetFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!

        guard let buffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw EngineError.audioConversionFailed
        }

        let converter = AVAudioConverter(from: file.processingFormat, to: targetFormat)!

        var conversionError: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            autoreleasepool {
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
        }

        converter.convert(to: buffer, error: &conversionError, withInputFrom: inputBlock)

        if let error = conversionError {
            throw error
        }

        guard let floatData = buffer.floatChannelData?[0] else {
            throw EngineError.audioConversionFailed
        }

        return Array(UnsafeBufferPointer(start: floatData, count: Int(buffer.frameLength)))
    }

    /// Remove consecutive duplicate words from the end of a transcript
    /// This handles artifacts from the echo-tail padding approach
    private func dedupeTrailingWords(_ text: String) -> String {
        let words = text.split(separator: " ").map(String.init)
        guard words.count >= 2 else { return text }

        // Check for repeated sequences at the end (1-4 words)
        for seqLen in 1...min(4, words.count / 2) {
            let endSeq = Array(words.suffix(seqLen))
            let beforeSeq = Array(words.suffix(seqLen * 2).prefix(seqLen))

            if endSeq == beforeSeq {
                // Remove the duplicate sequence
                let dedupedWords = Array(words.dropLast(seqLen))
                return dedupedWords.joined(separator: " ")
            }
        }
        return text
    }

    /// Generate low-level noise for audio padding
    /// Pink noise with very low amplitude keeps the encoder engaged without adding speech content
    private func generateLowLevelNoise(count: Int, amplitude: Float) -> [Float] {
        var noise = [Float](repeating: 0, count: count)
        var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0

        for i in 0..<count {
            // Generate white noise
            let white = Float.random(in: -1...1)

            // Convert to pink noise using Paul Kellet's algorithm
            b0 = 0.99886 * b0 + white * 0.0555179
            b1 = 0.99332 * b1 + white * 0.0750759
            b2 = 0.96900 * b2 + white * 0.1538520
            b3 = 0.86650 * b3 + white * 0.3104856
            b4 = 0.55000 * b4 + white * 0.5329522
            b5 = -0.7616 * b5 - white * 0.0168980

            let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
            b6 = white * 0.115926

            noise[i] = pink * amplitude
        }
        return noise
    }

    // MARK: - Model Preloading

    nonisolated func preloadModel(_ modelId: String, reply: @escaping (String?) -> Void) {
        Task { @MainActor in
            await self.doPreloadModel(modelId, reply: reply)
        }
    }

    private func doPreloadModel(_ modelId: String, reply: @escaping (String?) -> Void) async {
        guard !isWarmingUp else {
            EngineStatusManager.shared.log(.warning, "Preload", "Rejected - already warming up")
            reply("Already warming up")
            return
        }

        isWarmingUp = true
        defer { isWarmingUp = false }

        let (family, actualModelId) = parseModelId(modelId)
        AppLogger.shared.info(.transcription, "Preloading \(family) model: \(actualModelId)")
        EngineStatusManager.shared.log(.info, "Preload", "Preloading \(family):\(actualModelId)...")

        let startTime = Date()

        do {
            if family == "parakeet" {
                // Skip if already loaded
                if currentParakeetModelId == actualModelId && asrManager != nil {
                    let elapsed = Date().timeIntervalSince(startTime)
                    AppLogger.shared.info(.transcription, "Parakeet model \(actualModelId) already loaded")
                    EngineStatusManager.shared.log(.info, "Preload", "✓ Parakeet \(actualModelId) already loaded (\(String(format: "%.0f", elapsed * 1000))ms)")
                    reply(nil)
                    return
                }

                let asrVersion: AsrModelVersion = actualModelId == "v2" ? .v2 : .v3
                let isCached = downloadedParakeetModels.contains(actualModelId)
                EngineStatusManager.shared.log(.debug, "Preload", isCached ? "Loading Parakeet from cache..." : "Downloading Parakeet models...")
                let models = try await AsrModels.downloadAndLoad(version: asrVersion)
                EngineStatusManager.shared.log(.debug, "Preload", "Initializing Parakeet ASR manager...")
                asrManager = AsrManager(config: .default)
                try await asrManager?.initialize(models: models)
                currentParakeetModelId = actualModelId
                downloadedParakeetModels.insert(actualModelId)

                // Mark as downloaded
                let markerPath = parakeetModelsBaseURL.appendingPathComponent(actualModelId)
                try? FileManager.default.createDirectory(at: markerPath, withIntermediateDirectories: true)
                try? "downloaded".write(to: markerPath.appendingPathComponent(".marker"), atomically: true, encoding: .utf8)

                // Warmup with silent audio (1 second at 16kHz)
                AppLogger.shared.info(.transcription, "Running Parakeet warmup inference...")
                EngineStatusManager.shared.log(.debug, "Preload", "Running warmup inference...")
                let silentSamples = [Float](repeating: 0.0, count: 16000)
                _ = try? await asrManager?.transcribe(silentSamples)

                EngineStatusManager.shared.currentModel = "parakeet:\(actualModelId)"
                let elapsed = Date().timeIntervalSince(startTime)
                AppLogger.shared.info(.transcription, "Parakeet model \(actualModelId) preloaded and warmed up")
                EngineStatusManager.shared.log(.info, "Preload", "✓ Parakeet \(actualModelId) ready in \(String(format: "%.1f", elapsed))s")
            } else {
                // Check if model is already downloaded locally
                let localPath = whisperModelPath(for: actualModelId)
                if FileManager.default.fileExists(atPath: localPath) {
                    // Model already downloaded - load from local folder
                    AppLogger.shared.info(.transcription, "Loading Whisper from local folder: \(localPath)")
                    EngineStatusManager.shared.log(.debug, "Preload", "Loading Whisper from cache...")
                    whisperKit = try await WhisperKit(modelFolder: localPath, verbose: false)
                } else {
                    // Model not downloaded - download it
                    AppLogger.shared.info(.transcription, "Whisper model not found locally, downloading...")
                    EngineStatusManager.shared.log(.info, "Preload", "Downloading Whisper model (not cached)...")
                    whisperKit = try await WhisperKit(
                        model: actualModelId,
                        downloadBase: whisperModelsBaseURL,
                        verbose: false
                    )
                }
                currentWhisperModelId = actualModelId
                downloadedWhisperModels.insert(actualModelId)

                // Warmup with silent audio
                AppLogger.shared.info(.transcription, "Running Whisper warmup inference...")
                EngineStatusManager.shared.log(.debug, "Preload", "Running warmup inference...")
                let silentAudio = [Float](repeating: 0.0, count: 16000)
                _ = try? await whisperKit?.transcribe(audioArray: silentAudio)

                EngineStatusManager.shared.currentModel = "whisper:\(actualModelId)"
                let elapsed = Date().timeIntervalSince(startTime)
                AppLogger.shared.info(.transcription, "Whisper model \(actualModelId) preloaded and warmed up")
                EngineStatusManager.shared.log(.info, "Preload", "✓ Whisper \(actualModelId) ready in \(String(format: "%.1f", elapsed))s")
            }

            reply(nil)

        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            AppLogger.shared.error(.transcription, "Failed to preload model: \(error.localizedDescription)")
            EngineStatusManager.shared.log(.error, "Preload", "✗ Failed after \(String(format: "%.1f", elapsed))s: \(error.localizedDescription)")
            reply(error.localizedDescription)
        }
    }

    nonisolated func unloadModel(reply: @escaping () -> Void) {
        Task { @MainActor in
            self.whisperKit = nil
            self.currentWhisperModelId = nil
            self.asrManager = nil
            self.currentParakeetModelId = nil
            EngineStatusManager.shared.currentModel = nil
            AppLogger.shared.info(.transcription, "All models unloaded")
            EngineStatusManager.shared.log(.info, "Engine", "All models unloaded")
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
            // Prefer Parakeet (faster, more commonly used) over Whisper in status
            if let parakeetModel = self.currentParakeetModelId {
                loadedId = "parakeet:\(parakeetModel)"
            } else if let whisperModel = self.currentWhisperModelId {
                loadedId = "whisper:\(whisperModel)"
            }

            #if DEBUG
            let isDebug = true
            #else
            let isDebug = false
            #endif

            let status = EngineStatus(
                pid: ProcessInfo.processInfo.processIdentifier,
                version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                startedAt: self.startedAt,
                bundleId: Bundle.main.bundleIdentifier ?? "jdi.talkie.engine",
                isDebugBuild: isDebug,
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
        AppLogger.shared.info(.transcription, "[XPC] ping received, responding true")
        reply(true)
    }

    // MARK: - Graceful Shutdown

    nonisolated func requestShutdown(waitForCompletion: Bool, reply: @escaping (Bool) -> Void) {
        AppLogger.shared.info(.transcription, "[XPC] Shutdown requested (waitForCompletion: \(waitForCompletion))")

        Task { @MainActor in
            // Stop accepting new work immediately
            self.isShuttingDown = true
            EngineStatusManager.shared.log(.warning, "Engine", "Shutdown requested - no longer accepting new work")

            if waitForCompletion && self.isTranscribing {
                EngineStatusManager.shared.log(.info, "Engine", "Waiting for current transcription to complete...")

                // Wait for transcription to finish (up to 2 minutes grace period)
                let deadline = Date().addingTimeInterval(120)
                while self.isTranscribing && Date() < deadline {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                }

                if self.isTranscribing {
                    EngineStatusManager.shared.log(.warning, "Engine", "Timeout waiting, shutting down anyway")
                } else {
                    EngineStatusManager.shared.log(.info, "Engine", "Transcription complete, shutting down")
                }
            }

            reply(true)

            // Give the reply a moment to send, then exit
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                autoreleasepool {
                    AppLogger.shared.info(.transcription, "TalkieEngine exiting gracefully")
                    EngineStatusManager.shared.log(.info, "Engine", "Goodbye!")
                    NSApp.terminate(nil)
                }
            }
        }
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
            EngineStatusManager.shared.log(.warning, "Download", "Rejected - already downloading")
            reply("Already downloading a model")
            return
        }

        let (family, actualModelId) = parseModelId(modelId)

        // Check if already downloaded
        if family == "parakeet" && downloadedParakeetModels.contains(actualModelId) {
            AppLogger.shared.info(.transcription, "Parakeet model \(actualModelId) already downloaded")
            EngineStatusManager.shared.log(.debug, "Download", "Parakeet \(actualModelId) already cached")
            reply(nil)
            return
        } else if family == "whisper" && downloadedWhisperModels.contains(actualModelId) {
            AppLogger.shared.info(.transcription, "Whisper model \(actualModelId) already downloaded")
            EngineStatusManager.shared.log(.debug, "Download", "Whisper \(actualModelId) already cached")
            reply(nil)
            return
        }

        isDownloading = true
        currentDownloadModelId = modelId
        downloadProgress = 0
        downloadedBytes = 0
        totalDownloadBytes = nil

        AppLogger.shared.info(.transcription, "Starting download for \(family) model: \(actualModelId)")
        EngineStatusManager.shared.log(.info, "Download", "Starting download: \(family):\(actualModelId)")

        let startTime = Date()

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
                        let elapsed = Date().timeIntervalSince(startTime)
                        AppLogger.shared.info(.transcription, "Parakeet model \(actualModelId) downloaded successfully")
                        EngineStatusManager.shared.log(.info, "Download", "✓ Parakeet \(actualModelId) downloaded in \(String(format: "%.1f", elapsed))s")
                    }
                } else {
                    // Download Whisper model using model name and downloadBase
                    AppLogger.shared.info(.transcription, "Downloading Whisper model \(actualModelId)...")
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
                        let elapsed = Date().timeIntervalSince(startTime)
                        AppLogger.shared.info(.transcription, "Whisper model \(actualModelId) downloaded successfully to \(self.whisperModelPath(for: actualModelId))")
                        EngineStatusManager.shared.log(.info, "Download", "✓ Whisper \(actualModelId) downloaded in \(String(format: "%.1f", elapsed))s")
                    }
                }
                reply(nil)

            } catch {
                await MainActor.run {
                    self.isDownloading = false
                    self.currentDownloadModelId = nil
                    let elapsed = Date().timeIntervalSince(startTime)
                    AppLogger.shared.error(.transcription, "Failed to download model \(actualModelId): \(error.localizedDescription)")
                    EngineStatusManager.shared.log(.error, "Download", "✗ Failed after \(String(format: "%.1f", elapsed))s: \(error.localizedDescription)")
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
            let modelId = self.currentDownloadModelId ?? "unknown"
            if let task = self.downloadTask {
                task.cancel()
                self.downloadTask = nil
            }
            self.isDownloading = false
            self.currentDownloadModelId = nil
            self.downloadProgress = 0
            AppLogger.shared.info(.transcription, "Download cancelled")
            EngineStatusManager.shared.log(.warning, "Download", "Cancelled download: \(modelId)")
            reply()
        }
    }

    nonisolated func getAvailableModels(reply: @escaping (Data?) -> Void) {
        AppLogger.shared.info(.transcription, "[XPC] getAvailableModels called")
        Task { @MainActor in
            var models: [ModelInfo] = []

            AppLogger.shared.info(.transcription, "[Models] Building model list - Whisper downloaded: \(self.downloadedWhisperModels), Parakeet downloaded: \(self.downloadedParakeetModels)")

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

            AppLogger.shared.info(.transcription, "[Models] Returning \(models.count) models to client")

            do {
                let data = try JSONEncoder().encode(models)
                AppLogger.shared.info(.transcription, "[Models] Encoded \(data.count) bytes of model data")
                reply(data)
            } catch {
                AppLogger.shared.error(.transcription, "[Models] Failed to encode models: \(error.localizedDescription)")
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
