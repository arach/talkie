//
//  ServiceBridge.swift
//  TalkieKit
//
//  Lightweight WebSocket JSON-RPC server using Network.framework.
//  Allows CLI tools and other local processes to invoke service methods
//  over a simple JSON protocol on localhost.
//
//  Wire protocol:
//    Request:  {"id": "1", "method": "syncNow", "params": {...}}
//    Response: {"id": "1", "result": {...}}  or  {"id": "1", "error": "..."}
//    Event:    {"event": "name", "data": {...}}  (push, no id)
//

import Foundation
import Network

private let log = Log(.system)

/// A WebSocket JSON-RPC server that binds to localhost on a given port.
/// Services register method handlers; the bridge dispatches incoming requests.
public final class ServiceBridge: @unchecked Sendable {

    public typealias Handler = (
        _ params: [String: Any]?,
        _ reply: @escaping (_ result: [String: Any]?, _ error: String?) -> Void
    ) -> Void

    public typealias StreamingHandler = (
        _ params: [String: Any]?,
        _ progress: @escaping (_ event: String, _ data: [String: Any]) -> Void,
        _ reply: @escaping (_ result: [String: Any]?, _ error: String?) -> Void
    ) -> Void

    /// Called when a WebSocket client disconnects. Parameter is the connection's unique ID.
    public var onClientDisconnected: ((_ connectionID: ObjectIdentifier) -> Void)?

    private let port: UInt16
    private let bindAddress: String
    private let serviceName: String
    private let queue: DispatchQueue
    private let handlersLock = NSLock()
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var handlers: [String: Handler] = [:]
    private var streamingHandlers: [String: StreamingHandler] = [:]

    public init(port: UInt16, serviceName: String, bindAddress: String = "127.0.0.1") {
        self.port = port
        self.serviceName = serviceName
        self.bindAddress = bindAddress
        self.queue = DispatchQueue(label: "to.talkie.app.bridge.\(serviceName.lowercased())")
    }

    // MARK: - Handler Registration

    /// Register a method handler. Thread-safe — call before or after start().
    public func handle(_ method: String, _ handler: @escaping Handler) {
        handlersLock.lock()
        handlers[method] = handler
        handlersLock.unlock()
    }

    /// Register a streaming handler that can send progress events before the final reply.
    public func handleStreaming(_ method: String, _ handler: @escaping StreamingHandler) {
        handlersLock.lock()
        streamingHandlers[method] = handler
        handlersLock.unlock()
    }

    // MARK: - Lifecycle

    public func start() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(bindAddress),
            port: NWEndpoint.Port(rawValue: port)!
        )

        // Add WebSocket protocol on top of TCP
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        do {
            listener = try NWListener(using: params)
        } catch {
            log.error("[\(serviceName)] ServiceBridge failed to create listener: \(error)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                log.info("[\(self.serviceName)] ServiceBridge listening on ws://\(self.bindAddress):\(self.port)")
            case .failed(let error):
                log.error("[\(self.serviceName)] ServiceBridge listener failed: \(error)")
                self.listener?.cancel()
            case .cancelled:
                log.info("[\(self.serviceName)] ServiceBridge listener cancelled")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.acceptConnection(connection)
        }

        listener?.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        queue.sync {
            for conn in connections { conn.cancel() }
            connections.removeAll()
        }
        log.info("[\(serviceName)] ServiceBridge stopped")
    }

    // MARK: - Connections

    private func acceptConnection(_ connection: NWConnection) {
        queue.async { self.connections.append(connection) }

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                log.debug("[\(self.serviceName)] WebSocket client connected")
                self.receiveMessage(on: connection)
            case .failed(let error):
                log.warning("[\(self.serviceName)] WebSocket connection failed: \(error)")
                self.removeConnection(connection)
            case .cancelled:
                self.removeConnection(connection)
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func removeConnection(_ connection: NWConnection) {
        let connID = ObjectIdentifier(connection)
        queue.async {
            let hadConnection = self.connections.contains { $0 === connection }
            self.connections.removeAll { $0 === connection }
            if hadConnection {
                self.onClientDisconnected?(connID)
            }
        }
    }

    // MARK: - WebSocket Message Handling

    private func receiveMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, context, isComplete, error in
            guard let self else { return }

            if let error {
                // posix(57) = socket not connected — normal close
                if case .posix(let code) = error as? NWError, code == .ENOTCONN {
                    connection.cancel()
                    return
                }
                log.warning("[\(self.serviceName)] WebSocket receive error: \(error)")
                connection.cancel()
                return
            }

            if let content {
                let text = String(data: content, encoding: .utf8) ?? ""
                self.handleTextMessage(text, on: connection)
            }

            // Continue receiving — for WebSocket, isComplete means the message frame
            // is complete, not the connection. Always listen for next message.
            self.receiveMessage(on: connection)
        }
    }

    private func handleTextMessage(_ text: String, on connection: NWConnection) {
        guard !text.isEmpty else { return }

        // Parse JSON
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            sendError(id: nil, message: "Invalid JSON", on: connection)
            return
        }

        let id = json["id"] as? String
        guard let method = json["method"] as? String else {
            sendError(id: id, message: "Missing 'method' field", on: connection)
            return
        }

        var params = json["params"] as? [String: Any] ?? [:]
        // Inject connection identity so handlers can track per-connection state
        params["_connectionID"] = "\(ObjectIdentifier(connection).hashValue)"

        // Look up handler (lock-based access — safe to call from any queue)
        handlersLock.lock()
        let streamingHandler: StreamingHandler? = streamingHandlers[method]
        let handler: Handler? = streamingHandler == nil ? handlers[method] : nil
        handlersLock.unlock()

        log.debug("[\(serviceName)] \(method) called")

        if let streamingHandler {
            let progress: (_ event: String, _ data: [String: Any]) -> Void = { [weak self, weak connection] event, data in
                guard let self, let connection else { return }
                var payload: [String: Any] = ["event": event, "data": data]
                if let id { payload["id"] = id }
                self.sendJSON(payload, on: connection)
            }

            let reply: (_ result: [String: Any]?, _ error: String?) -> Void = { [weak self, weak connection] result, error in
                guard let self, let connection else { return }
                if let error {
                    self.sendError(id: id, message: error, on: connection)
                } else {
                    self.sendResult(id: id, result: result ?? [:], on: connection)
                }
            }

            streamingHandler(params as [String: Any]?, progress, reply)
        } else if let handler {
            handler(params as [String: Any]?) { [weak self, weak connection] result, error in
                guard let self, let connection else { return }
                if let error {
                    self.sendError(id: id, message: error, on: connection)
                } else {
                    self.sendResult(id: id, result: result ?? [:], on: connection)
                }
            }
        } else {
            sendError(id: id, message: "Unknown method: \(method)", on: connection)
        }
    }

    // MARK: - Response Sending

    private func sendResult(id: String?, result: [String: Any], on connection: NWConnection) {
        var response: [String: Any] = ["result": result]
        if let id { response["id"] = id }
        sendJSON(response, on: connection)
    }

    private func sendError(id: String?, message: String, on connection: NWConnection) {
        var response: [String: Any] = ["error": message]
        if let id { response["id"] = id }
        sendJSON(response, on: connection)
    }

    /// Send a push event to all connected clients (for future streaming use).
    public func pushEvent(_ event: String, data: [String: Any]) {
        let payload: [String: Any] = ["event": event, "data": data]
        queue.async {
            for connection in self.connections {
                self.sendJSON(payload, on: connection)
            }
        }
    }

    private func sendJSON(_ object: [String: Any], on connection: NWConnection) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else {
            log.warning("[\(serviceName)] Failed to serialize JSON response")
            return
        }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "ws-response", metadata: [metadata])
        connection.send(content: data, contentContext: context, completion: .contentProcessed { error in
            if let error {
                log.warning("[\(self.serviceName)] WebSocket send error: \(error)")
            }
        })
    }
}
