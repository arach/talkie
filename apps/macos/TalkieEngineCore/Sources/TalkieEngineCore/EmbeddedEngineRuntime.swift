import Foundation
import TalkieKit

@MainActor
public protocol EmbeddedEngineRuntime: AnyObject {
    func ping() async -> Bool
    func statusSnapshot() async -> EngineStatus

    func transcribe(
        audioPath: String,
        modelId: String,
        externalRefId: String?,
        priority: TranscriptionPriority,
        postProcess: PostProcessOption
    ) async throws -> String

    func transcribeWithTimings(
        audioPath: String,
        modelId: String,
        externalRefId: String?,
        priority: TranscriptionPriority,
        postProcess: PostProcessOption
    ) async throws -> (text: String, timedTranscription: TimedTranscription?)

    func preloadModel(_ modelId: String) async throws
    func unloadModel() async

    func downloadModel(_ modelId: String) async throws
    func downloadProgressSnapshot() async -> DownloadProgress?
    func cancelDownload() async
    func availableModelsSnapshot() async -> [ModelInfo]

    func updateDictionary(_ entries: [DictionaryEntry]) async throws
    func setDictionaryEnabled(_ enabled: Bool) async
    func setSymbolicMappingEnabled(_ enabled: Bool) async
    func setFillerRemovalEnabled(_ enabled: Bool) async
    func reloadSymbolicMapping() async throws

    func startStreamingASR() async throws -> String
    func feedStreamingASR(sessionId: String, audio: Data) async throws -> [StreamingASREvent]?
    func stopStreamingASR(sessionId: String) async throws -> String
}
