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
    private var sharedKey: SymmetricKey?

    // MARK: - Configuration

    func configure(hostname: String, port: Int) {
        self.baseURL = URL(string: "http://\(hostname):\(port)")
    }

    func setSharedKey(_ key: SymmetricKey) {
        self.sharedKey = key
    }

    var isConfigured: Bool {
        baseURL != nil
    }

    // MARK: - API Calls

    func health() async throws -> HealthResponse {
        let data = try await get("/health")
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    func sessions() async throws -> SessionsResponse {
        let data = try await get("/sessions")
        return try JSONDecoder().decode(SessionsResponse.self, from: data)
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
        let body = MessageRequest(text: text)
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
        // Send empty text - server will just press Enter without inserting anything
        let body = MessageRequest(text: "")
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

    private func get(_ path: String) async throws -> Data {
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

    private func post<T: Encodable>(_ path: String, body: T, timeout: TimeInterval = 10) async throws -> Data {
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

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BridgeError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw BridgeError.httpError(httpResponse.statusCode)
        }

        return data
    }
}

// MARK: - Request/Response Types

struct HealthResponse: Codable {
    let status: String
    let version: String
    let hostname: String
    let port: Int
}

struct SessionsResponse: Codable {
    let sessions: [ClaudeSession]
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
    let text: String
}


struct AudioMessageRequest: Codable {
    let audio: String  // Base64 encoded audio
    let format: String  // "m4a", "wav", etc.
}

struct MessageResponse: Codable {
    let success: Bool
    let error: String?
    let transcript: String?  // Included when sending audio
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
