//
//  XPCServiceWrapper.swift
//  TalkieEngine
//
//  Non-MainActor wrapper for XPC protocol that dispatches to EngineService
//

import Foundation

/// Wrapper that implements TalkieEngineProtocol in a nonisolated context
/// EngineService methods are already nonisolated and handle MainActor dispatch internally
final class XPCServiceWrapper: NSObject, TalkieEngineProtocol {
    private let engine: EngineService

    init(engine: EngineService) {
        self.engine = engine
        super.init()
        AppLogger.shared.info(.xpc, "XPCServiceWrapper initialized with engine")
    }

    func transcribe(audioPath: String, modelId: String, priority: TranscriptionPriority, reply: @escaping (String?, String?) -> Void) {
        AppLogger.shared.info(.xpc, "transcribe called for \(audioPath) (priority: \(priority.displayName))")
        engine.transcribe(audioPath: audioPath, modelId: modelId, priority: priority, reply: reply)
    }

    func transcribe(audioPath: String, modelId: String, externalRefId: String?, priority: TranscriptionPriority, reply: @escaping (String?, String?) -> Void) {
        AppLogger.shared.info(.xpc, "transcribe called for \(audioPath) with refId: \(externalRefId ?? "nil") (priority: \(priority.displayName))")
        engine.transcribe(audioPath: audioPath, modelId: modelId, externalRefId: externalRefId, priority: priority, reply: reply)
    }

    func preloadModel(_ modelId: String, reply: @escaping (String?) -> Void) {
        AppLogger.shared.info(.xpc, "preloadModel called for \(modelId)")
        engine.preloadModel(modelId, reply: reply)
    }

    func unloadModel(reply: @escaping () -> Void) {
        AppLogger.shared.info(.xpc, "unloadModel called")
        engine.unloadModel(reply: reply)
    }

    func getStatus(reply: @escaping (Data?) -> Void) {
        AppLogger.shared.info(.xpc, "getStatus called")
        engine.getStatus(reply: reply)
    }

    func ping(reply: @escaping (Bool) -> Void) {
        NSLog("[XPCServiceWrapper] 🏓 PING received, sending PONG")
        AppLogger.shared.info(.xpc, "ping called")
        reply(true)
        NSLog("[XPCServiceWrapper] ✓ PONG sent")
    }

    // MARK: - Download Management

    func downloadModel(_ modelId: String, reply: @escaping (String?) -> Void) {
        AppLogger.shared.info(.xpc, "downloadModel called for \(modelId)")
        engine.downloadModel(modelId, reply: reply)
    }

    func getDownloadProgress(reply: @escaping (Data?) -> Void) {
        AppLogger.shared.info(.xpc, "getDownloadProgress called")
        engine.getDownloadProgress(reply: reply)
    }

    func cancelDownload(reply: @escaping () -> Void) {
        AppLogger.shared.info(.xpc, "cancelDownload called")
        engine.cancelDownload(reply: reply)
    }

    func getAvailableModels(reply: @escaping (Data?) -> Void) {
        AppLogger.shared.info(.xpc, "getAvailableModels called")
        engine.getAvailableModels(reply: reply)
    }

    // MARK: - Graceful Shutdown

    func requestShutdown(waitForCompletion: Bool, reply: @escaping (Bool) -> Void) {
        AppLogger.shared.info(.xpc, "requestShutdown called (waitForCompletion: \(waitForCompletion))")
        engine.requestShutdown(waitForCompletion: waitForCompletion, reply: reply)
    }
}
