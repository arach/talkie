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
    private(set) var sessions: [ClaudeSession] = []
    private(set) var windows: [TerminalWindow] = []
    private(set) var windowCaptures: [WindowCapture] = []
    private(set) var errorMessage: String?
    private(set) var pairedMacName: String?

    private let client = BridgeClient()
    private var refreshTask: Task<Void, Never>?

    // UserDefaults keys
    private let hostnameKey = "bridge.hostname"
    private let portKey = "bridge.port"
    private let deviceIdKey = "bridge.deviceId"
    private let pairedMacKey = "bridge.pairedMacName"

    // MARK: - Computed

    var isPaired: Bool {
        UserDefaults.standard.string(forKey: hostnameKey) != nil
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
            // Generate our key pair
            let privateKey = P256.KeyAgreement.PrivateKey()
            let publicKeyData = privateKey.publicKey.rawRepresentation
            let publicKeyBase64 = publicKeyData.base64EncodedString()

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

                // Test connection
                let health = try await client.health()
                pairedMacName = health.hostname
                UserDefaults.standard.set(health.hostname, forKey: pairedMacKey)

                status = .connected
                await refreshSessions()
                startAutoRefresh()
            } else {
                status = .error
                errorMessage = "Pairing rejected by Mac"
            }
        } catch {
            status = .error
            errorMessage = error.localizedDescription
        }
    }

    /// Connect using saved pairing
    func connect() async {
        guard let hostname = UserDefaults.standard.string(forKey: hostnameKey) else {
            return
        }

        let port = UserDefaults.standard.integer(forKey: portKey)
        guard port > 0 else { return }

        status = .connecting
        errorMessage = nil

        await client.configure(hostname: hostname, port: port)

        do {
            let health = try await client.health()
            pairedMacName = health.hostname
            status = .connected
            await refreshSessions()
            startAutoRefresh()
        } catch {
            status = .error
            errorMessage = "Could not connect to Mac"
        }
    }

    /// Disconnect and stop auto-refresh
    func disconnect() {
        stopAutoRefresh()
        status = .disconnected
        sessions = []
        windows = []
        windowCaptures = []
    }

    /// Remove pairing
    func unpair() {
        disconnect()
        UserDefaults.standard.removeObject(forKey: hostnameKey)
        UserDefaults.standard.removeObject(forKey: portKey)
        UserDefaults.standard.removeObject(forKey: pairedMacKey)
        pairedMacName = nil
    }

    /// Set error state (for validation failures before pairing)
    func setError(_ message: String) {
        status = .error
        errorMessage = message
    }

    /// Manually refresh sessions
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

    /// Send audio to be transcribed and submitted to Claude
    /// - Returns: The transcript that was sent
    func sendAudio(sessionId: String, audioURL: URL) async throws -> String {
        let audioData = try Data(contentsOf: audioURL)
        let response = try await client.sendAudio(sessionId: sessionId, audioData: audioData)
        if !response.success {
            throw BridgeError.messageFailed(response.error ?? "Unknown error")
        }
        return response.transcript ?? ""
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

    /// Refresh both sessions and windows
    func refreshAll() async {
        await refreshSessions()
        await refreshWindows()
    }

    // MARK: - Private

    private func loadPairing() {
        pairedMacName = UserDefaults.standard.string(forKey: pairedMacKey)
    }

    private func startAutoRefresh() {
        stopAutoRefresh()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                await refreshSessions()
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
