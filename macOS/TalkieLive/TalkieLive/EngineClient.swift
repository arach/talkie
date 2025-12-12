//
//  EngineClient.swift
//  TalkieLive
//
//  XPC client to connect to TalkieEngine for transcription
//

import Foundation
import AppKit
import os

private let logger = Logger(subsystem: "jdi.talkie.live", category: "Engine")

/// Mach service name for XPC connection (must match TalkieEngine)
#if DEBUG
private let kTalkieEngineServiceName = "jdi.talkie.engine.xpc.debug"
#else
private let kTalkieEngineServiceName = "jdi.talkie.engine.xpc"
#endif

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

    // Download management
    func downloadModel(_ modelId: String, reply: @escaping (_ error: String?) -> Void)
    func getDownloadProgress(reply: @escaping (_ progressJSON: Data?) -> Void)
    func cancelDownload(reply: @escaping () -> Void)
    func getAvailableModels(reply: @escaping (_ modelsJSON: Data?) -> Void)
}

/// Engine status (matches TalkieEngine's EngineStatus)
public struct EngineStatus: Codable, Sendable {
    // Process info
    public let pid: Int32
    public let version: String
    public let startedAt: Date
    public let bundleId: String
    public let isDebugBuild: Bool?  // Optional for backwards compat

    // Model state
    public let loadedModelId: String?
    public let isTranscribing: Bool
    public let isWarmingUp: Bool
    public let downloadedModels: [String]

    // Stats
    public let totalTranscriptions: Int
    public let memoryUsageMB: Int?

    /// Computed: Engine uptime
    public var uptime: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }

    /// Computed: Formatted uptime string
    public var uptimeFormatted: String {
        let seconds = Int(uptime)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        return "\(hours)h \(minutes % 60)m"
    }

    /// Computed: Memory usage formatted
    public var memoryFormatted: String? {
        guard let mb = memoryUsageMB else { return nil }
        if mb < 1024 { return "\(mb) MB" }
        return String(format: "%.1f GB", Double(mb) / 1024.0)
    }
}

/// Download progress (matches TalkieEngine's DownloadProgress)
public struct DownloadProgress: Codable, Sendable {
    public let modelId: String
    public let progress: Double  // 0.0 to 1.0
    public let downloadedBytes: Int64
    public let totalBytes: Int64?
    public let isDownloading: Bool

    /// Formatted progress string (e.g., "45%")
    public var progressFormatted: String {
        "\(Int(progress * 100))%"
    }

    /// Formatted size string (e.g., "150 MB / 300 MB")
    public var sizeFormatted: String {
        let downloaded = formatBytes(downloadedBytes)
        if let total = totalBytes {
            return "\(downloaded) / \(formatBytes(total))"
        }
        return downloaded
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb < 1000 {
            return String(format: "%.0f MB", mb)
        }
        return String(format: "%.1f GB", mb / 1000)
    }
}

/// Model family identifiers (matches TalkieEngine's ModelFamily)
public enum ModelFamily: String, Codable, Sendable, CaseIterable {
    case whisper = "whisper"
    case parakeet = "parakeet"

    public var displayName: String {
        switch self {
        case .whisper: return "Whisper"
        case .parakeet: return "Parakeet"
        }
    }

    public var description: String {
        switch self {
        case .whisper: return "OpenAI Whisper (WhisperKit)"
        case .parakeet: return "NVIDIA Parakeet (FluidAudio)"
        }
    }
}

/// Model info for display (matches TalkieEngine's ModelInfo)
public struct ModelInfo: Codable, Sendable, Identifiable {
    public let id: String           // Full ID including family prefix (e.g., "whisper:openai_whisper-small")
    public let family: String       // Model family ("whisper" or "parakeet")
    public let modelId: String      // Model ID without family prefix
    public let displayName: String
    public let sizeDescription: String
    public let description: String  // Quality/speed description
    public let isDownloaded: Bool
    public let isLoaded: Bool

    /// Parse a model ID string into family and model components
    public static func parseModelId(_ fullId: String) -> (family: String, modelId: String) {
        let parts = fullId.split(separator: ":", maxSplits: 1)
        if parts.count == 2 {
            return (String(parts[0]), String(parts[1]))
        }
        // Default to whisper for backwards compatibility
        return ("whisper", fullId)
    }

    /// Get the ModelFamily enum for this model
    public var modelFamily: ModelFamily? {
        ModelFamily(rawValue: family)
    }
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

    // MARK: - Download State
    @Published public private(set) var downloadProgress: DownloadProgress?
    @Published public private(set) var availableModels: [ModelInfo] = []

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
        guard connection == nil else {
            logger.debug("[Connect] Already have connection, state=\(self.connectionState.rawValue)")
            return
        }

        connectionState = .connecting
        logger.info("[Connect] Initiating XPC connection to '\(kTalkieEngineServiceName)'")

        let conn = NSXPCConnection(machServiceName: kTalkieEngineServiceName)
        conn.remoteObjectInterface = NSXPCInterface(with: TalkieEngineProtocol.self)
        logger.debug("[Connect] Created NSXPCConnection, setting up handlers")

        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                logger.warning("[Connect] XPC connection invalidated")
                self?.handleDisconnection(reason: "Connection invalidated")
            }
        }

        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                logger.warning("[Connect] XPC connection interrupted")
                self?.handleDisconnection(reason: "Connection interrupted")
            }
        }

        conn.resume()
        connection = conn
        logger.info("[Connect] Connection resumed, testing with ping...")

        // Test connection with ping
        Task {
            await testConnection()
        }
    }

    private func testConnection() async {
        logger.debug("[Connect] testConnection started")

        guard let conn = connection else {
            logger.error("[Connect] testConnection: connection is nil")
            return
        }

        logger.debug("[Connect] Getting remoteObjectProxy...")
        let proxy = conn.remoteObjectProxyWithErrorHandler { error in
            Task { @MainActor in
                logger.error("[Connect] XPC proxy error: \(error.localizedDescription)")
                self.lastError = error.localizedDescription
                self.handleDisconnection(reason: error.localizedDescription)
            }
        } as? TalkieEngineProtocol

        guard let proxy = proxy else {
            logger.error("[Connect] Failed to cast proxy to TalkieEngineProtocol")
            handleDisconnection(reason: "Failed to create proxy")
            return
        }

        logger.info("[Connect] Proxy obtained, sending ping...")

        // Ping to verify connection
        proxy.ping { [weak self] pong in
            Task { @MainActor in
                logger.info("[Connect] Ping response: \(pong)")
                if pong {
                    self?.connectionState = .connected
                    self?.connectedAt = Date()
                    self?.engineProxy = proxy
                    self?.lastError = nil
                    logger.info("[Connect] ✓ Connected to TalkieEngine, fetching models...")
                    self?.refreshStatus()
                    // Also fetch available models on connect
                    await self?.refreshAvailableModels()
                    logger.info("[Connect] ✓ Connection setup complete")
                } else {
                    logger.warning("[Connect] Ping returned false - engine not responding")
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
    /// On first launch, the engine may need time to start via launchd
    public func ensureConnected() async -> Bool {
        if isConnected { return true }

        // Try connecting with retries (engine may need to start via launchd)
        for attempt in 1...3 {
            if attempt > 1 {
                logger.info("[Connect] Retry attempt \(attempt)/3...")
                // Reset connection state for retry
                handleDisconnection(reason: "Retry attempt \(attempt)")

                // Try to launch TalkieEngine explicitly on retry
                await launchEngineIfNeeded()
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s for engine to start
            }

            connect()

            // Wait for connection (up to 2 seconds per attempt)
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                if isConnected { return true }
            }
        }

        return isConnected
    }

    /// Launch TalkieEngine app if it's not running
    private func launchEngineIfNeeded() async {
        // Check if engine is already running
        let runningApps = NSWorkspace.shared.runningApplications
        let engineRunning = runningApps.contains { $0.bundleIdentifier == "jdi.talkie.engine" }

        if engineRunning {
            logger.info("[Connect] TalkieEngine already running")
            return
        }

        logger.info("[Connect] Launching TalkieEngine...")

        // Try to launch from /Applications
        let engineURL = URL(fileURLWithPath: "/Applications/TalkieEngine.app")
        if FileManager.default.fileExists(atPath: engineURL.path) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false // Don't bring to front
            do {
                try await NSWorkspace.shared.openApplication(at: engineURL, configuration: config)
                logger.info("[Connect] TalkieEngine launched")
            } catch {
                logger.error("[Connect] Failed to launch TalkieEngine: \(error.localizedDescription)")
            }
        } else {
            logger.error("[Connect] TalkieEngine not found at /Applications/TalkieEngine.app")
        }
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
    /// Automatically waits and retries if engine is busy (loading model or transcribing)
    public func transcribe(audioData: Data, modelId: String = "openai_whisper-small") async throws -> String {
        guard let proxy = engineProxy else {
            // Try to connect first
            let connected = await ensureConnected()
            guard connected, let proxy = engineProxy else {
                throw EngineClientError.notConnected
            }
            return try await transcribeWithRetry(proxy: proxy, audioData: audioData, modelId: modelId)
        }

        return try await transcribeWithRetry(proxy: proxy, audioData: audioData, modelId: modelId)
    }

    /// Transcribe with automatic retry for "Already transcribing" errors
    /// This handles the case where engine is busy loading a model (can take 60+ seconds)
    /// or processing another transcription
    private func transcribeWithRetry(proxy: TalkieEngineProtocol, audioData: Data, modelId: String) async throws -> String {
        let maxAttempts = 30  // 30 attempts × 2s = 60s max wait
        let retryDelay: UInt64 = 2_000_000_000  // 2 seconds

        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                return try await doTranscribe(proxy: proxy, audioData: audioData, modelId: modelId)
            } catch let error as EngineClientError {
                // Check if it's "Already transcribing" - wait and retry
                if case .transcriptionFailed(let message) = error, message.contains("Already transcribing") {
                    logger.info("[Engine] Engine busy (attempt \(attempt)/\(maxAttempts)), waiting 2s...")
                    lastError = error
                    try? await Task.sleep(nanoseconds: retryDelay)
                    continue
                }
                // Other errors - don't retry
                throw error
            }
        }

        // Exhausted retries
        logger.error("[Engine] Engine still busy after \(maxAttempts) attempts (~60s)")
        throw lastError ?? EngineClientError.transcriptionFailed("Engine busy timeout")
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

    // MARK: - Download Management

    /// Download a model by ID
    public func downloadModel(_ modelId: String) async throws {
        logger.info("[Engine] Downloading model '\(modelId)'...")

        guard let proxy = engineProxy else {
            logger.error("[Engine] Cannot download - not connected")
            throw EngineClientError.notConnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            proxy.downloadModel(modelId) { error in
                if let error = error {
                    logger.error("[Engine] Download failed: \(error)")
                    continuation.resume(throwing: EngineClientError.downloadFailed(error))
                } else {
                    logger.info("[Engine] ✓ Model '\(modelId)' downloaded")
                    continuation.resume()
                }
            }
        }

        // Refresh available models after download
        await refreshAvailableModels()
        refreshStatus()
    }

    /// Get current download progress
    public func getDownloadProgress() async -> DownloadProgress? {
        guard let proxy = engineProxy else { return nil }

        return await withCheckedContinuation { continuation in
            proxy.getDownloadProgress { progressJSON in
                if let data = progressJSON,
                   let progress = try? JSONDecoder().decode(DownloadProgress.self, from: data) {
                    continuation.resume(returning: progress)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Cancel any ongoing download
    public func cancelDownload() async {
        logger.info("[Engine] Cancelling download...")

        guard let proxy = engineProxy else {
            logger.warning("[Engine] Cannot cancel - not connected")
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            proxy.cancelDownload {
                logger.info("[Engine] ✓ Download cancelled")
                continuation.resume()
            }
        }

        downloadProgress = nil
    }

    /// Refresh available models list
    public func refreshAvailableModels() async {
        logger.info("[Models] refreshAvailableModels called, connectionState=\(self.connectionState.rawValue)")

        guard let proxy = engineProxy else {
            logger.warning("[Models] Cannot refresh models - engineProxy is nil")
            return
        }

        logger.info("[Models] Calling getAvailableModels on XPC proxy...")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            proxy.getAvailableModels { [weak self] modelsJSON in
                Task { @MainActor in
                    logger.info("[Models] XPC callback received, data=\(modelsJSON != nil ? "\(modelsJSON!.count) bytes" : "nil")")

                    if let data = modelsJSON {
                        do {
                            let models = try JSONDecoder().decode([ModelInfo].self, from: data)
                            self?.availableModels = models
                            logger.info("[Models] ✓ Decoded \(models.count) models: \(models.map { "\($0.id)(\($0.isDownloaded ? "downloaded" : "remote"))" }.joined(separator: ", "))")
                        } catch {
                            logger.error("[Models] JSON decode failed: \(error.localizedDescription)")
                            if let jsonString = String(data: data, encoding: .utf8) {
                                logger.error("[Models] Raw JSON (first 500 chars): \(jsonString.prefix(500))")
                            }
                        }
                    } else {
                        logger.warning("[Models] Engine returned nil for getAvailableModels")
                    }
                    continuation.resume()
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
    case downloadFailed(String)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to TalkieEngine"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .preloadFailed(let message):
            return "Failed to preload model: \(message)"
        case .downloadFailed(let message):
            return "Failed to download model: \(message)"
        case .emptyResponse:
            return "Empty response from engine"
        }
    }
}
