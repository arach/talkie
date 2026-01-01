//
//  ModelState.swift
//  TalkieKit
//
//  Unified lifecycle state for AI models (STT and TTS).
//  Provides clear, consistent state representation across all model management UI.
//

import Foundation

// MARK: - Model Lifecycle State

/// Unified lifecycle state for both STT models and TTS voices.
/// Models progress through: notDownloaded → downloading → downloaded → loading → loaded
public enum ModelState: Equatable, Sendable {
    /// Model files are not on disk
    case notDownloaded

    /// Model is being downloaded (0.0 to 1.0 progress)
    case downloading(progress: Double)

    /// Model files are on disk but not loaded into memory
    case downloaded

    /// Model is being loaded into memory
    case loading

    /// Model is loaded in memory and ready for inference
    case loaded

    // MARK: - Convenience Properties

    /// Whether the model files exist on disk
    public var isOnDisk: Bool {
        switch self {
        case .notDownloaded, .downloading:
            return false
        case .downloaded, .loading, .loaded:
            return true
        }
    }

    /// Whether the model is currently in memory
    public var isInMemory: Bool {
        switch self {
        case .loaded:
            return true
        default:
            return false
        }
    }

    /// Whether the model is in a transitional state (downloading or loading)
    public var isTransitioning: Bool {
        switch self {
        case .downloading, .loading:
            return true
        default:
            return false
        }
    }

    /// Whether the model can be selected for use
    public var isSelectable: Bool {
        switch self {
        case .downloaded, .loaded:
            return true
        default:
            return false
        }
    }

    /// Download progress (0.0 to 1.0), nil if not downloading
    public var downloadProgress: Double? {
        if case .downloading(let progress) = self {
            return progress
        }
        return nil
    }

    // MARK: - Display

    /// Human-readable status text
    public var displayText: String {
        switch self {
        case .notDownloaded:
            return "Not Downloaded"
        case .downloading(let progress):
            return "Downloading \(Int(progress * 100))%"
        case .downloaded:
            return "Ready"
        case .loading:
            return "Loading..."
        case .loaded:
            return "Loaded"
        }
    }

    /// Short badge text for compact displays
    public var badgeText: String? {
        switch self {
        case .notDownloaded, .downloading, .loading:
            return nil
        case .downloaded:
            return "READY"
        case .loaded:
            return "LOADED"
        }
    }
}

// MARK: - Model Provider

/// Provider/family type for categorizing models
public enum ModelProvider: String, Codable, Sendable, CaseIterable {
    // STT Providers
    case whisper = "whisper"
    case parakeet = "parakeet"

    // TTS Providers
    case kokoro = "kokoro"
    case elevenLabs = "elevenlabs"
    case system = "system"

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .whisper: return "Whisper"
        case .parakeet: return "Parakeet"
        case .kokoro: return "Kokoro"
        case .elevenLabs: return "ElevenLabs"
        case .system: return "System"
        }
    }

    /// Short badge text (3-4 chars)
    public var badge: String {
        switch self {
        case .whisper: return "WSP"
        case .parakeet: return "PKT"
        case .kokoro: return "KKR"
        case .elevenLabs: return "11L"
        case .system: return "SYS"
        }
    }

    /// Whether this is a local (on-device) provider
    public var isLocal: Bool {
        switch self {
        case .whisper, .parakeet, .kokoro, .system:
            return true
        case .elevenLabs:
            return false
        }
    }

    /// Whether this is an STT provider
    public var isSTT: Bool {
        switch self {
        case .whisper, .parakeet:
            return true
        default:
            return false
        }
    }

    /// Whether this is a TTS provider
    public var isTTS: Bool {
        switch self {
        case .kokoro, .elevenLabs, .system:
            return true
        default:
            return false
        }
    }
}
