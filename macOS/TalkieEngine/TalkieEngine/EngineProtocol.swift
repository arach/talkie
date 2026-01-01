//
//  EngineProtocol.swift
//  TalkieEngine
//
//  Engine-local helper types. Core protocol is in TalkieKit/XPCProtocols.swift.
//

import Foundation
import TalkieKit

// TranscriptionPriority is defined in TalkieKit/XPCProtocols.swift

/// Mach service names for XPC connection (matches TalkieEnvironment)
public enum EngineServiceMode: String, CaseIterable {
    case production = "jdi.talkie.engine.xpc"
    case staging = "jdi.talkie.engine.xpc.staging"
    case dev = "jdi.talkie.engine.xpc.dev"

    public var displayName: String {
        switch self {
        case .production: return "Production"
        case .staging: return "Staging"
        case .dev: return "Dev"
        }
    }

    /// Badge text for menu bar
    public var badge: String {
        switch self {
        case .production: return "PROD"
        case .staging: return "STAGING"
        case .dev: return "DEV"
        }
    }

    /// Short name for logging
    public var shortName: String {
        switch self {
        case .production: return "prod"
        case .staging: return "staging"
        case .dev: return "dev"
        }
    }

    /// Launchd service label (for launchctl commands)
    /// This is the Label in the plist, NOT the MachService name
    public var launchdLabel: String {
        switch self {
        case .production: return "jdi.talkie.engine"
        case .staging: return "jdi.talkie.engine.staging"
        case .dev: return "jdi.talkie.engine.dev"
        }
    }
}

/// Default service name based on build configuration
#if DEBUG
public let kTalkieEngineServiceName = EngineServiceMode.dev.rawValue
#else
public let kTalkieEngineServiceName = EngineServiceMode.production.rawValue
#endif

/// Model family identifiers
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

// Note: TalkieEngineProtocol is now defined in TalkieKit/XPCProtocols.swift
// This file only contains Engine-local helper types

/// Engine status (Codable for JSON serialization over XPC)
public struct EngineStatus: Codable, Sendable {
    // Process info
    public let pid: Int32
    public let version: String
    public let startedAt: Date
    public let bundleId: String
    public let isDebugBuild: Bool

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
        isDebugBuild: Bool = false,
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
        self.isDebugBuild = isDebugBuild
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
    public let id: String           // Full ID including family prefix (e.g., "whisper:openai_whisper-small")
    public let family: String       // Model family ("whisper" or "parakeet")
    public let modelId: String      // Model ID without family prefix
    public let displayName: String
    public let sizeDescription: String
    public let description: String  // Quality/speed description
    public let isDownloaded: Bool
    public let isLoaded: Bool

    public init(
        id: String,
        family: String,
        modelId: String,
        displayName: String,
        sizeDescription: String,
        description: String,
        isDownloaded: Bool,
        isLoaded: Bool
    ) {
        self.id = id
        self.family = family
        self.modelId = modelId
        self.displayName = displayName
        self.sizeDescription = sizeDescription
        self.description = description
        self.isDownloaded = isDownloaded
        self.isLoaded = isLoaded
    }

    /// Parse a model ID string into family and model components
    public static func parseModelId(_ fullId: String) -> (family: String, modelId: String) {
        let parts = fullId.split(separator: ":", maxSplits: 1)
        if parts.count == 2 {
            return (String(parts[0]), String(parts[1]))
        }
        // Default to whisper for backwards compatibility
        return ("whisper", fullId)
    }
}
