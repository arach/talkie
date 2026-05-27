//
//  ActionEventModel.swift
//  Talkie
//
//  Append-only event stream for the Actions console.
//

import Foundation
import GRDB

struct ActionEventModel: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var actionRunId: UUID
    var sequence: Int
    var kind: Kind
    var level: Level
    var message: String
    var payloadJSON: String
    var createdAt: Date

    enum Kind: String, Codable, Hashable, Sendable {
        case runQueued
        case runStarted
        case runCompleted
        case runFailed
        case runCancelled
        case inputResolved
        case stepStarted
        case stepCompleted
        case stepFailed
        case stepLog
        case artifactCreated
    }

    enum Level: String, Codable, Hashable, Sendable {
        case debug
        case info
        case warning
        case error
    }

    init(
        id: UUID = UUID(),
        actionRunId: UUID,
        sequence: Int = 0,
        kind: Kind,
        level: Level = .info,
        message: String,
        payloadJSON: String = "{}",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.actionRunId = actionRunId
        self.sequence = sequence
        self.kind = kind
        self.level = level
        self.message = message
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
    }
}

extension ActionEventModel: FetchableRecord, PersistableRecord {
    static let databaseTableName = "action_events"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let actionRunId = Column(CodingKeys.actionRunId)
        static let sequence = Column(CodingKeys.sequence)
        static let kind = Column(CodingKeys.kind)
        static let level = Column(CodingKeys.level)
        static let message = Column(CodingKeys.message)
        static let payloadJSON = Column(CodingKeys.payloadJSON)
        static let createdAt = Column(CodingKeys.createdAt)
    }
}
