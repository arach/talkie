//
//  AgentRuntime.swift
//  TalkieAgent
//

import Foundation
import TalkieKit

private let runtimeLog = Log(.workflow)

enum AgentRuntimeCapability: String, Codable, Sendable {
    case codeExecution
    case computerUse
    case readOnlyData
    case longRunningJobs
}

enum AgentJobState: String, Codable, Sendable {
    case acked
    case working
    case done
    case failed
}

struct AgentChannel: Identifiable, Codable, Sendable {
    let id: UUID
    var code: String
    var label: String
    var systemPrompt: String
    var topLevelProviderId: String?
    var topLevelModelId: String?
    var executorRuntimeId: String?
    var executorProviderId: String?
    var executorModelId: String?
    var createdAt: Date
    var lastTransmissionAt: Date?

    static let defaultChannel = AgentChannel(
        id: UUID(uuidString: "A33C8089-8F07-4E29-AE55-DF0697736420") ?? UUID(),
        code: "CH-01",
        label: "NIGHTOPS",
        systemPrompt: "You are Talkie: brief, direct, useful, and comfortable handing longer work to an agent.",
        topLevelProviderId: nil,
        topLevelModelId: nil,
        executorRuntimeId: nil,
        executorProviderId: nil,
        executorModelId: nil,
        createdAt: Date(timeIntervalSince1970: 0),
        lastTransmissionAt: nil
    )
}

struct AgentModelUse: Codable, Sendable {
    let providerId: String
    let providerName: String
    let modelId: String
}

struct AgentInvocation: Codable, Sendable {
    let id: UUID
    let channel: AgentChannel
    let transcript: String
    let instruction: String
    let topLevelModel: AgentModelUse
    let requestedAt: Date
    let conversationId: String?
    let parentSessionId: String?
    let source: String?
}

struct AgentRuntimeResult: Sendable {
    let ack: String
    let sessionId: String?
    let providerId: String?
    let modelId: String?
    let jobState: AgentJobState
}

protocol AgentRuntime: Sendable {
    var id: String { get }
    var name: String { get }
    var capabilities: Set<AgentRuntimeCapability> { get }

    var isAvailable: Bool { get async }

    func invoke(_ invocation: AgentInvocation) async throws -> AgentRuntimeResult
    func cancel(sessionId: String) async
}

actor AgentRuntimeRegistry {
    static let shared = AgentRuntimeRegistry()

    private let runtimes: [any AgentRuntime] = [
        NodeDispatcherRuntime(),
        ScoutAgentSessionRuntime(),
    ]

    func runtime(for id: String) -> (any AgentRuntime)? {
        let normalizedId = id == NodeDispatcherRuntime.legacyId ? NodeDispatcherRuntime.currentId : id
        return runtimes.first { $0.id == normalizedId }
    }

    func resolve(preferredId: String?) async -> (any AgentRuntime)? {
        if let preferredId, let runtime = runtime(for: preferredId), await runtime.isAvailable {
            return runtime
        }

        for runtime in runtimes {
            if await runtime.isAvailable {
                return runtime
            }
        }

        return nil
    }
}

struct NodeDispatcherRuntime: AgentRuntime {
    static let currentId = "agent-node-dispatcher"
    static let legacyId = "walkie-node-dispatcher"

    let id = currentId
    let name = "Agent Runtime Dispatcher"
    let capabilities: Set<AgentRuntimeCapability> = [
        .readOnlyData,
        .longRunningJobs,
    ]

    var isAvailable: Bool {
        get async {
            await AgentRuntimeClient.shared.ping() != nil
        }
    }

    func invoke(_ invocation: AgentInvocation) async throws -> AgentRuntimeResult {
        runtimeLog.info(
            "Agent runtime dispatcher invoking agent session",
            detail: "invocation=\(invocation.id.uuidString) channel=\(invocation.channel.code)"
        )
        return try await AgentRuntimeClient.shared.invoke(invocation)
    }

    func cancel(sessionId: String) async {
        await AgentRuntimeClient.shared.cancel(sessionId: sessionId)
    }
}

struct ScoutAgentSessionRuntime: AgentRuntime {
    let id = "scout-agent-session"
    let name = "Scout Agent"
    let capabilities: Set<AgentRuntimeCapability> = [
        .codeExecution,
        .computerUse,
        .longRunningJobs,
    ]

    var isAvailable: Bool {
        get async {
            guard TalkieSharedSettings.bool(forKey: AgentSettingsKey.agentRuntimeScoutEnabled) else {
                return false
            }

            let ping = await AgentRuntimeClient.shared.ping()
            return ping?.scoutBridge == .configured
        }
    }

    func invoke(_ invocation: AgentInvocation) async throws -> AgentRuntimeResult {
        runtimeLog.info(
            "Scout runtime invoking agent session",
            detail: "invocation=\(invocation.id.uuidString) channel=\(invocation.channel.code)"
        )

        return try await AgentRuntimeClient.shared.invoke(invocation)
    }

    func cancel(sessionId: String) async {
        await AgentRuntimeClient.shared.cancel(sessionId: sessionId)
    }
}

func agentRuntimeDisplayName(for adapterId: String?) -> String? {
    switch adapterId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "codex":
        return "Codex"
    case "claude-code", "claude":
        return "Claude Code"
    case "opencode", "open-code":
        return "OpenCode"
    case "pi":
        return "Pi"
    case "echo":
        return "Echo"
    default:
        let trimmed = adapterId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
