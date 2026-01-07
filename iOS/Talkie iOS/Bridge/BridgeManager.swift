//
//  BridgeManager.swift
//  Talkie iOS
//
//  Manages connection to TalkieBridge on Mac
//

import Foundation
import CryptoKit
import SwiftUI

@Observable
final class BridgeManager {
    static let shared = BridgeManager()

    // MARK: - State

    enum ConnectionStatus: String {
        case disconnected = "Disconnected"
        case connecting = "Connecting"
        case connected = "Connected"
        case error = "Error"

        var icon: String {
            switch self {
            case .disconnected: return "wifi.slash"
            case .connecting: return "wifi.exclamationmark"
            case .connected: return "wifi"
            case .error: return "exclamationmark.triangle"
            }
        }

        var color: Color {
            switch self {
            case .disconnected: return .gray
            case .connecting: return .orange
            case .connected: return .green
            case .error: return .red
            }
        }
    }

    // MARK: - Properties

    private(set) var status: ConnectionStatus = .disconnected
    var sessions: [ClaudeSession] = []
    var projectPaths: [ProjectPath] = []  // Grouped by project
    private(set) var windows: [TerminalWindow] = []
    private(set) var windowCaptures: [WindowCapture] = []
    private(set) var errorMessage: String?
    private(set) var pairedMacName: String?
    private(set) var retryCount = 0

    let client = BridgeClient()
    private var retryTask: Task<Void, Never>?

    // Retry configuration
    private let maxRetries = 3
    private let baseRetryDelayNs: UInt64 = 2_000_000_000  // 2 seconds

    // UserDefaults keys
    private let hostnameKey = "bridge.hostname"
    private let portKey = "bridge.port"
    private let deviceIdKey = "bridge.deviceId"
    private let pairedMacKey = "bridge.pairedMacName"
    private let privateKeyKey = "bridge.privateKey"
    private let serverPublicKeyKey = "bridge.serverPublicKey"

    // MARK: - Computed

    var isPaired: Bool {
        UserDefaults.standard.string(forKey: hostnameKey) != nil
    }

    /// Whether the manager should attempt to connect (paired but not connected)
    var shouldConnect: Bool {
        isPaired && (status == .disconnected || status == .error)
    }

    var deviceId: String {
        if let existing = UserDefaults.standard.string(forKey: deviceIdKey) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: deviceIdKey)
        return newId
    }

    var deviceName: String {
        UIDevice.current.name
    }

    // MARK: - Init

    private init() {
        loadPairing()
    }

    // MARK: - Public API

    /// Process scanned QR code data
    func processPairing(qrData: QRCodeData) async {
        status = .connecting
        errorMessage = nil

        // Configure client
        await client.configure(hostname: qrData.hostname, port: qrData.port)

        do {
            // Decode server's public key from QR (X9.63 format: 04 || x || y)
            guard let serverPublicKeyData = Data(base64Encoded: qrData.publicKey) else {
                throw BridgeError.invalidResponse
            }
            let serverPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: serverPublicKeyData)

            // Generate our key pair
            let privateKey = P256.KeyAgreement.PrivateKey()
            // Use X9.63 format to match Web Crypto's "raw" export (04 || x || y)
            let publicKeyData = privateKey.publicKey.x963Representation
            let publicKeyBase64 = publicKeyData.base64EncodedString()

            // Derive shared secret via ECDH
            let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: serverPublicKey)

            // Configure auth BEFORE making authenticated requests
            await client.configureAuth(deviceId: deviceId, sharedSecret: sharedSecret)

            // Sync clocks
            try await client.connect()

            // Send pairing request
            let response = try await client.pair(
                deviceId: deviceId,
                publicKey: publicKeyBase64,
                name: deviceName
            )

            if response.status == "approved" || response.status == "pending_approval" {
                // Save pairing info
                UserDefaults.standard.set(qrData.hostname, forKey: hostnameKey)
                UserDefaults.standard.set(qrData.port, forKey: portKey)
                UserDefaults.standard.set(qrData.publicKey, forKey: serverPublicKeyKey)

                // Save our private key for reconnection
                let privateKeyBase64 = privateKey.rawRepresentation.base64EncodedString()
                UserDefaults.standard.set(privateKeyBase64, forKey: privateKeyKey)

                // Test connection
                let health = try await client.health()
                pairedMacName = health.hostname
                UserDefaults.standard.set(health.hostname, forKey: pairedMacKey)

                status = .connected
                await refreshPaths()
                await refreshSessions()
            } else {
                status = .error
                errorMessage = "Pairing rejected by Mac"
            }
        } catch {
            status = .error
            errorMessage = error.localizedDescription
        }
    }

    /// Connect using saved pairing with auto-retry
    func connect() async {
        // Cancel any pending retry
        retryTask?.cancel()
        retryTask = nil

        guard let hostname = UserDefaults.standard.string(forKey: hostnameKey) else {
            return
        }

        let port = UserDefaults.standard.integer(forKey: portKey)
        guard port > 0 else { return }

        status = .connecting
        errorMessage = nil

        await client.configure(hostname: hostname, port: port)

        // Restore auth credentials from saved keys
        do {
            try await restoreAuth()
        } catch {
            status = .error
            errorMessage = "Auth keys missing - please re-pair"
            retryCount = maxRetries  // Don't retry auth failures
            return
        }

        do {
            // Sync clocks before making requests
            try await client.connect()

            let health = try await client.health()
            pairedMacName = health.hostname
            status = .connected
            retryCount = 0  // Reset on success
            await refreshPaths()
            await refreshSessions()
        } catch {
            status = .error
            errorMessage = "Could not connect to Mac"
            scheduleRetry()
        }
    }

    /// Manually retry connection (resets retry count)
    func retry() async {
        retryCount = 0
        await connect()
    }

    /// Schedule an automatic retry with exponential backoff
    private func scheduleRetry() {
        guard retryCount < maxRetries else {
            print("[BridgeManager] Max retries (\(maxRetries)) reached, giving up")
            return
        }

        retryCount += 1
        let delay = baseRetryDelayNs * UInt64(1 << (retryCount - 1))  // Exponential backoff
        print("[BridgeManager] Scheduling retry \(retryCount)/\(maxRetries) in \(delay / 1_000_000_000)s")

        retryTask = Task {
            do {
                try await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                await connect()
            } catch {
                // Task cancelled
            }
        }
    }

    /// Restore auth credentials from saved keys
    private func restoreAuth() async throws {
        guard let privateKeyBase64 = UserDefaults.standard.string(forKey: privateKeyKey),
              let serverPublicKeyBase64 = UserDefaults.standard.string(forKey: serverPublicKeyKey),
              let privateKeyData = Data(base64Encoded: privateKeyBase64),
              let serverPublicKeyData = Data(base64Encoded: serverPublicKeyBase64) else {
            throw BridgeError.notConfigured
        }

        let privateKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)
        // Server public key is in X9.63 format (04 || x || y)
        let serverPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: serverPublicKeyData)

        // Re-derive shared secret
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: serverPublicKey)

        // Configure auth
        await client.configureAuth(deviceId: deviceId, sharedSecret: sharedSecret)
    }

    /// Disconnect and clear state
    func disconnect() {
        retryTask?.cancel()
        retryTask = nil
        retryCount = 0
        status = .disconnected
        sessions = []
        projectPaths = []
        windows = []
        windowCaptures = []
    }

    /// Remove pairing completely (clears all credentials)
    func unpair() {
        disconnect()

        // Clear all pairing data
        UserDefaults.standard.removeObject(forKey: hostnameKey)
        UserDefaults.standard.removeObject(forKey: portKey)
        UserDefaults.standard.removeObject(forKey: pairedMacKey)
        UserDefaults.standard.removeObject(forKey: privateKeyKey)
        UserDefaults.standard.removeObject(forKey: serverPublicKeyKey)
        // Also clear device ID to force fresh identity on re-pair
        UserDefaults.standard.removeObject(forKey: deviceIdKey)

        pairedMacName = nil
        errorMessage = nil

        // Clear client auth state
        Task {
            await client.clearAuth()
        }
    }

    /// Set error state (for validation failures before pairing)
    func setError(_ message: String) {
        status = .error
        errorMessage = message
    }

    /// Manually refresh sessions (flat view)
    func refreshSessions() async {
        guard status == .connected else { return }

        do {
            let response = try await client.sessions()
            sessions = response.sessions
        } catch {
            // Don't change status on refresh failure
            print("Failed to refresh sessions: \(error)")
        }
    }

    /// Refresh project paths (grouped view - preferred)
    func refreshPaths() async {
        guard status == .connected else {
            print("[BridgeManager] refreshPaths: not connected, skipping")
            return
        }

        do {
            print("[BridgeManager] refreshPaths: fetching...")
            let response = try await client.paths()
            print("[BridgeManager] refreshPaths: got \(response.paths.count) paths")
            for path in response.paths.prefix(3) {
                print("[BridgeManager]   - \(path.name): \(path.sessions.count) sessions")
            }
            projectPaths = response.paths
        } catch {
            print("[BridgeManager] refreshPaths FAILED: \(error)")
        }
    }

    /// Get messages for a session
    func getMessages(sessionId: String) async throws -> [SessionMessage] {
        let response = try await client.sessionMessages(id: sessionId)
        return response.messages
    }

    /// Send a message to a Claude session's terminal
    func sendMessage(sessionId: String, text: String) async throws {
        let response = try await client.sendMessage(sessionId: sessionId, text: text)
        if !response.success {
            throw BridgeError.messageFailed(response.error ?? "Unknown error")
        }
    }

    /// Send a message with an attached image
    /// Note: Image sending is not yet supported by the bridge server
    func sendMessageWithImage(sessionId: String, text: String, image: UIImage) async throws {
        // TODO: Implement image sending when bridge server supports it
        // For now, just send the text portion
        try await sendMessage(sessionId: sessionId, text: text)
    }

    /// Send audio to be transcribed and submitted to Claude
    /// - Returns: The transcript that was sent
    func sendAudio(sessionId: String, audioURL: URL) async throws -> String {
        let response = try await sendAudioWithResponse(sessionId: sessionId, audioURL: audioURL)
        return response.transcript ?? ""
    }

    /// Send audio and return full response with delivery confirmation
    func sendAudioWithResponse(sessionId: String, audioURL: URL) async throws -> MessageResponse {
        let audioData = try Data(contentsOf: audioURL)
        let response = try await client.sendAudio(sessionId: sessionId, audioData: audioData)
        if !response.success {
            throw BridgeError.messageFailed(response.error ?? "Unknown error")
        }
        return response
    }

    /// Force press Enter key in a session's terminal
    /// Useful when auto-submit doesn't work
    func forceEnter(sessionId: String) async throws {
        let response = try await client.forceEnter(sessionId: sessionId)
        if !response.success {
            throw BridgeError.messageFailed(response.error ?? "Unknown error")
        }
    }

    // MARK: - Window & Screenshot Methods

    /// Refresh the list of terminal windows
    func refreshWindows() async {
        guard status == .connected else { return }

        do {
            let response = try await client.windows()
            windows = response.windows
        } catch {
            print("Failed to refresh windows: \(error)")
        }
    }

    /// Fetch all window captures (screenshots + metadata)
    func refreshWindowCaptures() async {
        guard status == .connected else { return }

        do {
            let response = try await client.windowCaptures()
            windowCaptures = response.screenshots
        } catch {
            print("Failed to capture windows: \(error)")
        }
    }

    /// Fetch all window captures (throwing version for UI feedback)
    func refreshWindowCapturesWithError() async throws {
        guard status == .connected else {
            throw BridgeError.notConfigured
        }

        let response = try await client.windowCaptures()
        windowCaptures = response.screenshots
    }

    /// Get screenshot data for a specific window
    func getWindowScreenshot(windowId: UInt32) async throws -> Data {
        try await client.windowScreenshot(windowId: windowId)
    }

    /// Refresh sessions, paths, and windows
    func refreshAll() async {
        await refreshPaths()
        await refreshSessions()
        await refreshWindows()
    }

    // MARK: - Private

    private func loadPairing() {
        pairedMacName = UserDefaults.standard.string(forKey: pairedMacKey)
    }

}
