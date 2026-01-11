//
//  DraftExtensionServer.swift
//  Talkie
//
//  WebSocket server for Draft Extension API.
//  Enables custom renderers to connect and interact with Drafts in real-time.
//
//  Protocol: ws://localhost:7847/draft
//
//  Talkie → Renderer:
//    - draft:state    { content, mode, wordCount, charCount }
//    - draft:revision { before, after, diff, instruction, provider, model }
//    - draft:resolved { accepted, content }
//
//  Renderer → Talkie:
//    - draft:update   { content }
//    - draft:refine   { instruction, constraints? }
//    - draft:accept
//    - draft:reject
//    - draft:save     { destination: "memo" | "clipboard" }
//    - renderer:connect { name, capabilities }
//

import Foundation
import Network
import TalkieKit

private let log = Log(.system)

// MARK: - Message Types

/// Messages sent from Talkie to connected renderers
enum DraftOutgoingMessage: Encodable {
    case state(DraftStateMessage)
    case revision(DraftRevisionMessage)
    case resolved(DraftResolvedMessage)
    case error(DraftErrorMessage)

    func encode(to encoder: Encoder) throws {
        switch self {
        case .state(let msg): try msg.encode(to: encoder)
        case .revision(let msg): try msg.encode(to: encoder)
        case .resolved(let msg): try msg.encode(to: encoder)
        case .error(let msg): try msg.encode(to: encoder)
        }
    }
}

struct DraftStateMessage: Codable {
    let type = "draft:state"
    let content: String
    let mode: String  // "editing" or "reviewing"
    let wordCount: Int
    let charCount: Int
}

struct DraftRevisionMessage: Codable {
    let type = "draft:revision"
    let before: String
    let after: String
    let diff: [DiffOperationDTO]
    let instruction: String
    let provider: String
    let model: String
}

struct DiffOperationDTO: Codable {
    let type: String  // "equal", "insert", "delete"
    let text: String
}

struct DraftResolvedMessage: Codable {
    let type = "draft:resolved"
    let accepted: Bool
    let content: String
}

struct DraftErrorMessage: Codable {
    let type = "draft:error"
    let error: String
}

/// Messages received from renderers
struct DraftIncomingMessage: Codable {
    let type: String
    let content: String?
    let instruction: String?
    let constraints: DraftConstraints?
    let destination: String?
    let name: String?
    let capabilities: [String]?
    let action: String?  // For capture: "start" or "stop"
    let token: String?   // Auth token for renderer:connect
    let version: String? // Protocol version for renderer:connect
}

/// Authentication required message
struct DraftAuthRequiredMessage: Codable {
    let type = "auth:required"
    let version: String
    let timeout: Int  // Seconds until disconnect
}

/// Transcription result message (sent after capture completes)
struct DraftTranscriptionMessage: Codable {
    let type = "draft:transcription"
    let text: String
    let append: Bool  // Whether to append to existing content
}

struct DraftConstraints: Codable {
    let maxLength: Int?
    let style: String?
    let format: String?
}

// MARK: - Connected Renderer

/// Represents a connected renderer client
/// Thread-safe via MainActor isolation (all access is on main thread)
@MainActor
final class ConnectedRenderer {
    let id: UUID
    let connection: NWConnection
    var name: String?
    var capabilities: [String] = []
    let connectedAt: Date
    var isAuthenticated: Bool = false

    init(connection: NWConnection) {
        self.id = UUID()
        self.connection = connection
        self.connectedAt = Date()
    }
}

// MARK: - Draft Extension Server

/// WebSocket server for the Draft Extension API
@MainActor
final class DraftExtensionServer {
    static let shared = DraftExtensionServer()

    private var listener: NWListener?
    private let port: UInt16 = 7847
    private var connectedRenderers: [UUID: ConnectedRenderer] = [:]

    /// Authentication token - renderers must send this in renderer:connect
    private(set) var authToken: String = ""

    /// Time allowed for authentication before disconnect (seconds)
    private let authTimeout: TimeInterval = 10

    /// Protocol version for compatibility checking
    static let protocolVersion = "1.0"

    /// Callback for incoming commands from renderers
    var onRefine: ((String, DraftConstraints?) async -> Void)?
    var onAccept: (() -> Void)?
    var onReject: (() -> Void)?
    var onUpdate: ((String) -> Void)?
    var onSave: ((String) -> Void)?  // "memo" or "clipboard"
    var onCaptureStart: (() -> Void)?
    var onCaptureStop: (() async -> String?)?  // Returns transcribed text

    var isRunning: Bool {
        listener?.state == .ready
    }

    var connectedCount: Int {
        connectedRenderers.count
    }

    var connectedRendererNames: [String] {
        connectedRenderers.values.compactMap { $0.name }
    }

    private init() {}

    // MARK: - Public API

    func start() {
        guard listener == nil else {
            log.debug("DraftExtensionServer already running")
            return
        }

        // Generate new auth token on each start
        authToken = generateAuthToken()
        log.info("DraftExtensionServer auth token: \(authToken)")

        do {
            // Create WebSocket parameters
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            // Add WebSocket protocol
            let wsOptions = NWProtocolWebSocket.Options()
            wsOptions.autoReplyPing = true
            params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleStateUpdate(state)
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleNewConnection(connection)
                }
            }

            listener?.start(queue: .main)
            log.info("DraftExtensionServer starting on port \(port)")
        } catch {
            log.error("Failed to start DraftExtensionServer: \(error)")
        }
    }

    func stop() {
        // Close all connections
        for renderer in connectedRenderers.values {
            renderer.connection.cancel()
        }
        connectedRenderers.removeAll()

        listener?.cancel()
        listener = nil
        log.info("DraftExtensionServer stopped")
    }

    // MARK: - Broadcasting

    /// Broadcast current draft state to all connected renderers
    func broadcastState(content: String, mode: String) {
        let words = content.split(separator: " ").count
        let chars = content.count

        let message = DraftStateMessage(
            content: content,
            mode: mode,
            wordCount: words,
            charCount: chars
        )

        broadcast(message)
    }

    /// Broadcast a revision (with diff) to all connected renderers
    func broadcastRevision(
        before: String,
        after: String,
        diff: [(type: String, text: String)],
        instruction: String,
        provider: String,
        model: String
    ) {
        let diffOps = diff.map { DiffOperationDTO(type: $0.type, text: $0.text) }

        let message = DraftRevisionMessage(
            before: before,
            after: after,
            diff: diffOps,
            instruction: instruction,
            provider: provider,
            model: model
        )

        broadcast(message)
    }

    /// Broadcast that a revision was resolved (accepted or rejected)
    func broadcastResolved(accepted: Bool, content: String) {
        let message = DraftResolvedMessage(
            accepted: accepted,
            content: content
        )

        broadcast(message)
    }

    /// Broadcast transcription result from voice capture
    func broadcastTranscription(text: String, append: Bool = true) {
        let message = DraftTranscriptionMessage(text: text, append: append)
        broadcast(message)
    }

    /// Broadcast an error to all connected renderers
    func broadcastError(_ error: String) {
        let message = DraftErrorMessage(error: error)
        broadcast(message)
    }

    // MARK: - Private

    private func handleStateUpdate(_ state: NWListener.State) {
        switch state {
        case .ready:
            log.info("DraftExtensionServer ready on port \(port)")
        case .failed(let error):
            log.error("DraftExtensionServer failed: \(error)")
            listener = nil
        case .cancelled:
            log.info("DraftExtensionServer cancelled")
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let renderer = ConnectedRenderer(connection: connection)
        connectedRenderers[renderer.id] = renderer

        log.info("Renderer connected: \(renderer.id), awaiting authentication")

        connection.stateUpdateHandler = { [weak self, rendererId = renderer.id] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    log.info("Renderer \(rendererId) ready, sending auth challenge")
                    self.sendAuthChallenge(to: renderer)
                    self.receiveMessages(from: renderer)
                    self.scheduleAuthTimeout(for: renderer)
                case .failed(let error):
                    log.error("Renderer \(rendererId) failed: \(error)")
                    self.disconnectRenderer(rendererId)
                case .cancelled:
                    log.info("Renderer \(rendererId) disconnected")
                    self.disconnectRenderer(rendererId)
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
    }

    private func sendAuthChallenge(to renderer: ConnectedRenderer) {
        let message = DraftAuthRequiredMessage(
            version: Self.protocolVersion,
            timeout: Int(authTimeout)
        )
        guard let data = try? JSONEncoder().encode(message) else { return }
        send(data: data, to: renderer)
    }

    private func scheduleAuthTimeout(for renderer: ConnectedRenderer) {
        let rendererId = renderer.id
        Task {
            try? await Task.sleep(for: .seconds(authTimeout))
            // Check if still connected and not authenticated
            if let r = connectedRenderers[rendererId], !r.isAuthenticated {
                log.warning("Renderer \(rendererId) failed to authenticate, disconnecting")
                sendError(to: r, error: "Authentication timeout")
                r.connection.cancel()
                disconnectRenderer(rendererId)
            }
        }
    }

    private func disconnectRenderer(_ id: UUID) {
        if let renderer = connectedRenderers.removeValue(forKey: id) {
            log.info("Renderer removed: \(renderer.name ?? id.uuidString)")
        }
    }

    private func receiveMessages(from renderer: ConnectedRenderer) {
        renderer.connection.receiveMessage { [weak self] content, context, isComplete, error in
            Task { @MainActor in
                guard let self else { return }

                if let error {
                    log.error("Receive error from \(renderer.id): \(error)")
                    self.disconnectRenderer(renderer.id)
                    return
                }

                if let content, let context {
                    // Check if this is a WebSocket message
                    if let metadata = context.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
                        switch metadata.opcode {
                        case .text:
                            self.handleTextMessage(content, from: renderer)
                        case .binary:
                            log.warning("Binary message not supported")
                        case .close:
                            self.disconnectRenderer(renderer.id)
                            return
                        case .ping, .pong:
                            break  // Handled automatically
                        default:
                            break
                        }
                    }
                }

                // Continue receiving if still connected
                if self.connectedRenderers[renderer.id] != nil {
                    self.receiveMessages(from: renderer)
                }
            }
        }
    }

    private func handleTextMessage(_ data: Data, from renderer: ConnectedRenderer) {
        guard let message = try? JSONDecoder().decode(DraftIncomingMessage.self, from: data) else {
            log.warning("Invalid message from renderer \(renderer.id)")
            sendError(to: renderer, error: "Invalid message format")
            return
        }

        log.debug("Received \(message.type) from \(renderer.name ?? renderer.id.uuidString)")

        // Require authentication for all messages except renderer:connect
        if message.type != "renderer:connect" && !renderer.isAuthenticated {
            log.warning("Rejecting message from unauthenticated renderer \(renderer.id)")
            sendError(to: renderer, error: "Not authenticated")
            return
        }

        switch message.type {
        case "renderer:connect":
            // Validate auth token
            guard let token = message.token, token == authToken else {
                log.warning("Renderer \(renderer.id) failed authentication")
                sendError(to: renderer, error: "Authentication failed: invalid token")
                renderer.connection.cancel()
                return
            }

            // Validate protocol version (optional but logged)
            if let version = message.version, version != Self.protocolVersion {
                log.warning("Renderer \(renderer.id) using protocol version \(version), expected \(Self.protocolVersion)")
            }

            renderer.isAuthenticated = true
            renderer.name = message.name
            renderer.capabilities = message.capabilities ?? []
            log.info("Renderer authenticated: \(renderer.name ?? "unnamed") with capabilities: \(renderer.capabilities)")

        case "draft:update":
            if let content = message.content {
                onUpdate?(content)
            }

        case "draft:refine":
            if let instruction = message.instruction {
                Task {
                    await onRefine?(instruction, message.constraints)
                }
            }

        case "draft:accept":
            onAccept?()

        case "draft:reject":
            onReject?()

        case "draft:save":
            if let destination = message.destination {
                onSave?(destination)
            }

        case "draft:capture":
            if message.action == "start" {
                onCaptureStart?()
            } else if message.action == "stop" {
                Task {
                    if let text = await onCaptureStop?() {
                        broadcastTranscription(text: text, append: true)
                    }
                }
            }

        default:
            log.warning("Unknown message type: \(message.type)")
            sendError(to: renderer, error: "Unknown message type: \(message.type)")
        }
    }

    private func broadcast<T: Encodable>(_ message: T) {
        guard let data = try? JSONEncoder().encode(message) else {
            log.error("Failed to encode broadcast message")
            return
        }

        // Only broadcast to authenticated renderers
        for renderer in connectedRenderers.values where renderer.isAuthenticated {
            send(data: data, to: renderer)
        }
    }

    private func send(data: Data, to renderer: ConnectedRenderer) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(
            identifier: "text",
            metadata: [metadata]
        )

        renderer.connection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { error in
                if let error {
                    log.error("Send error to \(renderer.id): \(error)")
                }
            }
        )
    }

    private func sendError(to renderer: ConnectedRenderer, error: String) {
        let message = DraftErrorMessage(error: error)
        guard let data = try? JSONEncoder().encode(message) else { return }
        send(data: data, to: renderer)
    }

    /// Generate a cryptographically secure auth token
    private func generateAuthToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
