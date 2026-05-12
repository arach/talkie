//
//  EngineClient.swift
//  Talkie
//
//  XPC client for the engine hosted inside TalkieAgent.
//  Handles transcription requests, model management, and downloads.
//
//  Connection state is managed by ServiceManager.shared.engine
//  This client focuses purely on XPC operations.
//

import Foundation
import AppKit
import Combine
import os
import TalkieKit
import Observation

private let logger = Logger(subsystem: "to.talkie.app.mac", category: "EngineClient")

// MARK: - Backwards Compatibility

/// Alias for backwards compatibility
public typealias ModelInfo = EngineModelInfo

/// Alias for backwards compatibility - use TalkieEnvironment directly
public typealias EngineServiceMode = TalkieEnvironment

extension TalkieEnvironment {
    /// For backwards compatibility with EngineServiceMode
    public var environment: TalkieEnvironment { self }
}

// MARK: - Engine Status Types

/// Engine status from the embedded engine
public struct EngineStatus: Codable, Sendable {
    public let pid: Int32?
    public let isDebugBuild: Bool?
    public let loadedModelId: String?
    public let isTranscribing: Bool
    public let isWarmingUp: Bool
    public let downloadedModels: [String]
}

/// Download progress from the embedded engine
public struct DownloadProgress: Codable, Sendable {
    public let modelId: String
    public let progress: Double
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

/// Connection state for UI display
public enum EngineConnectionState: String {
    case disconnected = "Disconnected"
    case connecting = "Connecting..."
    case connected = "Connected"
    case error = "Error"
}

/// Model info from the embedded engine
/// Model status for UI display (combines catalog + engine state)
public struct ModelStatusInfo {
    public let isDownloaded: Bool
    public let isLoaded: Bool
    public let isDownloading: Bool
    public let downloadProgress: Double

    public static let unknown = ModelStatusInfo(
        isDownloaded: false,
        isLoaded: false,
        isDownloading: false,
        downloadProgress: 0
    )
}

public struct EngineModelInfo: Codable, Sendable, Identifiable {
    public let id: String
    public let family: String
    public let modelId: String
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

    public static func formatModelName(_ fullId: String) -> String {
        let (family, id) = parseModelId(fullId)

        let familyDisplayName: String
        switch family.lowercased() {
        case "whisper": familyDisplayName = "Whisper"
        case "parakeet": familyDisplayName = "Parakeet"
        default: familyDisplayName = family.capitalized
        }

        let cleanId = id
            .replacingOccurrences(of: "openai_whisper-", with: "")
            .replacingOccurrences(of: "distil-whisper_distil-", with: "distil-")

        return "\(familyDisplayName) \(cleanId)"
    }
}

// MARK: - Engine Client

@MainActor
@Observable
public final class EngineClient {
    public static let shared = EngineClient()

    // ─── Model Management ───
    public var availableModels: [EngineModelInfo] = []
    public var downloadProgress: DownloadProgress?
    public var isDownloading: Bool = false

    // ─── Session Stats ───
    public private(set) var transcriptionCount: Int = 0
    public private(set) var lastTranscriptionAt: Date?

    // ─── Status (for backwards compatibility) ───
    public private(set) var status: EngineStatus?
    public var connectionState: EngineConnectionState {
        if xpcManager.isConnected { return .connected }
        if xpcManager.connectionState == .connecting { return .connecting }
        return .disconnected
    }

    // ─── Private ───
    @ObservationIgnored
    private let xpcManager: XPCServiceManager<TalkieAgentXPCServiceProtocol>

    @ObservationIgnored
    private var remoteTransport: WebSocketEngineTransport?

    /// Connected environment (nil if not connected)
    public var connectedMode: TalkieEnvironment? {
        xpcManager.connectedMode
    }

    /// Whether XPC is connected (or remote WebSocket is connected)
    public var isConnected: Bool {
        if isRemoteMode { return remoteTransport?.isConnected ?? false }
        return xpcManager.isConnected
    }

    /// Whether remote engine mode is active
    public var isRemoteMode: Bool {
        TalkieSharedSettings.bool(forKey: AgentSettingsKey.remoteEngineEnabled)
    }

    /// The configured remote host
    private var remoteHost: String {
        TalkieSharedSettings.string(forKey: AgentSettingsKey.remoteEngineHost) ?? ""
    }

    /// The configured remote port
    private var remotePort: Int {
        let port = TalkieSharedSettings.integer(forKey: AgentSettingsKey.remoteEnginePort)
        return port > 0 ? port : 19821
    }

    private init() {
        StartupProfiler.shared.mark("singleton.EngineClient.start")
        xpcManager = XPCServiceManager<TalkieAgentXPCServiceProtocol>(
            serviceNameProvider: { env in env.liveXPCService },
            interfaceProvider: { NSXPCInterface(with: TalkieAgentXPCServiceProtocol.self) }
        )
        xpcManager.preferredEnvironmentProvider = { ServiceManager.shared.effectiveHelperEnvironment }
        xpcManager.allowsCrossEnvironmentFallback = false

        // Verify connections with a real ping (prevents false-connected state)
        xpcManager.connectionVerifier = { proxy in
            await withCheckedContinuation { continuation in
                var resumed = false
                let lock = NSLock()

                // Timeout after 2s
                DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                    lock.lock()
                    guard !resumed else { lock.unlock(); return }
                    resumed = true
                    lock.unlock()
                    continuation.resume(returning: false)
                }

                proxy.ping { pong in
                    lock.lock()
                    guard !resumed else { lock.unlock(); return }
                    resumed = true
                    lock.unlock()
                    continuation.resume(returning: pong)
                }
            }
        }

        StartupProfiler.shared.mark("singleton.EngineClient.done")
    }

    // MARK: - Connection

    /// Connect to the embedded engine (XPC via TalkieAgent, or remote WebSocket)
    public func connect() {
        if isRemoteMode {
            connectRemote()
            return
        }

        guard !xpcManager.isConnected else {
            logger.info("[EngineClient] Already connected")
            return
        }

        logger.info("[EngineClient] Connecting...")

        Task {
            await xpcManager.connect()

            // Poll for connection (max 3 seconds)
            var attempts = 0
            while attempts < 30 {
                if xpcManager.isConnected {
                    await verifyConnection()
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
                attempts += 1
            }

            logger.error("[EngineClient] Connection timeout")
        }
    }

    /// Connect to a remote TalkieEngine via WebSocket
    private func connectRemote() {
        let host = remoteHost
        let port = remotePort
        guard !host.isEmpty else {
            logger.error("[EngineClient] Remote engine host not configured")
            return
        }

        logger.info("[EngineClient] Connecting to remote engine at \(host):\(port)")

        Task {
            do {
                let transport = WebSocketEngineTransport()
                try await transport.connect(host: host, port: port)
                self.remoteTransport = transport

                // Update ServiceManager
                if !AppMode.isLite {
                    ServiceManager.shared.engine.updateConnectionState(connected: true, environment: nil)
                }

                // Fetch initial data
                refreshStatus()
                await fetchAvailableModels()

                logger.info("[EngineClient] Remote engine connected")
            } catch {
                logger.error("[EngineClient] Remote connection failed: \(error.localizedDescription)")
            }
        }
    }

    private func verifyConnection() async {
        // Use error-handling proxy to ensure we always get a callback
        // Debug level since engine being unavailable is normal (it's optional)
        guard let proxy = xpcManager.remoteObjectProxy(errorHandler: { error in
            logger.debug("[EngineClient] Verify connection error: \(error.localizedDescription)")
        }) else { return }

        // Use a flag to ensure we only resume once
        let resumed = OSAllocatedUnfairLock(initialState: false)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // Set a timeout to prevent hanging forever
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    logger.debug("[EngineClient] Verify connection timed out")
                    continuation.resume()
                }
            }

            proxy.ping { [weak self] pong in
                // Only resume if we haven't already (timeout might have fired)
                guard resumed.withLock({ old in let was = old; old = true; return !was }) else { return }

                Task { @MainActor in
                    if pong {
                        logger.info("[EngineClient] Connected to \(self?.connectedMode?.displayName ?? "unknown")")

                        // Update ServiceManager (skip in lite mode)
                        if !AppMode.isLite {
                            ServiceManager.shared.engine.updateConnectionState(
                                connected: true,
                                environment: self?.connectedMode
                            )
                        }

                        // Fetch initial data
                        self?.refreshStatus()
                        Task { await self?.fetchAvailableModels() }

                        // Re-sync dictionary in case it loaded before engine was ready
                        if DictionaryManager.shared.isLoaded {
                            DictionaryManager.shared.syncToEngine()
                        }
                    }
                    continuation.resume()
                }
            }
        }
    }

    public func disconnect() {
        remoteTransport?.disconnect()
        remoteTransport = nil
        xpcManager.disconnect()
        if !AppMode.isLite {
            ServiceManager.shared.engine.updateConnectionState(connected: false, environment: nil)
        }
    }

    /// Force reconnect - drops current connection and rescans for engine
    /// Use when a new engine instance has been launched and needs to be picked up
    public func reconnect() {
        logger.info("[EngineClient] Force reconnecting...")
        disconnect()

        // Small delay to ensure clean disconnect
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            connect()
        }
    }

    public func ensureConnected() async -> Bool {
        if isRemoteMode {
            if remoteTransport?.isConnected == true { return true }
            connectRemote()
            let start = Date()
            while Date().timeIntervalSince(start) < 5.0 {
                if remoteTransport?.isConnected == true { return true }
                try? await Task.sleep(for: .milliseconds(100))
            }
            return false
        }

        if xpcManager.isConnected { return true }

        connect()

        let start = Date()
        while Date().timeIntervalSince(start) < 5.0 {
            if xpcManager.isConnected { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    // MARK: - Transcription

    /// Transcribe audio data
    /// - Parameters:
    ///   - audioData: Audio data to transcribe
    ///   - modelId: Model to use (default: small whisper)
    ///   - priority: Task priority - `.high` for real-time, `.medium` for interactive, `.low` for batch (default: .medium)
    ///   - postProcess: Optional post-processing to apply (default: .none = raw transcription)
    public func transcribe(
        audioData: Data,
        modelId: String = TalkieDefaults.dictationModelId,
        priority: TranscriptionPriority = .medium,
        postProcess: PostProcessOption = .none
    ) async throws -> String {
        guard await ensureConnected() else {
            throw NSError(domain: "EngineClient", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Embedded engine not connected"])
        }

        // Remote mode: send audio data directly over WebSocket (no temp file needed)
        if isRemoteMode, let transport = remoteTransport {
            logger.info("[EngineClient] Remote transcribing \(audioData.count) bytes")
            let transcript = try await transport.transcribe(
                audioData: audioData, modelId: modelId,
                priority: priority, postProcess: postProcess
            )
            transcriptionCount += 1
            lastTranscriptionAt = Date()
            return transcript
        }

        let audioPath = try await Task.detached {
            let tempDir = FileManager.default.temporaryDirectory
            let path = tempDir.appendingPathComponent("\(UUID().uuidString).wav")
            try audioData.write(to: path)
            return path.path
        }.value

        defer {
            Task.detached { try? FileManager.default.removeItem(atPath: audioPath) }
        }

        return try await transcribe(audioPath: audioPath, modelId: modelId, priority: priority, postProcess: postProcess)
    }

    /// Transcribe audio file
    /// - Parameters:
    ///   - audioPath: Path to audio file
    ///   - modelId: Model to use (default: TalkieDefaults.dictationModelId)
    ///   - priority: Task priority - `.high` for real-time (Live), `.medium` for interactive, `.low` for batch (default: .medium)
    ///   - postProcess: Optional post-processing to apply (default: .none = raw transcription)
    public func transcribe(
        audioPath: String,
        modelId: String = TalkieDefaults.dictationModelId,
        priority: TranscriptionPriority = .medium,
        postProcess: PostProcessOption = .none
    ) async throws -> String {
        guard await ensureConnected() else {
            throw NSError(domain: "EngineClient", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Embedded engine not connected"])
        }

        // Remote mode: read file into Data and send over WebSocket
        if isRemoteMode, let transport = remoteTransport {
            logger.info("[EngineClient] Remote transcribing file \(audioPath)")
            let audioData = try Data(contentsOf: URL(fileURLWithPath: audioPath))
            let transcript = try await transport.transcribe(
                audioData: audioData, modelId: modelId,
                priority: priority, postProcess: postProcess
            )
            transcriptionCount += 1
            lastTranscriptionAt = Date()
            refreshStatus()
            return transcript
        }

        logger.info("[EngineClient] Transcribing \(audioPath) (priority: \(priority.displayName))")

        let timeoutSeconds: Double = 120

        return try await withCheckedThrowingContinuation { continuation in
            // Track if we've already resumed to prevent double-resume or leaks
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

            // Get proxy with error handler that can resume the continuation
            guard let proxy = xpcManager.remoteObjectProxy(errorHandler: { error in
                logger.error("[EngineClient] XPC error: \(error.localizedDescription)")
                resumeOnce(with: .failure(NSError(domain: "EngineClient", code: -4,
                                                  userInfo: [NSLocalizedDescriptionKey: "XPC failed: \(error.localizedDescription)"])))
            }) else {
                resumeOnce(with: .failure(NSError(domain: "EngineClient", code: -1,
                                                  userInfo: [NSLocalizedDescriptionKey: "TalkieAgent engine proxy not available"])))
                return
            }

            // Start timeout timer
            let timeoutWork = DispatchWorkItem {
                logger.error("[EngineClient] Transcription timeout after \(Int(timeoutSeconds))s")
                resumeOnce(with: .failure(NSError(domain: "EngineClient", code: -5,
                                                  userInfo: [NSLocalizedDescriptionKey: "Timeout after \(Int(timeoutSeconds))s"])))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWork)

            // Make XPC call
            proxy.transcribe(audioPath: audioPath, modelId: modelId, externalRefId: nil, priority: priority, postProcess: postProcess) { [weak self] transcript, error in
                // Cancel timeout since we got a response
                timeoutWork.cancel()

                Task { @MainActor in
                    self?.transcriptionCount += 1
                    self?.lastTranscriptionAt = Date()
                    self?.refreshStatus()
                }

                if let error = error {
                    logger.error("[EngineClient] Transcription error: \(error)")
                    resumeOnce(with: .failure(NSError(domain: "EngineClient", code: -2,
                                                      userInfo: [NSLocalizedDescriptionKey: error])))
                } else if let transcript = transcript {
                    logger.info("[EngineClient] Transcribed \(transcript.count) chars")
                    resumeOnce(with: .success(transcript))
                } else {
                    resumeOnce(with: .failure(NSError(domain: "EngineClient", code: -3,
                                                      userInfo: [NSLocalizedDescriptionKey: "Nil result"])))
                }
            }
        }
    }

    // MARK: - Transcription with Timings

    /// Transcribe audio file and return word-level timestamps
    /// Falls back to plain transcription (nil timing data) if engine doesn't support the new method
    public func transcribeWithTimings(
        audioPath: String,
        modelId: String = TalkieDefaults.dictationModelId,
        priority: TranscriptionPriority = .medium,
        postProcess: PostProcessOption = .none
    ) async throws -> (transcript: String, timedTranscription: TimedTranscription?) {
        guard await ensureConnected() else {
            throw NSError(domain: "EngineClient", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Embedded engine not connected"])
        }

        // Remote mode: read file into Data and send over WebSocket
        if isRemoteMode, let transport = remoteTransport {
            logger.info("[EngineClient] Remote transcribing with timings \(audioPath)")
            let audioData = try Data(contentsOf: URL(fileURLWithPath: audioPath))
            let result = try await transport.transcribeWithTimings(
                audioData: audioData, modelId: modelId,
                priority: priority, postProcess: postProcess
            )
            transcriptionCount += 1
            lastTranscriptionAt = Date()
            refreshStatus()
            return result
        }

        logger.info("[EngineClient] Transcribing with timings \(audioPath)")

        let timeoutSeconds: Double = 120

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let lock = NSLock()

            func resumeOnce(with result: Result<(String, TimedTranscription?), Error>) {
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

            guard let proxy = xpcManager.remoteObjectProxy(errorHandler: { error in
                logger.error("[EngineClient] XPC error: \(error.localizedDescription)")
                resumeOnce(with: .failure(NSError(domain: "EngineClient", code: -4,
                                                  userInfo: [NSLocalizedDescriptionKey: "XPC failed: \(error.localizedDescription)"])))
            }) else {
                resumeOnce(with: .failure(NSError(domain: "EngineClient", code: -1,
                                                  userInfo: [NSLocalizedDescriptionKey: "TalkieAgent engine proxy not available"])))
                return
            }

            let timeoutWork = DispatchWorkItem {
                logger.error("[EngineClient] Transcription timeout after \(Int(timeoutSeconds))s")
                resumeOnce(with: .failure(NSError(domain: "EngineClient", code: -5,
                                                  userInfo: [NSLocalizedDescriptionKey: "Timeout after \(Int(timeoutSeconds))s"])))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWork)

            proxy.transcribeWithTimings(audioPath: audioPath, modelId: modelId, externalRefId: nil, priority: priority, postProcess: postProcess) { [weak self] transcript, segmentsJSON, error in
                timeoutWork.cancel()

                Task { @MainActor in
                    self?.transcriptionCount += 1
                    self?.lastTranscriptionAt = Date()
                    self?.refreshStatus()
                }

                if let error = error {
                    logger.error("[EngineClient] Transcription error: \(error)")
                    resumeOnce(with: .failure(NSError(domain: "EngineClient", code: -2,
                                                      userInfo: [NSLocalizedDescriptionKey: error])))
                } else if let transcript = transcript {
                    let timed = segmentsJSON.flatMap { TimedTranscription.from(data: $0) }
                    logger.info("[EngineClient] Transcribed \(transcript.count) chars, \(timed?.words.count ?? 0) word timings")
                    resumeOnce(with: .success((transcript, timed)))
                } else {
                    resumeOnce(with: .failure(NSError(domain: "EngineClient", code: -3,
                                                      userInfo: [NSLocalizedDescriptionKey: "Nil result"])))
                }
            }
        }
    }

    // MARK: - Model Management

    public func preloadModel(_ modelId: String) async throws {
        // Remote mode
        if isRemoteMode, let transport = remoteTransport {
            logger.info("[EngineClient] Remote preloading \(modelId)")
            try await transport.preloadModel(modelId)
            logger.info("[EngineClient] Remote model preloaded")
            return
        }

        guard let proxy = xpcManager.remoteObjectProxy() else {
            throw NSError(domain: "EngineClient", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Embedded engine not connected"])
        }

        logger.info("[EngineClient] Preloading \(modelId)")

        return try await withCheckedThrowingContinuation { continuation in
            proxy.preloadModel(modelId) { error in
                if let error = error {
                    logger.error("[EngineClient] Preload error: \(error)")
                    continuation.resume(throwing: NSError(domain: "EngineClient", code: -4,
                                                          userInfo: [NSLocalizedDescriptionKey: error]))
                } else {
                    logger.info("[EngineClient] Model preloaded")
                    continuation.resume()
                }
            }
        }
    }

    public func unloadModel() async {
        guard let proxy = xpcManager.remoteObjectProxy() else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            proxy.unloadModel {
                logger.info("[EngineClient] Model unloaded")
                continuation.resume()
            }
        }
    }

    public func fetchAvailableModels() async {
        // Remote mode
        if isRemoteMode, let transport = remoteTransport {
            do {
                let data = try await transport.getAvailableModels()
                if let models = try? JSONDecoder().decode([EngineModelInfo].self, from: data) {
                    availableModels = models
                    logger.info("[EngineClient] Fetched \(models.count) remote models")
                }
            } catch {
                logger.error("[EngineClient] Remote fetchModels error: \(error.localizedDescription)")
            }
            return
        }

        guard let proxy = xpcManager.remoteObjectProxy() else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            proxy.getAvailableModels { [weak self] modelsJSON in
                Task { @MainActor in
                    if let data = modelsJSON,
                       let models = try? JSONDecoder().decode([EngineModelInfo].self, from: data) {
                        self?.availableModels = models
                        logger.info("[EngineClient] Fetched \(models.count) models")
                    }
                    continuation.resume()
                }
            }
        }
    }

    public func downloadModel(_ modelId: String) async throws {
        guard let proxy = xpcManager.remoteObjectProxy() else {
            throw NSError(domain: "EngineClient", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Embedded engine not connected"])
        }

        logger.info("[EngineClient] Downloading \(modelId)")
        isDownloading = true

        return try await withCheckedThrowingContinuation { continuation in
            proxy.downloadModel(modelId) { [weak self] error in
                Task { @MainActor in
                    self?.isDownloading = false

                    if let error = error {
                        logger.error("[EngineClient] Download error: \(error)")
                        continuation.resume(throwing: NSError(domain: "EngineClient", code: -5,
                                                              userInfo: [NSLocalizedDescriptionKey: error]))
                    } else {
                        logger.info("[EngineClient] Download complete")
                        await self?.fetchAvailableModels()
                        continuation.resume()
                    }
                }
            }
        }
    }

    public func refreshDownloadProgress() {
        guard let proxy = xpcManager.remoteObjectProxy() else { return }

        proxy.getDownloadProgress { [weak self] progressJSON in
            Task { @MainActor in
                if let data = progressJSON,
                   let progress = try? JSONDecoder().decode(DownloadProgress.self, from: data) {
                    self?.downloadProgress = progress
                    self?.isDownloading = progress.isDownloading
                }
            }
        }
    }

    public func cancelDownload() async {
        guard let proxy = xpcManager.remoteObjectProxy() else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            proxy.cancelDownload {
                logger.info("[EngineClient] Download cancelled")
                continuation.resume()
            }
        }
    }

    // MARK: - Status

    public func refreshStatus() {
        // Remote mode
        if isRemoteMode, let transport = remoteTransport {
            Task {
                do {
                    let data = try await transport.getStatus()
                    if let status = try? JSONDecoder().decode(EngineStatus.self, from: data) {
                        self.status = status
                        if !AppMode.isLite {
                            ServiceManager.shared.engine.updateStatus(
                                loadedModel: status.loadedModelId,
                                transcribing: status.isTranscribing
                            )
                        }
                    }
                } catch {
                    logger.debug("[EngineClient] Remote status refresh error: \(error.localizedDescription)")
                }
            }
            return
        }

        guard let proxy = xpcManager.remoteObjectProxy() else { return }

        proxy.getStatus { [weak self] statusJSON in
            Task { @MainActor in
                if let data = statusJSON,
                   let status = try? JSONDecoder().decode(EngineStatus.self, from: data) {
                    // Store locally for backwards compatibility
                    self?.status = status

                    // Update ServiceManager with status info (skip in lite mode)
                    if !AppMode.isLite {
                        ServiceManager.shared.engine.updateStatus(
                            loadedModel: status.loadedModelId,
                            transcribing: status.isTranscribing
                        )
                    }
                }
            }
        }
    }

    /// Get model status for a given model ID (combines engine state with download progress)
    public func modelStatus(for modelId: String) -> ModelStatusInfo {
        // Check if currently downloading this model
        if let progress = downloadProgress, progress.modelId == modelId {
            return ModelStatusInfo(
                isDownloaded: false,
                isLoaded: false,
                isDownloading: progress.isDownloading,
                downloadProgress: progress.progress
            )
        }

        // Check engine status for downloaded/loaded state
        let isDownloaded = status?.downloadedModels.contains(modelId) ?? false
        let isLoaded = status?.loadedModelId == modelId

        return ModelStatusInfo(
            isDownloaded: isDownloaded || isLoaded,  // Loaded implies downloaded
            isLoaded: isLoaded,
            isDownloading: false,
            downloadProgress: 0
        )
    }

    // MARK: - Dictionary

    /// Update the dictionary for text post-processing
    /// Talkie pushes content, Engine persists to its own file
    public func updateDictionary(_ entries: [DictionaryEntry]) async throws {
        guard let proxy = xpcManager.remoteObjectProxy() else {
            throw NSError(domain: "EngineClient", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Embedded engine not connected"])
        }

        let entriesJSON = try JSONEncoder().encode(entries)
        logger.info("[EngineClient] Updating dictionary with \(entries.count) entries")

        return try await withCheckedThrowingContinuation { continuation in
            proxy.updateDictionary(entriesJSON: entriesJSON) { error in
                if let error = error {
                    logger.error("[EngineClient] Dictionary update error: \(error)")
                    continuation.resume(throwing: NSError(domain: "EngineClient", code: -6,
                                                          userInfo: [NSLocalizedDescriptionKey: error]))
                } else {
                    logger.info("[EngineClient] Dictionary updated")
                    continuation.resume()
                }
            }
        }
    }

    /// Enable or disable dictionary processing in Engine
    /// Engine persists this setting and loads dictionary on startup if enabled
    public func setDictionaryEnabled(_ enabled: Bool) async {
        guard let proxy = xpcManager.remoteObjectProxy() else {
            logger.warning("[EngineClient] Cannot set dictionary enabled - not connected")
            return
        }

        logger.info("[EngineClient] Setting dictionary enabled: \(enabled)")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            proxy.setDictionaryEnabled(enabled) {
                logger.info("[EngineClient] Dictionary \(enabled ? "enabled" : "disabled")")
                continuation.resume()
            }
        }
    }

    /// Enable or disable symbolic mapping in Engine
    /// Converts spoken symbols like "slash" → "/", "dash" → "-"
    public func setSymbolicMappingEnabled(_ enabled: Bool) async {
        guard let proxy = xpcManager.remoteObjectProxy() else {
            logger.warning("[EngineClient] Cannot set symbolic mapping enabled - not connected")
            return
        }

        logger.info("[EngineClient] Setting symbolic mapping enabled: \(enabled)")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            proxy.setSymbolicMappingEnabled(enabled) {
                logger.info("[EngineClient] Symbolic mapping \(enabled ? "enabled" : "disabled")")
                continuation.resume()
            }
        }
    }

    /// Enable or disable filler-word removal in Engine
    /// Removes conversational fillers like "um"/"uh" from transcript output.
    public func setFillerRemovalEnabled(_ enabled: Bool) async {
        guard let proxy = xpcManager.remoteObjectProxy() else {
            logger.warning("[EngineClient] Cannot set filler removal enabled - not connected")
            return
        }

        logger.info("[EngineClient] Setting filler removal enabled: \(enabled)")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            proxy.setFillerRemovalEnabled(enabled) {
                logger.info("[EngineClient] Filler removal \(enabled ? "enabled" : "disabled")")
                continuation.resume()
            }
        }
    }

    /// Reload symbolic mapping JSON from disk in Engine
    public func reloadSymbolicMapping() async throws {
        guard let proxy = xpcManager.remoteObjectProxy() else {
            throw NSError(domain: "EngineClient", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Embedded engine not connected"])
        }

        logger.info("[EngineClient] Reloading symbolic mapping from file")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            proxy.reloadSymbolicMapping { error in
                if let error = error {
                    logger.error("[EngineClient] Symbolic mapping reload error: \(error)")
                    continuation.resume(throwing: NSError(domain: "EngineClient", code: -6,
                                                          userInfo: [NSLocalizedDescriptionKey: error]))
                } else {
                    logger.info("[EngineClient] Symbolic mapping reloaded")
                    continuation.resume()
                }
            }
        }
    }

}
