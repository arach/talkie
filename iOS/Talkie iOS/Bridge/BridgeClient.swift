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
    }

    /// Configure authentication credentials from pairing
    func configureAuth(deviceId: String, sharedSecret: SharedSecret) {
        self.deviceId = deviceId
        self.authKey = sharedSecret.deriveAuthKey()
    }

    /// Clear all authentication state (for unpair)
    func clearAuth() {
        self.deviceId = nil
        self.authKey = nil
        self.sharedKey = nil
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
                print("[BridgeClient] Clock offset with Mac: \(String(format: "%.1f", clockOffset))s")
            }
        }
    }

    /// Recalibrate clock from a server timestamp (e.g., from 401 response)
    private func recalibrateClockFrom(serverTime: Int) {
        let localTime = Date().timeIntervalSince1970
        clockOffset = Double(serverTime) - localTime
        print("[BridgeClient] Clock recalibrated, new offset: \(String(format: "%.1f", clockOffset))s")
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
        // Use longer timeout for deep sync (scans all sessions)
        let data = try await get(path, timeout: deepSync ? 30 : 10)
        let response = try JSONDecoder().decode(SessionsResponse.self, from: data)

        // Log the full response for debugging
        if let jsonString = String(data: data, encoding: .utf8) {
            AppLogger.app.info("[Bridge] sessions() returned \(response.sessions.count) sessions - deepSync: \(deepSync)", detail: jsonString)
        }

        return response
    }

    func paths(deepSync: Bool = false) async throws -> PathsResponse {
        let path = deepSync ? "/paths?refresh=deep" : "/paths"
        // Use longer timeout for deep sync (scans all sessions)
        let data = try await get(path, timeout: deepSync ? 30 : 10)
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

    /// Get screenshot of a specific window (returns JPEG Data)
    func windowScreenshot(windowId: UInt32) async throws -> Data {
        return try await get("/windows/\(windowId)/screenshot")
    }

    /// Get all terminal window screenshots with metadata
    func windowCaptures() async throws -> WindowCapturesResponse {
        let data = try await get("/windows/captures")
        return try JSONDecoder().decode(WindowCapturesResponse.self, from: data)
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
        request.timeoutInterval = 10

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
    private func get(_ path: String, allowRetry: Bool = true, timeout: TimeInterval = 10) async throws -> Data {
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
    private func post<T: Encodable>(_ path: String, body: T, timeout: TimeInterval = 10, allowRetry: Bool = true) async throws -> Data {
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
    let path: String              // Full path (e.g., "/Users/arach/dev/talkie")
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
    let projectPath: String     // Full path (e.g., "/Users/arach/dev/talkie")
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


struct AudioMessageRequest: Codable {
    let audio: String  // Base64 encoded audio
    let format: String  // "m4a", "wav", etc.
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
    let publicKey: String
    let hostname: String
    let port: Int
    let `protocol`: String
}

// MARK: - Window Types

struct WindowsResponse: Codable {
    let windows: [TerminalWindow]
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
