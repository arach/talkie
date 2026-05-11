//
//  BridgeClient.swift
//  Talkie iOS
//
//  HTTP client for communicating with TalkieBridge on Mac
//

import Foundation
import CryptoKit

/// Client for communicating with TalkieBridge server
actor BridgeClient {
    private var baseURL: URL?
    private var sharedKey: SymmetricKey?  // Legacy - kept for backwards compat
    private var encryptionKey: SymmetricKey?

    // HMAC Authentication
    private var deviceId: String?
    private var authKey: SymmetricKey?
    private var clockOffset: TimeInterval = 0

    // MARK: - Configuration

    func configure(hostname: String, port: Int) {
        self.baseURL = URL(string: "http://\(hostname):\(port)")
    }

    func setSharedKey(_ key: SymmetricKey) {
        self.sharedKey = key
        self.encryptionKey = key
    }

    /// Configure authentication credentials from pairing
    func configureAuth(deviceId: String, sharedSecret: SharedSecret) {
        let encryptionKey = sharedSecret.deriveEncryptionKey()
        self.deviceId = deviceId
        self.authKey = sharedSecret.deriveAuthKey()
        self.sharedKey = encryptionKey
        self.encryptionKey = encryptionKey
    }

    /// Clear all authentication state (for unpair)
    func clearAuth() {
        self.deviceId = nil
        self.authKey = nil
        self.sharedKey = nil
        self.encryptionKey = nil
        self.baseURL = nil
        self.clockOffset = 0
    }

    var isConfigured: Bool {
        baseURL != nil
    }

    var isAuthenticated: Bool {
        deviceId != nil && authKey != nil
    }

    /// Current server time accounting for clock offset
    private var serverTime: Int {
        Int(Date().timeIntervalSince1970 + clockOffset)
    }

    /// Connect to the bridge and sync clocks
    /// Call this after configureAuth() before making authenticated requests
    func connect() async throws {
        let health = try await healthUnauthenticated()
        if let serverTimeValue = health.time {
            let localTime = Date().timeIntervalSince1970
            clockOffset = Double(serverTimeValue) - localTime

            // Log significant clock drift for debugging
            if abs(clockOffset) > 5 {
                AppLogger.app.info("[BridgeClient] Clock offset with Mac: \(String(format: "%.1f", clockOffset))s")
            }
        }
    }

    /// Recalibrate clock from a server timestamp (e.g., from 401 response)
    private func recalibrateClockFrom(serverTime: Int) {
        let localTime = Date().timeIntervalSince1970
        clockOffset = Double(serverTime) - localTime
        AppLogger.app.info("[BridgeClient] Clock recalibrated, new offset: \(String(format: "%.1f", clockOffset))s")
    }

    // MARK: - API Calls

    /// Health check (unauthenticated - for clock sync)
    private func healthUnauthenticated() async throws -> HealthResponse {
        let data = try await getUnauthenticated("/health")
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    func health() async throws -> HealthResponse {
        // Health is exempt from auth, but we can still use the standard method
        let data = try await getUnauthenticated("/health")
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    func sessions(deepSync: Bool = false) async throws -> SessionsResponse {
        let path = deepSync ? "/sessions?refresh=deep" : "/sessions"
        // Use longer timeout for mobile network + Tailscale latency
        let data = try await get(path, timeout: deepSync ? 60 : 30)
        let response = try JSONDecoder().decode(SessionsResponse.self, from: data)

        // Log the full response for debugging
        if let jsonString = String(data: data, encoding: .utf8) {
            AppLogger.app.info("[Bridge] sessions() returned \(response.sessions.count) sessions - deepSync: \(deepSync)", detail: jsonString)
        }

        return response
    }

    func paths(deepSync: Bool = false) async throws -> PathsResponse {
        let path = deepSync ? "/paths?refresh=deep" : "/paths"
        // Use longer timeout for mobile network + Tailscale latency
        let data = try await get(path, timeout: deepSync ? 60 : 30)
        let response = try JSONDecoder().decode(PathsResponse.self, from: data)

        // Log the full response for debugging
        if let jsonString = String(data: data, encoding: .utf8) {
            AppLogger.app.info("[Bridge] paths() returned \(response.paths.count) paths - deepSync: \(deepSync)", detail: jsonString)
        }

        return response
    }

    func sessionMessages(id: String, limit: Int = 50) async throws -> SessionMessagesResponse {
        let data = try await get("/sessions/\(id)/messages?limit=\(limit)")
        return try JSONDecoder().decode(SessionMessagesResponse.self, from: data)
    }

    func pair(deviceId: String, publicKey: String, name: String) async throws -> PairResponse {
        let body = PairRequest(deviceId: deviceId, publicKey: publicKey, name: name)
        let data = try await post("/pair", body: body)
        return try JSONDecoder().decode(PairResponse.self, from: data)
    }

    func sendMessage(sessionId: String, text: String) async throws -> MessageResponse {
        let body = MessageRequest(message: text)
        let data = try await post("/sessions/\(sessionId)/message", body: body)
        return try JSONDecoder().decode(MessageResponse.self, from: data)
    }

    /// Send audio to be transcribed and submitted to Claude
    /// - Parameters:
    ///   - sessionId: Claude session ID
    ///   - audioData: Raw audio data (m4a format)
    /// - Returns: Response including the transcript
    func sendAudio(sessionId: String, audioData: Data) async throws -> MessageResponse {
        let body = AudioMessageRequest(
            audio: audioData.base64EncodedString(),
            format: "m4a"
        )
        let data = try await post("/sessions/\(sessionId)/message", body: body, timeout: 30)
        return try JSONDecoder().decode(MessageResponse.self, from: data)
    }

    /// Force press Enter key in a session's terminal
    /// Useful when auto-submit doesn't work
    /// Sends empty message which triggers just pressing Enter
    func forceEnter(sessionId: String) async throws -> MessageResponse {
        // Send empty message - server will just press Enter without inserting anything
        let body = MessageRequest(message: "")
        let data = try await post("/sessions/\(sessionId)/message", body: body)
        return try JSONDecoder().decode(MessageResponse.self, from: data)
    }

    // MARK: - Window & Screenshot API

    /// List all terminal windows with metadata
    func windows() async throws -> WindowsResponse {
        let data = try await get("/windows")
        return try JSONDecoder().decode(WindowsResponse.self, from: data)
    }

    func companionState(deviceId: String? = nil, deviceClass: String? = nil) async throws -> CompanionStateResponse {
        var queryItems: [URLQueryItem] = []
        if let deviceId, !deviceId.isEmpty {
            queryItems.append(URLQueryItem(name: "deviceId", value: deviceId))
        }
        if let deviceClass, !deviceClass.isEmpty {
            queryItems.append(URLQueryItem(name: "deviceClass", value: deviceClass))
        }

        let path: String
        if queryItems.isEmpty {
            path = "/companion/state"
        } else {
            var components = URLComponents()
            components.path = "/companion/state"
            components.queryItems = queryItems
            path = components.string ?? "/companion/state"
        }

        let data = try await get(path)
        return try JSONDecoder().decode(CompanionStateResponse.self, from: data)
    }

    func acknowledgeSecurityEvent(id: String) async throws {
        _ = try await post("/security/events/\(id)/ack", body: EmptyBridgeRequest())
    }

    func companionTrigger(shortcutId: String) async throws -> CompanionTriggerResponse {
        let data = try await post("/companion/trigger", body: CompanionTriggerRequest(shortcutId: shortcutId))
        return try JSONDecoder().decode(CompanionTriggerResponse.self, from: data)
    }

    func companionActivateApp(
        processIdentifier: Int32,
        bundleIdentifier: String?
    ) async throws -> CompanionTriggerResponse {
        struct CompanionActivateAppRequest: Encodable {
            let processIdentifier: Int32
            let bundleIdentifier: String?
        }

        let request = CompanionActivateAppRequest(
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier
        )
        let data = try await post("/companion/activate-app", body: request)
        return try JSONDecoder().decode(CompanionTriggerResponse.self, from: data)
    }

    func companionTrackpad(event: TrackpadEvent, dx: Double = 0, dy: Double = 0) async throws {
        struct TrackpadRequest: Encodable {
            let event: String
            let dx: Double
            let dy: Double
        }
        _ = try await post("/companion/trackpad", body: TrackpadRequest(event: event.rawValue, dx: dx, dy: dy))
    }

    enum TrackpadEvent: String {
        case move, click, rightClick, scroll, mouseDown, mouseUp, drag
    }

    func companionPasteImage(
        imageData: Data,
        mimeType: String,
        autoPaste: Bool = true
    ) async throws -> CompanionTriggerResponse {
        let request = CompanionPasteImageRequest(
            imageBase64: imageData.base64EncodedString(),
            mimeType: mimeType,
            autoPaste: autoPaste
        )
        let data = try await post("/companion/paste-image", body: request, timeout: 30)
        return try JSONDecoder().decode(CompanionTriggerResponse.self, from: data)
    }

    func screenStreamRequest(
        fps: Int = 2,
        maxDimension: Int = 1400,
        quality: Double = 0.6
    ) async throws -> URLRequest {
        guard let baseURL else {
            throw BridgeError.notConfigured
        }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw BridgeError.invalidResponse
        }

        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/companion/screen"
        components.queryItems = [
            URLQueryItem(name: "fps", value: "\(max(1, fps))"),
            URLQueryItem(name: "maxDimension", value: "\(max(320, maxDimension))"),
            URLQueryItem(name: "quality", value: String(quality)),
        ]

        guard let url = components.url else {
            throw BridgeError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        signRequest(&request)
        return request
    }

    func companionEventsRequest(
        deviceId: String? = nil,
        deviceClass: String? = nil
    ) async throws -> URLRequest {
        guard let baseURL else {
            throw BridgeError.notConfigured
        }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw BridgeError.invalidResponse
        }

        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/companion/events"

        var queryItems: [URLQueryItem] = []
        if let deviceId, !deviceId.isEmpty {
            queryItems.append(URLQueryItem(name: "deviceId", value: deviceId))
        }
        if let deviceClass, !deviceClass.isEmpty {
            queryItems.append(URLQueryItem(name: "deviceClass", value: deviceClass))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw BridgeError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        signRequest(&request)
        return request
    }

    func updateDeviceSetupState(_ body: DeviceSetupStateRequest) async throws {
        _ = try await post("/devices/setup-state", body: body)
    }

    /// Get screenshot of a specific window (returns JPEG Data)
    func windowScreenshot(windowId: UInt32) async throws -> Data {
        return try await get("/windows/\(windowId)/screenshot")
    }

    /// Get all terminal window screenshots with metadata
    /// Uses longer timeout since response includes base64-encoded images
    func windowCaptures() async throws -> WindowCapturesResponse {
        let data = try await get("/windows/captures", timeout: 30)
        return try JSONDecoder().decode(WindowCapturesResponse.self, from: data)
    }

    // MARK: - Content Ingestion

    func ingestContent(body: IngestRequest) async throws -> IngestResponse {
        let data = try await post("/ingest", body: body, timeout: 30)
        return try JSONDecoder().decode(IngestResponse.self, from: data)
    }

    // MARK: - Text-to-Speech

    func requestTTS(text: String, voice: String = "echo", provider: String = "openai") async throws -> TTSResponse {
        let timeout: TimeInterval = provider == "local" ? 120 : 60
        let data = try await post("/tts", body: TTSRequest(text: text, voice: voice, provider: provider), timeout: timeout)
        return try JSONDecoder().decode(TTSResponse.self, from: data)
    }

    // MARK: - Memo Attachments

    func sendMemoAttachments(
        memoId: String,
        body: MemoAttachmentUploadRequest
    ) async throws -> MemoAttachmentUploadResponse {
        let data = try await post("/memos/\(memoId)/attachments", body: body, timeout: 60)
        return try JSONDecoder().decode(MemoAttachmentUploadResponse.self, from: data)
    }

    // MARK: - Headless Claude (AI Agent)

    /// Send a message to a Claude Code session in headless mode.
    /// Returns the assistant's text response.
    func headless(message: String, sessionId: String? = nil, projectDir: String? = nil) async throws -> HeadlessResponse {
        let body = HeadlessRequest(sessionId: sessionId, message: message, projectDir: projectDir)
        let data = try await post("/headless", body: body, timeout: 120)
        return try JSONDecoder().decode(HeadlessResponse.self, from: data)
    }

    /// Result from a streaming headless call, including the Claude session ID for follow-ups.
    struct HeadlessStreamResult: Sendable {
        let sessionId: String?
    }

    /// Stream a headless Claude response via SSE.
    /// Calls `onChunk` with each text fragment as it arrives.
    /// Returns the Claude session ID for multi-turn follow-ups.
    func headlessStream(
        message: String,
        sessionId: String? = nil,
        projectDir: String? = nil,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> HeadlessStreamResult {
        guard let baseURL = baseURL else {
            throw BridgeError.notConfigured
        }
        guard let url = URL(string: "/headless", relativeTo: baseURL) else {
            throw BridgeError.invalidResponse
        }

        let body = HeadlessRequest(sessionId: sessionId, message: message, projectDir: projectDir, stream: true)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try JSONEncoder().encode(body)

        signRequest(&request)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw BridgeError.httpError(statusCode)
        }

        // Parse SSE stream
        var capturedSessionId: String?

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))

            if payload == "[DONE]" { break }

            guard let jsonData = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(SSEChunk.self, from: jsonData) else {
                continue
            }

            // Capture session_id from session metadata event
            if chunk.type == "session", let sid = chunk.sessionId {
                capturedSessionId = sid
                continue
            }

            if let content = chunk.content, !content.isEmpty {
                onChunk(content)
            }
        }

        return HeadlessStreamResult(sessionId: capturedSessionId)
    }

    // MARK: - Remote CLI

    /// Execute a `talkie` or `talkie-dev` CLI command on the paired Mac.
    func executeCLI(command: String, timeout: Int = 30000) async throws -> CLIResponse {
        let body = CLIRequest(command: command, timeout: timeout)
        let data = try await post("/cli", body: body, timeout: TimeInterval(timeout / 1000 + 5))
        return try JSONDecoder().decode(CLIResponse.self, from: data)
    }

    // MARK: - Scout Handoff

    struct ScoutHandoffRequest: Codable {
        let memoId: String
        let memoTitle: String
        let memoTranscript: String
        let turns: [ScoutHandoffTurn]
        let claudeSessionId: String?
    }

    struct ScoutHandoffTurn: Codable {
        let role: String
        let content: String
        let timestamp: String
    }

    struct ScoutHandoffResponse: Codable {
        let success: Bool
        let conversationId: String?
        let messageCount: Int?
        let error: String?
    }

    /// Hand off an agent conversation to Scout for multi-turn continuation.
    func handoffToScout(
        memoId: String,
        memoTitle: String,
        memoTranscript: String,
        turns: [AgentTurn],
        claudeSessionId: String?
    ) async throws -> ScoutHandoffResponse {
        let handoffTurns = turns.map { turn in
            ScoutHandoffTurn(
                role: turn.role,
                content: turn.content,
                timestamp: ISO8601DateFormatter().string(from: turn.timestamp)
            )
        }
        let body = ScoutHandoffRequest(
            memoId: memoId,
            memoTitle: memoTitle,
            memoTranscript: memoTranscript,
            turns: handoffTurns,
            claudeSessionId: claudeSessionId
        )
        let data = try await post("/handoff/scout", body: body, timeout: 15)
        return try JSONDecoder().decode(ScoutHandoffResponse.self, from: data)
    }

    // MARK: - Compose

    func composeRevision(
        body: ComposeRevisionRequest
    ) async throws -> ComposeRevisionEnvelope {
        let data = try await post("/compose/revision", body: body, timeout: 60)
        return try JSONDecoder().decode(ComposeRevisionEnvelope.self, from: data)
    }

    func composeCommand(
        body: ComposeCommandRequest
    ) async throws -> ComposeCommandEnvelope {
        let data = try await post("/compose/command", body: body, timeout: 90)
        return try JSONDecoder().decode(ComposeCommandEnvelope.self, from: data)
    }

    func composeDirectOptions() async throws -> ComposeDirectOptionsResult {
        let data = try await post("/compose/options", body: EmptyBridgeRequest())
        let envelope = try JSONDecoder().decode(ComposeDirectOptionsEnvelope.self, from: data)

        guard envelope.ok, let result = envelope.result else {
            throw BridgeError.messageFailed(envelope.error ?? "Could not load direct Compose options")
        }

        return result
    }

    func composeBorrowedProvider(
        providerId: String? = nil,
        modelId: String? = nil
    ) async throws -> ComposeBorrowedProvider {
        let data = try await post(
            "/compose/provider",
            body: ComposeBorrowedProviderRequest(providerId: providerId, modelId: modelId)
        )
        let envelope = try JSONDecoder().decode(ComposeBorrowedProviderEnvelope.self, from: data)

        guard envelope.ok else {
            throw BridgeError.messageFailed(envelope.error ?? "Could not borrow provider credentials")
        }

        guard let encrypted = envelope.encrypted else {
            throw BridgeError.invalidResponse
        }

        return try decryptPayload(encrypted, as: ComposeBorrowedProvider.self)
    }

    // MARK: - HTTP Methods

    /// Unauthenticated GET (for exempt endpoints like /health)
    private func getUnauthenticated(_ path: String) async throws -> Data {
        guard let baseURL = baseURL else {
            throw BridgeError.notConfigured
        }

        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw BridgeError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30  // Longer timeout for mobile + Tailscale

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BridgeError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw BridgeError.httpError(httpResponse.statusCode)
        }

        return data
    }

    /// Authenticated GET with HMAC signing
    private func get(_ path: String, allowRetry: Bool = true, timeout: TimeInterval = 30) async throws -> Data {
        guard let baseURL = baseURL else {
            throw BridgeError.notConfigured
        }

        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw BridgeError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout

        // Sign request if authenticated
        signRequest(&request)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BridgeError.invalidResponse
        }

        // Handle 401 with clock recalibration
        if httpResponse.statusCode == 401 && allowRetry {
            if let serverTime = try? extractServerTime(from: data) {
                recalibrateClockFrom(serverTime: serverTime)
                return try await get(path, allowRetry: false, timeout: timeout)  // Retry once
            }
        }

        guard httpResponse.statusCode == 200 else {
            throw BridgeError.httpError(httpResponse.statusCode)
        }

        return data
    }

    /// Authenticated POST with HMAC signing
    private func post<T: Encodable>(_ path: String, body: T, timeout: TimeInterval = 30, allowRetry: Bool = true) async throws -> Data {
        guard let baseURL = baseURL else {
            throw BridgeError.notConfigured
        }

        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw BridgeError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder().encode(body)

        // Sign request if authenticated
        signRequest(&request)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BridgeError.invalidResponse
        }

        // Handle 401 with clock recalibration
        if httpResponse.statusCode == 401 && allowRetry {
            if let serverTime = try? extractServerTime(from: data) {
                recalibrateClockFrom(serverTime: serverTime)
                return try await post(path, body: body, timeout: timeout, allowRetry: false)
            }
        }

        guard httpResponse.statusCode == 200 else {
            throw BridgeError.httpError(httpResponse.statusCode)
        }

        return data
    }

    // MARK: - Signing Helpers

    /// Sign a request with HMAC if credentials are available
    private func signRequest(_ request: inout URLRequest) {
        guard let deviceId = deviceId, let authKey = authKey else {
            // Not authenticated - request will go unsigned
            return
        }

        let signer = RequestSigner(deviceId: deviceId, authKey: authKey)
        signer.sign(&request, serverTime: serverTime)
    }

    /// Extract serverTime from a 401 error response for clock recalibration
    private func extractServerTime(from data: Data) throws -> Int? {
        struct ErrorResponse: Codable {
            let error: String?
            let serverTime: Int?
        }
        let response = try JSONDecoder().decode(ErrorResponse.self, from: data)
        return response.serverTime
    }

    private func decryptPayload<T: Decodable>(
        _ payload: EncryptedBridgePayload,
        as type: T.Type
    ) throws -> T {
        guard let encryptionKey else {
            throw BridgeError.notConfigured
        }

        guard let combined = Data(base64Encoded: payload.ciphertext) else {
            throw BridgeError.invalidResponse
        }

        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)
        return try JSONDecoder().decode(type, from: decryptedData)
    }
}

// MARK: - Request/Response Types

struct HealthResponse: Codable {
    let status: String
    let version: String
    let hostname: String
    let port: Int
    let time: Int?  // Unix epoch seconds for clock sync
}

struct SessionsResponse: Codable {
    let sessions: [ClaudeSession]
    let meta: SessionsMeta?
}

struct DeviceSetupStateRequest: Codable, Equatable {
    let followComputerShortcutMode: Bool
    let companionSurfaceActive: Bool
    let terminalImported: Bool
    let terminalHost: String?
}

struct CompanionTriggerRequest: Codable {
    let shortcutId: String
}

struct CompanionTriggerResponse: Codable {
    let ok: Bool
    let handledShortcutId: String?
    let message: String?
    let error: String?
    let runtimeState: CompanionShortcutRuntimeState?
}

struct SessionsMeta: Codable {
    let count: Int
    let fromCache: Bool
    let cacheAgeMs: Int
    let syncedAt: String?
}

// MARK: - Paths (Grouped Sessions)

struct PathsResponse: Codable {
    let paths: [ProjectPath]
    let meta: PathsMeta
}

struct PathsMeta: Codable {
    let pathCount: Int
    let sessionCount: Int
    let fromCache: Bool
    let cacheAgeMs: Int
    let syncedAt: String?
}

struct ProjectPath: Codable, Identifiable {
    let path: String              // Full path (e.g., "/Users/example/dev/talkie")
    let name: String              // Display name (e.g., "talkie")
    let folderName: String        // Encoded path for lookup
    let sessions: [PathSession]   // Sessions for this project
    let lastSeen: String
    let isLive: Bool

    var id: String { path }
}

struct PathSession: Codable, Identifiable {
    let id: String                // Claude session UUID
    let lastSeen: String
    let messageCount: Int
    let isLive: Bool
    let lastMessage: String?      // Preview of most recent message
    let title: String?            // Session title/name if available
}

struct ClaudeSession: Codable, Identifiable {
    let id: String              // Claude session UUID
    let folderName: String?     // Encoded path (e.g., "-Users-arach-dev-talkie")
    let project: String         // Display name (e.g., "talkie")
    let projectPath: String     // Full path (e.g., "/Users/example/dev/talkie")
    let isLive: Bool
    let lastSeen: String
    let messageCount: Int
}

struct SessionMessagesResponse: Codable {
    let session: SessionInfo
    let messages: [SessionMessage]
}

struct SessionInfo: Codable {
    let id: String
    let project: String
    let projectPath: String
    let isLive: Bool
    let lastSeen: String
}

struct SessionMessage: Codable, Identifiable {
    var id: String { "\(timestamp)-\(role)" }
    let role: String
    let content: String
    let timestamp: String
    let toolCalls: [ToolCall]?
}

struct ToolCall: Codable {
    let name: String
    let input: String?
    let output: String?
}

struct PairRequest: Codable {
    let deviceId: String
    let publicKey: String
    let name: String
}

struct PairResponse: Codable {
    let status: String
    let message: String?
}

struct MessageRequest: Codable {
    let message: String
}

struct CompanionPasteImageRequest: Codable {
    let imageBase64: String
    let mimeType: String
    let autoPaste: Bool
}


struct AudioMessageRequest: Codable {
    let audio: String  // Base64 encoded audio
    let format: String  // "m4a", "wav", etc.
}

struct MemoAttachmentUploadItem: Codable {
    let id: String
    let originalName: String
    let addedAt: String
    let fileSizeBytes: Int64
    let pixelWidth: Int?
    let pixelHeight: Int?
    let recordingOffsetSeconds: Double?
    let mimeType: String?
    let dataBase64: String
}

// MARK: - TTS Types

struct TTSRequest: Codable {
    let text: String
    let voice: String
    var provider: String = "openai"
}

struct TTSResponse: Codable {
    let ok: Bool
    let audioBase64: String?
    let voice: String?
    let error: String?
}

// MARK: - Content Ingestion Types

struct IngestRequest: Codable {
    let sourceType: String   // "url", "ocr", "photo", "text"
    let text: String
    let title: String?
    let sourceURL: String?
    let imageBase64: String?
    let imageFilename: String?
    let bookmarkCanonicalURL: String?
    let bookmarkHost: String?
    let bookmarkSiteName: String?
    let bookmarkSummary: String?
    let bookmarkImageURL: String?
    let sourceApplicationBundleID: String?
    let sourceApplicationName: String?
    let sourceDevice: String?
    let ingestMethod: String?
}

struct IngestResponse: Codable {
    let ok: Bool
    let objectId: String?
    let storedAt: String?
    let error: String?
}

// MARK: - Memo Attachment Types

struct MemoAttachmentUploadRequest: Codable {
    let memoTitle: String?
    let memoCreatedAt: String?
    let attachments: [MemoAttachmentUploadItem]
}

struct MemoAttachmentUploadResponse: Codable {
    let success: Bool
    let memoId: String
    let savedCount: Int
    let storedAt: String
}

struct ComposeRevisionRequest: Codable {
    let text: String
    let instruction: String
}

struct ComposeCommandRequest: Codable {
    let context: String
    let instruction: String
    let title: String?
    let sourceDescription: String?
}

struct EmptyBridgeRequest: Codable {}

struct ComposeBorrowedProviderRequest: Codable {
    let providerId: String?
    let modelId: String?
}

struct ComposeRevisionEnvelope: Codable {
    let ok: Bool
    let result: ComposeRevisionResult?
    let error: String?
}

struct ComposeCommandEnvelope: Codable {
    let ok: Bool
    let result: ComposeCommandResult?
    let error: String?
}

struct EncryptedBridgePayload: Codable {
    let ciphertext: String
}

struct ComposeBorrowedProviderEnvelope: Codable {
    let ok: Bool
    let encrypted: EncryptedBridgePayload?
    let error: String?
}

struct ComposeDirectOptionsEnvelope: Codable {
    let ok: Bool
    let result: ComposeDirectOptionsResult?
    let error: String?
}

struct ComposeDirectOptionsResult: Codable {
    let providers: [ComposeDirectProviderOption]
    let selectedProviderId: String
    let selectedModelId: String
}

struct ComposeDirectProviderOption: Codable, Hashable, Identifiable {
    let providerId: String
    let providerName: String
    let models: [ComposeDirectModelOption]

    var id: String { providerId }
}

struct ComposeDirectModelOption: Codable, Hashable, Identifiable {
    let id: String
    let name: String
}

struct ComposeRevisionResult: Codable {
    let revisedText: String
    let providerId: String
    let providerName: String
    let modelId: String
    let usedConfiguredProvider: Bool
    let usedConfiguredModel: Bool
    let fallbackReason: String?
}

struct ComposeCommandResult: Codable {
    let outputText: String
    let providerId: String
    let providerName: String
    let modelId: String
    let usedConfiguredProvider: Bool
    let usedConfiguredModel: Bool
    let fallbackReason: String?
}

struct ComposeBorrowedProvider: Codable {
    let providerId: String
    let providerName: String
    let modelId: String
    let apiKey: String
    let assistantPrompt: String
    let fallbackReason: String?
}

// MARK: - Headless Types

struct HeadlessRequest: Codable {
    let sessionId: String?
    let message: String
    let projectDir: String?
    let stream: Bool?

    init(sessionId: String? = nil, message: String, projectDir: String? = nil, stream: Bool = false) {
        self.sessionId = sessionId
        self.message = message
        self.projectDir = projectDir
        self.stream = stream
    }
}

struct HeadlessResponse: Codable {
    let success: Bool
    let response: String?
    let messageCount: Int?
    let sessionId: String?
    let error: String?
    let stderr: String?
}

// MARK: - Remote CLI Types

struct CLIRequest: Codable {
    let command: String
    let timeout: Int?
}

struct CLIResponse: Codable {
    let success: Bool
    let output: String?
    let error: String?
    let exitCode: Int?
    let durationMs: Int?
}

struct SSEChunk: Codable {
    let type: String?
    let content: String?
    let error: String?
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case type, content, error
        case sessionId = "session_id"
    }
}

struct MessageResponse: Codable {
    let success: Bool
    let error: String?
    let transcript: String?      // Included when sending audio
    let deliveredAt: String?     // ISO timestamp when delivered to Claude
    let insertedText: String?    // The actual text that was inserted

    // Mode info (smart routing)
    let mode: String?            // "ui" or "headless"
    let modeReason: String?      // Why this mode was chosen
    let screenLocked: Bool?      // Was Mac screen locked?
    let response: String?        // Claude's response (headless mode only)
    let verified: Bool?          // UI mode: did message appear in logs?
    let verifyAttempts: Int?     // How many log checks were needed
}

struct QRCodeData: Codable {
    enum Mode: String, Codable {
        case pairing
        case nearby
        case localDev = "local_dev"
    }

    let publicKey: String
    let hostname: String
    let alternateHosts: [String]?
    let port: Int
    let `protocol`: String
    let mode: Mode?
    let pairingReady: Bool?
}

// MARK: - Window Types

struct WindowsResponse: Codable {
    let windows: [TerminalWindow]
}

struct CompanionStateResponse: Codable, Equatable {
    enum RequestedSurface: String, Codable {
        case normal
        case shortcut
    }

    let isAvailable: Bool
    let requestedSurface: RequestedSurface
    let shortcutSlots: [String]?
    let shortcutPages: [CompanionShortcutPage]?
    let shortcutStates: [CompanionShortcutRuntimeState]?
    let recentResults: [CompanionShortcutRecentResult]?
    let appSwitcherApps: [CompanionAppSwitcherApp]?
    let securityEvents: [BridgeSecurityEvent]?
    let publishRevision: Int?
    let lastPublishedAt: String?
}

struct CompanionEventEnvelope: Codable {
    let type: String
    let snapshot: CompanionStateResponse?
    let reason: String?
    let error: String?
}

struct BridgeSecurityEvent: Codable, Identifiable, Equatable {
    let id: String
    let type: String
    let severity: String
    let source: String
    let title: String
    let message: String
    let createdAt: String
    let macName: String?
    let deviceId: String?
    let deviceName: String?
}

struct CompanionShortcutPage: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let shortcutSlots: [String]
}

struct CompanionShortcutRuntimeState: Codable, Hashable {
    enum Phase: String, Codable {
        case preparing
        case recording
        case processing
    }

    let shortcutId: String
    let phase: Phase
    let canStop: Bool
    let detail: String?
    let elapsedSeconds: Double?
    let signalLevel: Double?
}

struct CompanionShortcutRecentResult: Codable, Hashable {
    let shortcutId: String
    let resultText: String
    let completedAt: String
}

struct CompanionAppSwitcherApp: Codable, Hashable, Identifiable {
    var id: String {
        bundleIdentifier ?? "pid-\(processIdentifier)"
    }

    let processIdentifier: Int32
    let bundleIdentifier: String?
    let displayName: String
    let isFrontmost: Bool
    let iconPNGBase64: String?

    var iconData: Data? {
        guard let iconPNGBase64 else { return nil }
        return Data(base64Encoded: iconPNGBase64)
    }
}

struct TerminalWindow: Codable, Identifiable {
    let windowID: UInt32
    let pid: Int32
    let bundleId: String?
    let appName: String
    let title: String?
    let isOnScreen: Bool
    let bounds: WindowBounds?

    var id: UInt32 { windowID }

    var displayTitle: String {
        title ?? appName
    }
}

struct WindowBounds: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct WindowCapturesResponse: Codable {
    let screenshots: [WindowCapture]
    let count: Int
}

struct WindowCapture: Codable, Identifiable {
    let windowID: UInt32
    let bundleId: String
    let title: String
    let imageBase64: String

    var id: UInt32 { windowID }

    /// Decode the base64 image data
    var imageData: Data? {
        Data(base64Encoded: imageBase64)
    }
}

// MARK: - Errors

enum BridgeError: LocalizedError {
    case notConfigured
    case invalidResponse
    case httpError(Int)
    case connectionFailed
    case pairingRejected
    case messageFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Bridge not configured. Scan QR code first."
        case .invalidResponse:
            return "Invalid response from bridge"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .connectionFailed:
            return "Could not connect to Mac"
        case .pairingRejected:
            return "Pairing was rejected"
        case .messageFailed(let reason):
            return "Could not send message: \(reason)"
        }
    }
}
