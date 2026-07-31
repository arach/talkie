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
    /// Number of consecutive bridge operations being retried for this same
    /// submission. A non-zero value means the Mac-owned receipt remains the
    /// source of truth; Talkie is reconnecting rather than creating a duplicate.
    var retryCount: Int
    var updates: [CodexProgressUpdate]
    var response: String?
    var state: CodexLaneActivityState

    init(
        id: UUID = UUID(),
        instruction: String,
        jobID: String? = nil,
        retryCount: Int = 0,
        updates: [CodexProgressUpdate] = [],
        response: String? = nil,
        state: CodexLaneActivityState,
        sentAt: Date = Date()
    ) {
        self.id = id
        self.instruction = instruction
        self.sentAt = sentAt
        self.jobID = jobID
        self.retryCount = retryCount
        self.updates = updates
        self.response = response
        self.state = state
    }

    /// Compact, truthful stage for the deck's always-visible status displays.
    var statusLabel: String {
        if retryCount > 0 { return "RECONNECTING" }

        switch state {
        case .working(let mode):
            if jobID != nil { return mode == .queue ? "QUEUED" : "RECEIVED" }
            return "SENDING"
        case .accepted(let delivery):
            switch delivery {
            case .startedTurn: return "WORKING"
            case .queuedTurn: return "QUEUED"
            case .steeredActiveTurn: return "STEERED"
            }
        case .receiving:
            return "RESPONSE"
        case .failed:
            return "ERROR"
        }
    }
}
