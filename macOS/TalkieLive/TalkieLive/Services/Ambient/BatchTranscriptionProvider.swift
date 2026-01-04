//
//  BatchTranscriptionProvider.swift
//  TalkieLive
//
//  Batch transcription provider for ambient mode.
//  Uses existing EngineClient.transcribe() for file-based transcription.
//

import Foundation
import TalkieKit

private let log = Log(.system)

// MARK: - Batch Transcription Provider

/// Provider that uses batch (file-based) transcription for ambient mode
/// Wraps existing EngineClient.transcribe() and performs phrase detection on results
@MainActor
final class BatchTranscriptionProvider: AmbientTranscriptionProvider {
    // MARK: - Dependencies

    private let engine: EngineClient
    private let settings: LiveSettings

    // MARK: - State

    private var state: AmbientProviderState = .idle
    private var config: AmbientTranscriptionConfig?
    private var phraseDetector: PhraseDetector?

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

    init(
        engine: EngineClient = .shared,
        settings: LiveSettings = .shared
    ) {
        self.engine = engine
        self.settings = settings
    }

    // MARK: - Provider Protocol

    func start(config: AmbientTranscriptionConfig) async throws {
        guard state == .idle else {
            log.warning("[BatchASR] ⚠️ Already started")
            return
        }

        log.info("[BatchASR] 🚀 Starting batch provider (context buffer)...")

        self.config = config
        self.phraseDetector = PhraseDetector(config: config)
        self.state = .listening
        self.commandText = ""
        self.wakeTimestamp = nil

        // Ensure engine is connected
        log.info("[BatchASR] Connecting to TalkieEngine...")
        let connected = await engine.ensureConnected()
        if !connected {
            let error = "Failed to connect to TalkieEngine"
            log.error("[BatchASR] ❌ \(error)")
            emit(.error(message: error, isFatal: true))
            state = .error(error)
            return
        }
        log.info("[BatchASR] ✓ Engine connected")

        // Get memory usage from status if available
        let memoryMB = engine.status?.memoryUsageMB

        emit(.ready(memoryMB: memoryMB))
        log.info("[BatchASR] ✅ Ready!", detail: "model=\(settings.selectedModelId)")
    }

    func stop() async {
        guard state != .idle else { return }

        log.info("[BatchASR] Stopping batch provider")

        state = .stopping
        commandText = ""
        wakeTimestamp = nil
        config = nil
        phraseDetector = nil

        state = .idle
        eventContinuation?.finish()
    }

    func ingest(_ input: AmbientAudioInput) async {
        guard state == .listening || state.isCommandMode else {
            log.debug("[BatchASR] Ignoring audio in state: \(state)")
            return
        }

        switch input {
        case .chunk(let chunk):
            await transcribeChunk(chunk)

        case .pcm16kFloat:
            // Batch provider doesn't support streaming PCM
            log.warning("[BatchASR] Chunk input expected - pcm16kFloat not supported")
        }
    }

    // MARK: - Transcription

    /// Transcribe an audio chunk using the engine
    private func transcribeChunk(_ chunk: AudioChunk) async {
        let fileName = chunk.fileURL.lastPathComponent
        log.debug("[BatchASR] 📤 Transcribing chunk", detail: fileName)

        do {
            let transcript = try await engine.transcribe(
                audioPath: chunk.fileURL.path,
                modelId: settings.selectedModelId,
                priority: .low,  // Lower priority than user-initiated recordings
                postProcess: .none
            )

            let cleanedText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedText.isEmpty else {
                log.debug("[BatchASR] (empty transcript)", detail: fileName)
                return
            }

            log.info("[BatchASR] 📝 Transcript", detail: "[\(formatDuration(chunk.duration))] \"\(cleanedText)\"")

            // Emit transcript event
            emit(.transcript(text: cleanedText, confidence: nil, isFinal: true))

            // Process based on current state
            processTranscript(cleanedText)

        } catch {
            log.warning("[BatchASR] ❌ Transcription failed", error: error)
            emit(.error(message: error.localizedDescription, isFatal: false))
        }
    }

    // MARK: - Phrase Detection

    /// Process transcript for phrase detection
    private func processTranscript(_ text: String) {
        guard let detector = phraseDetector else { return }

        switch state {
        case .listening:
            checkForWakePhrase(text, detector: detector)

        case .command:
            accumulateCommand(text)
            checkForEndOrCancel(detector: detector)

        default:
            break
        }
    }

    /// Check if text contains the wake phrase
    private func checkForWakePhrase(_ text: String, detector: PhraseDetector) {
        log.debug("[BatchASR] Checking for wake phrase in: \"\(text)\"")
        guard let match = detector.containsWakePhrase(in: text) else { return }

        log.info("[BatchASR] 🎯 Wake phrase detected!", detail: "'\(config?.wakePhrase ?? "")'")

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

    /// Accumulate text during command mode
    private func accumulateCommand(_ text: String) {
        if !commandText.isEmpty {
            commandText += " "
        }
        commandText += text
    }

    /// Check for end phrase or cancel phrase in accumulated command
    private func checkForEndOrCancel(detector: PhraseDetector) {
        // Check for cancel first (in the full accumulated command)
        if detector.containsCancelPhrase(in: commandText) != nil {
            log.info("[BatchASR] Cancel phrase detected", detail: "'\(config?.cancelPhrase ?? "")'")
            handleCancel()
            return
        }

        // Check for end phrase
        if let endMatch = detector.containsEndPhrase(in: commandText) {
            log.info("[BatchASR] End phrase detected", detail: "'\(config?.endPhrase ?? "")'")

            // Extract command (text before end phrase)
            let finalCommand = endMatch.textBefore.trimmingCharacters(in: .whitespacesAndNewlines)
            handleEnd(command: finalCommand)
        }
    }

    // MARK: - State Transitions

    /// Handle cancel phrase detection
    private func handleCancel() {
        log.info("[BatchASR] Command cancelled")

        commandText = ""
        wakeTimestamp = nil
        state = .listening

        emit(.cancelDetected)
    }

    /// Handle end phrase detection
    private func handleEnd(command: String) {
        guard !command.isEmpty else {
            log.warning("[BatchASR] Empty command captured, returning to listening")
            commandText = ""
            wakeTimestamp = nil
            state = .listening
            return
        }

        let duration = wakeTimestamp.map { Date().timeIntervalSince($0) } ?? 0
        log.info("[BatchASR] ✅ Command captured", detail: "'\(command)' (\(String(format: "%.1f", duration))s)")

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

    /// Format duration for logging
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "%.1fs", duration)
        }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes)m \(seconds)s"
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
