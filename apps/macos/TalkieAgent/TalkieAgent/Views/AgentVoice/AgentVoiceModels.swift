//
//  AgentVoiceModels.swift
//  TalkieAgent
//

import Foundation

enum AgentVoiceTransmissionMode: String, Codable, Sendable {
    case verbal
    case async
}

enum AgentVoiceExecutorBranchState: Equatable, Sendable {
    case idle
    case working
    case done
    case failed
}

struct AgentVoiceTransmission: Identifiable, Codable, Sendable {
    let id: UUID
    let channelId: UUID
    let code: String
    let userBody: String
    let userDurationMs: Int
    var talkieBody: String?
    var mode: AgentVoiceTransmissionMode
    var topLevelProviderId: String?
    var topLevelProviderName: String?
    var topLevelModelId: String?
    var executorRuntimeId: String?
    var executorRuntimeName: String?
    var executorProviderId: String?
    var executorModelId: String?
    var executorSessionId: String?
    var latencyMs: Int?
    var tokens: Int?
    let startedAt: Date
    var completedAt: Date?
    var jobState: AgentJobState?
}

struct AgentVoiceTransmissionDraft: Sendable {
    let id: UUID
    let channel: AgentChannel
    let code: String
    let userBody: String
    let userDurationMs: Int
    let startedAt: Date

    init(
        id: UUID = UUID(),
        channel: AgentChannel = .defaultChannel,
        code: String = "T01",
        userBody: String,
        userDurationMs: Int,
        startedAt: Date
    ) {
        self.id = id
        self.channel = channel
        self.code = code
        self.userBody = userBody
        self.userDurationMs = userDurationMs
        self.startedAt = startedAt
    }
}

struct AgentVoiceRouteDecision: Sendable {
    let mode: AgentVoiceTransmissionMode
    let reply: String
    let executorInstruction: String?
    let confidence: Double?
    let rationale: String?
}

struct AgentVoiceTurnResult: Sendable {
    let transmission: AgentVoiceTransmission
    let route: AgentVoiceRouteDecision
    let topLevelModel: AgentModelUse
}

enum AgentVoiceOrchestratorError: LocalizedError {
    case noTopLevelModelConfigured
    case emptyRouteReply

    var errorDescription: String? {
        switch self {
        case .noTopLevelModelConfigured:
            return "No LLM provider is configured for talking to agents."
        case .emptyRouteReply:
            return "The agent returned an empty reply."
        }
    }
}
