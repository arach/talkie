//
//  PastLivesDatabase.swift
//  TalkieLive
//
//  SQLite database for storing utterances using GRDB
//

import Foundation
import GRDB

enum PastLivesDatabase {
    static let shared: DatabaseQueue = {
        do {
            let fm = FileManager.default
            let appSupport = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            let folderURL = appSupport.appendingPathComponent("TalkieLive", isDirectory: true)
            try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

            let dbURL = folderURL.appendingPathComponent("PastLives.sqlite")
            let dbQueue = try DatabaseQueue(path: dbURL.path)

            var migrator = DatabaseMigrator()

            migrator.registerMigration("createLiveUtterance") { db in
                try db.create(table: "live_utterance") { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("createdAt", .double).notNull()
                    t.column("text", .text).notNull()
                    t.column("mode", .text).notNull()
                    t.column("appBundleID", .text)
                    t.column("appName", .text)
                    t.column("windowTitle", .text)
                    t.column("durationSeconds", .double)
                    t.column("wordCount", .integer)
                    t.column("whisperModel", .text)
                    t.column("transcriptionMs", .integer)
                    t.column("sessionID", .text)
                    t.column("metadata", .text)
                }
            }

            // Migration 2: Add audio filename column
            migrator.registerMigration("addAudioFilename") { db in
                try db.alter(table: "live_utterance") { t in
                    t.add(column: "audioFilename", .text)
                }
            }

            // Migration 3: Add promotion tracking columns
            migrator.registerMigration("addPromotionFields") { db in
                try db.alter(table: "live_utterance") { t in
                    t.add(column: "promotionStatus", .text).defaults(to: "none")
                    t.add(column: "talkieMemoID", .text)
                    t.add(column: "commandID", .text)
                }
            }

            // Migration 4: Add implicit queue columns
            migrator.registerMigration("addQueueFields") { db in
                try db.alter(table: "live_utterance") { t in
                    t.add(column: "createdInTalkieView", .integer).notNull().defaults(to: 0)
                    t.add(column: "pasteTimestamp", .double)
                }
            }

            // Migration 5: Add transcription status columns for retry support
            migrator.registerMigration("addTranscriptionStatus") { db in
                try db.alter(table: "live_utterance") { t in
                    t.add(column: "transcriptionStatus", .text).defaults(to: "success")
                    t.add(column: "transcriptionError", .text)
                }
            }

            try migrator.migrate(dbQueue)
            return dbQueue
        } catch {
            fatalError("PastLivesDatabase init error: \(error)")
        }
    }()
}

// MARK: - Database Operations

extension PastLivesDatabase {
    static func store(_ utterance: LiveUtterance) {
        do {
            try shared.write { db in
                _ = try utterance.inserted(db)
            }
        } catch {
            print("[PastLivesDatabase] store error: \(error)")
        }
    }

    static func recent(limit: Int = 100) -> [LiveUtterance] {
        (try? shared.read { db in
            try LiveUtterance
                .order(LiveUtterance.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []
    }

    static func all() -> [LiveUtterance] {
        (try? shared.read { db in
            try LiveUtterance
                .order(LiveUtterance.Columns.createdAt.desc)
                .fetchAll(db)
        }) ?? []
    }

    static func search(_ query: String) -> [LiveUtterance] {
        guard !query.isEmpty else { return all() }
        return (try? shared.read { db in
            try LiveUtterance
                .filter(LiveUtterance.Columns.text.like("%\(query)%"))
                .order(LiveUtterance.Columns.createdAt.desc)
                .fetchAll(db)
        }) ?? []
    }

    static func byApp(_ bundleID: String) -> [LiveUtterance] {
        (try? shared.read { db in
            try LiveUtterance
                .filter(LiveUtterance.Columns.appBundleID == bundleID)
                .order(LiveUtterance.Columns.createdAt.desc)
                .fetchAll(db)
        }) ?? []
    }

    static func delete(_ utterance: LiveUtterance) {
        guard let id = utterance.id else { return }

        // Delete associated audio file
        if let filename = utterance.audioFilename {
            AudioStorage.delete(filename: filename)
        }

        try? shared.write { db in
            _ = try LiveUtterance.deleteOne(db, id: id)
        }
    }

    static func deleteAll() {
        // Delete all audio files first
        AudioStorage.deleteAll()

        try? shared.write { db in
            _ = try LiveUtterance.deleteAll(db)
        }
    }

    static func prune(olderThanHours hours: Int) {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 60 * 60)
        let cutoffTS = cutoff.timeIntervalSince1970

        // First get audio filenames for utterances that will be deleted
        let audioFilenames: [String] = (try? shared.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT audioFilename FROM live_utterance WHERE createdAt < ? AND audioFilename IS NOT NULL",
                arguments: [cutoffTS]
            )
        }) ?? []

        // Delete audio files
        for filename in audioFilenames {
            AudioStorage.delete(filename: filename)
        }

        // Delete database records
        try? shared.write { db in
            try db.execute(
                sql: "DELETE FROM live_utterance WHERE createdAt < ?",
                arguments: [cutoffTS]
            )
        }
    }

    static func count() -> Int {
        (try? shared.read { db in
            try LiveUtterance.fetchCount(db)
        }) ?? 0
    }

    // MARK: - Promotion Methods

    /// Mark a Live as promoted to a Talkie memo
    static func markAsMemo(id: Int64?, talkieMemoID: String) {
        guard let id else { return }
        try? shared.write { db in
            try db.execute(
                sql: """
                    UPDATE live_utterance
                    SET promotionStatus = ?, talkieMemoID = ?
                    WHERE id = ?
                    """,
                arguments: [PromotionStatus.memo.rawValue, talkieMemoID, id]
            )
        }
    }

    /// Mark a Live as promoted to a command/workflow
    static func markAsCommand(id: Int64?, commandID: String) {
        guard let id else { return }
        try? shared.write { db in
            try db.execute(
                sql: """
                    UPDATE live_utterance
                    SET promotionStatus = ?, commandID = ?
                    WHERE id = ?
                    """,
                arguments: [PromotionStatus.command.rawValue, commandID, id]
            )
        }
    }

    /// Mark a Live as ignored (don't bother me again)
    static func markAsIgnored(id: Int64?) {
        guard let id else { return }
        try? shared.write { db in
            try db.execute(
                sql: "UPDATE live_utterance SET promotionStatus = ? WHERE id = ?",
                arguments: [PromotionStatus.ignored.rawValue, id]
            )
        }
    }

    /// Reset a Live back to "none" status (undo promotion)
    static func resetPromotion(id: Int64?) {
        guard let id else { return }
        try? shared.write { db in
            try db.execute(
                sql: """
                    UPDATE live_utterance
                    SET promotionStatus = ?, talkieMemoID = NULL, commandID = NULL
                    WHERE id = ?
                    """,
                arguments: [PromotionStatus.none.rawValue, id]
            )
        }
    }

    // MARK: - Filtered Queries

    /// Get Lives that need action (not promoted, not ignored)
    static func needsAction(limit: Int = 100) -> [LiveUtterance] {
        (try? shared.read { db in
            try LiveUtterance
                .filter(LiveUtterance.Columns.promotionStatus == PromotionStatus.none.rawValue)
                .order(LiveUtterance.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []
    }

    /// Get Lives by promotion status
    static func byStatus(_ status: PromotionStatus, limit: Int = 100) -> [LiveUtterance] {
        (try? shared.read { db in
            try LiveUtterance
                .filter(LiveUtterance.Columns.promotionStatus == status.rawValue)
                .order(LiveUtterance.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []
    }

    /// Count Lives that need action
    static func countNeedsAction() -> Int {
        (try? shared.read { db in
            try LiveUtterance
                .filter(LiveUtterance.Columns.promotionStatus == PromotionStatus.none.rawValue)
                .fetchCount(db)
        }) ?? 0
    }

    // MARK: - Implicit Queue Methods

    /// Fetch queued Lives (created in Talkie, never pasted, not promoted)
    static func fetchQueued() -> [LiveUtterance] {
        (try? shared.read { db in
            try LiveUtterance
                .filter(LiveUtterance.Columns.createdInTalkieView == 1)
                .filter(LiveUtterance.Columns.pasteTimestamp == nil)
                .filter(LiveUtterance.Columns.promotionStatus == PromotionStatus.none.rawValue)
                .order(LiveUtterance.Columns.createdAt.desc)
                .fetchAll(db)
        }) ?? []
    }

    /// Count queued Lives
    static func countQueued() -> Int {
        (try? shared.read { db in
            try LiveUtterance
                .filter(LiveUtterance.Columns.createdInTalkieView == 1)
                .filter(LiveUtterance.Columns.pasteTimestamp == nil)
                .filter(LiveUtterance.Columns.promotionStatus == PromotionStatus.none.rawValue)
                .fetchCount(db)
        }) ?? 0
    }

    /// Mark a Live as pasted (exits the queue)
    static func markPasted(id: Int64?) {
        guard let id else { return }
        let now = Date().timeIntervalSince1970
        try? shared.write { db in
            try db.execute(
                sql: "UPDATE live_utterance SET pasteTimestamp = ? WHERE id = ?",
                arguments: [now, id]
            )
        }
    }

    /// Fetch a single Live by ID
    static func fetch(id: Int64) -> LiveUtterance? {
        try? shared.read { db in
            try LiveUtterance.fetchOne(db, id: id)
        }
    }

    // MARK: - Transcription Retry Methods

    /// Fetch Lives that need transcription retry (failed or pending with audio)
    static func fetchNeedsRetry() -> [LiveUtterance] {
        (try? shared.read { db in
            try LiveUtterance
                .filter(
                    LiveUtterance.Columns.transcriptionStatus == TranscriptionStatus.failed.rawValue ||
                    LiveUtterance.Columns.transcriptionStatus == TranscriptionStatus.pending.rawValue
                )
                .filter(LiveUtterance.Columns.audioFilename != nil)
                .order(LiveUtterance.Columns.createdAt.desc)
                .fetchAll(db)
        }) ?? []
    }

    /// Count Lives that need transcription retry
    static func countNeedsRetry() -> Int {
        (try? shared.read { db in
            try LiveUtterance
                .filter(
                    LiveUtterance.Columns.transcriptionStatus == TranscriptionStatus.failed.rawValue ||
                    LiveUtterance.Columns.transcriptionStatus == TranscriptionStatus.pending.rawValue
                )
                .filter(LiveUtterance.Columns.audioFilename != nil)
                .fetchCount(db)
        }) ?? 0
    }

    /// Update transcription result (success)
    static func markTranscriptionSuccess(id: Int64?, text: String, transcriptionMs: Int?, model: String?) {
        guard let id else { return }
        try? shared.write { db in
            try db.execute(
                sql: """
                    UPDATE live_utterance
                    SET transcriptionStatus = ?, transcriptionError = NULL,
                        text = ?, wordCount = ?, transcriptionMs = ?, whisperModel = ?
                    WHERE id = ?
                    """,
                arguments: [
                    TranscriptionStatus.success.rawValue,
                    text,
                    text.split(separator: " ").count,
                    transcriptionMs,
                    model,
                    id
                ]
            )
        }
    }

    /// Update transcription result (failed)
    static func markTranscriptionFailed(id: Int64?, error: String) {
        guard let id else { return }
        try? shared.write { db in
            try db.execute(
                sql: """
                    UPDATE live_utterance
                    SET transcriptionStatus = ?, transcriptionError = ?
                    WHERE id = ?
                    """,
                arguments: [TranscriptionStatus.failed.rawValue, error, id]
            )
        }
    }
}
