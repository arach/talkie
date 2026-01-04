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

    private func post<T: Encodable>(_ path: String, body: T) async throws -> Data {
        guard let baseURL = baseURL else {
            throw BridgeError.notConfigured
        }

        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw BridgeError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
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
    let id: String
    let project: String
    let projectPath: String
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

struct MessageResponse: Codable {
    let success: Bool
    let error: String?
}

struct QRCodeData: Codable {
    let publicKey: String
    let hostname: String
    let port: Int
    let `protocol`: String
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
