//
//  ModelItem.swift
//  TalkieKit
//
//  Protocol for AI model items (STT models and TTS voices).
//  Enables shared UI components to work with both types.
//

import SwiftUI

// MARK: - Model Item Protocol

/// Common interface for STT models and TTS voices.
/// Enables generic UI components like ModelCard to work with both.
public protocol ModelItem: Identifiable, Sendable {
    /// Unique identifier (e.g., "whisper:openai_whisper-small", "kokoro:default")
    var id: String { get }

    /// Human-readable name (e.g., "Whisper Small", "Kokoro")
    var displayName: String { get }

    /// Brief description of the model
    var description: String { get }

    /// Whether model files are downloaded to disk
    var isDownloaded: Bool { get }

    /// Whether the model is currently loaded in memory
    var isLoaded: Bool { get }

    /// Provider/family (whisper, parakeet, kokoro, etc.)
    var providerName: String { get }
}

// MARK: - Protocol Extensions

extension ModelItem {
    /// Compute current state from downloaded/loaded flags
    public var state: ModelState {
        if isLoaded {
            return .loaded
        } else if isDownloaded {
            return .downloaded
        } else {
            return .notDownloaded
        }
    }

    /// Parse provider from ID (format: "provider:modelId")
    public var provider: ModelProvider? {
        let parts = id.split(separator: ":", maxSplits: 1)
        guard let providerString = parts.first else { return nil }
        return ModelProvider(rawValue: String(providerString))
    }

    /// Model ID without provider prefix
    public var modelId: String {
        let parts = id.split(separator: ":", maxSplits: 1)
        if parts.count == 2 {
            return String(parts[1])
        }
        return id
    }
}

// MARK: - STT Model Item

/// Wrapper to make EngineModelInfo conform to ModelItem
public struct STTModelItem: ModelItem {
    public let id: String
    public let displayName: String
    public let description: String
    public let isDownloaded: Bool
    public let isLoaded: Bool
    public let providerName: String

    /// Size description (e.g., "~500 MB")
    public let sizeDescription: String

    /// Speed tier for this model
    public let speedTier: STTSpeedTier

    /// Language support info (e.g., "99+", "EN", "25")
    public let languageInfo: String

    public init(
        id: String,
        displayName: String,
        description: String,
        isDownloaded: Bool,
        isLoaded: Bool,
        providerName: String,
        sizeDescription: String,
        speedTier: STTSpeedTier,
        languageInfo: String
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.isDownloaded = isDownloaded
        self.isLoaded = isLoaded
        self.providerName = providerName
        self.sizeDescription = sizeDescription
        self.speedTier = speedTier
        self.languageInfo = languageInfo
    }
}

/// Speed tier for STT models
public enum STTSpeedTier: String, Sendable {
    case realtime = "Real-time"
    case fast = "Fast"
    case balanced = "Balanced"
    case accurate = "Accurate"

    public var sortOrder: Int {
        switch self {
        case .realtime: return 0
        case .fast: return 1
        case .balanced: return 2
        case .accurate: return 3
        }
    }
}

// MARK: - TTS Voice Item

/// Wrapper to make TTSVoiceInfo conform to ModelItem
public struct TTSVoiceItem: ModelItem {
    public let id: String
    public let displayName: String
    public let description: String
    public let isDownloaded: Bool
    public let isLoaded: Bool
    public let providerName: String

    /// Voice ID without provider prefix
    public let voiceId: String

    /// Language code (e.g., "en-US")
    public let language: String

    /// Estimated memory usage when loaded (MB)
    public let memoryMB: Int?

    public init(
        id: String,
        displayName: String,
        description: String,
        isDownloaded: Bool,
        isLoaded: Bool,
        providerName: String,
        voiceId: String,
        language: String,
        memoryMB: Int? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.isDownloaded = isDownloaded
        self.isLoaded = isLoaded
        self.providerName = providerName
        self.voiceId = voiceId
        self.language = language
        self.memoryMB = memoryMB
    }
}

// MARK: - Accent Colors

/// Accent colors for different model providers
public enum ModelAccentColor {
    /// Get accent color for a provider
    public static func color(for provider: ModelProvider) -> Color {
        switch provider {
        case .whisper:
            return .orange
        case .parakeet:
            return .cyan
        case .kokoro:
            return .purple
        case .elevenLabs:
            return .blue
        case .system:
            return .gray
        }
    }

    /// Get accent color for a provider name string
    public static func color(forName name: String) -> Color {
        guard let provider = ModelProvider(rawValue: name.lowercased()) else {
            return .gray
        }
        return color(for: provider)
    }
}

/// Accent colors for STT speed tiers
extension STTSpeedTier {
    public var color: Color {
        switch self {
        case .realtime: return .green
        case .fast: return .blue
        case .balanced: return .orange
        case .accurate: return .purple
        }
    }
}
