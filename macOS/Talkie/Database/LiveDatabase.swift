//
//  LiveDatabase.swift
//  TalkieLive
//
//  SQLite database for Live dictations using GRDB.
//  Single source of truth for all TalkieLive persistence.
//

import Foundation
import GRDB
import TalkieKit

private let log = Log(.database)

enum LiveDatabase {
    /// Database filename
    static let dbFilename = "live.sqlite"

    /// Shared folder for all Talkie apps (unsandboxed)
    static let folderName = "Talkie"

    /// The resolved database URL (Application Support, shared by all apps)
    /// ~/Library/Application Support/Talkie/live.sqlite
    /// Falls back to temp directory if Application Support unavailable (should never happen)
    static let databaseURL: URL = {
        let fm = FileManager.default

        // Use shared Application Support directory - all apps are unsandboxed
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let folderURL = appSupport.appendingPathComponent(folderName, isDirectory: true)
            try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let dbURL = folderURL.appendingPathComponent(dbFilename)
            log.info("[LiveDatabase] Using shared database path: \(dbURL.path)")
            return dbURL
        }

        // Fallback to temp directory (should never happen on macOS)
        log.error("[LiveDatabase] Application Support unavailable, using temp directory")
        let tempURL = fm.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
        try? fm.createDirectory(at: tempURL, withIntermediateDirectories: true)
        return tempURL.appendingPathComponent(dbFilename)
    }()

    static let shared: DatabaseQueue = {
        do {
            let fm = FileManager.default

            // Ensure parent directory exists
            let folderURL = databaseURL.deletingLastPathComponent()
            try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

            let dbQueue = try DatabaseQueue(path: databaseURL.path)
            log.info("[LiveDatabase] Opened database at: \(databaseURL.path)")

            var migrator = DatabaseMigrator()

            // v1: Create main table (fresh installs get "dictations", legacy migration renames in v4)
            migrator.registerMigration("v1_utterances") { db in
                // Fresh install: create "dictations" directly, skip v4 rename
                // Legacy: this migration already ran and created "utterances", v4 will rename it
                let hasUtterances = try db.tableExists("utterances")
                let hasDictations = try db.tableExists("dictations")

                if !hasUtterances && !hasDictations {
                    // Fresh install - create with correct name from the start
                    try db.create(table: "dictations") { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("createdAt", .double).notNull()
                    t.column("text", .text).notNull()
                    t.column("mode", .text).notNull()

                    // App context
                    t.column("appBundleID", .text)
                    t.column("appName", .text)
                    t.column("windowTitle", .text)

                    // Recording details
                    t.column("durationSeconds", .double)
                    t.column("wordCount", .integer)
                    t.column("audioFilename", .text)

                    // Transcription
                    t.column("transcriptionModel", .text)
                    t.column("transcriptionStatus", .text).notNull().defaults(to: "success")
                    t.column("transcriptionError", .text)

                    // Performance metrics (perf prefix)
                    t.column("perfEngineMs", .integer)      // Time in TalkieEngine
                    t.column("perfEndToEndMs", .integer)    // Stop recording → delivery
                    t.column("perfInAppMs", .integer)       // TalkieLive processing

                    // Promotion tracking
                    t.column("promotionStatus", .text).notNull().defaults(to: "none")
                    t.column("talkieMemoID", .text)
                    t.column("commandID", .text)

                    // Queue tracking
                    t.column("createdInTalkieView", .integer).notNull().defaults(to: 0)
                    t.column("pasteTimestamp", .double)

                    // Flexible metadata (JSON blob)
                    t.column("sessionID", .text)
                    t.column("metadata", .text)
                    }
                }
                // Else: table already exists (migration already ran or renamed), skip
            }

            // v2: Rename whisperModel → transcriptionModel (now supports Parakeet, etc.)
            // Only run if the old column exists (for existing databases)
            // Note: Checks "utterances" for backwards compat before v4 migration
            migrator.registerMigration("v2_rename_whisperModel") { db in
                // Check if old column exists (check both old and new table names for compat)
                let tableName = try db.tableExists("dictations") ? "dictations" : "utterances"
                let hasOldColumn = try db.columns(in: tableName).contains { $0.name == "whisperModel" }

                if hasOldColumn {
                    try db.execute(sql: "ALTER TABLE \(tableName) RENAME COLUMN whisperModel TO transcriptionModel")
                }
            }

            // v3: Add indexes for common queries (major performance improvement)
            migrator.registerMigration("v3_add_indexes") { db in
                // Detect table name (fresh installs have "dictations", legacy have "utterances" before v4)
                let tableName = try db.tableExists("dictations") ? "dictations" : "utterances"
                let indexPrefix = tableName == "dictations" ? "idx_dictations" : "idx_utterances"

                // Index for ORDER BY createdAt DESC (used in almost every query)
                try db.create(
                    index: "\(indexPrefix)_createdAt",
                    on: tableName,
                    columns: ["createdAt"],
                    ifNotExists: true
                )

                // Composite index for queue picker (fetchQueued, countQueued)
                // Covers: createdInTalkieView = 1 AND pasteTimestamp IS NULL AND promotionStatus = 'none'
                try db.create(
                    index: "\(indexPrefix)_queue",
                    on: tableName,
                    columns: ["createdInTalkieView", "promotionStatus", "pasteTimestamp"],
                    ifNotExists: true
                )

                // Index for retry queries (fetchNeedsRetry, countNeedsRetry)
                // Covers: transcriptionStatus IN ('failed', 'pending') AND audioFilename IS NOT NULL
                try db.create(
                    index: "\(indexPrefix)_retry",
                    on: tableName,
                    columns: ["transcriptionStatus", "audioFilename"],
                    ifNotExists: true
                )

                // Index for app-based filtering (byApp)
                try db.create(
                    index: "\(indexPrefix)_appBundleID",
                    on: tableName,
                    columns: ["appBundleID"],
                    ifNotExists: true
                )

                log.info("[LiveDatabase] Created performance indexes on \(tableName)")
            }

            // v4: Rename table utterances → dictations (terminology clarification)
            migrator.registerMigration("v4_rename_to_dictations") { db in
                // Check if table needs to be renamed (skip if already done)
                if try db.tableExists("utterances") && !db.tableExists("dictations") {
                    // Rename the table
                    try db.execute(sql: "ALTER TABLE utterances RENAME TO dictations")

                    // Rename all indexes to match new table name
                    try db.execute(sql: "DROP INDEX IF EXISTS idx_utterances_createdAt")
                    try db.execute(sql: "DROP INDEX IF EXISTS idx_utterances_queue")
                    try db.execute(sql: "DROP INDEX IF EXISTS idx_utterances_retry")
                    try db.execute(sql: "DROP INDEX IF EXISTS idx_utterances_appBundleID")

                    try db.create(index: "idx_dictations_createdAt", on: "dictations", columns: ["createdAt"])
                    try db.create(index: "idx_dictations_queue", on: "dictations", columns: ["createdInTalkieView", "promotionStatus", "pasteTimestamp"])
                    try db.create(index: "idx_dictations_retry", on: "dictations", columns: ["transcriptionStatus", "audioFilename"])
                    try db.create(index: "idx_dictations_appBundleID", on: "dictations", columns: ["appBundleID"])

                    log.info("[LiveDatabase] Renamed table: utterances → dictations")
                }
            }

            // v5: Add live_state table for real-time state synchronization between apps
            migrator.registerMigration("v5_live_state") { db in
                // Skip if table already exists (may have been created by v4_live_state before rename)
                if try !db.tableExists("live_state") {
                    try db.create(table: "live_state") { t in
                        t.column("id", .integer).primaryKey()
                        t.column("state", .text).notNull() // idle, listening, transcribing, routing
                        t.column("updatedAt", .double).notNull()
                        t.column("elapsedTime", .double).defaults(to: 0)
                        t.column("transcript", .text).defaults(to: "")
                    }

                    // Insert initial idle state
                    try db.execute(
                        sql: "INSERT INTO live_state (id, state, updatedAt) VALUES (1, 'idle', ?)",
                        arguments: [Date().timeIntervalSince1970]
                    )

                    log.info("[LiveDatabase] Created live_state table for real-time sync")
                }
            }

            try migrator.migrate(dbQueue)

            return dbQueue
        } catch {
            // Log error and fall back to in-memory database to prevent crash
            // User will lose persistence but app remains functional
            log.error("[LiveDatabase] Failed to initialize database: \(error.localizedDescription)")
            log.error("[LiveDatabase] Falling back to in-memory database - data will not persist!")

            // Create in-memory database as fallback
            do {
                let memoryDb = try DatabaseQueue()
                var migrator = DatabaseMigrator()
                migrator.registerMigration("v1_memory_fallback") { db in
                    try db.create(table: "dictations") { t in
                        t.autoIncrementedPrimaryKey("id")
                        t.column("createdAt", .double).notNull()
                        t.column("text", .text).notNull()
                        t.column("mode", .text).notNull()
                        t.column("appBundleID", .text)
                        t.column("appName", .text)
                        t.column("windowTitle", .text)
                        t.column("durationSeconds", .double)
                        t.column("wordCount", .integer)
                        t.column("audioFilename", .text)
                        t.column("transcriptionModel", .text)
                        t.column("transcriptionStatus", .text).notNull().defaults(to: "success")
                        t.column("transcriptionError", .text)
                        t.column("perfEngineMs", .integer)
                        t.column("perfEndToEndMs", .integer)
                        t.column("perfInAppMs", .integer)
                        t.column("promotionStatus", .text).notNull().defaults(to: "none")
                        t.column("talkieMemoID", .text)
                        t.column("commandID", .text)
                        t.column("createdInTalkieView", .integer).notNull().defaults(to: 0)
                        t.column("pasteTimestamp", .double)
                        t.column("sessionID", .text)
                        t.column("metadata", .text)
                    }
                    try db.create(table: "live_state") { t in
                        t.column("id", .integer).primaryKey()
                        t.column("state", .text).notNull()
                        t.column("updatedAt", .double).notNull()
                        t.column("elapsedTime", .double).defaults(to: 0)
                        t.column("transcript", .text).defaults(to: "")
                    }
                    try db.execute(
                        sql: "INSERT INTO live_state (id, state, updatedAt) VALUES (1, 'idle', ?)",
                        arguments: [Date().timeIntervalSince1970]
                    )
                }
                try migrator.migrate(memoryDb)
                return memoryDb
            } catch {
                // If even in-memory fails, we have a serious problem - but still don't crash
                log.fault("[LiveDatabase] In-memory database also failed: \(error.localizedDescription)")
                return try! DatabaseQueue() // Last resort: empty in-memory DB
            }
        }
    }()
}

// MARK: - CRUD Operations

extension LiveDatabase {
    /// Store dictation and return its ID (for fire-and-forget enrichment)
    @discardableResult
    static func store(_ utterance: LiveDictation) -> Int64? {
        do {
            return try shared.write { db -> Int64? in
                let mutable = utterance
                try mutable.insert(db)
                // Use lastInsertedRowID as fallback if didInsert didn't populate id
                let insertedId = mutable.id ?? db.lastInsertedRowID
                log.debug( "Stored dictation", detail: "ID: \(insertedId)")
                return insertedId
            }
        } catch {
            log.error( "Store failed", error: error)
            return nil
        }
    }

    static func fetch(id: Int64) -> LiveDictation? {
        try? shared.read { db in
            try LiveDictation.fetchOne(db, id: id)
        }
    }

    static func all() -> [LiveDictation] {
        (try? shared.read { db in
            try LiveDictation
                .order(LiveDictation.Columns.createdAt.desc)
                .fetchAll(db)
        }) ?? []
    }

    static func recent(limit: Int = 100) -> [LiveDictation] {
        (try? shared.read { db in
            try LiveDictation
                .order(LiveDictation.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []
    }

    /// Fetch dictations with ID greater than specified (for incremental updates)
    /// Uses INTEGER PRIMARY KEY for optimal performance - O(log n) seek + O(k) scan
    static func since(id: Int64) -> [LiveDictation] {
        (try? shared.read { db in
            try LiveDictation
                .filter(LiveDictation.Columns.id > id)
                .order(LiveDictation.Columns.id.asc)  // Sequential order for processing
                .fetchAll(db)
        }) ?? []
    }

    static func search(_ query: String) -> [LiveDictation] {
        guard !query.isEmpty else { return all() }
        return (try? shared.read { db in
            try LiveDictation
                .filter(LiveDictation.Columns.text.like("%\(query)%"))
                .order(LiveDictation.Columns.createdAt.desc)
                .fetchAll(db)
        }) ?? []
    }

    static func byApp(_ bundleID: String) -> [LiveDictation] {
        (try? shared.read { db in
            try LiveDictation
                .filter(LiveDictation.Columns.appBundleID == bundleID)
                .order(LiveDictation.Columns.createdAt.desc)
                .fetchAll(db)
        }) ?? []
    }

    static func count() -> Int {
        (try? shared.read { db in
            try LiveDictation.fetchCount(db)
        }) ?? 0
    }

    static func prune(olderThanHours hours: Int) {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 60 * 60)
        let cutoffTS = cutoff.timeIntervalSince1970

        // Get audio filenames for dictations that will be deleted
        let audioFilenames: [String] = (try? shared.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT audioFilename FROM dictations WHERE createdAt < ? AND audioFilename IS NOT NULL",
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
                sql: "DELETE FROM dictations WHERE createdAt < ?",
                arguments: [cutoffTS]
            )
        }
    }

    /// Preview what would be pruned (count and oldest date)
    static func prunePreview(olderThanHours hours: Int) -> (count: Int, oldestDate: Date?, newestDate: Date?) {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 60 * 60)
        let cutoffTS = cutoff.timeIntervalSince1970

        return (try? shared.read { db -> (Int, Date?, Date?) in
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM dictations WHERE createdAt < ?",
                arguments: [cutoffTS]
            ) ?? 0

            let oldest: Double? = try Double.fetchOne(
                db,
                sql: "SELECT MIN(createdAt) FROM dictations WHERE createdAt < ?",
                arguments: [cutoffTS]
            )

            let newest: Double? = try Double.fetchOne(
                db,
                sql: "SELECT MAX(createdAt) FROM dictations WHERE createdAt < ?",
                arguments: [cutoffTS]
            )

            return (
                count,
                oldest.map { Date(timeIntervalSince1970: $0) },
                newest.map { Date(timeIntervalSince1970: $0) }
            )
        }) ?? (0, nil, nil)
    }

    /// Get all audio filenames referenced in database
    static func allAudioFilenames() -> Set<String> {
        let filenames: [String] = (try? shared.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT audioFilename FROM dictations WHERE audioFilename IS NOT NULL"
            )
        }) ?? []
        return Set(filenames)
    }
}

// MARK: - Promotion Methods

extension LiveDatabase {
    static func markAsMemo(id: Int64?, talkieMemoID: String) {
        guard let id else { return }
        try? shared.write { db in
            try db.execute(
                sql: "UPDATE dictations SET promotionStatus = ?, talkieMemoID = ? WHERE id = ?",
                arguments: [PromotionStatus.memo.rawValue, talkieMemoID, id]
            )
        }
    }

    static func markAsCommand(id: Int64?, commandID: String) {
        guard let id else { return }
        try? shared.write { db in
            try db.execute(
                sql: "UPDATE dictations SET promotionStatus = ?, commandID = ? WHERE id = ?",
                arguments: [PromotionStatus.command.rawValue, commandID, id]
            )
        }
    }

    static func markAsIgnored(id: Int64?) {
        guard let id else { return }
        try? shared.write { db in
            try db.execute(
                sql: "UPDATE dictations SET promotionStatus = ? WHERE id = ?",
                arguments: [PromotionStatus.ignored.rawValue, id]
            )
        }
    }

    static func resetPromotion(id: Int64?) {
        guard let id else { return }
        try? shared.write { db in
            try db.execute(
                sql: "UPDATE dictations SET promotionStatus = ?, talkieMemoID = NULL, commandID = NULL WHERE id = ?",
                arguments: [PromotionStatus.none.rawValue, id]
            )
        }
    }
}

// MARK: - Filtered Queries

extension LiveDatabase {
    static func needsAction(limit: Int = 100) -> [LiveDictation] {
        (try? shared.read { db in
            try LiveDictation
                .filter(LiveDictation.Columns.promotionStatus == PromotionStatus.none.rawValue)
                .order(LiveDictation.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []
    }

    static func byStatus(_ status: PromotionStatus, limit: Int = 100) -> [LiveDictation] {
        (try? shared.read { db in
            try LiveDictation
                .filter(LiveDictation.Columns.promotionStatus == status.rawValue)
                .order(LiveDictation.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []
    }

    static func countNeedsAction() -> Int {
        (try? shared.read { db in
            try LiveDictation
                .filter(LiveDictation.Columns.promotionStatus == PromotionStatus.none.rawValue)
                .fetchCount(db)
        }) ?? 0
    }
}

// MARK: - Queue Methods

extension LiveDatabase {
    static func fetchQueued() -> [LiveDictation] {
        (try? shared.read { db in
            try LiveDictation
                .filter(LiveDictation.Columns.createdInTalkieView == 1)
                .filter(LiveDictation.Columns.pasteTimestamp == nil)
                .filter(LiveDictation.Columns.promotionStatus == PromotionStatus.none.rawValue)
                .order(LiveDictation.Columns.createdAt.desc)
                .fetchAll(db)
        }) ?? []
    }

    static func countQueued() -> Int {
        (try? shared.read { db in
            try LiveDictation
                .filter(LiveDictation.Columns.createdInTalkieView == 1)
                .filter(LiveDictation.Columns.pasteTimestamp == nil)
                .filter(LiveDictation.Columns.promotionStatus == PromotionStatus.none.rawValue)
                .fetchCount(db)
        }) ?? 0
    }

    static func markPasted(id: Int64?) {
        guard let id else { return }
        let now = Date().timeIntervalSince1970
        try? shared.write { db in
            try db.execute(
                sql: "UPDATE dictations SET pasteTimestamp = ? WHERE id = ?",
                arguments: [now, id]
            )
        }
    }
}

// MARK: - Live State Methods (Real-time sync between apps)

extension LiveDatabase {
    /// Get current live state
    static func getLiveState() -> (state: String, elapsedTime: TimeInterval, transcript: String)? {
        try? shared.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT state, elapsedTime, transcript FROM live_state WHERE id = 1") else {
                return nil
            }
            return (
                state: row["state"] as String? ?? "idle",
                elapsedTime: row["elapsedTime"] as TimeInterval? ?? 0,
                transcript: row["transcript"] as String? ?? ""
            )
        }
    }

    /// Update live state (called by TalkieLive)
    static func updateLiveState(state: String, elapsedTime: TimeInterval = 0, transcript: String = "") {
        try? shared.write { db in
            try db.execute(
                sql: "UPDATE live_state SET state = ?, updatedAt = ?, elapsedTime = ?, transcript = ? WHERE id = 1",
                arguments: [state, Date().timeIntervalSince1970, elapsedTime, transcript]
            )
        }
    }

    /// Reset to idle state
    static func resetLiveState() {
        updateLiveState(state: "idle", elapsedTime: 0, transcript: "")
    }
}

// MARK: - Transcription Retry Methods

extension LiveDatabase {
    static func fetchNeedsRetry() -> [LiveDictation] {
        (try? shared.read { db in
            try LiveDictation
                .filter(
                    LiveDictation.Columns.transcriptionStatus == TranscriptionStatus.failed.rawValue ||
                    LiveDictation.Columns.transcriptionStatus == TranscriptionStatus.pending.rawValue
                )
                .filter(LiveDictation.Columns.audioFilename != nil)
                .order(LiveDictation.Columns.createdAt.desc)
                .fetchAll(db)
        }) ?? []
    }

    static func countNeedsRetry() -> Int {
        (try? shared.read { db in
            try LiveDictation
                .filter(
                    LiveDictation.Columns.transcriptionStatus == TranscriptionStatus.failed.rawValue ||
                    LiveDictation.Columns.transcriptionStatus == TranscriptionStatus.pending.rawValue
                )
                .filter(LiveDictation.Columns.audioFilename != nil)
                .fetchCount(db)
        }) ?? 0
    }

    static func markTranscriptionSuccess(id: Int64?, text: String, perfEngineMs: Int?, model: String?) {
        guard let id else { return }
        try? shared.write { db in
            try db.execute(
                sql: """
                    UPDATE dictations
                    SET transcriptionStatus = ?, transcriptionError = NULL,
                        text = ?, wordCount = ?, perfEngineMs = ?, transcriptionModel = ?
                    WHERE id = ?
                    """,
                arguments: [
                    TranscriptionStatus.success.rawValue,
                    text,
                    text.split(separator: " ").count,
                    perfEngineMs,
                    model,
                    id
                ]
            )
        }
    }

    static func markTranscriptionFailed(id: Int64?, error: String) {
        guard let id else { return }
        try? shared.write { db in
            try db.execute(
                sql: "UPDATE dictations SET transcriptionStatus = ?, transcriptionError = ? WHERE id = ?",
                arguments: [TranscriptionStatus.failed.rawValue, error, id]
            )
        }
    }

}
