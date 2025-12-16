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

/// Engine service modes for XPC connection
public enum EngineServiceMode: String, CaseIterable, Identifiable {
    case production = "jdi.talkie.engine.xpc"
    case dev = "jdi.talkie.engine.xpc.dev"
    case debug = "jdi.talkie.engine.xpc.dev.debug"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .production: return "Production"
        case .dev: return "Dev (Daemon)"
        case .debug: return "Debug (Xcode)"
        }
    }

    public var shortName: String {
        switch self {
        case .production: return "PROD"
        case .dev: return "DEV"
        case .debug: return "DBG"
        }
    }

    /// Whether this is debug mode (orange indicator)
    public var isDebugMode: Bool { self == .debug }
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
    case connectedWrongBuild = "Wrong Engine"  // Connected to prod when expecting debug, or vice versa
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

    // MARK: - Download State
    @Published public private(set) var downloadProgress: DownloadProgress?
    @Published public private(set) var availableModels: [ModelInfo] = []

    /// Computed property for backwards compatibility
    public var isConnected: Bool { connectionState == .connected || connectionState == .connectedWrongBuild }

    /// Whether we're in DEBUG build
    public var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Whether the connected engine matches our build type
    public var isMatchingBuild: Bool {
        guard let engineDebug = status?.isDebugBuild else { return true }  // Assume match if unknown
        return engineDebug == isDebugBuild
    }

    /// Warning message if connected to wrong engine
    public var buildMismatchWarning: String? {
        guard isConnected, !isMatchingBuild else { return nil }
        if isDebugBuild {
            return "Connected to RELEASE engine (expected DEBUG)"
        } else {
            return "Connected to DEBUG engine (expected RELEASE)"
        }
    }

    private var connection: NSXPCConnection?
    private var engineProxy: TalkieEngineProtocol?

    private init() {
        logger.info("[Engine] Client initialized")
    }

    // MARK: - Connection Management

    /// Connect using honor system: try debug first, fall back to dev
    public func connect() {
        guard connection == nil else {
            logger.debug("[Connect] Already have connection, state=\(self.connectionState.rawValue)")
            return
        }

        #if DEBUG
        // Honor system: try debug (Xcode) first, fall back to dev (daemon)
        connectWithFallback(modes: [.debug, .dev])
        #else
        // Production: only try production
        connectToMode(.production)
        #endif
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
        logger.info("[Engine] Connecting to \(mode.shortName) (\(mode.rawValue))")

        tryConnect(to: mode) { [weak self] success in
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
                if !completed {
                    completed = true
                    completion(false)
                } else {
                    self?.handleDisconnection(reason: "Connection invalidated")
                }
            }
        }

        conn.resume()

        // Test with ping
        let proxy = conn.remoteObjectProxyWithErrorHandler { _ in
            Task { @MainActor in
                if !completed {
                    completed = true
                    conn.invalidate()
                    completion(false)
                }
            }
        } as? TalkieEngineProtocol

        guard let proxy = proxy else {
            conn.invalidate()
            completion(false)
            return
        }

        proxy.ping { [weak self] pong in
            Task { @MainActor in
                guard !completed else { return }
                completed = true

                if pong {
                    // Success! Keep this connection
                    self?.connection = conn
                    self?.engineProxy = proxy
                    self?.connectionState = .connected
                    self?.connectedAt = Date()
                    self?.lastError = nil

                    // Set up real disconnection handler now
                    conn.interruptionHandler = { [weak self] in
                        Task { @MainActor in
                            self?.handleDisconnection(reason: "Connection interrupted")
                        }
                    }

                    self?.refreshStatus()
                    // Also fetch available models on connect
                    Task {
                        await self?.refreshAvailableModels()
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
        let wasConnected = connectionState == .connected || connectionState == .connectedWrongBuild
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

            // If we were on debug, try falling back to dev
            #if DEBUG
            if wasMode == .debug {
                logger.info("[Engine] Debug disconnected, falling back to dev daemon...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.connectToMode(.dev)
                }
            }
            #endif
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

    /// Transcribe audio file using TalkieEngine
    /// Automatically waits and retries if engine is busy (loading model or transcribing)
    /// - Parameters:
    ///   - audioPath: Path to audio file (client owns the file, engine reads directly)
    ///   - modelId: Model to use for transcription
    public func transcribe(audioPath: String, modelId: String = "parakeet:v3") async throws -> String {
        guard let proxy = engineProxy else {
            // Try to connect first
            let connected = await ensureConnected()
            guard connected, let proxy = engineProxy else {
                throw EngineClientError.notConnected
            }
            return try await transcribeWithRetry(proxy: proxy, audioPath: audioPath, modelId: modelId)
        }

        return try await transcribeWithRetry(proxy: proxy, audioPath: audioPath, modelId: modelId)
    }

    /// Transcribe with automatic retry for "Already transcribing" errors
    /// This handles the case where engine is busy loading a model (can take 60+ seconds)
    /// or processing another transcription
    private func transcribeWithRetry(proxy: TalkieEngineProtocol, audioPath: String, modelId: String) async throws -> String {
        let maxAttempts = 30  // 30 attempts × 2s = 60s max wait
        let retryDelay: UInt64 = 2_000_000_000  // 2 seconds

        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                return try await doTranscribe(proxy: proxy, audioPath: audioPath, modelId: modelId)
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

    /// Refresh engine status
    public func refreshStatus() {
        guard let proxy = engineProxy else { return }

        proxy.getStatus { [weak self] statusJSON in
            Task { @MainActor in
                guard let self else { return }

                if let data = statusJSON,
                   let status = try? JSONDecoder().decode(EngineStatus.self, from: data) {
                    self.status = status

                    // Check for build mismatch
                    if let engineDebug = status.isDebugBuild {
                        if engineDebug != self.isDebugBuild {
                            self.connectionState = .connectedWrongBuild
                            logger.warning("[Engine] ⚠️ Build mismatch! App=\(self.isDebugBuild ? "DEBUG" : "RELEASE"), Engine=\(engineDebug ? "DEBUG" : "RELEASE")")
                        } else if self.connectionState == .connectedWrongBuild {
                            // Was mismatched, now correct
                            self.connectionState = .connected
                        }
                    }

                    if let modelId = status.loadedModelId {
                        logger.debug("[Engine] Status: model='\(modelId)', transcribing=\(status.isTranscribing), debug=\(status.isDebugBuild ?? false)")
                    } else {
                        logger.debug("[Engine] Status: no model loaded, debug=\(status.isDebugBuild ?? false)")
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
