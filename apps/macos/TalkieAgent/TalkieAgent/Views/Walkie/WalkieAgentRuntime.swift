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

struct WalkieAgentJob: Sendable {
    let id: UUID
    let channel: WalkieChannel
    let transcript: String
    let instruction: String
    let topLevelModel: WalkieModelUse
    let requestedAt: Date
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

    func start(job: WalkieAgentJob) async throws -> WalkieAgentRuntimeResult
    func cancel(sessionId: String) async
}

actor WalkieRuntimeRegistry {
    static let shared = WalkieRuntimeRegistry()

    private let runtimes: [any WalkieAgentRuntime] = [
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

struct WalkieScoutAgentSessionRuntime: WalkieAgentRuntime {
    let id = "scout-agent-session"
    let name = "Scout Agent Session"
    let capabilities: Set<WalkieRuntimeCapability> = [
        .codeExecution,
        .computerUse,
        .longRunningJobs,
    ]

    var isAvailable: Bool {
        get async {
            // This runtime is the intended async executor, but the stdio
            // bridge is not wired yet. Keeping the adapter here makes the
            // boundary explicit without pretending the executor is live.
            TalkieSharedSettings.bool(forKey: AgentSettingsKey.walkieScoutRuntimeEnabled)
        }
    }

    func start(job: WalkieAgentJob) async throws -> WalkieAgentRuntimeResult {
        runtimeLog.info(
            "Walkie Scout runtime accepted job",
            detail: "job=\(job.id.uuidString) channel=\(job.channel.code)"
        )

        return WalkieAgentRuntimeResult(
            ack: "On it. I handed that to Scout and will report back when it finishes.",
            sessionId: job.id.uuidString,
            providerId: job.channel.executorProviderId,
            modelId: job.channel.executorModelId,
            jobState: .working
        )
    }

    func cancel(sessionId: String) async {
        runtimeLog.info("Walkie Scout runtime cancel requested", detail: "session=\(sessionId)")
    }
}
