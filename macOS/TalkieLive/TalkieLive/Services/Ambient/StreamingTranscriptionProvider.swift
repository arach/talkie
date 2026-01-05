//
//  StreamingTranscriptionProvider.swift
//  TalkieLive
//
//  Streaming transcription provider for ambient mode.
//  Uses EngineClient's streaming ASR methods for low-latency wake phrase detection.
//

import Foundation
import TalkieKit

private let log = Log(.system)

// MARK: - Streaming Transcription Provider

/// Provider that uses streaming ASR for real-time wake phrase detection
/// Uses EngineClient streaming methods (XPC → TalkieEngine → streaming-asr pod)
@MainActor
final class StreamingTranscriptionProvider: AmbientTranscriptionProvider {
    // MARK: - Dependencies

    private let engine: EngineClient

    // MARK: - State

    private var state: AmbientProviderState = .idle
    private var config: AmbientTranscriptionConfig?
    private var phraseDetector: PhraseDetector?

    /// Active streaming session ID
    private var sessionId: String?

    /// Accumulated command text during command mode
    private var commandText: String = ""

    /// When wake phrase was detected
    private var wakeTimestamp: Date?

    // MARK: - Event Stream

    private var eventContinuation: AsyncStream<AmbientTranscriptionEvent>.Continuation?

    var events: AsyncStream<AmbientTranscriptionEvent> {
        AsyncStream { [weak self] continuation in
            self?.eventContinuation = continuation

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.eventContinuation = nil
                }
            }
        }
    }

    // MARK: - Init

    init(engine: EngineClient = .shared) {
        self.engine = engine
    }

    // MARK: - Provider Protocol

    func start(config: AmbientTranscriptionConfig) async throws {
        guard state == .idle else {
            log.warning("[StreamASR] ⚠️ Already started")
            return
        }

        log.info("[StreamASR] 🚀 Starting streaming provider...")
        log.info("[StreamASR] Wake phrase: '\(config.wakePhrase)'")

        self.config = config
        self.phraseDetector = PhraseDetector(config: config)
        self.state = .starting
        self.commandText = ""
        self.wakeTimestamp = nil
        self.audioChunkCount = 0

        // Ensure engine is connected
        log.info("[StreamASR] Connecting to TalkieEngine...")
        let connected = await engine.ensureConnected()
        if !connected {
            let error = "Failed to connect to TalkieEngine"
            log.error("[StreamASR] ❌ \(error)")
            emit(.error(message: error, isFatal: true))
            state = .error(error)
            return
        }
        log.info("[StreamASR] ✓ Engine connected")

        // Start streaming ASR session
        log.info("[StreamASR] Starting streaming ASR session via XPC...")
        do {
            let sid = try await engine.startStreamingASR()
            sessionId = sid
            state = .listening

            log.info("[StreamASR] ✅ Session ready!", detail: "id=\(sid.prefix(8))")

            // Get memory usage (pod loads ~200MB)
            emit(.ready(memoryMB: 200))

        } catch {
            let errorMsg = error.localizedDescription
            log.error("[StreamASR] ❌ Failed to start session", error: error)
            emit(.error(message: errorMsg, isFatal: true))
            state = .error(errorMsg)
        }
    }

    func stop() async {
        guard state != .idle else { return }

        log.info("Stopping StreamingTranscriptionProvider")

        state = .stopping

        // Stop streaming session if active
        if let sid = sessionId {
            do {
                let finalTranscript = try await engine.stopStreamingASR(sessionId: sid)
                if !finalTranscript.isEmpty {
                    log.info("Final transcript from session", detail: "\(finalTranscript.prefix(50))...")
                }
            } catch {
                log.warning("Error stopping streaming ASR", error: error)
            }
        }

        sessionId = nil
        commandText = ""
        wakeTimestamp = nil
        config = nil
        phraseDetector = nil

        state = .idle
        eventContinuation?.finish()
    }

    /// Counter for audio chunks ingested (for logging)
    private var audioChunkCount: Int = 0

    func ingest(_ input: AmbientAudioInput) async {
        guard state == .listening || state.isCommandMode else {
            if audioChunkCount % 100 == 0 {
                log.debug("[StreamASR] Ignoring audio in state: \(state)")
            }
            return
        }

        guard let sid = sessionId else {
            log.warning("[StreamASR] No active session - dropping audio")
            return
        }

        switch input {
        case .pcm16kFloat(let data):
            audioChunkCount += 1
            // Log every 50 chunks (~5 seconds at 100ms chunks)
            if audioChunkCount % 50 == 0 {
                log.debug("[StreamASR] Feeding audio chunk #\(audioChunkCount)", detail: "\(data.count) bytes")
            }
            await feedAudio(sessionId: sid, data: data)

        case .chunk:
            // Streaming provider doesn't use file chunks
            log.warning("[StreamASR] Chunk input not supported - use pcm16kFloat")
        }
    }

    // MARK: - Audio Feeding

    /// Feed audio data to the streaming session
    private func feedAudio(sessionId: String, data: Data) async {
        do {
            let events = try await engine.feedStreamingASR(sessionId: sessionId, audio: data)

            // Process any returned events
            if let events = events {
                for event in events {
                    handleStreamingEvent(event)
                }
            }

        } catch {
            log.warning("Streaming ASR feed error", error: error)
            emit(.error(message: error.localizedDescription, isFatal: false))
        }
    }

    // MARK: - Event Processing

    /// Handle events from the streaming ASR pod
    private func handleStreamingEvent(_ event: StreamingASREvent) {
        switch event.type {
        case "transcript":
            guard let text = event.text, !text.isEmpty else { return }

            let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedText.isEmpty else { return }

            let isFinal = event.isFinal ?? false
            let confidence = event.confidence

            // Log all transcripts for debugging
            log.info("[StreamASR] 📝 Transcript", detail: "[\(isFinal ? "FINAL" : "hypo")] \"\(cleanedText)\"")

            emit(.transcript(text: cleanedText, confidence: confidence, isFinal: isFinal))

            // For wake detection, use hypothesis transcripts (faster)
            // For command capture, prefer final transcripts (more accurate)
            switch state {
            case .listening:
                // Use any transcript for wake detection (speed > accuracy)
                log.debug("[StreamASR] Checking for wake phrase in: \"\(cleanedText)\"")
                processTranscriptForWake(cleanedText)

            case .command:
                // Accumulate only FINAL transcripts for clean command text
                if isFinal {
                    accumulateCommand(cleanedText)
                }

                // But check ALL transcripts for end/cancel phrases
                // (user intent to stop should be detected ASAP, even on hypothesis)
                checkTranscriptForEndOrCancel(cleanedText, isFinal: isFinal)

            default:
                break
            }

        case "speechStart":
            log.debug("[StreamASR] 🎤 Speech started")
            emit(.speechStart)

        case "speechEnd":
            let duration = event.silenceDuration
            log.debug("[StreamASR] 🔇 Speech ended", detail: duration.map { "\($0)s silence" } ?? "")
            emit(.speechEnd(silenceDuration: duration))

        case "error":
            let message = event.message ?? "Unknown error"
            let isFatal = event.isFatal ?? false
            log.warning("[StreamASR] ❌ Error", detail: "\(message) (fatal=\(isFatal))")
            emit(.error(message: message, isFatal: isFatal))

        default:
            log.debug("[StreamASR] Unknown event type", detail: event.type)
        }
    }

    // MARK: - Phrase Detection

    /// Process transcript for wake phrase detection (uses hypothesis)
    private func processTranscriptForWake(_ text: String) {
        guard let detector = phraseDetector else { return }

        guard let match = detector.containsWakePhrase(in: text) else { return }

        log.info("Wake phrase detected!", detail: "'\(config?.wakePhrase ?? "")'")

        // Transition to command mode
        wakeTimestamp = Date()
        commandText = ""
        state = .command(startTime: Date())

        // Extract any text after the wake phrase as start of command
        let afterWake = match.textAfter
        if !afterWake.isEmpty {
            commandText = afterWake
        }

        emit(.wakeDetected(phrase: config?.wakePhrase ?? "", afterText: afterWake))
    }

    /// Accumulate text during command mode (uses final transcripts)
    private func accumulateCommand(_ text: String) {
        if !commandText.isEmpty {
            commandText += " "
        }
        commandText += text
    }

    /// Check for end phrase or cancel phrase in a single transcript
    /// This runs on BOTH hypothesis and final transcripts to catch user intent ASAP
    private func checkTranscriptForEndOrCancel(_ text: String, isFinal: Bool) {
        guard let detector = phraseDetector else { return }

        // Check for cancel first (in the current transcript)
        if detector.containsCancelPhrase(in: text) != nil {
            log.info("Cancel phrase detected", detail: "'\(config?.cancelPhrase ?? "")' (isFinal=\(isFinal))")
            handleCancel()
            return
        }

        // Check for end phrase (in the current transcript)
        if detector.containsEndPhrase(in: text) != nil {
            log.info("End phrase detected", detail: "'\(config?.endPhrase ?? "")' (isFinal=\(isFinal))")

            // Use accumulated command text (from FINAL transcripts only)
            // If detecting from hypothesis, the command is whatever we've accumulated so far
            let finalCommand = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
            handleEnd(command: finalCommand)
        }
    }

    // MARK: - State Transitions

    /// Handle cancel phrase detection
    private func handleCancel() {
        log.info("Command cancelled")

        commandText = ""
        wakeTimestamp = nil
        state = .listening

        emit(.cancelDetected)
    }

    /// Handle end phrase detection
    private func handleEnd(command: String) {
        guard !command.isEmpty else {
            log.warning("Empty command captured, returning to listening")
            commandText = ""
            wakeTimestamp = nil
            state = .listening
            return
        }

        let duration = wakeTimestamp.map { Date().timeIntervalSince($0) } ?? 0
        log.info("Command captured", detail: "'\(command)' (\(String(format: "%.1f", duration))s)")

        emit(.endDetected(command: command))

        // Reset to listening
        commandText = ""
        wakeTimestamp = nil
        state = .listening
    }

    // MARK: - Helpers

    /// Emit an event to the stream
    private func emit(_ event: AmbientTranscriptionEvent) {
        eventContinuation?.yield(event)
    }
}

// MARK: - State Extension

private extension AmbientProviderState {
    var isCommandMode: Bool {
        if case .command = self {
            return true
        }
        return false
    }
}
