//
//  CodexLaneActivity.swift
//  Talkie iOS
//
//  Ephemeral, truthful host activity for one Codex lane.
//

import Foundation

enum CodexLaneActivityState: Equatable, Sendable {
    case working(CodexMessageMode)
    case accepted(CodexTurnDelivery)
    case receiving(CodexTurnDelivery)
    case failed(String)
}

struct CodexLaneActivity: Identifiable, Equatable, Sendable {
    let id: UUID
    let instruction: String
    let sentAt: Date
    var jobID: String?
    var updates: [CodexProgressUpdate]
    var response: String?
    var state: CodexLaneActivityState

    init(
        id: UUID = UUID(),
        instruction: String,
        jobID: String? = nil,
        updates: [CodexProgressUpdate] = [],
        response: String? = nil,
        state: CodexLaneActivityState,
        sentAt: Date = Date()
    ) {
        self.id = id
        self.instruction = instruction
        self.sentAt = sentAt
        self.jobID = jobID
        self.updates = updates
        self.response = response
        self.state = state
    }
}
