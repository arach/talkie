//
//  CodexWatchChannel.swift
//  TalkieWatch
//
//  Compact, property-list-safe conversation state published by iPhone.
//

import Foundation

enum CodexWatchDispatchAction: String {
    case continueTask = "continue"
    case newTask = "new-task"
}

struct CodexWatchChannel: Identifiable, Equatable {
    enum Status: Equatable {
        case ready
        case running
        case queued
        case receiving
        case failed
        case unavailable
        case unknown

        init(_ value: String) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "ready", "idle", "completed", "complete", "done":
                self = .ready
            case "running", "working", "accepted", "submitting", "transcribing":
                self = .running
            case "queued", "waiting":
                self = .queued
            case "receiving", "response", "speaking":
                self = .receiving
            case "failed", "error":
                self = .failed
            case "unavailable", "offline":
                self = .unavailable
            default:
                self = .unknown
            }
        }

        var label: String {
            switch self {
            case .ready: return "READY"
            case .running: return "RUNNING"
            case .queued: return "QUEUED"
            case .receiving: return "RECEIVING"
            case .failed: return "FAILED"
            case .unavailable: return "UNAVAILABLE"
            case .unknown: return "STATUS UNKNOWN"
            }
        }
    }

    let taskID: String
    let title: String
    let project: String
    let workingDirectory: String
    let status: Status
    let updatedAt: Double

    var id: String { taskID }

    init?(propertyList: [String: Any]) {
        guard let taskID = propertyList["taskID"] as? String,
              !taskID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let title = propertyList["title"] as? String,
              let project = propertyList["project"] as? String,
              let workingDirectory = propertyList["cwd"] as? String,
              !workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        self.taskID = taskID
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled task"
            : title
        self.project = project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Unknown project"
            : project
        self.workingDirectory = workingDirectory
        self.status = Status(propertyList["status"] as? String ?? "")

        if let updatedAt = propertyList["updatedAt"] as? Double {
            self.updatedAt = updatedAt
        } else if let updatedAt = propertyList["updatedAt"] as? NSNumber {
            self.updatedAt = updatedAt.doubleValue
        } else {
            self.updatedAt = 0
        }
    }
}
