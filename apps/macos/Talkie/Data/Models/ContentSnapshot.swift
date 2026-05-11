//
//  ContentSnapshot.swift
//  Talkie
//
//  Append-only edit history for note/recording content.
//  Each row is a full snapshot of the text at a point in time.
//  Enables undo at the database level.
//

import Foundation
import GRDB

struct ContentSnapshot: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let recordingId: UUID
    var title: String?
    var text: String
    var source: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        recordingId: UUID,
        title: String? = nil,
        text: String,
        source: Source,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.recordingId = recordingId
        self.title = title
        self.text = text
        self.source = source.rawValue
        self.createdAt = createdAt
    }

    enum Source: String, Codable {
        case dictation      // In-note dictation segment
        case transcription  // Memo/recording transcription result
        case typing         // Manual keyboard edits
        case paste          // Pasted content
        case aiRevision     // AI-assisted rewrite
        case undo           // Reverted to a previous snapshot
        case migration      // Initial snapshot on first save (baseline)
    }

    var sourceEnum: Source? {
        Source(rawValue: source)
    }
}

// MARK: - GRDB Record

extension ContentSnapshot: FetchableRecord, PersistableRecord {
    static let databaseTableName = "content_history"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let recordingId = Column(CodingKeys.recordingId)
        static let title = Column(CodingKeys.title)
        static let text = Column(CodingKeys.text)
        static let source = Column(CodingKeys.source)
        static let createdAt = Column(CodingKeys.createdAt)
    }
}
