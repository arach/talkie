import Foundation
import os.log
import TalkieCore
import TalkieServices

private let logger = Logger(subsystem: "live.talkie", category: "Dependencies")

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
/// Falls back to local WhisperService if Engine is unavailable
struct EngineTranscriptionService: TranscriptionService {
    private let modelId: String

    init(modelId: String = "openai_whisper-small") {
        self.modelId = modelId
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        let client = await EngineClient.shared

        // Try to connect to engine
        let connected = await client.ensureConnected()

        if connected {
            logger.info("Using TalkieEngine for transcription")
            do {
                let text = try await client.transcribe(audioData: request.audioData, modelId: modelId)
                return Transcript(text: text, confidence: nil)
            } catch {
                logger.warning("Engine transcription failed, falling back to local: \(error.localizedDescription)")
                // Fall through to local transcription
            }
        } else {
            logger.info("TalkieEngine not available, using local transcription")
        }

        // Fallback to local WhisperService
        return try await fallbackToLocal(request)
    }

    private func fallbackToLocal(_ request: TranscriptionRequest) async throws -> Transcript {
        // Use local WhisperService as fallback
        let whisperService = WhisperTranscriptionService(model: .small)
        return try await whisperService.transcribe(request)
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
