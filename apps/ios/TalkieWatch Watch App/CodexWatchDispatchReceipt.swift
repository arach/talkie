//
//  CodexWatchDispatchReceipt.swift
//  TalkieWatch
//
//  Fresh-task delivery state for one Watch-originated Codex dispatch.
//

import Foundation

struct CodexWatchDispatchReceipt: Identifiable, Equatable, Codable {
    enum State: String, Equatable, Codable {
        case sending
        case queued
        case transferred
        case received
        case running
        case completed
        case failed

        init?(_ value: String) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "sending": self = .sending
            case "queued", "waiting": self = .queued
            case "transferred", "awaiting-receipt": self = .transferred
            case "received": self = .received
            case "running", "working", "transcribing", "accepted": self = .running
            case "completed", "complete", "succeeded", "done": self = .completed
            case "failed", "error": self = .failed
            default: return nil
            }
        }

        var label: String {
            switch self {
            case .sending: return "SENDING TO PHONE"
            case .queued: return "QUEUED · PHONE UNAVAILABLE"
            case .transferred: return "WAITING FOR PHONE RECEIPT"
            case .received: return "PHONE RECEIVED"
            case .running: return "CODEX RUNNING"
            case .completed: return "CODEX COMPLETED"
            case .failed: return "DISPATCH FAILED"
            }
        }

        var isTerminal: Bool {
            switch self {
            case .completed, .failed: return true
            case .sending, .queued, .transferred, .received, .running: return false
            }
        }

        /// Monotonic delivery progress. WatchConnectivity callbacks can arrive
        /// after a newer phone-side receipt, so transport acknowledgements must
        /// never move the visible state backward.
        var progressRank: Int {
            switch self {
            case .sending: return 0
            case .queued: return 1
            case .transferred: return 2
            case .received: return 3
            case .running: return 4
            case .completed, .failed: return 5
            }
        }
    }

    let requestID: UUID
    let hostID: String
    let taskID: String
    let state: State
    let detail: String?
    let updatedAt: Double

    var id: UUID { requestID }

    init(
        requestID: UUID,
        hostID: String,
        taskID: String,
        state: State,
        detail: String? = nil,
        updatedAt: Double = Date().timeIntervalSince1970
    ) {
        self.requestID = requestID
        self.hostID = hostID
        self.taskID = taskID
        self.state = state
        self.detail = detail
        self.updatedAt = updatedAt
    }

    init?(propertyList: [String: Any]) {
        guard let requestIDString = propertyList["requestID"] as? String,
              let requestID = UUID(uuidString: requestIDString),
              let hostID = propertyList["hostID"] as? String,
              !hostID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let taskID = propertyList["taskID"] as? String,
              !taskID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let rawState = propertyList["status"] as? String,
              let state = State(rawState) else {
            return nil
        }

        self.requestID = requestID
        self.hostID = hostID
        self.taskID = taskID
        self.state = state
        self.detail = propertyList["detail"] as? String
        self.updatedAt = propertyList["updatedAt"] as? Double ?? Date().timeIntervalSince1970
    }
}
