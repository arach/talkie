//
//  WalkieModels.swift
//  TalkieAgent
//

import Foundation

enum WalkieTransmissionMode: String, Codable, Sendable {
    case verbal
    case async
}

enum WalkieJobState: String, Codable, Sendable {
    case acked
    case working
    case done
    case failed
}

struct WalkieChannel: Identifiable, Codable, Sendable {
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

    static let defaultChannel = WalkieChannel(
        id: UUID(uuidString: "A33C8089-8F07-4E29-AE55-DF0697736420") ?? UUID(),
        code: "CH-01",
        label: "NIGHTOPS",
        systemPrompt: "You are Talkie: brief, direct, useful, and comfortable handing longer work to an executor.",
        topLevelProviderId: nil,
        topLevelModelId: nil,
        executorRuntimeId: nil,
        executorProviderId: nil,
        executorModelId: nil,
        createdAt: Date(timeIntervalSince1970: 0),
        lastTransmissionAt: nil
    )
}

struct WalkieTransmission: Identifiable, Codable, Sendable {
    let id: UUID
    let channelId: UUID
    let code: String
    let userBody: String
    let userDurationMs: Int
    var talkieBody: String?
    var mode: WalkieTransmissionMode
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
    var jobState: WalkieJobState?
}

struct WalkieTransmissionDraft: Sendable {
    let id: UUID
    let channel: WalkieChannel
    let code: String
    let userBody: String
    let userDurationMs: Int
    let startedAt: Date

    init(
        id: UUID = UUID(),
        channel: WalkieChannel = .defaultChannel,
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

struct WalkieModelUse: Sendable {
    let providerId: String
    let providerName: String
    let modelId: String
}

struct WalkieRouteDecision: Sendable {
    let mode: WalkieTransmissionMode
    let reply: String
    let executorInstruction: String?
    let confidence: Double?
    let rationale: String?
}

struct WalkieTurnResult: Sendable {
    let transmission: WalkieTransmission
    let route: WalkieRouteDecision
    let topLevelModel: WalkieModelUse
}

enum WalkieOrchestratorError: LocalizedError {
    case noTopLevelModelConfigured
    case emptyRouteReply

    var errorDescription: String? {
        switch self {
        case .noTopLevelModelConfigured:
            return "No LLM provider is configured for Walkie."
        case .emptyRouteReply:
            return "Walkie returned an empty reply."
        }
    }
}
