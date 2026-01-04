//
//  BridgeServer.swift
//  TalkieLive
//
//  Local HTTP server for receiving commands from TalkieBridge.
//  Listens on port 8766 for inject requests.
//

import Foundation
import Network
import TalkieKit

private let log = Log(.system)

/// Request body for /inject endpoint
/// Bridge sends sessionId + text; TalkieLive looks up the terminal context
struct InjectRequest: Codable {
    let sessionId: String
    let text: String
}

/// Response for /inject endpoint
struct InjectResponse: Codable {
    let success: Bool
    let error: String?
}

/// Local HTTP server for bridge communication
@MainActor
final class BridgeServer {
    static let shared = BridgeServer()

    private var listener: NWListener?
    private let port: UInt16 = 8766

    var isRunning: Bool {
        listener?.state == .ready
    }

    private init() {}

    // MARK: - Public API

    func start() {
        guard listener == nil else {
            log.debug("BridgeServer already running")
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
            log.info("BridgeServer starting on port \(port)")
        } catch {
            log.error("Failed to start BridgeServer: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        log.info("BridgeServer stopped")
    }

    // MARK: - Private

    private func handleStateUpdate(_ state: NWListener.State) {
        switch state {
        case .ready:
            log.info("BridgeServer ready on port \(port)")
        case .failed(let error):
            log.error("BridgeServer failed: \(error)")
            listener = nil
        case .cancelled:
            log.info("BridgeServer cancelled")
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

        log.debug("BridgeServer: \(method) \(path)")

        // Find body (after empty line)
        var body: Data?
        if let emptyLineIndex = lines.firstIndex(of: "") {
            let bodyLines = lines[(emptyLineIndex + 1)...]
            let bodyString = bodyLines.joined(separator: "\r\n")
            body = bodyString.data(using: .utf8)
        }

        // Route request
        if path == "/health" && method == "GET" {
            let response = ["status": "ok", "service": "TalkieLive"]
            sendJSONResponse(connection, statusCode: 200, body: response)
        } else if path == "/inject" && method == "POST" {
            await handleInject(connection, body: body)
        } else {
            sendResponse(connection, statusCode: 404, body: "Not found")
        }
    }

    private func handleInject(_ connection: NWConnection, body: Data?) async {
        guard let body else {
            sendJSONResponse(connection, statusCode: 400, body: InjectResponse(success: false, error: "No body"))
            return
        }

        let request: InjectRequest
        do {
            request = try JSONDecoder().decode(InjectRequest.self, from: body)
        } catch {
            sendJSONResponse(connection, statusCode: 400, body: InjectResponse(success: false, error: "Invalid JSON: \(error)"))
            return
        }

        log.info("Inject request for session: \(request.sessionId), text: \(request.text.prefix(50))...")

        // Look up the terminal context for this session
        guard let context = BridgeContextMapper.shared.getContext(for: request.sessionId) else {
            // Context not found - try a terminal scan first
            log.info("No cached context for session, attempting terminal scan...")
            await MainActor.run {
                BridgeContextMapper.shared.refreshFromScan()
            }

            // Try again after scan
            guard let context = BridgeContextMapper.shared.getContext(for: request.sessionId) else {
                log.error("Could not find terminal for session: \(request.sessionId)")
                sendJSONResponse(connection, statusCode: 404, body: InjectResponse(
                    success: false,
                    error: "No terminal found for session '\(request.sessionId)'. Try dictating in that session first."
                ))
                return
            }

            await doInject(request.text, context: context, connection: connection)
            return
        }

        await doInject(request.text, context: context, connection: connection)
    }

    private func doInject(_ text: String, context: SessionContext, connection: NWConnection) async {
        log.info("Injecting into \(context.app) (\(context.bundleId))")

        // Use TextInserter to inject the text
        let success = await TextInserter.shared.insert(
            text,
            intoAppWithBundleID: context.bundleId,
            replaceSelection: false
        )

        if success {
            log.info("Text injected successfully into \(context.app)")
            sendJSONResponse(connection, statusCode: 200, body: InjectResponse(success: true, error: nil))
        } else {
            log.error("Text injection failed for \(context.app)")
            sendJSONResponse(connection, statusCode: 500, body: InjectResponse(success: false, error: "Injection failed"))
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
