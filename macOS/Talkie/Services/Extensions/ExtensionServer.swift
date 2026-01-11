//
//  ExtensionServer.swift
//  Talkie
//
//  WebSocket server for the Talkie Extensions Platform.
//  Exposes core primitives (transcription, LLM, diff) to external applications.
//
//  Protocol: ws://localhost:7847
//
//  Capabilities:
//    - transcribe    Voice capture and transcription
//    - llm           LLM completions and revisions
//    - llm:stream    Streaming LLM responses
//    - diff          Text diff computation
//    - storage       Clipboard and memo operations
//
//  Message Namespaces:
//    - ext:*         Extension lifecycle
//    - transcribe:*  Voice capture
//    - llm:*         LLM operations
//    - diff:*        Diff computation
//    - storage:*     Clipboard/memo operations
//

import Foundation
import Network
import TalkieKit

private let log = Log(.system)

// MARK: - Message Types

/// Generic incoming message from extensions
struct ExtensionMessage: Codable {
    let type: String

    // ext:connect
    let name: String?
    let capabilities: [String]?
    let token: String?
    let version: String?

    // transcribe:* (no additional fields needed)

    // llm:complete
    let messages: [LLMMessage]?
    let provider: String?
    let model: String?
    let stream: Bool?

    // llm:revise
    let content: String?
    let instruction: String?
    let constraints: LLMConstraints?

    // diff:compute
    let before: String?
    let after: String?

    // storage:*
    let title: String?
    let destination: String?  // Legacy: "memo" | "clipboard"

    // Legacy draft:* support
    let action: String?  // For draft:capture compatibility
}

struct LLMMessage: Codable {
    let role: String  // "system", "user", "assistant"
    let content: String
}

struct LLMConstraints: Codable {
    let maxLength: Int?
    let maxTokens: Int?
    let temperature: Double?
    let style: String?
    let format: String?
}

// MARK: - Outgoing Messages

struct AuthRequiredMessage: Codable {
    let type = "auth:required"
    let version: String
    let timeout: Int
    let capabilities: [String]  // Available capabilities
}

struct ExtConnectedMessage: Codable {
    let type = "ext:connected"
    let granted: [String]  // Granted capabilities
}

struct TranscribeStartedMessage: Codable {
    let type = "transcribe:started"
}

struct TranscribeResultMessage: Codable {
    let type = "transcribe:result"
    let text: String
}

struct LLMResultMessage: Codable {
    let type = "llm:result"
    let content: String
    let provider: String
    let model: String
    let requestId: String?
}

struct LLMChunkMessage: Codable {
    let type = "llm:chunk"
    let content: String
    let done: Bool
    let requestId: String?
}

struct LLMRevisionMessage: Codable {
    let type = "llm:revision"
    let before: String
    let after: String
    let diff: [ExtDiffOperation]
    let instruction: String
    let provider: String
    let model: String
}

struct DiffResultMessage: Codable {
    let type = "diff:result"
    let operations: [ExtDiffOperation]
}

struct ExtDiffOperation: Codable {
    let type: String  // "equal", "insert", "delete"
    let text: String
}

struct StorageClipboardContentMessage: Codable {
    let type = "storage:clipboard:content"
    let content: String
}

struct StorageMemoSavedMessage: Codable {
    let type = "storage:memo:saved"
    let id: String
}

struct ExtensionErrorMessage: Codable {
    let type = "error"
    let error: String
    let code: String?
}

// MARK: - Legacy Message Support (v1 compatibility)

struct LegacyStateMessage: Codable {
    let type = "draft:state"
    let content: String
    let mode: String
    let wordCount: Int
    let charCount: Int
}

struct LegacyRevisionMessage: Codable {
    let type = "draft:revision"
    let before: String
    let after: String
    let diff: [ExtDiffOperation]
    let instruction: String
    let provider: String
    let model: String
}

struct LegacyResolvedMessage: Codable {
    let type = "draft:resolved"
    let accepted: Bool
    let content: String
}

struct LegacyTranscriptionMessage: Codable {
    let type = "draft:transcription"
    let text: String
    let append: Bool
}

// MARK: - Connected Extension

/// Represents a connected extension client
@MainActor
final class ConnectedExtension {
    let id: UUID
    let connection: NWConnection
    var name: String?
    var requestedCapabilities: [String] = []
    var grantedCapabilities: Set<String> = []
    let connectedAt: Date
    var isAuthenticated: Bool = false

    init(connection: NWConnection) {
        self.id = UUID()
        self.connection = connection
        self.connectedAt = Date()
    }

    func hasCapability(_ capability: String) -> Bool {
        grantedCapabilities.contains(capability)
    }
}

// MARK: - Extension Server

/// WebSocket server for the Talkie Extensions Platform
@MainActor
final class ExtensionServer {
    static let shared = ExtensionServer()

    private var listener: NWListener?
    private let port: UInt16 = 7847
    private var connectedExtensions: [UUID: ConnectedExtension] = [:]

    /// Authentication token - extensions must send this in ext:connect
    private(set) var authToken: String = ""

    /// Time allowed for authentication before disconnect (seconds)
    private let authTimeout: TimeInterval = 10

    /// Protocol version
    static let protocolVersion = "2.0"

    /// Available capabilities that extensions can request
    static let availableCapabilities: Set<String> = [
        "transcribe",
        "llm",
        "llm:stream",
        "diff",
        "storage:clipboard",
        "storage:memo"
    ]

    // MARK: - Service Dependencies

    /// Transcription service - set by app on startup
    var transcriptionService: TranscriptionServiceProtocol?

    /// LLM service - set by app on startup
    var llmService: LLMServiceProtocol?

    // MARK: - Legacy Callbacks (for v1 draft:* compatibility)

    var onLegacyRefine: ((String, LLMConstraints?) async -> Void)?
    var onLegacyAccept: (() -> Void)?
    var onLegacyReject: (() -> Void)?
    var onLegacyUpdate: ((String) -> Void)?
    var onLegacySave: ((String) -> Void)?

    // MARK: - State

    var isRunning: Bool {
        listener?.state == .ready
    }

    var connectedCount: Int {
        connectedExtensions.count
    }

    var authenticatedCount: Int {
        connectedExtensions.values.filter { $0.isAuthenticated }.count
    }

    var connectedExtensionNames: [String] {
        connectedExtensions.values.compactMap { $0.name }
    }

    private init() {}

    // MARK: - Public API

    func start() {
        guard listener == nil else {
            log.debug("ExtensionServer already running")
            return
        }

        // Generate new auth token on each start
        authToken = generateAuthToken()
        log.info("ExtensionServer auth token generated")

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

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
            log.info("ExtensionServer starting on port \(port)")
        } catch {
            log.error("Failed to start ExtensionServer: \(error)")
        }
    }

    func stop() {
        for ext in connectedExtensions.values {
            ext.connection.cancel()
        }
        connectedExtensions.removeAll()

        listener?.cancel()
        listener = nil
        log.info("ExtensionServer stopped")
    }

    // MARK: - Broadcasting

    /// Broadcast to all authenticated extensions with a specific capability
    func broadcast<T: Encodable>(_ message: T, requiring capability: String? = nil) {
        guard let data = try? JSONEncoder().encode(message) else {
            log.error("Failed to encode broadcast message")
            return
        }

        for ext in connectedExtensions.values where ext.isAuthenticated {
            if let cap = capability, !ext.hasCapability(cap) {
                continue
            }
            send(data: data, to: ext)
        }
    }

    /// Send to a specific extension
    func send<T: Encodable>(_ message: T, to extensionId: UUID) {
        guard let ext = connectedExtensions[extensionId] else { return }
        guard let data = try? JSONEncoder().encode(message) else { return }
        send(data: data, to: ext)
    }

    /// Broadcast error to all authenticated extensions
    func broadcastError(_ error: String, code: String? = nil) {
        let message = ExtensionErrorMessage(error: error, code: code)
        broadcast(message)
    }

    // MARK: - Legacy v1 API (draft:* messages)

    func broadcastLegacyState(content: String, mode: String) {
        let message = LegacyStateMessage(
            content: content,
            mode: mode,
            wordCount: content.split(separator: " ").count,
            charCount: content.count
        )
        broadcast(message)
    }

    func broadcastLegacyRevision(
        before: String,
        after: String,
        diff: [(type: String, text: String)],
        instruction: String,
        provider: String,
        model: String
    ) {
        let diffOps = diff.map { ExtDiffOperation(type: $0.type, text: $0.text) }
        let message = LegacyRevisionMessage(
            before: before,
            after: after,
            diff: diffOps,
            instruction: instruction,
            provider: provider,
            model: model
        )
        broadcast(message)
    }

    func broadcastLegacyResolved(accepted: Bool, content: String) {
        let message = LegacyResolvedMessage(accepted: accepted, content: content)
        broadcast(message)
    }

    func broadcastLegacyTranscription(text: String, append: Bool = true) {
        let message = LegacyTranscriptionMessage(text: text, append: append)
        broadcast(message)
    }

    // MARK: - Private - Connection Handling

    private func handleStateUpdate(_ state: NWListener.State) {
        switch state {
        case .ready:
            log.info("ExtensionServer ready on port \(port)")
        case .failed(let error):
            log.error("ExtensionServer failed: \(error)")
            listener = nil
        case .cancelled:
            log.info("ExtensionServer cancelled")
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let ext = ConnectedExtension(connection: connection)
        connectedExtensions[ext.id] = ext

        log.info("Extension connected: \(ext.id), awaiting authentication")

        connection.stateUpdateHandler = { [weak self, extId = ext.id] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    log.info("Extension \(extId) ready, sending auth challenge")
                    self.sendAuthChallenge(to: ext)
                    self.receiveMessages(from: ext)
                    self.scheduleAuthTimeout(for: ext)
                case .failed(let error):
                    log.error("Extension \(extId) failed: \(error)")
                    self.disconnectExtension(extId)
                case .cancelled:
                    log.info("Extension \(extId) disconnected")
                    self.disconnectExtension(extId)
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
    }

    private func sendAuthChallenge(to ext: ConnectedExtension) {
        let message = AuthRequiredMessage(
            version: Self.protocolVersion,
            timeout: Int(authTimeout),
            capabilities: Array(Self.availableCapabilities)
        )
        guard let data = try? JSONEncoder().encode(message) else { return }
        send(data: data, to: ext)
    }

    private func scheduleAuthTimeout(for ext: ConnectedExtension) {
        let extId = ext.id
        Task {
            try? await Task.sleep(for: .seconds(authTimeout))
            if let e = connectedExtensions[extId], !e.isAuthenticated {
                log.warning("Extension \(extId) failed to authenticate, disconnecting")
                sendError(to: e, error: "Authentication timeout", code: "AUTH_TIMEOUT")
                e.connection.cancel()
                disconnectExtension(extId)
            }
        }
    }

    private func disconnectExtension(_ id: UUID) {
        if let ext = connectedExtensions.removeValue(forKey: id) {
            log.info("Extension removed: \(ext.name ?? id.uuidString)")
        }
    }

    // MARK: - Private - Message Handling

    private func receiveMessages(from ext: ConnectedExtension) {
        ext.connection.receiveMessage { [weak self] content, context, isComplete, error in
            Task { @MainActor in
                guard let self else { return }

                if let error {
                    log.error("Receive error from \(ext.id): \(error)")
                    self.disconnectExtension(ext.id)
                    return
                }

                if let content, let context {
                    if let metadata = context.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
                        switch metadata.opcode {
                        case .text:
                            self.handleMessage(content, from: ext)
                        case .binary:
                            log.warning("Binary messages not supported")
                        case .close:
                            self.disconnectExtension(ext.id)
                            return
                        case .ping, .pong:
                            break
                        default:
                            break
                        }
                    }
                }

                if self.connectedExtensions[ext.id] != nil {
                    self.receiveMessages(from: ext)
                }
            }
        }
    }

    private func handleMessage(_ data: Data, from ext: ConnectedExtension) {
        guard let message = try? JSONDecoder().decode(ExtensionMessage.self, from: data) else {
            log.warning("Invalid message from extension \(ext.id)")
            sendError(to: ext, error: "Invalid message format", code: "INVALID_FORMAT")
            return
        }

        log.debug("Received \(message.type) from \(ext.name ?? ext.id.uuidString)")

        // Authentication required for all messages except ext:connect
        let isConnectMessage = message.type == "ext:connect" || message.type == "renderer:connect"
        if !isConnectMessage && !ext.isAuthenticated {
            log.warning("Rejecting message from unauthenticated extension \(ext.id)")
            sendError(to: ext, error: "Not authenticated", code: "NOT_AUTHENTICATED")
            return
        }

        // Route message by namespace
        let parts = message.type.split(separator: ":")
        let namespace = parts.first.map(String.init) ?? message.type

        switch namespace {
        case "ext", "renderer":  // renderer: for v1 compatibility
            handleExtMessage(message, from: ext)
        case "transcribe":
            handleTranscribeMessage(message, from: ext)
        case "llm":
            handleLLMMessage(message, from: ext)
        case "diff":
            handleDiffMessage(message, from: ext)
        case "storage":
            handleStorageMessage(message, from: ext)
        case "draft":  // Legacy v1 support
            handleLegacyDraftMessage(message, from: ext)
        default:
            log.warning("Unknown message namespace: \(namespace)")
            sendError(to: ext, error: "Unknown message type: \(message.type)", code: "UNKNOWN_TYPE")
        }
    }

    // MARK: - Message Handlers

    private func handleExtMessage(_ message: ExtensionMessage, from ext: ConnectedExtension) {
        switch message.type {
        case "ext:connect", "renderer:connect":
            // Validate auth token
            guard let token = message.token, token == authToken else {
                log.warning("Extension \(ext.id) failed authentication")
                sendError(to: ext, error: "Authentication failed: invalid token", code: "AUTH_FAILED")
                ext.connection.cancel()
                return
            }

            // Log version mismatch
            if let version = message.version, version != Self.protocolVersion {
                log.warning("Extension \(ext.id) using protocol v\(version), server is v\(Self.protocolVersion)")
            }

            // Grant requested capabilities (all for now, could add restrictions)
            ext.isAuthenticated = true
            ext.name = message.name
            ext.requestedCapabilities = message.capabilities ?? []
            ext.grantedCapabilities = Set(ext.requestedCapabilities).intersection(Self.availableCapabilities)

            log.info("Extension authenticated: \(ext.name ?? "unnamed"), capabilities: \(ext.grantedCapabilities)")

            // Send confirmation
            let response = ExtConnectedMessage(granted: Array(ext.grantedCapabilities))
            if let data = try? JSONEncoder().encode(response) {
                send(data: data, to: ext)
            }

        default:
            sendError(to: ext, error: "Unknown ext message: \(message.type)", code: "UNKNOWN_TYPE")
        }
    }

    private func handleTranscribeMessage(_ message: ExtensionMessage, from ext: ConnectedExtension) {
        guard ext.hasCapability("transcribe") else {
            sendError(to: ext, error: "Capability 'transcribe' not granted", code: "CAPABILITY_DENIED")
            return
        }

        switch message.type {
        case "transcribe:start":
            Task {
                do {
                    try await transcriptionService?.startCapture()
                    let started = TranscribeStartedMessage()
                    if let data = try? JSONEncoder().encode(started) {
                        send(data: data, to: ext)
                    }
                    log.info("Transcription started for extension \(ext.name ?? ext.id.uuidString)")
                } catch {
                    log.error("Failed to start transcription: \(error)")
                    sendError(to: ext, error: "Failed to start transcription: \(error.localizedDescription)", code: "TRANSCRIBE_ERROR")
                }
            }

        case "transcribe:stop":
            Task {
                do {
                    let text = try await transcriptionService?.stopAndTranscribe() ?? ""
                    let result = TranscribeResultMessage(text: text)
                    if let data = try? JSONEncoder().encode(result) {
                        send(data: data, to: ext)
                    }
                    log.info("Transcription completed for extension \(ext.name ?? ext.id.uuidString): \(text.prefix(50))...")
                } catch {
                    log.error("Failed to transcribe: \(error)")
                    sendError(to: ext, error: "Transcription failed: \(error.localizedDescription)", code: "TRANSCRIBE_ERROR")
                }
            }

        default:
            sendError(to: ext, error: "Unknown transcribe message: \(message.type)", code: "UNKNOWN_TYPE")
        }
    }

    private func handleLLMMessage(_ message: ExtensionMessage, from ext: ConnectedExtension) {
        guard ext.hasCapability("llm") else {
            sendError(to: ext, error: "Capability 'llm' not granted", code: "CAPABILITY_DENIED")
            return
        }

        switch message.type {
        case "llm:complete":
            guard let messages = message.messages, !messages.isEmpty else {
                sendError(to: ext, error: "Messages required for llm:complete", code: "INVALID_PARAMS")
                return
            }

            Task {
                do {
                    let result = try await llmService?.complete(
                        messages: messages,
                        provider: message.provider,
                        model: message.model,
                        stream: message.stream ?? false
                    )

                    if let result {
                        let response = LLMResultMessage(
                            content: result.content,
                            provider: result.provider,
                            model: result.model,
                            requestId: nil
                        )
                        if let data = try? JSONEncoder().encode(response) {
                            send(data: data, to: ext)
                        }
                    }
                } catch {
                    log.error("LLM completion failed: \(error)")
                    sendError(to: ext, error: "LLM completion failed: \(error.localizedDescription)", code: "LLM_ERROR")
                }
            }

        case "llm:revise":
            guard let content = message.content, let instruction = message.instruction else {
                sendError(to: ext, error: "Content and instruction required for llm:revise", code: "INVALID_PARAMS")
                return
            }

            Task {
                do {
                    let result = try await llmService?.revise(
                        content: content,
                        instruction: instruction,
                        constraints: message.constraints,
                        provider: message.provider,
                        model: message.model
                    )

                    if let result {
                        // Compute diff
                        let diff = computeDiff(before: content, after: result.content)

                        let response = LLMRevisionMessage(
                            before: content,
                            after: result.content,
                            diff: diff,
                            instruction: instruction,
                            provider: result.provider,
                            model: result.model
                        )
                        if let data = try? JSONEncoder().encode(response) {
                            send(data: data, to: ext)
                        }
                    }
                } catch {
                    log.error("LLM revision failed: \(error)")
                    sendError(to: ext, error: "LLM revision failed: \(error.localizedDescription)", code: "LLM_ERROR")
                }
            }

        default:
            sendError(to: ext, error: "Unknown llm message: \(message.type)", code: "UNKNOWN_TYPE")
        }
    }

    private func handleDiffMessage(_ message: ExtensionMessage, from ext: ConnectedExtension) {
        guard ext.hasCapability("diff") else {
            sendError(to: ext, error: "Capability 'diff' not granted", code: "CAPABILITY_DENIED")
            return
        }

        switch message.type {
        case "diff:compute":
            guard let before = message.before, let after = message.after else {
                sendError(to: ext, error: "Before and after required for diff:compute", code: "INVALID_PARAMS")
                return
            }

            let diff = computeDiff(before: before, after: after)
            let response = DiffResultMessage(operations: diff)
            if let data = try? JSONEncoder().encode(response) {
                send(data: data, to: ext)
            }

        default:
            sendError(to: ext, error: "Unknown diff message: \(message.type)", code: "UNKNOWN_TYPE")
        }
    }

    private func handleStorageMessage(_ message: ExtensionMessage, from ext: ConnectedExtension) {
        switch message.type {
        case "storage:clipboard:write":
            guard ext.hasCapability("storage:clipboard") else {
                sendError(to: ext, error: "Capability 'storage:clipboard' not granted", code: "CAPABILITY_DENIED")
                return
            }

            if let content = message.content {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(content, forType: .string)
                log.info("Clipboard written by extension \(ext.name ?? ext.id.uuidString)")
            }

        case "storage:clipboard:read":
            guard ext.hasCapability("storage:clipboard") else {
                sendError(to: ext, error: "Capability 'storage:clipboard' not granted", code: "CAPABILITY_DENIED")
                return
            }

            let content = NSPasteboard.general.string(forType: .string) ?? ""
            let response = StorageClipboardContentMessage(content: content)
            if let data = try? JSONEncoder().encode(response) {
                send(data: data, to: ext)
            }

        case "storage:memo:save":
            guard ext.hasCapability("storage:memo") else {
                sendError(to: ext, error: "Capability 'storage:memo' not granted", code: "CAPABILITY_DENIED")
                return
            }

            // TODO: Implement memo saving via MemoManager
            log.info("Memo save requested by extension \(ext.name ?? ext.id.uuidString)")
            let response = StorageMemoSavedMessage(id: UUID().uuidString)
            if let data = try? JSONEncoder().encode(response) {
                send(data: data, to: ext)
            }

        default:
            sendError(to: ext, error: "Unknown storage message: \(message.type)", code: "UNKNOWN_TYPE")
        }
    }

    // MARK: - Legacy v1 Support

    private func handleLegacyDraftMessage(_ message: ExtensionMessage, from ext: ConnectedExtension) {
        log.debug("Handling legacy draft:* message: \(message.type)")

        switch message.type {
        case "draft:update":
            if let content = message.content {
                onLegacyUpdate?(content)
            }

        case "draft:refine":
            if let instruction = message.instruction {
                Task {
                    await onLegacyRefine?(instruction, message.constraints)
                }
            }

        case "draft:accept":
            onLegacyAccept?()

        case "draft:reject":
            onLegacyReject?()

        case "draft:save":
            if let destination = message.destination {
                onLegacySave?(destination)
            }

        case "draft:capture":
            // Map to new transcribe:* messages
            if message.action == "start" {
                handleTranscribeMessage(ExtensionMessage(
                    type: "transcribe:start",
                    name: nil, capabilities: nil, token: nil, version: nil,
                    messages: nil, provider: nil, model: nil, stream: nil,
                    content: nil, instruction: nil, constraints: nil,
                    before: nil, after: nil,
                    title: nil, destination: nil, action: nil
                ), from: ext)
            } else if message.action == "stop" {
                handleTranscribeMessage(ExtensionMessage(
                    type: "transcribe:stop",
                    name: nil, capabilities: nil, token: nil, version: nil,
                    messages: nil, provider: nil, model: nil, stream: nil,
                    content: nil, instruction: nil, constraints: nil,
                    before: nil, after: nil,
                    title: nil, destination: nil, action: nil
                ), from: ext)
            }

        default:
            sendError(to: ext, error: "Unknown draft message: \(message.type)", code: "UNKNOWN_TYPE")
        }
    }

    // MARK: - Utilities

    private func computeDiff(before: String, after: String) -> [ExtDiffOperation] {
        let diff = DiffEngine.diff(original: before, proposed: after)
        return diff.operations.map { op in
            switch op {
            case .equal(let text): return ExtDiffOperation(type: "equal", text: text)
            case .insert(let text): return ExtDiffOperation(type: "insert", text: text)
            case .delete(let text): return ExtDiffOperation(type: "delete", text: text)
            }
        }
    }

    private func send(data: Data, to ext: ConnectedExtension) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(
            identifier: "text",
            metadata: [metadata]
        )

        ext.connection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { error in
                if let error {
                    log.error("Send error to \(ext.id): \(error)")
                }
            }
        )
    }

    private func sendError(to ext: ConnectedExtension, error: String, code: String?) {
        let message = ExtensionErrorMessage(error: error, code: code)
        guard let data = try? JSONEncoder().encode(message) else { return }
        send(data: data, to: ext)
    }

    private func generateAuthToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Service Protocols

/// Protocol for transcription service integration
protocol TranscriptionServiceProtocol {
    func startCapture() async throws
    func stopAndTranscribe() async throws -> String
}

/// Protocol for LLM service integration
protocol LLMServiceProtocol {
    func complete(
        messages: [LLMMessage],
        provider: String?,
        model: String?,
        stream: Bool
    ) async throws -> LLMServiceResult

    func revise(
        content: String,
        instruction: String,
        constraints: LLMConstraints?,
        provider: String?,
        model: String?
    ) async throws -> LLMServiceResult
}

struct LLMServiceResult {
    let content: String
    let provider: String
    let model: String
}
