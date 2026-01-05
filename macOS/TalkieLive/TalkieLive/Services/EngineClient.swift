//
//  EngineClient.swift
//  TalkieLive
//
//  XPC client to connect to TalkieEngine for transcription
//

import Foundation
import AppKit
import os
import os.signpost
import TalkieKit

private let log = Log(.xpc)

/// Signpost log for XPC round-trip profiling in Instruments
private let xpcSignpostLog = OSLog(subsystem: "jdi.talkie.live", category: .pointsOfInterest)

// TranscriptionPriority is now defined in TalkieKit

/// Log an XPC error with full details for debugging
private func logXPCError(_ error: Error, context: String) {
    let nsError = error as NSError
    let detail = "Context: \(context) | Domain: \(nsError.domain) | Code: \(nsError.code) | Recovery: Try restarting TalkieEngine"
    log.error("XPC Error: \(context)", detail: detail, error: error)
}

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

// NOTE: TalkieEngineProtocol is imported from TalkieKit
// Do NOT duplicate it here - use TalkieKit.TalkieEngineProtocol

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
        log.info("Client initialized")
    }

    // MARK: - Connection Management

    /// Connect using honor system: try debug first, fall back to dev
    public func connect() {
        guard connection == nil else {
            log.debug("Already have connection", detail: "state=\(self.connectionState.rawValue)")
            return
        }

        // Determine mode from current environment
        let environment = TalkieEnvironment.current
        let primaryMode = EngineServiceMode(from: environment)

        // Connect directly to environment-specific engine
        connectToMode(primaryMode)

        log.info("Connecting to engine", detail: "\(environment.displayName) (\(primaryMode.rawValue))")
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
        log.info("Trying engine", detail: "\(mode.shortName) (\(mode.rawValue))")

        tryConnect(to: mode) { [weak self] success in
            guard let self = self else { return }

            if success {
                self.connectedMode = mode
                log.info("Connected to engine", detail: mode.shortName)
            } else if !remainingModes.isEmpty {
                // Try next mode
                log.info("Engine not available, trying next", detail: mode.shortName)
                self.connectWithFallback(modes: remainingModes)
            } else {
                self.connectionState = .error
                self.lastError = "No engines available"
                log.error("All connection attempts failed - no engines available")
            }
        }
    }

    /// Connect directly to a specific mode
    private func connectToMode(_ mode: EngineServiceMode) {
        connectionState = .connecting
        log.info("Connecting to mode", detail: "\(mode.shortName) (\(mode.rawValue))")

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

        log.info("Attempting XPC connection", detail: serviceName)

        let conn = NSXPCConnection(machServiceName: serviceName)
        conn.remoteObjectInterface = NSXPCInterface(with: TalkieEngineProtocol.self)

        // Quick timeout for connection test
        var completed = false

        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                if !completed {
                    completed = true
                    log.warning("XPC connection invalidated before ping completed", detail: "Service: \(serviceName). Engine may not be running or has a version mismatch.")
                    completion(false)
                } else {
                    self?.handleDisconnection(reason: "XPC invalidated (\(serviceName))")
                }
            }
        }

        conn.resume()

        // Test with ping
        let proxy = conn.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in
                if !completed {
                    completed = true
                    logXPCError(error, context: "Connecting to \(serviceName)")
                    self?.lastError = error.localizedDescription
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
                            log.error("XPC connection interrupted", detail: "Service: \(serviceName). Engine may have crashed, been killed, or there's an interface version mismatch.")
                            self?.handleDisconnection(reason: "XPC interrupted (\(serviceName)) - engine may have crashed or been killed")
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
            log.warning("Disconnected from engine", detail: "\(wasMode?.shortName ?? "?"): \(reason) (session: \(sessionDuration))")
        } else {
            log.warning("Connection failed", detail: reason)
        }

        connectedAt = nil
    }

    /// Disconnect from TalkieEngine
    public func disconnect() {
        log.info("Disconnecting...")
        handleDisconnection(reason: "User requested disconnect")
    }

    /// Reconnect to the engine
    public func reconnect() {
        log.info("Reconnecting...")
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
                log.info("Retry attempt", detail: "\(attempt)/3")

                // Clean reset for retry - don't use handleDisconnection() as it triggers
                // the debug→dev fallback which races with our retry loop
                connection?.invalidate()
                connection = nil
                engineProxy = nil
                connectionState = .disconnected

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
            log.info("TalkieEngine already running")
            return
        }

        log.info("Launching TalkieEngine...")

        // Try to launch from /Applications
        let engineURL = URL(fileURLWithPath: "/Applications/TalkieEngine.app")
        if FileManager.default.fileExists(atPath: engineURL.path) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false // Don't bring to front
            do {
                try await NSWorkspace.shared.openApplication(at: engineURL, configuration: config)
                log.info("TalkieEngine launched")
            } catch {
                log.error("Failed to launch TalkieEngine", error: error)
            }
        } else {
            log.error("TalkieEngine not found", detail: "/Applications/TalkieEngine.app")
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
    ///   - externalRefId: Optional reference ID for correlating with Engine traces (deep link support)
    ///   - priority: Task priority (defaults to .high for real-time TalkieLive transcription)
    ///   - postProcess: Optional post-processing to apply (default: .none = raw transcription)
    public func transcribe(audioPath: String, modelId: String = "parakeet:v3", externalRefId: String? = nil, priority: TranscriptionPriority = .high, postProcess: PostProcessOption = .none) async throws -> String {
        guard let proxy = engineProxy else {
            // Try to connect first
            let connected = await ensureConnected()
            guard connected, let proxy = engineProxy else {
                throw EngineClientError.notConnected
            }
            return try await transcribeWithRetry(proxy: proxy, audioPath: audioPath, modelId: modelId, externalRefId: externalRefId, priority: priority, postProcess: postProcess)
        }

        return try await transcribeWithRetry(proxy: proxy, audioPath: audioPath, modelId: modelId, externalRefId: externalRefId, priority: priority, postProcess: postProcess)
    }

    /// Transcribe with automatic retry for "Already transcribing" errors
    /// This handles the case where engine is busy loading a model (can take 60+ seconds)
    /// or processing another transcription
    private func transcribeWithRetry(proxy: TalkieEngineProtocol, audioPath: String, modelId: String, externalRefId: String?, priority: TranscriptionPriority, postProcess: PostProcessOption) async throws -> String {
        let maxAttempts = 30  // 30 attempts × 2s = 60s max wait
        let retryDelay: UInt64 = 2_000_000_000  // 2 seconds

        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                return try await doTranscribe(proxy: proxy, audioPath: audioPath, modelId: modelId, externalRefId: externalRefId, priority: priority, postProcess: postProcess)
            } catch let error as EngineClientError {
                // Check if it's "Already transcribing" - wait and retry
                if case .transcriptionFailed(let message) = error, message.contains("Already transcribing") {
                    log.info("Engine busy, waiting", detail: "attempt \(attempt)/\(maxAttempts)")
                    lastError = error
                    try? await Task.sleep(nanoseconds: retryDelay)
                    continue
                }
                // Other errors - don't retry
                throw error
            }
        }

        // Exhausted retries
        log.error("Engine still busy after max attempts", detail: "\(maxAttempts) attempts (~60s)")
        throw lastError ?? EngineClientError.transcriptionFailed("Engine busy timeout")
    }

    private func doTranscribe(proxy: TalkieEngineProtocol, audioPath: String, modelId: String, externalRefId: String?, priority: TranscriptionPriority, postProcess: PostProcessOption) async throws -> String {
        let fileName = URL(fileURLWithPath: audioPath).lastPathComponent
        log.info("Transcribing", detail: "'\(fileName)' with model '\(modelId)' priority=\(priority.displayName)")

        let startTime = Date()
        // Use generous timeout - transcription should complete, not timeout
        // Long audio files can take time, and the user is waiting
        let timeoutSeconds: Double = 120.0

        // Start XPC round-trip signpost for Instruments profiling
        let signpostID = OSSignpostID(log: xpcSignpostLog)
        os_signpost(.begin, log: xpcSignpostLog, name: "XPC Transcribe", signpostID: signpostID,
                    "file=%{public}s model=%{public}s", fileName, modelId)

        // Use a continuation wrapper that ensures exactly one resume
        // This prevents leaks when XPC connection dies or timeout fires
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            // Track if we've already resumed to prevent double-resume
            var hasResumed = false
            let lock = NSLock()

            func resumeOnce(with result: Result<String, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true

                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            // Start timeout timer
            let timeoutWork = DispatchWorkItem {
                // End signpost on timeout
                os_signpost(.end, log: xpcSignpostLog, name: "XPC Transcribe", signpostID: signpostID, "timeout")
                resumeOnce(with: .failure(EngineClientError.transcriptionFailed("Timeout after \(Int(timeoutSeconds))s - engine may have disconnected")))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWork)

            // Make XPC call
            proxy.transcribe(audioPath: audioPath, modelId: modelId, externalRefId: externalRefId, priority: priority, postProcess: postProcess) { [weak self] transcript, error in
                // Cancel timeout since we got a response
                timeoutWork.cancel()

                if let error = error {
                    // End signpost with error
                    os_signpost(.end, log: xpcSignpostLog, name: "XPC Transcribe", signpostID: signpostID, "error=%{public}s", error)
                    resumeOnce(with: .failure(EngineClientError.transcriptionFailed(error)))
                } else if let transcript = transcript {
                    // Update stats on success
                    if let self = self {
                        let elapsed = Date().timeIntervalSince(startTime)
                        self.transcriptionCount += 1
                        self.lastTranscriptionAt = Date()
                        let wordCount = transcript.split(separator: " ").count
                        let charCount = transcript.count

                        // End signpost with result metadata
                        os_signpost(.end, log: xpcSignpostLog, name: "XPC Transcribe", signpostID: signpostID,
                                    "elapsed=%.0fms words=%d chars=%d", elapsed * 1000, wordCount, charCount)

                        log.info("Transcription completed", detail: "#\(self.transcriptionCount) in \(String(format: "%.1f", elapsed))s (\(wordCount) words)")
                    } else {
                        os_signpost(.end, log: xpcSignpostLog, name: "XPC Transcribe", signpostID: signpostID, "success")
                    }
                    resumeOnce(with: .success(transcript))
                } else {
                    os_signpost(.end, log: xpcSignpostLog, name: "XPC Transcribe", signpostID: signpostID, "empty")
                    resumeOnce(with: .failure(EngineClientError.emptyResponse))
                }
            }
        }
    }

    // MARK: - Model Management

    /// Preload a model for fast transcription
    public func preloadModel(_ modelId: String) async throws {
        log.info("Preloading model", detail: modelId)

        let startTime = Date()
        let timeoutSeconds: Double = 120

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var hasResumed = false
            let lock = NSLock()

            func resumeOnce(with result: Result<Void, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }

            guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
                logXPCError(error, context: "preloadModel(\(modelId))")
                resumeOnce(with: .failure(EngineClientError.preloadFailed("XPC failed: \(error.localizedDescription)")))
            }) as? TalkieEngineProtocol else {
                resumeOnce(with: .failure(EngineClientError.notConnected))
                return
            }

            let timeoutWork = DispatchWorkItem {
                log.error("Preload timeout", detail: "\(Int(timeoutSeconds))s")
                resumeOnce(with: .failure(EngineClientError.preloadFailed("Timeout")))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWork)

            proxy.preloadModel(modelId) { error in
                timeoutWork.cancel()
                let elapsed = Date().timeIntervalSince(startTime)
                if let error = error {
                    log.error("Model preload failed", detail: "\(String(format: "%.1f", elapsed))s: \(error)")
                    resumeOnce(with: .failure(EngineClientError.preloadFailed(error)))
                } else {
                    log.info("Model preloaded", detail: "'\(modelId)' in \(String(format: "%.1f", elapsed))s")
                    resumeOnce(with: .success(()))
                }
            }
        }

        refreshStatus()
    }

    /// Unload current model
    public func unloadModel() async {
        log.info("Unloading model...")

        guard let proxy = engineProxy else {
            log.warning("Cannot unload - not connected")
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            proxy.unloadModel {
                log.info("Model unloaded")
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
                            log.warning("Build mismatch", detail: "App=\(self.isDebugBuild ? "DEBUG" : "RELEASE"), Engine=\(engineDebug ? "DEBUG" : "RELEASE")")
                        } else if self.connectionState == .connectedWrongBuild {
                            // Was mismatched, now correct
                            self.connectionState = .connected
                        }
                    }

                    if let modelId = status.loadedModelId {
                        log.debug("Status", detail: "model='\(modelId)', transcribing=\(status.isTranscribing), debug=\(status.isDebugBuild ?? false)")
                    } else {
                        log.debug("Status", detail: "no model loaded, debug=\(status.isDebugBuild ?? false)")
                    }
                }
            }
        }
    }

    // MARK: - Download Management

    /// Download a model by ID
    public func downloadModel(_ modelId: String) async throws {
        log.info("Downloading model", detail: modelId)

        guard let proxy = engineProxy else {
            log.error("Cannot download - not connected")
            throw EngineClientError.notConnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            proxy.downloadModel(modelId) { error in
                if let error = error {
                    log.error("Download failed", detail: error)
                    continuation.resume(throwing: EngineClientError.downloadFailed(error))
                } else {
                    log.info("Model downloaded", detail: modelId)
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
        log.info("[Engine] Cancelling download...")

        guard let proxy = engineProxy else {
            log.warning("[Engine] Cannot cancel - not connected")
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            proxy.cancelDownload {
                log.info("[Engine] ✓ Download cancelled")
                continuation.resume()
            }
        }

        downloadProgress = nil
    }

    // MARK: - Streaming ASR

    /// Start a streaming ASR session for real-time transcription
    /// - Returns: Session ID (UUID string) for use with feedStreamingASR and stopStreamingASR
    public func startStreamingASR() async throws -> String {
        log.info("Starting streaming ASR session...")

        guard let proxy = engineProxy else {
            let connected = await ensureConnected()
            guard connected, let proxy = engineProxy else {
                throw EngineClientError.notConnected
            }
            return try await doStartStreamingASR(proxy: proxy)
        }

        return try await doStartStreamingASR(proxy: proxy)
    }

    private func doStartStreamingASR(proxy: TalkieEngineProtocol) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            proxy.startStreamingASR { sessionId, error in
                if let error = error {
                    log.error("Streaming ASR start failed", detail: error)
                    continuation.resume(throwing: EngineClientError.streamingASRFailed(error))
                } else if let sessionId = sessionId {
                    log.info("Streaming ASR session started", detail: sessionId.prefix(8).description)
                    continuation.resume(returning: sessionId)
                } else {
                    continuation.resume(throwing: EngineClientError.emptyResponse)
                }
            }
        }
    }

    /// Feed audio data to an active streaming ASR session
    /// - Parameters:
    ///   - sessionId: Session ID from startStreamingASR
    ///   - audio: Float32 16kHz mono audio samples as Data
    /// - Returns: JSON-encoded transcript events (or nil if none)
    public func feedStreamingASR(sessionId: String, audio: Data) async throws -> [StreamingASREvent]? {
        guard let proxy = engineProxy else {
            throw EngineClientError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            proxy.feedStreamingASR(sessionId: sessionId, audio: audio) { eventsJSON, error in
                if let error = error {
                    log.warning("Streaming ASR feed error", detail: error)
                    continuation.resume(throwing: EngineClientError.streamingASRFailed(error))
                } else if let data = eventsJSON {
                    // Decode events
                    if let events = try? JSONDecoder().decode([StreamingASREvent].self, from: data) {
                        continuation.resume(returning: events)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Stop a streaming ASR session and get the final transcript
    /// - Parameter sessionId: Session ID from startStreamingASR
    /// - Returns: Final transcript
    public func stopStreamingASR(sessionId: String) async throws -> String {
        guard let proxy = engineProxy else {
            throw EngineClientError.notConnected
        }

        log.info("Stopping streaming ASR session...", detail: sessionId.prefix(8).description)

        return try await withCheckedThrowingContinuation { continuation in
            proxy.stopStreamingASR(sessionId: sessionId) { transcript, error in
                if let error = error {
                    log.error("Streaming ASR stop failed", detail: error)
                    continuation.resume(throwing: EngineClientError.streamingASRFailed(error))
                } else if let transcript = transcript {
                    let wordCount = transcript.split(separator: " ").count
                    log.info("Streaming ASR session stopped", detail: "\(wordCount) words")
                    continuation.resume(returning: transcript)
                } else {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    /// Refresh available models list
    public func refreshAvailableModels() async {
        log.info("[Models] refreshAvailableModels called, connectionState=\(self.connectionState.rawValue)")

        guard let proxy = engineProxy else {
            log.warning("[Models] Cannot refresh models - engineProxy is nil")
            return
        }

        log.info("[Models] Calling getAvailableModels on XPC proxy...")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            proxy.getAvailableModels { [weak self] modelsJSON in
                Task { @MainActor in
                    log.info("[Models] XPC callback received, data=\(modelsJSON != nil ? "\(modelsJSON!.count) bytes" : "nil")")

                    if let data = modelsJSON {
                        do {
                            let models = try JSONDecoder().decode([ModelInfo].self, from: data)
                            self?.availableModels = models
                            log.info("[Models] ✓ Decoded \(models.count) models: \(models.map { "\($0.id)(\($0.isDownloaded ? "downloaded" : "remote"))" }.joined(separator: ", "))")
                        } catch {
                            log.error("[Models] JSON decode failed: \(error.localizedDescription)")
                            if let jsonString = String(data: data, encoding: .utf8) {
                                log.error("[Models] Raw JSON (first 500 chars): \(jsonString.prefix(500))")
                            }
                        }
                    } else {
                        log.warning("[Models] Engine returned nil for getAvailableModels")
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
    case streamingASRFailed(String)
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
        case .streamingASRFailed(let message):
            return "Streaming ASR failed: \(message)"
        case .emptyResponse:
            return "Empty response from engine"
        }
    }
}

// MARK: - Streaming ASR Types

/// Event emitted by streaming ASR (matches pod output format)
public struct StreamingASREvent: Codable, Sendable {
    public let type: String
    public let text: String?
    public let confidence: Double?
    public let isFinal: Bool?
    public let silenceDuration: Double?
    public let message: String?
    public let isFatal: Bool?

    /// Whether this is a transcript event
    public var isTranscript: Bool {
        type == "transcript"
    }

    /// Whether this is a speech start event
    public var isSpeechStart: Bool {
        type == "speechStart"
    }

    /// Whether this is a speech end event
    public var isSpeechEnd: Bool {
        type == "speechEnd"
    }

    /// Whether this is an error event
    public var isError: Bool {
        type == "error"
    }
}
