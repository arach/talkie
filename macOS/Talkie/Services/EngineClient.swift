//
//  EngineClient.swift
//  Talkie
//
//  XPC client for TalkieEngine transcription.
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

private let logger = Logger(subsystem: "jdi.talkie.core", category: "EngineClient")

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

/// Engine status from TalkieEngine
public struct EngineStatus: Codable, Sendable {
    public let pid: Int32?
    public let isDebugBuild: Bool?
    public let loadedModelId: String?
    public let isTranscribing: Bool
    public let isWarmingUp: Bool
    public let downloadedModels: [String]
}

/// Download progress from TalkieEngine
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

/// Model info from TalkieEngine
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
    private let xpcManager: XPCServiceManager<TalkieEngineProtocol>

    /// Connected environment (nil if not connected)
    public var connectedMode: TalkieEnvironment? {
        xpcManager.connectedMode
    }

    /// Whether XPC is connected
    public var isConnected: Bool {
        xpcManager.isConnected
    }

    private init() {
        xpcManager = XPCServiceManager<TalkieEngineProtocol>(
            serviceNameProvider: { env in env.engineXPCService },
            interfaceProvider: { NSXPCInterface(with: TalkieEngineProtocol.self) }
        )
        logger.info("[EngineClient] Initialized")
    }

    // MARK: - Connection

    /// Connect to TalkieEngine
    public func connect() {
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

    private func verifyConnection() async {
        guard let proxy = xpcManager.remoteObjectProxy() else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            proxy.ping { [weak self] pong in
                Task { @MainActor in
                    if pong {
                        logger.info("[EngineClient] Connected to \(self?.connectedMode?.displayName ?? "unknown")")

                        // Update ServiceManager
                        ServiceManager.shared.engine.updateConnectionState(
                            connected: true,
                            environment: self?.connectedMode
                        )

                        // Fetch initial data
                        self?.refreshStatus()
                        Task { await self?.fetchAvailableModels() }
                    }
                    continuation.resume()
                }
            }
        }
    }

    public func disconnect() {
        xpcManager.disconnect()
        ServiceManager.shared.engine.updateConnectionState(connected: false, environment: nil)
    }

    public func ensureConnected() async -> Bool {
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
        modelId: String = "whisper:openai_whisper-small",
        priority: TranscriptionPriority = .medium,
        postProcess: PostProcessOption = .none
    ) async throws -> String {
        guard await ensureConnected() else {
            throw NSError(domain: "EngineClient", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Engine not connected"])
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
    ///   - modelId: Model to use (default: small whisper)
    ///   - priority: Task priority - `.high` for real-time (Live), `.medium` for interactive, `.low` for batch (default: .medium)
    ///   - postProcess: Optional post-processing to apply (default: .none = raw transcription)
    public func transcribe(
        audioPath: String,
        modelId: String = "whisper:openai_whisper-small",
        priority: TranscriptionPriority = .medium,
        postProcess: PostProcessOption = .none
    ) async throws -> String {
        guard await ensureConnected() else {
            throw NSError(domain: "EngineClient", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "TalkieEngine not connected"])
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
                                                  userInfo: [NSLocalizedDescriptionKey: "Engine proxy not available"])))
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

    // MARK: - Model Management

    public func preloadModel(_ modelId: String) async throws {
        guard let proxy = xpcManager.remoteObjectProxy() else {
            throw NSError(domain: "EngineClient", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Engine not connected"])
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
                         userInfo: [NSLocalizedDescriptionKey: "Engine not connected"])
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
        guard let proxy = xpcManager.remoteObjectProxy() else { return }

        proxy.getStatus { [weak self] statusJSON in
            Task { @MainActor in
                if let data = statusJSON,
                   let status = try? JSONDecoder().decode(EngineStatus.self, from: data) {
                    // Store locally for backwards compatibility
                    self?.status = status

                    // Update ServiceManager with status info
                    ServiceManager.shared.engine.updateStatus(
                        loadedModel: status.loadedModelId,
                        transcribing: status.isTranscribing
                    )
                }
            }
        }
    }

    // MARK: - Dictionary

    /// Update the dictionary for text post-processing
    /// Talkie pushes content, Engine persists to its own file
    public func updateDictionary(_ entries: [DictionaryEntry]) async throws {
        guard let proxy = xpcManager.remoteObjectProxy() else {
            throw NSError(domain: "EngineClient", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Engine not connected"])
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
}
