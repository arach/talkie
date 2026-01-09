//
//  BridgeManager.swift
//  Talkie macOS
//
//  Manages the TalkieBridge server for iOS connectivity
//

import Foundation
import TalkieKit

private let log = Log(.system)

@Observable
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

    enum TailscaleStatus {
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
    }

    struct PairedDevice: Identifiable, Codable {
        var id: String
        var name: String
        var pairedAt: String
        var lastSeen: String?
    }

    struct PendingPairing: Identifiable, Codable {
        var id: String { deviceId }
        var deviceId: String
        var name: String
        var requestedAt: String
    }

    struct QRData: Codable {
        var publicKey: String
        var hostname: String
        var port: Int
        var `protocol`: String
    }

    // MARK: - Properties

    private(set) var bridgeStatus: BridgeStatus = .stopped
    private(set) var tailscaleStatus: TailscaleStatus = .notInstalled
    private(set) var pairedDevices: [PairedDevice] = []
    private(set) var pendingPairings: [PendingPairing] = []
    private(set) var qrData: QRData?
    private(set) var errorMessage: String?

    private var bridgeProcess: Process?
    private var refreshTimer: Timer?

    // Source code location (derived from this file's compile-time path - works with git worktrees)
    private static var bridgeSourcePath: String {
        // #filePath at compile time: .../macOS/Talkie/Services/Bridge/BridgeManager.swift
        // We need: .../macOS/TalkieServer
        let thisFile = URL(fileURLWithPath: #filePath)
        let macOSDir = thisFile
            .deletingLastPathComponent() // BridgeManager.swift → Bridge/
            .deletingLastPathComponent() // Bridge/ → Services/
            .deletingLastPathComponent() // Services/ → Talkie/
            .deletingLastPathComponent() // Talkie/ → macOS/
        return macOSDir.appendingPathComponent("TalkieServer").path
    }
    // Runtime data location (App Support)
    private static let bridgeDataPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Application Support/Talkie/Bridge"
    private var pidFile: String { "\(Self.bridgeDataPath)/bridge.pid" }
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

    // Known Bun locations (in priority order)
    private let defaultBunPaths = [
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/.bun/bin/bun",  // Default bun install
        "/opt/homebrew/bin/bun",                                                   // Homebrew Apple Silicon
        "/usr/local/bin/bun",                                                      // Homebrew Intel
        "/usr/bin/bun"                                                             // System install
    ]

    /// Find the Bun runtime path
    private func findBunPath() -> String? {
        for path in defaultBunPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    // MARK: - Init

    private init() {
        checkStatus()
    }

    // MARK: - Public API

    func checkStatus() {
        Task {
            await checkTailscaleStatus()
            await checkBridgeStatus()
            await refreshDevices()
            await refreshPendingPairings()
            await fetchQRData()
        }
    }

    func startBridge() async {
        guard bridgeStatus != .running && bridgeStatus != .starting else { return }

        // Find bun runtime
        guard let bunPath = findBunPath() else {
            log.error("Bun runtime not found. Install from https://bun.sh")
            bridgeStatus = .error
            errorMessage = "Bun runtime not found. Install from https://bun.sh"
            return
        }

        bridgeStatus = .starting
        errorMessage = nil

        // Kill any stray processes before starting
        await killStrayBridgeProcesses()

        // Verify source path exists
        let sourcePath = Self.bridgeSourcePath
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            let msg = "Bridge source not found at: \(sourcePath)"
            log.error(msg)
            bridgeStatus = .error
            errorMessage = msg
            return
        }

        // Verify server.ts exists
        let serverScript = "\(sourcePath)/src/server.ts"
        guard FileManager.default.fileExists(atPath: serverScript) else {
            let msg = "server.ts not found at: \(serverScript)"
            log.error(msg)
            bridgeStatus = .error
            errorMessage = msg
            return
        }

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: bunPath)
            process.arguments = ["run", "src/server.ts"]
            process.currentDirectoryURL = URL(fileURLWithPath: sourcePath)

            // Capture output for debugging
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            bridgeProcess = process

            log.info("Bridge started with PID \(process.processIdentifier) from \(sourcePath)")

            // Poll until server is ready (max 5 seconds)
            let ready = await waitForBridgeReady(maxAttempts: 10, delayMs: 500)
            if ready {
                bridgeStatus = .running
                await fetchQRData()
            } else {
                // Read any error output
                let errorData = errorPipe.fileHandleForReading.availableData
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                let outputData = outputPipe.fileHandleForReading.availableData
                let stdOutput = String(data: outputData, encoding: .utf8) ?? ""

                log.error("Bridge started but not responding")
                if !errorOutput.isEmpty {
                    log.error("stderr: \(errorOutput)")
                }
                if !stdOutput.isEmpty {
                    log.info("stdout: \(stdOutput)")
                }

                bridgeStatus = .error
                errorMessage = errorOutput.isEmpty ? "Bridge started but not responding" : errorOutput
                return
            }

            // Start the message relay server (receives commands from Bridge, forwards to TalkieLive via XPC)
            await startMessageRelay()

            // Start refresh timer
            startRefreshTimer()
        } catch {
            log.error("Failed to start Bridge: \(error)")
            bridgeStatus = .error
            errorMessage = error.localizedDescription
        }
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

        // Stop TalkieServer
        await MainActor.run {
            TalkieServer.shared.stop()
        }

        // Kill via PID file
        if let pidString = try? String(contentsOfFile: pidFile),
           let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) {
            kill(pid, SIGTERM)
            log.info("Sent SIGTERM to TalkieBridge PID \(pid)")
        }

        // Also terminate our process reference
        bridgeProcess?.terminate()
        bridgeProcess = nil

        // Clean up any stray processes that might be holding the port
        await killStrayBridgeProcesses()

        bridgeStatus = .stopped
    }

    /// Kill any processes holding port 8765 or running the bridge server
    /// This handles orphaned bun processes that weren't properly cleaned up
    private func killStrayBridgeProcesses() async {
        // Find PIDs using port 8765 via lsof
        let lsofProcess = Process()
        lsofProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsofProcess.arguments = ["-ti", ":\(port)"]

        let lsofPipe = Pipe()
        lsofProcess.standardOutput = lsofPipe
        lsofProcess.standardError = Pipe()

        do {
            try lsofProcess.run()
            lsofProcess.waitUntilExit()

            let data = lsofPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let pids = output.components(separatedBy: .newlines)
                    .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }

                for pid in pids {
                    // Don't kill ourselves
                    if pid != ProcessInfo.processInfo.processIdentifier {
                        log.info("Killing stray process on port \(port): PID \(pid)")
                        kill(pid, SIGKILL)  // SIGKILL to force terminate stuck processes
                    }
                }

                // If we killed anything, wait a moment for port to be released
                if !pids.isEmpty {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        } catch {
            log.debug("lsof check failed (probably no process on port): \(error)")
        }

        // Also kill any bun processes running our server script
        let pgrepProcess = Process()
        pgrepProcess.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrepProcess.arguments = ["-f", "bun.*TalkieServer.*server"]

        let pgrepPipe = Pipe()
        pgrepProcess.standardOutput = pgrepPipe
        pgrepProcess.standardError = Pipe()

        do {
            try pgrepProcess.run()
            pgrepProcess.waitUntilExit()

            let data = pgrepPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let pids = output.components(separatedBy: .newlines)
                    .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }

                for pid in pids {
                    if pid != ProcessInfo.processInfo.processIdentifier {
                        log.info("Killing stray bun process: PID \(pid)")
                        kill(pid, SIGKILL)
                    }
                }
            }
        } catch {
            log.debug("pgrep check failed: \(error)")
        }
    }

    /// Force restart the bridge, killing any stray processes first
    func restartBridge() async {
        await stopBridge()
        // Extra wait to ensure port is fully released
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await startBridge()
    }

    func approvePairing(_ deviceId: String) async {
        do {
            let url = URL(string: "http://localhost:\(port)/pair/\(deviceId)/approve")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"

            let (_, response) = try await URLSession.shared.data(for: request)
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
            let url = URL(string: "http://localhost:\(port)/pair/\(deviceId)/reject")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"

            let (_, response) = try await URLSession.shared.data(for: request)
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

    // MARK: - Private

    private func checkTailscaleStatus() async {
        // Find Tailscale CLI
        guard let tailscalePath = findTailscalePath() else {
            tailscaleStatus = .notInstalled
            return
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
                // Tailscale app exists but daemon not responding
                tailscaleStatus = .notRunning
                return
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                tailscaleStatus = .notRunning
                return
            }

            // Check backend state
            if let backendState = json["BackendState"] as? String,
               backendState == "NeedsLogin" {
                let authUrl = json["AuthURL"] as? String
                tailscaleStatus = .needsLogin(authUrl: authUrl)
                return
            }

            // Check if online
            guard let selfInfo = json["Self"] as? [String: Any],
                  let online = selfInfo["Online"] as? Bool,
                  online else {
                tailscaleStatus = .offline
                return
            }

            // Get hostname
            let hostname = (selfInfo["DNSName"] as? String)?.replacingOccurrences(of: ".$", with: "", options: .regularExpression) ?? "unknown"

            // Get peers
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
                tailscaleStatus = .noPeers(hostname: hostname)
            } else {
                tailscaleStatus = .ready(hostname: hostname, peers: peers)
            }
        } catch {
            log.error("Failed to check Tailscale status: \(error)")
            tailscaleStatus = .notInstalled
        }
    }

    private func checkBridgeStatus() async {
        do {
            let url = URL(string: "http://localhost:\(port)/health")!
            let (_, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                bridgeStatus = .stopped
                return
            }
            bridgeStatus = .running

            // Ensure TalkieServer is running when Bridge is running
            await ensureTalkieServerRunning()
        } catch {
            bridgeStatus = .stopped
        }
    }

    /// Poll until bridge health endpoint responds (or max attempts reached)
    private func waitForBridgeReady(maxAttempts: Int, delayMs: UInt64) async -> Bool {
        let url = URL(string: "http://localhost:\(port)/health")!

        for attempt in 1...maxAttempts {
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    log.info("Bridge ready after \(attempt) attempt(s)")
                    return true
                }
            } catch {
                // Not ready yet, wait and retry
            }
            try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
        }

        return false
    }

    /// Ensure TalkieServer is running (auto-start if Bridge is up but TalkieServer is not)
    @MainActor
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

    private func refreshDevices() async {
        guard bridgeStatus == .running else { return }

        do {
            let url = URL(string: "http://localhost:\(port)/devices")!
            let (data, _) = try await URLSession.shared.data(from: url)

            struct DevicesResponse: Codable {
                var devices: [PairedDevice]
            }

            let response = try JSONDecoder().decode(DevicesResponse.self, from: data)
            pairedDevices = response.devices
        } catch {
            log.error("Failed to refresh devices: \(error)")
        }
    }

    private func refreshPendingPairings() async {
        guard bridgeStatus == .running else { return }

        do {
            let url = URL(string: "http://localhost:\(port)/pair/pending")!
            let (data, _) = try await URLSession.shared.data(from: url)

            struct PendingResponse: Codable {
                var pending: [PendingPairing]
            }

            let response = try JSONDecoder().decode(PendingResponse.self, from: data)
            pendingPairings = response.pending
        } catch {
            log.error("Failed to refresh pending pairings: \(error)")
        }
    }

    private func fetchQRData() async {
        guard bridgeStatus == .running else { return }

        do {
            let url = URL(string: "http://localhost:\(port)/pair/info")!
            let (data, _) = try await URLSession.shared.data(from: url)
            qrData = try JSONDecoder().decode(QRData.self, from: data)
        } catch {
            log.error("Failed to fetch QR data: \(error)")
        }
    }

    private func startRefreshTimer() {
        stopRefreshTimer()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkStatus()
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    enum BridgeError: Error {
        case requestFailed
    }
}
