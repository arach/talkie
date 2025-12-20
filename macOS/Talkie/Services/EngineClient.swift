//
//  EngineClient.swift
//  Talkie
//
//  XPC client to connect to TalkieEngine for transcription
//

import Foundation
import AppKit
import os
import TalkieKit

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Engine")

/// Engine service modes for XPC connection (aligned with TalkieEnvironment)
public enum EngineServiceMode: String, CaseIterable, Identifiable {
    case production = "jdi.talkie.engine.xpc"
    case staging = "jdi.talkie.engine.xpc.staging"
    case dev = "jdi.talkie.engine.xpc.dev"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .production: return "Production"
        case .staging: return "Staging"
        case .dev: return "Dev"
        }
    }

    public var shortName: String {
        switch self {
        case .production: return "PROD"
        case .staging: return "STAGE"
        case .dev: return "DEV"
        }
    }

    /// Initialize from TalkieEnvironment
    public init(from environment: TalkieEnvironment) {
        switch environment {
        case .production:
            self = .production
        case .staging:
            self = .staging
        case .dev:
            self = .dev
        }
    }
}

/// XPC protocol for TalkieEngine (must match TalkieEngine's protocol)
@objc protocol TalkieEngineProtocol {
    func transcribe(
        audioPath: String,
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

    // MARK: - Model Download Management

    func downloadModel(
        _ modelId: String,
        reply: @escaping (_ error: String?) -> Void
    )

    func getDownloadProgress(reply: @escaping (_ progressJSON: Data?) -> Void)

    func cancelDownload(reply: @escaping () -> Void)

    func getAvailableModels(reply: @escaping (_ modelsJSON: Data?) -> Void)
}

/// Engine status (matches TalkieEngine's EngineStatus)
public struct EngineStatus: Codable, Sendable {
    public let pid: Int32?
    public let isDebugBuild: Bool?
    public let loadedModelId: String?
    public let isTranscribing: Bool
    public let isWarmingUp: Bool
    public let downloadedModels: [String]
}

/// Download progress (matches TalkieEngine's DownloadProgress)
public struct DownloadProgress: Codable, Sendable {
    public let modelId: String
    public let progress: Double  // 0.0 to 1.0
    public let downloadedBytes: Int64
    public let totalBytes: Int64?
    public let isDownloading: Bool

    public var progressFormatted: String {
        "\(Int(progress * 100))%"
    }

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

/// Model info for display (matches TalkieEngine's ModelInfo)
public struct ModelInfo: Codable, Sendable, Identifiable {
    public let id: String           // Full ID including family prefix
    public let family: String       // Model family ("whisper" or "parakeet")
    public let modelId: String      // Model ID without family prefix
    public let displayName: String
    public let sizeDescription: String
    public let description: String
    public let isDownloaded: Bool
    public let isLoaded: Bool

    public static func parseModelId(_ fullId: String) -> (family: String, modelId: String) {
        let parts = fullId.split(separator: ":", maxSplits: 1)
        if parts.count == 2 {
            return (String(parts[0]), String(parts[1]))
        }
        return ("whisper", fullId)
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

    /// The mode we're currently connected to (for UI display)
    @Published public private(set) var connectedMode: EngineServiceMode?

    // MARK: - Session Stats
    @Published public private(set) var connectedAt: Date?
    @Published public private(set) var transcriptionCount: Int = 0
    @Published public private(set) var lastTranscriptionAt: Date?

    // MARK: - Model Management State
    @Published public var availableModels: [ModelInfo] = []
    @Published public var downloadProgress: DownloadProgress?
    @Published public var isDownloading: Bool = false

    /// Computed property for backwards compatibility
    public var isConnected: Bool { connectionState == .connected }

    private var connection: NSXPCConnection?
    private var engineProxy: TalkieEngineProtocol?

    private init() {
        logger.info("[Engine] Client initialized")
    }

    // MARK: - Connection Management

    /// Connect to engine based on current environment
    public func connect() {
        guard connection == nil else {
            NSLog("[EngineClient] ⚠️ Already connected, skipping")
            return
        }

        // Determine mode from current environment
        let environment = TalkieEnvironment.current
        let primaryMode = EngineServiceMode(from: environment)

        NSLog("[EngineClient] 🔌 Connecting to \(environment.displayName) engine (\(primaryMode.rawValue))")
        logger.info("[Engine] Connecting to \(environment.displayName) engine (\(primaryMode.rawValue))")

        // Connect directly to environment-specific engine
        connectToMode(primaryMode)
    }

    /// Try connecting to modes in order until one succeeds
    private func connectWithFallback(modes: [EngineServiceMode]) {
        guard !modes.isEmpty else {
            connectionState = .error
            lastError = "No engines available"
            return
        }

        let mode = modes[0]
        let remainingModes = Array(modes.dropFirst())

        connectionState = .connecting
        logger.info("[Engine] Trying \(mode.shortName) (\(mode.rawValue))...")

        tryConnect(to: mode) { [weak self] success in
            guard let self = self else { return }

            if success {
                self.connectedMode = mode
                logger.info("[Engine] ✓ Connected to \(mode.shortName)")
            } else if !remainingModes.isEmpty {
                // Try next mode
                logger.info("[Engine] \(mode.shortName) not available, trying next...")
                self.connectWithFallback(modes: remainingModes)
            } else {
                self.connectionState = .error
                self.lastError = "No engines available"
                logger.warning("[Engine] All connection attempts failed")
            }
        }
    }

    /// Connect directly to a specific mode
    private func connectToMode(_ mode: EngineServiceMode) {
        connectionState = .connecting
        NSLog("[EngineClient] Connecting to \(mode.shortName) (\(mode.rawValue))")
        logger.info("[Engine] Connecting to \(mode.shortName) (\(mode.rawValue))")

        tryConnect(to: mode) { [weak self] success in
            NSLog("[EngineClient] Connection result: \(success ? "✓ SUCCESS" : "✗ FAILED")")
            if success {
                self?.connectedMode = mode
            } else {
                self?.connectionState = .error
            }
        }
    }

    /// Attempt to connect to a specific mode
    private func tryConnect(to mode: EngineServiceMode, completion: @escaping (Bool) -> Void) {
        let serviceName = mode.rawValue

        let conn = NSXPCConnection(machServiceName: serviceName)
        conn.remoteObjectInterface = NSXPCInterface(with: TalkieEngineProtocol.self)

        // Quick timeout for connection test
        var completed = false

        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                NSLog("[EngineClient] ⚠️ Connection invalidation handler fired")
                if !completed {
                    completed = true
                    completion(false)
                } else {
                    self?.handleDisconnection(reason: "Connection invalidated")
                }
            }
        }

        NSLog("[EngineClient] Resuming XPC connection...")
        conn.resume()
        NSLog("[EngineClient] XPC connection resumed, getting proxy...")

        // Test with ping
        let proxy = conn.remoteObjectProxyWithErrorHandler { error in
            Task { @MainActor in
                NSLog("[EngineClient] ❌ XPC Error handler fired: \(error.localizedDescription)")
                if !completed {
                    completed = true
                    conn.invalidate()
                    completion(false)
                }
            }
        } as? TalkieEngineProtocol

        guard let proxy = proxy else {
            NSLog("[EngineClient] ❌ Failed to get proxy object")
            conn.invalidate()
            completion(false)
            return
        }

        NSLog("[EngineClient] ✓ Got proxy, sending ping...")
        proxy.ping { [weak self] pong in
            Task { @MainActor in
                guard !completed else { return }
                completed = true

                NSLog("[EngineClient] Ping response: \(pong ? "PONG ✓" : "NO RESPONSE")")

                if pong {
                    // Success! Keep this connection
                    self?.connection = conn
                    self?.engineProxy = proxy
                    self?.connectionState = .connected
                    self?.connectedAt = Date()
                    self?.lastError = nil

                    NSLog("[EngineClient] ✓ Connected to \(mode.displayName) (\(serviceName))")
                    logger.info("[Engine] ✓ Connected to \(mode.displayName) (\(serviceName))")

                    // Set up real disconnection handler now
                    conn.interruptionHandler = { [weak self] in
                        Task { @MainActor in
                            self?.handleDisconnection(reason: "Connection interrupted")
                        }
                    }

                    self?.refreshStatus()

                    // Fetch available models immediately after connection
                    NSLog("[EngineClient] Fetching available models...")
                    Task { @MainActor in
                        await self?.fetchAvailableModels()
                    }

                    completion(true)
                } else {
                    conn.invalidate()
                    completion(false)
                }
            }
        }

        // Timeout after 500ms
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !completed {
                completed = true
                conn.invalidate()
                completion(false)
            }
        }
    }

    private func handleDisconnection(reason: String) {
        let wasConnected = connectionState == .connected
        let wasMode = connectedMode

        connectionState = .disconnected
        engineProxy = nil
        connection?.invalidate()
        connection = nil
        status = nil
        connectedMode = nil

        if wasConnected {
            let sessionDuration = connectedAt.map { formatDuration(since: $0) } ?? "unknown"
            logger.info("[Engine] Disconnected from \(wasMode?.shortName ?? "?") after \(sessionDuration)")
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
        // Check if engine is already running (production or dev)
        let engineBundleIds = ["jdi.talkie.engine", "jdi.talkie.engine.dev"]
        let runningApps = NSWorkspace.shared.runningApplications
        let engineRunning = runningApps.contains { app in
            engineBundleIds.contains(app.bundleIdentifier ?? "")
        }

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
    /// Audio is written to a temp file, engine reads from path, temp file is cleaned up after
    public func transcribe(audioData: Data, modelId: String = "whisper:openai_whisper-small") async throws -> String {
        // Write audio data to temp file for engine to read
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        do {
            try audioData.write(to: tempURL)
        } catch {
            throw EngineClientError.transcriptionFailed("Failed to write temp audio file: \(error.localizedDescription)")
        }

        // Ensure cleanup
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        return try await transcribe(audioPath: tempURL.path, modelId: modelId)
    }

    /// Transcribe audio from a file path using TalkieEngine
    public func transcribe(audioPath: String, modelId: String = "whisper:openai_whisper-small") async throws -> String {
        guard let proxy = engineProxy else {
            // Try to connect first
            let connected = await ensureConnected()
            guard connected, let proxy = engineProxy else {
                throw EngineClientError.notConnected
            }
            return try await doTranscribe(proxy: proxy, audioPath: audioPath, modelId: modelId)
        }

        return try await doTranscribe(proxy: proxy, audioPath: audioPath, modelId: modelId)
    }

    private func doTranscribe(proxy: TalkieEngineProtocol, audioPath: String, modelId: String) async throws -> String {
        let fileName = URL(fileURLWithPath: audioPath).lastPathComponent
        logger.info("[Engine] Transcribing '\(fileName)' with model '\(modelId)'")

        let startTime = Date()
        let timeoutSeconds: UInt64 = 120 // 2 minute timeout for long audio files

        // Use task group with timeout to prevent continuation leaks when XPC connection dies
        return try await withThrowingTaskGroup(of: String.self) { group in
            // Task 1: The actual XPC call
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    proxy.transcribe(audioPath: audioPath, modelId: modelId) { transcript, error in
                        if let error = error {
                            continuation.resume(throwing: EngineClientError.transcriptionFailed(error))
                        } else if let transcript = transcript {
                            continuation.resume(returning: transcript)
                        } else {
                            continuation.resume(throwing: EngineClientError.emptyResponse)
                        }
                    }
                }
            }

            // Task 2: Timeout watchdog
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                throw EngineClientError.transcriptionFailed("Timeout after \(timeoutSeconds)s - engine may have disconnected")
            }

            // Return first result (success or timeout), cancel the other
            guard let result = try await group.next() else {
                throw EngineClientError.transcriptionFailed("Unexpected task group state")
            }
            group.cancelAll()

            // Update stats on success
            let elapsed = Date().timeIntervalSince(startTime)
            self.transcriptionCount += 1
            self.lastTranscriptionAt = Date()
            let wordCount = result.split(separator: " ").count
            logger.info("[Engine] ✓ Transcription #\(self.transcriptionCount) completed in \(String(format: "%.1f", elapsed))s (\(wordCount) words)")

            return result
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

    // MARK: - Model Download Management

    /// Get list of available models from engine
    public func fetchAvailableModels() async {
        NSLog("[EngineClient] fetchAvailableModels() called, engineProxy = \(engineProxy != nil ? "NOT NIL" : "NIL")")

        guard let proxy = engineProxy else {
            NSLog("[EngineClient] ❌ Cannot fetch models - engineProxy is NIL")
            logger.warning("[Engine] Cannot fetch models - not connected (engineProxy is nil)")
            return
        }

        NSLog("[EngineClient] Calling proxy.getAvailableModels()...")
        logger.info("[Engine] Fetching available models from engine...")

        proxy.getAvailableModels { [weak self] modelsJSON in
            Task { @MainActor in
                NSLog("[EngineClient] getAvailableModels callback received, data = \(modelsJSON != nil ? "NOT NIL" : "NIL")")
                if let data = modelsJSON,
                   let models = try? JSONDecoder().decode([ModelInfo].self, from: data) {
                    NSLog("[EngineClient] ✓ Decoded \(models.count) models, updating availableModels")
                    self?.availableModels = models
                    logger.info("[Engine] ✓ Fetched \(models.count) available models")
                } else {
                    NSLog("[EngineClient] ❌ Failed to decode models")
                    logger.warning("[Engine] Failed to decode available models")
                }
            }
        }
    }

    /// Download a model
    public func downloadModel(_ modelId: String) async throws {
        logger.info("[Engine] Downloading model '\(modelId)'...")

        guard let proxy = engineProxy else {
            logger.error("[Engine] Cannot download - not connected")
            throw EngineClientError.notConnected
        }

        isDownloading = true

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                proxy.downloadModel(modelId) { error in
                    Task { @MainActor in
                        self.isDownloading = false
                        if let error = error {
                            logger.error("[Engine] Model download failed: \(error)")
                            continuation.resume(throwing: EngineClientError.downloadFailed(error))
                        } else {
                            logger.info("[Engine] ✓ Model '\(modelId)' downloaded successfully")
                            continuation.resume()
                        }
                    }
                }
            }

            // Refresh models and status after download
            await fetchAvailableModels()
            refreshStatus()
        } catch {
            isDownloading = false
            throw error
        }
    }

    /// Start monitoring download progress (call periodically while downloading)
    public func refreshDownloadProgress() {
        guard let proxy = engineProxy else { return }

        proxy.getDownloadProgress { [weak self] progressJSON in
            Task { @MainActor in
                if let data = progressJSON,
                   let progress = try? JSONDecoder().decode(DownloadProgress.self, from: data) {
                    self?.downloadProgress = progress
                    self?.isDownloading = progress.isDownloading
                } else {
                    self?.downloadProgress = nil
                }
            }
        }
    }

    /// Cancel ongoing download
    public func cancelDownload() async {
        logger.info("[Engine] Canceling download...")

        guard let proxy = engineProxy else {
            logger.warning("[Engine] Cannot cancel - not connected")
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            proxy.cancelDownload {
                Task { @MainActor in
                    self.isDownloading = false
                    self.downloadProgress = nil
                    logger.info("[Engine] ✓ Download canceled")
                    continuation.resume()
                }
            }
        }
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
