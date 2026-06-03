//
//  TalkieAgentServerSupervisor.swift
//  TalkieAgent
//
//  Supervises the TalkieServer (Bun/TypeScript) sidecar process.
//  Spawns on agent boot, health-checks periodically, restarts with
//  exponential backoff, and reports status via XPC to Talkie.app.
//

import Foundation
import TalkieKit

@MainActor
final class TalkieAgentServerSupervisor {
    private struct ServerHealthSnapshot: Decodable {
        let status: String
        let version: String
        let hostname: String
        let port: Int
        let mode: String
        let pairingReady: Bool
        let instanceId: String
        let time: Int
        let timestamp: String
    }

    private enum HealthProbeResult {
        case ready
        case conflict(String)
        case notReady
    }

    static let shared = TalkieAgentServerSupervisor()

    private let log = Log(.system)
    private let port = 8765

    // Process
    private var process: Process?
    private var startedAt: Date?

    // Health
    private var healthTimer: Timer?
    private var consecutiveFailures = 0
    private var restartCount = 0
    private var backoffInterval: TimeInterval = 10
    private var lastHealthCheckOk = false
    private var lastError: String?
    private var tailscaleReady = false
    private var processState: TalkieAgentServerStatus.ProcessState = .stopped

    // Guards
    private var isStarting = false
    private let maxConsecutiveFailures = 10
    private let healthyProbeInterval: TimeInterval = 30
    private let minBackoff: TimeInterval = 10
    private let maxBackoff: TimeInterval = 300

    private init() {}

    // MARK: - Public

    var currentStatus: TalkieAgentServerStatus {
        TalkieAgentServerStatus(
            processState: processState,
            pid: process?.processIdentifier,
            uptime: startedAt.map { Date().timeIntervalSince($0) },
            lastHealthCheckOk: lastHealthCheckOk,
            consecutiveFailures: consecutiveFailures,
            restartCount: restartCount,
            lastError: lastError,
            tailscaleReady: tailscaleReady,
            backoffSeconds: consecutiveFailures > 0 ? backoffInterval : nil
        )
    }

    func start() async {
        guard !isStarting else { return }
        if processState == .running, lastHealthCheckOk {
            log.info("TalkieAgentServerSupervisor: server already running")
            startHealthTimer()
            return
        }

        isStarting = true
        defer { isStarting = false }

        log.info("TalkieAgentServerSupervisor: starting")
        updateState(.starting)

        // Find bun
        guard let bunPath = BunResolver.findBunPath() else {
            log.error("TalkieAgentServerSupervisor: bun not found")
            updateState(.error, error: "Bun runtime not found")
            return
        }

        // Verify source
        let sourcePath = Self.serverSourcePath
        let serverScript = "\(sourcePath)/src/server.ts"
        guard FileManager.default.fileExists(atPath: serverScript) else {
            log.error("TalkieAgentServerSupervisor: server.ts not found at \(serverScript)")
            updateState(.error, error: "server.ts not found")
            return
        }

        // Auto-install deps if needed
        let nodeModules = "\(sourcePath)/node_modules"
        if !FileManager.default.fileExists(atPath: nodeModules) {
            log.info("TalkieAgentServerSupervisor: installing dependencies")
            await installDependencies(bunPath: bunPath, sourcePath: sourcePath)
        }

        await refreshTailscaleStatus()

        switch await probeServerHealth(timeout: 2) {
        case .ready:
            log.info("TalkieAgentServerSupervisor: found existing healthy bridge, adopting it")
            markServerRunning()
            startHealthTimer()
            return
        case .conflict(let reason):
            log.error("TalkieServer startup conflict: \(reason)")
            updateState(.error, error: reason)
            return
        case .notReady:
            break
        }

        // The supervised bridge is reachable on local LAN and, when available,
        // Tailscale. App-level pairing/auth gates sensitive routes.
        let args = ["run", "src/server.ts", "--nearby", "--allow-lan", "--require-approval"]
        let instanceID = UUID().uuidString
        // Spawn
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bunPath)
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: sourcePath)

        var env = ExecutableResolver.enrichedEnvironment()

        env["TALKIE_SERVER_ENABLE_BRIDGE"] = "1"
        env["TALKIE_SERVER_ENABLE_EXTENSIONS"] = "1"
        env["TALKIE_SPEECH_TOKEN"] = TalkieSpeechSupervisor.shared.authToken
        env["TALKIE_SHARED_SETTINGS_SUITE"] = TalkieEnvironment.current.sharedSettingsSuite
        env["TALKIE_SETTINGS_CONFIG_PATH"] = TalkieEnvironment.current.appSupportDirectory
            .appending(path: "settings", directoryHint: .isDirectory)
            .appending(path: "config.json")
            .path
        if let speechHost = ProcessInfo.processInfo.environment["TALKIE_SPEECH_HOST"] {
            env["TALKIE_SPEECH_HOST"] = speechHost
        }
        env["TALKIE_SERVER_INSTANCE_ID"] = instanceID
        #if DEBUG
        env["TALKIE_DEBUG"] = "1"
        #endif
        proc.environment = env

        // Capture output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        proc.standardOutput = outputPipe
        proc.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                Task { @MainActor in
                    self?.log.debug("TalkieServer stdout: \(text)")
                }
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                Task { @MainActor in
                    self?.log.warning("TalkieServer stderr: \(text)")
                }
            }
        }

        // Termination handler — detect unexpected exits
        proc.terminationHandler = { [weak self] terminatedProcess in
            Task { @MainActor in
                guard let self else { return }
                let code = terminatedProcess.terminationStatus
                self.log.warning("TalkieServer exited with code \(code)")
                self.process = nil
                self.startedAt = nil

                // Don't restart if we intentionally stopped
                if self.processState == .stopped { return }

                self.updateState(.error, error: "Process exited with code \(code)")
                self.scheduleRestart()
            }
        }

        do {
            try proc.run()
            process = proc
            startedAt = Date()
            log.info("TalkieServer started: PID \(proc.processIdentifier)")

            // Wait for health
            let readiness = await waitForReady(maxAttempts: 10, delayMs: 500)
            var shouldStartHealthTimer = false
            switch readiness {
            case .ready:
                markServerRunning()
                shouldStartHealthTimer = true

            case .conflict(let reason):
                log.error("TalkieServer startup conflict: \(reason)")
                NearbyBridgeAdvertiser.shared.stop()
                proc.terminationHandler = nil
                if proc.isRunning {
                    kill(proc.processIdentifier, SIGTERM)
                }
                process = nil
                startedAt = nil
                updateState(.error, error: reason)

            case .notReady:
                log.error("TalkieServer started but not responding")
                NearbyBridgeAdvertiser.shared.stop()
                updateState(.degraded, error: "Started but not responding to health checks")
                shouldStartHealthTimer = true
            }

            if shouldStartHealthTimer {
                startHealthTimer()
            }
        } catch {
            log.error("TalkieAgentServerSupervisor: failed to start: \(error)")
            switch await probeServerHealth(timeout: 2) {
            case .ready:
                log.info("TalkieAgentServerSupervisor: start failed because bridge is already running, adopting it")
                process = nil
                startedAt = nil
                markServerRunning()
                startHealthTimer()
            case .conflict(let reason):
                updateState(.error, error: reason)
            case .notReady:
                updateState(.error, error: error.localizedDescription)
            }
        }
    }

    func stop() async {
        log.info("TalkieAgentServerSupervisor: stopping")
        stopHealthTimer()
        NearbyBridgeAdvertiser.shared.stop()
        updateState(.stopped)

        guard let proc = process, proc.isRunning else {
            process = nil
            startedAt = nil
            return
        }

        // SIGTERM first
        kill(proc.processIdentifier, SIGTERM)

        // Wait up to 3s for graceful exit
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(100))
            if !proc.isRunning { break }
        }

        // SIGKILL if still alive
        if proc.isRunning {
            log.warning("TalkieServer didn't exit gracefully, sending SIGKILL")
            kill(proc.processIdentifier, SIGKILL)
        }

        process = nil
        startedAt = nil
    }

    /// Synchronous stop for applicationWillTerminate
    func stopSync() {
        stopHealthTimer()
        NearbyBridgeAdvertiser.shared.stop()
        processState = .stopped

        if let proc = process, proc.isRunning {
            kill(proc.processIdentifier, SIGTERM)
            // Brief synchronous wait
            usleep(500_000) // 500ms
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
            }
        }
        process = nil
    }

    func restart() async {
        await stop()
        try? await Task.sleep(for: .seconds(1))
        await start()
    }

    // MARK: - Health Check

    private func startHealthTimer() {
        stopHealthTimer()
        let interval = consecutiveFailures == 0 ? healthyProbeInterval : backoffInterval
        healthTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.performHealthCheck()
            }
        }
    }

    private func stopHealthTimer() {
        healthTimer?.invalidate()
        healthTimer = nil
    }

    private func performHealthCheck() async {
        switch await probeServerHealth(timeout: 5) {
        case .ready:
            if processState != .running {
                markServerRunning()
            }

            startHealthTimer()

        case .conflict(let reason):
            NearbyBridgeAdvertiser.shared.stop()
            lastHealthCheckOk = false
            lastError = reason
            process = nil
            startedAt = nil
            stopHealthTimer()
            updateState(.error, error: reason)

        case .notReady:
            await handleHealthFailure("Health check returned non-200 or could not validate server identity")
        }
    }

    private func handleHealthFailure(_ reason: String) async {
        consecutiveFailures += 1
        lastHealthCheckOk = false
        lastError = reason

        log.warning("TalkieServer health check failed (\(consecutiveFailures)/\(maxConsecutiveFailures)): \(reason)")

        // Check if process is still alive
        let processAlive = process?.isRunning ?? false

        if !processAlive {
            // Process died — restart with backoff
            process = nil
            startedAt = nil
            updateState(.error, error: reason)

            if consecutiveFailures >= maxConsecutiveFailures {
                log.error("TalkieServer: max failures reached, going dormant")
                return
            }

            scheduleRestart()
        } else {
            // Process alive but not responding
            updateState(.degraded, error: reason)
            backoffInterval = min(backoffInterval * 2, maxBackoff)
            startHealthTimer()
        }
    }

    private func scheduleRestart() {
        backoffInterval = min(backoffInterval * 2, maxBackoff)
        restartCount += 1
        log.info("TalkieServer: scheduling restart in \(backoffInterval)s (attempt \(restartCount))")

        broadcastStatus()

        healthTimer = Timer.scheduledTimer(withTimeInterval: backoffInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.start()
            }
        }
    }

    // MARK: - Tailscale

    private func refreshTailscaleStatus() async {
        let paths = ["/opt/homebrew/bin/tailscale", "/usr/local/bin/tailscale", "/Applications/Tailscale.app/Contents/MacOS/Tailscale"]
        var tailscalePath: String?
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                tailscalePath = path
                break
            }
        }

        guard let tsPath = tailscalePath else {
            tailscaleReady = false
            return
        }

        do {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: tsPath)
            proc.arguments = ["status", "--json"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            try proc.run()
            proc.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let backendState = json["BackendState"] as? String {
                tailscaleReady = backendState == "Running"
            } else {
                tailscaleReady = false
            }
        } catch {
            tailscaleReady = false
        }
    }

    // MARK: - Process Helpers

    private func waitForReady(maxAttempts: Int, delayMs: UInt64) async -> HealthProbeResult {
        for attempt in 1...maxAttempts {
            switch await probeServerHealth(timeout: 3) {
            case .ready:
                log.info("TalkieServer ready after \(attempt) attempt(s)")
                return .ready

            case .conflict(let reason):
                return .conflict(reason)

            case .notReady:
                break
            }
            try? await Task.sleep(for: .milliseconds(Int(delayMs)))
        }
        return .notReady
    }

    private func probeServerHealth(timeout: TimeInterval) async -> HealthProbeResult {
        let url = URL(string: "http://localhost:\(port)/health")!

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .notReady
            }

            let snapshot = try JSONDecoder().decode(ServerHealthSnapshot.self, from: data)
            if !snapshot.pairingReady {
                let occupant = portOccupantDescription()
                let suffix = occupant.map { " (\($0))" } ?? ""
                return .conflict("Port \(port) is serving a bridge that is not pairable\(suffix). Stop the other bridge before pairing devices.")
            }

            return .ready
        } catch {
            return .notReady
        }
    }

    private func portOccupantDescription() -> String? {
        do {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            proc.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fpc"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            try proc.run()
            proc.waitUntilExit()

            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            var pid: String?
            var command: String?

            for line in output.components(separatedBy: .newlines) {
                guard let prefix = line.first else { continue }
                let value = String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                switch prefix {
                case "p" where pid == nil:
                    pid = value
                case "c" where command == nil:
                    command = value
                default:
                    continue
                }
            }

            switch (pid, command) {
            case let (pid?, command?) where !pid.isEmpty && !command.isEmpty:
                return "PID \(pid), \(command)"
            case let (pid?, _):
                return "PID \(pid)"
            case let (_, command?) where !command.isEmpty:
                return command
            default:
                return nil
            }
        } catch {
            return nil
        }
    }

    private func installDependencies(bunPath: String, sourcePath: String) async {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bunPath)
        proc.arguments = ["install"]
        proc.currentDirectoryURL = URL(fileURLWithPath: sourcePath)
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                log.info("TalkieServer dependencies installed")
            } else {
                log.error("TalkieServer bun install failed with code \(proc.terminationStatus)")
            }
        } catch {
            log.error("TalkieServer bun install error: \(error)")
        }
    }

    // MARK: - State

    private func updateState(_ state: TalkieAgentServerStatus.ProcessState, error: String? = nil) {
        processState = state
        lastError = error
        broadcastStatus()
    }

    private func markServerRunning() {
        updateState(.running)
        consecutiveFailures = 0
        backoffInterval = minBackoff
        lastHealthCheckOk = true
        NearbyBridgeAdvertiser.shared.start(
            port: Int32(port),
            route: tailscaleReady ? "local,tailscale" : "local",
            mode: "nearby"
        )
    }

    private func broadcastStatus() {
        let status = currentStatus
        TalkieAgentXPCService.shared.broadcastTalkieAgentServerStatus(status)
    }

    // MARK: - Source Path

    private static var serverSourcePath: String {
        if let runtimePath = LocalCheckoutLocator
            .talkieServerSourceURL(compileTimeFilePath: #filePath)?
            .path {
            return runtimePath
        }

        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent() // Services/
            .deletingLastPathComponent() // TalkieAgent/
            .deletingLastPathComponent() // TalkieAgent/
            .deletingLastPathComponent() // apps/macos/
            .appendingPathComponent("TalkieServer")
            .path
    }
}
