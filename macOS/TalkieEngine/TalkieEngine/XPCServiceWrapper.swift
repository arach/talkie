//
//  XPCServiceWrapper.swift
//  TalkieEngine
//
//  Non-MainActor wrapper for XPC protocol that dispatches to EngineService
//

import Foundation
import TalkieKit

/// Wrapper that implements TalkieEngineProtocol in a nonisolated context
/// EngineService methods are already nonisolated and handle MainActor dispatch internally
final class XPCServiceWrapper: NSObject, TalkieEngineProtocol {
    private let engine: EngineService

    init(engine: EngineService) {
        self.engine = engine
        super.init()
        AppLogger.shared.info(.xpc, "XPCServiceWrapper initialized with engine")
    }

    func transcribe(audioPath: String, modelId: String, externalRefId: String?, priority: TranscriptionPriority, postProcess: PostProcessOption, reply: @escaping (String?, String?) -> Void) {
        let refStr = externalRefId ?? "nil"
        let postStr = postProcess == .none ? "" : " +\(postProcess.displayName)"
        AppLogger.shared.info(.xpc, "transcribe(priority:\(priority.displayName))\(postStr) for \(audioPath) refId:\(refStr)")
        engine.transcribe(audioPath: audioPath, modelId: modelId, externalRefId: externalRefId, priority: priority, postProcess: postProcess, reply: reply)
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

    // MARK: - Dictionary Management

    func updateDictionary(entriesJSON: Data, reply: @escaping (String?) -> Void) {
        AppLogger.shared.info(.xpc, "updateDictionary called (\(entriesJSON.count) bytes)")
        engine.updateDictionary(entriesJSON: entriesJSON, reply: reply)
    }

    func setDictionaryEnabled(_ enabled: Bool, reply: @escaping () -> Void) {
        AppLogger.shared.info(.xpc, "setDictionaryEnabled called: \(enabled)")
        engine.setDictionaryEnabled(enabled, reply: reply)
    }

    // MARK: - Text-to-Speech

    func synthesize(text: String, voiceId: String, reply: @escaping (String?, String?) -> Void) {
        AppLogger.shared.info(.xpc, "synthesize called: \(text.prefix(30))... voice:\(voiceId)")
        engine.synthesize(text: text, voiceId: voiceId, reply: reply)
    }

    func preloadTTSVoice(_ voiceId: String, reply: @escaping (String?) -> Void) {
        AppLogger.shared.info(.xpc, "preloadTTSVoice called: \(voiceId)")
        engine.preloadTTSVoice(voiceId, reply: reply)
    }

    func getAvailableTTSVoices(reply: @escaping (Data?) -> Void) {
        AppLogger.shared.info(.xpc, "getAvailableTTSVoices called")
        engine.getAvailableTTSVoices(reply: reply)
    }

    func unloadTTS(reply: @escaping (Bool) -> Void) {
        AppLogger.shared.info(.xpc, "unloadTTS called")
        engine.unloadTTS(reply: reply)
    }

    func getTTSStatus(reply: @escaping (Bool, Double) -> Void) {
        engine.getTTSStatus(reply: reply)
    }
}
