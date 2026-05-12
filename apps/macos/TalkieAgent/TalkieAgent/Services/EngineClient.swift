//
//  EngineClient.swift
//  TalkieAgent
//
//  Local client for the embedded Talkie engine hosted inside TalkieAgent.
//

import Foundation
import Combine
import TalkieKit
import TalkieEngineCore

private let log = Log(.xpc)

public enum EngineServiceMode: String, CaseIterable, Identifiable {
    case production = "to.talkie.app.agent.xpc"
    case dev = "to.talkie.app.agent.xpc.dev"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .production: return "Production"
        case .dev: return "Dev"
        }
    }

    public var shortName: String {
        switch self {
        case .production: return "PROD"
        case .dev: return "DEV"
        }
    }

    public var environment: TalkieEnvironment {
        switch self {
        case .production: return .production
        case .dev: return .dev
        }
    }

    public init(from environment: TalkieEnvironment) {
        switch environment {
        case .production: self = .production
        case .dev: self = .dev
        }
    }
}

public typealias EngineStatus = TalkieEngineCore.EngineStatus
public typealias DownloadProgress = TalkieEngineCore.DownloadProgress
public typealias ModelFamily = TalkieEngineCore.ModelFamily
public typealias ModelInfo = TalkieEngineCore.ModelInfo

public enum EngineConnectionState: String {
    case disconnected = "Disconnected"
    case launchingEngine = "Launching Embedded Engine..."
    case connecting = "Starting Embedded Engine..."
    case connected = "Connected"
    case connectedWrongBuild = "Connected (Wrong Build)"
    case engineNotFound = "Engine Not Found"
    case error = "Error"
}

@MainActor
public final class EngineClient: ObservableObject {
    public static let shared = EngineClient()

    @Published public var connectionState: EngineConnectionState = .disconnected
    @Published public var status: EngineStatus?
    @Published public var lastError: String?
    @Published public private(set) var connectedMode: EngineServiceMode?
    @Published public private(set) var connectedAt: Date?
    @Published public private(set) var transcriptionCount: Int = 0
    @Published public private(set) var lastTranscriptionAt: Date?
    @Published public private(set) var downloadProgress: DownloadProgress?
    @Published public private(set) var availableModels: [ModelInfo] = []

    public var isConnected: Bool { connectionState == .connected }

    public var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    public var isMatchingBuild: Bool {
        guard let engineDebug = status?.isDebugBuild else { return true }
        return engineDebug == isDebugBuild
    }

    public var buildMismatchWarning: String? {
        nil
    }

    private let coordinator = EmbeddedEngineCoordinator.shared

    private init() {}

    public func startBackgroundRetry() {}

    public func stopBackgroundRetry() {}

    public func connect() {
        guard connectionState != .connecting else { return }
        connectionState = .connecting
        lastError = nil

        Task {
            let connected = await coordinator.ensureReady()
            if connected {
                markConnected()
                refreshStatus()
                await refreshAvailableModels()
            } else {
                connectionState = .error
                lastError = "Embedded engine failed to respond"
            }
        }
    }

    public func disconnect() {
        connectionState = .disconnected
        status = nil
        lastError = nil
        connectedMode = nil
        downloadProgress = nil
    }

    public func reconnect() {
        disconnect()
        connect()
    }

    @discardableResult
    public func ensureConnected() async -> Bool {
        if isConnected { return true }

        let connected = await coordinator.ensureReady()
        if connected {
            markConnected()
            refreshStatus()
            await refreshAvailableModels()
        } else {
            connectionState = .error
            lastError = "Embedded engine failed to respond"
        }
        return connected
    }

    public func transcribe(
        audioPath: String,
        modelId: String = TalkieDefaults.transcriptionModelId,
        externalRefId: String? = nil,
        priority: TranscriptionPriority = .high,
        postProcess: PostProcessOption = .none
    ) async throws -> String {
        guard await ensureConnected() else {
            throw EmbeddedEngineError.notStarted
        }

        let text = try await coordinator.transcribe(
            audioPath: audioPath,
            modelId: modelId,
            externalRefId: externalRefId,
            priority: priority,
            postProcess: postProcess
        )

        transcriptionCount += 1
        lastTranscriptionAt = Date()
        refreshStatus()
        return text
    }

    public func transcribeWithTimings(
        audioPath: String,
        modelId: String = TalkieDefaults.transcriptionModelId,
        externalRefId: String? = nil,
        priority: TranscriptionPriority = .high,
        postProcess: PostProcessOption = .none
    ) async throws -> (text: String, timedTranscription: TimedTranscription?) {
        guard await ensureConnected() else {
            throw EmbeddedEngineError.notStarted
        }

        let result = try await coordinator.transcribeWithTimings(
            audioPath: audioPath,
            modelId: modelId,
            externalRefId: externalRefId,
            priority: priority,
            postProcess: postProcess
        )

        transcriptionCount += 1
        lastTranscriptionAt = Date()
        refreshStatus()
        return result
    }

    public func preloadModel(_ modelId: String) async throws {
        guard await ensureConnected() else {
            throw EmbeddedEngineError.notStarted
        }
        try await coordinator.preloadModel(modelId)
        refreshStatus()
        await refreshAvailableModels()
    }

    public func unloadModel() async {
        await coordinator.unloadModel()
        refreshStatus()
        await refreshAvailableModels()
    }

    public func refreshStatus() {
        Task {
            self.status = await coordinator.statusSnapshot()
            if self.connectionState != .connected {
                self.markConnected()
            }
        }
    }

    public func downloadModel(_ modelId: String) async throws {
        guard await ensureConnected() else {
            throw EmbeddedEngineError.notStarted
        }

        try await coordinator.downloadModel(modelId)
        downloadProgress = nil
        refreshStatus()
        await refreshAvailableModels()
    }

    public func getDownloadProgress() async -> DownloadProgress? {
        let progress = await coordinator.downloadProgressSnapshot()
        downloadProgress = progress
        return progress
    }

    public func cancelDownload() async {
        await coordinator.cancelDownload()
        downloadProgress = nil
    }

    public func startStreamingASR() async throws -> String {
        guard await ensureConnected() else {
            throw EmbeddedEngineError.notStarted
        }
        return try await coordinator.startStreamingASR()
    }

    public func feedStreamingASR(sessionId: String, audio: Data) async throws -> [StreamingASREvent]? {
        guard await ensureConnected() else {
            throw EmbeddedEngineError.notStarted
        }
        return try await coordinator.feedStreamingASR(sessionId: sessionId, audio: audio)
    }

    public func stopStreamingASR(sessionId: String) async throws -> String {
        guard await ensureConnected() else {
            throw EmbeddedEngineError.notStarted
        }
        return try await coordinator.stopStreamingASR(sessionId: sessionId)
    }

    public func refreshAvailableModels() async {
        availableModels = await coordinator.availableModelsSnapshot()
    }

    public func updateDictionary(_ entries: [DictionaryEntry]) async throws {
        let data = try JSONEncoder().encode(entries)
        try await coordinator.updateDictionary(entriesJSON: data)
    }

    public func setDictionaryEnabled(_ enabled: Bool) async {
        await coordinator.setDictionaryEnabled(enabled)
    }

    public func setSymbolicMappingEnabled(_ enabled: Bool) async {
        await coordinator.setSymbolicMappingEnabled(enabled)
    }

    public func setFillerRemovalEnabled(_ enabled: Bool) async {
        await coordinator.setFillerRemovalEnabled(enabled)
    }

    public func reloadSymbolicMapping() async throws {
        try await coordinator.reloadSymbolicMapping()
    }

    private func markConnected() {
        connectionState = .connected
        connectedMode = EngineServiceMode(from: TalkieEnvironment.current)
        connectedAt = connectedAt ?? Date()
        lastError = nil
        log.info("[EngineClient] Embedded engine connected")
    }
}
