//
//  TalkieSpeechSupervisor.swift
//  TalkieAgent
//
//  Supervises the TalkieSpeech (Kokoro TTS) sidecar process.
//  Spawns on demand, health-checks periodically, restarts with
//  exponential backoff. TalkieSpeech self-unloads models after idle.
//

import Foundation
import TalkieKit

@MainActor
final class TalkieSpeechSupervisor {
    static let shared = TalkieSpeechSupervisor()

    private let log = Log(.system)
    let port = 8780

    private var process: Process?
    private var startedAt: Date?

    private var healthTimer: Timer?
    private var consecutiveFailures = 0
    private var restartCount = 0
    private var backoffInterval: TimeInterval = 10
    private var lastHealthCheckOk = false
    private var lastError: String?
    private(set) var processState: ProcessState = .stopped

    private var isStarting = false
    private let maxConsecutiveFailures = 10
    private let minBackoff: TimeInterval = 10
    private let maxBackoff: TimeInterval = 300

    private(set) var authToken: String = ""

    enum ProcessState: String {
        case stopped, starting, running, degraded, error
    }

    private init() {
        authToken = generateToken()
    }

    // MARK: - Public

    var isRunning: Bool { processState == .running }

    func start() async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        log.info("TalkieSpeechSupervisor: starting")
        processState = .starting

        await killStrayProcesses()

        let executablePath = Self.executablePath
        guard FileManager.default.fileExists(atPath: executablePath) else {
            log.error("TalkieSpeechSupervisor: executable not found at \(executablePath)")
            processState = .error
            lastError = "TalkieSpeech executable not found"
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = ["--port", "\(port)", "--host", "0.0.0.0"]

        var env = ProcessInfo.processInfo.environment
        env["TALKIE_SPEECH_TOKEN"] = authToken
        proc.environment = env

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        proc.standardOutput = outputPipe
        proc.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                Task { @MainActor in self?.log.debug("TalkieSpeech stdout: \(text)") }
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                Task { @MainActor in self?.log.warning("TalkieSpeech stderr: \(text)") }
            }
        }

        proc.terminationHandler = { [weak self] terminatedProcess in
            Task { @MainActor in
                guard let self else { return }
                let code = terminatedProcess.terminationStatus
                self.log.warning("TalkieSpeech exited with code \(code)")
                self.process = nil
                self.startedAt = nil
                if self.processState == .stopped { return }
                self.processState = .error
                self.lastError = "Process exited with code \(code)"
                self.scheduleRestart()
            }
        }

        do {
            try proc.run()
            process = proc
            startedAt = Date()
            log.info("TalkieSpeech started: PID \(proc.processIdentifier)")

            let ready = await waitForReady(maxAttempts: 15, delayMs: 500)
            if ready {
                processState = .running
                consecutiveFailures = 0
                backoffInterval = minBackoff
                lastHealthCheckOk = true
            } else {
                log.error("TalkieSpeech started but not responding")
                processState = .degraded
                lastError = "Started but not responding to health checks"
            }

            startHealthTimer()
        } catch {
            log.error("TalkieSpeechSupervisor: failed to start: \(error)")
            processState = .error
            lastError = error.localizedDescription
        }
    }

    func stop() async {
        log.info("TalkieSpeechSupervisor: stopping")
        stopHealthTimer()
        processState = .stopped

        guard let proc = process, proc.isRunning else {
            process = nil
            startedAt = nil
            await killStrayProcesses()
            return
        }

        kill(proc.processIdentifier, SIGTERM)

        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(100))
            if !proc.isRunning { break }
        }

        if proc.isRunning {
            log.warning("TalkieSpeech didn't exit gracefully, sending SIGKILL")
            kill(proc.processIdentifier, SIGKILL)
        }

        process = nil
        startedAt = nil
        await killStrayProcesses()
    }

    func stopSync() {
        stopHealthTimer()
        processState = .stopped

        if let proc = process, proc.isRunning {
            kill(proc.processIdentifier, SIGTERM)
            usleep(500_000)
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
        healthTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.performHealthCheck() }
        }
    }

    private func stopHealthTimer() {
        healthTimer?.invalidate()
        healthTimer = nil
    }

    private func performHealthCheck() async {
        let url = URL(string: "http://127.0.0.1:\(port)/health")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                handleHealthFailure("Health check returned non-200")
                return
            }

            if processState != .running { processState = .running }
            lastHealthCheckOk = true
            consecutiveFailures = 0
            backoffInterval = minBackoff
            lastError = nil
        } catch {
            handleHealthFailure(error.localizedDescription)
        }
    }

    private func handleHealthFailure(_ reason: String) {
        consecutiveFailures += 1
        lastHealthCheckOk = false
        lastError = reason

        log.warning("TalkieSpeech health check failed (\(consecutiveFailures)/\(maxConsecutiveFailures)): \(reason)")

        let processAlive = process?.isRunning ?? false

        if !processAlive {
            process = nil
            startedAt = nil
            processState = .error

            if consecutiveFailures >= maxConsecutiveFailures {
                log.error("TalkieSpeech: max failures reached, going dormant")
                return
            }

            scheduleRestart()
        } else {
            processState = .degraded
            backoffInterval = min(backoffInterval * 2, maxBackoff)
        }
    }

    private func scheduleRestart() {
        backoffInterval = min(backoffInterval * 2, maxBackoff)
        restartCount += 1
        log.info("TalkieSpeech: scheduling restart in \(backoffInterval)s (attempt \(restartCount))")

        stopHealthTimer()
        healthTimer = Timer.scheduledTimer(withTimeInterval: backoffInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.start() }
        }
    }

    // MARK: - Process Helpers

    private func waitForReady(maxAttempts: Int, delayMs: UInt64) async -> Bool {
        let url = URL(string: "http://127.0.0.1:\(port)/health")!
        for attempt in 1...maxAttempts {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 3
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    log.info("TalkieSpeech ready after \(attempt) attempt(s)")
                    return true
                }
            } catch {}
            try? await Task.sleep(for: .milliseconds(Int(delayMs)))
        }
        return false
    }

    private func killStrayProcesses() async {
        do {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            proc.arguments = ["-ti", ":\(port)"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            try proc.run()
            proc.waitUntilExit()

            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let pids = output.components(separatedBy: .newlines)
                .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let myPID = ProcessInfo.processInfo.processIdentifier
            for pid in pids where pid != myPID {
                log.info("Killing stray process on port \(port): PID \(pid)")
                kill(pid, SIGKILL)
            }
            if !pids.isEmpty {
                try? await Task.sleep(for: .milliseconds(500))
            }
        } catch {}
    }

    private func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Source Path

    private static var executablePath: String {
        if let runtimePath = LocalCheckoutLocator
            .talkieSpeechExecutableURL(compileTimeFilePath: #filePath)?
            .path {
            return runtimePath
        }

        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent() // Services/
            .deletingLastPathComponent() // TalkieAgent/
            .deletingLastPathComponent() // TalkieAgent/
            .deletingLastPathComponent() // apps/macos/
            .appendingPathComponent("TalkieSpeech/.build/debug/TalkieSpeech")
            .path
    }
}
