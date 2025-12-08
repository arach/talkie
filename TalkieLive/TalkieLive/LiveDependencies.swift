import Foundation
import os.log
import TalkieCore

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

struct LoggingRouter: LiveRouter {
    func handle(transcript: String) async {
        logger.info("Routing transcript...")
        // Simulate routing taking 0.5 seconds
        try? await Task.sleep(for: .milliseconds(500))
        logger.info("Transcript routed: \(transcript)")
    }
}
