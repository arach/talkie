//
//  PodManager.swift
//  TalkieEngine
//
//  Manages execution pods - separate processes for memory-intensive capabilities.
//  Each pod can be killed to instantly reclaim memory without affecting other capabilities.
//

import Foundation
import TalkieKit

/// Represents a running pod process
actor PodInstance {
    let capability: String
    let process: Process
    let stdin: FileHandle
    let stdout: FileHandle
    private(set) var isReady = false
    private(set) var memoryMB = 0
    private var pendingResponses: [String: CheckedContinuation<PodResponse, Error>] = [:]
    private var readTask: Task<Void, Never>?

    init(capability: String, process: Process, stdin: FileHandle, stdout: FileHandle) {
        self.capability = capability
        self.process = process
        self.stdin = stdin
        self.stdout = stdout
    }

    func markReady(memoryMB: Int) {
        self.isReady = true
        self.memoryMB = memoryMB
    }

    func addPendingRequest(id: String, continuation: CheckedContinuation<PodResponse, Error>) {
        pendingResponses[id] = continuation
    }

    func completePendingRequest(response: PodResponse) {
        if let continuation = pendingResponses.removeValue(forKey: response.id) {
            continuation.resume(returning: response)
        }
    }

    func failAllPending(error: Error) {
        for (_, continuation) in pendingResponses {
            continuation.resume(throwing: error)
        }
        pendingResponses.removeAll()
    }

    func setReadTask(_ task: Task<Void, Never>) {
        self.readTask = task
    }

    func cancelReadTask() {
        readTask?.cancel()
    }
}

/// Manages pod lifecycle and communication
@MainActor
final class PodManager {
    static let shared = PodManager()

    private var pods: [String: PodInstance] = [:]
    private let podExecutablePath: String

    // Path to the pod executable (embedded or in build directory)
    private init() {
        // During development, use the build output from TalkieSuite workspace
        // In production, this would be embedded in the app bundle
        if let builtProductsDir = ProcessInfo.processInfo.environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"]?.split(separator: ":").first {
            // Running from Xcode - use same build directory
            self.podExecutablePath = "\(builtProductsDir)/TalkieEnginePod"
            AppLogger.shared.info(.system, "Pod path (Xcode): \(self.podExecutablePath)")
        } else {
            // Fallback: Check standalone build first (has streaming-asr), then TalkieSuite
            let standalonePath = "/Users/arach/Library/Developer/Xcode/DerivedData/TalkieEnginePod-cxskgjvfilrsfqdtktvylicabxbs/Build/Products/Debug/TalkieEnginePod"
            let suitePath = "/Users/arach/Library/Developer/Xcode/DerivedData/TalkieSuite-guavpoyqmfbntrgcygyesivttxyh/Build/Products/Debug/TalkieEnginePod"

            // Prefer standalone build (more up-to-date with streaming-asr)
            if FileManager.default.fileExists(atPath: standalonePath) {
                self.podExecutablePath = standalonePath
                AppLogger.shared.info(.system, "Pod path (standalone): \(self.podExecutablePath)")
            } else {
                self.podExecutablePath = suitePath
                AppLogger.shared.info(.system, "Pod path (suite): \(self.podExecutablePath)")
            }
        }
    }

    // MARK: - Pod Lifecycle

    /// Spawn a pod for the given capability
    func spawn(capability: String, config: [String: String] = [:]) async throws -> PodInstance {
        // Check if already running
        if let existing = pods[capability], existing.process.isRunning {
            AppLogger.shared.info(.system, "Pod already running: \(capability)")
            return existing
        }

        AppLogger.shared.info(.system, "Spawning pod: \(capability)")
        EngineStatusManager.shared.log(.info, "Pod", "Spawning \(capability) pod...")

        // Prepare config JSON
        let configData = try JSONSerialization.data(withJSONObject: config)
        let configJson = String(data: configData, encoding: .utf8) ?? "{}"

        // Create process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: podExecutablePath)
        process.arguments = [capability, configJson]

        // Setup pipes
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Launch
        do {
            try process.run()
        } catch {
            AppLogger.shared.error(.system, "Failed to spawn pod", detail: error.localizedDescription)
            throw PodError.spawnFailed(error)
        }

        let pod = PodInstance(
            capability: capability,
            process: process,
            stdin: stdinPipe.fileHandleForWriting,
            stdout: stdoutPipe.fileHandleForReading
        )

        pods[capability] = pod

        // Start reading output
        let readTask = Task { [weak self] in
            guard let self else { return }
            await self.readPodOutput(pod: pod)
        }
        await pod.setReadTask(readTask)

        // Wait for ready signal
        try await waitForReady(pod: pod, timeout: 120)  // TTS can take a while to load

        AppLogger.shared.info(.system, "Pod ready: \(capability)", detail: "Memory: \(await pod.memoryMB)MB")
        EngineStatusManager.shared.log(.info, "Pod", "\(capability) ready (\(await pod.memoryMB)MB)")

        return pod
    }

    /// Kill a pod to reclaim memory
    func kill(capability: String) async {
        guard let pod = pods[capability] else { return }

        AppLogger.shared.info(.system, "Killing pod: \(capability)")
        EngineStatusManager.shared.log(.info, "Pod", "Killing \(capability) pod...")

        await pod.cancelReadTask()
        pod.process.terminate()

        // Wait for termination
        pod.process.waitUntilExit()

        await pod.failAllPending(error: PodError.killed)
        pods.removeValue(forKey: capability)

        AppLogger.shared.info(.system, "Pod killed: \(capability)")
        EngineStatusManager.shared.log(.info, "Pod", "\(capability) pod terminated")
    }

    /// Get status of all pods
    func getStatus() async -> [String: PodStatus] {
        var result: [String: PodStatus] = [:]

        for (capability, pod) in pods {
            result[capability] = PodStatus(
                capability: capability,
                loaded: await pod.isReady && pod.process.isRunning,
                memoryMB: await pod.memoryMB,
                requestsHandled: 0
            )
        }

        return result
    }

    /// Check if a pod is running
    func isRunning(capability: String) -> Bool {
        guard let pod = pods[capability] else { return false }
        return pod.process.isRunning
    }

    // MARK: - Request Handling

    /// Send a request to a pod and get a response
    func request(capability: String, action: String, payload: [String: String] = [:]) async throws -> PodResponse {
        // Spawn if needed
        let pod: PodInstance
        if let existing = pods[capability], existing.process.isRunning {
            pod = existing
        } else {
            pod = try await spawn(capability: capability)
        }

        let request = PodRequest(action: action, payload: payload)

        return try await withCheckedThrowingContinuation { continuation in
            Task {
                await pod.addPendingRequest(id: request.id, continuation: continuation)

                do {
                    let data = try JSONEncoder().encode(request)
                    var line = data
                    line.append(contentsOf: "\n".utf8)
                    pod.stdin.write(line)
                } catch {
                    await pod.completePendingRequest(response: PodResponse.failure(id: request.id, error: error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Private

    private func waitForReady(pod: PodInstance, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if await pod.isReady {
                return
            }

            if !pod.process.isRunning {
                throw PodError.processExited(pod.process.terminationStatus)
            }

            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        }

        throw PodError.timeout
    }

    private func readPodOutput(pod: PodInstance) async {
        // Run blocking I/O on a background thread to avoid freezing the main thread
        // availableData is synchronous and would block the main actor otherwise
        let stdout = pod.stdout

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var buffer = Data()

                while !Task.isCancelled && pod.process.isRunning {
                    let chunk = stdout.availableData

                    if chunk.isEmpty {
                        // EOF
                        break
                    }

                    buffer.append(chunk)

                    // Process complete lines
                    while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                        let lineData = buffer[..<newlineIndex]
                        buffer = buffer[(newlineIndex + 1)...]

                        guard !lineData.isEmpty else { continue }

                        // Process on main actor
                        let data = Data(lineData)
                        Task { @MainActor in
                            await self.processLine(data, pod: pod)
                        }
                    }
                }

                continuation.resume()
            }
        }
    }

    private func processLine(_ data: Data, pod: PodInstance) async {
        // Try to parse as JSON
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Check message type
        if let type = json["type"] as? String {
            switch type {
            case "ready":
                let memoryMB = json["memoryMB"] as? Int ?? 0
                await pod.markReady(memoryMB: memoryMB)

            case "log":
                if let message = json["message"] as? String {
                    AppLogger.shared.debug(.system, "Pod[\(pod.capability)]", detail: message)
                }

            default:
                break
            }
            return
        }

        // Try to parse as PodResponse
        if let response = try? JSONDecoder().decode(PodResponse.self, from: data) {
            await pod.completePendingRequest(response: response)
        }
    }
}

// MARK: - Errors

enum PodError: LocalizedError {
    case spawnFailed(Error)
    case timeout
    case processExited(Int32)
    case killed
    case notRunning

    var errorDescription: String? {
        switch self {
        case .spawnFailed(let error):
            return "Failed to spawn pod: \(error.localizedDescription)"
        case .timeout:
            return "Pod failed to become ready in time"
        case .processExited(let code):
            return "Pod process exited with code \(code)"
        case .killed:
            return "Pod was killed"
        case .notRunning:
            return "Pod is not running"
        }
    }
}

// MARK: - Pod Protocol Types (mirror of TalkieEnginePod types)

struct PodRequest: Codable {
    let id: String
    let action: String
    let payload: [String: String]

    init(id: String = UUID().uuidString, action: String, payload: [String: String] = [:]) {
        self.id = id
        self.action = action
        self.payload = payload
    }
}

struct PodResponse: Codable {
    let id: String
    let success: Bool
    let result: [String: String]?
    let error: String?
    let durationMs: Int?

    static func failure(id: String, error: String) -> PodResponse {
        PodResponse(id: id, success: false, result: nil, error: error, durationMs: nil)
    }
}

struct PodStatus: Codable {
    let capability: String
    let loaded: Bool
    let memoryMB: Int
    let requestsHandled: Int
}
