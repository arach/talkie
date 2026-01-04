//
//  StreamingASRService.swift
//  TalkieEngine
//
//  Streaming ASR service using subprocess isolation.
//  Streaming ASR runs in TalkieEnginePod process for real-time transcription.
//

import Foundation
import TalkieKit

/// Streaming ASR service (subprocess-based)
/// Manages streaming speech recognition sessions via the streaming-asr pod capability.
@MainActor
final class StreamingASRService {
    static let shared = StreamingASRService()

    // MARK: - State

    private var isPodSpawned = false
    private var isSpawning = false
    private var activeSessionId: String?
    private var pendingEvents: [StreamingASREvent] = []

    private init() {
        AppLogger.shared.info(.system, "StreamingASRService initialized (subprocess mode)")
    }

    // MARK: - Session Management

    /// Start a new streaming ASR session
    /// - Returns: Session ID (UUID string)
    func startSession() async throws -> String {
        // Ensure pod is spawned
        if !isPodSpawned {
            try await spawnPod()
        }

        AppLogger.shared.info(.system, "Starting streaming ASR session...")
        EngineStatusManager.shared.log(.info, "StreamASR", "Starting session...")

        let startTime = Date()

        // Send startStream request to pod
        let response = try await PodManager.shared.request(
            capability: "streaming-asr",
            action: "startStream",
            payload: [:]
        )

        guard response.success,
              let result = response.result,
              let sessionId = result["streamId"] else {
            let errorMsg = response.error ?? "Unknown error"
            AppLogger.shared.error(.system, "Failed to start streaming ASR", detail: errorMsg)
            EngineStatusManager.shared.log(.error, "StreamASR", "Start failed: \(errorMsg)")
            throw StreamingASRError.startFailed(errorMsg)
        }

        activeSessionId = sessionId
        pendingEvents = []

        let elapsed = Date().timeIntervalSince(startTime)
        AppLogger.shared.info(.system, "Streaming ASR session started", detail: "ID: \(sessionId), \(String(format: "%.2f", elapsed))s")
        EngineStatusManager.shared.log(.info, "StreamASR", "Session started: \(sessionId.prefix(8))...")

        return sessionId
    }

    /// Feed audio data to the active session
    /// - Parameters:
    ///   - sessionId: Session ID from startSession
    ///   - audioData: Raw Float32 16kHz mono audio samples (will be base64 encoded)
    /// - Returns: JSON-encoded array of transcript events
    func feedAudio(sessionId: String, audioData: Data) async throws -> Data? {
        guard sessionId == activeSessionId else {
            throw StreamingASRError.invalidSession("Session ID mismatch")
        }

        guard isPodSpawned else {
            throw StreamingASRError.notRunning
        }

        // Base64 encode the audio data
        let base64Audio = audioData.base64EncodedString()

        // Send audioChunk request to pod
        let response = try await PodManager.shared.request(
            capability: "streaming-asr",
            action: "audioChunk",
            payload: ["audio": base64Audio]
        )

        guard response.success else {
            let errorMsg = response.error ?? "Unknown error"
            AppLogger.shared.warning(.system, "Streaming ASR feed error", detail: errorMsg)
            throw StreamingASRError.feedFailed(errorMsg)
        }

        // Check if pod returned any events
        if let result = response.result,
           let eventsJSON = result["events"],
           !eventsJSON.isEmpty {
            // Return the events JSON as Data for XPC transport
            return eventsJSON.data(using: .utf8)
        }

        return nil
    }

    /// Stop the streaming session and get final transcript
    /// - Parameter sessionId: Session ID from startSession
    /// - Returns: Final transcript
    func stopSession(sessionId: String) async throws -> String {
        guard sessionId == activeSessionId else {
            throw StreamingASRError.invalidSession("Session ID mismatch")
        }

        guard isPodSpawned else {
            throw StreamingASRError.notRunning
        }

        AppLogger.shared.info(.system, "Stopping streaming ASR session...", detail: sessionId.prefix(8).description)
        EngineStatusManager.shared.log(.info, "StreamASR", "Stopping session...")

        let startTime = Date()

        // Send stopStream request to pod
        let response = try await PodManager.shared.request(
            capability: "streaming-asr",
            action: "stopStream",
            payload: [:]
        )

        activeSessionId = nil
        pendingEvents = []

        guard response.success,
              let result = response.result,
              let transcript = result["transcript"] else {
            let errorMsg = response.error ?? "Unknown error"
            AppLogger.shared.error(.system, "Failed to stop streaming ASR", detail: errorMsg)
            EngineStatusManager.shared.log(.error, "StreamASR", "Stop failed: \(errorMsg)")
            throw StreamingASRError.stopFailed(errorMsg)
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let wordCount = transcript.split(separator: " ").count
        AppLogger.shared.info(.system, "Streaming ASR session stopped", detail: "\(wordCount) words, \(String(format: "%.2f", elapsed))s")
        EngineStatusManager.shared.log(.info, "StreamASR", "Session stopped: \(wordCount) words")

        return transcript
    }

    // MARK: - Pod Management

    private func spawnPod() async throws {
        guard !isSpawning else {
            // Wait for current spawn to complete
            while isSpawning {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            return
        }

        guard !isPodSpawned else { return }

        isSpawning = true
        defer { isSpawning = false }

        AppLogger.shared.info(.system, "Spawning streaming ASR pod...")
        EngineStatusManager.shared.log(.info, "StreamASR", "Spawning subprocess...")

        let startTime = Date()

        do {
            _ = try await PodManager.shared.spawn(capability: "streaming-asr")
            isPodSpawned = true

            let elapsed = Date().timeIntervalSince(startTime)
            AppLogger.shared.info(.system, "Streaming ASR pod ready", detail: "\(String(format: "%.1f", elapsed))s")
            EngineStatusManager.shared.log(.info, "StreamASR", "Subprocess ready in \(String(format: "%.1f", elapsed))s")

        } catch {
            AppLogger.shared.error(.system, "Failed to spawn streaming ASR pod", detail: error.localizedDescription)
            EngineStatusManager.shared.log(.error, "StreamASR", "Pod spawn failed: \(error.localizedDescription)")
            throw StreamingASRError.spawnFailed(error)
        }
    }

    /// Unload the streaming ASR pod to reclaim memory
    func unload() {
        guard isPodSpawned else { return }

        AppLogger.shared.info(.system, "Killing streaming ASR pod to reclaim memory...")
        EngineStatusManager.shared.log(.info, "StreamASR", "Killing subprocess...")

        Task {
            await PodManager.shared.kill(capability: "streaming-asr")
        }

        isPodSpawned = false
        activeSessionId = nil
        pendingEvents = []

        AppLogger.shared.info(.system, "Streaming ASR pod killed, memory reclaimed")
        EngineStatusManager.shared.log(.info, "StreamASR", "Subprocess killed, memory reclaimed")
    }

    /// Check if streaming ASR pod is running
    var isLoaded: Bool {
        isPodSpawned
    }

    /// Check if there's an active session
    var hasActiveSession: Bool {
        activeSessionId != nil
    }

    /// Get the current active session ID (if any)
    var currentSessionId: String? {
        activeSessionId
    }
}

// MARK: - Streaming ASR Errors

enum StreamingASRError: LocalizedError {
    case spawnFailed(Error)
    case startFailed(String)
    case feedFailed(String)
    case stopFailed(String)
    case invalidSession(String)
    case notRunning

    var errorDescription: String? {
        switch self {
        case .spawnFailed(let error):
            return "Failed to spawn streaming ASR pod: \(error.localizedDescription)"
        case .startFailed(let message):
            return "Failed to start streaming ASR: \(message)"
        case .feedFailed(let message):
            return "Failed to feed audio: \(message)"
        case .stopFailed(let message):
            return "Failed to stop streaming ASR: \(message)"
        case .invalidSession(let message):
            return "Invalid session: \(message)"
        case .notRunning:
            return "Streaming ASR pod is not running"
        }
    }
}

// MARK: - Streaming ASR Event Types

/// Event emitted by streaming ASR (matches pod output format)
struct StreamingASREvent: Codable {
    let type: String
    let text: String?
    let confidence: Double?
    let isFinal: Bool?
    let silenceDuration: Double?
    let message: String?
    let isFatal: Bool?
}
