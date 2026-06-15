//
//  HeadlessServer.swift
//  TalkieHeadless
//
//  HTTP server for extension API.
//  Uses Network.framework for lightweight HTTP handling.
//

import Foundation
import Network
import AppKit

@MainActor
final class HeadlessServer {
    static let shared = HeadlessServer()

    private var listener: NWListener?
    private var connections: [NWConnection] = []

    // Services
    private let engineClient = HeadlessEngineClient()
    private let liveClient = HeadlessLiveClient()

    // Active transcription sessions (sessionId → capture sessionId from Live)
    private var transcriptionSessions: [String: String] = [:]

    private init() {}

    func start(port: UInt16) async throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                HeadlessConsole.info("[HeadlessServer] Listening on port \(port)")
            case .failed(let error):
                HeadlessConsole.info("[HeadlessServer] Failed: \(error)")
            case .cancelled:
                HeadlessConsole.info("[HeadlessServer] Cancelled")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }

        listener?.start(queue: .main)

        // Connect to TalkieEngine
        await engineClient.connect()

        // Connect to TalkieAgent
        await liveClient.connect()
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for conn in connections {
            conn.cancel()
        }
        connections.removeAll()
    }

    private func handleConnection(_ connection: NWConnection) {
        connections.append(connection)

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.receiveData(on: connection)
                case .failed, .cancelled:
                    self?.removeConnection(connection)
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
    }

    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
    }

    private func receiveData(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                if let data = data, !data.isEmpty {
                    await self?.handleRequest(data: data, connection: connection)
                }

                if let error = error {
                    HeadlessConsole.info("[HeadlessServer] Receive error: \(error)")
                    connection.cancel()
                    return
                }

                if isComplete {
                    connection.cancel()
                } else {
                    self?.receiveData(on: connection)
                }
            }
        }
    }

    private func handleRequest(data: Data, connection: NWConnection) async {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, status: 400, body: "Invalid request")
            return
        }

        // Parse HTTP request
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, status: 400, body: "Invalid request")
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: 400, body: "Invalid request")
            return
        }

        let method = parts[0]
        let path = parts[1]

        // Extract body for POST requests
        var body: Data?
        if let bodyStart = requestString.range(of: "\r\n\r\n") {
            let bodyString = String(requestString[bodyStart.upperBound...])
            body = bodyString.data(using: .utf8)
        }

        // Route request
        await routeRequest(method: method, path: path, body: body, connection: connection)
    }

    private func routeRequest(method: String, path: String, body: Data?, connection: NWConnection) async {
        HeadlessConsole.info("[HeadlessServer] \(method) \(path)")

        switch (method, path) {
        case ("GET", "/health"):
            await handleHealth(connection: connection)

        case ("GET", "/transcribe/preflight"):
            await handleTranscribePreflight(connection: connection)

        case ("POST", "/transcribe/start"):
            handleTranscribeStart(body: body, connection: connection)

        case ("POST", "/transcribe/stop"):
            handleTranscribeStop(body: body, connection: connection)

        case ("POST", "/diff/compute"):
            handleDiffCompute(body: body, connection: connection)

        case ("POST", "/storage/clipboard/write"):
            handleClipboardWrite(body: body, connection: connection)

        case ("GET", "/storage/clipboard/read"):
            handleClipboardRead(connection: connection)

        default:
            sendResponse(connection: connection, status: 404, body: "Not found")
        }
    }

    // MARK: - Handlers

    private func handleHealth(connection: NWConnection) async {
        let response: [String: Any] = [
            "status": "ok",
            "service": "TalkieHeadless",
            "engineConnected": await engineClient.isConnected,
            "liveConnected": await liveClient.isConnected
        ]
        sendJSON(connection: connection, status: 200, body: response)
    }

    private func handleTranscribePreflight(connection: NWConnection) async {
        var checks: [[String: Any]] = []
        var ready = true

        // Check TalkieAgent connection (attempt reconnect if needed)
        let liveStatus = await liveClient.preflight()
        checks.append([
            "name": "TalkieAgent",
            "ok": liveStatus.connected,
            "detail": liveStatus.detail
        ])
        if !liveStatus.connected { ready = false }

        // Check microphone permission (via TalkieAgent state)
        checks.append([
            "name": "Microphone",
            "ok": liveStatus.microphoneAuthorized,
            "detail": liveStatus.microphoneAuthorized ? "Authorized" : "Permission not granted"
        ])
        if !liveStatus.microphoneAuthorized { ready = false }

        // Check TalkieEngine connection (attempt reconnect if needed)
        let engineConnected = await engineClient.checkConnection()
        checks.append([
            "name": "TalkieEngine",
            "ok": engineConnected,
            "detail": engineConnected ? "Connected" : "Not running or XPC not registered"
        ])
        if !engineConnected { ready = false }

        let response: [String: Any] = [
            "ready": ready,
            "checks": checks
        ]
        sendJSON(connection: connection, status: 200, body: response)
    }

    private func handleTranscribeStart(body: Data?, connection: NWConnection) {
        Task {
            do {
                // Start ephemeral capture via TalkieAgent (will auto-reconnect if needed)
                let captureSessionId = try await liveClient.startCapture()

                // Create our session ID and map it
                let sessionId = UUID().uuidString
                transcriptionSessions[sessionId] = captureSessionId

                HeadlessConsole.info("[HeadlessServer] Transcribe started: \(sessionId) -> Live:\(captureSessionId)")

                let response: [String: Any] = [
                    "sessionId": sessionId,
                    "status": "recording"
                ]
                sendJSON(connection: connection, status: 200, body: response)
            } catch {
                HeadlessConsole.info("[HeadlessServer] Transcribe start error: \(error)")
                sendJSON(connection: connection, status: 500, body: [
                    "error": error.localizedDescription
                ])
            }
        }
    }

    private func handleTranscribeStop(body: Data?, connection: NWConnection) {
        // Parse session ID from body if provided
        var sessionId: String?
        if let body = body,
           let request = try? JSONDecoder().decode(TranscribeStopRequest.self, from: body) {
            sessionId = request.sessionId
        }

        // If no session ID provided, use the most recent one
        if sessionId == nil {
            sessionId = transcriptionSessions.keys.first
        }

        guard let sessionId = sessionId,
              let captureSessionId = transcriptionSessions[sessionId] else {
            sendJSON(connection: connection, status: 400, body: [
                "error": "No active transcription session"
            ])
            return
        }

        Task {
            do {
                // Stop capture and get audio file path
                let audioPath = try await liveClient.stopCapture(sessionId: captureSessionId)
                HeadlessConsole.info("[HeadlessServer] Got audio file: \(audioPath)")

                // Transcribe via Engine
                guard await engineClient.isConnected else {
                    sendJSON(connection: connection, status: 503, body: [
                        "error": "TalkieEngine not connected"
                    ])
                    return
                }

                let startTime = Date()
                let transcript = try await engineClient.transcribe(audioPath: audioPath)
                let duration = Date().timeIntervalSince(startTime)

                // Clean up session
                transcriptionSessions.removeValue(forKey: sessionId)

                // Clean up audio file
                try? FileManager.default.removeItem(atPath: audioPath)

                HeadlessConsole.info("[HeadlessServer] Transcription complete: \(transcript.prefix(50))... (\(duration)s)")

                let response: [String: Any] = [
                    "text": transcript,
                    "duration": duration
                ]
                sendJSON(connection: connection, status: 200, body: response)
            } catch {
                HeadlessConsole.info("[HeadlessServer] Transcribe stop error: \(error)")
                transcriptionSessions.removeValue(forKey: sessionId)
                sendJSON(connection: connection, status: 500, body: [
                    "error": error.localizedDescription
                ])
            }
        }
    }

    private func handleDiffCompute(body: Data?, connection: NWConnection) {
        guard let body = body,
              let request = try? JSONDecoder().decode(DiffRequest.self, from: body) else {
            sendResponse(connection: connection, status: 400, body: "Invalid request body")
            return
        }

        // Compute diff using simple algorithm
        let diff = computeDiff(original: request.original, proposed: request.proposed)
        let response: [String: Any] = [
            "diff": diff.map { $0.toDict() }
        ]
        sendJSON(connection: connection, status: 200, body: response)
    }

    private func handleClipboardWrite(body: Data?, connection: NWConnection) {
        guard let body = body,
              let request = try? JSONDecoder().decode(ClipboardWriteRequest.self, from: body) else {
            sendResponse(connection: connection, status: 400, body: "Invalid request body")
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(request.content, forType: .string)

        let response: [String: Any] = ["success": true]
        sendJSON(connection: connection, status: 200, body: response)
    }

    private func handleClipboardRead(connection: NWConnection) {
        let pasteboard = NSPasteboard.general
        let content = pasteboard.string(forType: .string) ?? ""

        let response: [String: Any] = ["content": content]
        sendJSON(connection: connection, status: 200, body: response)
    }

    // MARK: - Response Helpers

    private func sendResponse(connection: NWConnection, status: Int, body: String) {
        let statusText = httpStatusText(status)
        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: text/plain\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendJSON(connection: NWConnection, status: Int, body: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            sendResponse(connection: connection, status: 500, body: "JSON encoding failed")
            return
        }

        let statusText = httpStatusText(status)
        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: application/json\r
        Content-Length: \(jsonString.utf8.count)\r
        Connection: close\r
        \r
        \(jsonString)
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func httpStatusText(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "Unknown"
        }
    }
}

// MARK: - Request/Response Types

struct TranscribeStopRequest: Codable {
    let sessionId: String?
}

struct DiffRequest: Codable {
    let original: String
    let proposed: String
}

struct ClipboardWriteRequest: Codable {
    let content: String
}

// MARK: - Diff Algorithm

enum DiffOperation {
    case equal(String)
    case insert(String)
    case delete(String)

    func toDict() -> [String: String] {
        switch self {
        case .equal(let text):
            return ["type": "equal", "text": text]
        case .insert(let text):
            return ["type": "insert", "text": text]
        case .delete(let text):
            return ["type": "delete", "text": text]
        }
    }
}

func computeDiff(original: String, proposed: String) -> [DiffOperation] {
    // Simple word-based diff
    let originalWords = original.components(separatedBy: .whitespaces)
    let proposedWords = proposed.components(separatedBy: .whitespaces)

    var result: [DiffOperation] = []
    var i = 0, j = 0

    while i < originalWords.count || j < proposedWords.count {
        if i >= originalWords.count {
            // Rest is insertions
            result.append(.insert(proposedWords[j]))
            j += 1
        } else if j >= proposedWords.count {
            // Rest is deletions
            result.append(.delete(originalWords[i]))
            i += 1
        } else if originalWords[i] == proposedWords[j] {
            result.append(.equal(originalWords[i]))
            i += 1
            j += 1
        } else {
            // Simple: treat as delete + insert
            result.append(.delete(originalWords[i]))
            result.append(.insert(proposedWords[j]))
            i += 1
            j += 1
        }
    }

    return result
}
