import Foundation
import AppKit
import TalkieKit

private let log = Log(.system)

struct MicStopResult {
    let filePath: String
    let duration: TimeInterval
    let fileSize: Int
}

enum MicClientError: LocalizedError {
    case invalidResponse(String)
    case serverError(String)
    case helperNotFound
    case timeout
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message):
            return "Invalid TalkieMic response: \(message)"
        case .serverError(let message):
            return "TalkieMic error: \(message)"
        case .helperNotFound:
            return "TalkieMic app not found"
        case .timeout:
            return "TalkieMic request timed out"
        case .notConnected:
            return "TalkieMic is not connected"
        }
    }
}

@MainActor
final class MicClient {
    var onDisconnected: (() -> Void)?

    private var session: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var isConnected = false

    private var pendingRequests: [String: PendingRequest] = [:]

    private let port = 19824
    private let host = "127.0.0.1"

    private struct PendingRequest {
        let continuation: CheckedContinuation<[String: Any], Error>
        let timeoutTask: Task<Void, Never>
    }

    /// Remove a pending request and cancel its timeout — returns nil if already consumed.
    /// All resolution paths (timeout, send error, response, disconnect) MUST go through
    /// this single method to prevent double-resume of the continuation.
    private func consumeRequest(id: String) -> PendingRequest? {
        guard let pending = pendingRequests.removeValue(forKey: id) else { return nil }
        pending.timeoutTask.cancel()
        return pending
    }

    func startSession(
        clientId: String,
        persist: Bool,
        label: String?
    ) async throws -> String {
        var params: [String: Any] = [
            "clientId": clientId,
            "persist": persist
        ]
        if let label {
            params["label"] = label
        }

        let result = try await sendRequest(
            method: "startSession",
            params: params
        )

        guard let sessionId = result["sessionId"] as? String else {
            throw MicClientError.invalidResponse("Missing sessionId")
        }

        return sessionId
    }

    func stopSession(sessionId: String) async throws -> MicStopResult {
        let result = try await sendRequest(
            method: "stopSession",
            params: ["sessionId": sessionId]
        )

        guard let filePath = result["filePath"] as? String else {
            throw MicClientError.invalidResponse("Missing filePath")
        }

        return MicStopResult(
            filePath: filePath,
            duration: result["duration"] as? Double ?? 0,
            fileSize: result["fileSize"] as? Int ?? 0
        )
    }

    func cancelSession(sessionId: String) async throws {
        _ = try await sendRequest(
            method: "cancelSession",
            params: ["sessionId": sessionId]
        )
    }

    func shutdown() async {
        _ = try? await sendRequest(method: "shutdown")
        disconnect(notify: false)
    }

    private func sendRequest(
        method: String,
        params: [String: Any]? = nil,
        timeout: TimeInterval = 15
    ) async throws -> [String: Any] {
        try await ensureConnected()

        guard let webSocketTask else {
            throw MicClientError.notConnected
        }

        let requestId = UUID().uuidString
        var request: [String: Any] = [
            "id": requestId,
            "method": method
        ]
        if let params {
            request["params"] = params
        }

        let data = try JSONSerialization.data(withJSONObject: request)
        guard let text = String(data: data, encoding: .utf8) else {
            throw MicClientError.invalidResponse("Request encoding failed")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                await MainActor.run {
                    guard let self,
                          let pending = self.consumeRequest(id: requestId) else { return }
                    pending.continuation.resume(throwing: MicClientError.timeout)
                }
            }

            pendingRequests[requestId] = PendingRequest(
                continuation: continuation,
                timeoutTask: timeoutTask
            )

            Task {
                do {
                    try await webSocketTask.send(.string(text))
                } catch {
                    await MainActor.run {
                        guard let pending = self.consumeRequest(id: requestId) else { return }
                        pending.continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func ensureConnected() async throws {
        if isConnected {
            return
        }

        log.info("[MicClient] Not connected — trying direct connect first")
        do {
            try await connect()
            return
        } catch {
            log.info("[MicClient] Direct connect failed, will launch helper")
            disconnect(notify: false)
        }

        try await launchHelperIfNeeded()

        var lastError: Error = MicClientError.notConnected
        for attempt in 0..<40 {
            do {
                try await Task.sleep(for: .milliseconds(250))
                try await connect()
                log.info("[MicClient] Connected after \(attempt + 1) retries")
                return
            } catch {
                lastError = error
                disconnect(notify: false)
            }
        }

        log.error("[MicClient] Failed to connect after 40 retries: \(lastError)")
        throw lastError
    }

    private func connect() async throws {
        disconnect(notify: false)

        guard let url = URL(string: "ws://\(host):\(port)") else {
            throw MicClientError.invalidResponse("Bad websocket URL")
        }

        let session = URLSession(configuration: .default)
        let webSocketTask = session.webSocketTask(with: url)

        self.session = session
        self.webSocketTask = webSocketTask

        webSocketTask.resume()
        startReceiveLoop()

        let pong = try await sendPing()
        guard pong else {
            throw MicClientError.invalidResponse("Ping failed")
        }

        isConnected = true
        log.info("Connected to TalkieMic")
    }

    private func sendPing() async throws -> Bool {
        guard let webSocketTask else {
            throw MicClientError.notConnected
        }

        let requestId = UUID().uuidString
        let request: [String: Any] = [
            "id": requestId,
            "method": "ping"
        ]

        let data = try JSONSerialization.data(withJSONObject: request)
        guard let text = String(data: data, encoding: .utf8) else {
            throw MicClientError.invalidResponse("Ping encoding failed")
        }

        let result = try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                await MainActor.run {
                    guard let self,
                          let pending = self.consumeRequest(id: requestId) else { return }
                    pending.continuation.resume(throwing: MicClientError.timeout)
                }
            }

            pendingRequests[requestId] = PendingRequest(
                continuation: continuation,
                timeoutTask: timeoutTask
            )

            Task {
                do {
                    try await webSocketTask.send(.string(text))
                } catch {
                    await MainActor.run {
                        guard let pending = self.consumeRequest(id: requestId) else { return }
                        pending.continuation.resume(throwing: error)
                    }
                }
            }
        }

        return result["pong"] as? Bool ?? false
    }

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                guard let webSocketTask = await MainActor.run(body: { self.webSocketTask }) else {
                    return
                }

                do {
                    let message = try await webSocketTask.receive()
                    await MainActor.run {
                        self.handleMessage(message)
                    }
                } catch {
                    await MainActor.run {
                        self.handleDisconnect(error: error)
                    }
                    return
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let value):
            text = value
        case .data(let data):
            text = String(decoding: data, as: UTF8.self)
        @unknown default:
            return
        }

        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let requestId = json["id"] as? String,
              let pending = consumeRequest(id: requestId) else {
            return
        }

        if let error = json["error"] as? String {
            pending.continuation.resume(throwing: MicClientError.serverError(error))
            return
        }

        pending.continuation.resume(returning: json["result"] as? [String: Any] ?? [:])
    }

    private func handleDisconnect(error: Error) {
        log.warning("TalkieMic disconnected", detail: error.localizedDescription)
        disconnect(notify: true, error: error)
    }

    private func disconnect(notify: Bool, error: Error = MicClientError.notConnected) {
        isConnected = false
        receiveTask?.cancel()
        receiveTask = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        session?.invalidateAndCancel()
        session = nil

        let pending = pendingRequests
        pendingRequests.removeAll()

        for (_, request) in pending {
            request.timeoutTask.cancel()
            request.continuation.resume(throwing: error)
        }

        if notify {
            onDisconnected?()
        }
    }

    private func launchHelperIfNeeded() async throws {
        guard let helperURL = resolveHelperURL() else {
            log.error("[MicClient] TalkieMic helper not found (bundleId=\(helperBundleIdentifier))")
            throw MicClientError.helperNotFound
        }

        log.info("[MicClient] Launching TalkieMic from \(helperURL.path)")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        try await NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration)
        log.info("[MicClient] TalkieMic launch requested")
    }

    private func resolveHelperURL() -> URL? {
        // 1. Embedded inside TalkieAgent.app/Contents/Helpers/
        let embeddedURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/TalkieMic.app")

        if FileManager.default.fileExists(atPath: embeddedURL.path) {
            log.info("[MicClient] Found TalkieMic embedded: \(embeddedURL.path)")
            return embeddedURL
        }

        // 2. Sibling of TalkieAgent.app (legacy/dev layout)
        let siblingURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("TalkieMic.app")

        if FileManager.default.fileExists(atPath: siblingURL.path) {
            log.info("[MicClient] Found TalkieMic as sibling: \(siblingURL.path)")
            return siblingURL
        }

        // 3. Launch Services lookup by bundle identifier (dev: separate DerivedData)
        if let lsURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: helperBundleIdentifier) {
            log.info("[MicClient] Found TalkieMic via Launch Services: \(lsURL.path)")
            return lsURL
        }

        log.error("[MicClient] TalkieMic not found — embedded=\(embeddedURL.path) sibling=\(siblingURL.path) bundleId=\(helperBundleIdentifier)")
        return nil
    }

    private var helperBundleIdentifier: String {
        let bundleId = Bundle.main.bundleIdentifier ?? "jdi.talkie.agent"
        if bundleId.contains(".staging") {
            return "jdi.talkie.mic.staging"
        }
        if bundleId.contains(".dev") {
            return "jdi.talkie.mic.dev"
        }
        return "jdi.talkie.mic"
    }
}
