//
//  WebSocketEngineTransport.swift
//  Talkie
//
//  WebSocket client for remote TalkieAgent-hosted engine transcription.
//  Sends JSON-RPC messages matching ServiceBridge's wire format
//  over URLSessionWebSocketTask.
//

import Foundation
import TalkieKit

private let log = Log(.xpc)

/// Errors specific to the remote engine transport
enum RemoteEngineError: LocalizedError {
    case notConnected
    case invalidResponse(String)
    case serverError(String)
    case timeout
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to remote engine"
        case .invalidResponse(let msg): return "Invalid response: \(msg)"
        case .serverError(let msg): return "Remote engine error: \(msg)"
        case .timeout: return "Request timed out"
        case .encodingFailed: return "Failed to encode request"
        }
    }
}

/// WebSocket client that talks to a remote TalkieAgent-hosted engine bridge.
/// Main-actor isolated so request bookkeeping stays in one place.
@MainActor
final class WebSocketEngineTransport {

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private(set) var isConnected = false

    /// Pending request callbacks keyed by request ID
    private var pendingRequests: [String: CheckedContinuation<[String: Any], Error>] = [:]

    private var host: String = ""
    private var port: Int = 19821

    // MARK: - Connection

    func connect(host: String, port: Int) async throws {
        disconnect()

        self.host = host
        self.port = port

        guard let url = URL(string: "ws://\(host):\(port)") else {
            throw RemoteEngineError.invalidResponse("Invalid URL: ws://\(host):\(port)")
        }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        self.session = session
        self.webSocketTask = task

        task.resume()

        // Start receiving messages
        startReceiving()

        // Verify connection with a ping
        let pong = try await ping()
        if pong {
            isConnected = true
            log.info("[RemoteEngine] Connected to ws://\(host):\(port)")
        } else {
            throw RemoteEngineError.invalidResponse("Ping failed")
        }
    }

    func disconnect() {
        isConnected = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil

        let pending = pendingRequests
        pendingRequests.removeAll()

        for (_, continuation) in pending {
            continuation.resume(throwing: RemoteEngineError.notConnected)
        }
    }

    // MARK: - Public API

    func ping() async throws -> Bool {
        let result = try await sendRequest(method: "ping")
        return result["pong"] as? Bool ?? false
    }

    func getStatus() async throws -> Data {
        let result = try await sendRequest(method: "status")
        return try JSONSerialization.data(withJSONObject: result)
    }

    func getAvailableModels() async throws -> Data {
        let result = try await sendRequest(method: "models")
        if let models = result["models"] {
            return try JSONSerialization.data(withJSONObject: models)
        }
        return try JSONSerialization.data(withJSONObject: result)
    }

    func preloadModel(_ modelId: String) async throws {
        _ = try await sendRequest(method: "preload", params: ["modelId": modelId])
    }

    /// Transcribe audio data sent as base64 over WebSocket
    func transcribe(
        audioData: Data,
        modelId: String,
        priority: TranscriptionPriority,
        postProcess: PostProcessOption
    ) async throws -> String {
        let params: [String: Any] = [
            "audioData": audioData.base64EncodedString(),
            "modelId": modelId,
            "priority": priority.rawValue,
            "postProcess": postProcess.rawValue
        ]

        let result = try await sendRequest(method: "transcribeAudio", params: params, timeout: 120)

        guard let transcript = result["transcript"] as? String else {
            throw RemoteEngineError.invalidResponse("Missing 'transcript' in response")
        }
        return transcript
    }

    /// Transcribe audio data and return word-level timestamps
    func transcribeWithTimings(
        audioData: Data,
        modelId: String,
        priority: TranscriptionPriority,
        postProcess: PostProcessOption
    ) async throws -> (transcript: String, timedTranscription: TimedTranscription?) {
        let params: [String: Any] = [
            "audioData": audioData.base64EncodedString(),
            "modelId": modelId,
            "priority": priority.rawValue,
            "postProcess": postProcess.rawValue
        ]

        let result = try await sendRequest(method: "transcribeAudioWithTimings", params: params, timeout: 120)

        guard let transcript = result["transcript"] as? String else {
            throw RemoteEngineError.invalidResponse("Missing 'transcript' in response")
        }

        var timed: TimedTranscription? = nil
        if let segments = result["segments"] {
            let segmentsData = try JSONSerialization.data(withJSONObject: segments)
            timed = TimedTranscription.from(data: segmentsData)
        }

        return (transcript, timed)
    }

    // MARK: - JSON-RPC Transport

    private func sendRequest(
        method: String,
        params: [String: Any]? = nil,
        timeout: TimeInterval = 30
    ) async throws -> [String: Any] {
        guard let webSocketTask, isConnected || method == "ping" else {
            throw RemoteEngineError.notConnected
        }

        let requestId = UUID().uuidString

        var request: [String: Any] = [
            "id": requestId,
            "method": method
        ]
        if let params {
            request["params"] = params
        }

        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let text = String(data: data, encoding: .utf8) else {
            throw RemoteEngineError.encodingFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestId] = continuation

            // Set up timeout
            let timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    let pending = self.pendingRequests.removeValue(forKey: requestId)
                    pending?.resume(throwing: RemoteEngineError.timeout)
                }
            }

            // Send message
            webSocketTask.send(.string(text)) { [weak self] error in
                Task { @MainActor [weak self] in
                    timeoutTask.cancel()
                    guard let self, let error else { return }
                    let pending = self.pendingRequests.removeValue(forKey: requestId)
                    pending?.resume(throwing: error)
                }
                // On success, wait for response via receiveMessage loop
            }
        }
    }

    // MARK: - Receive Loop

    private func startReceiving() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }

                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    // Continue receiving
                    self.startReceiving()

                case .failure(let error):
                    log.warning("[RemoteEngine] WebSocket receive error: \(error.localizedDescription)")
                    self.isConnected = false
                    let pending = self.pendingRequests
                    self.pendingRequests.removeAll()
                    for (_, continuation) in pending {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let str):
            text = str
        case .data(let data):
            text = String(data: data, encoding: .utf8) ?? ""
        @unknown default:
            return
        }

        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log.warning("[RemoteEngine] Failed to parse response JSON")
            return
        }

        // Match response to request by ID
        guard let responseId = json["id"] as? String else {
            // Push event (no id) — ignore for now
            return
        }

        let continuation = pendingRequests.removeValue(forKey: responseId)

        guard let continuation else {
            log.debug("[RemoteEngine] Response for unknown request ID: \(responseId)")
            return
        }

        if let error = json["error"] as? String {
            continuation.resume(throwing: RemoteEngineError.serverError(error))
        } else if let result = json["result"] as? [String: Any] {
            continuation.resume(returning: result)
        } else {
            continuation.resume(returning: [:])
        }
    }
}
