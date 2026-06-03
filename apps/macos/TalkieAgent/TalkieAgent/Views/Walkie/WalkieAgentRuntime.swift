//
//  WalkieAgentRuntime.swift
//  TalkieAgent
//

import Foundation
import TalkieKit

private let runtimeLog = Log(.workflow)

enum WalkieRuntimeCapability: String, Codable, Sendable {
    case codeExecution
    case computerUse
    case readOnlyData
    case longRunningJobs
}

struct WalkieAgentInvocation: Codable, Sendable {
    let id: UUID
    let channel: WalkieChannel
    let transcript: String
    let instruction: String
    let topLevelModel: WalkieModelUse
    let requestedAt: Date
    let conversationId: String?
    let parentSessionId: String?
    let source: String?
}

struct WalkieAgentRuntimeResult: Sendable {
    let ack: String
    let sessionId: String?
    let providerId: String?
    let modelId: String?
    let jobState: WalkieJobState
}

protocol WalkieAgentRuntime: Sendable {
    var id: String { get }
    var name: String { get }
    var capabilities: Set<WalkieRuntimeCapability> { get }

    var isAvailable: Bool { get async }

    func invoke(_ invocation: WalkieAgentInvocation) async throws -> WalkieAgentRuntimeResult
    func cancel(sessionId: String) async
}

actor WalkieRuntimeRegistry {
    static let shared = WalkieRuntimeRegistry()

    private let runtimes: [any WalkieAgentRuntime] = [
        WalkieNodeDispatcherRuntime(),
        WalkieScoutAgentSessionRuntime(),
    ]

    func runtime(for id: String) -> (any WalkieAgentRuntime)? {
        runtimes.first { $0.id == id }
    }

    func resolve(preferredId: String?) async -> (any WalkieAgentRuntime)? {
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

struct WalkieNodeDispatcherRuntime: WalkieAgentRuntime {
    let id = "walkie-node-dispatcher"
    let name = "Agent Runtime Dispatcher"
    let capabilities: Set<WalkieRuntimeCapability> = [
        .readOnlyData,
        .longRunningJobs,
    ]

    var isAvailable: Bool {
        get async {
            await WalkieNodeRuntimeClient.shared.ping() != nil
        }
    }

    func invoke(_ invocation: WalkieAgentInvocation) async throws -> WalkieAgentRuntimeResult {
        runtimeLog.info(
            "Agent runtime dispatcher invoking agent session",
            detail: "invocation=\(invocation.id.uuidString) channel=\(invocation.channel.code)"
        )
        return try await WalkieNodeRuntimeClient.shared.invoke(invocation)
    }

    func cancel(sessionId: String) async {
        await WalkieNodeRuntimeClient.shared.cancel(sessionId: sessionId)
    }
}

struct WalkieScoutAgentSessionRuntime: WalkieAgentRuntime {
    let id = "scout-agent-session"
    let name = "Scout Agent"
    let capabilities: Set<WalkieRuntimeCapability> = [
        .codeExecution,
        .computerUse,
        .longRunningJobs,
    ]

    var isAvailable: Bool {
        get async {
            guard TalkieSharedSettings.bool(forKey: AgentSettingsKey.walkieScoutRuntimeEnabled) else {
                return false
            }

            let ping = await WalkieNodeRuntimeClient.shared.ping()
            return ping?.scoutBridge == .configured
        }
    }

    func invoke(_ invocation: WalkieAgentInvocation) async throws -> WalkieAgentRuntimeResult {
        runtimeLog.info(
            "Scout runtime invoking agent session",
            detail: "invocation=\(invocation.id.uuidString) channel=\(invocation.channel.code)"
        )

        return try await WalkieNodeRuntimeClient.shared.invoke(invocation)
    }

    func cancel(sessionId: String) async {
        await WalkieNodeRuntimeClient.shared.cancel(sessionId: sessionId)
    }
}

func walkieAgentDisplayName(for adapterId: String?) -> String? {
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
