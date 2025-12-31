//
//  XPCProtocols.swift
//  TalkieKit
//
//  XPC protocol definitions shared between Talkie, TalkieLive, and TalkieEngine.
//  Single source of truth - all apps import from here.
//

import Foundation

// MARK: - XPC Service Names

/// XPC service name for TalkieLive (environment-aware)
public var kTalkieLiveXPCServiceName: String {
    TalkieEnvironment.current.liveXPCService
}

/// XPC service name for TalkieEngine (environment-aware)
public var kTalkieEngineXPCServiceName: String {
    TalkieEnvironment.current.engineXPCService
}

// MARK: - TalkieLive XPC Protocols

/// Protocol for TalkieLive's XPC service (Talkie → Live commands)
@objc public protocol TalkieLiveXPCServiceProtocol {
    /// Get current recording state, elapsed time, and process ID
    func getCurrentState(reply: @escaping (_ state: String, _ elapsedTime: TimeInterval, _ pid: Int32) -> Void)

    /// Register for state change notifications (returns success and PID)
    func registerStateObserver(reply: @escaping (_ success: Bool, _ pid: Int32) -> Void)

    /// Unregister from state change notifications
    func unregisterStateObserver(reply: @escaping (_ success: Bool) -> Void)

    /// Toggle recording (start if idle, stop if listening)
    func toggleRecording(reply: @escaping (_ success: Bool) -> Void)

    /// Get TalkieLive's permission status
    /// - Parameters:
    ///   - reply: Callback with microphone granted, accessibility granted, screen recording granted
    func getPermissions(reply: @escaping (_ microphone: Bool, _ accessibility: Bool, _ screenRecording: Bool) -> Void)
}

/// Protocol for Talkie to receive callbacks from TalkieLive (Live → Talkie events)
@objc public protocol TalkieLiveStateObserverProtocol {
    /// Called when TalkieLive's state changes
    func stateDidChange(state: String, elapsedTime: TimeInterval)

    /// Called when TalkieLive adds a new dictation to the database
    func dictationWasAdded()

    /// Called when audio level changes (throttled to ~2Hz)
    func audioLevelDidChange(level: Float)
}

// MARK: - TalkieEngine XPC Protocol

/// Post-processing options for transcription
/// Transcription is pure by default - processing is opt-in
@objc public enum PostProcessOption: Int, Sendable {
    case none = 0        // Raw transcription only (default)
    case dictionary = 1  // Apply dictionary replacements

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .dictionary: return "Dictionary"
        }
    }
}

/// Task priority for transcription requests
@objc public enum TranscriptionPriority: Int, Sendable {
    case background = 0       // Lowest - maintenance, cleanup
    case utility = 1          // Long-running tasks
    case low = 2             // Deferrable work
    case medium = 3          // Default - balanced priority
    case userInitiated = 4   // User-facing, should complete quickly
    case high = 5            // Highest - real-time, interactive (Live dictations)

    /// Convert to Swift TaskPriority
    public var taskPriority: TaskPriority {
        switch self {
        case .background: return .background
        case .utility: return .utility
        case .low: return .low
        case .medium: return .medium
        case .userInitiated: return .userInitiated
        case .high: return .high
        }
    }

    public var displayName: String {
        switch self {
        case .background: return "Background"
        case .utility: return "Utility"
        case .low: return "Low"
        case .medium: return "Medium"
        case .userInitiated: return "User Initiated"
        case .high: return "High (Real-time)"
        }
    }
}

/// Protocol for TalkieEngine's XPC service (Talkie/Live → Engine)
@objc public protocol TalkieEngineProtocol {
    /// Transcribe audio file to text
    ///
    /// Transcription is pure by default - just audio to text.
    /// Use `postProcess` to opt-in to additional processing steps.
    ///
    /// Priority Guidelines:
    /// - `.high` - Real-time dictation (TalkieLive) - user is waiting
    /// - `.medium` - Interactive features (scratch pad) - user-facing but can wait
    /// - `.low` - Batch/async operations - user isn't waiting
    ///
    /// - Parameters:
    ///   - audioPath: Path to audio file
    ///   - modelId: Model identifier (e.g., "whisper:openai_whisper-small" or "parakeet:v3")
    ///   - externalRefId: Optional trace ID for cross-app correlation
    ///   - priority: Task priority for scheduling
    ///   - postProcess: Optional processing to apply (default: .none = raw transcription)
    ///   - reply: Callback with transcript or error
    func transcribe(
        audioPath: String,
        modelId: String,
        externalRefId: String?,
        priority: TranscriptionPriority,
        postProcess: PostProcessOption,
        reply: @escaping (_ transcript: String?, _ error: String?) -> Void
    )

    /// Preload a model into memory for faster transcription
    func preloadModel(
        _ modelId: String,
        reply: @escaping (_ error: String?) -> Void
    )

    /// Unload the current model from memory
    func unloadModel(reply: @escaping () -> Void)

    /// Get engine status (returns JSON-encoded EngineStatus)
    func getStatus(reply: @escaping (_ statusJSON: Data?) -> Void)

    /// Ping to verify connection
    func ping(reply: @escaping (_ pong: Bool) -> Void)

    /// Request graceful shutdown
    func requestShutdown(waitForCompletion: Bool, reply: @escaping (_ accepted: Bool) -> Void)

    /// Start downloading a model
    func downloadModel(
        _ modelId: String,
        reply: @escaping (_ error: String?) -> Void
    )

    /// Get current download progress (returns JSON-encoded DownloadProgress)
    func getDownloadProgress(reply: @escaping (_ progressJSON: Data?) -> Void)

    /// Cancel current download
    func cancelDownload(reply: @escaping () -> Void)

    /// Get list of available models (returns JSON-encoded [ModelInfo])
    func getAvailableModels(reply: @escaping (_ modelsJSON: Data?) -> Void)

    /// Update the dictionary for text post-processing
    /// Talkie pushes content, Engine persists to its own file
    /// - Parameters:
    ///   - entriesJSON: JSON-encoded [DictionaryEntry]
    ///   - reply: Callback with error message if failed
    func updateDictionary(
        entriesJSON: Data,
        reply: @escaping (_ error: String?) -> Void
    )

    /// Enable or disable dictionary processing
    /// Engine persists this setting and loads dictionary on startup if enabled
    /// - Parameters:
    ///   - enabled: Whether dictionary should be active
    ///   - reply: Callback when done
    func setDictionaryEnabled(
        _ enabled: Bool,
        reply: @escaping () -> Void
    )
}

// Note: LiveState enum is defined in UI/LiveState.swift
