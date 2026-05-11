import Foundation
import TalkieKit
import TalkieEngineCore

private let embeddedEngineLog = Log(.xpc)

enum EmbeddedEngineError: LocalizedError {
    case notStarted
    case operationFailed(String)
    case missingResponse(String)

    var errorDescription: String? {
        switch self {
        case .notStarted:
            return "Embedded engine is not started"
        case .operationFailed(let message):
            return message
        case .missingResponse(let operation):
            return "Embedded engine returned no response for \(operation)"
        }
    }
}

@MainActor
final class EmbeddedEngineCoordinator {
    static let shared = EmbeddedEngineCoordinator()

    private let engine: any EmbeddedEngineRuntime
    private var hasStarted = false
    private var bridge: ServiceBridge?
    private let bridgePort: UInt16 = 19821

    private init() {
        engine = TalkieEngineCoreFactory.makeEmbeddedEngine()
    }

    func start() {
        guard !hasStarted else {
            refreshBridge()
            return
        }

        hasStarted = true
        embeddedEngineLog.info("[EmbeddedEngine] Started inside TalkieAgent")
        refreshBridge()
    }

    func ensureReady() async -> Bool {
        start()
        return await ping()
    }

    func refreshBridge() {
        let remoteEnabled = TalkieSharedSettings.bool(forKey: AgentSettingsKey.remoteEngineEnabled)

        bridge?.stop()
        bridge = nil

        guard remoteEnabled else {
            embeddedEngineLog.info("[EmbeddedEngine] ServiceBridge disabled (remote access off)")
            return
        }

        let bindAddress = "0.0.0.0"

        let bridge = ServiceBridge(port: bridgePort, serviceName: "TalkieAgentEngine", bindAddress: bindAddress)
        configureBridge(bridge)
        bridge.start()
        self.bridge = bridge
        embeddedEngineLog.info("[EmbeddedEngine] ServiceBridge started on ws://\(bindAddress):\(bridgePort)")
    }

    private func configureBridge(_ bridge: ServiceBridge) {
        bridge.handle("ping") { _, reply in
            reply(["pong": true], nil)
        }

        bridge.handle("status") { [weak self] _, reply in
            Task { @MainActor in
                guard let self else {
                    reply(nil, EmbeddedEngineError.notStarted.localizedDescription)
                    return
                }

                do {
                    let statusJSON = try await self.statusJSONObject()
                    reply(statusJSON, nil)
                } catch {
                    reply(nil, error.localizedDescription)
                }
            }
        }

        bridge.handle("models") { [weak self] _, reply in
            Task { @MainActor in
                guard let self else {
                    reply(nil, EmbeddedEngineError.notStarted.localizedDescription)
                    return
                }

                do {
                    let models = try await self.availableModelsJSONObject()
                    reply(["models": models], nil)
                } catch {
                    reply(nil, error.localizedDescription)
                }
            }
        }

        bridge.handle("preload") { [weak self] params, reply in
            Task { @MainActor in
                guard let self else {
                    reply(nil, EmbeddedEngineError.notStarted.localizedDescription)
                    return
                }

                let modelId = params?["modelId"] as? String ?? TalkieDefaults.transcriptionModelId
                do {
                    try await self.preloadModel(modelId)
                    reply(["success": true, "modelId": modelId], nil)
                } catch {
                    reply(nil, error.localizedDescription)
                }
            }
        }

        bridge.handle("transcribe") { [weak self] params, reply in
            Task { @MainActor in
                guard let self else {
                    reply(nil, EmbeddedEngineError.notStarted.localizedDescription)
                    return
                }

                do {
                    let result = try await self.handleBridgeTranscription(params: params, withTimings: false)
                    reply(result, nil)
                } catch {
                    reply(nil, error.localizedDescription)
                }
            }
        }

        bridge.handle("transcribeWithTimings") { [weak self] params, reply in
            Task { @MainActor in
                guard let self else {
                    reply(nil, EmbeddedEngineError.notStarted.localizedDescription)
                    return
                }

                do {
                    let result = try await self.handleBridgeTranscription(params: params, withTimings: true)
                    reply(result, nil)
                } catch {
                    reply(nil, error.localizedDescription)
                }
            }
        }

        bridge.handle("transcribeAudio") { [weak self] params, reply in
            Task { @MainActor in
                guard let self else {
                    reply(nil, EmbeddedEngineError.notStarted.localizedDescription)
                    return
                }

                do {
                    let result = try await self.handleBridgeAudioTranscription(params: params, withTimings: false)
                    reply(result, nil)
                } catch {
                    reply(nil, error.localizedDescription)
                }
            }
        }

        bridge.handle("transcribeAudioWithTimings") { [weak self] params, reply in
            Task { @MainActor in
                guard let self else {
                    reply(nil, EmbeddedEngineError.notStarted.localizedDescription)
                    return
                }

                do {
                    let result = try await self.handleBridgeAudioTranscription(params: params, withTimings: true)
                    reply(result, nil)
                } catch {
                    reply(nil, error.localizedDescription)
                }
            }
        }
    }

    private func handleBridgeTranscription(params: [String: Any]?, withTimings: Bool) async throws -> [String: Any] {
        guard let audioPath = params?["audioPath"] as? String else {
            throw EmbeddedEngineError.operationFailed("Missing 'audioPath' parameter")
        }

        let modelId = params?["modelId"] as? String ?? TalkieDefaults.transcriptionModelId
        let priorityRaw = params?["priority"] as? Int ?? TranscriptionPriority.userInitiated.rawValue
        let priority = TranscriptionPriority(rawValue: priorityRaw) ?? .userInitiated
        let postProcessRaw = params?["postProcess"] as? Int ?? PostProcessOption.dictionary.rawValue
        let postProcess = PostProcessOption(rawValue: postProcessRaw) ?? .dictionary
        let externalRefId = params?["externalRefId"] as? String

        if withTimings {
            let (transcript, timedTranscription) = try await transcribeWithTimings(
                audioPath: audioPath,
                modelId: modelId,
                externalRefId: externalRefId,
                priority: priority,
                postProcess: postProcess
            )

            var result: [String: Any] = ["transcript": transcript]
            if let timedTranscription,
               let data = timedTranscription.toData(),
               let json = try? JSONSerialization.jsonObject(with: data) {
                result["segments"] = json
            }
            return result
        }

        let transcript = try await transcribe(
            audioPath: audioPath,
            modelId: modelId,
            externalRefId: externalRefId,
            priority: priority,
            postProcess: postProcess
        )
        return ["transcript": transcript]
    }

    private func handleBridgeAudioTranscription(params: [String: Any]?, withTimings: Bool) async throws -> [String: Any] {
        guard let audioBase64 = params?["audioData"] as? String,
              let audioData = Data(base64Encoded: audioBase64) else {
            throw EmbeddedEngineError.operationFailed("Missing or invalid 'audioData' (expected base64)")
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        do {
            try audioData.write(to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            var updatedParams = params ?? [:]
            updatedParams["audioPath"] = tempURL.path
            return try await handleBridgeTranscription(params: updatedParams, withTimings: withTimings)
        } catch {
            throw EmbeddedEngineError.operationFailed("Failed to write temp audio file: \(error.localizedDescription)")
        }
    }

    private func statusJSONObject() async throws -> [String: Any] {
        guard let json = try jsonObject(from: await statusSnapshot()) as? [String: Any] else {
            throw EmbeddedEngineError.missingResponse("status")
        }
        return json
    }

    private func availableModelsJSONObject() async throws -> Any {
        try jsonObject(from: await availableModelsSnapshot())
    }

    private func jsonObject<Value: Encodable>(from value: Value) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    func ping() async -> Bool {
        await engine.ping()
    }

    func statusSnapshot() async -> EngineStatus {
        await engine.statusSnapshot()
    }

    func transcribe(
        audioPath: String,
        modelId: String,
        externalRefId: String? = nil,
        priority: TranscriptionPriority = .high,
        postProcess: PostProcessOption = .none
    ) async throws -> String {
        try await engine.transcribe(
            audioPath: audioPath,
            modelId: modelId,
            externalRefId: externalRefId,
            priority: priority,
            postProcess: postProcess
        )
    }

    func transcribeWithTimings(
        audioPath: String,
        modelId: String,
        externalRefId: String? = nil,
        priority: TranscriptionPriority = .high,
        postProcess: PostProcessOption = .none
    ) async throws -> (text: String, timedTranscription: TimedTranscription?) {
        try await engine.transcribeWithTimings(
            audioPath: audioPath,
            modelId: modelId,
            externalRefId: externalRefId,
            priority: priority,
            postProcess: postProcess
        )
    }

    func preloadModel(_ modelId: String) async throws {
        try await engine.preloadModel(modelId)
    }

    func unloadModel() async {
        await engine.unloadModel()
    }

    func downloadModel(_ modelId: String) async throws {
        try await engine.downloadModel(modelId)
    }

    func downloadProgressSnapshot() async -> DownloadProgress? {
        await engine.downloadProgressSnapshot()
    }

    func cancelDownload() async {
        await engine.cancelDownload()
    }

    func availableModelsSnapshot() async -> [ModelInfo] {
        await engine.availableModelsSnapshot()
    }

    func updateDictionary(entriesJSON: Data) async throws {
        let entries = try JSONDecoder().decode([DictionaryEntry].self, from: entriesJSON)
        try await engine.updateDictionary(entries)
    }

    func setDictionaryEnabled(_ enabled: Bool) async {
        await engine.setDictionaryEnabled(enabled)
    }

    func setSymbolicMappingEnabled(_ enabled: Bool) async {
        await engine.setSymbolicMappingEnabled(enabled)
    }

    func setFillerRemovalEnabled(_ enabled: Bool) async {
        await engine.setFillerRemovalEnabled(enabled)
    }

    func reloadSymbolicMapping() async throws {
        try await engine.reloadSymbolicMapping()
    }

    func startStreamingASR() async throws -> String {
        try await engine.startStreamingASR()
    }

    func feedStreamingASR(sessionId: String, audio: Data) async throws -> [StreamingASREvent]? {
        try await engine.feedStreamingASR(sessionId: sessionId, audio: audio)
    }

    func stopStreamingASR(sessionId: String) async throws -> String {
        try await engine.stopStreamingASR(sessionId: sessionId)
    }
}
