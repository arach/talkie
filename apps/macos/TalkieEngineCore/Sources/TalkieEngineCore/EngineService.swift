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
    private var whisperPrepareTask: Task<Void, Error>?
    private var whisperPrepareModelId: String?
    private var parakeetPrepareTask: Task<Void, Error>?
    private var parakeetPrepareModelId: String?

    override init() {
        super.init()
        refreshDownloadedModels()
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

        // Log cached models (debug only - don't spam startup logs)
        AppLogger.shared.debug(.model, "Cached models", detail: "whisper=\(downloadedWhisperModels.count), parakeet=\(downloadedParakeetModels.count)")
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

    private func missingModelMessage(for fullModelId: String) -> String {
        "Model \(fullModelId) is not downloaded. Download it in Talkie settings before transcribing."
    }

    private func preparingModelMessage(for fullModelId: String) -> String {
        "Model \(fullModelId) is still preparing in the background. Wait for it to finish or choose a downloaded model in Talkie settings."
    }

    private func markParakeetModelDownloaded(_ modelId: String) {
        let markerPath = parakeetModelsBaseURL.appendingPathComponent(modelId)
        try? FileManager.default.createDirectory(at: markerPath, withIntermediateDirectories: true)
        try? "downloaded".write(to: markerPath.appendingPathComponent(".marker"), atomically: true, encoding: .utf8)
        downloadedParakeetModels.insert(modelId)
    }

    private func runParakeetWarmupIfNeeded() async {
        guard let asrManager else { return }
        AppLogger.shared.info(.transcription, "Running Parakeet warmup inference...")
        EngineStatusManager.shared.log(.debug, "Preload", "Running warmup inference...")
        let silentSamples = [Float](repeating: 0.0, count: 16000)
        _ = try? await asrManager.transcribe(silentSamples)
    }

    private func runWhisperWarmupIfNeeded() async {
        guard let whisperKit else { return }
        AppLogger.shared.info(.transcription, "Running Whisper warmup inference...")
        EngineStatusManager.shared.log(.debug, "Preload", "Running warmup inference...")
        let silentAudio = [Float](repeating: 0.0, count: 16000)
        _ = try? await whisperKit.transcribe(audioArray: silentAudio)
    }

    private func ensureParakeetModelReady(
        _ modelId: String,
        allowDownload: Bool,
        warmUp: Bool
    ) async throws {
        if currentParakeetModelId == modelId, asrManager != nil {
            if warmUp {
                await runParakeetWarmupIfNeeded()
            }
            return
        }

        if let task = parakeetPrepareTask {
            let activeModelId = parakeetPrepareModelId
            let isDownloaded = downloadedParakeetModels.contains(modelId)

            if activeModelId == modelId, !allowDownload, !isDownloaded {
                throw EngineError.modelNotDownloaded(preparingModelMessage(for: "parakeet:\(modelId)"))
            }

            do {
                try await task.value
            } catch {
                if activeModelId == modelId {
                    throw error
                }
            }

            if currentParakeetModelId == modelId, asrManager != nil {
                if warmUp {
                    await runParakeetWarmupIfNeeded()
                }
                return
            }
        }

        let fullModelId = "parakeet:\(modelId)"
        guard downloadedParakeetModels.contains(modelId) || allowDownload else {
            throw EngineError.modelNotDownloaded(missingModelMessage(for: fullModelId))
        }

        let task = Task<Void, Error> { @MainActor [self] in
            let asrVersion: AsrModelVersion = modelId == "v2" ? .v2 : .v3
            AppLogger.shared.info(.transcription, "Loading Parakeet model: \(modelId)")
            EngineStatusManager.shared.log(
                .info,
                "Parakeet",
                downloadedParakeetModels.contains(modelId)
                    ? "Loading model: \(modelId)"
                    : "Downloading and loading model: \(modelId)"
            )

            let models = try await AsrModels.downloadAndLoad(version: asrVersion)
            EngineStatusManager.shared.log(.debug, "Parakeet", "Models downloaded, initializing ASR manager...")

            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            asrManager = manager
            currentParakeetModelId = modelId
            markParakeetModelDownloaded(modelId)
            EngineStatusManager.shared.currentModel = fullModelId
            EngineStatusManager.shared.log(.info, "Parakeet", "Model \(modelId) loaded and ready")
        }

        parakeetPrepareTask = task
        parakeetPrepareModelId = modelId

        do {
            try await task.value
        } catch {
            if parakeetPrepareModelId == modelId {
                parakeetPrepareTask = nil
                parakeetPrepareModelId = nil
            }
            throw error
        }

        if parakeetPrepareModelId == modelId {
            parakeetPrepareTask = nil
            parakeetPrepareModelId = nil
        }

        if warmUp {
            await runParakeetWarmupIfNeeded()
        }
    }

    private func ensureWhisperModelReady(
        _ modelId: String,
        allowDownload: Bool,
        warmUp: Bool
    ) async throws {
        if currentWhisperModelId == modelId, whisperKit != nil {
            if warmUp {
                await runWhisperWarmupIfNeeded()
            }
            return
        }

        if let task = whisperPrepareTask {
            let activeModelId = whisperPrepareModelId
            let localPath = whisperModelPath(for: modelId)
            let isCached = downloadedWhisperModels.contains(modelId) || FileManager.default.fileExists(atPath: localPath)

            if activeModelId == modelId, !allowDownload, !isCached {
                throw EngineError.modelNotDownloaded(preparingModelMessage(for: "whisper:\(modelId)"))
            }

            do {
                try await task.value
            } catch {
                if activeModelId == modelId {
                    throw error
                }
            }

            if currentWhisperModelId == modelId, whisperKit != nil {
                if warmUp {
                    await runWhisperWarmupIfNeeded()
                }
                return
            }
        }

        let fullModelId = "whisper:\(modelId)"
        let localPath = whisperModelPath(for: modelId)
        let isCached = downloadedWhisperModels.contains(modelId) || FileManager.default.fileExists(atPath: localPath)
        guard isCached || allowDownload else {
            throw EngineError.modelNotDownloaded(missingModelMessage(for: fullModelId))
        }

        let task = Task<Void, Error> { @MainActor [self] in
            AppLogger.shared.info(.transcription, "Loading Whisper model: \(modelId)")
            EngineStatusManager.shared.log(
                .info,
                "Whisper",
                isCached ? "Loading model: \(modelId)" : "Downloading and loading model: \(modelId)"
            )

            if FileManager.default.fileExists(atPath: localPath) {
                AppLogger.shared.info(.transcription, "Loading from local folder: \(localPath)")
                EngineStatusManager.shared.log(.debug, "Whisper", "Loading from local cache...")
                whisperKit = try await WhisperKit(modelFolder: localPath, verbose: false)
            } else {
                AppLogger.shared.info(.transcription, "Model not found locally, downloading...")
                whisperKit = try await WhisperKit(
                    model: modelId,
                    downloadBase: whisperModelsBaseURL,
                    verbose: false
                )
            }

            currentWhisperModelId = modelId
            downloadedWhisperModels.insert(modelId)
            EngineStatusManager.shared.currentModel = fullModelId
            EngineStatusManager.shared.log(.info, "Whisper", "Model \(modelId) loaded")
        }

        whisperPrepareTask = task
        whisperPrepareModelId = modelId

        do {
            try await task.value
        } catch {
            if whisperPrepareModelId == modelId {
                whisperPrepareTask = nil
                whisperPrepareModelId = nil
            }
            throw error
        }

        if whisperPrepareModelId == modelId {
            whisperPrepareTask = nil
            whisperPrepareModelId = nil
        }

        if warmUp {
            await runWhisperWarmupIfNeeded()
        }
    }

    // MARK: - TalkieEngineProtocol

    /// Transcribe audio file to text
    /// Transcription is pure by default - use postProcess to opt-in to additional processing
    nonisolated func transcribe(
        audioPath: String,
        modelId: String,
        externalRefId: String?,
        priority: TranscriptionPriority,
        postProcess: PostProcessOption,
        reply: @escaping (String?, String?) -> Void
    ) {
        Task(priority: priority.taskPriority) { @MainActor in
            do {
                let transcript = try await self.transcribe(
                    audioPath: audioPath,
                    modelId: modelId,
                    externalRefId: externalRefId,
                    priority: priority,
                    postProcess: postProcess
                )
                reply(transcript, nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    /// Transcribe with word-level timestamps
    nonisolated func transcribeWithTimings(
        audioPath: String,
        modelId: String,
        externalRefId: String?,
        priority: TranscriptionPriority,
        postProcess: PostProcessOption,
        reply: @escaping (String?, Data?, String?) -> Void
    ) {
        Task(priority: priority.taskPriority) { @MainActor in
            do {
                let result = try await self.transcribeWithTimings(
                    audioPath: audioPath,
                    modelId: modelId,
                    externalRefId: externalRefId,
                    priority: priority,
                    postProcess: postProcess
                )
                reply(result.text, result.timedTranscription?.toData(), nil)
            } catch {
                reply(nil, nil, error.localizedDescription)
            }
        }
    }

    private func doTranscribeWithTimings(
        audioPath: String,
        modelId: String,
        externalRefId: String?,
        postProcess: PostProcessOption,
        reply: @escaping (String?, Data?, String?) -> Void
    ) async {
        // Reuse the shared transcription pipeline, pass timing data in reply
        await doTranscribeShared(
            audioPath: audioPath,
            modelId: modelId,
            externalRefId: externalRefId,
            postProcess: postProcess
        ) { transcript, timedTranscription, error in
            reply(transcript, timedTranscription?.toData(), error)
        }
    }

    private func doTranscribe(
        audioPath: String,
        modelId: String,
        externalRefId: String?,
        postProcess: PostProcessOption,
        reply: @escaping (String?, String?) -> Void
    ) async {
        // Delegate to shared pipeline, discard timing data
        await doTranscribeShared(
            audioPath: audioPath,
            modelId: modelId,
            externalRefId: externalRefId,
            postProcess: postProcess
        ) { transcript, _, error in
            reply(transcript, error)
        }
    }

    private func doTranscribeShared(
        audioPath: String,
        modelId: String,
        externalRefId: String?,
        postProcess: PostProcessOption,
        reply: @escaping (String?, TimedTranscription?, String?) -> Void
    ) async {
        guard !isShuttingDown else {
            EngineStatusManager.shared.log(.warning, "Transcribe", "Rejected - engine is shutting down")
            reply(nil, nil, "Engine is shutting down, please retry")
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
            reply(nil, nil, "Audio file not found")
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
        let refStr = externalRefId.map { "[\($0)] " } ?? ""
        let fileSizeKB = String(format: "%.0f KB", Double(fileSize) / 1024)
        AppLogger.shared.info(.transcription, "Transcribing \(fileName) with \(family):\(actualModelId)")
        EngineStatusManager.shared.log(.info, "Request", "\(refStr)→ \(fileName) (\(fileSizeKB)) • \(family):\(actualModelId)")

        trace.mark("start", metadata: "\(family):\(actualModelId)")

        do {
            let result: TranscriptionResult
            if family == "parakeet" {
                result = try await transcribeWithParakeet(audioPath: audioPath, modelId: actualModelId, trace: trace)
            } else {
                result = try await transcribeWithWhisper(audioPath: audioPath, modelId: actualModelId, trace: trace)
            }

            trace.mark("complete")

            // Apply post-processing if requested (transcription is pure by default)
            let finalTranscript: String
            switch postProcess {
            case .none:
                // Raw transcription - no processing
                trace.begin("postprocess")
                trace.end("none (raw)")
                finalTranscript = result.transcript

            case .inverseTextNormalization:
                trace.begin("postprocess")
                let normalized = InverseTextNormalizer.normalize(result.transcript)
                if normalized != result.transcript {
                    AppLogger.shared.info(.transcription, "Inverse text normalization applied")
                    EngineStatusManager.shared.log(.debug, "ITN", "spoken-form → written-form")
                }
                finalTranscript = normalized
                trace.end(normalized != result.transcript ? "itn" : "itn (no changes)")

            case .dictionary:
                // Apply dictionary replacements, then number/punctuation normalization
                trace.begin("postprocess")
                let processed = TextPostProcessor.shared.process(result.transcript)
                var text = processed.processed
                if processed.hasChanges {
                    AppLogger.shared.info(.transcription, "Dictionary applied", detail: processed.replacementSummary)
                    EngineStatusManager.shared.log(.debug, "Dictionary", processed.replacementSummary)
                }

                // Run number + punctuation normalization on natural text
                let normalized = InverseTextNormalizer.normalize(text)
                if normalized != text {
                    let changes = text == processed.processed ? "numbers/punctuation" : "dictionary + numbers/punctuation"
                    AppLogger.shared.info(.transcription, "Text normalized", detail: changes)
                    text = normalized
                }
                finalTranscript = text
                trace.end(text != result.transcript ? "dictionary+normalize" : "dictionary (no changes)")

            case .intentRecognition:
                // Recognize voice navigation intent and return JSON-encoded IntentResult
                trace.begin("postprocess")
                let intentResult = await VoiceIntentRecognizer.shared.recognize(result.transcript)
                if let jsonData = try? JSONEncoder().encode(intentResult),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    finalTranscript = jsonString
                    AppLogger.shared.info(.transcription, "Intent recognized",
                                         detail: "\(intentResult.intent.rawValue) (\(String(format: "%.0f", intentResult.confidence * 100))%)")
                    EngineStatusManager.shared.log(.debug, "Intent", "\(intentResult.intent.rawValue) @ \(String(format: "%.0f", intentResult.confidence * 100))%")
                } else {
                    // Fallback to raw transcript if encoding fails
                    finalTranscript = result.transcript
                    AppLogger.shared.warning(.transcription, "Intent encoding failed, returning raw transcript")
                }
                trace.end("intent: \(intentResult.intent.rawValue)")

            case .proceduralProcessor:
                // Deterministic protocol dictation → syntax (e.g. "git space push space dash u" → "git push -u")
                trace.begin("postprocess")
                let processed = ProceduralProcessor.shared.process(result.transcript)
                finalTranscript = processed
                let charCount = processed.count
                AppLogger.shared.info(.transcription, "Procedural processor applied",
                                     detail: "\(result.transcript.prefix(40)) → \(processed.prefix(40))")
                EngineStatusManager.shared.log(.debug, "Procedural", "\(charCount) chars output")
                trace.end("procedural (\(charCount) chars)")

            @unknown default:
                // Future PostProcessOption values — fall back to dictionary processing
                trace.begin("postprocess")
                let fallbackResult = TextPostProcessor.shared.process(result.transcript)
                finalTranscript = fallbackResult.processed
                AppLogger.shared.warning(.transcription, "Unknown postProcess option, falling back to dictionary")
                trace.end("fallback dictionary")
            }

            let finalTimedTranscription = result.timedTranscription.map { timedTranscription in
                if timedTranscription.text == finalTranscript {
                    return timedTranscription
                }
                return TimedTranscription(text: finalTranscript, words: timedTranscription.words)
            }

            // Log trace summary for E2E trace viewer correlation
            AppLogger.shared.log(.performance, "Trace complete", detail: trace.summary)

            totalTranscriptions += 1
            let elapsed = trace.elapsedSeconds
            let elapsedMs = trace.elapsedMs
            let wordCount = finalTranscript.split(separator: " ").count
            AppLogger.shared.info(.transcription, "Transcribed #\(self.totalTranscriptions): \(finalTranscript.prefix(50))...")
            let timeStr = elapsedMs < 1000 ? "\(elapsedMs)ms" : String(format: "%.2fs", elapsed)

            // Calculate RTF (realtime factor) for performance insight
            let audioDur = result.audioDuration ?? 0
            let rtf = audioDur > 0 ? elapsed / audioDur : 0
            let rtfStr = rtf > 0 ? String(format: "%.1fx", 1.0 / rtf) : "—"  // Higher is better (e.g., 5.2x = 5.2x faster than realtime)

            // Abbreviated transcript preview (first ~40 chars)
            let preview = finalTranscript.prefix(40)
            let previewStr = finalTranscript.count > 40 ? "\(preview)..." : String(preview)

            // Rich log: refId → time (RTF) words "preview..."
            EngineStatusManager.shared.log(.info, "Complete", "\(refStr)✓ \(timeStr) (\(rtfStr)) \(wordCount)w \"\(previewStr)\"")
            EngineStatusManager.shared.totalTranscriptions = totalTranscriptions

            // Record metric with full trace
            EngineStatusManager.shared.recordMetric(
                elapsed: elapsed,
                audioDuration: result.audioDuration,
                wordCount: wordCount,
                transcript: finalTranscript,
                trace: trace,
                modelId: modelId,
                audioFilename: fileName,
                audioSamples: result.sampleCount
            )
            reply(finalTranscript, finalTimedTranscription, nil)

        } catch {
            trace.mark("error", metadata: error.localizedDescription)
            let elapsed = trace.elapsedSeconds
            let elapsedMs = trace.elapsedMs
            let timeStr = elapsedMs < 1000 ? "\(elapsedMs)ms" : String(format: "%.2fs", elapsed)
            AppLogger.shared.error(.transcription, "Transcription failed: \(error.localizedDescription)")
            EngineStatusManager.shared.log(.error, "Error", "\(refStr)✗ \(fileName) failed after \(timeStr): \(error.localizedDescription)")
            reply(nil, nil, error.localizedDescription)
        }
    }

    /// Result from transcription methods (includes metadata for tracing)
    private struct TranscriptionResult {
        let transcript: String
        let audioDuration: Double?
        let sampleCount: Int?
        let timedTranscription: TimedTranscription?
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
            try await ensureWhisperModelReady(modelId, allowDownload: false, warmUp: false)
            trace.end("prepared")
        }

        guard let whisper = whisperKit else {
            throw EngineError.modelNotLoaded
        }

        // Transcribe directly from client's file
        trace.begin("inference")
        let options = DecodingOptions(language: "en")
        let results = try await whisper.transcribe(audioPath: audioPath, decodeOptions: options)

        // Post-process
        let transcript = results.map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = transcript.split(separator: " ").count
        let charCount = transcript.count

        // Extract word-level timings from WhisperKit results
        // TranscriptionResult.allWords flattens segments → words
        var wordSegments: [WordSegment] = []
        for result in results {
            for w in result.allWords {
                wordSegments.append(WordSegment(
                    word: w.word,
                    start: Double(w.start),
                    end: Double(w.end),
                    confidence: w.probability
                ))
            }
        }
        let timedTranscription: TimedTranscription? = wordSegments.isEmpty
            ? nil
            : TimedTranscription(text: transcript, words: wordSegments)

        // End inference with result metadata for signpost
        let inferenceMs = trace.end("\(results.count) segments, \(charCount) chars, \(wordCount) words, \(wordSegments.count) word timings")

        // Alert on slow transcriptions (>5s inference)
        if inferenceMs > 5000 {
            AppLogger.shared.warning(.performance, "SLOW WHISPER INFERENCE: \(inferenceMs)ms")
            EngineStatusManager.shared.log(.warning, "Perf", "⚠️ Slow Whisper inference: \(inferenceMs)ms")
        }

        AppLogger.shared.info(.transcription, "Whisper transcribed: \(transcript.prefix(50))...")
        return TranscriptionResult(transcript: transcript, audioDuration: nil, sampleCount: nil, timedTranscription: timedTranscription)
    }

    // MARK: - Parakeet Transcription

    private func transcribeWithParakeet(audioPath: String, modelId: String, trace: TranscriptionTrace) async throws -> TranscriptionResult {
        // Check if model needs loading
        trace.begin("model_check")
        let needsModelLoad = asrManager == nil || currentParakeetModelId != modelId
        trace.end(needsModelLoad ? "needs load" : "already loaded")

        // Load model if needed
        if needsModelLoad {
            trace.begin("model_load")
            try await ensureParakeetModelReady(modelId, allowDownload: false, warmUp: false)
            trace.end("prepared")
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

        // Trim trailing silence then append a chirp tail to keep the decoder active.
        // The Agent writes 1.5s of silence to the WAV for Whisper compatibility, but
        // Parakeet interprets prolonged silence as end-of-speech and drops trailing tokens.
        // The chirp is a broadband frequency sweep — clearly non-speech, impossible to
        // transcribe as words, but acoustically "alive" enough to flush final tokens.
        trace.begin("audio_pad")
        let trimmed = trimTrailingSilence(samples, threshold: 0.002, minKeep: 800)  // keep ≥50ms after last speech
        let trimmedCount = samples.count - trimmed.count
        samples = trimmed
        samples.append(contentsOf: generateChirpTail())
        trace.end("trimmed \(trimmedCount), +chirp tail")

        // Run inference - trace captures timing with mach_absolute_time
        trace.begin("inference")
        let result = try await manager.transcribe(samples)

        let transcript = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = transcript.split(separator: " ").count
        let charCount = transcript.count

        // Extract word-level timings from Parakeet token timings
        var wordSegments: [WordSegment] = []
        if let tokenTimings = result.tokenTimings {
            for t in tokenTimings {
                wordSegments.append(WordSegment(
                    word: t.token,
                    start: t.startTime,
                    end: t.endTime,
                    confidence: t.confidence
                ))
            }
        }
        let timedTranscription: TimedTranscription? = wordSegments.isEmpty
            ? nil
            : TimedTranscription(text: transcript, words: wordSegments)

        // End inference with result metadata for signpost
        let inferenceMs = trace.end("\(charCount) chars, \(wordCount) words, \(wordSegments.count) word timings")

        // Alert on slow transcriptions (>5s inference)
        if inferenceMs > 5000 {
            let rtf = Double(inferenceMs) / 1000.0 / audioDuration
            AppLogger.shared.warning(.performance, "SLOW INFERENCE: \(inferenceMs)ms for \(String(format: "%.1f", audioDuration))s audio (RTF: \(String(format: "%.2f", rtf)))")
            EngineStatusManager.shared.log(.warning, "Perf", "⚠️ Slow inference: \(inferenceMs)ms (\(String(format: "%.1fx", audioDuration * 1000 / Double(inferenceMs))) realtime)")
        }

        AppLogger.shared.info(.transcription, "Parakeet transcribed: \(transcript.prefix(50))... (\(samples.count) samples)")
        return TranscriptionResult(transcript: transcript, audioDuration: audioDuration, sampleCount: originalSampleCount, timedTranscription: timedTranscription)
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

    /// Trim trailing silence/near-silence from audio samples.
    /// Walks backward from the end, finds the last sample above `threshold`,
    /// then keeps at least `minKeep` samples after it as natural decay.
    private func trimTrailingSilence(_ samples: [Float], threshold: Float, minKeep: Int) -> [Float] {
        var lastLoudIndex = samples.count - 1
        while lastLoudIndex > 0 && abs(samples[lastLoudIndex]) < threshold {
            lastLoudIndex -= 1
        }
        let keepTo = min(samples.count, lastLoudIndex + 1 + minKeep)
        return Array(samples[0..<keepTo])
    }

    /// Generate a chirp tail for Parakeet: room tone → chirp burst → room tone.
    /// Layout: [150ms pink noise] [100ms chirp sweep 200→4000Hz] [150ms pink noise]
    /// Total: 400ms (6400 samples at 16kHz)
    ///
    /// The chirp is a linear frequency sweep — broadband energy that keeps the
    /// decoder active without producing recognizable speech tokens. Think of it
    /// as a tiny audio "ping" that says "still here" to the model.
    private func generateChirpTail() -> [Float] {
        let sampleRate: Float = 16000
        let roomToneSamples = 2400   // 150ms
        let chirpSamples = 1600      // 100ms
        let totalSamples = roomToneSamples + chirpSamples + roomToneSamples

        var tail = [Float](repeating: 0, count: totalSamples)

        // Room tone (pink noise at ~-40dB) — natural background
        let roomTone = generatePinkNoise(sampleCount: totalSamples, amplitude: 0.01)
        for i in 0..<totalSamples {
            tail[i] = roomTone[i]
        }

        // Chirp burst in the middle: linear sweep 200Hz → 4000Hz at ~-30dB
        let chirpStart = roomToneSamples
        let chirpAmplitude: Float = 0.03
        let f0: Float = 200
        let f1: Float = 4000
        for i in 0..<chirpSamples {
            let t = Float(i) / sampleRate
            let progress = Float(i) / Float(chirpSamples)
            let phase = 2 * Float.pi * (f0 * t + (f1 - f0) * t * progress / 2)
            // Hann window to avoid click artifacts at edges
            let window = 0.5 * (1 - cos(2 * Float.pi * progress))
            tail[chirpStart + i] += chirpAmplitude * window * sin(phase)
        }

        return tail
    }

    /// Generate pink noise using Paul Kellett's cascaded feedback algorithm.
    /// Used for room-tone simulation in chirp tails.
    private func generatePinkNoise(sampleCount: Int, amplitude: Float = 0.001) -> [Float] {
        var b0: Float = 0, b1: Float = 0, b2: Float = 0
        var b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
        var samples = [Float](repeating: 0, count: sampleCount)

        for i in 0..<sampleCount {
            let white = Float.random(in: -1...1)
            b0 = 0.99886 * b0 + white * 0.0555179
            b1 = 0.99332 * b1 + white * 0.0750759
            b2 = 0.96900 * b2 + white * 0.1538520
            b3 = 0.86650 * b3 + white * 0.3104856
            b4 = 0.55000 * b4 + white * 0.5329522
            b5 = -0.7616 * b5 - white * 0.0168980
            let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
            b6 = white * 0.115926
            samples[i] = pink * amplitude
        }
        return samples
    }

    // MARK: - Model Preloading

    nonisolated func preloadModel(_ modelId: String, reply: @escaping (String?) -> Void) {
        Task { @MainActor in
            do {
                try await self.preloadModel(modelId)
                reply(nil)
            } catch {
                reply(error.localizedDescription)
            }
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

                try await ensureParakeetModelReady(actualModelId, allowDownload: true, warmUp: true)
                let elapsed = Date().timeIntervalSince(startTime)
                AppLogger.shared.info(.transcription, "Parakeet model \(actualModelId) preloaded and warmed up")
                EngineStatusManager.shared.log(.info, "Preload", "✓ Parakeet \(actualModelId) ready in \(String(format: "%.1f", elapsed))s")
            } else {
                try await ensureWhisperModelReady(actualModelId, allowDownload: true, warmUp: true)
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
            await self.unloadModel()
            reply()
        }
    }

    nonisolated func getStatus(reply: @escaping (Data?) -> Void) {
        Task { @MainActor in
            reply(try? JSONEncoder().encode(await self.statusSnapshot()))
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
        Task { @MainActor in
            reply(await self.ping())
        }
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
            do {
                try await self.downloadModel(modelId)
                reply(nil)
            } catch {
                reply(error.localizedDescription)
            }
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
            guard let progress = await self.downloadProgressSnapshot() else {
                reply(nil)
                return
            }

            reply(try? JSONEncoder().encode(progress))
        }
    }

    nonisolated func cancelDownload(reply: @escaping () -> Void) {
        Task { @MainActor in
            await self.cancelDownload()
            reply()
        }
    }

    // MARK: - Dictionary Management

    nonisolated func updateDictionary(entriesJSON: Data, reply: @escaping (String?) -> Void) {
        Task { @MainActor in
            do {
                let entries = try JSONDecoder().decode([DictionaryEntry].self, from: entriesJSON)
                try await self.updateDictionary(entries)
                reply(nil)
            } catch {
                AppLogger.shared.error(.system, "Failed to decode dictionary", detail: error.localizedDescription)
                EngineStatusManager.shared.log(.error, "Dictionary", "Failed to decode: \(error.localizedDescription)")
                reply(error.localizedDescription)
            }
        }
    }

    nonisolated func setDictionaryEnabled(_ enabled: Bool, reply: @escaping () -> Void) {
        Task { @MainActor in
            await self.setDictionaryEnabled(enabled)
            reply()
        }
    }

    nonisolated func setSymbolicMappingEnabled(_ enabled: Bool, reply: @escaping () -> Void) {
        Task { @MainActor in
            await self.setSymbolicMappingEnabled(enabled)
            reply()
        }
    }

    nonisolated func setFillerRemovalEnabled(_ enabled: Bool, reply: @escaping () -> Void) {
        Task { @MainActor in
            await self.setFillerRemovalEnabled(enabled)
            reply()
        }
    }

    nonisolated func reloadSymbolicMapping(reply: @escaping (String?) -> Void) {
        Task { @MainActor in
            do {
                try await self.reloadSymbolicMapping()
                reply(nil)
            } catch {
                reply(error.localizedDescription)
            }
        }
    }

    nonisolated func getAvailableModels(reply: @escaping (Data?) -> Void) {
        AppLogger.shared.info(.transcription, "[XPC] getAvailableModels called")
        Task { @MainActor in
            do {
                let data = try JSONEncoder().encode(await self.availableModelsSnapshot())
                AppLogger.shared.info(.transcription, "[Models] Encoded \(data.count) bytes of model data")
                reply(data)
            } catch {
                AppLogger.shared.error(.transcription, "[Models] Failed to encode models: \(error.localizedDescription)")
                reply(nil)
            }
        }
    }

    // MARK: - Streaming ASR

    nonisolated func startStreamingASR(_ reply: @escaping (String?, String?) -> Void) {
        AppLogger.shared.info(.system, "[XPC] startStreamingASR called")
        Task { @MainActor in
            do {
                let sessionId = try await self.startStreamingASR()
                reply(sessionId, nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    private func doStartStreamingASR(reply: @escaping (String?, String?) -> Void) async {
        guard !isShuttingDown else {
            EngineStatusManager.shared.log(.warning, "StreamASR", "Rejected - engine is shutting down")
            reply(nil, "Engine is shutting down")
            return
        }

        do {
            let sessionId = try await StreamingASRService.shared.startSession()
            reply(sessionId, nil)
        } catch {
            AppLogger.shared.error(.system, "Streaming ASR start failed", detail: error.localizedDescription)
            reply(nil, error.localizedDescription)
        }
    }

    nonisolated func feedStreamingASR(sessionId: String, audio: Data, _ reply: @escaping (Data?, String?) -> Void) {
        Task { @MainActor in
            do {
                let events = try await self.feedStreamingASR(sessionId: sessionId, audio: audio)
                let data = try events.map { try JSONEncoder().encode($0) }
                reply(data, nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    private func doFeedStreamingASR(sessionId: String, audio: Data, reply: @escaping (Data?, String?) -> Void) async {
        guard !isShuttingDown else {
            reply(nil, "Engine is shutting down")
            return
        }

        do {
            let eventsData = try await StreamingASRService.shared.feedAudio(sessionId: sessionId, audioData: audio)
            reply(eventsData, nil)
        } catch {
            AppLogger.shared.warning(.system, "Streaming ASR feed failed", detail: error.localizedDescription)
            reply(nil, error.localizedDescription)
        }
    }

    nonisolated func stopStreamingASR(sessionId: String, _ reply: @escaping (String?, String?) -> Void) {
        AppLogger.shared.info(.system, "[XPC] stopStreamingASR called", detail: sessionId.prefix(8).description)
        Task { @MainActor in
            do {
                let transcript = try await self.stopStreamingASR(sessionId: sessionId)
                reply(transcript, nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    private func doStopStreamingASR(sessionId: String, reply: @escaping (String?, String?) -> Void) async {
        do {
            let transcript = try await StreamingASRService.shared.stopSession(sessionId: sessionId)
            reply(transcript, nil)
        } catch {
            AppLogger.shared.error(.system, "Streaming ASR stop failed", detail: error.localizedDescription)
            reply(nil, error.localizedDescription)
        }
    }
}

extension EngineService: EmbeddedEngineRuntime {
    func ping() async -> Bool {
        AppLogger.shared.info(.transcription, "[Runtime] ping")
        return true
    }

    func statusSnapshot() async -> EngineStatus {
        var allDownloaded: [String] = []
        for model in downloadedWhisperModels {
            allDownloaded.append("whisper:\(model)")
        }
        for model in downloadedParakeetModels {
            allDownloaded.append("parakeet:\(model)")
        }

        let loadedId: String?
        if let parakeetModel = currentParakeetModelId {
            loadedId = "parakeet:\(parakeetModel)"
        } else if let whisperModel = currentWhisperModelId {
            loadedId = "whisper:\(whisperModel)"
        } else {
            loadedId = nil
        }

        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif

        return EngineStatus(
            pid: ProcessInfo.processInfo.processIdentifier,
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            startedAt: startedAt,
            bundleId: Bundle.main.bundleIdentifier ?? "jdi.talkie.engine",
            isDebugBuild: isDebug,
            loadedModelId: loadedId,
            isTranscribing: isTranscribing,
            isWarmingUp: isWarmingUp,
            downloadedModels: allDownloaded,
            totalTranscriptions: totalTranscriptions,
            memoryUsageMB: getMemoryUsageMB()
        )
    }

    func transcribe(
        audioPath: String,
        modelId: String,
        externalRefId: String?,
        priority: TranscriptionPriority,
        postProcess: PostProcessOption
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                await doTranscribe(
                    audioPath: audioPath,
                    modelId: modelId,
                    externalRefId: externalRefId,
                    postProcess: postProcess
                ) { transcript, error in
                    if let error {
                        continuation.resume(throwing: EngineError.operationFailed(error))
                    } else if let transcript {
                        continuation.resume(returning: transcript)
                    } else {
                        continuation.resume(throwing: EngineError.emptyResponse)
                    }
                }
            }
        }
    }

    func transcribeWithTimings(
        audioPath: String,
        modelId: String,
        externalRefId: String?,
        priority: TranscriptionPriority,
        postProcess: PostProcessOption
    ) async throws -> (text: String, timedTranscription: TimedTranscription?) {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                await doTranscribeWithTimings(
                    audioPath: audioPath,
                    modelId: modelId,
                    externalRefId: externalRefId,
                    postProcess: postProcess
                ) { transcript, segmentsJSON, error in
                    if let error {
                        continuation.resume(throwing: EngineError.operationFailed(error))
                    } else if let transcript {
                        continuation.resume(returning: (transcript, segmentsJSON.flatMap(TimedTranscription.from(data:))))
                    } else {
                        continuation.resume(throwing: EngineError.emptyResponse)
                    }
                }
            }
        }
    }

    func preloadModel(_ modelId: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                await doPreloadModel(modelId) { error in
                    if let error {
                        continuation.resume(throwing: EngineError.operationFailed(error))
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    func unloadModel() async {
        whisperKit = nil
        currentWhisperModelId = nil
        asrManager = nil
        currentParakeetModelId = nil
        EngineStatusManager.shared.currentModel = nil
        AppLogger.shared.info(.transcription, "All models unloaded")
        EngineStatusManager.shared.log(.info, "Engine", "All models unloaded")
    }

    func downloadModel(_ modelId: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                await doDownloadModel(modelId) { error in
                    if let error {
                        continuation.resume(throwing: EngineError.operationFailed(error))
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    func downloadProgressSnapshot() async -> DownloadProgress? {
        guard isDownloading, let modelId = currentDownloadModelId else {
            return nil
        }

        return DownloadProgress(
            modelId: modelId,
            progress: downloadProgress,
            downloadedBytes: downloadedBytes,
            totalBytes: totalDownloadBytes,
            isDownloading: isDownloading
        )
    }

    func cancelDownload() async {
        let modelId = currentDownloadModelId ?? "unknown"
        if let task = downloadTask {
            task.cancel()
            downloadTask = nil
        }
        isDownloading = false
        currentDownloadModelId = nil
        downloadProgress = 0
        AppLogger.shared.info(.transcription, "Download cancelled")
        EngineStatusManager.shared.log(.warning, "Download", "Cancelled download: \(modelId)")
    }

    func availableModelsSnapshot() async -> [ModelInfo] {
        AppLogger.shared.info(.transcription, "[Models] Building model list - Whisper downloaded: \(downloadedWhisperModels), Parakeet downloaded: \(downloadedParakeetModels)")

        var models: [ModelInfo] = []

        for model in Self.knownWhisperModels {
            let fullId = "whisper:\(model.id)"
            models.append(ModelInfo(
                id: fullId,
                family: "whisper",
                modelId: model.id,
                displayName: "Whisper \(model.displayName)",
                sizeDescription: model.size,
                description: model.description,
                isDownloaded: downloadedWhisperModels.contains(model.id),
                isLoaded: currentWhisperModelId == model.id
            ))
        }

        for model in Self.knownParakeetModels {
            let fullId = "parakeet:\(model.id)"
            models.append(ModelInfo(
                id: fullId,
                family: "parakeet",
                modelId: model.id,
                displayName: model.displayName,
                sizeDescription: model.size,
                description: model.description,
                isDownloaded: downloadedParakeetModels.contains(model.id),
                isLoaded: currentParakeetModelId == model.id
            ))
        }

        AppLogger.shared.info(.transcription, "[Models] Returning \(models.count) models to runtime client")
        return models
    }

    func updateDictionary(_ entries: [DictionaryEntry]) async throws {
        TextPostProcessor.shared.updateDictionary(entries)
        EngineStatusManager.shared.log(.info, "Dictionary", "Updated with \(entries.count) entries")
    }

    func setDictionaryEnabled(_ enabled: Bool) async {
        TextPostProcessor.shared.setEnabled(enabled)
        EngineStatusManager.shared.log(.info, "Dictionary", enabled ? "Enabled" : "Disabled")
    }

    func setSymbolicMappingEnabled(_ enabled: Bool) async {
        TextPostProcessor.shared.isSymbolicMappingEnabled = enabled
        EngineStatusManager.shared.log(.info, "Symbolic Mapping", enabled ? "Enabled" : "Disabled")
    }

    func setFillerRemovalEnabled(_ enabled: Bool) async {
        TextPostProcessor.shared.setFillerRemovalEnabled(enabled)
        EngineStatusManager.shared.log(.info, "Filler Removal", enabled ? "Enabled" : "Disabled")
    }

    func reloadSymbolicMapping() async throws {
        SymbolicMapper.shared.reloadFromFile()
        EngineStatusManager.shared.log(.info, "Symbolic Mapping", "Reloaded from file")
    }

    func startStreamingASR() async throws -> String {
        guard !isShuttingDown else {
            EngineStatusManager.shared.log(.warning, "StreamASR", "Rejected - engine is shutting down")
            throw EngineError.operationFailed("Engine is shutting down")
        }

        return try await StreamingASRService.shared.startSession()
    }

    func feedStreamingASR(sessionId: String, audio: Data) async throws -> [StreamingASREvent]? {
        guard !isShuttingDown else {
            throw EngineError.operationFailed("Engine is shutting down")
        }

        guard let data = try await StreamingASRService.shared.feedAudio(sessionId: sessionId, audioData: audio) else {
            return nil
        }

        return try JSONDecoder().decode([StreamingASREvent].self, from: data)
    }

    func stopStreamingASR(sessionId: String) async throws -> String {
        try await StreamingASRService.shared.stopSession(sessionId: sessionId)
    }
}

// MARK: - Engine Errors

enum EngineError: LocalizedError {
    case modelNotLoaded
    case modelNotDownloaded(String)
    case audioConversionFailed
    case transcriptionFailed(Error)
    case operationFailed(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Model not loaded"
        case .modelNotDownloaded(let message):
            return message
        case .audioConversionFailed:
            return "Failed to convert audio format"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .operationFailed(let message):
            return message
        case .emptyResponse:
            return "Engine returned an empty response"
        }
    }
}
