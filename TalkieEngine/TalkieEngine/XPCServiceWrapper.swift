//
//  XPCServiceWrapper.swift
//  TalkieEngine
//
//  Non-MainActor wrapper for XPC protocol that dispatches to EngineService
//

import Foundation
import os

private let logger = Logger(subsystem: "live.talkie.engine", category: "XPCWrapper")

/// Wrapper that implements TalkieEngineProtocol in a nonisolated context
/// EngineService methods are already nonisolated and handle MainActor dispatch internally
final class XPCServiceWrapper: NSObject, TalkieEngineProtocol {
    private let engine: EngineService

    init(engine: EngineService) {
        self.engine = engine
        super.init()
        logger.info("XPCServiceWrapper initialized with engine")
    }

    func transcribe(audioData: Data, modelId: String, reply: @escaping (String?, String?) -> Void) {
        logger.info("XPC: transcribe called, \(audioData.count) bytes")
        // EngineService.transcribe is nonisolated and handles MainActor dispatch internally
        engine.transcribe(audioData: audioData, modelId: modelId, reply: reply)
    }

    func preloadModel(_ modelId: String, reply: @escaping (String?) -> Void) {
        logger.info("XPC: preloadModel called for \(modelId)")
        engine.preloadModel(modelId, reply: reply)
    }

    func unloadModel(reply: @escaping () -> Void) {
        logger.info("XPC: unloadModel called")
        engine.unloadModel(reply: reply)
    }

    func getStatus(reply: @escaping (Data?) -> Void) {
        logger.info("XPC: getStatus called")
        engine.getStatus(reply: reply)
    }

    func ping(reply: @escaping (Bool) -> Void) {
        logger.info("XPC: ping called")
        reply(true)
    }
}
