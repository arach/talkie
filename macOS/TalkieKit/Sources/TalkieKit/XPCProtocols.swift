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

/// Protocol for TalkieEngine's XPC service (Talkie/Live → Engine)
@objc public protocol TalkieEngineProtocol {
    /// Transcribe audio file to text
    /// - Parameters:
    ///   - audioPath: Path to audio file
    ///   - modelId: Whisper model ID to use
    ///   - externalRefId: Optional trace ID for cross-app correlation (e.g., "a1b2c3d4")
    func transcribe(
        audioPath: String,
        modelId: String,
        externalRefId: String?,
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
}

// Note: LiveState enum is defined in UI/LiveState.swift
