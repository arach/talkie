//
//  AgentRuntimeClient.swift
//  TalkieAgent
//

import Foundation
import TalkieKit

private let agentRuntimeClientLog = Log(.workflow)

enum AgentScoutBridgeStatus: String, Codable, Sendable {
    case pending
    case configured
}

struct AgentRuntimePing: Equatable, Sendable {
    let pid: Int?
    let version: String
    let runtimeId: String
    let runtimeName: String
    let capabilities: Set<AgentRuntimeCapability>
    let scoutBridge: AgentScoutBridgeStatus
    let agents: [AgentRuntimeAgentSnapshot]
}

struct AgentRuntimeAgentSnapshot: Identifiable, Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let adapterType: String
    let status: String
    let isAvailable: Bool
    let isPreferred: Bool?
    let executable: String?
    let executablePath: String?
    let detail: String?
    let capabilities: [String]
    let activeSessions: Int?
    let lastSeenAt: String?
}

struct AgentRuntimeActivitySnapshot: Decodable, Equatable, Sendable {
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

struct AgentRuntimeStatus: Equatable, Sendable {
    let ping: AgentRuntimePing
    let activities: [AgentRuntimeActivitySnapshot]
}

enum AgentRuntimeClientError: LocalizedError, Sendable {
    case missingNodeRuntime
    case missingNodeExecutable
    case runtimeFailed(String)
    case runtimeTimedOut
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingNodeRuntime:
            return "Agent node runtime was not found."
        case .missingNodeExecutable:
            return "Bun or Node.js was not found."
        case .runtimeFailed(let detail):
            return "Agent node runtime failed: \(detail)"
        case .runtimeTimedOut:
            return "Agent node runtime timed out."
        case .invalidResponse(let detail):
            return "Agent node runtime returned an invalid response: \(detail)"
        }
    }
}

actor AgentRuntimeClient {
    static let shared = AgentRuntimeClient()

    private let timeoutMs = 10_000

    func ping() async -> AgentRuntimePing? {
        do {
            let response = try await send(NodeRuntimeRequest(op: "ping"))
            return try runtimePing(from: response)
        } catch {
            agentRuntimeClientLog.debug("Agent runtime ping failed", detail: error.localizedDescription)
            return nil
        }
    }

    func status() async throws -> AgentRuntimeStatus {
        let response = try await send(NodeRuntimeRequest(op: "status"))
        return AgentRuntimeStatus(
            ping: try runtimePing(from: response),
            activities: response.activities ?? response.jobs ?? []
        )
    }

    func invoke(_ invocation: AgentInvocation) async throws -> AgentRuntimeResult {
        let response = try await send(NodeRuntimeRequest(op: "invoke", invocation: invocation))
        guard let activity = response.activity ?? response.job else {
            throw AgentRuntimeClientError.invalidResponse("Missing activity object.")
        }

        return AgentRuntimeResult(
            ack: activity.ack,
            sessionId: activity.sessionId,
            providerId: activity.providerId,
            modelId: activity.modelId,
            jobState: AgentJobState(rawValue: activity.state) ?? .acked
        )
    }

    func cancel(sessionId: String) async {
        do {
            _ = try await send(NodeRuntimeRequest(op: "cancelInvocation", sessionId: sessionId))
        } catch {
            agentRuntimeClientLog.warning(
                "Agent runtime cancel failed",
                detail: "session=\(sessionId) error=\(error.localizedDescription)"
            )
        }
    }
}

private extension AgentRuntimeClient {
    struct NodeRuntimeRequest: Encodable {
        let op: String
        var invocation: AgentInvocation?
        var sessionId: String?

        init(op: String, invocation: AgentInvocation? = nil, sessionId: String? = nil) {
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
        let agents: [AgentRuntimeAgentSnapshot]?
        let activity: AgentRuntimeActivitySnapshot?
        let activities: [AgentRuntimeActivitySnapshot]?
        let job: AgentRuntimeActivitySnapshot?
        let jobs: [AgentRuntimeActivitySnapshot]?
    }

    struct RuntimeInfo: Decodable {
        let id: String
        let name: String
        let capabilities: [String]
        let scoutBridge: AgentScoutBridgeStatus?
        let agents: [AgentRuntimeAgentSnapshot]?
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
            throw AgentRuntimeClientError.runtimeFailed(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        do {
            let response = try JSONDecoder().decode(NodeRuntimeResponse.self, from: stdoutData)
            if response.ok {
                return response
            }
            throw AgentRuntimeClientError.runtimeFailed(response.error ?? "Unknown runtime error.")
        } catch let error as AgentRuntimeClientError {
            throw error
        } catch {
            throw AgentRuntimeClientError.invalidResponse(stdout.isEmpty ? error.localizedDescription : stdout)
        }
    }

    func runtimePing(from response: NodeRuntimeResponse) throws -> AgentRuntimePing {
        guard let runtime = response.runtime else {
            throw AgentRuntimeClientError.invalidResponse("Missing runtime object.")
        }

        return AgentRuntimePing(
            pid: response.pid,
            version: response.version ?? "0.0.0",
            runtimeId: runtime.id,
            runtimeName: runtime.name,
            capabilities: Set(runtime.capabilities.compactMap(AgentRuntimeCapability.init(rawValue:))),
            scoutBridge: runtime.scoutBridge ?? .pending,
            agents: runtime.agents ?? response.agents ?? []
        )
    }

    func resolveInvocation() throws -> Invocation {
        guard let runtimeURL = resolveRuntimeURL() else {
            throw AgentRuntimeClientError.missingNodeRuntime
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

        throw AgentRuntimeClientError.missingNodeExecutable
    }

    func runtimeEnvironment() -> [String: String] {
        var environment = ExecutableResolver.enrichedEnvironment()

        if environment["TALKIE_AGENT_EXECUTOR_CWD"] == nil,
           environment["TALKIE_WALKIE_EXECUTOR_CWD"] == nil,
           let workspaceURL = resolveSourceWorkspaceURL() {
            environment["TALKIE_AGENT_EXECUTOR_CWD"] = workspaceURL.path(percentEncoded: false)
        }

        if let codexPath = ExecutableResolver.resolvePath("codex") {
            environment["OPENSCOUT_CODEX_BIN"] = environment["OPENSCOUT_CODEX_BIN"] ?? codexPath
            environment["CODEX_BIN"] = environment["CODEX_BIN"] ?? codexPath
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

        let environment = ProcessInfo.processInfo.environment
        if let override = environment["TALKIE_AGENT_RUNTIME_NODE"] ?? environment["TALKIE_WALKIE_RUNTIME_NODE"],
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
                throw AgentRuntimeClientError.runtimeTimedOut
            }

            defer { group.cancelAll() }

            guard let result = try await group.next() else {
                throw AgentRuntimeClientError.invalidResponse("Process ended without a termination result.")
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
