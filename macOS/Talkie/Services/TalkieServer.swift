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

/// Request body for /message endpoint
private struct MessageRequest: Codable {
    let sessionId: String
    let text: String
}

/// Response for /message endpoint
private struct MessageResponse: Codable {
    let success: Bool
    let error: String?
}

/// Local HTTP server for Bridge communication
/// Receives message requests and forwards to TalkieLive via XPC
@MainActor
final class TalkieServer {
    static let shared = TalkieServer()

    private var listener: NWListener?
    private let port: UInt16 = 8766

    // XPC manager for TalkieLive
    private var xpcManager: XPCServiceManager<TalkieLiveXPCServiceProtocol>?

    var isRunning: Bool {
        listener?.state == .ready
    }

    private init() {}

    // MARK: - Public API

    func start(xpcManager: XPCServiceManager<TalkieLiveXPCServiceProtocol>) {
        self.xpcManager = xpcManager

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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                log.error("Receive error: \(error)")
                connection.cancel()
                return
            }

            if let data {
                Task { @MainActor in
                    await self.processRequest(data, connection: connection)
                }
            }

            if isComplete {
                connection.cancel()
            }
        }
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

        log.debug("TalkieServer: \(method) \(path)")

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
            await handleMessage(connection, body: body)
        } else {
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

        log.info("Message for session: \(request.sessionId), text: \(request.text.prefix(50))...")

        // Forward to TalkieLive via XPC
        guard let proxy = xpcManager?.remoteObjectProxy(errorHandler: { error in
            log.error("XPC error: \(error)")
        }) else {
            log.error("TalkieLive not connected")
            sendJSONResponse(connection, statusCode: 503, body: MessageResponse(
                success: false,
                error: "TalkieLive not connected"
            ))
            return
        }

        // Call the XPC method
        proxy.appendMessage(request.text, sessionId: request.sessionId) { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }

                if success {
                    log.info("Message sent via XPC")
                    self.sendJSONResponse(connection, statusCode: 200, body: MessageResponse(success: true, error: nil))
                } else {
                    log.error("Message failed: \(error ?? "unknown error")")
                    self.sendJSONResponse(connection, statusCode: 500, body: MessageResponse(success: false, error: error))
                }
            }
        }
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
