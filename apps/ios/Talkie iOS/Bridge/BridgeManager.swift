//
//  BridgeManager.swift
//  Talkie iOS
//
//  Manages connection to TalkieBridge on Mac
//

import Foundation
import CryptoKit
import SwiftUI
import TalkieMobileKit

extension Notification.Name {
    static let bridgeDidConnect = Notification.Name("com.jdi.talkie.bridgeDidConnect")
}

@MainActor
@Observable
final class BridgeManager {
    typealias PairedMac = TalkieAppConfiguration.Bridge.PairedMac

    enum PairingResult {
        case approved
        case pendingApproval
    }

    private struct PairingExecutionResult {
        let privateKeyBase64: String
        let connectionHost: String
        let pairedMacName: String
        let pairingResult: PairingResult
    }

    private enum PairingExecutionError: LocalizedError {
        case rejected

        var errorDescription: String? {
            switch self {
            case .rejected:
                return "Pairing rejected by Mac"
            }
        }
    }

    static let shared = BridgeManager()

    private let log = Log(.system)
    private let configurationStore = TalkieAppConfigurationStore.shared

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

    /// Set to true when pairing completes, UI should consume and reset
    var justCompletedPairing = false

    let client = BridgeClient()
    private var retryTask: Task<Void, Never>?
    private var companionPollTask: Task<Void, Never>?
    private var companionEventTask: Task<Void, Never>?
    private var companionEventSocket: URLSessionWebSocketTask?
    private var lastReportedSetupState: DeviceSetupStateRequest?
    private var isRefreshingCompanionState = false
    private var pendingCompanionRefresh = false
    private var isCompanionDeckVisible = false
    private var isCompanionRuntimeActive = false
    private var isCompanionEventStreamConnected = false

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

    var activePairedMac: PairedMac? {
        let bridgeConfiguration = configurationStore.configuration.bridge
        return bridgeConfiguration.pairedMacs.first(where: { $0.id == bridgeConfiguration.activePairedMacID })
            ?? bridgeConfiguration.pairedMacs.first
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
        loadPairing()
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

        status = .connecting
        errorMessage = nil
        awaitingPairingApproval = false
        let hostname = qrData.hostname
        let candidateHosts = pairingCandidateHosts(for: qrData)
        let port = qrData.port
        let serverPublicKeyBase64 = qrData.publicKey
        let localDeviceId = deviceId
        let localDeviceName = deviceName

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

            upsertPairedMac(
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
                awaitingPairingApproval = false
                lastSuccessfulContactAt = .now
                updateActiveMacContactDate(.now)
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
                lastSuccessfulContactAt = nil
                justCompletedPairing = false
                status = .disconnected
            }
            return result.pairingResult
        } catch {
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

        status = .connecting
        errorMessage = nil

        do {
            let health = try await Task.detached(priority: .userInitiated) { [client] in
                await client.configure(hostname: hostname, port: port)
                try await Self.restoreAuth(
                    client: client,
                    deviceId: configuredDeviceId,
                    privateKeyBase64: privateKeyBase64,
                    serverPublicKeyBase64: serverPublicKeyBase64
                )
                try await client.connect()
                return try await client.health()
            }.value

            let resolvedMacName = resolvedPairedMacName(from: health.hostname)
            pairedMacName = resolvedMacName
            updateStoredActiveMacName(resolvedMacName)
            TalkieAppSettings.shared.reloadFromDisk()
            awaitingPairingApproval = false
            lastSuccessfulContactAt = .now
            updateActiveMacContactDate(.now)
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
        } catch BridgeError.httpError(401) where awaitingPairingApproval {
            status = .disconnected
            errorMessage = "Approve this iPhone on your Mac to finish pairing."
            retryCount = 0
        } catch {
            status = .error
            errorMessage = "Could not connect to Mac"
            scheduleRetry()
        }
    }

    func retry() async {
        retryCount = 0
        await connect()
    }

    func disconnect() {
        retryTask?.cancel()
        retryTask = nil
        companionPollTask?.cancel()
        companionPollTask = nil
        stopCompanionEventStream()
        lastReportedSetupState = nil
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
            configurationStore.update { configuration in
                configuration.bridge = .init()
            }
            TalkieAppSettings.shared.reloadFromDisk()
            pairedMacName = nil
            lastSuccessfulContactAt = nil
            awaitingPairingApproval = false
            errorMessage = nil

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
        disconnect()

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
        let data: Data

        switch message {
        case .string(let text):
            guard let textData = text.data(using: .utf8) else { return }
            data = textData
        case .data(let bytes):
            data = bytes
        @unknown default:
            return
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

        try? await reportDeviceSetupStateIfNeeded()
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

    private func upsertPairedMac(
        deviceId: String,
        hostname: String,
        port: Int,
        pairedMacName: String,
        serverPublicKey: String,
        privateKey: String,
        activate: Bool
    ) {
        let now = Date().timeIntervalSince1970
        configurationStore.update { configuration in
            configuration.bridge.deviceId = deviceId

            let existingIndex = configuration.bridge.pairedMacs.firstIndex(where: {
                $0.hostname == hostname && $0.port == port
            })

            if let existingIndex {
                configuration.bridge.pairedMacs[existingIndex].hostname = hostname
                configuration.bridge.pairedMacs[existingIndex].port = port
                configuration.bridge.pairedMacs[existingIndex].pairedMacName = pairedMacName
                configuration.bridge.pairedMacs[existingIndex].serverPublicKey = serverPublicKey
                configuration.bridge.pairedMacs[existingIndex].privateKey = privateKey
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
                    privateKey: privateKey
                )
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
