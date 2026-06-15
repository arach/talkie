//
//  TalkieAgentRuntime.swift
//  TalkieAgent
//
//  Supervises the Node-based TalkieAgent runtime sidecar.
//

import Darwin
import Foundation
import TalkieKit

private let talkieAgentRuntimeLog = Log(.system)

private enum TalkieAgentRuntimeError: LocalizedError {
    case missingNodeExecutable(searchedPaths: [String])
    case missingRuntimeScript(searchedPaths: [String])
    case invalidRequest(String)
    case invalidResponse(String)
    case processNotRunning
    case processExited(op: String?, status: Int32, reason: String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingNodeExecutable(let searchedPaths):
            return "Node.js was not found. Checked executable paths: \(searchedPaths.joined(separator: ", ")), then `which node` via /bin/bash -lc."
        case .missingRuntimeScript(let searchedPaths):
            return "TalkieAgent runtime script was not found. Checked: \(searchedPaths.joined(separator: ", "))."
        case .invalidRequest(let detail):
            return "TalkieAgent runtime request is not JSON-serializable: \(detail)"
        case .invalidResponse(let detail):
            return "TalkieAgent runtime returned an invalid response: \(detail)"
        case .processNotRunning:
            return "TalkieAgent runtime process is not running."
        case .processExited(let op, let status, let reason):
            if let op {
                return "TalkieAgent runtime exited while handling op `\(op)` with status \(status) (\(reason))."
            }
            return "TalkieAgent runtime exited with status \(status) (\(reason))."
        case .writeFailed(let detail):
            return "Failed to write to TalkieAgent runtime stdin: \(detail)"
        }
    }
}

@MainActor
final class TalkieAgentRuntime {
    static let shared = TalkieAgentRuntime()

    private struct PendingRequest {
        let op: String
        let continuation: CheckedContinuation<[String: Any], Error>
    }

    private final class ProcessBox: @unchecked Sendable {
        let process: Process

        init(_ process: Process) {
            self.process = process
        }
    }

    private static let nodeCandidatePaths = [
        "/opt/homebrew/bin/node",
        "/usr/local/bin/node",
        "/usr/bin/node",
    ]

    private static let bundledScriptRelativePath = "Runtime/node/index.mjs"
    private static let developmentScriptPath = "~/dev/talkie/apps/macos/TalkieAgent/TalkieAgent/Runtime/node/index.mjs"

    private let newlineData = Data([0x0A])

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var pendingRequest: PendingRequest?
    private var turnWaiters: [CheckedContinuation<Void, Never>] = []
    private var restartTask: Task<Void, Never>?
    private var restartDelaySeconds = 1
    private var isStopping = false

    private init() {}

    /// Starts the Node sidecar if it is not already running.
    func start() {
        do {
            try ensureProcessRunning()
        } catch {
            talkieAgentRuntimeLog.error("Failed to start node sidecar: \(error.localizedDescription)")
        }
    }

    /// Sends one JSON line to stdin and awaits one JSON line from stdout.
    func request(_ payload: [String: Any]) async throws -> [String: Any] {
        await waitForTurn()
        try Task.checkCancellation()
        try ensureProcessRunning()

        guard let stdinHandle, process?.isRunning == true else {
            throw TalkieAgentRuntimeError.processNotRunning
        }

        let op = Self.operationName(from: payload)
        let payloadData = try Self.serializePayload(payload)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequest = PendingRequest(op: op, continuation: continuation)

            do {
                try stdinHandle.write(contentsOf: payloadData)
                talkieAgentRuntimeLog.info("Runtime request op=\(op)")
            } catch {
                completePending(throwing: TalkieAgentRuntimeError.writeFailed(error.localizedDescription))
            }
        }
    }

    /// Stops the Node sidecar with SIGTERM, escalating to SIGKILL after 2 seconds.
    func stop() {
        isStopping = true
        restartTask?.cancel()
        restartTask = nil
        failPending(TalkieAgentRuntimeError.processNotRunning)

        guard let process else {
            cleanupProcessState()
            isStopping = false
            return
        }

        let processBox = ProcessBox(process)
        let pid = process.processIdentifier
        talkieAgentRuntimeLog.info("Stopping node sidecar pid=\(pid) signal=SIGTERM")
        cleanupProcessState()

        if process.isRunning {
            process.terminate()
        }

        Task { @MainActor [processBox] in
            try? await Task.sleep(for: .seconds(2))
            guard processBox.process.isRunning else { return }
            talkieAgentRuntimeLog.error("Node sidecar did not exit after SIGTERM; sending SIGKILL pid=\(pid)")
            _ = Darwin.kill(pid, SIGKILL)
        }

        isStopping = false
    }
}

private extension TalkieAgentRuntime {
    func waitForTurn() async {
        while pendingRequest != nil {
            await withCheckedContinuation { continuation in
                turnWaiters.append(continuation)
            }
        }
    }

    func ensureProcessRunning() throws {
        if let process, process.isRunning {
            return
        }

        cleanupProcessState()
        restartTask?.cancel()
        restartTask = nil
        isStopping = false
        try spawnProcess()
    }

    func spawnProcess() throws {
        let nodeURL = try resolveNodeURL()
        let scriptURL = try resolveScriptURL()
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = nodeURL
        process.arguments = [scriptURL.path]
        process.currentDirectoryURL = scriptURL.deletingLastPathComponent()
        process.environment = ProcessInfo.processInfo.environment
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdinHandle = stdinPipe.fileHandleForWriting
        stdoutHandle = stdoutPipe.fileHandleForReading
        stderrHandle = stderrPipe.fileHandleForReading
        stdoutBuffer.removeAll(keepingCapacity: true)
        stderrBuffer.removeAll(keepingCapacity: true)
        installStdoutHandler(stdoutPipe.fileHandleForReading)
        installStderrHandler(stderrPipe.fileHandleForReading)

        process.terminationHandler = { [weak self] terminatedProcess in
            Task { @MainActor in
                self?.handleTermination(of: terminatedProcess)
            }
        }

        do {
            try process.run()
            self.process = process
            talkieAgentRuntimeLog.info("Spawned node sidecar pid=\(process.processIdentifier)")
        } catch {
            cleanupProcessState()
            throw error
        }
    }

    func resolveNodeURL() throws -> URL {
        let fileManager = FileManager.default

        for path in Self.nodeCandidatePaths where fileManager.fileExists(atPath: path) && fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        if let path = try? resolveNodeViaShell(),
           fileManager.fileExists(atPath: path),
           fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        throw TalkieAgentRuntimeError.missingNodeExecutable(searchedPaths: Self.nodeCandidatePaths)
    }

    func resolveNodeViaShell() throws -> String? {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", "which node"]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)
    }

    func resolveScriptURL() throws -> URL {
        let fileManager = FileManager.default
        let candidates = Self.runtimeScriptCandidateURLs()

        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        throw TalkieAgentRuntimeError.missingRuntimeScript(
            searchedPaths: candidates.map(\.path)
        )
    }

    static func runtimeScriptCandidateURLs() -> [URL] {
        var candidates: [URL] = []

        if let configuredPath = ProcessInfo.processInfo.environment["TALKIE_AGENT_RUNTIME_SCRIPT"],
           !configuredPath.isEmpty {
            candidates.append(URL(fileURLWithPath: (configuredPath as NSString).expandingTildeInPath))
        }

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appending(path: bundledScriptRelativePath))
        }

        candidates.append(URL(fileURLWithPath: (developmentScriptPath as NSString).expandingTildeInPath))
        return candidates
    }

    func installStdoutHandler(_ handle: FileHandle) {
        handle.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty else { return }

            Task { @MainActor in
                self?.receiveStdout(data)
            }
        }
    }

    func installStderrHandler(_ handle: FileHandle) {
        handle.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty else { return }

            Task { @MainActor in
                self?.receiveStderr(data)
            }
        }
    }

    func receiveStdout(_ data: Data) {
        stdoutBuffer.append(data)

        while let range = stdoutBuffer.firstRange(of: newlineData) {
            let lineData = stdoutBuffer.subdata(in: 0..<range.lowerBound)
            stdoutBuffer.removeSubrange(0..<range.upperBound)
            handleStdoutLine(lineData)
        }
    }

    func receiveStderr(_ data: Data) {
        stderrBuffer.append(data)

        while let range = stderrBuffer.firstRange(of: newlineData) {
            let lineData = stderrBuffer.subdata(in: 0..<range.lowerBound)
            stderrBuffer.removeSubrange(0..<range.upperBound)
            handleStderrLine(lineData)
        }
    }

    func handleStdoutLine(_ data: Data) {
        let line = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }

        guard let pendingRequest else {
            talkieAgentRuntimeLog.warning("Runtime stdout without pending request")
            return
        }

        do {
            let response = try Self.parseResponseLine(line)
            logResponse(response, op: pendingRequest.op)

            if pendingRequest.op == "ping", Self.boolValue(response["ok"]) == true {
                restartDelaySeconds = 1
            }

            completePending(returning: response)
        } catch {
            talkieAgentRuntimeLog.error("Runtime response op=\(pendingRequest.op) error=\(error.localizedDescription)")
            completePending(throwing: error)
        }
    }

    func handleStderrLine(_ data: Data) {
        let line = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        talkieAgentRuntimeLog.error("Runtime stderr: \(line)")
    }

    func logResponse(_ response: [String: Any], op: String) {
        if Self.boolValue(response["ok"]) == true {
            talkieAgentRuntimeLog.info("Runtime response op=\(op) ok=true")
        } else {
            let error = response["error"] as? String ?? "Unknown runtime error"
            talkieAgentRuntimeLog.error("Runtime response op=\(op) error=\(error)")
        }
    }

    func handleTermination(of terminatedProcess: Process) {
        let status = terminatedProcess.terminationStatus
        let reason = String(describing: terminatedProcess.terminationReason)
        let op = pendingRequest?.op

        guard terminatedProcess === process else {
            talkieAgentRuntimeLog.debug("Ignoring stale node sidecar termination status=\(status) reason=\(reason)")
            return
        }

        cleanupProcessState()
        let error = TalkieAgentRuntimeError.processExited(op: op, status: status, reason: reason)
        failPending(error)
        talkieAgentRuntimeLog.error("Node sidecar exited status=\(status) reason=\(reason)")

        guard !isStopping else { return }
        scheduleRestart()
    }

    func scheduleRestart() {
        guard restartTask == nil else { return }

        let delay = restartDelaySeconds
        restartDelaySeconds = min(restartDelaySeconds * 2, 30)
        talkieAgentRuntimeLog.warning("Scheduling node sidecar restart in \(delay)s")

        restartTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(delay))
                restartTask = nil
                guard process?.isRunning != true else { return }
                try spawnProcess()
            } catch is CancellationError {
                restartTask = nil
            } catch {
                restartTask = nil
                talkieAgentRuntimeLog.error("Failed to restart node sidecar: \(error.localizedDescription)")
                scheduleRestart()
            }
        }
    }

    func cleanupProcessState() {
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        try? stdinHandle?.close()
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil
        process = nil
        stdoutBuffer.removeAll(keepingCapacity: true)
        stderrBuffer.removeAll(keepingCapacity: true)
    }

    func completePending(returning response: [String: Any]) {
        guard let pendingRequest else { return }
        self.pendingRequest = nil
        pendingRequest.continuation.resume(returning: response)
        wakeTurnWaiters()
    }

    func completePending(throwing error: Error) {
        guard let pendingRequest else { return }
        self.pendingRequest = nil
        pendingRequest.continuation.resume(throwing: error)
        wakeTurnWaiters()
    }

    func failPending(_ error: Error) {
        completePending(throwing: error)
    }

    func wakeTurnWaiters() {
        guard pendingRequest == nil, !turnWaiters.isEmpty else { return }
        let waiters = turnWaiters
        turnWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    static func operationName(from payload: [String: Any]) -> String {
        if let op = payload["op"] as? String, !op.isEmpty {
            return op
        }
        return "unknown"
    }

    static func serializePayload(_ payload: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw TalkieAgentRuntimeError.invalidRequest("Payload must contain only JSON-compatible values.")
        }

        do {
            var data = try JSONSerialization.data(withJSONObject: payload, options: [])
            data.append(0x0A)
            return data
        } catch {
            throw TalkieAgentRuntimeError.invalidRequest(error.localizedDescription)
        }
    }

    static func parseResponseLine(_ line: String) throws -> [String: Any] {
        guard let data = line.data(using: .utf8) else {
            throw TalkieAgentRuntimeError.invalidResponse("Response was not valid UTF-8.")
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw TalkieAgentRuntimeError.invalidResponse(error.localizedDescription)
        }

        guard let response = object as? [String: Any] else {
            throw TalkieAgentRuntimeError.invalidResponse("Expected a top-level JSON object.")
        }

        return response
    }

    static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }

        if let number = value as? NSNumber {
            return number.boolValue
        }

        return nil
    }
}
