//
//  ActionSubjectRef.swift
//  Talkie
//
//  Polymorphic subject references for ActionRunModel.
//

import Foundation
import GRDB

struct ActionSubjectRef: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var actionRunId: UUID
    var kind: Kind
    var recordId: UUID?
    var assetURLString: String?
    var titleSnapshot: String?
    var sha256: String?
    var createdAt: Date

    enum Kind: String, Codable, Hashable, Sendable {
        case memo
        case capture
        case note
        case screenshot
        case audio
        case selection
        case device
    }

    init(
        id: UUID = UUID(),
        actionRunId: UUID,
        kind: Kind,
        recordId: UUID? = nil,
        assetURLString: String? = nil,
        titleSnapshot: String? = nil,
        sha256: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.actionRunId = actionRunId
        self.kind = kind
        self.recordId = recordId
        self.assetURLString = assetURLString
        self.titleSnapshot = titleSnapshot
        self.sha256 = sha256
        self.createdAt = createdAt
    }
}

extension ActionSubjectRef: FetchableRecord, PersistableRecord {
    static let databaseTableName = "action_subject_refs"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let actionRunId = Column(CodingKeys.actionRunId)
        static let kind = Column(CodingKeys.kind)
        static let recordId = Column(CodingKeys.recordId)
        static let assetURLString = Column(CodingKeys.assetURLString)
        static let titleSnapshot = Column(CodingKeys.titleSnapshot)
        static let sha256 = Column(CodingKeys.sha256)
        static let createdAt = Column(CodingKeys.createdAt)
    }
}
