//
//  EngineProtocol.swift
//  TalkieEngine
//
//  XPC protocol for transcription service
//

import Foundation

/// Mach service name for XPC connection
public let kTalkieEngineServiceName = "jdi.talkie.engine.xpc"

/// XPC protocol for TalkieEngine transcription service
@objc public protocol TalkieEngineProtocol {

    /// Transcribe audio data to text
    /// - Parameters:
    ///   - audioData: Audio data (m4a, wav, etc.)
    ///   - modelId: Whisper model identifier (e.g., "openai_whisper-small")
    ///   - reply: Callback with transcript or error message
    func transcribe(
        audioData: Data,
        modelId: String,
        reply: @escaping (_ transcript: String?, _ error: String?) -> Void
    )

    /// Preload a model into memory for fast transcription
    /// - Parameters:
    ///   - modelId: Whisper model identifier
    ///   - reply: Callback with error message if failed
    func preloadModel(
        _ modelId: String,
        reply: @escaping (_ error: String?) -> Void
    )

    /// Unload current model from memory
    func unloadModel(reply: @escaping () -> Void)

    /// Get current engine status
    func getStatus(reply: @escaping (_ statusJSON: Data?) -> Void)

    /// Check if engine is alive (for connection testing)
    func ping(reply: @escaping (_ pong: Bool) -> Void)

    // MARK: - Model Download Management

    /// Download a model by ID
    /// - Parameters:
    ///   - modelId: Whisper model identifier to download
    ///   - reply: Callback with error message if failed (nil on success)
    func downloadModel(
        _ modelId: String,
        reply: @escaping (_ error: String?) -> Void
    )

    /// Get current download progress
    /// - Parameter reply: Callback with progress JSON (nil if no download active)
    func getDownloadProgress(reply: @escaping (_ progressJSON: Data?) -> Void)

    /// Cancel any ongoing download
    func cancelDownload(reply: @escaping () -> Void)

    /// Get list of available models (not necessarily downloaded)
    func getAvailableModels(reply: @escaping (_ modelsJSON: Data?) -> Void)
}

/// Engine status (Codable for JSON serialization over XPC)
public struct EngineStatus: Codable, Sendable {
    // Process info
    public let pid: Int32
    public let version: String
    public let startedAt: Date
    public let bundleId: String

    // Model state
    public let loadedModelId: String?
    public let isTranscribing: Bool
    public let isWarmingUp: Bool
    public let downloadedModels: [String]

    // Stats
    public let totalTranscriptions: Int
    public let memoryUsageMB: Int?

    public init(
        pid: Int32,
        version: String,
        startedAt: Date,
        bundleId: String,
        loadedModelId: String?,
        isTranscribing: Bool,
        isWarmingUp: Bool,
        downloadedModels: [String],
        totalTranscriptions: Int = 0,
        memoryUsageMB: Int? = nil
    ) {
        self.pid = pid
        self.version = version
        self.startedAt = startedAt
        self.bundleId = bundleId
        self.loadedModelId = loadedModelId
        self.isTranscribing = isTranscribing
        self.isWarmingUp = isWarmingUp
        self.downloadedModels = downloadedModels
        self.totalTranscriptions = totalTranscriptions
        self.memoryUsageMB = memoryUsageMB
    }
}

/// Download progress (Codable for JSON serialization over XPC)
public struct DownloadProgress: Codable, Sendable {
    public let modelId: String
    public let progress: Double  // 0.0 to 1.0
    public let downloadedBytes: Int64
    public let totalBytes: Int64?
    public let isDownloading: Bool

    public init(
        modelId: String,
        progress: Double,
        downloadedBytes: Int64,
        totalBytes: Int64?,
        isDownloading: Bool
    ) {
        self.modelId = modelId
        self.progress = progress
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.isDownloading = isDownloading
    }

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

/// Model info for display (Codable for JSON serialization over XPC)
public struct ModelInfo: Codable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let sizeDescription: String
    public let isDownloaded: Bool
    public let isLoaded: Bool

    public init(
        id: String,
        displayName: String,
        sizeDescription: String,
        isDownloaded: Bool,
        isLoaded: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.sizeDescription = sizeDescription
        self.isDownloaded = isDownloaded
        self.isLoaded = isLoaded
    }
}
