//
//  TalkieServer.swift
//  Talkie
//
//  HTTP server for receiving message requests from Bridge.
//  Listens on port 8766 and forwards to TalkieAgent via XPC.
//

import Foundation
import Network
import AppKit
import CryptoKit
import IOKit.hid
import TalkieKit

private let log = Log(.system)

private extension NWError {
    var isAddressAlreadyInUse: Bool {
        if case .posix(let code) = self {
            return code == .EADDRINUSE
        }
        return false
    }
}

// MARK: - Error Messages

/// Actionable error messages with troubleshooting steps
private enum TalkieServerError {
    static let talkieLiveNotConnected = """
        TalkieAgent not connected. Troubleshooting:
        1. Check TalkieAgent is running (look for menu bar icon)
        2. Ensure same build environment (both from Xcode or both from /Applications)
        3. Verify Accessibility permission is granted (System Settings → Privacy & Security → Accessibility)
        4. Try restarting TalkieAgent from Talkie menu bar
        """

    static let xpcConnectionFailed = """
        XPC connection failed. This usually means:
        1. TalkieAgent crashed or was force-quit
        2. macOS invalidated the XPC connection
        3. Different code signing between apps
        Try: Restart TalkieAgent from Talkie menu, or restart both apps
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

private struct WorkflowHostContextPayload: Codable {
    let transcript: String
    let title: String
    let date: String
    let outputs: [String: String]
    let outputOrder: [String]
}

private struct WorkflowHostStepRequest: Codable {
    let memoId: UUID
    let stepId: String
    let stepType: String
    let outputKey: String
    let configJSON: String
    let context: WorkflowHostContextPayload
}

private struct WorkflowHostStepResultPayload: Codable {
    let status: String
    let output: String?
    let reason: String?
}

private struct WorkflowHostStepResponse: Codable {
    let ok: Bool
    let result: WorkflowHostStepResultPayload?
    let error: String?

    init(ok: Bool, result: WorkflowHostStepResultPayload? = nil, error: String? = nil) {
        self.ok = ok
        self.result = result
        self.error = error
    }
}

private struct CompanionShortcutTriggerRequest: Codable {
    let shortcutId: String
}

private struct CompanionShortcutTriggerResponse: Codable {
    let ok: Bool
    let handledShortcutId: String?
    let message: String?
    let error: String?
    let runtimeState: CompanionShortcutRuntimeState?

    init(
        ok: Bool,
        handledShortcutId: String? = nil,
        message: String? = nil,
        error: String? = nil,
        runtimeState: CompanionShortcutRuntimeState? = nil
    ) {
        self.ok = ok
        self.handledShortcutId = handledShortcutId
        self.message = message
        self.error = error
        self.runtimeState = runtimeState
    }
}

private struct CompanionShortcutRuntimeState: Codable {
    let shortcutId: String
    let phase: String
    let canStop: Bool
    let detail: String?
    let elapsedSeconds: Double?
    let signalLevel: Double?
}

private struct CompanionShortcutRecentResult: Codable {
    let shortcutId: String
    let resultText: String
    let completedAt: String
}

private struct CompanionAppSwitcherApp: Codable {
    let processIdentifier: Int32
    let bundleIdentifier: String?
    let displayName: String
    let isFrontmost: Bool
    let iconPNGBase64: String?
}

private struct CompanionRuntimeStateResponse: Codable {
    let shortcutStates: [CompanionShortcutRuntimeState]
    let recentResults: [CompanionShortcutRecentResult]
    let appSwitcherApps: [CompanionAppSwitcherApp]
}

private struct CompanionActivateAppRequest: Codable {
    let processIdentifier: Int32?
    let bundleIdentifier: String?
}

private struct TerminalAccessResponse: Codable {
    let ok: Bool
    let payload: String?
    let label: String?
    let host: String?
    let alternateHosts: [String]
    let fingerprint: String?
    let error: String?
}

private enum LocalBridgeCapability {
    static let companionRuntimeState = "companion.runtimeState"
    static let companionTrigger = "companion.trigger"
    static let companionActivateApp = "companion.activateApp"
    static let companionTrackpad = "companion.trackpad"
    static let companionPasteImage = "companion.pasteImage"
    static let terminalAccess = "terminal.access"
    static let desktopWindowsRead = "desktop.windows.read"
    static let desktopScreenshotRead = "desktop.screenshot.read"
    static let messageInject = "message.inject"
    static let workflowExecute = "workflow.execute"

    static let supported: Set<String> = [
        companionRuntimeState,
        companionTrigger,
        companionActivateApp,
        companionTrackpad,
        companionPasteImage,
        terminalAccess,
        desktopWindowsRead,
        desktopScreenshotRead,
        messageInject,
        workflowExecute,
    ]

    static func grantedCapabilities(for requested: [String]?) -> [String] {
        let cleaned = Set((requested ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let desired = cleaned.isEmpty ? supported : cleaned
        return desired.intersection(supported).sorted()
    }
}

private struct LocalClientAccessRequest: Codable {
    let clientId: String
    let displayName: String
    let publicKey: String
    let requestedCapabilities: [String]?
}

private struct LocalClientAccessResponse: Codable {
    let ok: Bool
    let status: String
    let clientId: String?
    let grantedCapabilities: [String]
    let fingerprint: String?
    let message: String?
}

private struct TrustedLocalClientRecord: Codable {
    var id: String
    var displayName: String
    var publicKey: String
    var fingerprint: String
    var capabilities: [String]
    var isEnabled: Bool
    var pairedAt: Date
    var lastSeenAt: Date
}

private struct LocalClientAuthorizationErrorResponse: Codable {
    let ok: Bool
    let error: String
    let serverTime: String
    let requiredCapability: String?
}

/// Local HTTP server for Bridge communication
/// Receives message requests and forwards to TalkieAgent via XPC
@MainActor
final class TalkieServer {
    static let shared = TalkieServer()

    private var listener: NWListener?
    private let port: UInt16 = 8766
    private let recordingRepository = TalkieObjectRepository()
    private var activeDictationShortcutId: String = "talkie-dictate"
    private var lastCompanionDictationShortcutId: String?
    private var lastCompanionDictationStartedAt: Date?
    private var lastCompanionDictationStoppedShortcutId: String?
    private var lastCompanionDictationStoppedAt: Date?
    private let companionDictationRestartSuppressionInterval: TimeInterval = 0.9
    private var isCompanionAppSwitcherActive = false
    private var isUsingExternalRelay = false
    private var companionAppSwitcherReleaseTask: Task<Void, Never>?
    private var companionAppActivationOrder: [Int32] = []
    private var companionWorkspaceActivationObserver: NSObjectProtocol?
    private var trustedLocalClients: [String: TrustedLocalClientRecord]
    private var localClientSeenNonces: [String: Date] = [:]
    private var localClientDeniedUntil: [String: Date] = [:]

    private let localClientTimeSkewAllowance: TimeInterval = 300
    private let localClientReplayWindow: TimeInterval = 600

    private enum LocalClientDefaultsKey {
        static let trustedClients = "talkie.localBridge.trustedClients.v1"
    }

    private enum LocalClientHeader {
        static let clientID = "x-talkie-client-id"
        static let timestamp = "x-talkie-timestamp"
        static let nonce = "x-talkie-nonce"
        static let bodySHA256 = "x-talkie-body-sha256"
        static let signature = "x-talkie-signature"
    }

    private enum LocalClientAuthorizationResult {
        case authorized(TrustedLocalClientRecord)
        case rejected(statusCode: Int, error: String, requiredCapability: String?)
    }

    // Get XPC manager dynamically from ServiceManager (handles reconnection)
    private var xpcManager: XPCServiceManager<TalkieAgentXPCServiceProtocol>? {
        ServiceManager.shared.live.xpcManager
    }

    var isRunning: Bool {
        listener?.state == .ready || isUsingExternalRelay
    }

    private init() {
        self.trustedLocalClients = Self.loadTrustedLocalClients()
    }

    // MARK: - Public API

    func start(xpcManager: XPCServiceManager<TalkieAgentXPCServiceProtocol>? = nil) {
        // xpcManager parameter kept for API compatibility but not used
        // We now get it dynamically from ServiceManager

        installCompanionWorkspaceObserverIfNeeded()

        guard listener == nil else {
            log.debug("TalkieServer already running")
            return
        }
        guard !isUsingExternalRelay else {
            log.debug("TalkieServer relay already owned by another process")
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
            if (error as? NWError)?.isAddressAlreadyInUse == true {
                isUsingExternalRelay = true
                log.info("TalkieServer port \(port) already owned by another process; using existing relay")
                return
            }
            log.error("Failed to start TalkieServer: \(error)")
        }
    }

    func stop() {
        let hadLocalListener = listener != nil
        listener?.cancel()
        listener = nil
        isUsingExternalRelay = false
        if hadLocalListener {
            log.info("TalkieServer stopped")
        }
    }

    // MARK: - Private

    private func handleStateUpdate(_ state: NWListener.State) {
        switch state {
        case .ready:
            isUsingExternalRelay = false
            log.info("TalkieServer ready on port \(port)")
        case .failed(let error):
            if error.isAddressAlreadyInUse {
                isUsingExternalRelay = true
                log.info("TalkieServer port \(port) already owned by another process; using existing relay")
            } else {
                isUsingExternalRelay = false
                log.error("TalkieServer failed: \(error)")
            }
            listener?.cancel()
            listener = nil
        case .cancelled:
            log.info("TalkieServer cancelled")
        default:
            break
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        guard isLoopbackConnection(connection) else {
            log.warning("Rejected non-loopback TalkieServer connection: \(String(describing: connection.endpoint))")
            connection.cancel()
            return
        }

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
            Task { @MainActor [weak self] in
                guard let self else { return }

                switch result {
                case .success(let data):
                    await self.processRequest(data, connection: connection)
                case .failure(let error):
                    log.error("Receive error: \(error)")
                    connection.cancel()
                }
            }
        }
    }

    /// Receive HTTP request: parse headers for Content-Length, then read exact body size
    private func receiveHTTPRequest(
        connection: NWConnection,
        accumulated: Data,
        completion: @escaping @Sendable (Result<Data, Error>) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
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
                            self.receiveRemainingBody(
                                connection: connection,
                                accumulated: totalData,
                                targetSize: totalData.count + remaining,
                                completion: completion
                            )
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
    }

    /// Continue receiving until we have targetSize bytes
    private func receiveRemainingBody(
        connection: NWConnection,
        accumulated: Data,
        targetSize: Int,
        completion: @escaping @Sendable (Result<Data, Error>) -> Void
    ) {
        let remaining = targetSize - accumulated.count
        connection.receive(minimumIncompleteLength: 1, maximumLength: min(remaining, 10_485_760)) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
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

    private func parseHeaders(from lines: [String]) -> [String: String] {
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }
        return headers
    }

    private func isLoopbackConnection(_ connection: NWConnection) -> Bool {
        switch connection.endpoint {
        case .hostPort(let host, _):
            switch host {
            case .name(let name, _):
                let lower = name.lowercased()
                return lower == "localhost" || lower == "127.0.0.1" || lower == "::1"
            case .ipv4(let address):
                return "\(address)" == "127.0.0.1"
            case .ipv6(let address):
                let value = "\(address)"
                return value == "::1" || value == "0:0:0:0:0:0:0:1" || value == "::ffff:127.0.0.1"
            @unknown default:
                return false
            }
        default:
            return false
        }
    }

    private func authorizeLocalClientIfNeeded(
        connection: NWConnection,
        method: String,
        rawPath: String,
        path: String,
        headers: [String: String],
        body: Data
    ) -> Bool {
        guard let requiredCapability = requiredLocalClientCapability(method: method, path: path) else {
            return true
        }

        switch authorizeLocalClient(
            method: method,
            rawPath: rawPath,
            headers: headers,
            body: body,
            requiredCapability: requiredCapability
        ) {
        case .authorized:
            return true
        case .rejected(let statusCode, let error, let requiredCapability):
            log.warning("Rejected TalkieServer local client request: \(error)")
            sendJSONResponse(
                connection,
                statusCode: statusCode,
                body: LocalClientAuthorizationErrorResponse(
                    ok: false,
                    error: error,
                    serverTime: String(Int(Date().timeIntervalSince1970)),
                    requiredCapability: requiredCapability
                )
            )
            return false
        }
    }

    private func requiredLocalClientCapability(method: String, path: String) -> String? {
        switch (method, path) {
        case ("GET", "/companion/runtime-state"):
            return LocalBridgeCapability.companionRuntimeState
        case ("POST", "/companion/trigger"):
            return LocalBridgeCapability.companionTrigger
        case ("POST", "/companion/activate-app"):
            return LocalBridgeCapability.companionActivateApp
        case ("POST", "/companion/trackpad"):
            return LocalBridgeCapability.companionTrackpad
        case ("POST", "/companion/paste-image"):
            return LocalBridgeCapability.companionPasteImage
        case ("POST", "/terminal/access"):
            return LocalBridgeCapability.terminalAccess
        case ("GET", "/windows/claude"):
            return LocalBridgeCapability.desktopWindowsRead
        case ("GET", "/screenshot/terminals"), ("GET", "/screenshot/display"):
            return LocalBridgeCapability.desktopScreenshotRead
        case ("POST", "/message"), ("POST", "/inject"):
            return LocalBridgeCapability.messageInject
        case ("POST", "/workflows/host/execute-step"):
            return LocalBridgeCapability.workflowExecute
        default:
            if method == "GET" && path.hasPrefix("/screenshot/window/") {
                return LocalBridgeCapability.desktopScreenshotRead
            }
            return nil
        }
    }

    private func authorizeLocalClient(
        method: String,
        rawPath: String,
        headers: [String: String],
        body: Data,
        requiredCapability: String
    ) -> LocalClientAuthorizationResult {
        guard let clientID = headers[LocalClientHeader.clientID], !clientID.isEmpty else {
            return .rejected(statusCode: 401, error: "Missing trusted local client header: \(LocalClientHeader.clientID)", requiredCapability: requiredCapability)
        }
        guard let timestamp = headers[LocalClientHeader.timestamp], let timestampSeconds = TimeInterval(timestamp) else {
            return .rejected(statusCode: 401, error: "Missing or invalid trusted local client timestamp", requiredCapability: requiredCapability)
        }
        guard let nonce = headers[LocalClientHeader.nonce], !nonce.isEmpty else {
            return .rejected(statusCode: 401, error: "Missing trusted local client nonce", requiredCapability: requiredCapability)
        }
        guard let suppliedBodyHash = headers[LocalClientHeader.bodySHA256]?.lowercased(), !suppliedBodyHash.isEmpty else {
            return .rejected(statusCode: 401, error: "Missing trusted local client body hash", requiredCapability: requiredCapability)
        }
        guard let signatureValue = headers[LocalClientHeader.signature], !signatureValue.isEmpty else {
            return .rejected(statusCode: 401, error: "Missing trusted local client signature", requiredCapability: requiredCapability)
        }
        guard var record = trustedLocalClients[clientID], record.isEnabled else {
            return .rejected(statusCode: 401, error: "Local client is not trusted by Talkie", requiredCapability: requiredCapability)
        }
        guard record.capabilities.contains(requiredCapability) else {
            return .rejected(statusCode: 403, error: "Local client is missing required capability", requiredCapability: requiredCapability)
        }

        let now = Date()
        guard abs(now.timeIntervalSince1970 - timestampSeconds) <= localClientTimeSkewAllowance else {
            return .rejected(statusCode: 401, error: "Trusted local client request timestamp is stale", requiredCapability: requiredCapability)
        }

        purgeExpiredLocalClientNonces(now: now)
        let nonceKey = "\(clientID):\(nonce)"
        guard localClientSeenNonces[nonceKey] == nil else {
            return .rejected(statusCode: 401, error: "Trusted local client nonce was already used", requiredCapability: requiredCapability)
        }

        let computedBodyHash = Self.sha256Hex(body)
        guard Self.constantTimeEqual(suppliedBodyHash, computedBodyHash) else {
            return .rejected(statusCode: 401, error: "Trusted local client body hash mismatch", requiredCapability: requiredCapability)
        }

        guard let publicKey = Self.localClientPublicKey(from: record.publicKey),
              let signatureData = Data(base64Encoded: signatureValue),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureData)
        else {
            return .rejected(statusCode: 401, error: "Trusted local client key or signature is invalid", requiredCapability: requiredCapability)
        }

        let canonical = "\(method)\n\(rawPath)\n\(timestamp)\n\(nonce)\n\(computedBodyHash)"
        guard publicKey.isValidSignature(signature, for: Data(canonical.utf8)) else {
            return .rejected(statusCode: 401, error: "Trusted local client signature verification failed", requiredCapability: requiredCapability)
        }

        localClientSeenNonces[nonceKey] = now
        record.lastSeenAt = now
        trustedLocalClients[clientID] = record
        persistTrustedLocalClients()
        return .authorized(record)
    }

    private func purgeExpiredLocalClientNonces(now: Date = Date()) {
        localClientSeenNonces = localClientSeenNonces.filter { _, seenAt in
            now.timeIntervalSince(seenAt) <= localClientReplayWindow
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
        let rawPath = parts[1]
        let requestURL = URLComponents(string: "http://localhost\(rawPath)")
        let path = requestURL?.path ?? rawPath
        let headers = parseHeaders(from: lines)

        log.info("TalkieServer received: \(method) '\(rawPath)'")

        // Find body (after empty line)
        var body: Data?
        if let emptyLineIndex = lines.firstIndex(of: "") {
            let bodyLines = lines[(emptyLineIndex + 1)...]
            let bodyString = bodyLines.joined(separator: "\r\n")
            body = bodyString.data(using: .utf8)
        }
        let bodyData = body ?? Data()

        // Route request
        if path == "/health" && method == "GET" {
            let response = ["status": "ok", "service": "Talkie"]
            sendJSONResponse(connection, statusCode: 200, body: response)
        } else if path == "/doctor" && method == "GET" {
            await handleDoctor(connection)
        } else if path == "/local-clients/request-access" && method == "POST" {
            await handleLocalClientAccessRequest(connection, body: body)
        } else if path == "/companion/runtime-state" && method == "GET" {
            guard authorizeLocalClientIfNeeded(
                connection: connection,
                method: method,
                rawPath: rawPath,
                path: path,
                headers: headers,
                body: bodyData
            ) else { return }
            let runtimeState = await currentCompanionRuntimeState()
            sendJSONResponse(connection, statusCode: 200, body: runtimeState)
        } else if path == "/companion/activate-app" && method == "POST" {
            guard authorizeLocalClientIfNeeded(
                connection: connection,
                method: method,
                rawPath: rawPath,
                path: path,
                headers: headers,
                body: bodyData
            ) else { return }
            await handleCompanionActivateApp(connection, body: body)
        } else if path == "/workflows/host/execute-step" && method == "POST" {
            guard authorizeLocalClientIfNeeded(
                connection: connection,
                method: method,
                rawPath: rawPath,
                path: path,
                headers: headers,
                body: bodyData
            ) else { return }
            await handleWorkflowHostExecuteStep(connection, body: body)
        } else if (path == "/message" || path == "/inject") && method == "POST" {
            guard authorizeLocalClientIfNeeded(
                connection: connection,
                method: method,
                rawPath: rawPath,
                path: path,
                headers: headers,
                body: bodyData
            ) else { return }
            // /message is preferred, /inject for backwards compat
            // Empty text = force enter (just press Enter without inserting)
            await handleMessage(connection, body: body)
        } else if path == "/companion/trigger" && method == "POST" {
            guard authorizeLocalClientIfNeeded(
                connection: connection,
                method: method,
                rawPath: rawPath,
                path: path,
                headers: headers,
                body: bodyData
            ) else { return }
            await handleCompanionTrigger(connection, body: body)
        } else if path == "/companion/trackpad" && method == "POST" {
            guard authorizeLocalClientIfNeeded(
                connection: connection,
                method: method,
                rawPath: rawPath,
                path: path,
                headers: headers,
                body: bodyData
            ) else { return }
            await handleCompanionTrackpad(connection, body: body)
        } else if path == "/companion/paste-image" && method == "POST" {
            guard authorizeLocalClientIfNeeded(
                connection: connection,
                method: method,
                rawPath: rawPath,
                path: path,
                headers: headers,
                body: bodyData
            ) else { return }
            await handleCompanionPasteImage(connection, body: body)
        } else if path == "/terminal/access" && method == "POST" {
            guard authorizeLocalClientIfNeeded(
                connection: connection,
                method: method,
                rawPath: rawPath,
                path: path,
                headers: headers,
                body: bodyData
            ) else { return }
            await handleTerminalAccess(connection)
        } else if path == "/windows/claude" && method == "GET" {
            guard authorizeLocalClientIfNeeded(
                connection: connection,
                method: method,
                rawPath: rawPath,
                path: path,
                headers: headers,
                body: bodyData
            ) else { return }
            await handleListClaudeWindows(connection)
        } else if path == "/screenshot/terminals" && method == "GET" {
            guard authorizeLocalClientIfNeeded(
                connection: connection,
                method: method,
                rawPath: rawPath,
                path: path,
                headers: headers,
                body: bodyData
            ) else { return }
            await handleCaptureTerminals(connection)
        } else if path == "/screenshot/display" && method == "GET" {
            guard authorizeLocalClientIfNeeded(
                connection: connection,
                method: method,
                rawPath: rawPath,
                path: path,
                headers: headers,
                body: bodyData
            ) else { return }
            let maxDimension = requestURL?.queryItems?.first(where: { $0.name == "maxDimension" })?.value.flatMap(Int.init) ?? 1600
            let quality = requestURL?.queryItems?.first(where: { $0.name == "quality" })?.value.flatMap(Double.init) ?? 0.7
            await handleCaptureMainDisplay(connection, maxDimension: maxDimension, quality: quality)
        } else if path.hasPrefix("/screenshot/window/") && method == "GET" {
            guard authorizeLocalClientIfNeeded(
                connection: connection,
                method: method,
                rawPath: rawPath,
                path: path,
                headers: headers,
                body: bodyData
            ) else { return }
            let windowIdStr = String(path.dropFirst("/screenshot/window/".count))
            if let windowId = UInt32(windowIdStr) {
                await handleCaptureWindow(connection, windowID: windowId)
            } else {
                sendResponse(connection, statusCode: 400, body: "Invalid window ID")
            }
        } else if path.hasPrefix("/tray/") && method == "GET" {
            await handleTrayImage(connection, path: path)
        } else {
            log.warning("TalkieServer 404: method='\(method)' path='\(path)'")
            sendResponse(connection, statusCode: 404, body: "Not found")
        }
    }

    private func handleLocalClientAccessRequest(_ connection: NWConnection, body: Data?) async {
        guard let body else {
            sendJSONResponse(
                connection,
                statusCode: 400,
                body: LocalClientAccessResponse(
                    ok: false,
                    status: "invalid",
                    clientId: nil,
                    grantedCapabilities: [],
                    fingerprint: nil,
                    message: "No request body"
                )
            )
            return
        }

        let request: LocalClientAccessRequest
        do {
            request = try JSONDecoder().decode(LocalClientAccessRequest.self, from: body)
        } catch {
            sendJSONResponse(
                connection,
                statusCode: 400,
                body: LocalClientAccessResponse(
                    ok: false,
                    status: "invalid",
                    clientId: nil,
                    grantedCapabilities: [],
                    fingerprint: nil,
                    message: "Invalid JSON: \(error.localizedDescription)"
                )
            )
            return
        }

        let clientID = request.clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = request.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let publicKey = request.publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let grantedCapabilities = LocalBridgeCapability.grantedCapabilities(for: request.requestedCapabilities)
        let fingerprint = Self.fingerprint(forPublicKeyBase64: publicKey)

        guard !clientID.isEmpty, !displayName.isEmpty, !publicKey.isEmpty else {
            sendJSONResponse(
                connection,
                statusCode: 400,
                body: LocalClientAccessResponse(
                    ok: false,
                    status: "invalid",
                    clientId: clientID.isEmpty ? nil : clientID,
                    grantedCapabilities: [],
                    fingerprint: fingerprint,
                    message: "Client id, display name, and public key are required"
                )
            )
            return
        }

        guard !grantedCapabilities.isEmpty else {
            sendJSONResponse(
                connection,
                statusCode: 403,
                body: LocalClientAccessResponse(
                    ok: false,
                    status: "denied",
                    clientId: clientID,
                    grantedCapabilities: [],
                    fingerprint: fingerprint,
                    message: "No supported capabilities were requested"
                )
            )
            return
        }

        guard Self.localClientPublicKey(from: publicKey) != nil else {
            sendJSONResponse(
                connection,
                statusCode: 400,
                body: LocalClientAccessResponse(
                    ok: false,
                    status: "invalid",
                    clientId: clientID,
                    grantedCapabilities: [],
                    fingerprint: fingerprint,
                    message: "Public key is not a supported P-256 key"
                )
            )
            return
        }

        if
            let existing = trustedLocalClients[clientID],
            existing.publicKey == publicKey,
            existing.isEnabled
        {
            var updated = existing
            updated.displayName = displayName
            updated.capabilities = grantedCapabilities
            updated.lastSeenAt = Date()
            trustedLocalClients[clientID] = updated
            persistTrustedLocalClients()
            sendJSONResponse(
                connection,
                statusCode: 200,
                body: LocalClientAccessResponse(
                    ok: true,
                    status: "approved",
                    clientId: clientID,
                    grantedCapabilities: grantedCapabilities,
                    fingerprint: fingerprint,
                    message: "Local client is already trusted"
                )
            )
            return
        }

        if let deniedUntil = localClientDeniedUntil[clientID], deniedUntil > Date() {
            sendJSONResponse(
                connection,
                statusCode: 403,
                body: LocalClientAccessResponse(
                    ok: false,
                    status: "denied",
                    clientId: clientID,
                    grantedCapabilities: [],
                    fingerprint: fingerprint,
                    message: "Local client access was recently denied"
                )
            )
            return
        }

        let isKeyRotation = trustedLocalClients[clientID] != nil
        let approved = promptForLocalClientAccess(
            displayName: displayName,
            fingerprint: fingerprint,
            capabilities: grantedCapabilities,
            isKeyRotation: isKeyRotation
        )

        guard approved else {
            localClientDeniedUntil[clientID] = Date().addingTimeInterval(600)
            sendJSONResponse(
                connection,
                statusCode: 403,
                body: LocalClientAccessResponse(
                    ok: false,
                    status: "denied",
                    clientId: clientID,
                    grantedCapabilities: [],
                    fingerprint: fingerprint,
                    message: "Access denied in Talkie"
                )
            )
            return
        }

        let now = Date()
        let record = TrustedLocalClientRecord(
            id: clientID,
            displayName: displayName,
            publicKey: publicKey,
            fingerprint: fingerprint,
            capabilities: grantedCapabilities,
            isEnabled: true,
            pairedAt: trustedLocalClients[clientID]?.pairedAt ?? now,
            lastSeenAt: now
        )
        trustedLocalClients[clientID] = record
        localClientDeniedUntil.removeValue(forKey: clientID)
        persistTrustedLocalClients()

        sendJSONResponse(
            connection,
            statusCode: 200,
            body: LocalClientAccessResponse(
                ok: true,
                status: "approved",
                clientId: clientID,
                grantedCapabilities: grantedCapabilities,
                fingerprint: fingerprint,
                message: "Local client access approved"
            )
        )
    }

    private func promptForLocalClientAccess(
        displayName: String,
        fingerprint: String,
        capabilities: [String],
        isKeyRotation: Bool
    ) -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = isKeyRotation
            ? "Allow \(displayName) to update its Talkie access key?"
            : "Allow \(displayName) to control Talkie locally?"
        alert.informativeText = """
        \(displayName) wants to call Talkie's local bridge from this Mac.

        Capabilities:
        \(capabilities.joined(separator: "\n"))

        Key fingerprint: \(fingerprint)
        """
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Deny")

        return alert.runModal() == .alertFirstButtonReturn
    }

    private func handleCompanionTrigger(_ connection: NWConnection, body: Data?) async {
        guard let body else {
            sendJSONResponse(
                connection,
                statusCode: 400,
                body: CompanionShortcutTriggerResponse(ok: false, error: "No body")
            )
            return
        }

        let request: CompanionShortcutTriggerRequest
        do {
            request = try JSONDecoder().decode(CompanionShortcutTriggerRequest.self, from: body)
        } catch {
            sendJSONResponse(
                connection,
                statusCode: 400,
                body: CompanionShortcutTriggerResponse(ok: false, error: "Invalid JSON: \(error.localizedDescription)")
            )
            return
        }

        let shortcutId = request.shortcutId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !shortcutId.isEmpty else {
            sendJSONResponse(
                connection,
                statusCode: 400,
                body: CompanionShortcutTriggerResponse(ok: false, error: "Shortcut ID is required")
            )
            return
        }

        let response = await performCompanionTrigger(shortcutId: shortcutId)
        sendJSONResponse(connection, statusCode: response.ok ? 200 : 400, body: response)
    }

    private func handleCompanionActivateApp(_ connection: NWConnection, body: Data?) async {
        guard let body else {
            sendJSONResponse(
                connection,
                statusCode: 400,
                body: CompanionShortcutTriggerResponse(ok: false, error: "No body")
            )
            return
        }

        let request: CompanionActivateAppRequest
        do {
            request = try JSONDecoder().decode(CompanionActivateAppRequest.self, from: body)
        } catch {
            sendJSONResponse(
                connection,
                statusCode: 400,
                body: CompanionShortcutTriggerResponse(ok: false, error: "Invalid JSON: \(error.localizedDescription)")
            )
            return
        }

        let processIdentifier = request.processIdentifier
        let bundleIdentifier = request.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard processIdentifier != nil || (bundleIdentifier?.isEmpty == false) else {
            sendJSONResponse(
                connection,
                statusCode: 400,
                body: CompanionShortcutTriggerResponse(ok: false, error: "App target is required")
            )
            return
        }

        guard let app = resolveCompanionSwitcherApp(
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier
        ) else {
            sendJSONResponse(
                connection,
                statusCode: 404,
                body: CompanionShortcutTriggerResponse(ok: false, error: "App is no longer available")
            )
            return
        }

        let activated = activateCompanionApp(app)
        sendJSONResponse(
            connection,
            statusCode: activated ? 200 : 500,
            body: CompanionShortcutTriggerResponse(
                ok: activated,
                handledShortcutId: "companion-activate-app",
                message: activated ? "\(app.localizedName ?? "App") focused" : nil,
                error: activated ? nil : "Failed to focus \(app.localizedName ?? "that app")"
            )
        )
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
                // Use default dictation model - already warm/loaded
                let modelId = TalkieDefaults.dictationModelId
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

        // Forward to TalkieAgent via XPC
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

        let appendResult: (success: Bool, error: String?)? = await callAgent(
            label: "appendMessage",
            timeoutSeconds: 10
        ) { service, reply in
            service.appendMessage(
                textToSend,
                sessionId: request.sessionId,
                projectPath: request.projectPath,
                submit: true
            ) { success, error in
                reply((success: success, error: error))
            }
        }

        guard let appendResult else {
            let durationMs = Int(Date().timeIntervalSince(xpcStartTime) * 1000)
            log.error("TalkieAgent not connected")
            respondOnce(503, MessageResponse(
                success: false,
                error: TalkieServerError.talkieLiveNotConnected,
                transcript: transcript
            ), false)
            MessageQueue.shared.updateStatus(messageId, status: .failed, error: TalkieServerError.talkieLiveNotConnected, xpcDurationMs: durationMs)
            return
        }

        let durationMs = Int(Date().timeIntervalSince(xpcStartTime) * 1000)
        if appendResult.success {
            log.info("Message sent via XPC in \(durationMs)ms")
            let deliveredAt = Date().iso8601
            respondOnce(200, MessageResponse(
                success: true,
                error: nil,
                transcript: transcript,
                deliveredAt: deliveredAt,
                insertedText: textToSend
            ), true)
        } else {
            log.error("Message failed: \(appendResult.error ?? "unknown error")")
            MessageQueue.shared.updateStatus(messageId, status: .failed, error: appendResult.error, xpcDurationMs: durationMs)
            respondOnce(500, MessageResponse(success: false, error: appendResult.error, transcript: transcript), false)
        }
    }

    private func handleWorkflowHostExecuteStep(_ connection: NWConnection, body: Data?) async {
        guard let body else {
            sendJSONResponse(connection, statusCode: 400, body: WorkflowHostStepResponse(ok: false, error: "No body"))
            return
        }

        let request: WorkflowHostStepRequest
        do {
            request = try JSONDecoder().decode(WorkflowHostStepRequest.self, from: body)
        } catch {
            sendJSONResponse(connection, statusCode: 400, body: WorkflowHostStepResponse(ok: false, error: "Invalid JSON: \(error.localizedDescription)"))
            return
        }

        guard let stepType = WorkflowStep.StepType(rawValue: request.stepType) else {
            sendJSONResponse(connection, statusCode: 400, body: WorkflowHostStepResponse(ok: false, error: "Unsupported step type: \(request.stepType)"))
            return
        }

        let isoFormatter = ISO8601DateFormatter()
        let fractionalISOFormatter = ISO8601DateFormatter()
        fractionalISOFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let date = fractionalISOFormatter.date(from: request.context.date)
            ?? isoFormatter.date(from: request.context.date) else {
            sendJSONResponse(connection, statusCode: 400, body: WorkflowHostStepResponse(ok: false, error: "Invalid context date"))
            return
        }

        do {
            let repository = LocalRepository()
            let memo: MemoModel?
            let assets: TalkieObjectAssets?
            if let memoData = try await repository.fetchMemo(id: request.memoId) {
                memo = memoData.memo
                assets = nil
            } else if let recording = try await TalkieObjectRepository().fetchRecording(id: request.memoId) {
                memo = recording.toMemoModel()
                assets = recording.assets
            } else {
                memo = nil
                assets = nil
            }

            guard let memo else {
                sendJSONResponse(connection, statusCode: 404, body: WorkflowHostStepResponse(ok: false, error: "Memo not found"))
                return
            }

            var workflowContext = WorkflowContext(
                transcript: request.context.transcript,
                title: request.context.title,
                date: date,
                assets: assets,
                memo: memo
            )
            workflowContext.outputs = request.context.outputs
            workflowContext.outputOrder = request.context.outputOrder

            let step = WorkflowStep(
                id: UUID(uuidString: request.stepId) ?? UUID(),
                type: stepType,
                config: try decodeHostedStepConfig(type: stepType, configJSON: request.configJSON),
                outputKey: request.outputKey,
                isEnabled: true
            )

            do {
                let output = try await WorkflowExecutor.shared.executeHostedStep(step, context: &workflowContext)
                sendJSONResponse(
                    connection,
                    statusCode: 200,
                    body: WorkflowHostStepResponse(
                        ok: true,
                        result: WorkflowHostStepResultPayload(status: "completed", output: output, reason: nil)
                    )
                )
            } catch is WorkflowExecutor.TriggerNotMatchedError {
                sendJSONResponse(
                    connection,
                    statusCode: 200,
                    body: WorkflowHostStepResponse(
                        ok: true,
                        result: WorkflowHostStepResultPayload(status: "halted", output: nil, reason: "Trigger not matched")
                    )
                )
            } catch {
                sendJSONResponse(connection, statusCode: 500, body: WorkflowHostStepResponse(ok: false, error: error.localizedDescription))
            }
        } catch {
            sendJSONResponse(connection, statusCode: 500, body: WorkflowHostStepResponse(ok: false, error: error.localizedDescription))
        }
    }

    private func decodeHostedStepConfig(type: WorkflowStep.StepType, configJSON: String) throws -> StepConfig {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(configJSON.utf8)

        switch type {
        case .llm:
            return .llm(try decoder.decode(LLMStepConfig.self, from: data))
        case .shell:
            return .shell(try decoder.decode(ShellStepConfig.self, from: data))
        case .webhook:
            return .webhook(try decoder.decode(WebhookStepConfig.self, from: data))
        case .email:
            return .email(try decoder.decode(EmailStepConfig.self, from: data))
        case .notification:
            return .notification(try decoder.decode(NotificationStepConfig.self, from: data))
        case .iOSPush:
            return .iOSPush(try decoder.decode(iOSPushStepConfig.self, from: data))
        case .appleNotes:
            return .appleNotes(try decoder.decode(AppleNotesStepConfig.self, from: data))
        case .appleReminders:
            return .appleReminders(try decoder.decode(AppleRemindersStepConfig.self, from: data))
        case .appleCalendar:
            return .appleCalendar(try decoder.decode(AppleCalendarStepConfig.self, from: data))
        case .clipboard:
            return .clipboard(try decoder.decode(ClipboardStepConfig.self, from: data))
        case .saveFile:
            return .saveFile(try decoder.decode(SaveFileStepConfig.self, from: data))
        case .conditional:
            return .conditional(try decoder.decode(ConditionalStepConfig.self, from: data))
        case .transform:
            return .transform(try decoder.decode(TransformStepConfig.self, from: data))
        case .transcribe:
            return .transcribe(try decoder.decode(TranscribeStepConfig.self, from: data))
        case .speak:
            return .speak(try decoder.decode(SpeakStepConfig.self, from: data))
        case .trigger:
            return .trigger(try decoder.decode(TriggerStepConfig.self, from: data))
        case .intentExtract:
            return .intentExtract(try decoder.decode(IntentExtractStepConfig.self, from: data))
        case .executeWorkflows:
            return .executeWorkflows(try decoder.decode(ExecuteWorkflowsStepConfig.self, from: data))
        case .cloudUpload:
            return .cloudUpload(try decoder.decode(CloudUploadStepConfig.self, from: data))
        }
    }

    private func performCompanionTrigger(shortcutId: String) async -> CompanionShortcutTriggerResponse {
        log.info("Companion shortcut trigger: \(shortcutId)")

        let appSwitcherShortcutIDs: Set<String> = ["deck-app-next", "deck-app-previous"]
        if !appSwitcherShortcutIDs.contains(shortcutId) {
            releaseCompanionAppSwitcherIfNeeded(reason: "shortcut=\(shortcutId)")
        }

        switch shortcutId {
        case "talkie-record":
            let memoRecorder = MemoRecordingController.shared
            switch memoRecorder.state {
            case .recording:
                memoRecorder.stopRecording()
                return CompanionShortcutTriggerResponse(
                    ok: true,
                    handledShortcutId: shortcutId,
                    message: "Memo recording is finishing",
                    runtimeState: companionRuntimeState(
                        shortcutId: shortcutId,
                        phase: "processing",
                        canStop: false,
                        detail: "Saving memo on your Mac",
                        elapsedSeconds: memoRecorder.elapsedTime
                    )
                )

            case .idle, .complete, .error:
                memoRecorder.startRecording()
                return CompanionShortcutTriggerResponse(
                    ok: true,
                    handledShortcutId: shortcutId,
                    message: "Memo recording started",
                    runtimeState: companionRuntimeState(
                        shortcutId: shortcutId,
                        phase: "preparing",
                        canStop: false,
                        detail: "Preparing memo recording"
                    )
                )

            case .preparing:
                return CompanionShortcutTriggerResponse(
                    ok: true,
                    handledShortcutId: shortcutId,
                    message: "Memo recording is preparing",
                    runtimeState: companionRuntimeState(
                        shortcutId: shortcutId,
                        phase: "preparing",
                        canStop: false,
                        detail: "Preparing memo recording"
                    )
                )

            case .processing:
                return CompanionShortcutTriggerResponse(
                    ok: true,
                    handledShortcutId: shortcutId,
                    message: "Memo recording is finishing",
                    runtimeState: companionRuntimeState(
                        shortcutId: shortcutId,
                        phase: "processing",
                        canStop: false,
                        detail: "Saving memo on your Mac",
                        elapsedSeconds: memoRecorder.elapsedTime
                    )
                )
            }

        case "talkie-dictate":
            activeDictationShortcutId = shortcutId
            switch ServiceManager.shared.live.state {
            case .idle:
                if shouldSuppressCompanionDictationRestart(shortcutId: shortcutId) {
                    return companionDictationAlreadyStoppedResponse(shortcutId: shortcutId)
                }

                lastCompanionDictationShortcutId = shortcutId
                lastCompanionDictationStartedAt = Date()
                ServiceManager.shared.live.toggleRecording()
                return CompanionShortcutTriggerResponse(
                    ok: true,
                    handledShortcutId: shortcutId,
                    message: "Dictation started",
                    runtimeState: companionRuntimeState(
                        shortcutId: shortcutId,
                        phase: "preparing",
                        canStop: false,
                        detail: "Starting dictation on your Mac"
                    )
                )

            case .listening:
                markCompanionDictationStopped(shortcutId: shortcutId)
                ServiceManager.shared.live.toggleRecording()
                return CompanionShortcutTriggerResponse(
                    ok: true,
                    handledShortcutId: shortcutId,
                    message: "Dictation is finishing",
                    runtimeState: companionRuntimeState(
                        shortcutId: shortcutId,
                        phase: "processing",
                        canStop: false,
                        detail: "Finishing dictation on your Mac",
                        elapsedSeconds: ServiceManager.shared.live.elapsedTime
                    )
                )

            case .transcribing, .routing, .refining:
                return CompanionShortcutTriggerResponse(
                    ok: true,
                    handledShortcutId: shortcutId,
                    message: "Dictation is finishing",
                    runtimeState: companionRuntimeState(
                        shortcutId: shortcutId,
                        phase: "processing",
                        canStop: false,
                        detail: "Finishing dictation on your Mac",
                        elapsedSeconds: ServiceManager.shared.live.elapsedTime
                    )
                )
            }

        case "iterm-dictate":
            activeDictationShortcutId = shortcutId
            switch ServiceManager.shared.live.state {
            case .idle:
                if shouldSuppressCompanionDictationRestart(shortcutId: shortcutId) {
                    return companionDictationAlreadyStoppedResponse(shortcutId: shortcutId)
                }

                lastCompanionDictationShortcutId = shortcutId
                lastCompanionDictationStartedAt = Date()
                let didOpen = await openITermForCompanion()
                guard didOpen else {
                    return CompanionShortcutTriggerResponse(
                        ok: false,
                        handledShortcutId: shortcutId,
                        error: "iTerm is not available or could not be opened"
                    )
                }

                try? await Task.sleep(for: .milliseconds(300))
                ServiceManager.shared.live.toggleRecording()
                return CompanionShortcutTriggerResponse(
                    ok: true,
                    handledShortcutId: shortcutId,
                    message: "New iTerm ready for dictated input",
                    runtimeState: companionRuntimeState(
                        shortcutId: shortcutId,
                        phase: "preparing",
                        canStop: false,
                        detail: "Starting iTerm dictation on your Mac"
                    )
                )

            case .listening:
                markCompanionDictationStopped(shortcutId: shortcutId)
                ServiceManager.shared.live.toggleRecording()
                return CompanionShortcutTriggerResponse(
                    ok: true,
                    handledShortcutId: shortcutId,
                    message: "iTerm dictation is finishing",
                    runtimeState: companionRuntimeState(
                        shortcutId: shortcutId,
                        phase: "processing",
                        canStop: false,
                        detail: "Finishing iTerm dictation on your Mac",
                        elapsedSeconds: ServiceManager.shared.live.elapsedTime
                    )
                )

            case .transcribing, .routing, .refining:
                return CompanionShortcutTriggerResponse(
                    ok: true,
                    handledShortcutId: shortcutId,
                    message: "iTerm dictation is finishing",
                    runtimeState: companionRuntimeState(
                        shortcutId: shortcutId,
                        phase: "processing",
                        canStop: false,
                        detail: "Finishing iTerm dictation on your Mac",
                        elapsedSeconds: ServiceManager.shared.live.elapsedTime
                    )
                )
            }

        case "talkie-search":
            bringTalkieToFront()
            SettingsManager.shared.isContentSearchPresented = true
            return CompanionShortcutTriggerResponse(
                ok: true,
                handledShortcutId: shortcutId,
                message: "Search opened"
            )

        case "mac-sessions":
            bringTalkieToFront()
            NavigationState.shared.navigateToWorkflows()
            return CompanionShortcutTriggerResponse(
                ok: true,
                handledShortcutId: shortcutId,
                message: "Workflows opened"
            )

        case "mac-windows":
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("to.talkie.app.screenshotChord"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            return CompanionShortcutTriggerResponse(
                ok: true,
                handledShortcutId: shortcutId,
                message: "Screenshot flow started"
            )

        case "mac-claude":
            bringTalkieToFront()
            _ = NavigationState.shared.navigateToConsoleTab(
                "claude",
                createIfMissing: TabPresets.claude
            )
            return CompanionShortcutTriggerResponse(
                ok: true,
                handledShortcutId: shortcutId,
                message: "Claude tab opened"
            )

        case "talkie-ssh":
            bringTalkieToFront()
            _ = NavigationState.shared.navigateToConsoleTab(
                "talkie-shell",
                createIfMissing: TabPresets.talkieShell
            )
            return CompanionShortcutTriggerResponse(
                ok: true,
                handledShortcutId: shortcutId,
                message: "Talkie Shell opened"
            )

        case "talkie-settings":
            bringTalkieToFront()
            SettingsManager.shared.isVoiceCommandPresented = true
            return CompanionShortcutTriggerResponse(
                ok: true,
                handledShortcutId: shortcutId,
                message: "Voice command opened"
            )

        case "talkie-memos":
            bringTalkieToFront()
            NavigationState.shared.navigateToAllMemos()
            return CompanionShortcutTriggerResponse(
                ok: true,
                handledShortcutId: shortcutId,
                message: "Memo library opened"
            )

        case "talkie-keyboard":
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("to.talkie.app.screenRecordChord"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            return CompanionShortcutTriggerResponse(
                ok: true,
                handledShortcutId: shortcutId,
                message: "Screen recording flow started"
            )

        case "talkie-home":
            bringTalkieToFront()
            NavigationState.shared.navigateToHome()
            return CompanionShortcutTriggerResponse(
                ok: true,
                handledShortcutId: shortcutId,
                message: "Talkie home opened"
            )

        case "talkie-agent":
            bringTalkieToFront()
            _ = NavigationState.shared.navigateToConsoleTab(
                "pi",
                createIfMissing: TabPresets.pi
            )
            return CompanionShortcutTriggerResponse(
                ok: true,
                handledShortcutId: shortcutId,
                message: "Pi tab opened"
            )

        case "talkie-pending":
            bringTalkieToFront()
            NavigationState.shared.navigate(to: .pendingActions)
            return CompanionShortcutTriggerResponse(
                ok: true,
                handledShortcutId: shortcutId,
                message: "Pending actions opened"
            )

        case "talkie-command":
            bringTalkieToFront()
            SettingsManager.shared.isCommandPalettePresented = true
            return CompanionShortcutTriggerResponse(
                ok: true,
                handledShortcutId: shortcutId,
                message: "Command palette opened"
            )

        case "talkie-recent":
            bringTalkieToFront()
            NavigationState.shared.navigateToDictations()
            return CompanionShortcutTriggerResponse(
                ok: true,
                handledShortcutId: shortcutId,
                message: "Recent activity opened"
            )

        case "talkie-devices":
            bringTalkieToFront()
            NavigationState.shared.navigateToSettings(.shortcutKeyboard)
            return CompanionShortcutTriggerResponse(
                ok: true,
                handledShortcutId: shortcutId,
                message: "Devices settings opened"
            )

        case "deck-enter":
            return keyPressResponse(
                shortcutId: shortcutId,
                succeeded: performCompanionKeyPress(keyCode: 36),
                successMessage: "Return key sent",
                failureMessage: "Failed to send Return key"
            )

        case "deck-delete":
            return keyPressResponse(
                shortcutId: shortcutId,
                succeeded: performCompanionKeyPress(keyCode: 51),
                successMessage: "Delete key sent",
                failureMessage: "Failed to send Delete key"
            )

        case "deck-select-all":
            return keyPressResponse(
                shortcutId: shortcutId,
                succeeded: performCompanionKeyPress(keyCode: 0, modifiers: .maskCommand),
                successMessage: "Select all sent",
                failureMessage: "Failed to send Command-A"
            )

        case "deck-paste":
            return keyPressResponse(
                shortcutId: shortcutId,
                succeeded: performCompanionKeyPress(keyCode: 9, modifiers: .maskCommand),
                successMessage: "Paste sent",
                failureMessage: "Failed to send Command-V"
            )

        case "deck-copy":
            return keyPressResponse(
                shortcutId: shortcutId,
                succeeded: performCompanionKeyPress(keyCode: 8, modifiers: .maskCommand),
                successMessage: "Copy sent",
                failureMessage: "Failed to send Command-C"
            )

        case "deck-escape":
            return keyPressResponse(
                shortcutId: shortcutId,
                succeeded: performCompanionKeyPress(keyCode: 53),
                successMessage: "Escape sent",
                failureMessage: "Failed to send Escape"
            )

        case "deck-up":
            return keyPressResponse(
                shortcutId: shortcutId,
                succeeded: performCompanionKeyPress(keyCode: 126),
                successMessage: "Up arrow sent",
                failureMessage: "Failed to send Up arrow"
            )

        case "deck-down":
            return keyPressResponse(
                shortcutId: shortcutId,
                succeeded: performCompanionKeyPress(keyCode: 125),
                successMessage: "Down arrow sent",
                failureMessage: "Failed to send Down arrow"
            )

        case "deck-left":
            return keyPressResponse(
                shortcutId: shortcutId,
                succeeded: performCompanionKeyPress(keyCode: 123),
                successMessage: "Left arrow sent",
                failureMessage: "Failed to send Left arrow"
            )

        case "deck-right":
            return keyPressResponse(
                shortcutId: shortcutId,
                succeeded: performCompanionKeyPress(keyCode: 124),
                successMessage: "Right arrow sent",
                failureMessage: "Failed to send Right arrow"
            )

        case "deck-space":
            return keyPressResponse(
                shortcutId: shortcutId,
                succeeded: performCompanionKeyPress(keyCode: 49),
                successMessage: "Space sent",
                failureMessage: "Failed to send Space"
            )

        case "deck-ctrl-c":
            return keyPressResponse(
                shortcutId: shortcutId,
                succeeded: performCompanionKeyPress(keyCode: 8, modifiers: .maskControl),
                successMessage: "Control-C sent",
                failureMessage: "Failed to send Control-C"
            )

        case "deck-window-previous":
            return keyPressResponse(
                shortcutId: shortcutId,
                succeeded: performFrontmostWindowSwitch(next: false),
                successMessage: "Previous window focused",
                failureMessage: "Failed to focus previous window"
            )

        case "deck-window-next":
            return keyPressResponse(
                shortcutId: shortcutId,
                succeeded: performFrontmostWindowSwitch(next: true),
                successMessage: "Next window focused",
                failureMessage: "Failed to focus next window"
            )

        case "deck-tab-previous":
            return keyPressResponse(
                shortcutId: shortcutId,
                succeeded: performFrontmostTabSwitch(next: false),
                successMessage: "Previous tab sent",
                failureMessage: "Failed to send previous tab switch"
            )

        case "deck-tab-next":
            return keyPressResponse(
                shortcutId: shortcutId,
                succeeded: performFrontmostTabSwitch(next: true),
                successMessage: "Next tab sent",
                failureMessage: "Failed to send next tab switch"
            )

        case "deck-app-previous":
            return keyPressResponse(
                shortcutId: shortcutId,
                succeeded: performFrontmostAppSwitch(next: false),
                successMessage: "Previous app sent",
                failureMessage: "Failed to send previous app switch"
            )

        case "deck-app-next":
            return keyPressResponse(
                shortcutId: shortcutId,
                succeeded: performFrontmostAppSwitch(next: true),
                successMessage: "Next app sent",
                failureMessage: "Failed to send next app switch"
            )

        case "deck-space-left":
            return keyPressResponse(
                shortcutId: shortcutId,
                succeeded: performSpaceSwitch(offset: -1),
                successMessage: "Moved one space left",
                failureMessage: "Failed to move one space left"
            )

        case "deck-space-right":
            return keyPressResponse(
                shortcutId: shortcutId,
                succeeded: performSpaceSwitch(offset: 1),
                successMessage: "Moved one space right",
                failureMessage: "Failed to move one space right"
            )

        case "deck-space-left-2":
            return keyPressResponse(
                shortcutId: shortcutId,
                succeeded: performSpaceSwitch(offset: -2),
                successMessage: "Moved two spaces left",
                failureMessage: "Failed to move two spaces left"
            )

        case "deck-space-right-2":
            return keyPressResponse(
                shortcutId: shortcutId,
                succeeded: performSpaceSwitch(offset: 2),
                successMessage: "Moved two spaces right",
                failureMessage: "Failed to move two spaces right"
            )

        default:
            return CompanionShortcutTriggerResponse(
                ok: false,
                handledShortcutId: shortcutId,
                error: "Unsupported shortcut ID: \(shortcutId)"
            )
        }
    }

    private func currentCompanionRuntimeState() async -> CompanionRuntimeStateResponse {
        var states: [CompanionShortcutRuntimeState] = []

        switch MemoRecordingController.shared.state {
        case .idle, .complete, .error:
            break
        case .preparing:
            states.append(
                CompanionShortcutRuntimeState(
                    shortcutId: "talkie-record",
                    phase: "preparing",
                    canStop: false,
                    detail: "Preparing memo recording",
                    elapsedSeconds: nil,
                    signalLevel: nil
                )
            )
        case .recording:
            states.append(
                CompanionShortcutRuntimeState(
                    shortcutId: "talkie-record",
                    phase: "recording",
                    canStop: true,
                    detail: "Recording memo on your Mac",
                    elapsedSeconds: MemoRecordingController.shared.elapsedTime,
                    signalLevel: Double(MemoRecordingController.shared.audioLevel)
                )
            )
        case .processing:
            states.append(
                CompanionShortcutRuntimeState(
                    shortcutId: "talkie-record",
                    phase: "processing",
                    canStop: false,
                    detail: "Saving memo on your Mac",
                    elapsedSeconds: MemoRecordingController.shared.elapsedTime,
                    signalLevel: nil
                )
            )
        }

        let dictationShortcutId = activeDictationShortcutId

        switch ServiceManager.shared.live.state {
        case .idle:
            break
        case .listening:
            states.append(
                CompanionShortcutRuntimeState(
                    shortcutId: dictationShortcutId,
                    phase: "recording",
                    canStop: true,
                    detail: dictationShortcutId == "iterm-dictate" ? "Listening for iTerm on your Mac" : "Listening on your Mac",
                    elapsedSeconds: ServiceManager.shared.live.elapsedTime,
                    signalLevel: Double(ServiceManager.shared.live.audioLevel)
                )
            )
        case .transcribing, .routing, .refining:
            states.append(
                CompanionShortcutRuntimeState(
                    shortcutId: dictationShortcutId,
                    phase: "processing",
                    canStop: false,
                    detail: dictationShortcutId == "iterm-dictate" ? "Finishing iTerm dictation on your Mac" : "Finishing dictation on your Mac",
                    elapsedSeconds: ServiceManager.shared.live.elapsedTime,
                    signalLevel: nil
                )
            )
        }

        let activeShortcutIDs = Set(states.map(\.shortcutId))
        let recentResults = await currentCompanionRecentResults(excluding: activeShortcutIDs)
        let appSwitcherApps = currentCompanionAppSwitcherApps()

        return CompanionRuntimeStateResponse(
            shortcutStates: states,
            recentResults: recentResults,
            appSwitcherApps: appSwitcherApps
        )
    }

    private func companionRuntimeState(
        shortcutId: String,
        phase: String,
        canStop: Bool,
        detail: String,
        elapsedSeconds: Double? = nil,
        signalLevel: Double? = nil
    ) -> CompanionShortcutRuntimeState {
        CompanionShortcutRuntimeState(
            shortcutId: shortcutId,
            phase: phase,
            canStop: canStop,
            detail: detail,
            elapsedSeconds: elapsedSeconds,
            signalLevel: signalLevel
        )
    }

    private func markCompanionDictationStopped(shortcutId: String) {
        lastCompanionDictationStoppedShortcutId = shortcutId
        lastCompanionDictationStoppedAt = Date()
    }

    private func shouldSuppressCompanionDictationRestart(shortcutId: String) -> Bool {
        guard lastCompanionDictationStoppedShortcutId == shortcutId,
              let stoppedAt = lastCompanionDictationStoppedAt else {
            return false
        }

        return Date().timeIntervalSince(stoppedAt) <= companionDictationRestartSuppressionInterval
    }

    private func companionDictationAlreadyStoppedResponse(shortcutId: String) -> CompanionShortcutTriggerResponse {
        CompanionShortcutTriggerResponse(
            ok: true,
            handledShortcutId: shortcutId,
            message: "Dictation is stopped"
        )
    }

    private func currentCompanionRecentResults(
        excluding activeShortcutIDs: Set<String>
    ) async -> [CompanionShortcutRecentResult] {
        guard ServiceManager.shared.live.state == .idle,
              let shortcutId = lastCompanionDictationShortcutId,
              let startedAt = lastCompanionDictationStartedAt,
              !activeShortcutIDs.contains(shortcutId) else {
            return []
        }

        do {
            let recentDictations = try await recordingRepository.fetchRecentDictations(limit: 3)
            guard let latestDictation = recentDictations.first(where: {
                guard let text = $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    return false
                }
                return !text.isEmpty
            }) else {
                return []
            }

            let completionDate = latestDictation.lastModified ?? latestDictation.createdAt
            let elapsedSinceCompletion = Date().timeIntervalSince(completionDate)
            guard elapsedSinceCompletion >= 0, elapsedSinceCompletion <= 120 else {
                return []
            }

            guard completionDate >= startedAt.addingTimeInterval(-5),
                  let resultText = latestDictation.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !resultText.isEmpty else {
                return []
            }

            return [
                CompanionShortcutRecentResult(
                    shortcutId: shortcutId,
                    resultText: resultText,
                    completedAt: ISO8601DateFormatter().string(from: completionDate)
                )
            ]
        } catch {
            log.warning("Failed to fetch recent companion dictation", detail: "\(error)")
            return []
        }
    }

    private func keyPressResponse(
        shortcutId: String,
        succeeded: Bool,
        successMessage: String,
        failureMessage: String
    ) -> CompanionShortcutTriggerResponse {
        CompanionShortcutTriggerResponse(
            ok: succeeded,
            handledShortcutId: shortcutId,
            message: succeeded ? successMessage : nil,
            error: succeeded ? nil : failureMessage
        )
    }

    private func installCompanionWorkspaceObserverIfNeeded() {
        guard companionWorkspaceActivationObserver == nil else { return }

        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            rememberCompanionAppActivation(frontmostApp)
        }

        companionWorkspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            Task { @MainActor [weak self] in
                self?.rememberCompanionAppActivation(app)
            }
        }
    }

    private func rememberCompanionAppActivation(_ app: NSRunningApplication) {
        guard isEligibleCompanionSwitcherApp(app) else { return }

        companionAppActivationOrder.removeAll { $0 == app.processIdentifier }
        companionAppActivationOrder.insert(app.processIdentifier, at: 0)

        if companionAppActivationOrder.count > 16 {
            companionAppActivationOrder.removeLast(companionAppActivationOrder.count - 16)
        }
    }

    private func currentCompanionAppSwitcherApps(limit: Int = 12) -> [CompanionAppSwitcherApp] {
        let runningApps = NSWorkspace.shared.runningApplications.filter(isEligibleCompanionSwitcherApp)
        guard !runningApps.isEmpty else { return [] }

        let runningByPID = Dictionary(uniqueKeysWithValues: runningApps.map { ($0.processIdentifier, $0) })
        let frontmostPID = NSWorkspace.shared.frontmostApplication
            .flatMap { isEligibleCompanionSwitcherApp($0) ? $0.processIdentifier : nil }

        var orderedPIDs = companionAppActivationOrder.filter { runningByPID[$0] != nil }
        if let frontmostPID {
            orderedPIDs.removeAll { $0 == frontmostPID }
            orderedPIDs.insert(frontmostPID, at: 0)
        }

        let remainder = runningApps
            .filter { app in !orderedPIDs.contains(app.processIdentifier) }
            .sorted { lhs, rhs in
                let lhsName = lhs.localizedName ?? ""
                let rhsName = rhs.localizedName ?? ""
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }
            .map(\.processIdentifier)

        orderedPIDs.append(contentsOf: remainder)

        return orderedPIDs.prefix(limit).compactMap { pid in
            guard let app = runningByPID[pid],
                  let displayName = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !displayName.isEmpty else {
                return nil
            }

            return CompanionAppSwitcherApp(
                processIdentifier: app.processIdentifier,
                bundleIdentifier: app.bundleIdentifier,
                displayName: displayName,
                isFrontmost: app.processIdentifier == frontmostPID,
                iconPNGBase64: companionAppIconBase64(for: app)
            )
        }
    }

    private func companionAppIconBase64(
        for app: NSRunningApplication,
        size: NSSize = NSSize(width: 60, height: 60)
    ) -> String? {
        let iconImage: NSImage

        if let bundleIdentifier = app.bundleIdentifier {
            iconImage = AppIconProvider.shared.icon(forBundleIdentifier: bundleIdentifier, size: size)
        } else if let appIcon = app.icon {
            iconImage = renderedCompanionAppIcon(from: appIcon, size: size)
        } else {
            return nil
        }

        guard let tiffData = iconImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return nil
        }

        return pngData.base64EncodedString()
    }

    private func renderedCompanionAppIcon(from source: NSImage, size: NSSize) -> NSImage {
        let scale = max(1.0, NSScreen.main?.backingScaleFactor ?? 2.0)
        let pixelWidth = max(1, Int((size.width * scale).rounded(.up)))
        let pixelHeight = max(1, Int((size.height * scale).rounded(.up)))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            let fallback = source.copy() as? NSImage ?? source
            fallback.size = size
            return fallback
        }

        bitmap.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: source.size),
            operation: .copy,
            fraction: 1.0
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }

    private func resolveCompanionSwitcherApp(
        processIdentifier: Int32?,
        bundleIdentifier: String?
    ) -> NSRunningApplication? {
        if let processIdentifier,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == processIdentifier }) {
            return app
        }

        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier })
        }

        return nil
    }

    private func activateCompanionApp(_ app: NSRunningApplication) -> Bool {
        releaseCompanionAppSwitcherIfNeeded(reason: "directActivation")
        _ = app.unhide()

        let detail = "\(app.localizedName ?? "Unknown") pid=\(app.processIdentifier)"

        if app.activate(options: [.activateAllWindows]) {
            rememberCompanionAppActivation(app)
            log.info("Companion activated app directly", detail: detail)
            return true
        }

        if let bundleIdentifier = app.bundleIdentifier,
           activateCompanionAppViaAppleScript(bundleIdentifier: bundleIdentifier) {
            rememberCompanionAppActivation(app)
            log.info(
                "Companion activated app via AppleScript fallback",
                detail: "\(detail) bundleId=\(bundleIdentifier)"
            )
            return true
        }

        log.warning("Companion failed to activate app directly", detail: detail)
        return false
    }

    private func activateCompanionAppViaAppleScript(bundleIdentifier: String) -> Bool {
        let script = #"tell application id "\#(bundleIdentifier)" to activate"#
        var errorInfo: NSDictionary?
        let executed = NSAppleScript(source: script)?.executeAndReturnError(&errorInfo) != nil

        if !executed, let errorInfo {
            log.warning(
                "Companion AppleScript activation failed",
                detail: "\(bundleIdentifier): \(errorInfo)"
            )
        }

        return executed
    }

    private func isEligibleCompanionSwitcherApp(_ app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular else { return false }
        guard let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return false
        }
        return true
    }

    private func handleTerminalAccess(_ connection: NWConnection) async {
        do {
            let connectionDetails = preferredTerminalAccessConnection()
            let prepared = try await SSHKeyQRCodeProvisioner.prepare(connection: connectionDetails)
            let response = TerminalAccessResponse(
                ok: true,
                payload: prepared.payload,
                label: prepared.status.label,
                host: connectionDetails?.host,
                alternateHosts: connectionDetails?.alternateHosts ?? [],
                fingerprint: prepared.status.fingerprint,
                error: nil
            )
            sendJSONResponse(connection, statusCode: 200, body: response)
        } catch {
            log.error("Failed to prepare terminal access payload", detail: error.localizedDescription)
            sendJSONResponse(
                connection,
                statusCode: 500,
                body: TerminalAccessResponse(
                    ok: false,
                    payload: nil,
                    label: nil,
                    host: nil,
                    alternateHosts: [],
                    fingerprint: nil,
                    error: error.localizedDescription
                )
            )
        }
    }

    private func preferredTerminalAccessConnection() -> SSHKeyQRCodeProvisioner.ConnectionDetails? {
        let hosts = preferredTerminalAccessHosts
        guard let host = hosts.first else {
            return nil
        }

        return SSHKeyQRCodeProvisioner.ConnectionDetails(
            host: host,
            port: 22,
            username: NSUserName(),
            startupProfileRawValue: "standardShell",
            launcherModeRawValue: "native",
            autoConnect: true,
            alternateHosts: Array(hosts.dropFirst())
        )
    }

    private var preferredTerminalAccessHosts: [String] {
        let bridgeManager = BridgeManager.shared
        var candidates: [String?] = []

        if bridgeManager.qrData?.isPairingReady == true {
            candidates.append(bridgeManager.qrData?.hostname)
            candidates.append(contentsOf: bridgeManager.qrData?.alternateHosts ?? [])
        }

        candidates.append(TalkieNetworkRouteClassifier.localBonjourHostname(from: Host.current().name))
        candidates.append(bridgeManager.tailscaleStatus.hostname)

        var seen: Set<String> = []
        var hosts: [String] = []
        for candidate in candidates {
            let host = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let normalized = host.lowercased()
            guard !host.isEmpty,
                  normalized != "localhost",
                  normalized != "127.0.0.1",
                  normalized != "::1",
                  !seen.contains(normalized) else {
                continue
            }

            seen.insert(normalized)
            hosts.append(host)
        }

        return hosts
    }

    private struct CompanionPasteImageRequest: Codable {
        let imageBase64: String
        let mimeType: String?
        let autoPaste: Bool?
    }

    private struct CompanionTerminalImagePasteTarget {
        let bundleIdentifier: String
        let displayName: String
    }

    private struct CompanionTerminalImagePastePayload {
        let fileURL: URL
        let pasteText: String
        let pngData: Data
    }

    private func handleCompanionPasteImage(_ connection: NWConnection, body: Data?) async {
        guard let body else {
            sendJSONResponse(
                connection,
                statusCode: 400,
                body: CompanionShortcutTriggerResponse(ok: false, error: "No body")
            )
            return
        }

        let request: CompanionPasteImageRequest
        do {
            request = try JSONDecoder().decode(CompanionPasteImageRequest.self, from: body)
        } catch {
            sendJSONResponse(
                connection,
                statusCode: 400,
                body: CompanionShortcutTriggerResponse(ok: false, error: "Invalid JSON: \(error.localizedDescription)")
            )
            return
        }

        guard let imageData = Data(base64Encoded: request.imageBase64),
              let image = NSImage(data: imageData) else {
            sendJSONResponse(
                connection,
                statusCode: 400,
                body: CompanionShortcutTriggerResponse(ok: false, error: "Invalid image payload")
            )
            return
        }

        if let terminalTarget = currentCompanionTerminalImagePasteTarget(),
           let terminalPayload = makeCompanionTerminalImagePastePayload(
               from: image
           ) {
            let clipboardWritten = await MainActor.run { () -> Bool in
                writeCompanionTerminalImagePasteboard(terminalPayload)
            }

            guard clipboardWritten else {
                sendJSONResponse(
                    connection,
                    statusCode: 500,
                    body: CompanionShortcutTriggerResponse(ok: false, error: "Failed to write image path to clipboard")
                )
                return
            }

            if request.autoPaste ?? true {
                try? await Task.sleep(for: .milliseconds(80))

                let inserted = insertCompanionTerminalImageReference(
                    terminalPayload.pasteText,
                    into: terminalTarget
                ) || performCompanionShortcutKeyPress(keyCode: 9, modifiers: .maskCommand)

                guard inserted else {
                    sendJSONResponse(
                        connection,
                        statusCode: 500,
                        body: CompanionShortcutTriggerResponse(
                            ok: false,
                            error: "Image saved and copied, but paste into \(terminalTarget.displayName) failed"
                        )
                    )
                    return
                }
            }

            sendJSONResponse(
                connection,
                statusCode: 200,
                body: CompanionShortcutTriggerResponse(
                    ok: true,
                    handledShortcutId: "companion-paste-image",
                    message: request.autoPaste ?? true
                        ? "Image path pasted into \(terminalTarget.displayName)"
                        : "Image path copied to clipboard"
                )
            )
            return
        }

        let clipboardWritten = await MainActor.run { () -> Bool in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.writeObjects([image])
        }

        guard clipboardWritten else {
            sendJSONResponse(
                connection,
                statusCode: 500,
                body: CompanionShortcutTriggerResponse(ok: false, error: "Failed to write image to clipboard")
            )
            return
        }

        if request.autoPaste ?? true {
            try? await Task.sleep(for: .milliseconds(80))

            guard performCompanionKeyPress(keyCode: 9, modifiers: .maskCommand) else {
                sendJSONResponse(
                    connection,
                    statusCode: 500,
                    body: CompanionShortcutTriggerResponse(ok: false, error: "Image copied, but paste failed")
                )
                return
            }
        }

        sendJSONResponse(
            connection,
            statusCode: 200,
            body: CompanionShortcutTriggerResponse(
                ok: true,
                handledShortcutId: "companion-paste-image",
                message: request.autoPaste ?? true ? "Image pasted" : "Image copied to clipboard"
            )
        )
    }

    private func currentCompanionTerminalImagePasteTarget() -> CompanionTerminalImagePasteTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = app.bundleIdentifier?.lowercased() else {
            return nil
        }

        let terminalBundleIdentifiers: Set<String> = [
            "com.googlecode.iterm2",
            "com.apple.terminal",
            "com.github.wez.wezterm",
            "com.mitchellh.ghostty",
            "dev.warp.warp-stable",
            "net.kovidgoyal.kitty",
            "org.alacritty",
            "io.alacritty",
        ]

        guard terminalBundleIdentifiers.contains(bundleIdentifier) else {
            return nil
        }

        return CompanionTerminalImagePasteTarget(
            bundleIdentifier: bundleIdentifier,
            displayName: app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "terminal"
        )
    }

    private func makeCompanionTerminalImagePastePayload(from image: NSImage) -> CompanionTerminalImagePastePayload? {
        guard let pngData = pngData(from: image) else {
            return nil
        }

        let imageSize = companionImagePixelSize(image)
        guard let fileURL = ScreenshotStorage.saveStandalone(
            pngData,
            capturedAt: Date(),
            captureMode: "devices/companion",
            width: imageSize.width,
            height: imageSize.height,
            appName: "iPhone",
            displayName: "Shared Image",
            relativeDirectory: "devices/companion"
        ) else {
            return nil
        }

        return CompanionTerminalImagePastePayload(
            fileURL: fileURL,
            pasteText: fileURL.path,
            pngData: pngData
        )
    }

    private func writeCompanionTerminalImagePasteboard(
        _ payload: CompanionTerminalImagePastePayload
    ) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let wroteText = pasteboard.setString(payload.pasteText, forType: .string)
        pasteboard.setString(payload.fileURL.absoluteString, forType: .fileURL)
        pasteboard.setData(payload.pngData, forType: .png)
        return wroteText
    }

    private func insertCompanionTerminalImageReference(
        _ text: String,
        into target: CompanionTerminalImagePasteTarget
    ) -> Bool {
        guard target.bundleIdentifier == "com.googlecode.iterm2" else {
            return false
        }
        guard text.count <= 120_000 else {
            log.info("Companion iTerm image path using clipboard paste", detail: "chars=\(text.count)")
            return false
        }

        let escaped = appleScriptStringLiteral(text)
        let script = """
        tell application id "com.googlecode.iterm2"
            tell current session of current window
                write text "\(escaped)" newline NO
            end tell
        end tell
        """

        return runAppleScript(script, failurePrefix: "Companion iTerm image path paste failed")
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    private func companionImagePixelSize(_ image: NSImage) -> (width: Int, height: Int) {
        let bestRepresentation = image.representations.max { lhs, rhs in
            (lhs.pixelsWide * lhs.pixelsHigh) < (rhs.pixelsWide * rhs.pixelsHigh)
        }

        if let bestRepresentation,
           bestRepresentation.pixelsWide > 0,
           bestRepresentation.pixelsHigh > 0 {
            return (bestRepresentation.pixelsWide, bestRepresentation.pixelsHigh)
        }

        return (
            max(1, Int(image.size.width.rounded(.up))),
            max(1, Int(image.size.height.rounded(.up)))
        )
    }

    private func appleScriptStringLiteral(_ value: String) -> String {
        value
            .replacing("\\", with: "\\\\")
            .replacing("\"", with: "\\\"")
            .replacing("\r", with: " ")
            .replacing("\n", with: " ")
    }

    // MARK: - Trackpad handler

    private struct TrackpadRequest: Decodable {
        let event: String          // "move" | "click" | "rightClick" | "scroll" | "mouseDown" | "mouseUp" | "drag"
        let dx: Double?
        let dy: Double?
    }

    private func handleCompanionTrackpad(_ connection: NWConnection, body: Data?) async {
        guard let body,
              let req = try? JSONDecoder().decode(TrackpadRequest.self, from: body) else {
            sendResponse(connection, statusCode: 400, body: "Invalid trackpad request")
            return
        }

        let ok: Bool
        switch req.event {
        case "move":
            ok = performMouseMove(dx: req.dx ?? 0, dy: req.dy ?? 0)
        case "click":
            ok = consumeCompanionSelectionConfirmationIfNeeded() || performMouseClick(button: .left)
        case "rightClick":
            ok = consumeCompanionSelectionConfirmationIfNeeded() || performMouseClick(button: .right)
        case "scroll":
            ok = performMouseScroll(dx: req.dx ?? 0, dy: req.dy ?? 0)
        case "mouseDown":
            ok = consumeCompanionSelectionConfirmationIfNeeded() || performMouseButtonState(button: .left, isDown: true)
        case "mouseUp":
            ok = consumeCompanionSelectionConfirmationIfNeeded() || performMouseButtonState(button: .left, isDown: false)
        case "drag":
            ok = performMouseDrag(dx: req.dx ?? 0, dy: req.dy ?? 0)
        default:
            sendResponse(connection, statusCode: 400, body: "Unknown trackpad event: \(req.event)")
            return
        }

        let response = ["ok": ok]
        if let data = try? JSONEncoder().encode(response) {
            sendResponse(connection, statusCode: 200, body: String(data: data, encoding: .utf8) ?? "{}")
        } else {
            sendResponse(connection, statusCode: 200, body: "{\"ok\":\(ok)}")
        }
    }

    private func consumeCompanionSelectionConfirmationIfNeeded() -> Bool {
        guard isCompanionAppSwitcherActive else { return false }
        releaseCompanionAppSwitcherIfNeeded(reason: "trackpadConfirm")
        log.info("Companion app switcher confirmed from trackpad tap")
        return true
    }

    private func performMouseMove(dx: Double, dy: Double) -> Bool {
        let current = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let currentCG = CGPoint(x: current.x, y: screenHeight - current.y)
        let next = CGPoint(x: currentCG.x + dx, y: currentCG.y - dy)

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                                  mouseCursorPosition: next, mouseButton: .left) else {
            return false
        }
        event.post(tap: .cghidEventTap)
        return true
    }

    private func performMouseClick(button: CGMouseButton) -> Bool {
        let current = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let pos = CGPoint(x: current.x, y: screenHeight - current.y)

        let downType: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
        let upType: CGEventType   = button == .left ? .leftMouseUp   : .rightMouseUp

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(mouseEventSource: source, mouseType: downType,
                                 mouseCursorPosition: pos, mouseButton: button),
              let up   = CGEvent(mouseEventSource: source, mouseType: upType,
                                 mouseCursorPosition: pos, mouseButton: button) else {
            return false
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private func performMouseButtonState(button: CGMouseButton, isDown: Bool) -> Bool {
        let current = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let pos = CGPoint(x: current.x, y: screenHeight - current.y)

        let eventType: CGEventType
        switch (button, isDown) {
        case (.left, true): eventType = .leftMouseDown
        case (.left, false): eventType = .leftMouseUp
        case (.right, true): eventType = .rightMouseDown
        case (.right, false): eventType = .rightMouseUp
        default: eventType = .leftMouseDown
        }

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let event = CGEvent(
                mouseEventSource: source,
                mouseType: eventType,
                mouseCursorPosition: pos,
                mouseButton: button
              ) else {
            return false
        }
        event.post(tap: .cghidEventTap)
        return true
    }

    private func performMouseDrag(dx: Double, dy: Double) -> Bool {
        let current = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let currentCG = CGPoint(x: current.x, y: screenHeight - current.y)
        let next = CGPoint(x: currentCG.x + dx, y: currentCG.y - dy)

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let event = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: next,
                mouseButton: .left
              ) else {
            return false
        }
        event.post(tap: .cghidEventTap)
        return true
    }

    private func performMouseScroll(dx: Double, dy: Double) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel,
                                  wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx),
                                  wheel3: 0) else {
            return false
        }
        event.post(tap: CGEventTapLocation.cghidEventTap)
        return true
    }

    private func performCompanionKeyPress(keyCode: UInt16, modifiers: CGEventFlags = []) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            log.error("Companion key press failed to create events", detail: "keyCode=\(keyCode)")
            return false
        }

        keyDown.flags = modifiers
        keyUp.flags = modifiers
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        log.info("Companion key press sent", detail: "keyCode=\(keyCode) modifiers=\(modifiers.rawValue)")
        return true
    }

    private func performRepeatedCompanionKeyPress(
        keyCode: UInt16,
        modifiers: CGEventFlags = [],
        count: Int
    ) -> Bool {
        guard count > 0 else { return false }

        for _ in 0..<count {
            guard performCompanionKeyPress(keyCode: keyCode, modifiers: modifiers) else {
                return false
            }
        }

        return true
    }

    private func performCompanionShortcutKeyPress(
        keyCode: UInt16,
        modifiers: CGEventFlags = []
    ) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            log.error("Companion shortcut key press failed to create source", detail: "keyCode=\(keyCode)")
            return false
        }

        let modifierEvents = modifierKeyEvents(for: modifiers, source: source)

        for event in modifierEvents.down {
            event.post(tap: .cghidEventTap)
        }

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            log.error("Companion shortcut key press failed to create events", detail: "keyCode=\(keyCode)")
            for event in modifierEvents.up {
                event.post(tap: .cghidEventTap)
            }
            return false
        }

        keyDown.flags = modifiers
        keyUp.flags = modifiers
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        for event in modifierEvents.up {
            event.post(tap: .cghidEventTap)
        }

        log.info("Companion shortcut key press sent", detail: "keyCode=\(keyCode) modifiers=\(modifiers.rawValue)")
        return true
    }

    private func performRepeatedCompanionShortcutKeyPress(
        keyCode: UInt16,
        modifiers: CGEventFlags = [],
        count: Int
    ) -> Bool {
        guard count > 0 else { return false }

        for _ in 0..<count {
            guard performCompanionShortcutKeyPress(keyCode: keyCode, modifiers: modifiers) else {
                return false
            }
        }

        return true
    }

    private func modifierKeyEvents(
        for modifiers: CGEventFlags,
        source: CGEventSource
    ) -> (down: [CGEvent], up: [CGEvent]) {
        let modifierKeyCodes: [(flag: CGEventFlags, keyCode: UInt16)] = [
            (.maskCommand, 55),
            (.maskShift, 56),
            (.maskAlternate, 58),
            (.maskControl, 59),
        ]

        let active = modifierKeyCodes.filter { modifiers.contains($0.flag) }
        let down = active.compactMap { item in
            let event = CGEvent(keyboardEventSource: source, virtualKey: item.keyCode, keyDown: true)
            event?.flags = modifiers
            return event
        }
        let up = active.reversed().compactMap { item in
            let event = CGEvent(keyboardEventSource: source, virtualKey: item.keyCode, keyDown: false)
            event?.flags = modifiers
            return event
        }

        return (down, up)
    }

    private func performFrontmostWindowSwitch(next: Bool) -> Bool {
        let modifiers: CGEventFlags = next ? .maskCommand : [.maskCommand, .maskShift]
        let succeeded = performCompanionShortcutKeyPress(keyCode: 50, modifiers: modifiers)

        if succeeded {
            log.info(
                "Companion window switch sent via native shortcut",
                detail: "direction=\(next ? "next" : "previous")"
            )
        }

        return succeeded
    }

    private func frontmostWindows(for appElement: AXUIElement) -> [AXUIElement]? {
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            return nil
        }

        return windows
    }

    private func focusedWindow(in appElement: AXUIElement) -> AXUIElement? {
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
           let windowRef {
            return windowRef as! AXUIElement
        }

        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &windowRef) == .success,
           let windowRef {
            return windowRef as! AXUIElement
        }

        return frontmostWindows(for: appElement)?.first
    }

    private func performFrontmostTabSwitch(next: Bool) -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier?.lowercased() else {
            log.warning("Tab switch skipped because no frontmost app was available")
            return false
        }

        let bracketDrivenBundles: Set<String> = [
            "com.apple.finder",
            "com.apple.safari",
            "com.google.chrome",
            "com.google.chrome.canary",
            "com.brave.browser",
            "com.vivaldi.vivaldi",
            "com.microsoft.edgemac",
            "company.thebrowser.browser",
            "org.mozilla.firefox",
            "org.mozilla.nightly",
            "com.googlecode.iterm2",
            "com.apple.terminal",
            "dev.warp.warp-stable",
            "com.github.wez.wezterm",
            "com.mitchellh.ghostty",
            "com.todesktop.230313mzl4w4u92",
        ]
        let controlTabBundles: Set<String> = [
            "com.microsoft.vscode",
            "com.visualstudio.code.oss",
            "com.cursor.cursor",
            "com.zed.zed",
        ]

        if bracketDrivenBundles.contains(bundleId) {
            let keyCode: UInt16 = next ? 30 : 33
            return performCompanionShortcutKeyPress(keyCode: keyCode, modifiers: [.maskCommand, .maskShift])
        }

        if controlTabBundles.contains(bundleId) {
            return performCompanionShortcutKeyPress(
                keyCode: 48,
                modifiers: next ? .maskControl : [.maskControl, .maskShift]
            )
        }

        log.warning(
            "Tab switch is unsupported for frontmost app",
            detail: "\(bundleId) (\(frontApp.localizedName ?? "Unknown"))"
        )
        return false
    }

    private func performFrontmostAppSwitch(next: Bool) -> Bool {
        guard let source = beginCompanionAppSwitcherIfNeeded() else {
            return false
        }

        if !next {
            guard postModifierKey(keyCode: 56, isDown: true, flags: [.maskCommand, .maskShift], source: source) else {
                releaseCompanionAppSwitcherIfNeeded(reason: "shiftDownFailed")
                return false
            }
        }

        let modifiers: CGEventFlags = next ? .maskCommand : [.maskCommand, .maskShift]
        let succeeded = performCompanionFlaggedKeyPress(keyCode: 48, modifiers: modifiers, source: source)

        if !next {
            _ = postModifierKey(keyCode: 56, isDown: false, flags: .maskCommand, source: source)
        }

        if succeeded {
            scheduleCompanionAppSwitcherRelease()
            log.info(
                "Companion app switch step sent via held switcher",
                detail: "direction=\(next ? "next" : "previous")"
            )
        } else {
            releaseCompanionAppSwitcherIfNeeded(reason: "stepFailed")
        }

        return succeeded
    }

    private func performSpaceSwitch(offset: Int) -> Bool {
        guard offset != 0 else { return false }

        let keyCode = offset > 0 ? 124 : 123
        let count = abs(offset)

        for _ in 0..<count {
            let script = """
            tell application "System Events"
                key code \(keyCode) using control down
            end tell
            """

            if !runAppleScript(script) {
                log.warning("Space switch AppleScript failed; falling back to synthetic shortcut", detail: "offset=\(offset)")
                return performRepeatedCompanionShortcutKeyPress(
                    keyCode: UInt16(keyCode),
                    modifiers: .maskControl,
                    count: count
                )
            }
        }

        return true
    }

    private func beginCompanionAppSwitcherIfNeeded() -> CGEventSource? {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let source else {
            log.error("Companion app switch failed to create source")
            return nil
        }

        if !isCompanionAppSwitcherActive {
            guard postModifierKey(keyCode: 55, isDown: true, flags: .maskCommand, source: source) else {
                log.error("Companion app switch failed to hold Command")
                return nil
            }
            isCompanionAppSwitcherActive = true
        }

        companionAppSwitcherReleaseTask?.cancel()
        companionAppSwitcherReleaseTask = nil
        return source
    }

    private func scheduleCompanionAppSwitcherRelease() {
        companionAppSwitcherReleaseTask?.cancel()
        companionAppSwitcherReleaseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            await self?.releaseCompanionAppSwitcherIfNeeded(reason: "timeout")
        }
    }

    private func releaseCompanionAppSwitcherIfNeeded(reason: String) {
        companionAppSwitcherReleaseTask?.cancel()
        companionAppSwitcherReleaseTask = nil

        guard isCompanionAppSwitcherActive else { return }
        isCompanionAppSwitcherActive = false

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            log.warning("Companion app switcher release skipped because no source was available")
            return
        }

        if postModifierKey(keyCode: 55, isDown: false, flags: [], source: source) {
            log.info("Companion app switcher released", detail: reason)
        } else {
            log.warning("Companion app switcher release failed", detail: reason)
        }
    }

    private func performCompanionFlaggedKeyPress(
        keyCode: UInt16,
        modifiers: CGEventFlags,
        source: CGEventSource
    ) -> Bool {
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            log.error("Companion flagged key press failed to create events", detail: "keyCode=\(keyCode)")
            return false
        }

        keyDown.flags = modifiers
        keyUp.flags = modifiers
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func postModifierKey(
        keyCode: UInt16,
        isDown: Bool,
        flags: CGEventFlags,
        source: CGEventSource
    ) -> Bool {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else {
            return false
        }

        event.flags = flags
        event.post(tap: .cghidEventTap)
        return true
    }

    private func bringTalkieToFront() {
        NSApp.activate(ignoringOtherApps: true)
        if let mainWindow = NSApp.windows.first(where: { $0.canBecomeMain }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }

    private func openITermForCompanion() async -> Bool {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") != nil else {
            return false
        }

        let script = """
        tell application id "com.googlecode.iterm2"
            activate
            try
                create window with default profile
            on error
                try
                    tell current window to create tab with default profile
                on error
                    activate
                end try
            end try
        end tell
        """

        return runAppleScript(script, failurePrefix: "Companion iTerm launch AppleScript failed")
    }

    private func runAppleScript(
        _ script: String,
        failurePrefix: String = "Companion AppleScript failed"
    ) -> Bool {
        guard let appleScript = NSAppleScript(source: script) else {
            log.warning("\(failurePrefix): could not create script")
            return false
        }

        var errorInfo: NSDictionary?
        appleScript.executeAndReturnError(&errorInfo)

        if let errorInfo {
            log.warning("\(failurePrefix): \(errorInfo)")
            return false
        }

        return true
    }

    // MARK: - Screenshot Handlers

    private func handleListClaudeWindows(_ connection: NWConnection) async {
        let windowsJSON: Data? = await callAgent(label: "listClaudeWindows") { service, reply in
            service.listClaudeWindows { data in
                reply(data)
            }
        }

        guard let windowsJSON else {
            sendErrorResponse(connection, statusCode: 503, error: TalkieServerError.talkieLiveNotConnected)
            return
        }

        if let windows = try? JSONSerialization.jsonObject(with: windowsJSON),
           let wrapped = try? JSONSerialization.data(withJSONObject: ["windows": windows]) {
            sendRawJSONResponse(connection, statusCode: 200, jsonData: wrapped)
        } else {
            sendErrorResponse(connection, statusCode: 500, error: "Failed to list windows")
        }
    }

    private func handleCaptureWindow(_ connection: NWConnection, windowID: UInt32) async {
        let result: (imageData: Data?, error: String?)? = await callAgent(
            label: "captureWindow",
            timeoutSeconds: 8
        ) { service, reply in
            service.captureWindow(windowID: windowID) { imageData, error in
                reply((imageData: imageData, error: error))
            }
        }

        guard let result else {
            sendErrorResponse(connection, statusCode: 503, error: TalkieServerError.talkieLiveNotConnected)
            return
        }

        if let data = result.imageData {
            sendImageResponse(connection, data: data, contentType: "image/jpeg")
        } else {
            sendErrorResponse(connection, statusCode: 500, error: result.error ?? "Failed to capture window")
        }
    }

    private func handleCaptureMainDisplay(_ connection: NWConnection, maxDimension: Int, quality: Double) async {
        let requestedDimension = UInt32(max(maxDimension, 0))
        let requestedQuality = min(max(quality, 0.1), 1.0)

        let result: (imageData: Data?, error: String?)? = await callAgent(
            label: "captureMainDisplay",
            timeoutSeconds: 8
        ) { service, reply in
            service.captureMainDisplay(maxDimension: requestedDimension, quality: requestedQuality) { imageData, error in
                reply((imageData: imageData, error: error))
            }
        }

        guard let result else {
            sendErrorResponse(connection, statusCode: 503, error: TalkieServerError.talkieLiveNotConnected)
            return
        }

        if let data = result.imageData {
            sendImageResponse(connection, data: data, contentType: "image/jpeg")
        } else {
            sendErrorResponse(connection, statusCode: 500, error: result.error ?? "Failed to capture display")
        }
    }

    private func handleTrayImage(_ connection: NWConnection, path: String) async {
        // Extract UUID from /tray/<uuid>.png
        let filename = String(path.dropFirst("/tray/".count))
        let uuidString = filename.replacingOccurrences(of: ".png", with: "")
        guard let uuid = UUID(uuidString: uuidString) else {
            sendResponse(connection, statusCode: 400, body: "Invalid UUID")
            return
        }

        guard let item = ScreenshotTray.shared.items.first(where: { $0.id == uuid }),
              let data = item.loadData() else {
            sendResponse(connection, statusCode: 404, body: "Tray item not found")
            return
        }

        sendImageResponse(connection, data: data, contentType: "image/png")
    }

    private func handleCaptureTerminals(_ connection: NWConnection) async {
        let result: (screenshotsJSON: Data?, error: String?)? = await callAgent(
            label: "captureTerminalWindows",
            timeoutSeconds: 8
        ) { service, reply in
            service.captureTerminalWindows { screenshotsJSON, error in
                reply((screenshotsJSON: screenshotsJSON, error: error))
            }
        }

        guard let result else {
            sendErrorResponse(connection, statusCode: 503, error: TalkieServerError.talkieLiveNotConnected)
            return
        }

        if let data = result.screenshotsJSON {
            sendRawJSONResponse(connection, statusCode: 200, jsonData: data)
        } else {
            sendErrorResponse(connection, statusCode: 500, error: result.error ?? "Failed to capture terminals")
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

    // MARK: - /doctor

    private struct DoctorResponse: Encodable {
        struct ProcessPermissions: Encodable {
            let microphone: String
            let accessibility: String
            let inputMonitoring: String
            let screenRecording: String
        }
        struct Permissions: Encodable {
            let talkie: ProcessPermissions
            let agent: ProcessPermissions
        }
        struct Services: Encodable {
            let talkie: String
            let agent: String
            let sync: String
            let talkieServer: String
        }
        struct Prerequisites: Encodable {
            let bun: Bool
            let serverSource: Bool
            let dependencies: Bool
            let tailscale: Bool
        }
        struct ProTools: Encodable {
            let active: Bool
            let prerequisites: Prerequisites
        }

        let version: String
        let permissions: Permissions
        let services: Services
        let proTools: ProTools
    }

    private func handleDoctor(_ connection: NWConnection) async {
        // Talkie.app's own permissions (passive refresh, never prompts).
        PermissionsManager.shared.refreshPassivePermissions()
        let pm = PermissionsManager.shared
        let talkieInput = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted

        // TalkieAgent permissions via XPC (unknown if disconnected).
        let agentPerms = await fetchAgentPermissionsSnapshot()

        // Service states.
        let sm = ServiceManager.shared
        let serverStatus = await fetchServerStatus()

        // Pro Tools + prerequisites.
        let settings = SettingsManager.shared
        let prereqs = await BridgeManager.shared.checkPrerequisites()

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        let resp = DoctorResponse(
            version: version,
            permissions: .init(
                talkie: .init(
                    microphone: Self.permissionString(pm.microphoneStatus),
                    accessibility: Self.permissionString(pm.accessibilityStatus),
                    inputMonitoring: talkieInput ? "granted" : "denied",
                    screenRecording: Self.permissionString(pm.screenRecordingStatus)
                ),
                agent: .init(
                    microphone: Self.agentPermString(agentPerms?.microphone),
                    accessibility: Self.agentPermString(agentPerms?.accessibility),
                    inputMonitoring: Self.agentPermString(agentPerms?.inputMonitoring),
                    screenRecording: Self.agentPermString(agentPerms?.screenRecording)
                )
            ),
            services: .init(
                talkie: "running",
                agent: sm.live.isRunning ? "running" : "stopped",
                sync: sm.sync.isRunning ? "running" : "stopped",
                talkieServer: Self.serverStateString(serverStatus?.processState)
            ),
            proTools: .init(
                active: settings.isProToolsActive,
                prerequisites: .init(
                    bun: prereqs.bunInstalled,
                    serverSource: prereqs.serverSourceExists,
                    dependencies: prereqs.dependenciesInstalled,
                    tailscale: prereqs.tailscaleInstalled
                )
            )
        )
        sendJSONResponse(connection, statusCode: 200, body: resp)
    }

    private struct AgentPermSnapshot {
        let microphone: Bool
        let accessibility: Bool
        let screenRecording: Bool
        let inputMonitoring: Bool
    }

    private func fetchAgentPermissionsSnapshot() async -> AgentPermSnapshot? {
        async let triple: (Bool, Bool, Bool)? = callAgent(label: "getPermissions") { service, reply in
            service.getPermissions { mic, ax, sr in
                reply((mic, ax, sr))
            }
        }
        async let input: Bool? = callAgent(label: "getInputMonitoringPermission") { service, reply in
            service.getInputMonitoringPermission { granted in
                reply(granted)
            }
        }
        guard let t = await triple else { return nil }
        let im = await input ?? false
        return AgentPermSnapshot(microphone: t.0, accessibility: t.1, screenRecording: t.2, inputMonitoring: im)
    }

    private func fetchServerStatus() async -> TalkieAgentServerStatus? {
        let data: Data? = await callAgent(label: "getTalkieAgentServerStatus") { service, reply in
            service.getTalkieAgentServerStatus { data in
                reply(data)
            }
        }
        guard let data else { return nil }
        return try? JSONDecoder().decode(TalkieAgentServerStatus.self, from: data)
    }

    /// Fresh XPC call with timeout. Errors or a slow/missing agent resolve to nil
    /// instead of hanging the HTTP handler.
    private func callAgent<T>(
        label: String = "xpc",
        timeoutSeconds: Double = 2.5,
        _ call: @escaping (TalkieAgentXPCServiceProtocol, @escaping (T?) -> Void) -> Void
    ) async -> T? {
        let xpcLog = Log(.xpc)
        let serviceName = TalkieHelper.agent.xpcServiceName(
            for: ServiceManager.shared.effectiveHelperEnvironment
        )
        let connection = NSXPCConnection(machServiceName: serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: TalkieAgentXPCServiceProtocol.self)
        connection.resume()

        let guardFlag = OneShotFlag()
        let result: T? = await withCheckedContinuation { continuation in
            let resumeOnce: (T?) -> Void = { value in
                if guardFlag.setOnce() {
                    continuation.resume(returning: value)
                }
            }

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                xpcLog.warning("\(label) XPC error: \(error)")
                resumeOnce(nil)
            } as? TalkieAgentXPCServiceProtocol

            guard let proxy else {
                xpcLog.warning("\(label) could not acquire XPC proxy")
                resumeOnce(nil)
                return
            }
            call(proxy) { reply in
                resumeOnce(reply)
            }

            Task {
                try? await Task.sleep(for: .milliseconds(Int(timeoutSeconds * 1_000)))
                resumeOnce(nil)
            }
        }

        connection.invalidate()
        return result
    }

    /// Returns true the first time setOnce() is called; false thereafter.
    private final class OneShotFlag {
        private let lock = NSLock()
        private var fired = false
        func setOnce() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if fired { return false }
            fired = true
            return true
        }
    }

    private static func permissionString(_ s: PermissionStatus) -> String {
        switch s {
        case .granted: return "granted"
        case .denied: return "denied"
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .unknown: return "unknown"
        }
    }

    private static func agentPermString(_ granted: Bool?) -> String {
        guard let granted else { return "unknown" }
        return granted ? "granted" : "denied"
    }

    private static func serverStateString(_ state: TalkieAgentServerStatus.ProcessState?) -> String {
        guard let state else { return "unknown" }
        return state.rawValue
    }

    private static func loadTrustedLocalClients() -> [String: TrustedLocalClientRecord] {
        guard
            let data = UserDefaults.standard.data(forKey: LocalClientDefaultsKey.trustedClients),
            let clients = try? JSONDecoder().decode([TrustedLocalClientRecord].self, from: data)
        else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0) })
    }

    private func persistTrustedLocalClients() {
        let clients = trustedLocalClients.values.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        guard let data = try? JSONEncoder().encode(clients) else { return }
        UserDefaults.standard.set(data, forKey: LocalClientDefaultsKey.trustedClients)
    }

    private static func localClientPublicKey(from base64Value: String) -> P256.Signing.PublicKey? {
        guard let keyData = Data(base64Encoded: base64Value) else { return nil }
        if let key = try? P256.Signing.PublicKey(x963Representation: keyData) {
            return key
        }
        if let key = try? P256.Signing.PublicKey(derRepresentation: keyData) {
            return key
        }
        return nil
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func fingerprint(forPublicKeyBase64 value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let compact = String(hex.prefix(16)).uppercased()
        return compact.chunked(into: 4).joined(separator: "-")
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let lhsData = Array(lhs.utf8)
        let rhsData = Array(rhs.utf8)
        guard lhsData.count == rhsData.count else { return false }
        var diff: UInt8 = 0
        for index in lhsData.indices {
            diff |= lhsData[index] ^ rhsData[index]
        }
        return diff == 0
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

private extension String {
    func chunked(into size: Int) -> [String] {
        guard size > 0, !isEmpty else { return [self] }
        var chunks: [String] = []
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[index..<next]))
            index = next
        }
        return chunks
    }
}
