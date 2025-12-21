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

    /// Convert to TalkieEnvironment
    public var environment: TalkieEnvironment {
        switch self {
        case .production: return .production
        case .staging: return .staging
        case .dev: return .dev
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

    /// Format model ID for display with family name (e.g., "Parakeet v3" instead of "parakeet:v3")
    public static func formatModelName(_ fullId: String) -> String {
        let (family, id) = parseModelId(fullId)

        // Convert family to display name
        let familyDisplayName: String
        switch family.lowercased() {
        case "whisper":
            familyDisplayName = "Whisper"
        case "parakeet":
            familyDisplayName = "Parakeet"
        default:
            familyDisplayName = family.capitalized
        }

        // Clean up the model ID
        let cleanId = id
            .replacingOccurrences(of: "openai_whisper-", with: "")
            .replacingOccurrences(of: "distil-whisper_distil-", with: "distil-")

        return "\(familyDisplayName) \(cleanId)"
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

    // MARK: - Model Management State
    @Published public var availableModels: [ModelInfo] = []
    @Published public var downloadProgress: DownloadProgress?
    @Published public var isDownloading: Bool = false

    /// Computed property for backwards compatibility
    public var isConnected: Bool { connectionState == .connected }

    // XPC service manager with environment-aware connection
    private let xpcManager: XPCServiceManager<TalkieEngineProtocol>

    /// The mode we're currently connected to (for UI display)
    public var connectedMode: EngineServiceMode? {
        xpcManager.connectedMode.map { EngineServiceMode(from: $0) }
    }

    private init() {
        // Initialize XPC manager with environment-aware service names
        self.xpcManager = XPCServiceManager<TalkieEngineProtocol>(
            serviceNameProvider: { env in env.engineXPCService },
            interfaceProvider: {
                NSXPCInterface(with: TalkieEngineProtocol.self)
            }
        )

        logger.info("[Engine] Client initialized")
    }

    // MARK: - Connection Management

    /// Connect to engine based on current environment
    public func connect() {
        guard !xpcManager.isConnected else {
            NSLog("[EngineClient] ⚠️ Already connected, skipping")
            return
        }

        let environment = TalkieEnvironment.current
        NSLog("[EngineClient] 🔌 Connecting to \(environment.displayName) engine")
        logger.info("[Engine] Connecting to \(environment.displayName) engine")

        connectionState = .connecting

        Task {
            // Attempt initial connection
            await xpcManager.connect()

            // Poll for connection success (max 3 seconds)
            var attempts = 0
            let maxAttempts = 30 // 30 * 100ms = 3 seconds

            while attempts < maxAttempts {
                if xpcManager.isConnected {
                    // Connection succeeded, verify with ping
                    await verifyConnection()
                    return
                }

                // Wait 100ms before checking again
                try? await Task.sleep(for: .milliseconds(100))
                attempts += 1
            }

            // Timeout - connection failed
            connectionState = .error
            lastError = "Failed to connect to engine (timeout after 3s)"
            logger.error("[Engine] ❌ Failed to connect after \(attempts) attempts")
        }
    }

    /// Verify connection by sending ping
    private func verifyConnection() async {
        guard let proxy = xpcManager.remoteObjectProxy() else {
            connectionState = .error
            lastError = "No proxy available"
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            proxy.ping { [weak self] pong in
                Task { @MainActor [weak self] in
                    guard let self = self else {
                        continuation.resume()
                        return
                    }

                    if pong {
                        self.connectionState = .connected
                        self.connectedAt = Date()
                        self.lastError = nil

                        if let mode = self.connectedMode {
                            NSLog("[EngineClient] ✓ Connected to \(mode.displayName)")
                            logger.info("[Engine] ✓ Connected to \(mode.displayName)")
                        }

                        // Refresh status and fetch models
                        self.refreshStatus()
                        Task {
                            await self.fetchAvailableModels()
                        }
                    } else {
                        self.connectionState = .error
                        self.lastError = "Engine ping failed"
                        self.xpcManager.disconnect()
                    }

                    continuation.resume()
                }
            }
        }
    }

    public func disconnect() {
        xpcManager.disconnect()
        connectionState = .disconnected
        connectedAt = nil
        status = nil
    }

    public func reconnect() {
        disconnect()
        connect()
    }

    public func ensureConnected() async -> Bool {
        if xpcManager.isConnected {
            return true
        }

        connect()

        // Wait for connection to complete (max 5 seconds)
        for _ in 0..<50 {
            if connectionState == .connected {
                return true
            }
            if connectionState == .error {
                return false
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        return false
    }

    private func handleDisconnection(reason: String) {
        NSLog("[EngineClient] ⚠️ Disconnected: \(reason)")
        logger.warning("[Engine] Disconnected: \(reason)")

        connectionState = .disconnected
        status = nil
        lastError = reason
    }

    // MARK: - Transcription

    /// Transcribe audio data
    public func transcribe(audioData: Data, modelId: String = "whisper:openai_whisper-small") async throws -> String {
        guard await ensureConnected() else {
            throw NSError(domain: "EngineClient", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Engine not connected"
            ])
        }

        // Write audio data to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let audioPath = tempDir.appendingPathComponent("\(UUID().uuidString).wav").path

        try audioData.write(to: URL(fileURLWithPath: audioPath))

        defer {
            try? FileManager.default.removeItem(atPath: audioPath)
        }

        return try await transcribe(audioPath: audioPath, modelId: modelId)
    }

    /// Transcribe audio file
    public func transcribe(audioPath: String, modelId: String = "whisper:openai_whisper-small") async throws -> String {
        guard let proxy = xpcManager.remoteObjectProxy() else {
            throw NSError(domain: "EngineClient", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Engine proxy not available"
            ])
        }

        logger.info("[Engine] Transcribing \(audioPath) with \(modelId)")

        return try await withCheckedThrowingContinuation { continuation in
            proxy.transcribe(audioPath: audioPath, modelId: modelId) { [weak self] transcript, error in
                Task { @MainActor [weak self] in
                    self?.transcriptionCount += 1
                    self?.lastTranscriptionAt = Date()
                    self?.refreshStatus()

                    if let error = error {
                        logger.error("[Engine] Transcription error: \(error)")
                        continuation.resume(throwing: NSError(
                            domain: "EngineClient",
                            code: -2,
                            userInfo: [NSLocalizedDescriptionKey: error]
                        ))
                    } else if let transcript = transcript {
                        logger.info("[Engine] ✓ Transcription complete (\(transcript.count) chars)")
                        continuation.resume(returning: transcript)
                    } else {
                        logger.error("[Engine] Transcription returned nil")
                        continuation.resume(throwing: NSError(
                            domain: "EngineClient",
                            code: -3,
                            userInfo: [NSLocalizedDescriptionKey: "Transcription returned nil"]
                        ))
                    }
                }
            }
        }
    }

    // MARK: - Model Management

    public func preloadModel(_ modelId: String) async throws {
        guard let proxy = xpcManager.remoteObjectProxy() else {
            throw NSError(domain: "EngineClient", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Engine not connected"
            ])
        }

        logger.info("[Engine] Preloading model: \(modelId)")

        return try await withCheckedThrowingContinuation { continuation in
            proxy.preloadModel(modelId) { error in
                Task { @MainActor in
                    if let error = error {
                        logger.error("[Engine] Preload error: \(error)")
                        continuation.resume(throwing: NSError(
                            domain: "EngineClient",
                            code: -4,
                            userInfo: [NSLocalizedDescriptionKey: error]
                        ))
                    } else {
                        logger.info("[Engine] ✓ Model preloaded")
                        continuation.resume()
                    }
                }
            }
        }
    }

    public func unloadModel() async {
        guard let proxy = xpcManager.remoteObjectProxy() else {
            logger.warning("[Engine] Cannot unload - not connected")
            return
        }

        logger.info("[Engine] Unloading model")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            proxy.unloadModel {
                Task { @MainActor in
                    logger.info("[Engine] ✓ Model unloaded")
                    continuation.resume()
                }
            }
        }
    }

    public func fetchAvailableModels() async {
        guard let proxy = xpcManager.remoteObjectProxy() else {
            logger.warning("[Engine] Cannot fetch models - not connected")
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            proxy.getAvailableModels { [weak self] modelsJSON in
                Task { @MainActor [weak self] in
                    guard let self = self else {
                        continuation.resume()
                        return
                    }

                    if let data = modelsJSON,
                       let models = try? JSONDecoder().decode([ModelInfo].self, from: data) {
                        self.availableModels = models
                        logger.info("[Engine] ✓ Fetched \(models.count) models")
                    } else {
                        logger.warning("[Engine] Failed to decode models")
                    }

                    continuation.resume()
                }
            }
        }
    }

    public func downloadModel(_ modelId: String) async throws {
        guard let proxy = xpcManager.remoteObjectProxy() else {
            throw NSError(domain: "EngineClient", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Engine not connected"
            ])
        }

        logger.info("[Engine] Downloading model: \(modelId)")
        isDownloading = true

        return try await withCheckedThrowingContinuation { continuation in
            proxy.downloadModel(modelId) { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.isDownloading = false

                    if let error = error {
                        logger.error("[Engine] Download error: \(error)")
                        continuation.resume(throwing: NSError(
                            domain: "EngineClient",
                            code: -5,
                            userInfo: [NSLocalizedDescriptionKey: error]
                        ))
                    } else {
                        logger.info("[Engine] ✓ Download complete")
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
            Task { @MainActor [weak self] in
                if let data = progressJSON,
                   let progress = try? JSONDecoder().decode(DownloadProgress.self, from: data) {
                    self?.downloadProgress = progress
                    self?.isDownloading = progress.isDownloading
                }
            }
        }
    }

    public func cancelDownload() async {
        guard let proxy = xpcManager.remoteObjectProxy() else {
            logger.warning("[Engine] Cannot cancel - not connected")
            return
        }

        logger.info("[Engine] Cancelling download")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            proxy.cancelDownload {
                Task { @MainActor in
                    logger.info("[Engine] ✓ Download cancelled")
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Status

    public func refreshStatus() {
        guard let proxy = xpcManager.remoteObjectProxy() else { return }

        proxy.getStatus { [weak self] statusJSON in
            Task { @MainActor [weak self] in
                if let data = statusJSON,
                   let status = try? JSONDecoder().decode(EngineStatus.self, from: data) {
                    self?.status = status
                }
            }
        }
    }
}
