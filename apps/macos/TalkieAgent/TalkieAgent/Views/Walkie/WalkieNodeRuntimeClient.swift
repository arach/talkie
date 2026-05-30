//
//  WalkieNodeRuntimeClient.swift
//  TalkieAgent
//

import Foundation
import TalkieKit

private let nodeRuntimeLog = Log(.workflow)

enum WalkieScoutBridgeStatus: String, Codable, Sendable {
    case pending
    case configured
}

struct WalkieRuntimePing: Sendable {
    let pid: Int?
    let version: String
    let runtimeId: String
    let runtimeName: String
    let capabilities: Set<WalkieRuntimeCapability>
    let scoutBridge: WalkieScoutBridgeStatus
}

struct WalkieRuntimeActivitySnapshot: Decodable, Sendable {
    let id: String
    let sessionId: String
    let state: String
    let ack: String
    let providerId: String?
    let modelId: String?
    let topLevelProviderId: String?
    let topLevelProviderName: String?
    let topLevelModelId: String?
    let runtimeId: String?
    let runtimeName: String?
    let conversationId: String?
    let parentSessionId: String?
    let continuedFromSessionId: String?
    let source: String?
    let channelCode: String?
    let instruction: String?
    let transcript: String?
    let output: String?
    let spokenSummary: String?
    let bridgeStatus: String?
    let agentSessionId: String?
    let agentSessionThreadId: String?
    let agentSessionStatus: String?
    let agentSessionName: String?
    let createdAt: String?
    let updatedAt: String?
    let error: String?
}

struct WalkieRuntimeStatus: Sendable {
    let ping: WalkieRuntimePing
    let activities: [WalkieRuntimeActivitySnapshot]
}

enum WalkieNodeRuntimeError: LocalizedError, Sendable {
    case missingNodeRuntime
    case missingNodeExecutable
    case runtimeFailed(String)
    case runtimeTimedOut
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingNodeRuntime:
            return "Walkie node runtime was not found."
        case .missingNodeExecutable:
            return "Bun or Node.js was not found."
        case .runtimeFailed(let detail):
            return "Walkie node runtime failed: \(detail)"
        case .runtimeTimedOut:
            return "Walkie node runtime timed out."
        case .invalidResponse(let detail):
            return "Walkie node runtime returned an invalid response: \(detail)"
        }
    }
}

actor WalkieNodeRuntimeClient {
    static let shared = WalkieNodeRuntimeClient()

    private let timeoutMs = 10_000

    func ping() async -> WalkieRuntimePing? {
        do {
            let response = try await send(NodeRuntimeRequest(op: "ping"))
            return try runtimePing(from: response)
        } catch {
            nodeRuntimeLog.debug("Walkie node runtime ping failed", detail: error.localizedDescription)
            return nil
        }
    }

    func status() async throws -> WalkieRuntimeStatus {
        let response = try await send(NodeRuntimeRequest(op: "status"))
        return WalkieRuntimeStatus(
            ping: try runtimePing(from: response),
            activities: response.activities ?? response.jobs ?? []
        )
    }

    func invoke(_ invocation: WalkieAgentInvocation) async throws -> WalkieAgentRuntimeResult {
        let response = try await send(NodeRuntimeRequest(op: "invoke", invocation: invocation))
        guard let activity = response.activity ?? response.job else {
            throw WalkieNodeRuntimeError.invalidResponse("Missing activity object.")
        }

        return WalkieAgentRuntimeResult(
            ack: activity.ack,
            sessionId: activity.sessionId,
            providerId: activity.providerId,
            modelId: activity.modelId,
            jobState: WalkieJobState(rawValue: activity.state) ?? .acked
        )
    }

    func cancel(sessionId: String) async {
        do {
            _ = try await send(NodeRuntimeRequest(op: "cancelInvocation", sessionId: sessionId))
        } catch {
            nodeRuntimeLog.warning(
                "Walkie node runtime cancel failed",
                detail: "session=\(sessionId) error=\(error.localizedDescription)"
            )
        }
    }
}

private extension WalkieNodeRuntimeClient {
    struct NodeRuntimeRequest: Encodable {
        let op: String
        var invocation: WalkieAgentInvocation?
        var sessionId: String?

        init(op: String, invocation: WalkieAgentInvocation? = nil, sessionId: String? = nil) {
            self.op = op
            self.invocation = invocation
            self.sessionId = sessionId
        }
    }

    struct NodeRuntimeResponse: Decodable {
        let ok: Bool
        let error: String?
        let pid: Int?
        let version: String?
        let runtime: RuntimeInfo?
        let activity: WalkieRuntimeActivitySnapshot?
        let activities: [WalkieRuntimeActivitySnapshot]?
        let job: WalkieRuntimeActivitySnapshot?
        let jobs: [WalkieRuntimeActivitySnapshot]?
    }

    struct RuntimeInfo: Decodable {
        let id: String
        let name: String
        let capabilities: [String]
        let scoutBridge: WalkieScoutBridgeStatus?
    }

    struct Invocation: Sendable {
        let executableURL: URL
        let arguments: [String]
        let currentDirectoryURL: URL
    }

    final class ProcessBox: @unchecked Sendable {
        let process: Process

        init(_ process: Process) {
            self.process = process
        }
    }

    func send(_ request: NodeRuntimeRequest) async throws -> NodeRuntimeResponse {
        let invocation = try resolveInvocation()
        let process = Process()
        let processBox = ProcessBox(process)
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.currentDirectoryURL
        process.environment = runtimeEnvironment()

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutTask = Task { try await collectOutput(from: stdoutPipe.fileHandleForReading) }
        let stderrTask = Task { try await collectOutput(from: stderrPipe.fileHandleForReading) }

        do {
            try process.run()
        } catch {
            stdoutTask.cancel()
            stderrTask.cancel()
            throw error
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            var data = try encoder.encode(request)
            data.append(0x0A)
            try stdinPipe.fileHandleForWriting.write(contentsOf: data)
            try stdinPipe.fileHandleForWriting.close()
        } catch {
            process.terminate()
            stdoutTask.cancel()
            stderrTask.cancel()
            throw error
        }

        let exitCode = try await awaitTermination(of: processBox)
        let stdoutData = try await stdoutTask.value
        let stderrData = try await stderrTask.value
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard exitCode == 0 else {
            let detail = stderr.isEmpty ? stdout : stderr
            throw WalkieNodeRuntimeError.runtimeFailed(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        do {
            let response = try JSONDecoder().decode(NodeRuntimeResponse.self, from: stdoutData)
            if response.ok {
                return response
            }
            throw WalkieNodeRuntimeError.runtimeFailed(response.error ?? "Unknown runtime error.")
        } catch let error as WalkieNodeRuntimeError {
            throw error
        } catch {
            throw WalkieNodeRuntimeError.invalidResponse(stdout.isEmpty ? error.localizedDescription : stdout)
        }
    }

    func runtimePing(from response: NodeRuntimeResponse) throws -> WalkieRuntimePing {
        guard let runtime = response.runtime else {
            throw WalkieNodeRuntimeError.invalidResponse("Missing runtime object.")
        }

        return WalkieRuntimePing(
            pid: response.pid,
            version: response.version ?? "0.0.0",
            runtimeId: runtime.id,
            runtimeName: runtime.name,
            capabilities: Set(runtime.capabilities.compactMap(WalkieRuntimeCapability.init(rawValue:))),
            scoutBridge: runtime.scoutBridge ?? .pending
        )
    }

    func resolveInvocation() throws -> Invocation {
        guard let runtimeURL = resolveRuntimeURL() else {
            throw WalkieNodeRuntimeError.missingNodeRuntime
        }

        if let bunURL = ExecutableResolver.resolve("bun") {
            return Invocation(
                executableURL: bunURL,
                arguments: [runtimeURL.path(percentEncoded: false)],
                currentDirectoryURL: runtimeURL.deletingLastPathComponent()
            )
        }

        if let nodeURL = ExecutableResolver.resolve("node") {
            return Invocation(
                executableURL: nodeURL,
                arguments: [runtimeURL.path(percentEncoded: false)],
                currentDirectoryURL: runtimeURL.deletingLastPathComponent()
            )
        }

        if FileManager.default.isExecutableFile(atPath: "/usr/bin/env") {
            return Invocation(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["node", runtimeURL.path(percentEncoded: false)],
                currentDirectoryURL: runtimeURL.deletingLastPathComponent()
            )
        }

        throw WalkieNodeRuntimeError.missingNodeExecutable
    }

    func runtimeEnvironment() -> [String: String] {
        var environment = ExecutableResolver.enrichedEnvironment()

        if environment["TALKIE_WALKIE_EXECUTOR_CWD"] == nil,
           let workspaceURL = resolveSourceWorkspaceURL() {
            environment["TALKIE_WALKIE_EXECUTOR_CWD"] = workspaceURL.path(percentEncoded: false)
        }

        return environment
    }

    func resolveSourceWorkspaceURL() -> URL? {
        let fileManager = FileManager.default
        var candidate = URL(fileURLWithPath: #filePath)

        for _ in 0..<12 {
            candidate.deleteLastPathComponent()
            let hasAgentInstructions = fileManager.fileExists(
                atPath: candidate.appending(path: "AGENTS.md").path(percentEncoded: false)
            )
            let hasMacApps = fileManager.fileExists(
                atPath: candidate.appending(path: "apps/macos").path(percentEncoded: false)
            )

            if hasAgentInstructions && hasMacApps {
                return candidate
            }
        }

        return nil
    }

    func resolveRuntimeURL() -> URL? {
        let fileManager = FileManager.default

        if let override = ProcessInfo.processInfo.environment["TALKIE_WALKIE_RUNTIME_NODE"],
           !override.isEmpty,
           fileManager.fileExists(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        var candidates: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appending(path: "Runtime/node/index.mjs"))
        }

        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let appSourceURL = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        candidates.append(appSourceURL.appending(path: "Runtime/node/index.mjs"))

        return candidates.first { fileManager.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    func awaitTermination(of processBox: ProcessBox) async throws -> Int32 {
        let timeoutMs = self.timeoutMs

        return try await withThrowingTaskGroup(of: Int32.self) { group in
            group.addTask {
                while processBox.process.isRunning {
                    try await Task.sleep(for: .milliseconds(25))
                }
                return processBox.process.terminationStatus
            }

            group.addTask {
                try await Task.sleep(for: .milliseconds(timeoutMs))
                if processBox.process.isRunning {
                    processBox.process.terminate()
                }
                throw WalkieNodeRuntimeError.runtimeTimedOut
            }

            defer { group.cancelAll() }

            guard let result = try await group.next() else {
                throw WalkieNodeRuntimeError.invalidResponse("Process ended without a termination result.")
            }

            return result
        }
    }

    func collectOutput(from handle: FileHandle) async throws -> Data {
        var data = Data()
        for try await byte in handle.bytes {
            data.append(byte)
        }
        return data
    }
}
