//
//  AmbientTranscriptionProvider.swift
//  TalkieLive
//
//  Protocol and types for ambient transcription providers.
//  Abstracts batch vs streaming transcription for wake phrase detection.
//

import Foundation

// MARK: - Configuration

/// Configuration for ambient transcription
struct AmbientTranscriptionConfig: Sendable {
    let wakePhrase: String
    let endPhrase: String
    let cancelPhrase: String
    let locale: Locale

    init(
        wakePhrase: String = "hey talkie",
        endPhrase: String = "that's it",
        cancelPhrase: String = "never mind",
        locale: Locale = .current
    ) {
        self.wakePhrase = wakePhrase
        self.endPhrase = endPhrase
        self.cancelPhrase = cancelPhrase
        self.locale = locale
    }
}

// MARK: - Audio Input Types

/// Audio input for transcription providers
enum AmbientAudioInput: Sendable {
    /// File-based path (M4A chunks from AmbientAudioCapture)
    case chunk(AudioChunk)

    /// Streaming path (16kHz Float32 PCM data)
    case pcm16kFloat(Data)
}

// MARK: - Transcription Events

/// Events emitted by transcription providers
enum AmbientTranscriptionEvent: Sendable, Equatable {
    /// Provider is ready to process audio
    case ready(memoryMB: Int?)

    /// Speech activity detected (VAD)
    case speechStart

    /// Speech ended with silence duration
    case speechEnd(silenceDuration: TimeInterval?)

    /// Transcript available (partial or final)
    case transcript(text: String, confidence: Double?, isFinal: Bool)

    /// Wake phrase detected with text after the phrase
    case wakeDetected(phrase: String, afterText: String)

    /// End phrase detected (command should be processed)
    case endDetected(command: String)

    /// Cancel phrase detected (command should be discarded)
    case cancelDetected

    /// Error occurred
    case error(message: String, isFatal: Bool)

    // MARK: - Equatable

    static func == (lhs: AmbientTranscriptionEvent, rhs: AmbientTranscriptionEvent) -> Bool {
        switch (lhs, rhs) {
        case let (.ready(lMem), .ready(rMem)):
            return lMem == rMem
        case (.speechStart, .speechStart):
            return true
        case let (.speechEnd(lDur), .speechEnd(rDur)):
            return lDur == rDur
        case let (.transcript(lText, lConf, lFinal), .transcript(rText, rConf, rFinal)):
            return lText == rText && lConf == rConf && lFinal == rFinal
        case let (.wakeDetected(lPhrase, lAfter), .wakeDetected(rPhrase, rAfter)):
            return lPhrase == lPhrase && lAfter == rAfter
        case let (.endDetected(lCmd), .endDetected(rCmd)):
            return lCmd == rCmd
        case (.cancelDetected, .cancelDetected):
            return true
        case let (.error(lMsg, lFatal), .error(rMsg, rFatal)):
            return lMsg == rMsg && lFatal == rFatal
        default:
            return false
        }
    }
}

// MARK: - Provider Protocol

/// Protocol for ambient transcription providers
/// Implementations can use batch (file-based) or streaming transcription
@MainActor
protocol AmbientTranscriptionProvider: AnyObject {
    /// Stream of transcription events
    var events: AsyncStream<AmbientTranscriptionEvent> { get }

    /// Start the provider with configuration
    func start(config: AmbientTranscriptionConfig) async throws

    /// Stop the provider
    func stop() async

    /// Ingest audio for transcription
    func ingest(_ input: AmbientAudioInput) async
}

// MARK: - Provider State

/// Internal state for providers
enum AmbientProviderState: Equatable {
    case idle
    case starting
    case listening
    case command(startTime: Date)
    case stopping
    case error(String)
}
