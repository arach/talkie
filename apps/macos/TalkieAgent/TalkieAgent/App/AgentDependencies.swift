import Foundation
import os.log

private let logger = Logger(subsystem: "to.talkie.app.agent", category: "Dependencies")

// MARK: - Audio Reboot Result

/// Result of audio system reboot operation
enum AudioRebootResult {
    case success           // Rebooted and HAL is healthy
    case successDegraded   // Rebooted but HAL still slow
    case failed            // Reboot failed entirely
}

// MARK: - Protocols

protocol AgentAudioCapture {
    func startCapture(onChunk: @escaping ([String]) -> Void)  // Receives segment file paths
    func stopCapture()
    func requestCheckpoint()
    var currentSegmentIndex: Int { get }
    var onSegmentCompleted: ((AudioWriterSegment) -> Void)? { get set }
    var onCaptureError: ((String) -> Void)? { get set }  // Called when capture fails to start
    @discardableResult
    func reboot() async -> AudioRebootResult  // Full audio system reset
}

protocol AgentRouter {
    @MainActor @discardableResult
    func handle(transcript: String) async -> Bool
}

// MARK: - Stub Implementations (for now)

final class StubAudioCapture: AgentAudioCapture {
    private var timer: Timer?
    var onSegmentCompleted: ((AudioWriterSegment) -> Void)?
    var onCaptureError: ((String) -> Void)?
    var currentSegmentIndex: Int { 0 }

    func startCapture(onChunk: @escaping ([String]) -> Void) {
        logger.info("Audio capture started")
        // Simulate listening for 2 seconds, then deliver a "buffer"
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            logger.info("Audio buffer captured")
            onChunk(["/tmp/stub-audio.m4a"])  // Stub path
        }
    }

    func stopCapture() {
        logger.info("Audio capture stopped")
        timer?.invalidate()
        timer = nil
    }

    func requestCheckpoint() {
        logger.info("Audio checkpoint requested (stub - no-op)")
    }

    @discardableResult
    func reboot() async -> AudioRebootResult {
        logger.info("Audio reboot (stub - no-op)")
        return .success
    }
}

struct StubTranscriptionService: TranscriptionService {
    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        logger.info("Transcribing audio file: \(request.audioPath) (live: \(request.isLive))...")
        // Simulate transcription taking 1.5 seconds
        try await Task.sleep(for: .milliseconds(1500))
        let transcript = "This is a stub transcript from Talkie Agent."
        logger.info("Transcription complete: \(transcript)")
        return Transcript(text: transcript, confidence: 0.95)
    }
}

// MARK: - Engine Transcription Service

/// TranscriptionService that uses the embedded engine hosted inside TalkieAgent.
struct EngineTranscriptionService: TranscriptionService {
    private let modelId: String

    init(modelId: String = TalkieDefaults.transcriptionModelId) {
        self.modelId = modelId
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        let engine = await EmbeddedEngineCoordinator.shared
        let connected = await engine.ensureReady()

        guard connected else {
            logger.error("═══════════════════════════════════════════════════════════")
            logger.error("  ❌ EMBEDDED ENGINE UNAVAILABLE")
            logger.error("  TalkieAgent could not start its in-process engine.")
            logger.error("═══════════════════════════════════════════════════════════")
            throw EngineTranscriptionError.engineNotRunning
        }

        let fileName = URL(fileURLWithPath: request.audioPath).lastPathComponent
        logger.notice("═══════════════════════════════════════════════════════════")
        logger.notice("  🎙️ TRANSCRIBING VIA EMBEDDED ENGINE")
        logger.notice("  Model: \(self.modelId)")
        logger.notice("  Audio: \(fileName)")
        logger.notice("═══════════════════════════════════════════════════════════")

        let startTime = Date()

        let (text, timedTranscription) = try await engine.transcribeWithTimings(
            audioPath: request.audioPath,
            modelId: modelId,
            externalRefId: request.externalRefId,
            priority: .high,
            postProcess: request.postProcess
        )
        let elapsed = Date().timeIntervalSince(startTime)

        let wordTimingCount = timedTranscription?.words.count ?? 0
        logger.notice("═══════════════════════════════════════════════════════════")
        logger.notice("  ✅ ENGINE TRANSCRIPTION COMPLETE")
        logger.notice("  Time: \(String(format: "%.2f", elapsed))s")
        logger.notice("  Result: \(text.prefix(80))...")
        logger.notice("  Word timings: \(wordTimingCount)")
        logger.notice("═══════════════════════════════════════════════════════════")

        return Transcript(text: text, confidence: nil, timedTranscription: timedTranscription)
    }
}

enum EngineTranscriptionError: LocalizedError {
    case engineNotRunning

    var errorDescription: String? {
        switch self {
        case .engineNotRunning:
            return "TalkieAgent's embedded engine failed to start."
        }
    }
}

struct LoggingRouter: AgentRouter {
    @MainActor @discardableResult
    func handle(transcript: String) async -> Bool {
        logger.info("Routing transcript...")
        // Simulate routing taking 0.5 seconds
        try? await Task.sleep(for: .milliseconds(500))
        logger.info("Transcript routed: \(transcript)")
        return true
    }
}
