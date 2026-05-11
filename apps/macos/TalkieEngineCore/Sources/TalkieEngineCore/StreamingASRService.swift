//
//  StreamingASRService.swift
//  TalkieEngineCore
//
//  In-process streaming ASR powered directly by FluidAudio.
//

import AVFoundation
import FluidAudio
import Foundation
import TalkieKit

@MainActor
final class StreamingASRService {
    static let shared = StreamingASRService()

    private var cachedModels: AsrModels?
    private var streamingManager: SlidingWindowAsrManager?
    private var activeSessionId: String?
    private var accumulatedTranscript: String = ""
    private var pendingEvents: [StreamingASREvent] = []
    private var updateListenerTask: Task<Void, Never>?
    private var isSpeaking = false
    private var lastSpeechTime: Date?
    private var audioChunkCount = 0

    private let sampleRate: Double = 16_000
    private let streamConfig = SlidingWindowAsrConfig(
        chunkSeconds: 3.0,
        hypothesisChunkSeconds: 0.5,
        leftContextSeconds: 1.0,
        rightContextSeconds: 1.0,
        minContextForConfirmation: 3.0,
        confirmationThreshold: 0.75
    )

    private init() {
        AppLogger.shared.info(.system, "StreamingASRService initialized (in-process)")
    }

    func startSession() async throws -> String {
        let models = try await ensureModelsLoaded()

        if let currentManager = streamingManager {
            await currentManager.cancel()
            updateListenerTask?.cancel()
        }

        let sessionId = UUID().uuidString
        let manager = SlidingWindowAsrManager(config: streamConfig)

        AppLogger.shared.info(.system, "Starting streaming ASR session...", detail: sessionId.prefix(8).description)
        EngineStatusManager.shared.log(.info, "StreamASR", "Starting in-process session...")

        do {
            try await manager.start(models: models, source: .microphone)
        } catch {
            AppLogger.shared.error(.system, "Failed to start streaming ASR", detail: error.localizedDescription)
            EngineStatusManager.shared.log(.error, "StreamASR", "Start failed: \(error.localizedDescription)")
            throw StreamingASRError.startFailed(error.localizedDescription)
        }

        streamingManager = manager
        activeSessionId = sessionId
        accumulatedTranscript = ""
        pendingEvents = []
        isSpeaking = false
        lastSpeechTime = nil
        audioChunkCount = 0

        updateListenerTask = Task { @MainActor [weak self] in
            await self?.listenForUpdates(streamId: sessionId, manager: manager)
        }

        AppLogger.shared.info(.system, "Streaming ASR session started", detail: sessionId.prefix(8).description)
        EngineStatusManager.shared.log(.info, "StreamASR", "Session started: \(sessionId.prefix(8))...")

        return sessionId
    }

    func feedAudio(sessionId: String, audioData: Data) async throws -> Data? {
        guard sessionId == activeSessionId else {
            throw StreamingASRError.invalidSession("Session ID mismatch")
        }

        guard let manager = streamingManager else {
            throw StreamingASRError.notRunning
        }

        let samples = audioData.withUnsafeBytes { ptr -> [Float] in
            Array(ptr.bindMemory(to: Float.self))
        }

        updateVoiceActivity(samples)

        guard let pcmBuffer = createPCMBuffer(from: samples) else {
            throw StreamingASRError.feedFailed("Failed to create PCM buffer")
        }

        audioChunkCount += 1
        if audioChunkCount % 100 == 0 {
            AppLogger.shared.info(.system, "Streaming ASR processed audio chunks", detail: "\(audioChunkCount)")
        }

        await manager.streamAudio(pcmBuffer)

        let events = drainPendingEvents()
        guard !events.isEmpty else { return nil }

        return try JSONEncoder().encode(events)
    }

    func stopSession(sessionId: String) async throws -> String {
        guard sessionId == activeSessionId else {
            throw StreamingASRError.invalidSession("Session ID mismatch")
        }

        guard let manager = streamingManager else {
            throw StreamingASRError.notRunning
        }

        AppLogger.shared.info(.system, "Stopping streaming ASR session...", detail: sessionId.prefix(8).description)
        EngineStatusManager.shared.log(.info, "StreamASR", "Stopping session...")

        updateListenerTask?.cancel()
        updateListenerTask = nil

        let finalTranscript: String
        do {
            finalTranscript = try await manager.finish()
        } catch {
            AppLogger.shared.warning(.system, "Streaming ASR finish failed; returning accumulated transcript", detail: error.localizedDescription)
            finalTranscript = accumulatedTranscript
        }

        streamingManager = nil
        activeSessionId = nil
        isSpeaking = false
        lastSpeechTime = nil
        pendingEvents = []

        let transcript = InverseTextNormalizer.normalize(
            finalTranscript.isEmpty ? accumulatedTranscript : finalTranscript
        )
        let wordCount = transcript.split(separator: " ").count
        accumulatedTranscript = ""

        AppLogger.shared.info(.system, "Streaming ASR session stopped", detail: "\(wordCount) words")
        EngineStatusManager.shared.log(.info, "StreamASR", "Session stopped: \(wordCount) words")

        return transcript
    }

    func unload() async {
        updateListenerTask?.cancel()
        updateListenerTask = nil

        if let manager = streamingManager {
            await manager.cancel()
        }

        streamingManager = nil
        cachedModels = nil
        activeSessionId = nil
        accumulatedTranscript = ""
        pendingEvents = []
        isSpeaking = false
        lastSpeechTime = nil
        audioChunkCount = 0
    }

    var isLoaded: Bool {
        cachedModels != nil
    }

    var hasActiveSession: Bool {
        activeSessionId != nil
    }

    var currentSessionId: String? {
        activeSessionId
    }

    private func ensureModelsLoaded() async throws -> AsrModels {
        if let cachedModels {
            return cachedModels
        }

        AppLogger.shared.info(.system, "Loading streaming ASR models in-process...")
        EngineStatusManager.shared.log(.info, "StreamASR", "Loading models...")

        do {
            let models = try await AsrModels.downloadAndLoad()
            cachedModels = models
            EngineStatusManager.shared.log(.info, "StreamASR", "Models loaded")
            return models
        } catch {
            AppLogger.shared.error(.system, "Failed to load streaming ASR models", detail: error.localizedDescription)
            EngineStatusManager.shared.log(.error, "StreamASR", "Model load failed: \(error.localizedDescription)")
            throw StreamingASRError.startFailed(error.localizedDescription)
        }
    }

    private func updateVoiceActivity(_ samples: [Float]) {
        let rms = calculateRMS(samples)
        let speechThreshold: Float = 0.01

        if rms > speechThreshold {
            if !isSpeaking {
                isSpeaking = true
                queueEvent(StreamingASREvent(type: "speechStart"))
            }
            lastSpeechTime = Date()
            return
        }

        guard isSpeaking, let lastSpeechTime else { return }

        let silenceDuration = Date().timeIntervalSince(lastSpeechTime)
        if silenceDuration > 0.8 {
            isSpeaking = false
            queueEvent(StreamingASREvent(type: "speechEnd", silenceDuration: silenceDuration))
        }
    }

    private func createPCMBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            return nil
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)

        guard let channelData = buffer.floatChannelData?[0] else {
            return nil
        }

        for (index, sample) in samples.enumerated() {
            channelData[index] = sample
        }

        return buffer
    }

    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(0) { $0 + ($1 * $1) }
        return sqrt(sumOfSquares / Float(samples.count))
    }

    private func queueEvent(_ event: StreamingASREvent) {
        pendingEvents.append(event)
    }

    private func drainPendingEvents() -> [StreamingASREvent] {
        let events = pendingEvents
        pendingEvents.removeAll()
        return events
    }

    private func listenForUpdates(streamId: String, manager: SlidingWindowAsrManager) async {
        for await update in await manager.transcriptionUpdates {
            guard activeSessionId == streamId else { break }

            let text = InverseTextNormalizer
                .normalize(update.text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            queueEvent(
                StreamingASREvent(
                    type: "transcript",
                    text: text,
                    confidence: Double(update.confidence),
                    isFinal: update.isConfirmed
                )
            )

            if update.isConfirmed {
                if !accumulatedTranscript.isEmpty {
                    accumulatedTranscript += " "
                }
                accumulatedTranscript += text
            }
        }
    }
}

enum StreamingASRError: LocalizedError {
    case startFailed(String)
    case feedFailed(String)
    case stopFailed(String)
    case invalidSession(String)
    case notRunning

    var errorDescription: String? {
        switch self {
        case .startFailed(let message):
            return "Failed to start streaming ASR: \(message)"
        case .feedFailed(let message):
            return "Failed to feed audio: \(message)"
        case .stopFailed(let message):
            return "Failed to stop streaming ASR: \(message)"
        case .invalidSession(let message):
            return "Invalid session: \(message)"
        case .notRunning:
            return "Streaming ASR is not running"
        }
    }
}
