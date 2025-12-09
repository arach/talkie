//
//  EngineProtocol.swift
//  TalkieEngine
//
//  XPC protocol for transcription service
//

import Foundation

/// Mach service name for XPC connection
public let kTalkieEngineServiceName = "live.talkie.engine.xpc"

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
}

/// Engine status (Codable for JSON serialization over XPC)
public struct EngineStatus: Codable, Sendable {
    public let loadedModelId: String?
    public let isTranscribing: Bool
    public let isWarmingUp: Bool
    public let downloadedModels: [String]

    public init(
        loadedModelId: String?,
        isTranscribing: Bool,
        isWarmingUp: Bool,
        downloadedModels: [String]
    ) {
        self.loadedModelId = loadedModelId
        self.isTranscribing = isTranscribing
        self.isWarmingUp = isWarmingUp
        self.downloadedModels = downloadedModels
    }
}
