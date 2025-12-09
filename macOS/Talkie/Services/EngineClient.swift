//
//  EngineClient.swift
//  Talkie
//
//  XPC client to connect to TalkieEngine for transcription
//

import Foundation
import os

private let logger = Logger(subsystem: "live.talkie.core", category: "Engine")

/// Mach service name for XPC connection (must match TalkieEngine)
private let kTalkieEngineServiceName = "live.talkie.engine.xpc"

/// XPC protocol for TalkieEngine (must match TalkieEngine's protocol)
@objc protocol TalkieEngineProtocol {
    func transcribe(
        audioData: Data,
        modelId: String,
        reply: @escaping (_ transcript: String?, _ error: String?) -> Void
    )

    func preloadModel(
        _ modelId: String,
        reply: @escaping (_ error: String?) -> Void
    )

    func unloadModel(reply: @escaping () -> Void)

    func getStatus(reply: @escaping (_ statusJSON: Data?) -> Void)

    func ping(reply: @escaping (_ pong: Bool) -> Void)
}

/// Engine status (matches TalkieEngine's EngineStatus)
public struct EngineStatus: Codable, Sendable {
    public let loadedModelId: String?
    public let isTranscribing: Bool
    public let isWarmingUp: Bool
    public let downloadedModels: [String]
}

/// Connection state for UI display
public enum EngineConnectionState: String {
    case disconnected = "Disconnected"
    case connecting = "Connecting..."
    case connected = "Connected"
    case error = "Error"
}

/// Client for communicating with TalkieEngine XPC service
@MainActor
public final class EngineClient: ObservableObject {
    public static let shared = EngineClient()

    // MARK: - Published State
    @Published public var connectionState: EngineConnectionState = .disconnected
    @Published public var status: EngineStatus?
    @Published public var lastError: String?

    // MARK: - Session Stats
    @Published public private(set) var connectedAt: Date?
    @Published public private(set) var transcriptionCount: Int = 0
    @Published public private(set) var lastTranscriptionAt: Date?

    /// Computed property for backwards compatibility
    public var isConnected: Bool { connectionState == .connected }

    private var connection: NSXPCConnection?
    private var engineProxy: TalkieEngineProtocol?

    private init() {
        logger.info("[Engine] Client initialized")
    }

    // MARK: - Connection Management

    /// Connect to TalkieEngine XPC service
    public func connect() {
        guard connection == nil else { return }

        connectionState = .connecting
        logger.info("[Engine] Connecting to XPC service: \(kTalkieEngineServiceName)")

        let conn = NSXPCConnection(machServiceName: kTalkieEngineServiceName)
        conn.remoteObjectInterface = NSXPCInterface(with: TalkieEngineProtocol.self)

        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                logger.warning("[Engine] XPC connection invalidated")
                self?.handleDisconnection(reason: "Connection invalidated")
            }
        }

        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                logger.warning("[Engine] XPC connection interrupted - will attempt to resume")
                self?.handleDisconnection(reason: "Connection interrupted")
            }
        }

        conn.resume()
        connection = conn

        // Test connection with ping
        Task {
            await testConnection()
        }
    }

    private func testConnection() async {
        guard let conn = connection else { return }

        let proxy = conn.remoteObjectProxyWithErrorHandler { error in
            Task { @MainActor in
                logger.error("[Engine] XPC proxy error: \(error.localizedDescription)")
                self.lastError = error.localizedDescription
                self.handleDisconnection(reason: error.localizedDescription)
            }
        } as? TalkieEngineProtocol

        guard let proxy = proxy else {
            logger.error("[Engine] Failed to create XPC proxy")
            handleDisconnection(reason: "Failed to create proxy")
            return
        }

        // Ping to verify connection
        proxy.ping { [weak self] pong in
            Task { @MainActor in
                if pong {
                    self?.connectionState = .connected
                    self?.connectedAt = Date()
                    self?.engineProxy = proxy
                    self?.lastError = nil
                    logger.info("[Engine] ✓ Connected to TalkieEngine")
                    self?.refreshStatus()
                } else {
                    logger.warning("[Engine] Ping failed - engine not responding")
                    self?.handleDisconnection(reason: "Ping failed")
                }
            }
        }
    }

    private func handleDisconnection(reason: String) {
        let wasConnected = connectionState == .connected
        connectionState = .disconnected
        engineProxy = nil
        connection?.invalidate()
        connection = nil
        status = nil

        if wasConnected {
            let sessionDuration = connectedAt.map { formatDuration(since: $0) } ?? "unknown"
            logger.info("[Engine] Disconnected after \(sessionDuration) (\(self.transcriptionCount) transcriptions)")
        }

        connectedAt = nil
    }

    /// Disconnect from TalkieEngine
    public func disconnect() {
        logger.info("[Engine] Disconnecting...")
        handleDisconnection(reason: "User requested disconnect")
    }

    /// Reconnect to the engine
    public func reconnect() {
        logger.info("[Engine] Reconnecting...")
        handleDisconnection(reason: "Reconnect requested")
        transcriptionCount = 0
        connect()
    }

    /// Ensure we're connected, attempting reconnection if needed
    public func ensureConnected() async -> Bool {
        if isConnected { return true }

        connect()

        // Wait briefly for connection
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if isConnected { return true }
        }

        return isConnected
    }

    private func formatDuration(since date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        return "\(hours)h \(minutes % 60)m"
    }

    // MARK: - Transcription

    /// Transcribe audio using TalkieEngine
    public func transcribe(audioData: Data, modelId: String = "openai_whisper-small") async throws -> String {
        guard let proxy = engineProxy else {
            // Try to connect first
            let connected = await ensureConnected()
            guard connected, let proxy = engineProxy else {
                throw EngineClientError.notConnected
            }
            return try await doTranscribe(proxy: proxy, audioData: audioData, modelId: modelId)
        }

        return try await doTranscribe(proxy: proxy, audioData: audioData, modelId: modelId)
    }

    private func doTranscribe(proxy: TalkieEngineProtocol, audioData: Data, modelId: String) async throws -> String {
        let audioSizeKB = audioData.count / 1024
        logger.info("[Engine] Transcribing \(audioSizeKB)KB audio with model '\(modelId)'")

        let startTime = Date()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.transcribe(audioData: audioData, modelId: modelId) { [weak self] transcript, error in
                Task { @MainActor in
                    let elapsed = Date().timeIntervalSince(startTime)

                    if let error = error {
                        logger.error("[Engine] Transcription failed after \(String(format: "%.1f", elapsed))s: \(error)")
                        continuation.resume(throwing: EngineClientError.transcriptionFailed(error))
                    } else if let transcript = transcript {
                        self?.transcriptionCount += 1
                        self?.lastTranscriptionAt = Date()
                        let wordCount = transcript.split(separator: " ").count
                        logger.info("[Engine] ✓ Transcription #\(self?.transcriptionCount ?? 0) completed in \(String(format: "%.1f", elapsed))s (\(wordCount) words)")
                        continuation.resume(returning: transcript)
                    } else {
                        logger.warning("[Engine] Empty response from engine")
                        continuation.resume(throwing: EngineClientError.emptyResponse)
                    }
                }
            }
        }
    }

    // MARK: - Model Management

    /// Preload a model for fast transcription
    public func preloadModel(_ modelId: String) async throws {
        logger.info("[Engine] Preloading model '\(modelId)'...")

        guard let proxy = engineProxy else {
            logger.error("[Engine] Cannot preload - not connected")
            throw EngineClientError.notConnected
        }

        let startTime = Date()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            proxy.preloadModel(modelId) { error in
                let elapsed = Date().timeIntervalSince(startTime)
                if let error = error {
                    logger.error("[Engine] Model preload failed after \(String(format: "%.1f", elapsed))s: \(error)")
                    continuation.resume(throwing: EngineClientError.preloadFailed(error))
                } else {
                    logger.info("[Engine] ✓ Model '\(modelId)' preloaded in \(String(format: "%.1f", elapsed))s")
                    continuation.resume()
                }
            }
        }

        // Refresh status after preload
        refreshStatus()
    }

    /// Unload current model
    public func unloadModel() async {
        logger.info("[Engine] Unloading model...")

        guard let proxy = engineProxy else {
            logger.warning("[Engine] Cannot unload - not connected")
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            proxy.unloadModel {
                logger.info("[Engine] ✓ Model unloaded")
                continuation.resume()
            }
        }

        // Refresh status after unload
        refreshStatus()
    }

    /// Refresh engine status
    public func refreshStatus() {
        guard let proxy = engineProxy else { return }

        proxy.getStatus { [weak self] statusJSON in
            Task { @MainActor in
                if let data = statusJSON,
                   let status = try? JSONDecoder().decode(EngineStatus.self, from: data) {
                    self?.status = status
                    if let modelId = status.loadedModelId {
                        logger.debug("[Engine] Status: model='\(modelId)', transcribing=\(status.isTranscribing)")
                    } else {
                        logger.debug("[Engine] Status: no model loaded")
                    }
                }
            }
        }
    }
}

// MARK: - Errors

public enum EngineClientError: LocalizedError {
    case notConnected
    case transcriptionFailed(String)
    case preloadFailed(String)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to TalkieEngine"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .preloadFailed(let message):
            return "Failed to preload model: \(message)"
        case .emptyResponse:
            return "Empty response from engine"
        }
    }
}
