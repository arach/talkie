//
//  TalkieServer.swift
//  Talkie
//
//  HTTP server for receiving message requests from Bridge.
//  Listens on port 8766 and forwards to TalkieLive via XPC.
//

import Foundation
import Network
import TalkieKit

private let log = Log(.system)

// MARK: - Error Messages

/// Actionable error messages with troubleshooting steps
private enum TalkieServerError {
    static let talkieLiveNotConnected = """
        TalkieLive not connected. Troubleshooting:
        1. Check TalkieLive is running (look for menu bar icon)
        2. Ensure same build environment (both from Xcode or both from /Applications)
        3. Verify Accessibility permission is granted (System Settings → Privacy & Security → Accessibility)
        4. Try restarting TalkieLive from Talkie menu bar
        """

    static let xpcConnectionFailed = """
        XPC connection failed. This usually means:
        1. TalkieLive crashed or was force-quit
        2. macOS invalidated the XPC connection
        3. Different code signing between apps
        Try: Restart TalkieLive from Talkie menu, or restart both apps
        """

    static let noTerminalFound = """
        No terminal window found for this project. Troubleshooting:
        1. Open a terminal in the project directory
        2. Start a Claude Code session (run 'claude')
        3. Make sure the terminal window title shows the project path
        4. Check Accessibility permissions for your terminal app
        """
}

/// Request body for /message endpoint
/// Accepts either text OR audio (base64) - audio gets transcribed first
private struct MessageRequest: Codable {
    let sessionId: String
    let projectPath: String?  // Full path for terminal matching
    let text: String?  // Direct text to send
    let audio: String?  // Base64 encoded audio (alternative to text)
    let format: String?  // Audio format: "wav", "m4a", etc.
}

/// Response for /message endpoint
private struct MessageResponse: Codable {
    let success: Bool
    let error: String?
    let transcript: String?  // For audio endpoint
    let deliveredAt: String?  // ISO timestamp when delivered
    let insertedText: String?  // The actual text that was inserted

    init(success: Bool, error: String? = nil, transcript: String? = nil, deliveredAt: String? = nil, insertedText: String? = nil) {
        self.success = success
        self.error = error
        self.transcript = transcript
        self.deliveredAt = deliveredAt
        self.insertedText = insertedText
    }
}

/// Local HTTP server for Bridge communication
/// Receives message requests and forwards to TalkieLive via XPC
@MainActor
final class TalkieServer {
    static let shared = TalkieServer()

    private var listener: NWListener?
    private let port: UInt16 = 8766

    // Get XPC manager dynamically from ServiceManager (handles reconnection)
    private var xpcManager: XPCServiceManager<TalkieLiveXPCServiceProtocol>? {
        ServiceManager.shared.live.xpcManager
    }

    var isRunning: Bool {
        listener?.state == .ready
    }

    private init() {}

    // MARK: - Public API

    func start(xpcManager: XPCServiceManager<TalkieLiveXPCServiceProtocol>? = nil) {
        // xpcManager parameter kept for API compatibility but not used
        // We now get it dynamically from ServiceManager

        guard listener == nil else {
            log.debug("TalkieServer already running")
            return
        }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleStateUpdate(state)
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleConnection(connection)
                }
            }

            listener?.start(queue: .main)
            log.info("TalkieServer starting on port \(port)")
        } catch {
            log.error("Failed to start TalkieServer: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        log.info("TalkieServer stopped")
    }

    // MARK: - Private

    private func handleStateUpdate(_ state: NWListener.State) {
        switch state {
        case .ready:
            log.info("TalkieServer ready on port \(port)")
        case .failed(let error):
            log.error("TalkieServer failed: \(error)")
            listener = nil
        case .cancelled:
            log.info("TalkieServer cancelled")
        default:
            break
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.receiveRequest(connection)
                case .failed(let error):
                    log.error("Connection failed: \(error)")
                    connection.cancel()
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
    }

    private func receiveRequest(_ connection: NWConnection) {
        // First, receive headers to get Content-Length
        receiveHTTPRequest(connection: connection, accumulated: Data()) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let data):
                Task { @MainActor in
                    await self.processRequest(data, connection: connection)
                }
            case .failure(let error):
                log.error("Receive error: \(error)")
                connection.cancel()
            }
        }
    }

    /// Receive HTTP request: parse headers for Content-Length, then read exact body size
    private func receiveHTTPRequest(connection: NWConnection, accumulated: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                completion(.failure(error))
                return
            }

            var totalData = accumulated
            if let data {
                totalData.append(data)
            }

            // Check if we have complete headers (ends with \r\n\r\n)
            if let headerEndRange = totalData.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = totalData[..<headerEndRange.lowerBound]
                let bodyStartIndex = headerEndRange.upperBound

                // Parse Content-Length from headers
                if let headerString = String(data: headerData, encoding: .utf8) {
                    let contentLength = self.parseContentLength(from: headerString)
                    let currentBodyLength = totalData.count - bodyStartIndex

                    if currentBodyLength >= contentLength {
                        // We have all the data
                        log.debug("Received complete HTTP request: \(totalData.count) bytes (body: \(contentLength))")
                        completion(.success(totalData))
                    } else {
                        // Need more body data
                        let remaining = contentLength - currentBodyLength
                        log.debug("Need \(remaining) more bytes (have \(currentBodyLength)/\(contentLength))")
                        self.receiveRemainingBody(connection: connection, accumulated: totalData, targetSize: totalData.count + remaining, completion: completion)
                    }
                } else {
                    completion(.failure(NSError(domain: "TalkieServer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid header encoding"])))
                }
            } else if isComplete {
                // Connection closed before headers complete - process what we have
                log.debug("Connection closed with \(totalData.count) bytes")
                completion(.success(totalData))
            } else {
                // Headers not complete yet, keep receiving
                self.receiveHTTPRequest(connection: connection, accumulated: totalData, completion: completion)
            }
        }
    }

    /// Continue receiving until we have targetSize bytes
    private func receiveRemainingBody(connection: NWConnection, accumulated: Data, targetSize: Int, completion: @escaping (Result<Data, Error>) -> Void) {
        let remaining = targetSize - accumulated.count
        connection.receive(minimumIncompleteLength: 1, maximumLength: min(remaining, 10_485_760)) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                completion(.failure(error))
                return
            }

            var totalData = accumulated
            if let data {
                totalData.append(data)
            }

            if totalData.count >= targetSize {
                log.debug("Received complete body: \(totalData.count) bytes")
                completion(.success(totalData))
            } else if isComplete {
                // Connection closed early - process what we have
                log.warning("Connection closed early: got \(totalData.count)/\(targetSize) bytes")
                completion(.success(totalData))
            } else {
                // Keep receiving
                self.receiveRemainingBody(connection: connection, accumulated: totalData, targetSize: targetSize, completion: completion)
            }
        }
    }

    /// Parse Content-Length header value
    private func parseContentLength(from headers: String) -> Int {
        let lines = headers.components(separatedBy: "\r\n")
        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(value) ?? 0
            }
        }
        return 0
    }

    private func processRequest(_ data: Data, connection: NWConnection) async {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendResponse(connection, statusCode: 400, body: "Invalid request")
            return
        }

        // Parse HTTP request
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection, statusCode: 400, body: "No request line")
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection, statusCode: 400, body: "Invalid request line")
            return
        }

        let method = parts[0]
        let path = parts[1]

        log.info("TalkieServer received: \(method) '\(path)'")

        // Find body (after empty line)
        var body: Data?
        if let emptyLineIndex = lines.firstIndex(of: "") {
            let bodyLines = lines[(emptyLineIndex + 1)...]
            let bodyString = bodyLines.joined(separator: "\r\n")
            body = bodyString.data(using: .utf8)
        }

        // Route request
        if path == "/health" && method == "GET" {
            let response = ["status": "ok", "service": "Talkie"]
            sendJSONResponse(connection, statusCode: 200, body: response)
        } else if (path == "/message" || path == "/inject") && method == "POST" {
            // /message is preferred, /inject for backwards compat
            // Empty text = force enter (just press Enter without inserting)
            await handleMessage(connection, body: body)
        } else if path == "/windows/claude" && method == "GET" {
            await handleListClaudeWindows(connection)
        } else if path == "/screenshot/terminals" && method == "GET" {
            await handleCaptureTerminals(connection)
        } else if path.hasPrefix("/screenshot/window/") && method == "GET" {
            let windowIdStr = String(path.dropFirst("/screenshot/window/".count))
            if let windowId = UInt32(windowIdStr) {
                await handleCaptureWindow(connection, windowID: windowId)
            } else {
                sendResponse(connection, statusCode: 400, body: "Invalid window ID")
            }
        } else {
            log.warning("TalkieServer 404: method='\(method)' path='\(path)'")
            sendResponse(connection, statusCode: 404, body: "Not found")
        }
    }

    private func handleMessage(_ connection: NWConnection, body: Data?) async {
        guard let body else {
            sendJSONResponse(connection, statusCode: 400, body: MessageResponse(success: false, error: "No body"))
            return
        }

        let request: MessageRequest
        do {
            request = try JSONDecoder().decode(MessageRequest.self, from: body)
        } catch {
            sendJSONResponse(connection, statusCode: 400, body: MessageResponse(success: false, error: "Invalid JSON: \(error)"))
            return
        }

        // Determine the text to send - either direct text or transcribed audio
        let textToSend: String
        var transcript: String? = nil

        if let audio = request.audio, !audio.isEmpty {
            // Audio mode: transcribe first
            let format = request.format ?? "m4a"
            log.info("Audio message for session: \(request.sessionId), format: \(format), \(audio.count) chars base64")

            // Decode base64 audio
            guard let audioData = Data(base64Encoded: audio) else {
                sendJSONResponse(connection, statusCode: 400, body: MessageResponse(success: false, error: "Invalid base64 audio"))
                return
            }

            log.info("Decoded audio: \(audioData.count) bytes")

            // Save to temp file
            let tempDir = FileManager.default.temporaryDirectory
            let audioPath = tempDir.appendingPathComponent("\(UUID().uuidString).\(format)")

            do {
                try audioData.write(to: audioPath)
            } catch {
                sendJSONResponse(connection, statusCode: 500, body: MessageResponse(success: false, error: "Failed to save audio: \(error)"))
                return
            }

            defer {
                try? FileManager.default.removeItem(at: audioPath)
            }

            // Transcribe via TalkieEngine
            do {
                // Use Parakeet - already warm/loaded from local dictation
                let modelId = "parakeet:v3"
                log.info("Transcribing with model: \(modelId)")

                transcript = try await EngineClient.shared.transcribe(
                    audioPath: audioPath.path,
                    modelId: modelId,
                    priority: .high,  // Real-time request from iOS
                    postProcess: .dictionary  // Apply dictionary replacements
                )
                log.info("Transcribed: \(transcript?.prefix(50) ?? "")...")
            } catch {
                log.error("Transcription failed: \(error)")
                sendJSONResponse(connection, statusCode: 500, body: MessageResponse(success: false, error: "Transcription failed: \(error.localizedDescription)"))
                return
            }

            // Skip empty transcriptions
            guard let t = transcript, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                log.warning("Empty transcription, skipping send")
                sendJSONResponse(connection, statusCode: 200, body: MessageResponse(success: true, error: nil, transcript: ""))
                return
            }

            textToSend = t
        } else if let text = request.text {
            // Text mode: use directly (empty text = force Enter only)
            if text.isEmpty {
                log.info("Force Enter for session: \(request.sessionId)")
            } else {
                log.info("Message for session: \(request.sessionId), text: \(text.prefix(50))...")
            }
            textToSend = text
        } else {
            sendJSONResponse(connection, statusCode: 400, body: MessageResponse(success: false, error: "Either 'text' or 'audio' is required"))
            return
        }

        // Record in message queue for visibility
        let messageId = MessageQueue.shared.recordIncoming(
            sessionId: request.sessionId,
            projectPath: request.projectPath,
            text: textToSend,
            source: .bridge,
            metadata: ["endpoint": "/message", "isAudio": request.audio != nil ? "true" : "false"]
        )
        MessageQueue.shared.updateStatus(messageId, status: .sending)
        let xpcStartTime = Date()

        // Forward to TalkieLive via XPC
        // Use a flag to track if we've already responded (XPC error vs reply callback)
        var hasResponded = false
        let respondOnce: (Int, MessageResponse, Bool) -> Void = { [weak self] statusCode, response, success in
            guard let self, !hasResponded else { return }
            hasResponded = true
            let durationMs = Int(Date().timeIntervalSince(xpcStartTime) * 1000)
            if success {
                MessageQueue.shared.updateStatus(messageId, status: .sent, xpcDurationMs: durationMs)
            }
            self.sendJSONResponse(connection, statusCode: statusCode, body: response)
        }

        guard let proxy = xpcManager?.remoteObjectProxy(errorHandler: { error in
            log.error("XPC error: \(error)")
            Task { @MainActor in
                let durationMs = Int(Date().timeIntervalSince(xpcStartTime) * 1000)
                let errorMsg = "\(TalkieServerError.xpcConnectionFailed)\n\nTechnical: \(error.localizedDescription)"
                MessageQueue.shared.updateStatus(messageId, status: .failed, error: errorMsg, xpcDurationMs: durationMs)
                respondOnce(503, MessageResponse(success: false, error: errorMsg, transcript: transcript), false)
            }
        }) else {
            log.error("TalkieLive not connected")
            MessageQueue.shared.updateStatus(messageId, status: .failed, error: TalkieServerError.talkieLiveNotConnected)
            sendJSONResponse(connection, statusCode: 503, body: MessageResponse(
                success: false,
                error: TalkieServerError.talkieLiveNotConnected,
                transcript: transcript
            ))
            return
        }

        // Call the XPC method (submit: true to press Enter and send to Claude)
        proxy.appendMessage(textToSend, sessionId: request.sessionId, projectPath: request.projectPath, submit: true) { success, error in
            Task { @MainActor in
                let durationMs = Int(Date().timeIntervalSince(xpcStartTime) * 1000)
                if success {
                    log.info("Message sent via XPC in \(durationMs)ms")
                    let deliveredAt = ISO8601DateFormatter().string(from: Date())
                    respondOnce(200, MessageResponse(
                        success: true,
                        error: nil,
                        transcript: transcript,
                        deliveredAt: deliveredAt,
                        insertedText: textToSend
                    ), true)
                } else {
                    log.error("Message failed: \(error ?? "unknown error")")
                    MessageQueue.shared.updateStatus(messageId, status: .failed, error: error, xpcDurationMs: durationMs)
                    respondOnce(500, MessageResponse(success: false, error: error, transcript: transcript), false)
                }
            }
        }
    }

    // MARK: - Screenshot Handlers

    private func handleListClaudeWindows(_ connection: NWConnection) async {
        guard let proxy = xpcManager?.remoteObjectProxy(errorHandler: { error in
            log.error("XPC error: \(error)")
        }) else {
            sendErrorResponse(connection, statusCode: 503, error: TalkieServerError.talkieLiveNotConnected)
            return
        }

        proxy.listClaudeWindows { windowsJSON in
            Task { @MainActor in
                if let data = windowsJSON,
                   let windows = try? JSONSerialization.jsonObject(with: data),
                   let wrapped = try? JSONSerialization.data(withJSONObject: ["windows": windows]) {
                    self.sendRawJSONResponse(connection, statusCode: 200, jsonData: wrapped)
                } else {
                    self.sendErrorResponse(connection, statusCode: 500, error: "Failed to list windows")
                }
            }
        }
    }

    private func handleCaptureWindow(_ connection: NWConnection, windowID: UInt32) async {
        guard let proxy = xpcManager?.remoteObjectProxy(errorHandler: { error in
            log.error("XPC error: \(error)")
        }) else {
            sendErrorResponse(connection, statusCode: 503, error: TalkieServerError.talkieLiveNotConnected)
            return
        }

        proxy.captureWindow(windowID: windowID) { imageData, error in
            Task { @MainActor in
                if let data = imageData {
                    self.sendImageResponse(connection, data: data, contentType: "image/jpeg")
                } else {
                    self.sendErrorResponse(connection, statusCode: 500, error: error ?? "Failed to capture window")
                }
            }
        }
    }

    private func handleCaptureTerminals(_ connection: NWConnection) async {
        guard let proxy = xpcManager?.remoteObjectProxy(errorHandler: { error in
            log.error("XPC error: \(error)")
        }) else {
            sendErrorResponse(connection, statusCode: 503, error: TalkieServerError.talkieLiveNotConnected)
            return
        }

        proxy.captureTerminalWindows { screenshotsJSON, error in
            Task { @MainActor in
                if let data = screenshotsJSON {
                    // Forward the raw JSON directly
                    self.sendRawJSONResponse(connection, statusCode: 200, jsonData: data)
                } else {
                    self.sendErrorResponse(connection, statusCode: 500, error: error ?? "Failed to capture terminals")
                }
            }
        }
    }

    // MARK: - Response Helpers

    private func sendRawJSONResponse(_ connection: NWConnection, statusCode: Int, jsonData: Data) {
        let statusText = statusCode == 200 ? "OK" : "Error"
        let headers = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: application/json\r
        Content-Length: \(jsonData.count)\r
        Connection: close\r
        \r

        """

        var responseData = Data(headers.utf8)
        responseData.append(jsonData)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendErrorResponse(_ connection: NWConnection, statusCode: Int, error: String) {
        // Use proper JSON encoding to escape special characters
        let errorDict = ["error": error]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: errorDict),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            // Fallback to plain text if JSON encoding fails
            sendResponse(connection, statusCode: statusCode, body: error)
            return
        }

        let headers = """
        HTTP/1.1 \(statusCode) Error\r
        Content-Type: application/json\r
        Content-Length: \(jsonData.count)\r
        Connection: close\r
        \r
        \(jsonString)
        """

        connection.send(content: headers.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendImageResponse(_ connection: NWConnection, data: Data, contentType: String) {
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: \(contentType)\r
        Content-Length: \(data.count)\r
        Connection: close\r
        \r

        """

        var responseData = Data(response.utf8)
        responseData.append(data)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendResponse(_ connection: NWConnection, statusCode: Int, body: String) {
        let statusText = statusCode == 200 ? "OK" : "Error"
        let response = """
        HTTP/1.1 \(statusCode) \(statusText)\r
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

    private func sendJSONResponse<T: Encodable>(_ connection: NWConnection, statusCode: Int, body: T) {
        let statusText = statusCode == 200 ? "OK" : "Error"

        do {
            let jsonData = try JSONEncoder().encode(body)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            let response = """
            HTTP/1.1 \(statusCode) \(statusText)\r
            Content-Type: application/json\r
            Content-Length: \(jsonData.count)\r
            Connection: close\r
            \r
            \(jsonString)
            """

            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            sendResponse(connection, statusCode: 500, body: "JSON encoding error")
        }
    }
}
