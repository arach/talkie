//
//  BridgeManager.swift
//  Talkie macOS
//
//  Manages the TalkieBridge server for iOS connectivity
//

import Foundation
import Darwin
import UserNotifications
import TalkieKit

private let log = Log(.system)

@MainActor @Observable
final class BridgeManager {
    static let shared = BridgeManager()

    // MARK: - State

    enum BridgeStatus: String {
        case stopped = "Stopped"
        case starting = "Starting"
        case running = "Running"
        case error = "Error"

        var icon: String {
            switch self {
            case .stopped: return "circle"
            case .starting: return "circle.dashed"
            case .running: return "checkmark.circle.fill"
            case .error: return "exclamationmark.circle.fill"
            }
        }

        var color: String {
            switch self {
            case .stopped: return "gray"
            case .starting: return "orange"
            case .running: return "green"
            case .error: return "red"
            }
        }
    }

    enum TailscaleStatus: Equatable, Sendable {
        case notInstalled
        case notRunning
        case needsLogin(authUrl: String?)
        case offline
        case noPeers(hostname: String)
        case ready(hostname: String, peers: [String])

        var message: String {
            switch self {
            case .notInstalled:
                return "Tailscale is not installed"
            case .notRunning:
                return "Tailscale is not running"
            case .needsLogin:
                return "Tailscale needs login"
            case .offline:
                return "Tailscale is offline"
            case .noPeers(let hostname):
                return "Connected as \(hostname) (no peers)"
            case .ready(let hostname, let peers):
                return "Connected as \(hostname) (\(peers.count) peers)"
            }
        }

        var isReady: Bool {
            switch self {
            case .ready, .noPeers: return true
            default: return false
            }
        }

        var hostname: String? {
            switch self {
            case .noPeers(let hostname), .ready(let hostname, _):
                return hostname
            default:
                return nil
            }
        }
    }

    struct PairedDevice: Identifiable, Codable {
        struct SetupState: Codable {
            var followComputerShortcutMode: Bool?
            var companionSurfaceActive: Bool?
            var terminalImported: Bool?
            var terminalHost: String?
            var reportedAt: String?
        }

        var id: String
        var name: String
        var pairedAt: String
        var lastSeen: String?
        var setupState: SetupState?
    }

    struct PendingPairing: Identifiable, Codable {
        var id: String { deviceId }
        var deviceId: String
        var name: String
        var requestedAt: String
    }

    private struct HealthData: Codable {
        var status: String
        var hostname: String
        var port: Int
        var mode: String
        var pairingReady: Bool
        var instanceId: String?
    }

    struct QRData: Codable {
        enum Mode: String, Codable {
            case pairing
            case nearby
            case localDev = "local_dev"
        }

        var publicKey: String
        var hostname: String
        var alternateHosts: [String] = []
        var port: Int
        var `protocol`: String
        var mode: Mode = .pairing
        var pairingReady = true

        private enum CodingKeys: String, CodingKey {
            case publicKey
            case hostname
            case alternateHosts
            case port
            case `protocol`
            case mode
            case pairingReady
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            publicKey = try container.decode(String.self, forKey: .publicKey)
            hostname = try container.decode(String.self, forKey: .hostname)
            alternateHosts = try container.decodeIfPresent([String].self, forKey: .alternateHosts) ?? []
            port = try container.decode(Int.self, forKey: .port)
            `protocol` = try container.decode(String.self, forKey: .protocol)
            mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .pairing
            pairingReady = try container.decodeIfPresent(Bool.self, forKey: .pairingReady) ?? true
        }

        var isPairingReady: Bool {
            pairingReady && mode != .localDev && hostname != "localhost"
        }
    }

    /// Status of all prerequisites needed to run TalkieServer
    struct PrerequisiteStatus {
        var bunInstalled: Bool
        var bunPath: String?
        var serverSourceExists: Bool
        var dependenciesInstalled: Bool
        var tailscaleInstalled: Bool
        var tailscaleRunning: Bool

        var isReady: Bool {
            bunInstalled && serverSourceExists && dependenciesInstalled
        }

        var needsDependencyInstall: Bool {
            bunInstalled && serverSourceExists && !dependenciesInstalled
        }

        var missingItems: [String] {
            var items: [String] = []
            if !bunInstalled { items.append("Bun runtime") }
            if !serverSourceExists { items.append("TalkieServer source") }
            if !dependenciesInstalled { items.append("Server dependencies") }
            return items
        }
    }

    /// Result of dependency installation
    enum InstallResult {
        case success
        case bunNotFound
        case sourceNotFound
        case installFailed(String)
    }

    // MARK: - Documentation URLs

    static let docsBaseURL = "https://talkie.ing/docs"
    static let bridgeSetupURL = "\(docsBaseURL)/bridge-setup"
    static let tailscaleSetupURL = "\(docsBaseURL)/tailscale"

    // MARK: - Properties

    private(set) var bridgeStatus: BridgeStatus = .stopped
    private(set) var tailscaleStatus: TailscaleStatus = .notInstalled
    private(set) var pairedDevices: [PairedDevice] = []
    private(set) var pendingPairings: [PendingPairing] = []
    private(set) var qrData: QRData?
    private(set) var errorMessage: String?
    private(set) var prerequisiteStatus: PrerequisiteStatus?
    private(set) var isInstallingDependencies = false

    private enum RefreshSchedule {
        static let statusRefreshInterval: TimeInterval = 15
        static let backgroundPairingInterval: TimeInterval = 60
        static let activePendingPairingInterval: TimeInterval = 15
        static let pairableHealthFreshnessWindow: TimeInterval = 35
    }

    private var refreshTimer: Timer?
    private var isHandlingRefreshTimerTick = false
    private var lastBackgroundPairingRefreshAt: Date?
    private var isStartingBridge = false  // Prevents concurrent start attempts
    private var resolvedBridgeHost: String?
    private var lastPairableHealthAt: Date?
    private var notifiedPendingPairingIDs: Set<String> = []

    // MARK: - DEBUG Helpers

    /// Log full JSON response in DEBUG builds
    private func logResponse(_ data: Data, endpoint: String) {
        #if DEBUG
        if let json = String(data: data, encoding: .utf8) {
            log.debug("[\(endpoint)] Response: \(json)")
        }
        #endif
    }

    // Source code location for local TalkieServer tooling.
    private static var bridgeSourcePath: String {
        if let runtimePath = LocalCheckoutLocator
            .talkieServerSourceURL(compileTimeFilePath: #filePath)?
            .path {
            return runtimePath
        }

        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent() // BridgeManager.swift → Bridge/
            .deletingLastPathComponent() // Bridge/ → Services/
            .deletingLastPathComponent() // Services/ → Talkie/
            .deletingLastPathComponent() // Talkie/ → apps/macos/
            .appendingPathComponent("TalkieServer")
            .path
    }
    // Runtime data location (App Support)
    private static let bridgeDataPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Application Support/Talkie/Bridge"
    private var devicesFile: String { "\(Self.bridgeDataPath)/.config/devices.json" }
    private var localAuthTokenFile: String { "\(Self.bridgeDataPath)/.config/.local-auth-token" }
    private let port = 8765

    // Known Tailscale CLI locations (in priority order)
    private let defaultTailscalePaths = [
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",  // macOS app bundle
        "/usr/local/bin/tailscale",                               // Homebrew Intel
        "/opt/homebrew/bin/tailscale",                            // Homebrew Apple Silicon
        "/usr/bin/tailscale"                                      // System install
    ]

    // User can override via UserDefaults
    private var customTailscalePath: String? {
        UserDefaults.standard.string(forKey: "bridge.tailscalePath")
    }

    /// Find the Tailscale CLI path
    private func findTailscalePath() -> String? {
        // Check custom path first
        if let custom = customTailscalePath,
           FileManager.default.fileExists(atPath: custom) {
            return custom
        }

        // Try default locations
        for path in defaultTailscalePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }

    /// Set a custom Tailscale CLI path
    func setCustomTailscalePath(_ path: String?) {
        if let path = path {
            UserDefaults.standard.set(path, forKey: "bridge.tailscalePath")
        } else {
            UserDefaults.standard.removeObject(forKey: "bridge.tailscalePath")
        }
        checkStatus()
    }

    // MARK: - Init

    private init() {
        // Don't do network checks on init - defer until explicitly needed
        // This prevents noisy HTTP errors when bridge server isn't running
        bridgeStatus = .stopped
    }

    // MARK: - Public API

    /// Full status refresh - call when user navigates to Bridge settings
    func checkStatus() {
        Task {
            await checkStatusNow()
        }
    }

    /// Full status refresh for callers that need current state before continuing.
    func checkStatusNow() async {
        await checkTailscaleStatus()
        await checkBridgeStatus()
        await updatePrerequisiteStatus()
        normalizeAutomaticBridgeDefaultsIfNeeded()
        await autoStartBridgeIfNeeded()
        await refreshDevices()
        await refreshPendingPairings()
        await fetchQRData()
    }

    /// Quick status check without network calls
    func refreshNonNetworkStatus() {
        Task {
            await refreshNonNetworkStatusNow()
        }
    }

    /// Quick status check for callers that need current Tailscale state before continuing.
    func refreshNonNetworkStatusNow() async {
        await checkTailscaleStatus()
        await updatePrerequisiteStatus()
    }

    /// Check all prerequisites and return their status
    func checkPrerequisites() async -> PrerequisiteStatus {
        let bunPath = BunResolver.findBunPath()
        let bunInstalled = bunPath != nil

        let sourcePath = Self.bridgeSourcePath
        let serverSourceExists = FileManager.default.fileExists(atPath: "\(sourcePath)/src/server.ts")

        let nodeModulesPath = "\(sourcePath)/node_modules"
        let dependenciesInstalled = FileManager.default.fileExists(atPath: nodeModulesPath)

        let tailscaleInstalled = findTailscalePath() != nil

        // Check if Tailscale is actually running
        var tailscaleRunning = false
        if tailscaleInstalled {
            switch tailscaleStatus {
            case .ready, .noPeers:
                tailscaleRunning = true
            default:
                tailscaleRunning = false
            }
        }

        let status = PrerequisiteStatus(
            bunInstalled: bunInstalled,
            bunPath: bunPath,
            serverSourceExists: serverSourceExists,
            dependenciesInstalled: dependenciesInstalled,
            tailscaleInstalled: tailscaleInstalled,
            tailscaleRunning: tailscaleRunning
        )

        // Update the stored status
        await MainActor.run {
            self.prerequisiteStatus = status
        }

        return status
    }

    /// Update the prerequisite status (called from checkStatus)
    private func updatePrerequisiteStatus() async {
        _ = await checkPrerequisites()
    }

    /// Install TalkieServer dependencies (runs `bun install`)
    /// Returns the result of the installation
    func installDependencies() async -> InstallResult {
        guard !isInstallingDependencies else {
            return .installFailed("Installation already in progress")
        }

        guard let bunPath = BunResolver.findBunPath() else {
            log.error("Cannot install dependencies: Bun not found")
            return .bunNotFound
        }

        isInstallingDependencies = true
        defer { isInstallingDependencies = false }

        let sourcePath = Self.bridgeSourcePath
        guard FileManager.default.fileExists(atPath: "\(sourcePath)/src/server.ts") else {
            log.error("Cannot install dependencies: TalkieServer source not found at \(sourcePath)")
            return .sourceNotFound
        }

        log.info("Installing TalkieServer dependencies at \(sourcePath)...")

        do {
            let (status, stdout, stderr) = try await Task.detached(priority: .utility) {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: bunPath)
                proc.arguments = ["install"]
                proc.currentDirectoryURL = URL(fileURLWithPath: sourcePath)
                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = errPipe
                try proc.run()
                proc.waitUntilExit()
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return (proc.terminationStatus, out, err)
            }.value

            if status == 0 {
                log.info("Dependencies installed successfully")
                _ = await checkPrerequisites()
                return .success
            } else {
                let errorOutput = stderr.isEmpty ? stdout : stderr
                log.error("Dependency installation failed: \(errorOutput)")
                return .installFailed(errorOutput)
            }
        } catch {
            log.error("Failed to run bun install: \(error)")
            return .installFailed(error.localizedDescription)
        }
    }

    /// Open the bridge setup documentation in the default browser
    func openBridgeSetupDocs() {
        if let url = URL(string: Self.bridgeSetupURL) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Open the local TalkieServer overview when source is available, otherwise fall back to setup docs.
    func openTalkieServerOverview() {
        let sourceURL = URL(fileURLWithPath: Self.bridgeSourcePath, isDirectory: true)
        let architectureURL = sourceURL.appendingPathComponent("ARCHITECTURE.md")

        if FileManager.default.fileExists(atPath: architectureURL.path) {
            NSWorkspace.shared.open(architectureURL)
        } else if FileManager.default.fileExists(atPath: sourceURL.path) {
            NSWorkspace.shared.open(sourceURL)
        } else {
            openBridgeSetupDocs()
        }
    }

    /// Open the Tailscale setup documentation in the default browser
    func openTailscaleSetupDocs() {
        if let url = URL(string: Self.tailscaleSetupURL) {
            NSWorkspace.shared.open(url)
        }
    }

    func startBridge() async {
        guard !isStartingBridge else {
            log.debug("Bridge start already in progress, skipping")
            return
        }
        guard bridgeStatus != .running && bridgeStatus != .starting else { return }

        isStartingBridge = true
        defer { isStartingBridge = false }

        bridgeStatus = .starting
        errorMessage = nil

        // Delegate to TalkieAgent via XPC
        guard let proxy = ServiceManager.shared.live.xpcManager?.remoteObjectProxy(errorHandler: { error in
            Task { @MainActor in
                log.error("XPC error starting bridge: \(error)")
            }
        }) else {
            log.error("Cannot start bridge: TalkieAgent not connected")
            bridgeStatus = .error
            errorMessage = "TalkieAgent not connected. Ensure it is running."
            return
        }

        proxy.controlTalkieAgentServer(action: "start") { [weak self] (success: Bool, error: String?) in
            Task { @MainActor in
                guard let self else { return }
                if success {
                    // Query status to confirm
                    await self.refreshStatusFromAgent()
                    await self.startMessageRelay()
                    self.startRefreshTimer()
                } else {
                    self.bridgeStatus = .error
                    self.errorMessage = error ?? "Failed to start TalkieServer"
                }
            }
        }
    }

    func enableAndStartBridge() async {
        let settings = SettingsManager.shared
        if !settings.talkieServerEnabled {
            settings.talkieServerEnabled = true
        }
        if !settings.autoStartBridge {
            settings.autoStartBridge = true
        }

        let liveState = ServiceManager.shared.live
        if !liveState.isXPCConnected {
            liveState.startXPCMonitoring(autoConnect: true)
            ServiceManager.shared.launchLive(resolvingConflicts: true)

            for _ in 0..<12 {
                if liveState.isXPCConnected { break }
                liveState.connectXPC()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }

        guard liveState.isXPCConnected else {
            bridgeStatus = .error
            errorMessage = "TalkieAgent is not connected yet. Start TalkieAgent, then try enabling Bridge again."
            return
        }

        await startBridge()
        await checkStatusNow()
    }

    /// Start the local HTTP server that receives message commands from Bridge
    @MainActor
    private func startMessageRelay() async {
        // Start XPC monitoring (TalkieServer gets XPC dynamically, doesn't need it at start)
        let liveState = ServiceManager.shared.live
        if !liveState.isXPCConnected {
            liveState.startXPCMonitoring()
        }

        // Always start TalkieServer - it gets XPC dynamically when handling requests
        TalkieServer.shared.start()
        log.info("TalkieServer started (port 8766)")
    }

    func stopBridge() async {
        stopRefreshTimer()

        // Stop local TalkieServer (HTTP relay)
        TalkieServer.shared.stop()

        // Delegate process stop to TalkieAgent via XPC
        if let proxy = ServiceManager.shared.live.xpcManager?.remoteObjectProxy(errorHandler: { error in
            log.error("XPC error stopping bridge: \(error)")
        }) {
            proxy.controlTalkieAgentServer(action: "stop") { (success: Bool, error: String?) in
                if !success {
                    log.warning("TalkieAgent stop failed: \(error ?? "unknown")")
                }
            }
        }

        bridgeStatus = .stopped
    }

    /// Force restart the bridge via TalkieAgent
    func restartBridge() async {
        stopRefreshTimer()

        // Stop local TalkieServer (HTTP relay)
        TalkieServer.shared.stop()

        bridgeStatus = .starting

        // Delegate restart to TalkieAgent via XPC
        guard let proxy = ServiceManager.shared.live.xpcManager?.remoteObjectProxy(errorHandler: { error in
            Task { @MainActor in
                log.error("XPC error restarting bridge: \(error)")
            }
        }) else {
            bridgeStatus = .error
            errorMessage = "TalkieAgent not connected"
            return
        }

        proxy.controlTalkieAgentServer(action: "restart") { [weak self] (success: Bool, error: String?) in
            Task { @MainActor in
                guard let self else { return }
                if success {
                    await self.refreshStatusFromAgent()
                    await self.startMessageRelay()
                    self.startRefreshTimer()
                } else {
                    self.bridgeStatus = .error
                    self.errorMessage = error ?? "Failed to restart TalkieServer"
                }
            }
        }
    }

    func approvePairing(_ deviceId: String) async {
        do {
            let (_, response, _) = try await bridgeRequest(path: "/pair/\(deviceId)/approve", method: "POST")
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw BridgeError.requestFailed
            }

            log.info("Approved pairing for device: \(deviceId)")
            await refreshPendingPairings()
            await refreshDevices()
        } catch {
            log.error("Failed to approve pairing: \(error)")
        }
    }

    func rejectPairing(_ deviceId: String) async {
        do {
            let (_, response, _) = try await bridgeRequest(path: "/pair/\(deviceId)/reject", method: "POST")
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw BridgeError.requestFailed
            }

            log.info("Rejected pairing for device: \(deviceId)")
            await refreshPendingPairings()
        } catch {
            log.error("Failed to reject pairing: \(error)")
        }
    }

    /// Remove a paired device
    @discardableResult
    func removeDevice(_ deviceId: String) async -> Bool {
        guard removePersistedDeviceFromDisk(deviceId) else {
            log.error("Failed to remove persisted device: \(deviceId)")
            return false
        }

        pairedDevices.removeAll { $0.id == deviceId }
        pendingPairings.removeAll { $0.deviceId == deviceId }
        SettingsManager.shared.removeDeviceSettingsOverride(for: deviceId)
        log.info("Removed device: \(deviceId)")
        return true
    }

    /// Remove all paired devices
    @discardableResult
    func removeAllDevices() async -> Bool {
        let removedDeviceIDs = loadPairedDevicesFromDisk().map(\.id)
        guard removeAllPersistedDevicesFromDisk() else {
            log.error("Failed to remove all persisted devices")
            return false
        }

        pairedDevices = []
        pendingPairings = []
        for deviceId in removedDeviceIDs {
            SettingsManager.shared.removeDeviceSettingsOverride(for: deviceId)
        }
        log.info("Removed all devices")
        return true
    }

    // MARK: - Private

    private func checkTailscaleStatus() async {
        let customPath = customTailscalePath
        let defaultPaths = defaultTailscalePaths

        let status = await Task.detached(priority: .utility) { () -> TailscaleStatus in
            func resolvePath(customPath: String?, defaultPaths: [String]) -> String? {
                if let customPath,
                   FileManager.default.fileExists(atPath: customPath) {
                    return customPath
                }

                for path in defaultPaths where FileManager.default.fileExists(atPath: path) {
                    return path
                }
                return nil
            }

            guard let tailscalePath = resolvePath(customPath: customPath, defaultPaths: defaultPaths) else {
                return .notInstalled
            }

            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: tailscalePath)
                process.arguments = ["status", "--json"]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                try process.run()
                process.waitUntilExit()

                if process.terminationStatus != 0 {
                    return .notRunning
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return .notRunning
                }

                if let backendState = json["BackendState"] as? String,
                   backendState == "NeedsLogin" {
                    return .needsLogin(authUrl: json["AuthURL"] as? String)
                }

                guard let selfInfo = json["Self"] as? [String: Any],
                      let online = selfInfo["Online"] as? Bool,
                      online else {
                    return .offline
                }

                let hostname = (selfInfo["DNSName"] as? String)?
                    .replacingOccurrences(of: ".$", with: "", options: .regularExpression) ?? "unknown"

                var peers: [String] = []
                if let peerDict = json["Peer"] as? [String: Any] {
                    for (_, peerInfo) in peerDict {
                        if let peer = peerInfo as? [String: Any],
                           let peerOnline = peer["Online"] as? Bool,
                           peerOnline,
                           let peerName = peer["DNSName"] as? String {
                            peers.append(peerName)
                        }
                    }
                }

                if peers.isEmpty {
                    return .noPeers(hostname: hostname)
                } else {
                    return .ready(hostname: hostname, peers: peers)
                }
            } catch {
                return .notInstalled
            }
        }.value

        tailscaleStatus = status
    }

    private func checkBridgeStatus() async {
        // Direct health is the source of truth for whether the bridge on 8765 is usable.
        // A healthy, pairable bridge may have been launched by an earlier agent instance,
        // and that should be treated as good news rather than an ownership conflict.
        if await refreshDirectBridgeHealth() {
            await refreshStatusFromAgent()
            return
        }

        if ServiceManager.shared.live.isXPCConnected {
            await refreshStatusFromAgent()
            if bridgeStatus == .running {
                startRefreshTimer()
                await ensureTalkieServerRunning()
            }
            if bridgeStatus == .error, await refreshDirectBridgeHealth() {
                return
            }
            return
        }

        bridgeStatus = .stopped
        resolvedBridgeHost = nil
        stopRefreshTimer()
    }

    private func refreshDirectBridgeHealth(restartTimerOnSuccess: Bool = true) async -> Bool {
        do {
            let (data, response, _) = try await bridgeRequest(path: "/health")
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }

            let health = try? JSONDecoder().decode(HealthData.self, from: data)
            guard health?.status == "ok" else { return false }

            guard health?.pairingReady == true else {
                lastPairableHealthAt = nil
                bridgeStatus = .error
                errorMessage = "Bridge is responding on port \(port), but it is not ready for pairing."
                stopRefreshTimer()
                return false
            }

            lastPairableHealthAt = Date()
            bridgeStatus = .running
            errorMessage = nil
            if restartTimerOnSuccess {
                startRefreshTimer()
            }
            await ensureTalkieServerRunning()
            return true
        } catch {
            return false
        }
    }

    /// Query TalkieAgent for current TalkieServer status via XPC
    func refreshStatusFromAgent() async {
        guard let proxy = ServiceManager.shared.live.xpcManager?.remoteObjectProxy(errorHandler: { error in
            log.debug("XPC error querying server status: \(error)")
        }) else {
            return
        }

        proxy.getTalkieAgentServerStatus { [weak self] (statusJSON: Data?) in
            Task { @MainActor in
                guard let self, let data = statusJSON,
                      let status = try? JSONDecoder().decode(TalkieAgentServerStatus.self, from: data) else {
                    return
                }
                self.updateFromAgentStatus(status)
            }
        }
    }

    /// Update local bridge status from a TalkieAgentServerStatus push or query result
    func updateFromAgentStatus(_ status: TalkieAgentServerStatus) {
        switch status.processState {
        case .running:
            bridgeStatus = .running
            errorMessage = nil
        case .starting:
            bridgeStatus = .starting
            errorMessage = nil
        case .stopped:
            if isPairableHealthFresh {
                bridgeStatus = .running
                errorMessage = nil
                return
            }
            bridgeStatus = .stopped
            errorMessage = nil
        case .degraded:
            bridgeStatus = .running  // Still accessible, just degraded
            errorMessage = status.lastError
        case .error:
            if isPairableHealthFresh {
                bridgeStatus = .running
                errorMessage = nil
                return
            }
            bridgeStatus = .error
            errorMessage = status.lastError
        }
    }

    private var isPairableHealthFresh: Bool {
        guard let lastPairableHealthAt else { return false }
        return Date().timeIntervalSince(lastPairableHealthAt)
            < RefreshSchedule.pairableHealthFreshnessWindow
    }

    private func enableTalkieServerIfNeeded(reason: String) {
        guard !SettingsManager.shared.talkieServerEnabled else { return }

        SettingsManager.shared.talkieServerEnabled = true
        log.info("Enabled TalkieServer automatically for \(reason)")
    }

    /// Ensure TalkieServer is running (auto-start if Bridge is up but TalkieServer is not)
    private func ensureTalkieServerRunning() async {
        guard !TalkieServer.shared.isRunning else { return }

        log.info("Bridge is running but TalkieServer is not - starting TalkieServer")

        // Ensure XPC is connected
        let liveState = ServiceManager.shared.live
        if !liveState.isXPCConnected {
            liveState.startXPCMonitoring()
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        TalkieServer.shared.start()
    }

    private func normalizeAutomaticBridgeDefaultsIfNeeded() {
        let settings = SettingsManager.shared
        guard hasPersistedPairedDevices else { return }

        if !settings.autoStartBridge {
            settings.autoStartBridge = true
            log.info("Enabled bridge autostart automatically because paired devices already exist")
        }

        enableTalkieServerIfNeeded(reason: "existing paired devices")
    }

    private func autoStartBridgeIfNeeded() async {
        guard bridgeStatus == .stopped else { return }

        let settings = SettingsManager.shared
        guard settings.autoStartBridge || hasPersistedPairedDevices else { return }

        // TalkieAgent supervisor starts TalkieServer on boot — just sync status
        if ServiceManager.shared.live.isXPCConnected {
            await refreshStatusFromAgent()
            if bridgeStatus == .running {
                await ensureTalkieServerRunning()
                startRefreshTimer()
            }
        }
    }

    private func refreshDevices() async {
        if bridgeStatus == .running {
            do {
                let (data, _, _) = try await bridgeRequest(path: "/devices")
                logResponse(data, endpoint: "/devices")

                struct DevicesResponse: Codable {
                    var devices: [PairedDevice]
                }

                let response = try JSONDecoder().decode(DevicesResponse.self, from: data)
                pairedDevices = response.devices
                return
            } catch {
                log.error("Failed to refresh devices from bridge: \(error)")
            }
        }

        pairedDevices = loadPairedDevicesFromDisk()
    }

    private func refreshPendingPairings() async {
        guard bridgeStatus == .running else { return }

        do {
            let (data, _, _) = try await bridgeRequest(path: "/pair/pending")
            logResponse(data, endpoint: "/pair/pending")

            struct PendingResponse: Codable {
                var pending: [PendingPairing]
            }

            let response = try JSONDecoder().decode(PendingResponse.self, from: data)
            let previousNotifiedIDs = notifiedPendingPairingIDs
            pendingPairings = response.pending
            lastBackgroundPairingRefreshAt = Date()
            let pendingIDs = Set(response.pending.map(\.deviceId))
            notifiedPendingPairingIDs.formIntersection(pendingIDs)

            for pairing in response.pending where !previousNotifiedIDs.contains(pairing.deviceId) {
                notifyPendingPairing(pairing)
                notifiedPendingPairingIDs.insert(pairing.deviceId)
            }
        } catch {
            log.error("Failed to refresh pending pairings: \(error)")
        }
    }

    private func notifyPendingPairing(_ pairing: PendingPairing) {
        let content = UNMutableNotificationContent()
        content.title = "Approve Talkie iPhone?"
        content.body = "\(pairing.name) wants to refresh its Mac Bridge pairing."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "talkie-bridge-pairing-\(pairing.deviceId)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                log.warning("Failed to show pending pairing notification: \(error.localizedDescription)")
            }
        }
    }

    private func fetchQRData() async {
        guard bridgeStatus == .running else {
            qrData = nil
            return
        }

        do {
            let (data, _, _) = try await bridgeRequest(path: "/pair/info")
            logResponse(data, endpoint: "/pair/info")
            let decoded = try JSONDecoder().decode(QRData.self, from: data)
            qrData = decoded
            if !decoded.isPairingReady {
                log.warning("Bridge QR is not pairable", detail: "mode=\(decoded.mode.rawValue) hostname=\(decoded.hostname)")
            }
        } catch {
            qrData = nil
            log.error("Failed to fetch QR data: \(error)")
        }
    }

    private func loadPairedDevicesFromDisk() -> [PairedDevice] {
        let url = URL(fileURLWithPath: devicesFile)
        guard let data = try? Data(contentsOf: url) else {
            return []
        }

        struct DevicesResponse: Codable {
            var devices: [PairedDevice]
        }

        do {
            let response = try JSONDecoder().decode(DevicesResponse.self, from: data)
            return response.devices
        } catch {
            log.error("Failed to decode paired devices from disk: \(error)")
            return []
        }
    }

    private func saveRawDeviceRegistry(_ registry: [String: Any]) throws {
        let url = URL(fileURLWithPath: devicesFile)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let data = try JSONSerialization.data(
            withJSONObject: registry,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
    }

    private func removePersistedDeviceFromDisk(_ deviceId: String) -> Bool {
        let url = URL(fileURLWithPath: devicesFile)
        guard let data = try? Data(contentsOf: url) else {
            return false
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            log.error("Failed to decode paired device registry for removal: \(error)")
            return false
        }

        guard var registry = jsonObject as? [String: Any],
              let devices = registry["devices"] as? [[String: Any]] else {
            log.error("Paired device registry has an unexpected shape")
            return false
        }

        let originalCount = devices.count
        let updatedDevices = devices.filter { device in
            (device["id"] as? String) != deviceId
        }
        guard updatedDevices.count != originalCount else {
            return false
        }

        registry["devices"] = updatedDevices

        do {
            try saveRawDeviceRegistry(registry)
            return true
        } catch {
            log.error("Failed to save paired devices after removal: \(error)")
            return false
        }
    }

    private func removeAllPersistedDevicesFromDisk() -> Bool {
        var registry: [String: Any] = ["devices": []]
        let url = URL(fileURLWithPath: devicesFile)
        if let data = try? Data(contentsOf: url),
           let existingRegistry = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            registry = existingRegistry
            registry["devices"] = []
        }

        do {
            try saveRawDeviceRegistry(registry)
            return true
        } catch {
            log.error("Failed to clear paired devices from disk: \(error)")
            return false
        }
    }

    private var hasPersistedPairedDevices: Bool {
        !loadPairedDevicesFromDisk().isEmpty
    }

    private func readLocalAuthToken() -> String? {
        guard let token = try? String(contentsOfFile: localAuthTokenFile, encoding: .utf8) else {
            return nil
        }
        return token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func performBridgeRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> (Data, URLResponse, URL) {
        try await bridgeRequest(path: path, method: method, body: body, contentType: contentType)
    }

    private func bridgeRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> (Data, URLResponse, URL) {
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        var lastError: Error?
        let localAuthToken = readLocalAuthToken()

        for host in bridgeHostCandidates {
            guard let url = URL(string: "http://\(host):\(port)\(normalizedPath)") else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = method
            request.httpBody = body
            if let contentType, body != nil {
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
            if let localAuthToken, !localAuthToken.isEmpty {
                request.setValue("Bearer \(localAuthToken)", forHTTPHeaderField: "Authorization")
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                resolvedBridgeHost = host
                return (data, response, url)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? BridgeError.requestFailed
    }

    private var bridgeHostCandidates: [String] {
        var hosts: [String] = []

        if let resolvedBridgeHost {
            hosts.append(resolvedBridgeHost)
        }

        if let tailscaleIPv4 = currentTailscaleIPv4Address() {
            hosts.append(tailscaleIPv4)
        }

        if let hostname = tailscaleStatus.hostname {
            hosts.append(hostname)
        }

        hosts.append("localhost")

        var uniqueHosts: [String] = []
        for host in hosts where !uniqueHosts.contains(host) {
            uniqueHosts.append(host)
        }
        return uniqueHosts
    }

    private func currentTailscaleIPv4Address() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else {
            return nil
        }
        defer { freeifaddrs(interfaces) }

        var currentInterface: UnsafeMutablePointer<ifaddrs>? = firstInterface
        while let interface = currentInterface?.pointee {
            defer { currentInterface = interface.ifa_next }

            guard let address = interface.ifa_addr else { continue }
            guard address.pointee.sa_family == UInt8(AF_INET) else { continue }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            guard result == 0 else { continue }

            let host = String(cString: hostBuffer)
            if TalkieNetworkRouteClassifier.isTailscaleIPv4Address(host) {
                return host
            }
        }

        return nil
    }

    private func startRefreshTimer() {
        stopRefreshTimer()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: RefreshSchedule.statusRefreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshTimerTick()
            }
        }
    }

    private func refreshTimerTick() async {
        guard bridgeStatus == .running || bridgeStatus == .starting else {
            stopRefreshTimer()
            return
        }
        guard !isHandlingRefreshTimerTick else { return }

        isHandlingRefreshTimerTick = true
        defer { isHandlingRefreshTimerTick = false }

        if ServiceManager.shared.live.isXPCConnected {
            await refreshStatusFromAgent()
        } else {
            guard await refreshDirectBridgeHealth(restartTimerOnSuccess: false) else {
                guard bridgeStatus != .error else { return }
                if !isPairableHealthFresh {
                    bridgeStatus = .stopped
                    resolvedBridgeHost = nil
                    stopRefreshTimer()
                }
                return
            }
        }

        await refreshBackgroundPairingsIfDue()
    }

    private func refreshBackgroundPairingsIfDue() async {
        guard bridgeStatus == .running else {
            if !isPairableHealthFresh, !ServiceManager.shared.live.isXPCConnected {
                bridgeStatus = .stopped
                resolvedBridgeHost = nil
                stopRefreshTimer()
            }
            return
        }
        let interval: TimeInterval
        if pendingPairings.isEmpty {
            interval = RefreshSchedule.backgroundPairingInterval
        } else {
            interval = RefreshSchedule.activePendingPairingInterval
        }
        let now = Date()
        if let lastBackgroundPairingRefreshAt,
           now.timeIntervalSince(lastBackgroundPairingRefreshAt) < interval {
            return
        }

        lastBackgroundPairingRefreshAt = now
        await refreshPendingPairings()
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    enum BridgeError: Error {
        case requestFailed
    }
}
