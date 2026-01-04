//
//  StreamingASRCapability.swift
//  TalkieEnginePod
//
//  Streaming ASR capability for ambient mode.
//  Provides real-time transcription with low latency hypothesis updates.
//
//  Protocol:
//  - startStream: Begin streaming session
//  - audioChunk: Send base64-encoded Float32 16kHz audio
//  - stopStream: End session and get final transcript
//  - status: Get current state
//
//  Output events (emitted proactively via stdout):
//  - {"type":"transcript","text":"...","confidence":0.85,"isFinal":false}
//  - {"type":"speechStart"}
//  - {"type":"speechEnd","silenceDuration":1.2}
//  - {"type":"error","message":"...","isFatal":false}
//
//  NOTE: Phrase detection (wake/end/cancel) happens in the app, NOT here.
//

import Foundation
import FluidAudio
import AVFoundation

/// Streaming ASR capability for real-time transcription
final class StreamingASRCapability: PodCapability {
    static let name = "streaming-asr"
    static let description = "Real-time streaming speech recognition"
    static let supportedActions = ["startStream", "audioChunk", "stopStream", "status"]

    private var asrManager: StreamingAsrManager?
    private var activeStreamId: String?
    private var accumulatedTranscript: String = ""
    private var isStreaming = false
    private var lastSpeechTime: Date?
    private var isSpeaking = false
    private var updateListenerTask: Task<Void, Never>?

    /// Pre-loaded ASR models (cached to avoid 40s reload per session)
    private var cachedModels: AsrModels?

    /// Pending events to return with next audioChunk response
    private var pendingEvents: [[String: Any]] = []
    private let pendingEventsLock = NSLock()

    // Audio format: 16kHz mono Float32
    private let sampleRate: Double = 16000

    // Debug counter for audio chunks
    private var audioChunkCount: Int = 0

    init() {}

    // MARK: - PodCapability

    var isLoaded: Bool {
        asrManager != nil
    }

    var memoryUsageMB: Int {
        // Parakeet TDT model is ~150-200MB
        isLoaded ? 200 : 0
    }

    func load(config: PodConfig) async throws {
        guard !isLoaded else { return }

        // Pre-load ASR models ONCE during capability load
        // This takes ~40s but only happens once per pod spawn, not per session
        print(#"{"type":"log","message":"Loading Parakeet TDT models (one-time ~40s)..."}"#)
        fflush(stdout)

        let loadStart = Date()
        cachedModels = try await AsrModels.downloadAndLoad()
        let loadTime = Date().timeIntervalSince(loadStart)
        let loadTimeStr = String(format: "%.1f", loadTime)

        print(#"{"type":"log","message":"Models loaded in \#(loadTimeStr)s"}"#)
        fflush(stdout)

        // Create streaming ASR manager with low-latency config
        // Using the streaming preset optimized for quick hypothesis updates
        let streamConfig = StreamingAsrConfig(
            chunkSeconds: 3.0,            // Process every 3s for lower latency
            hypothesisChunkSeconds: 0.5,  // Quick hypothesis updates every 500ms
            leftContextSeconds: 1.0,      // 1s lookback
            rightContextSeconds: 1.0,     // 1s lookahead
            minContextForConfirmation: 3.0,
            confirmationThreshold: 0.75   // Slightly lower for faster confirmation
        )

        asrManager = StreamingAsrManager(config: streamConfig)
    }

    func handle(_ request: PodRequest) async throws -> PodResponse {
        switch request.action {
        case "startStream":
            return try await handleStartStream(request)

        case "audioChunk":
            return try await handleAudioChunk(request)

        case "stopStream":
            return try await handleStopStream(request)

        case "status":
            return handleStatus(request)

        default:
            return PodResponse.failure(
                id: request.id,
                error: "Unknown action: \(request.action). Supported: \(Self.supportedActions.joined(separator: ", "))"
            )
        }
    }

    func unload() async {
        if isStreaming {
            _ = try? await asrManager?.finish()
        }
        updateListenerTask?.cancel()
        updateListenerTask = nil
        asrManager = nil
        cachedModels = nil  // Release ~200MB of models
        activeStreamId = nil
        isStreaming = false
        accumulatedTranscript = ""
        isSpeaking = false
        lastSpeechTime = nil
    }

    // MARK: - Action Handlers

    private func handleStartStream(_ request: PodRequest) async throws -> PodResponse {
        guard var manager = asrManager else {
            return PodResponse.failure(id: request.id, error: "ASR not loaded")
        }

        guard let models = cachedModels else {
            return PodResponse.failure(id: request.id, error: "ASR models not loaded")
        }

        // End any existing stream
        if isStreaming {
            _ = try? await manager.finish()
            updateListenerTask?.cancel()
        }

        // Start new stream
        let streamId = UUID().uuidString

        do {
            // Start the ASR engine with PRE-LOADED models (instant, not 40s)
            // Even though we also feed audio via streamAudio(), the engine needs a source to initialize
            // Our fed audio goes into the inputBuilder alongside any mic input
            try await manager.start(models: models, source: .microphone)
        } catch {
            return PodResponse.failure(id: request.id, error: "Failed to start ASR: \(error.localizedDescription)")
        }

        activeStreamId = streamId
        isStreaming = true
        accumulatedTranscript = ""
        isSpeaking = false
        lastSpeechTime = nil

        // Start listening for transcript updates in background
        updateListenerTask = Task {
            await listenForUpdates(streamId: streamId, manager: manager)
        }

        return PodResponse.success(id: request.id, result: [
            "streamId": streamId,
            "status": "started"
        ])
    }

    private func handleAudioChunk(_ request: PodRequest) async throws -> PodResponse {
        guard let manager = asrManager else {
            return PodResponse.failure(id: request.id, error: "ASR not loaded")
        }

        guard isStreaming else {
            return PodResponse.failure(id: request.id, error: "No active stream. Call startStream first.")
        }

        // Decode base64 audio data
        guard let base64Audio = request.payload["audio"],
              let audioData = Data(base64Encoded: base64Audio) else {
            return PodResponse.failure(id: request.id, error: "Missing or invalid 'audio' (base64) in payload")
        }

        // Convert Data to Float32 samples
        let samples = audioData.withUnsafeBytes { ptr -> [Float] in
            let floatPtr = ptr.bindMemory(to: Float.self)
            return Array(floatPtr)
        }

        // Simple VAD: Check if audio has significant energy
        let rms = calculateRMS(samples)
        let speechThreshold: Float = 0.01  // Tunable threshold

        if rms > speechThreshold {
            if !isSpeaking {
                isSpeaking = true
                emitEvent(SpeechStartEvent())
            }
            lastSpeechTime = Date()
        } else if isSpeaking {
            // Check for silence duration
            if let lastTime = lastSpeechTime {
                let silenceDuration = Date().timeIntervalSince(lastTime)
                if silenceDuration > 0.8 {  // 800ms of silence = end of speech
                    isSpeaking = false
                    emitEvent(SpeechEndEvent(silenceDuration: silenceDuration))
                }
            }
        }

        // Convert Float32 samples to AVAudioPCMBuffer
        guard let pcmBuffer = createPCMBuffer(from: samples) else {
            return PodResponse.failure(id: request.id, error: "Failed to create audio buffer")
        }

        // Increment and log buffer details every 50 chunks
        audioChunkCount += 1
        if audioChunkCount % 50 == 0 {
            print("{\"type\":\"log\",\"message\":\"Audio chunk #\(audioChunkCount): \(samples.count) samples, buffer frames=\(pcmBuffer.frameLength), format=\(pcmBuffer.format.sampleRate)Hz\"}")
            fflush(stdout)
        }

        // Feed to ASR
        await manager.streamAudio(pcmBuffer)

        // Collect and return any pending events
        let events = drainPendingEvents()

        var result: [String: String] = [
            "status": "received",
            "samples": String(samples.count)
        ]

        if !events.isEmpty {
            // Encode events as JSON array string
            if let eventsData = try? JSONSerialization.data(withJSONObject: events),
               let eventsJSON = String(data: eventsData, encoding: .utf8) {
                result["events"] = eventsJSON
            }
        }

        return PodResponse.success(id: request.id, result: result)
    }

    /// Drain and return all pending events
    private func drainPendingEvents() -> [[String: Any]] {
        pendingEventsLock.lock()
        defer { pendingEventsLock.unlock() }
        let events = pendingEvents
        pendingEvents.removeAll()
        return events
    }

    /// Queue an event to be returned with next response
    private func queueEvent(_ event: [String: Any]) {
        pendingEventsLock.lock()
        defer { pendingEventsLock.unlock() }
        pendingEvents.append(event)
    }

    private func handleStopStream(_ request: PodRequest) async throws -> PodResponse {
        guard let manager = asrManager else {
            return PodResponse.failure(id: request.id, error: "ASR not loaded")
        }

        guard isStreaming else {
            return PodResponse.success(id: request.id, result: [
                "status": "no_stream",
                "transcript": ""
            ])
        }

        // Cancel update listener
        updateListenerTask?.cancel()
        updateListenerTask = nil

        // Finish stream and get final transcript
        let finalTranscript: String
        do {
            finalTranscript = try await manager.finish()
        } catch {
            finalTranscript = accumulatedTranscript
        }

        isStreaming = false
        activeStreamId = nil
        isSpeaking = false

        let result = finalTranscript.isEmpty ? accumulatedTranscript : finalTranscript
        accumulatedTranscript = ""

        return PodResponse.success(id: request.id, result: [
            "status": "stopped",
            "transcript": result
        ])
    }

    private func handleStatus(_ request: PodRequest) -> PodResponse {
        return PodResponse.success(id: request.id, result: [
            "loaded": String(isLoaded),
            "streaming": String(isStreaming),
            "streamId": activeStreamId ?? "",
            "memoryMB": String(memoryUsageMB),
            "isSpeaking": String(isSpeaking)
        ])
    }

    // MARK: - Audio Helpers

    /// Create an AVAudioPCMBuffer from Float32 samples at 16kHz mono
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

    // MARK: - VAD Helper

    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }

    // MARK: - Transcript Updates

    /// Listen for streaming transcript updates and queue them as events
    private func listenForUpdates(streamId: String, manager: StreamingAsrManager) async {
        print("{\"type\":\"log\",\"message\":\"listenForUpdates started for stream \(streamId.prefix(8))\"}")
        fflush(stdout)

        var updateCount = 0
        for await update in await manager.transcriptionUpdates {
            updateCount += 1
            print("{\"type\":\"log\",\"message\":\"Got transcript update #\(updateCount): '\(update.text.prefix(30))'\"}")
            fflush(stdout)

            // Only process if still the active stream
            guard activeStreamId == streamId, isStreaming else { break }

            let text = update.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            // Queue transcript event (app handles phrase detection)
            queueEvent([
                "type": "transcript",
                "text": text,
                "confidence": Double(update.confidence),
                "isFinal": update.isConfirmed
            ])

            // Update accumulated transcript for final result
            if update.isConfirmed {
                if !accumulatedTranscript.isEmpty {
                    accumulatedTranscript += " "
                }
                accumulatedTranscript += text
            }
        }
    }

    /// Emit a VAD event (speech start/end) - queue for next response
    private func emitEvent(_ event: SpeechStartEvent) {
        queueEvent(["type": "speechStart"])
    }

    private func emitEvent(_ event: SpeechEndEvent) {
        queueEvent([
            "type": "speechEnd",
            "silenceDuration": event.silenceDuration
        ])
    }
}

// MARK: - Event Types

/// Transcript update event
struct TranscriptEvent: Codable {
    let type: String
    let text: String
    let confidence: Double
    let isFinal: Bool

    init(text: String, confidence: Double, isFinal: Bool) {
        self.type = "transcript"
        self.text = text
        self.confidence = confidence
        self.isFinal = isFinal
    }
}

/// Speech started event
struct SpeechStartEvent: Codable {
    let type: String

    init() {
        self.type = "speechStart"
    }
}

/// Speech ended event
struct SpeechEndEvent: Codable {
    let type: String
    let silenceDuration: TimeInterval

    init(silenceDuration: TimeInterval) {
        self.type = "speechEnd"
        self.silenceDuration = silenceDuration
    }
}

/// Error event
struct ASRErrorEvent: Codable {
    let type: String
    let message: String
    let isFatal: Bool

    init(message: String, isFatal: Bool) {
        self.type = "error"
        self.message = message
        self.isFatal = isFatal
    }
}
