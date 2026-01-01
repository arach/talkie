//
//  PodCapability.swift
//  TalkieEnginePod
//
//  Generic capability protocol for execution pods
//

import Foundation

/// Configuration passed to capability at load time
public struct PodConfig: Codable {
    public let model: String?
    public let options: [String: String]?

    public init(model: String? = nil, options: [String: String]? = nil) {
        self.model = model
        self.options = options
    }
}

/// Request sent to capability handler
public struct PodRequest: Codable {
    public let id: String
    public let action: String
    public let payload: [String: String]

    public init(id: String = UUID().uuidString, action: String, payload: [String: String] = [:]) {
        self.id = id
        self.action = action
        self.payload = payload
    }
}

/// Response from capability handler
public struct PodResponse: Codable {
    public let id: String
    public let success: Bool
    public let result: [String: String]?
    public let error: String?
    public let durationMs: Int?

    public init(id: String, success: Bool, result: [String: String]? = nil, error: String? = nil, durationMs: Int? = nil) {
        self.id = id
        self.success = success
        self.result = result
        self.error = error
        self.durationMs = durationMs
    }

    public static func success(id: String, result: [String: String], durationMs: Int? = nil) -> PodResponse {
        PodResponse(id: id, success: true, result: result, durationMs: durationMs)
    }

    public static func failure(id: String, error: String) -> PodResponse {
        PodResponse(id: id, success: false, error: error)
    }
}

/// Status info for the pod
public struct PodStatus: Codable {
    public let capability: String
    public let loaded: Bool
    public let memoryMB: Int
    public let requestsHandled: Int

    public init(capability: String, loaded: Bool, memoryMB: Int, requestsHandled: Int) {
        self.capability = capability
        self.loaded = loaded
        self.memoryMB = memoryMB
        self.requestsHandled = requestsHandled
    }
}

/// Protocol that all capabilities must implement
public protocol PodCapability {
    /// Unique name for this capability (e.g., "tts", "asr", "llm")
    static var name: String { get }

    /// Human-readable description
    static var description: String { get }

    /// Supported actions (e.g., ["synthesize"] for TTS)
    static var supportedActions: [String] { get }

    /// Initialize the capability (doesn't load model yet)
    init()

    /// Load the model/resources based on config
    /// This is where the heavy lifting happens (model loading, etc.)
    func load(config: PodConfig) async throws

    /// Handle a request and return a response
    /// This is called for each incoming request
    func handle(_ request: PodRequest) async throws -> PodResponse

    /// Unload/cleanup resources
    /// Called on shutdown or when explicitly unloading
    func unload() async

    /// Check if capability is loaded and ready
    var isLoaded: Bool { get }

    /// Current memory usage estimate in MB
    var memoryUsageMB: Int { get }
}
