//
//  BridgeManager.swift
//  Talkie iOS
//
//  Manages connection to TalkieBridge on Mac
//

import Foundation
import Combine
import CryptoKit
import SwiftUI
import UIKit
import TalkieMobileKit

extension Notification.Name {
    static let bridgeDidConnect = Notification.Name("com.jdi.talkie.bridgeDidConnect")
    static let companionShortcutSurfaceRequested = Notification.Name("to.talkie.companionShortcutSurfaceRequested")
}

@MainActor
@Observable
final class BridgeManager {
    typealias PairedMac = TalkieAppConfiguration.Bridge.PairedMac

    enum PairingResult: Equatable {
        case approved
        case pendingApproval
    }

    private struct PairingExecutionResult {
        let privateKeyBase64: String
        let connectionHost: String
        let pairedMacName: String
        let pairingResult: PairingResult
    }

    private struct PendingPairingCandidate: Sendable {
        let attemptID: UUID
        let deviceId: String
        let privateKeyBase64: String
        let connectionHost: String
        let pairedMacName: String
        let port: Int
        let serverPublicKeyBase64: String
        let encryptionPinned: Bool
        let streamEncryptionPinned: Bool
    }

    private enum PairingExecutionError: LocalizedError {
        case rejected
        case pendingApproval

        var errorDescription: String? {
            switch self {
            case .rejected:
                return "Pairing rejected by Mac"
            case .pendingApproval:
                return "Approve this iPhone on your Mac, then try importing credentials again."
            }
        }
    }

    static let shared = BridgeManager()

    private let log = Log(.system)
    private let configurationStore = TalkieAppConfigurationStore.shared
    private let privateKeyStore = BridgePrivateKeyStore()

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

    struct CredentialImportEvent: Identifiable, Equatable {
        enum Level: Equatable {
            case info
            case warning
            case success
        }

        let id: UUID
        let date: Date
        let level: Level
        let message: String

        init(
            message: String,
            level: Level = .info,
            date: Date = .now,
            id: UUID = UUID()
        ) {
            self.id = id
            self.date = date
            self.level = level
            self.message = message
        }
    }

    // MARK: - Properties

    private(set) var status: ConnectionStatus = .disconnected {
        didSet {
            if status == .connected && oldValue != .connected {
                NotificationCenter.default.post(name: .bridgeDidConnect, object: nil)
            }
        }
    }
    var sessions: [ClaudeSession] = []
    var projectPaths: [ProjectPath] = []
    private(set) var windows: [TerminalWindow] = []
    private(set) var windowCaptures: [WindowCapture] = []
    private(set) var companionState: CompanionStateResponse?
    private(set) var errorMessage: String?
    private(set) var pairedMacName: String?
    private(set) var activePairedMacID: String?
    private(set) var lastSuccessfulContactAt: Date?
    private(set) var retryCount = 0
    private(set) var awaitingPairingApproval = false
    private(set) var credentialImportEvents: [CredentialImportEvent] = []

    /// Set to true when pairing completes, UI should consume and reset
    var justCompletedPairing = false

    let client = BridgeClient()
    private var retryTask: Task<Void, Never>?
    private var autoReconnectTask: Task<Void, Never>?
    private var autoReconnectCancellables = Set<AnyCancellable>()
    private var companionPollTask: Task<Void, Never>?
    private var pendingPairingApprovalTask: Task<Void, Never>?
    private var activePairingAttemptID: UUID?
    private var companionEventTask: Task<Void, Never>?
    private var companionEventSocket: URLSessionWebSocketTask?
    // Captured per stream connection: when true, each companion event frame is a
    // sealed envelope opened fail-closed (drop frames that can't be opened).
    private var companionEventStreamEncrypted = false
    private var lastReportedSetupState: DeviceSetupStateRequest?
    private var isRefreshingCompanionState = false
    private var pendingCompanionRefresh = false
    private var isCompanionDeckVisible = false
    private var isCompanionRuntimeActive = false
    private var isCompanionEventStreamConnected = false
    private var lastConnectionAuthFailed = false
    private var lastCompanionShortcutSurfaceRequestKey: String?

    // Retry configuration
    private let maxRetries = 3
    private let baseRetryDelayNs: UInt64 = 2_000_000_000  // 2 seconds

    // MARK: - Computed

    var pairedMacs: [PairedMac] {
        configurationStore.configuration.bridge.pairedMacs
    }

    var hasPairedMacs: Bool {
        !pairedMacs.isEmpty
    }

    var isPaired: Bool {
        activePairedMac != nil
    }

    /// Whether the manager should attempt to connect (paired but not connected)
    var shouldConnect: Bool {
        isPaired && (status == .disconnected || status == .error)
    }

    /// The Mac rejected the saved device identity, so retrying the same
    /// credentials cannot succeed. Surfaces a re-pair action to the UI.
    var pairingNeedsRefresh: Bool {
        lastConnectionAuthFailed
    }

    var activePairedMac: PairedMac? {
        let bridgeConfiguration = configurationStore.configuration.bridge
        let mac = bridgeConfiguration.pairedMacs.first(where: { $0.id == bridgeConfiguration.activePairedMacID })
            ?? bridgeConfiguration.pairedMacs.first
        return hydratePrivateKey(mac)
    }

    var pairedHostname: String? {
        let hostname = activePairedMac?.hostname ?? ""
        return hostname.isEmpty ? nil : hostname
    }

    var pairedPort: Int? {
        let value = activePairedMac?.port ?? 0
        return value > 0 ? value : nil
    }

    var pairedMacDisplayName: String? {
        if let pairedMacName = sanitizedMacName(pairedMacName) {
            return pairedMacName
        }

        if let storedName = sanitizedMacName(activePairedMac?.pairedMacName) {
            return storedName
        }

        return nil
    }

    var activeRouteDescription: String {
        TalkieNetworkRouteClassifier.route(for: pairedHostname).displayName
    }

    var deviceId: String {
        let currentConfiguration = configurationStore.configuration
        if !currentConfiguration.bridge.deviceId.isEmpty {
            return currentConfiguration.bridge.deviceId
        }

        let newId = UUID().uuidString
        configurationStore.update { configuration in
            configuration.bridge.deviceId = newId
        }
        TalkieAppSettings.shared.reloadFromDisk()
        return newId
    }

    var deviceName: String {
        UIDevice.current.name
    }

    private var currentDeviceClass: String {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            return "ipad"
        default:
            return "iphone"
        }
    }

    private var companionPollingInterval: Duration {
        if isCompanionRuntimeActive {
            return .seconds(1)
        }

        if isCompanionDeckVisible {
            return .seconds(5)
        }

        if isCompanionEventStreamConnected {
            return .seconds(60)
        }

        return .seconds(30)
    }

    // MARK: - Init

    private init() {
        migratePrivateKeysToKeychainIfNeeded()
        loadPairing()
        setupAutoReconnectObservers()
    }

    /// One-time migration: move any bridge private keys still stored in
    /// config.json / legacy UserDefaults into the keychain, then blank the
    /// plaintext copies. Idempotent — a no-op once everything lives in the keychain.
    private func migratePrivateKeysToKeychainIfNeeded() {
        let defaults = UserDefaults.standard
        var migratedAny = false

        configurationStore.update { configuration in
            for index in configuration.bridge.pairedMacs.indices {
                let mac = configuration.bridge.pairedMacs[index]
                let plaintextKey = mac.privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !plaintextKey.isEmpty else { continue }
                privateKeyStore.save(id: mac.id, privateKeyBase64: plaintextKey)
                configuration.bridge.pairedMacs[index].privateKey = ""
                migratedAny = true
            }
        }

        // Drop the legacy plaintext UserDefaults copy regardless (it is mirrored
        // into config.json on bootstrap, so the key is already preserved above).
        if defaults.object(forKey: "bridge.privateKey") != nil {
            defaults.removeObject(forKey: "bridge.privateKey")
            migratedAny = true
        }

        if migratedAny {
            TalkieAppSettings.shared.reloadFromDisk()
        }
    }

    /// Fill in a paired Mac's private key from the keychain (the field is no
    /// longer persisted in config.json).
    private func hydratePrivateKey(_ mac: PairedMac?) -> PairedMac? {
        guard var mac else { return nil }
        if mac.privateKey.isEmpty, let stored = privateKeyStore.load(id: mac.id) {
            mac.privateKey = stored
        }
        return mac
    }


    private var shouldAutoReconnect: Bool {
        hasPairedMacs &&
        status != .connected &&
        status != .connecting &&
        !awaitingPairingApproval
    }

    private func setupAutoReconnectObservers() {
        NetworkReachability.shared.start()

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.triggerAutoReconnect(reason: "foreground")
                }
            }
            .store(in: &autoReconnectCancellables)

        NetworkReachability.shared.$status
            .removeDuplicates()
            .sink { [weak self] status in
                guard status == .online else { return }
                Task { @MainActor [weak self] in
                    self?.triggerAutoReconnect(reason: "network up")
                }
            }
            .store(in: &autoReconnectCancellables)
    }

    private func triggerAutoReconnect(reason: String) {
        guard shouldAutoReconnect else { return }
        log.info("🔌 BridgeManager auto-reconnect: \(reason)")

        retryTask?.cancel()
        retryTask = nil
        autoReconnectTask?.cancel()

        autoReconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, self.shouldAutoReconnect else { return }
            await self.connect()
            if !Task.isCancelled {
                self.autoReconnectTask = nil
            }
        }
    }

    // MARK: - Public API

    /// Process scanned QR code data
    func processPairing(qrData: QRCodeData) async -> PairingResult? {
        if let validationError = pairingValidationError(for: qrData) {
            awaitingPairingApproval = false
            status = .error
            errorMessage = validationError
            return nil
        }

        stopPendingPairingApprovalMonitor()
        let pairingAttemptID = UUID()
        activePairingAttemptID = pairingAttemptID
        let hadPairedMacsBeforePairing = hasPairedMacs
        status = .connecting
        errorMessage = nil
        awaitingPairingApproval = false
        let hostname = qrData.hostname
        let candidateHosts = pairingCandidateHosts(for: qrData)
        let port = qrData.port
        let serverPublicKeyBase64 = qrData.publicKey
        let localDeviceId = deviceId
        let localDeviceName = deviceName
        let existingPairedMac = pairedMacMatchingPairing(
            serverPublicKey: serverPublicKeyBase64,
            candidateHosts: candidateHosts,
            port: port
        )
        let encryptionPinned = existingPairedMac.map { Self.isEncryptionPinned($0.id) } ?? false
        let streamEncryptionPinned = existingPairedMac.map { Self.isStreamEncryptionPinned($0.id) } ?? false

        do {
            let result = try await Task.detached(priority: .userInitiated) { [client] in
                guard let serverPublicKeyData = Data(base64Encoded: serverPublicKeyBase64) else {
                    throw BridgeError.invalidResponse
                }
                let serverPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: serverPublicKeyData)

                var lastError: Error?
                for candidateHost in candidateHosts {
                    do {
                        await client.configure(hostname: candidateHost, port: port)

                        let privateKey = P256.KeyAgreement.PrivateKey()
                        let publicKeyBase64 = privateKey.publicKey.x963Representation.base64EncodedString()
                        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: serverPublicKey)

                        await client.configureAuth(deviceId: localDeviceId, sharedSecret: sharedSecret)
                        await client.setEncryptionRequired(encryptionPinned)
                        await client.setStreamEncryptionRequired(streamEncryptionPinned)
                        try await client.connect()

                        let response = try await client.pair(
                            deviceId: localDeviceId,
                            publicKey: publicKeyBase64,
                            name: localDeviceName
                        )

                        switch response.status {
                        case "approved":
                            let health = try await client.health()
                            return PairingExecutionResult(
                                privateKeyBase64: privateKey.rawRepresentation.base64EncodedString(),
                                connectionHost: candidateHost,
                                pairedMacName: health.hostname,
                                pairingResult: .approved
                            )

                        case "pending_approval":
                            return PairingExecutionResult(
                                privateKeyBase64: privateKey.rawRepresentation.base64EncodedString(),
                                connectionHost: candidateHost,
                                pairedMacName: candidateHost,
                                pairingResult: .pendingApproval
                            )

                        default:
                            throw PairingExecutionError.rejected
                        }
                    } catch {
                        lastError = error
                    }
                }

                throw lastError ?? BridgeError.connectionFailed
            }.value

            guard activePairingAttemptID == pairingAttemptID else {
                return nil
            }

            let pendingCandidate = PendingPairingCandidate(
                attemptID: pairingAttemptID,
                deviceId: localDeviceId,
                privateKeyBase64: result.privateKeyBase64,
                connectionHost: result.connectionHost,
                pairedMacName: result.pairedMacName,
                port: port,
                serverPublicKeyBase64: serverPublicKeyBase64,
                encryptionPinned: encryptionPinned,
                streamEncryptionPinned: streamEncryptionPinned
            )

            let shouldStorePairing =
                result.pairingResult == .approved ||
                !hadPairedMacsBeforePairing ||
                isRefreshingActivePairing(
                    hostname: result.connectionHost,
                    port: port,
                    serverPublicKey: serverPublicKeyBase64
                )
            var storedPairedMacId: String?
            if shouldStorePairing {
                storedPairedMacId = upsertPairedMac(
                    deviceId: localDeviceId,
                    hostname: result.connectionHost,
                    port: port,
                    pairedMacName: result.pairedMacName,
                    serverPublicKey: serverPublicKeyBase64,
                    privateKey: result.privateKeyBase64,
                    activate: true
                )

                TalkieAppSettings.shared.reloadFromDisk()
            } else {
                await client.clearAuth()
                loadPairing()
            }

            switch result.pairingResult {
            case .approved:
                activePairingAttemptID = nil
                stopPendingPairingApprovalMonitor()
                awaitingPairingApproval = false
                lastSuccessfulContactAt = .now
                updateActiveMacContactDate(.now)
                if let storedPairedMacId, await client.didNegotiateEncryption {
                    Self.pinEncryption(storedPairedMacId)
                }
                if let storedPairedMacId, await client.didNegotiateStreamEncryption {
                    Self.pinStreamEncryption(storedPairedMacId)
                }
                justCompletedPairing = true
                status = .connected
                startCompanionPolling()
                startCompanionEventStream()
                Task {
                    await refreshCompanionState()
                    await refreshPaths()
                    await refreshSessions()
                }

            case .pendingApproval:
                awaitingPairingApproval = true
                justCompletedPairing = false
                status = .disconnected
                log.info("Bridge pairing is waiting for Mac approval")
                startPendingPairingApprovalMonitor(candidate: pendingCandidate)
                if shouldStorePairing {
                    lastSuccessfulContactAt = nil
                    errorMessage = "Approve this iPhone on your Mac to finish pairing."
                } else {
                    errorMessage = "Approve this iPhone on your Mac to refresh pairing. Your current pairing is still saved."
                }
            }
            return result.pairingResult
        } catch {
            guard activePairingAttemptID == pairingAttemptID else {
                return nil
            }
            activePairingAttemptID = nil
            awaitingPairingApproval = false
            status = .error
            errorMessage = pairingErrorMessage(for: error, hostname: hostname)
            return nil
        }
    }

    func processNearbyMac(_ mac: NearbyMacBrowser.NearbyMac) async -> PairingResult? {
        do {
            let pairInfo = try await fetchNearbyPairInfo(from: mac)
            let qrData = QRCodeData(
                publicKey: pairInfo.publicKey,
                hostname: mac.connectionHost,
                alternateHosts: pairInfo.alternateHosts,
                port: mac.port,
                protocol: pairInfo.protocol,
                mode: pairInfo.mode ?? .nearby,
                pairingReady: pairInfo.pairingReady ?? true
            )
            return await processPairing(qrData: qrData)
        } catch {
            awaitingPairingApproval = false
            status = .error
            errorMessage = pairingErrorMessage(for: error, hostname: mac.name)
            return nil
        }
    }

    /// Connect using saved pairing with auto-retry
    // MARK: - Encryption pin (per-Mac downgrade protection)

    private static func encryptionPinKey(_ macId: String) -> String {
        "bridge.encryptionRequired.\(macId)"
    }

    static func isEncryptionPinned(_ macId: String) -> Bool {
        guard !macId.isEmpty else { return false }
        return UserDefaults.standard.bool(forKey: encryptionPinKey(macId))
    }

    static func pinEncryption(_ macId: String) {
        guard !macId.isEmpty else { return }
        UserDefaults.standard.set(true, forKey: encryptionPinKey(macId))
    }

    static func clearEncryptionPin(_ macId: String) {
        guard !macId.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: encryptionPinKey(macId))
    }

    // Stream (SSE/WS per-frame) encryption pin — tracked separately from the body
    // pin because an older server may legitimately support body encryption only.
    private static func streamEncryptionPinKey(_ macId: String) -> String {
        "bridge.streamEncryptionRequired.\(macId)"
    }

    static func isStreamEncryptionPinned(_ macId: String) -> Bool {
        guard !macId.isEmpty else { return false }
        return UserDefaults.standard.bool(forKey: streamEncryptionPinKey(macId))
    }

    static func pinStreamEncryption(_ macId: String) {
        guard !macId.isEmpty else { return }
        UserDefaults.standard.set(true, forKey: streamEncryptionPinKey(macId))
    }

    static func clearStreamEncryptionPin(_ macId: String) {
        guard !macId.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: streamEncryptionPinKey(macId))
    }

    func connect() async {
        retryTask?.cancel()
        retryTask = nil

        guard let bridgeConfiguration = activePairedMac else { return }

        guard !bridgeConfiguration.hostname.isEmpty else { return }
        guard bridgeConfiguration.port > 0 else { return }
        let hostname = bridgeConfiguration.hostname
        let port = bridgeConfiguration.port
        let configuredDeviceId = deviceId
        let privateKeyBase64 = bridgeConfiguration.privateKey
        let serverPublicKeyBase64 = bridgeConfiguration.serverPublicKey
        let deviceClass = currentDeviceClass
        let macId = bridgeConfiguration.id
        let encryptionPinned = Self.isEncryptionPinned(macId)
        let streamEncryptionPinned = Self.isStreamEncryptionPinned(macId)

        status = .connecting
        errorMessage = nil
        lastConnectionAuthFailed = false

        do {
            let health = try await Task.detached(priority: .userInitiated) { [client] in
                await client.configure(hostname: hostname, port: port)
                try await Self.restoreAuth(
                    client: client,
                    deviceId: configuredDeviceId,
                    privateKeyBase64: privateKeyBase64,
                    serverPublicKeyBase64: serverPublicKeyBase64
                )
                // Apply the per-Mac encryption pins so client.connect() refuses a
                // plaintext downgrade if this Mac has used encryption before.
                await client.setEncryptionRequired(encryptionPinned)
                await client.setStreamEncryptionRequired(streamEncryptionPinned)
                try await client.connect()
                _ = try await client.companionState(
                    deviceId: configuredDeviceId,
                    deviceClass: deviceClass
                )
                return try await client.health()
            }.value

            let resolvedMacName = resolvedPairedMacName(from: health.hostname)
            pairedMacName = resolvedMacName
            updateStoredActiveMacName(resolvedMacName)
            TalkieAppSettings.shared.reloadFromDisk()
            activePairingAttemptID = nil
            stopPendingPairingApprovalMonitor()
            awaitingPairingApproval = false
            lastSuccessfulContactAt = .now
            updateActiveMacContactDate(.now)
            // Pin encryption for this Mac the first time it negotiates a sealed
            // connection — future connects then refuse a plaintext downgrade.
            if await client.didNegotiateEncryption {
                Self.pinEncryption(macId)
            }
            if await client.didNegotiateStreamEncryption {
                Self.pinStreamEncryption(macId)
            }
            status = .connected
            retryCount = 0
            startCompanionPolling()
            startCompanionEventStream()
            Task {
                await refreshCompanionState()
                await refreshPaths()
                await refreshSessions()
            }
        } catch BridgeError.notConfigured {
            status = .error
            errorMessage = "Auth keys missing - please re-pair"
            retryCount = maxRetries
        } catch BridgeError.httpError(401, detail: _) {
            lastConnectionAuthFailed = true
            status = .error
            if awaitingPairingApproval {
                errorMessage = "Approve this device on your Mac to finish pairing."
            } else {
                errorMessage = "This Mac no longer recognizes this device. Scan a fresh pairing code to reconnect."
            }
            retryCount = 0
        } catch {
            status = .error
            errorMessage = "Could not connect to Mac"
            scheduleRetry()
        }
    }

    private func startPendingPairingApprovalMonitor(candidate: PendingPairingCandidate) {
        pendingPairingApprovalTask?.cancel()
        let approvalClient = BridgeClient()
        pendingPairingApprovalTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled && self.awaitingPairingApproval {
                try? await Task.sleep(for: .seconds(2))
                guard
                    !Task.isCancelled,
                    self.awaitingPairingApproval,
                    self.activePairingAttemptID == candidate.attemptID
                else {
                    return
                }

                let approved = await self.isPairingApproved(
                    candidate,
                    using: approvalClient
                )
                guard
                    approved,
                    !Task.isCancelled,
                    self.activePairingAttemptID == candidate.attemptID
                else {
                    continue
                }

                self.pendingPairingApprovalTask = nil
                await self.completeApprovedPairing(candidate)
                return
            }
        }
    }

    private func isPairingApproved(
        _ candidate: PendingPairingCandidate,
        using approvalClient: BridgeClient
    ) async -> Bool {
        do {
            await approvalClient.configure(
                hostname: candidate.connectionHost,
                port: candidate.port
            )
            try await Self.restoreAuth(
                client: approvalClient,
                deviceId: candidate.deviceId,
                privateKeyBase64: candidate.privateKeyBase64,
                serverPublicKeyBase64: candidate.serverPublicKeyBase64
            )
            await approvalClient.setEncryptionRequired(candidate.encryptionPinned)
            await approvalClient.setStreamEncryptionRequired(candidate.streamEncryptionPinned)
            try await approvalClient.connect()
            _ = try await approvalClient.companionState(deviceId: candidate.deviceId)
            return true
        } catch BridgeError.httpError(let statusCode, detail: _) where statusCode == 401 {
            return false
        } catch {
            return false
        }
    }

    private func completeApprovedPairing(_ candidate: PendingPairingCandidate) async {
        guard activePairingAttemptID == candidate.attemptID else { return }

        _ = upsertPairedMac(
            deviceId: candidate.deviceId,
            hostname: candidate.connectionHost,
            port: candidate.port,
            pairedMacName: candidate.pairedMacName,
            serverPublicKey: candidate.serverPublicKeyBase64,
            privateKey: candidate.privateKeyBase64,
            activate: true
        )
        TalkieAppSettings.shared.reloadFromDisk()
        activePairingAttemptID = nil
        awaitingPairingApproval = false
        log.info("Mac approval confirmed; completing Bridge pairing")

        await client.clearAuth()
        await connect()
        justCompletedPairing = status == .connected
    }

    private func stopPendingPairingApprovalMonitor() {
        pendingPairingApprovalTask?.cancel()
        pendingPairingApprovalTask = nil
    }

    func retry() async {
        retryCount = 0
        await connect()
    }

    func disconnect() {
        retryTask?.cancel()
        retryTask = nil
        autoReconnectTask?.cancel()
        autoReconnectTask = nil
        companionPollTask?.cancel()
        companionPollTask = nil
        stopPendingPairingApprovalMonitor()
        stopCompanionEventStream()
        lastReportedSetupState = nil
        lastCompanionShortcutSurfaceRequestKey = nil
        retryCount = 0
        status = .disconnected
        sessions = []
        projectPaths = []
        windows = []
        windowCaptures = []
        companionState = nil
    }

    func unpair() {
        guard let activePairedMacID else {
            disconnect()
            for mac in configurationStore.configuration.bridge.pairedMacs {
                privateKeyStore.delete(id: mac.id)
            }
            configurationStore.update { configuration in
                configuration.bridge = .init()
            }
            TalkieAppSettings.shared.reloadFromDisk()
            pairedMacName = nil
            lastSuccessfulContactAt = nil
            awaitingPairingApproval = false
            errorMessage = nil
            lastConnectionAuthFailed = false
            stopPendingPairingApprovalMonitor()

            Task {
                await client.clearAuth()
            }
            return
        }

        removePairedMac(id: activePairedMacID)
    }

    func setError(_ message: String) {
        status = .error
        errorMessage = message
    }

    func activatePairedMac(id: String) async {
        guard hasPairedMacs else { return }
        let bridgeConfiguration = configurationStore.configuration.bridge
        guard bridgeConfiguration.pairedMacs.contains(where: { $0.id == id }) else { return }

        if activePairedMacID == id {
            if status == .disconnected || status == .error {
                await connect()
            }
            return
        }

        disconnect()
        configurationStore.update { configuration in
            configuration.bridge.activePairedMacID = id
            if let index = configuration.bridge.pairedMacs.firstIndex(where: { $0.id == id }) {
                configuration.bridge.pairedMacs[index].lastSelectedAt = Date().timeIntervalSince1970
            }
        }
        await client.clearAuth()
        loadPairing()
        TalkieAppSettings.shared.reloadFromDisk()
        await connect()
    }

    func activateAdjacentPairedMac(offset: Int) async {
        let macs = pairedMacs
        guard macs.count > 1 else { return }
        guard let activeID = activePairedMacID,
              let currentIndex = macs.firstIndex(where: { $0.id == activeID }) else {
            await activatePairedMac(id: macs[0].id)
            return
        }

        let nextIndex = (currentIndex + offset + macs.count) % macs.count
        await activatePairedMac(id: macs[nextIndex].id)
    }

    func removePairedMac(id: String) {
        let wasActive = activePairedMacID == id
        if wasActive {
            lastConnectionAuthFailed = false
        }
        disconnect()

        privateKeyStore.delete(id: id)
        // Drop the encryption pins so re-pairing this Mac on a trusted network
        // can re-negotiate cleanly.
        Self.clearEncryptionPin(id)
        Self.clearStreamEncryptionPin(id)
        configurationStore.update { configuration in
            configuration.bridge.pairedMacs.removeAll(where: { $0.id == id })
            if configuration.bridge.pairedMacs.isEmpty {
                configuration.bridge.activePairedMacID = ""
            } else if wasActive || !configuration.bridge.pairedMacs.contains(where: { $0.id == configuration.bridge.activePairedMacID }) {
                configuration.bridge.activePairedMacID = configuration.bridge.pairedMacs[0].id
                configuration.bridge.pairedMacs[0].lastSelectedAt = Date().timeIntervalSince1970
            }
        }

        loadPairing()
        TalkieAppSettings.shared.reloadFromDisk()
        errorMessage = nil

        Task {
            await client.clearAuth()
            if self.isPaired {
                await self.connect()
            }
        }
    }

    func refreshSessions() async {
        guard status == .connected else { return }

        do {
            let response = try await client.sessions()
            sessions = response.sessions
        } catch {
            log.debug("Failed to refresh sessions: \(error.localizedDescription)")
        }
    }

    func refreshPaths() async {
        guard status == .connected else {
            log.debug("refreshPaths: not connected, skipping")
            return
        }

        do {
            let response = try await client.paths()
            log.debug("refreshPaths: got \(response.paths.count) paths")
            projectPaths = response.paths
        } catch {
            log.warning("refreshPaths failed: \(error.localizedDescription)")
        }
    }

    func getMessages(sessionId: String) async throws -> [SessionMessage] {
        let response = try await client.sessionMessages(id: sessionId)
        return response.messages
    }

    func sendMessage(sessionId: String, text: String) async throws {
        let response = try await client.sendMessage(sessionId: sessionId, text: text)
        if !response.success {
            throw BridgeError.messageFailed(response.error ?? "Unknown error")
        }
    }

    func triggerCompanionShortcut(_ shortcutID: String) async throws -> CompanionTriggerResponse {
        guard isPaired else {
            throw BridgeError.notConfigured
        }

        if status != .connected {
            await connect()
        }

        guard status == .connected else {
            throw BridgeError.connectionFailed
        }

        let response = try await client.companionTrigger(shortcutId: shortcutID)
        lastSuccessfulContactAt = .now
        updateActiveMacContactDate(.now)
        return response
    }

    func activateCompanionApp(_ app: CompanionAppSwitcherApp) async throws -> CompanionTriggerResponse {
        guard isPaired else {
            throw BridgeError.notConfigured
        }

        if status != .connected {
            await connect()
        }

        guard status == .connected else {
            throw BridgeError.connectionFailed
        }

        let response = try await client.companionActivateApp(
            processIdentifier: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier
        )
        lastSuccessfulContactAt = .now
        updateActiveMacContactDate(.now)
        await refreshCompanionState()
        return response
    }

    func sendCompanionTrackpad(
        event: BridgeClient.TrackpadEvent,
        dx: Double = 0,
        dy: Double = 0
    ) async throws {
        guard isPaired else {
            throw BridgeError.notConfigured
        }

        if status != .connected {
            await connect()
        }

        guard status == .connected else {
            throw BridgeError.connectionFailed
        }

        try await client.companionTrackpad(event: event, dx: dx, dy: dy)
        lastSuccessfulContactAt = .now
        updateActiveMacContactDate(.now)
    }

    func sendCompanionImageToMac(
        imageData: Data,
        mimeType: String,
        autoPaste: Bool = true
    ) async throws -> CompanionTriggerResponse {
        guard isPaired else {
            throw BridgeError.notConfigured
        }

        if status != .connected {
            await connect()
        }

        guard status == .connected else {
            throw BridgeError.connectionFailed
        }

        let response = try await client.companionPasteImage(
            imageData: imageData,
            mimeType: mimeType,
            autoPaste: autoPaste
        )
        lastSuccessfulContactAt = .now
        updateActiveMacContactDate(.now)
        return response
    }

    func terminalAccessPayload() async throws -> SSHPrivateKeyQRCodePayload {
        guard isPaired else {
            throw BridgeError.notConfigured
        }

        if status != .connected {
            await connect()
        }

        guard status == .connected else {
            throw BridgeError.connectionFailed
        }

        let response = try await client.terminalAccessPayload()
        lastSuccessfulContactAt = .now
        updateActiveMacContactDate(.now)

        guard response.ok, let payload = response.payload else {
            throw BridgeError.messageFailed(response.error ?? "Terminal access preparation failed")
        }

        return try await SSHPrivateKeyQRCodePayload.decode(from: payload)
    }

    func sendMessageWithImage(sessionId: String, text: String, image: UIImage) async throws {
        try await sendMessage(sessionId: sessionId, text: text)
    }

    func sendAudio(sessionId: String, audioURL: URL) async throws -> String {
        let response = try await sendAudioWithResponse(sessionId: sessionId, audioURL: audioURL)
        return response.transcript ?? ""
    }

    func sendAudioWithResponse(sessionId: String, audioURL: URL) async throws -> MessageResponse {
        let audioData = try Data(contentsOf: audioURL)
        let response = try await client.sendAudio(sessionId: sessionId, audioData: audioData)
        if !response.success {
            throw BridgeError.messageFailed(response.error ?? "Unknown error")
        }
        return response
    }

    func forceEnter(sessionId: String) async throws {
        let response = try await client.forceEnter(sessionId: sessionId)
        if !response.success {
            throw BridgeError.messageFailed(response.error ?? "Unknown error")
        }
    }

    func sendMemoAttachments(
        memoId: String,
        body: MemoAttachmentUploadRequest
    ) async throws -> MemoAttachmentUploadResponse {
        guard isPaired else {
            throw BridgeError.notConfigured
        }

        if status != .connected {
            await connect()
        }

        guard status == .connected else {
            throw BridgeError.connectionFailed
        }

        let response = try await client.sendMemoAttachments(memoId: memoId, body: body)
        lastSuccessfulContactAt = .now
        return response
    }

    func sendMemo(body: MemoTransferRequest) async throws -> MemoTransferResponse {
        guard isPaired else {
            throw BridgeError.notConfigured
        }

        if status != .connected {
            await connect()
        }

        guard status == .connected else {
            throw BridgeError.connectionFailed
        }

        let response = try await client.sendMemo(body: body)
        lastSuccessfulContactAt = .now
        updateActiveMacContactDate(.now)
        return response
    }

    func sendHyperScanCapture(
        body: HyperScanUploadRequest
    ) async throws -> HyperScanUploadResponse {
        guard isPaired else {
            throw BridgeError.notConfigured
        }

        if status != .connected {
            await connect()
        }

        guard status == .connected else {
            throw BridgeError.connectionFailed
        }

        let response = try await client.sendHyperScanCapture(body: body)
        lastSuccessfulContactAt = .now
        return response
    }

    func executeCLI(
        command: String,
        timeout: Int = 30_000
    ) async throws -> CLIResponse {
        guard isPaired else {
            throw BridgeError.notConfigured
        }

        if status != .connected {
            await connect()
        }

        guard status == .connected else {
            throw BridgeError.connectionFailed
        }

        let response = try await client.executeCLI(command: command, timeout: timeout)
        lastSuccessfulContactAt = .now
        updateActiveMacContactDate(.now)
        return response
    }

    func composeRevision(
        text: String,
        instruction: String
    ) async throws -> ComposeRevisionResult {
        guard isPaired else {
            throw BridgeError.notConfigured
        }

        if status != .connected {
            await connect()
        }

        guard status == .connected else {
            throw BridgeError.connectionFailed
        }

        let response = try await client.composeRevision(
            body: ComposeRevisionRequest(text: text, instruction: instruction)
        )
        lastSuccessfulContactAt = .now

        guard response.ok, let result = response.result else {
            throw BridgeError.messageFailed(response.error ?? "Compose revision failed")
        }

        return result
    }

    func configuredInference(messages: [InferenceMessage]) async throws -> InferenceResult {
        guard isPaired else {
            throw BridgeError.notConfigured
        }

        if status != .connected {
            await connect()
        }

        guard status == .connected else {
            throw BridgeError.connectionFailed
        }

        let result = try await client.configuredInference(messages: messages)
        lastSuccessfulContactAt = .now
        updateActiveMacContactDate(.now)
        return result
    }

    func composeCommand(
        context: String,
        instruction: String,
        title: String? = nil,
        sourceDescription: String? = nil
    ) async throws -> ComposeCommandResult {
        guard isPaired else {
            throw BridgeError.notConfigured
        }

        if status != .connected {
            await connect()
        }

        guard status == .connected else {
            throw BridgeError.connectionFailed
        }

        let response = try await client.composeCommand(
            body: ComposeCommandRequest(
                context: context,
                instruction: instruction,
                title: title,
                sourceDescription: sourceDescription
            )
        )
        lastSuccessfulContactAt = .now

        guard response.ok, let result = response.result else {
            throw BridgeError.messageFailed(response.error ?? "AI command failed")
        }

        return result
    }

    func composeBorrowedProvider() async throws -> ComposeBorrowedProvider {
        guard isPaired else {
            throw BridgeError.notConfigured
        }

        if status != .connected {
            await connect()
        }

        guard status == .connected else {
            throw BridgeError.connectionFailed
        }

        let provider = try await client.composeBorrowedProvider()
        lastSuccessfulContactAt = .now
        return provider
    }

    func composeDirectOptions() async throws -> ComposeDirectOptionsResult {
        guard isPaired else {
            throw BridgeError.notConfigured
        }

        if status != .connected {
            await connect()
        }

        guard status == .connected else {
            throw BridgeError.connectionFailed
        }

        let result = try await client.composeDirectOptions()
        lastSuccessfulContactAt = .now
        return result
    }

    func composeBorrowedProvider(
        providerId: String?,
        modelId: String?
    ) async throws -> ComposeBorrowedProvider {
        guard isPaired else {
            throw BridgeError.notConfigured
        }

        if status != .connected {
            await connect()
        }

        guard status == .connected else {
            throw BridgeError.connectionFailed
        }

        let provider = try await client.composeBorrowedProvider(providerId: providerId, modelId: modelId)
        lastSuccessfulContactAt = .now
        return provider
    }

    func importAIProviderCredentialsFromMac() async throws -> TalkieAIProviderCredentialIngestor.ImportResult {
        credentialImportEvents = []
        recordCredentialImportEvent("Starting secure import from \(pairedMacDisplayName ?? "paired Mac").")

        do {
            let result = try await importAIProviderCredentialsFromMacOnce()
            recordCredentialImportEvent(
                "Saved \(result.providerName) credentials for \(result.modelId).",
                level: .success
            )
            return result
        } catch BridgeError.httpError(401, detail: _) {
            recordCredentialImportEvent(
                "The Mac rejected this iPhone's stored bridge signature.",
                level: .warning
            )
            return try await refreshPairingAndRetryAIProviderImport()
        } catch BridgeError.connectionFailed where lastConnectionAuthFailed {
            recordCredentialImportEvent(
                "The saved Mac pairing could not prove its bridge signature.",
                level: .warning
            )
            return try await refreshPairingAndRetryAIProviderImport()
        } catch {
            recordCredentialImportEvent(credentialImportDiagnosticMessage(for: error), level: .warning)
            throw error
        }
    }

    private func refreshPairingAndRetryAIProviderImport() async throws -> TalkieAIProviderCredentialIngestor.ImportResult {
        recordCredentialImportEvent("Sending a fresh pairing request to the Mac.")
        let repairResult: PairingResult
        do {
            repairResult = try await refreshActivePairingForCredentialImport()
        } catch {
            recordCredentialImportEvent(credentialImportDiagnosticMessage(for: error), level: .warning)
            throw error
        }

        guard repairResult == .approved else {
            recordCredentialImportEvent(
                "Waiting for approval in Talkie on the Mac.",
                level: .warning
            )
            throw PairingExecutionError.pendingApproval
        }

        recordCredentialImportEvent("Pairing refreshed. Retrying credential import.")
        do {
            let result = try await importAIProviderCredentialsFromMacOnce()
            recordCredentialImportEvent(
                "Saved \(result.providerName) credentials for \(result.modelId).",
                level: .success
            )
            return result
        } catch {
            recordCredentialImportEvent(credentialImportDiagnosticMessage(for: error), level: .warning)
            throw error
        }
    }

    private func importAIProviderCredentialsFromMacOnce() async throws -> TalkieAIProviderCredentialIngestor.ImportResult {
        recordCredentialImportEvent("Asking the Mac for its configured AI provider.")
        let provider = try await composeBorrowedProvider(providerId: nil, modelId: nil)
        recordCredentialImportEvent("Received encrypted \(provider.providerName) provider payload.")

        let payload = TalkieAIProviderCredentialPayload(
            providerId: provider.providerId,
            providerName: provider.providerName,
            modelId: provider.modelId,
            apiKey: provider.apiKey,
            assistantPrompt: provider.assistantPrompt
        )
        return try await TalkieAIProviderCredentialIngestor.shared.ingest(.directCredential(payload))
    }

    func refreshWindows() async {
        guard status == .connected else { return }

        do {
            let response = try await client.windows()
            windows = response.windows
        } catch {
            log.debug("Failed to refresh windows: \(error.localizedDescription)")
        }
    }

    func refreshWindowCaptures() async {
        guard status == .connected else { return }

        do {
            let response = try await client.windowCaptures()
            windowCaptures = response.screenshots
        } catch {
            log.debug("Failed to capture windows: \(error.localizedDescription)")
        }
    }

    func refreshWindowCapturesWithError() async throws {
        guard status == .connected else {
            throw BridgeError.notConfigured
        }

        let response = try await client.windowCaptures()
        windowCaptures = response.screenshots
    }

    func getWindowScreenshot(windowId: UInt32) async throws -> Data {
        try await client.windowScreenshot(windowId: windowId)
    }

    func refreshAll() async {
        await refreshPaths()
        await refreshSessions()
        await refreshWindows()
        await refreshCompanionState()
    }

    func setCompanionDeckVisible(_ isVisible: Bool) {
        guard isCompanionDeckVisible != isVisible else { return }
        isCompanionDeckVisible = isVisible
        applyCompanionPollingMode(refreshImmediately: isVisible)
    }

    func setCompanionRuntimeActive(_ isActive: Bool) {
        guard isCompanionRuntimeActive != isActive else { return }
        isCompanionRuntimeActive = isActive
        applyCompanionPollingMode(refreshImmediately: isActive)
    }

    func refreshCompanionState() async {
        guard status == .connected else {
            await applyCompanionState(nil)
            lastReportedSetupState = nil
            pendingCompanionRefresh = false
            return
        }

        if isRefreshingCompanionState {
            pendingCompanionRefresh = true
            return
        }

        isRefreshingCompanionState = true
        pendingCompanionRefresh = false

        defer {
            isRefreshingCompanionState = false
            let shouldRunPendingRefresh = pendingCompanionRefresh && status == .connected
            pendingCompanionRefresh = false

            if shouldRunPendingRefresh {
                Task { @MainActor in
                    await refreshCompanionState()
                }
            }
        }

        do {
            let nextState = try await client.companionState(
                deviceId: deviceId,
                deviceClass: currentDeviceClass
            )

            await applyCompanionState(nextState)
        } catch {
            log.debug("Failed to refresh companion state: \(error.localizedDescription)")
        }
    }

    func acknowledgeSecurityEvent(id: String) async {
        guard status == .connected else { return }

        do {
            try await client.acknowledgeSecurityEvent(id: id)
            await refreshCompanionState()
        } catch {
            log.debug("Failed to acknowledge security event: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func fetchNearbyPairInfo(from mac: NearbyMacBrowser.NearbyMac) async throws -> QRCodeData {
        var components = URLComponents()
        components.scheme = "http"
        components.host = mac.connectionHost
        components.port = mac.port
        components.path = "/pair/info"

        guard let url = components.url else {
            throw BridgeError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BridgeError.invalidResponse
        }

        return try JSONDecoder().decode(QRCodeData.self, from: data)
    }

    private func applyCompanionPollingMode(refreshImmediately: Bool = false) {
        guard status == .connected else { return }

        startCompanionPolling()

        if refreshImmediately {
            Task { @MainActor in
                await refreshCompanionState()
            }
        }
    }

    private func startCompanionPolling() {
        companionPollTask?.cancel()
        companionPollTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await self.refreshCompanionState()
                try? await Task.sleep(for: self.companionPollingInterval)
            }
        }
    }

    private func startCompanionEventStream() {
        companionEventTask?.cancel()
        companionEventSocket?.cancel(with: .goingAway, reason: nil)
        companionEventSocket = nil
        updateCompanionEventStreamStatus(false)

        companionEventTask = Task { [weak self] in
            await self?.runCompanionEventStream()
        }
    }

    private func stopCompanionEventStream() {
        companionEventTask?.cancel()
        companionEventTask = nil
        companionEventSocket?.cancel(with: .normalClosure, reason: nil)
        companionEventSocket = nil
        isCompanionEventStreamConnected = false
    }

    private func updateCompanionEventStreamStatus(_ isConnected: Bool) {
        guard isCompanionEventStreamConnected != isConnected else { return }
        isCompanionEventStreamConnected = isConnected
        applyCompanionPollingMode()
    }

    private func runCompanionEventStream() async {
        while !Task.isCancelled {
            guard status == .connected else { return }

            do {
                let request = try await client.companionEventsRequest(
                    deviceId: deviceId,
                    deviceClass: currentDeviceClass
                )
                companionEventStreamEncrypted = await client.streamsAreEncrypted

                let socket = URLSession.shared.webSocketTask(with: request)
                companionEventSocket = socket
                socket.resume()

                while !Task.isCancelled && status == .connected {
                    let message = try await socket.receive()
                    try Task.checkCancellation()
                    await handleCompanionEventMessage(message)
                }
            } catch is CancellationError {
                return
            } catch {
                if status != .connected {
                    return
                }

                updateCompanionEventStreamStatus(false)
                log.debug("Companion events stream disconnected: \(error.localizedDescription)")
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func handleCompanionEventMessage(_ message: URLSessionWebSocketTask.Message) async {
        let raw: Data

        switch message {
        case .string(let text):
            guard let textData = text.data(using: .utf8) else { return }
            raw = textData
        case .data(let bytes):
            raw = bytes
        @unknown default:
            return
        }

        // Encrypted stream: every frame is a sealed envelope. Open it and drop
        // fail-closed if it can't be opened (never accept a plaintext frame).
        let data: Data
        if companionEventStreamEncrypted {
            guard let opened = try? await client.openStreamFrame(raw) else {
                return
            }
            data = opened
        } else {
            data = raw
        }

        guard let envelope = try? JSONDecoder().decode(CompanionEventEnvelope.self, from: data) else {
            return
        }

        switch envelope.type {
        case "companion:ready", "companion:update":
            updateCompanionEventStreamStatus(true)
            if let snapshot = envelope.snapshot {
                await applyCompanionState(snapshot)
            }
        case "companion:error":
            log.debug("Companion events stream reported error: \(envelope.error ?? "unknown error")")
        default:
            break
        }
    }

    private func applyCompanionState(_ nextState: CompanionStateResponse?) async {
        if companionState != nextState {
            companionState = nextState
        }

        DeckMirrorStore.shared.apply(companionState: nextState)
        notifyIfCompanionShortcutSurfaceRequested(nextState)

        try? await reportDeviceSetupStateIfNeeded()
    }

    private func notifyIfCompanionShortcutSurfaceRequested(_ nextState: CompanionStateResponse?) {
        guard status == .connected,
              TalkieAppSettings.shared.followComputerShortcutMode,
              nextState?.isAvailable == true,
              nextState?.requestedSurface == .shortcut else {
            lastCompanionShortcutSurfaceRequestKey = nil
            return
        }

        let requestKey = [
            activePairedMacID ?? "",
            String(nextState?.publishRevision ?? 0),
            nextState?.lastPublishedAt ?? ""
        ].joined(separator: "|")

        guard requestKey != lastCompanionShortcutSurfaceRequestKey else { return }
        lastCompanionShortcutSurfaceRequestKey = requestKey

        NotificationCenter.default.post(name: .companionShortcutSurfaceRequested, object: nil)
    }

    private func currentDeviceSetupState() -> DeviceSetupStateRequest {
        let appSettings = TalkieAppSettings.shared
        let pairedMacLabel = pairedMacName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let currentHostname = pairedHostname?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let savedHosts = SSHTerminalSavedHostStore().load()

        let terminalHost = savedHosts.first(where: { savedHost in
            if let currentHostname, savedHost.normalizedHost == currentHostname {
                return true
            }

            if let pairedMacLabel,
               let label = savedHost.deviceLabel?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               !label.isEmpty,
               label.contains(pairedMacLabel) {
                return true
            }

            return false
        })?.host

        let companionSurfaceActive =
            status == .connected &&
            appSettings.followComputerShortcutMode &&
            companionState?.isAvailable == true &&
            companionState?.requestedSurface == .shortcut

        return DeviceSetupStateRequest(
            followComputerShortcutMode: appSettings.followComputerShortcutMode,
            companionSurfaceActive: companionSurfaceActive,
            terminalImported: terminalHost != nil,
            terminalHost: terminalHost
        )
    }

    private func reportDeviceSetupStateIfNeeded(force: Bool = false) async throws {
        guard status == .connected else { return }

        let snapshot = currentDeviceSetupState()
        if !force, snapshot == lastReportedSetupState {
            return
        }

        try await client.updateDeviceSetupState(snapshot)
        lastReportedSetupState = snapshot
    }

    private func scheduleRetry() {
        guard retryCount < maxRetries else {
            log.debug("BridgeManager: Max retries (\(maxRetries)) reached")
            return
        }

        retryCount += 1
        let delay = baseRetryDelayNs * UInt64(1 << (retryCount - 1))
        log.debug("BridgeManager: Scheduling retry \(retryCount)/\(maxRetries) in \(delay / 1_000_000_000)s")

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

    private static func restoreAuth(
        client: BridgeClient,
        deviceId: String,
        privateKeyBase64: String,
        serverPublicKeyBase64: String
    ) async throws {
        guard !privateKeyBase64.isEmpty,
              !serverPublicKeyBase64.isEmpty,
              let privateKeyData = Data(base64Encoded: privateKeyBase64),
              let serverPublicKeyData = Data(base64Encoded: serverPublicKeyBase64) else {
            throw BridgeError.notConfigured
        }

        let privateKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)
        let serverPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: serverPublicKeyData)
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: serverPublicKey)
        await client.configureAuth(deviceId: deviceId, sharedSecret: sharedSecret)
    }

    private func loadPairing() {
        let bridgeConfiguration = configurationStore.configuration.bridge
        let activeMac = bridgeConfiguration.pairedMacs.first(where: { $0.id == bridgeConfiguration.activePairedMacID })
            ?? bridgeConfiguration.pairedMacs.first
        activePairedMacID = activeMac?.id
        pairedMacName = sanitizedMacName(activeMac?.pairedMacName)
        if let timestamp = activeMac?.lastSuccessfulContactAt, timestamp > 0 {
            lastSuccessfulContactAt = Date(timeIntervalSince1970: timestamp)
        } else {
            lastSuccessfulContactAt = nil
        }
    }

    private func pairingErrorMessage(for error: Error, hostname: String) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .dnsLookupFailed:
                return "Couldn’t find \(hostname). Make sure this iPhone is on the same network or can reach that Mac over Tailscale."
            case .cannotConnectToHost, .networkConnectionLost, .timedOut, .notConnectedToInternet:
                return "Couldn’t reach \(hostname). Make sure Talkie Bridge is running and this iPhone can reach it locally or over Tailscale."
            default:
                break
            }
        }

        return error.localizedDescription
    }

    private func pairingValidationError(for qrData: QRCodeData) -> String? {
        if qrData.mode == .localDev || qrData.pairingReady == false {
            return "This Mac is running a bridge that can’t be paired. Restart Mac Bridge, then try again."
        }

        if qrData.hostname == "localhost" {
            return "This QR code is advertising localhost, which only works on the Mac itself. Restart Mac Bridge, then scan a fresh QR code."
        }

        return nil
    }

    private func pairingCandidateHosts(for qrData: QRCodeData) -> [String] {
        var seen = Set<String>()
        var hosts: [String] = []

        for host in [qrData.hostname] + (qrData.alternateHosts ?? []) {
            let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !normalized.isEmpty else { continue }
            guard seen.insert(normalized.lowercased()).inserted else { continue }
            hosts.append(normalized)
        }

        return hosts
    }

    private func pairedMacMatchingPairing(
        serverPublicKey: String,
        candidateHosts: [String],
        port: Int
    ) -> PairedMac? {
        let bridgeConfiguration = configurationStore.configuration.bridge
        let normalizedCandidateHosts = Set(candidateHosts.map(Self.normalizedPairingHost).filter { !$0.isEmpty })

        if let activeMac = bridgeConfiguration.pairedMacs.first(where: { $0.id == bridgeConfiguration.activePairedMacID }) {
            if !serverPublicKey.isEmpty, activeMac.serverPublicKey == serverPublicKey {
                return activeMac
            }

            if activeMac.port == port,
               normalizedCandidateHosts.contains(Self.normalizedPairingHost(activeMac.hostname)) {
                return activeMac
            }
        }

        if let hostMatch = bridgeConfiguration.pairedMacs.first(where: { mac in
            mac.port == port && normalizedCandidateHosts.contains(Self.normalizedPairingHost(mac.hostname))
        }) {
            return hostMatch
        }

        if !serverPublicKey.isEmpty,
           let keyMatch = bridgeConfiguration.pairedMacs.first(where: { $0.serverPublicKey == serverPublicKey }) {
            return keyMatch
        }

        return nil
    }

    private static func normalizedPairingHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    private func isRefreshingActivePairing(
        hostname: String,
        port: Int,
        serverPublicKey: String
    ) -> Bool {
        guard let activePairedMac else { return false }

        if !serverPublicKey.isEmpty, activePairedMac.serverPublicKey == serverPublicKey {
            return true
        }

        return activePairedMac.hostname == hostname && activePairedMac.port == port
    }

    private func refreshActivePairingForCredentialImport() async throws -> PairingResult {
        guard let activePairedMac else {
            throw BridgeError.notConfigured
        }

        let hostname = activePairedMac.hostname
        let port = activePairedMac.port
        let serverPublicKeyBase64 = activePairedMac.serverPublicKey
        let currentName = sanitizedMacName(activePairedMac.pairedMacName) ?? activePairedMac.hostname
        let encryptionPinned = Self.isEncryptionPinned(activePairedMac.id)
        let streamEncryptionPinned = Self.isStreamEncryptionPinned(activePairedMac.id)

        guard !hostname.isEmpty, port > 0, !serverPublicKeyBase64.isEmpty else {
            throw BridgeError.notConfigured
        }

        status = .connecting
        errorMessage = nil
        awaitingPairingApproval = false

        let localDeviceId = deviceId
        let localDeviceName = deviceName

        recordCredentialImportEvent("Preparing a new device key for \(currentName).")
        let result = try await Task.detached(priority: .userInitiated) { [client] in
            guard let serverPublicKeyData = Data(base64Encoded: serverPublicKeyBase64) else {
                throw BridgeError.invalidResponse
            }

            let serverPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: serverPublicKeyData)
            await client.configure(hostname: hostname, port: port)

            let privateKey = P256.KeyAgreement.PrivateKey()
            let publicKeyBase64 = privateKey.publicKey.x963Representation.base64EncodedString()
            let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: serverPublicKey)

            await client.configureAuth(deviceId: localDeviceId, sharedSecret: sharedSecret)
            await client.setEncryptionRequired(encryptionPinned)
            await client.setStreamEncryptionRequired(streamEncryptionPinned)
            try await client.connect()

            let response = try await client.pair(
                deviceId: localDeviceId,
                publicKey: publicKeyBase64,
                name: localDeviceName
            )

            switch response.status {
            case "approved":
                let health = try await client.health()
                return PairingExecutionResult(
                    privateKeyBase64: privateKey.rawRepresentation.base64EncodedString(),
                    connectionHost: hostname,
                    pairedMacName: health.hostname,
                    pairingResult: .approved
                )

            case "pending_approval":
                return PairingExecutionResult(
                    privateKeyBase64: privateKey.rawRepresentation.base64EncodedString(),
                    connectionHost: hostname,
                    pairedMacName: currentName,
                    pairingResult: .pendingApproval
                )

            default:
                throw PairingExecutionError.rejected
            }
        }.value

        let pendingCandidate = PendingPairingCandidate(
            attemptID: UUID(),
            deviceId: localDeviceId,
            privateKeyBase64: result.privateKeyBase64,
            connectionHost: result.connectionHost,
            pairedMacName: result.pairedMacName,
            port: port,
            serverPublicKeyBase64: serverPublicKeyBase64,
            encryptionPinned: encryptionPinned,
            streamEncryptionPinned: streamEncryptionPinned
        )

        let storedPairedMacId = upsertPairedMac(
            deviceId: localDeviceId,
            hostname: result.connectionHost,
            port: port,
            pairedMacName: result.pairedMacName,
            serverPublicKey: serverPublicKeyBase64,
            privateKey: result.privateKeyBase64,
            activate: true
        )
        TalkieAppSettings.shared.reloadFromDisk()

        switch result.pairingResult {
        case .approved:
            activePairingAttemptID = nil
            recordCredentialImportEvent("The Mac approved the refreshed pairing.", level: .success)
            stopPendingPairingApprovalMonitor()
            awaitingPairingApproval = false
            errorMessage = nil
            if await client.didNegotiateEncryption {
                Self.pinEncryption(storedPairedMacId)
            }
            if await client.didNegotiateStreamEncryption {
                Self.pinStreamEncryption(storedPairedMacId)
            }
            await connect()

        case .pendingApproval:
            await client.clearAuth()
            loadPairing()
            awaitingPairingApproval = true
            justCompletedPairing = false
            lastSuccessfulContactAt = nil
            status = .disconnected
            errorMessage = "Approve this iPhone on your Mac, then try importing credentials again."
            activePairingAttemptID = pendingCandidate.attemptID
            startPendingPairingApprovalMonitor(candidate: pendingCandidate)
            recordCredentialImportEvent(
                "Open Talkie on the Mac, then approve this iPhone under Settings > iOS > Pending Pairings.",
                level: .warning
            )
        }

        return result.pairingResult
    }

    private func recordCredentialImportEvent(
        _ message: String,
        level: CredentialImportEvent.Level = .info
    ) {
        credentialImportEvents.append(CredentialImportEvent(message: message, level: level))
        if credentialImportEvents.count > 8 {
            credentialImportEvents.removeFirst(credentialImportEvents.count - 8)
        }
        log.info("AI credential import: \(message)")
    }

    private func credentialImportDiagnosticMessage(for error: Error) -> String {
        if let bridgeError = error as? BridgeError {
            switch bridgeError {
            case .messageFailed(let reason):
                return reason
            case .httpError(let code, detail: let detail):
                if let detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
                    return "The Mac bridge returned HTTP \(code): \(detail)"
                }
                return "The Mac bridge returned HTTP \(code)."
            case .connectionFailed:
                return "Could not connect to the Mac bridge."
            case .notConfigured:
                return "No paired Mac is configured on this iPhone."
            case .invalidResponse:
                return "The Mac returned an invalid credential response."
            case .pairingRejected:
                return "The Mac rejected this iPhone's pairing request."
            case .encryptionDowngrade:
                return "The Mac offered an unencrypted connection after previously using encryption. Refused for safety."
            }
        }

        return error.localizedDescription
    }

    private func resolvedPairedMacName(from candidate: String?) -> String {
        if let candidate = sanitizedMacName(candidate) {
            return candidate
        }

        if let storedName = sanitizedMacName(activePairedMac?.pairedMacName) {
            return storedName
        }

        return "Paired Mac"
    }

    private func sanitizedMacName(_ candidate: String?) -> String? {
        guard let candidate else { return nil }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        guard lowered != "localhost", lowered != "127.0.0.1", lowered != "::1" else { return nil }

        return trimmed
    }

    @discardableResult
    private func upsertPairedMac(
        deviceId: String,
        hostname: String,
        port: Int,
        pairedMacName: String,
        serverPublicKey: String,
        privateKey: String,
        activate: Bool
    ) -> String {
        let now = Date().timeIntervalSince1970
        var upsertedMacID = ""
        configurationStore.update { configuration in
            configuration.bridge.deviceId = deviceId

            let matchingHostIndex = configuration.bridge.pairedMacs.firstIndex(where: {
                $0.hostname == hostname && $0.port == port
            })
            let matchingActiveKeyIndex = configuration.bridge.pairedMacs.firstIndex(where: {
                $0.id == configuration.bridge.activePairedMacID &&
                !serverPublicKey.isEmpty &&
                $0.serverPublicKey == serverPublicKey
            })
            let existingIndex = matchingHostIndex ?? matchingActiveKeyIndex

            if let existingIndex {
                let macID = configuration.bridge.pairedMacs[existingIndex].id
                upsertedMacID = macID
                // Private key lives in the keychain, never in config.json.
                privateKeyStore.save(id: macID, privateKeyBase64: privateKey)
                configuration.bridge.pairedMacs[existingIndex].hostname = hostname
                configuration.bridge.pairedMacs[existingIndex].port = port
                configuration.bridge.pairedMacs[existingIndex].pairedMacName = pairedMacName
                configuration.bridge.pairedMacs[existingIndex].serverPublicKey = serverPublicKey
                configuration.bridge.pairedMacs[existingIndex].privateKey = ""
                if activate {
                    configuration.bridge.pairedMacs[existingIndex].lastSelectedAt = now
                    configuration.bridge.activePairedMacID = configuration.bridge.pairedMacs[existingIndex].id
                }
            } else {
                var pairedMac = PairedMac(
                    hostname: hostname,
                    port: port,
                    pairedMacName: pairedMacName,
                    serverPublicKey: serverPublicKey,
                    privateKey: ""
                )
                // Private key lives in the keychain, never in config.json.
                privateKeyStore.save(id: pairedMac.id, privateKeyBase64: privateKey)
                upsertedMacID = pairedMac.id
                if activate {
                    pairedMac.lastSelectedAt = now
                }
                configuration.bridge.pairedMacs.append(pairedMac)
                if activate || configuration.bridge.activePairedMacID.isEmpty {
                    configuration.bridge.activePairedMacID = pairedMac.id
                }
            }
        }

        loadPairing()
        return upsertedMacID
    }

    private func updateStoredActiveMacName(_ pairedMacName: String) {
        guard let activePairedMacID else { return }
        configurationStore.update { configuration in
            guard let index = configuration.bridge.pairedMacs.firstIndex(where: { $0.id == activePairedMacID }) else { return }
            configuration.bridge.pairedMacs[index].pairedMacName = pairedMacName
        }
        loadPairing()
    }

    private func updateActiveMacContactDate(_ date: Date) {
        guard let activePairedMacID else { return }
        configurationStore.update { configuration in
            guard let index = configuration.bridge.pairedMacs.firstIndex(where: { $0.id == activePairedMacID }) else { return }
            configuration.bridge.pairedMacs[index].lastSuccessfulContactAt = date.timeIntervalSince1970
        }
        lastSuccessfulContactAt = date
    }
}
