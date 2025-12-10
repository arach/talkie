import Foundation
import os.log

private let logger = Logger(subsystem: "jdi.talkie.live", category: "Dependencies")

// MARK: - Protocols

protocol LiveAudioCapture {
    func startCapture(onChunk: @escaping (Data) -> Void)
    func stopCapture()
}

protocol LiveRouter {
    func handle(transcript: String) async
}

// MARK: - Stub Implementations (for now)

final class StubAudioCapture: LiveAudioCapture {
    private var timer: Timer?

    func startCapture(onChunk: @escaping (Data) -> Void) {
        logger.info("Audio capture started")
        // Simulate listening for 2 seconds, then deliver a "buffer"
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            logger.info("Audio buffer captured")
            onChunk(Data())
        }
    }

    func stopCapture() {
        logger.info("Audio capture stopped")
        timer?.invalidate()
        timer = nil
    }
}

struct StubTranscriptionService: TranscriptionService {
    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        logger.info("Transcribing audio buffer (\(request.audioData.count) bytes, live: \(request.isLive))...")
        // Simulate transcription taking 1.5 seconds
        try await Task.sleep(for: .milliseconds(1500))
        let transcript = "This is a stub transcript from Talkie Live."
        logger.info("Transcription complete: \(transcript)")
        return Transcript(text: transcript, confidence: 0.95)
    }
}

// MARK: - Engine Transcription Service

/// TranscriptionService that uses TalkieEngine via XPC
/// NO FALLBACK - requires Engine to be running
struct EngineTranscriptionService: TranscriptionService {
    private let modelId: String

    init(modelId: String = "openai_whisper-small") {
        self.modelId = modelId
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        let client = await EngineClient.shared

        // Connect to Engine - NO FALLBACK
        let connected = await client.ensureConnected()

        guard connected else {
            logger.error("═══════════════════════════════════════════════════════════")
            logger.error("  ❌ TALKIE ENGINE NOT RUNNING")
            logger.error("  TalkieLive requires TalkieEngine to be running.")
            logger.error("  Please ensure the Engine is installed and started.")
            logger.error("═══════════════════════════════════════════════════════════")
            throw EngineTranscriptionError.engineNotRunning
        }

        logger.notice("═══════════════════════════════════════════════════════════")
        logger.notice("  🎙️ TRANSCRIBING VIA TALKIE ENGINE (XPC)")
        logger.notice("  Model: \(self.modelId)")
        logger.notice("  Audio: \(request.audioData.count) bytes")
        logger.notice("═══════════════════════════════════════════════════════════")

        let startTime = Date()
        let text = try await client.transcribe(audioData: request.audioData, modelId: modelId)
        let elapsed = Date().timeIntervalSince(startTime)

        logger.notice("═══════════════════════════════════════════════════════════")
        logger.notice("  ✅ ENGINE TRANSCRIPTION COMPLETE")
        logger.notice("  Time: \(String(format: "%.2f", elapsed))s")
        logger.notice("  Result: \(text.prefix(80))...")
        logger.notice("═══════════════════════════════════════════════════════════")

        return Transcript(text: text, confidence: nil)
    }
}

enum EngineTranscriptionError: LocalizedError {
    case engineNotRunning

    var errorDescription: String? {
        switch self {
        case .engineNotRunning:
            return "Talkie Engine is not running. Please start the Engine service."
        }
    }
}

struct LoggingRouter: LiveRouter {
    func handle(transcript: String) async {
        logger.info("Routing transcript...")
        // Simulate routing taking 0.5 seconds
        try? await Task.sleep(for: .milliseconds(500))
        logger.info("Transcript routed: \(transcript)")
    }
}
