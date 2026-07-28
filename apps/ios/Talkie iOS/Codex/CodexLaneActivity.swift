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
    var response: String?
    var state: CodexLaneActivityState

    init(
        id: UUID = UUID(),
        instruction: String,
        response: String? = nil,
        state: CodexLaneActivityState,
        sentAt: Date = Date()
    ) {
        self.id = id
        self.instruction = instruction
        self.sentAt = sentAt
        self.response = response
        self.state = state
    }
}
