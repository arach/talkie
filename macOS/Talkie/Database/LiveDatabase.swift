//
//  LiveDatabase.swift
//  TalkieLive
//
//  SQLite database for Live utterances using GRDB.
//  Single source of truth for all TalkieLive persistence.
//

import Foundation
import GRDB
import os

private let logger = Logger(subsystem: "jdi.talkie.live", category: "LiveDatabase")

enum LiveDatabase {
    /// Database filename
    static let dbFilename = "live.sqlite"

    /// Shared folder for all Talkie apps (unsandboxed)
    static let folderName = "Talkie"

    /// The resolved database URL (Application Support, shared by all apps)
    /// ~/Library/Application Support/Talkie/live.sqlite
    static let databaseURL: URL = {
        let fm = FileManager.default

        // Use shared Application Support directory - all apps are unsandboxed
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let folderURL = appSupport.appendingPathComponent(folderName, isDirectory: true)
            try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let dbURL = folderURL.appendingPathComponent(dbFilename)
            logger.info("[LiveDatabase] Using shared database path: \(dbURL.path)")
            return dbURL
        }

        fatalError("Could not determine database location")
    }()

    static let shared: DatabaseQueue = {
        do {
            let fm = FileManager.default

            // Ensure parent directory exists
            let folderURL = databaseURL.deletingLastPathComponent()
            try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

            let dbQueue = try DatabaseQueue(path: databaseURL.path)
            logger.info("[LiveDatabase] Opened database at: \(databaseURL.path)")

            var migrator = DatabaseMigrator()

            // Single clean schema for utterances table
            migrator.registerMigration("v1_utterances") { db in
                try db.create(table: "utterances") { t in
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
                // Index for ORDER BY createdAt DESC (used in almost every query)
                try db.create(
                    index: "idx_utterances_createdAt",
                    on: "utterances",
                    columns: ["createdAt"]
                )

                // Composite index for queue picker (fetchQueued, countQueued)
                // Covers: createdInTalkieView = 1 AND pasteTimestamp IS NULL AND promotionStatus = 'none'
                try db.create(
                    index: "idx_utterances_queue",
                    on: "utterances",
                    columns: ["createdInTalkieView", "promotionStatus", "pasteTimestamp"]
                )

                // Index for retry queries (fetchNeedsRetry, countNeedsRetry)
                // Covers: transcriptionStatus IN ('failed', 'pending') AND audioFilename IS NOT NULL
                try db.create(
                    index: "idx_utterances_retry",
                    on: "utterances",
                    columns: ["transcriptionStatus", "audioFilename"]
                )

                // Index for app-based filtering (byApp)
                try db.create(
                    index: "idx_utterances_appBundleID",
                    on: "utterances",
                    columns: ["appBundleID"]
                )

                logger.info("[LiveDatabase] Created performance indexes")
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

                    logger.info("[LiveDatabase] Renamed table: utterances → dictations")
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

                    logger.info("[LiveDatabase] Created live_state table for real-time sync")
                }
            }

            try migrator.migrate(dbQueue)

            // One-time migration from old PastLives.sqlite
            migrateFromOldDatabase(to: dbQueue)

            return dbQueue
        } catch {
            fatalError("LiveDatabase init error: \(error)")
        }
    }()
}

// MARK: - CRUD Operations

extension LiveDatabase {
    /// Store utterance and return its ID (for fire-and-forget enrichment)
    @discardableResult
    static func store(_ utterance: LiveDictation) -> Int64? {
        do {
            return try shared.write { db -> Int64? in
                let mutable = utterance
                try mutable.insert(db)
                // Use lastInsertedRowID as fallback if didInsert didn't populate id
                let insertedId = mutable.id ?? db.lastInsertedRowID
                NSLog("[LiveDatabase] Stored utterance with ID: \(insertedId)")
                return insertedId
            }
        } catch {
            NSLog("[LiveDatabase] store error: \(error)")
            logger.error("[LiveDatabase] store error: \(error)")
            return nil
        }
    }

    /// Update metadata fields for an existing utterance (used by fire-and-forget enrichment)
    static func updateMetadata(id: Int64, metadata: UtteranceMetadata) {
        do {
            try shared.write { db in
                // Build JSON from enriched fields
                var metaDict: [String: String] = [:]
                if let url = metadata.documentURL { metaDict["documentURL"] = url }
                if let url = metadata.browserURL { metaDict["browserURL"] = url }
                if let role = metadata.focusedElementRole { metaDict["focusedElementRole"] = role }
                if let value = metadata.focusedElementValue { metaDict["focusedElementValue"] = value }
                if let dir = metadata.terminalWorkingDir { metaDict["terminalWorkingDir"] = dir }

                let metadataJSON = metaDict.isEmpty ? nil : (try? JSONEncoder().encode(metaDict)).flatMap { String(data: $0, encoding: .utf8) }

                try db.execute(
                    sql: "UPDATE dictations SET metadata = ? WHERE id = ?",
                    arguments: [metadataJSON, id]
                )
            }
            logger.debug("[LiveDatabase] Updated metadata for utterance \(id)")
        } catch {
            logger.error("[LiveDatabase] updateMetadata error: \(error)")
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

    /// Fetch utterances created after a specific timestamp (for incremental updates)
    static func since(timestamp: Date) -> [LiveDictation] {
        (try? shared.read { db in
            try LiveDictation
                .filter(LiveDictation.Columns.createdAt > timestamp.timeIntervalSinceReferenceDate)
                .order(LiveDictation.Columns.createdAt.desc)
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

    static func delete(_ utterance: LiveDictation) {
        guard let id = utterance.id else { return }

        // Delete associated audio file
        if let filename = utterance.audioFilename {
            AudioStorage.delete(filename: filename)
        }

        try? shared.write { db in
            _ = try LiveDictation.deleteOne(db, id: id)
        }
    }

    static func deleteAll() {
        AudioStorage.deleteAll()
        try? shared.write { db in
            _ = try LiveDictation.deleteAll(db)
        }
    }

    static func count() -> Int {
        (try? shared.read { db in
            try LiveDictation.fetchCount(db)
        }) ?? 0
    }

    static func prune(olderThanHours hours: Int) {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 60 * 60)
        let cutoffTS = cutoff.timeIntervalSince1970

        // Get audio filenames for utterances that will be deleted
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

    /// Update utterance text (for retranscription)
    static func updateText(for id: Int64, newText: String) {
        try? shared.write { db in
            try db.execute(
                sql: """
                    UPDATE dictations
                    SET text = ?, wordCount = ?
                    WHERE id = ?
                    """,
                arguments: [
                    newText,
                    newText.split(separator: " ").count,
                    id
                ]
            )
        }
    }
}

// MARK: - One-Time Migration from Old Database

private extension LiveDatabase {
    static func migrateFromOldDatabase(to dbQueue: DatabaseQueue) {
        let fm = FileManager.default

        // Build list of potential old database locations
        var oldDbPaths: [URL] = []
        var jsonPaths: [URL] = []

        // Check for old data from previous sandboxed setup
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            // 1. Try old Group Container location (manual path, no longer accessible via API)
            let oldGroupPath = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Group Containers/group.com.jdi.talkie/TalkieLive")
            if fm.fileExists(atPath: oldGroupPath.path) {
                oldDbPaths.append(oldGroupPath.appendingPathComponent("PastLives.sqlite"))
                jsonPaths.append(oldGroupPath.appendingPathComponent("utterances.json"))
                logger.info("[LiveDatabase] Found old Group Container data for migration: \(oldGroupPath.path)")
            }

            // 2. Check old Application Support/TalkieLive/ location
            let oldAppSupport = appSupport.appendingPathComponent("TalkieLive")
            oldDbPaths.append(oldAppSupport.appendingPathComponent("PastLives.sqlite"))
            jsonPaths.append(oldAppSupport.appendingPathComponent("utterances.json"))
            logger.info("[LiveDatabase] Checking old App Support for migration: \(oldAppSupport.path)")
        }

        // Log existing count but continue to check for additional old data
        let existingCount = (try? dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dictations")
        }) ?? 0

        logger.info("[LiveDatabase] Current record count: \(existingCount), checking for old data to migrate...")

        var migratedCount = 0

        // 1. Migrate from old SQLite databases (check all locations)
        for oldDbPath in oldDbPaths where fm.fileExists(atPath: oldDbPath.path) {
            logger.info("[LiveDatabase] Found old database at: \(oldDbPath.path)")
            do {
                let oldDb = try DatabaseQueue(path: oldDbPath.path)

                // Check which column names exist (old schema used transcriptionMs, new uses perfEngineMs)
                let columns = try oldDb.read { db -> Set<String> in
                    let cursor = try Row.fetchCursor(db, sql: "PRAGMA table_info(live_utterance)")
                    var cols = Set<String>()
                    while let row = try cursor.next() {
                        if let name = row["name"] as? String {
                            cols.insert(name)
                        }
                    }
                    return cols
                }

                // Build query based on available columns
                let perfEngineCol = columns.contains("perfEngineMs") ? "perfEngineMs" :
                                   (columns.contains("transcriptionMs") ? "transcriptionMs" : "NULL")
                let perfEndToEndCol = columns.contains("perfEndToEndMs") ? "perfEndToEndMs" : "NULL"
                let perfInAppCol = columns.contains("perfInAppMs") ? "perfInAppMs" : "NULL"

                let rows = try oldDb.read { db in
                    try Row.fetchAll(db, sql: """
                        SELECT createdAt, text, mode, appBundleID, appName, windowTitle,
                               durationSeconds, wordCount, whisperModel, audioFilename,
                               \(perfEngineCol) as perfEngineMs,
                               \(perfEndToEndCol) as perfEndToEndMs,
                               \(perfInAppCol) as perfInAppMs,
                               transcriptionStatus, transcriptionError,
                               promotionStatus, talkieMemoID, commandID,
                               createdInTalkieView, pasteTimestamp, sessionID, metadata
                        FROM live_utterance
                        ORDER BY createdAt
                        """)
                }

                try dbQueue.write { db in
                    for row in rows {
                        let text: String = row["text"] ?? ""
                        guard !text.isEmpty else { continue }

                        // Check for duplicate by timestamp (within 1 second)
                        let createdAt = row["createdAt"] as Double? ?? 0
                        let exists = try Int.fetchOne(db, sql: """
                            SELECT COUNT(*) FROM dictations WHERE ABS(createdAt - ?) < 1
                            """, arguments: [createdAt]) ?? 0

                        if exists > 0 { continue }

                        try db.execute(
                            sql: """
                                INSERT INTO dictations (
                                    createdAt, text, mode, appBundleID, appName, windowTitle,
                                    durationSeconds, wordCount, transcriptionModel, audioFilename,
                                    perfEngineMs, perfEndToEndMs, perfInAppMs,
                                    transcriptionStatus, transcriptionError,
                                    promotionStatus, talkieMemoID, commandID,
                                    createdInTalkieView, pasteTimestamp, sessionID, metadata
                                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                                """,
                            arguments: [
                                row["createdAt"] as Double?,
                                text,
                                row["mode"] as String? ?? "typing",
                                row["appBundleID"] as String?,
                                row["appName"] as String?,
                                row["windowTitle"] as String?,
                                row["durationSeconds"] as Double?,
                                row["wordCount"] as Int?,
                                row["whisperModel"] as String?,
                                row["audioFilename"] as String?,
                                row["perfEngineMs"] as Int?,
                                row["perfEndToEndMs"] as Int?,
                                row["perfInAppMs"] as Int?,
                                row["transcriptionStatus"] as String? ?? "success",
                                row["transcriptionError"] as String?,
                                row["promotionStatus"] as String? ?? "none",
                                row["talkieMemoID"] as String?,
                                row["commandID"] as String?,
                                row["createdInTalkieView"] as Int? ?? 0,
                                row["pasteTimestamp"] as Double?,
                                row["sessionID"] as String?,
                                row["metadata"] as String?
                            ]
                        )
                        migratedCount += 1
                    }
                }
                logger.info("[LiveDatabase] Migrated \(migratedCount) records from old SQLite")

                // Rename old database to mark as migrated
                let backupPath = oldDbPath.deletingPathExtension().appendingPathExtension("migrated.sqlite")
                try? fm.moveItem(at: oldDbPath, to: backupPath)

            } catch {
                logger.error("[LiveDatabase] Failed to migrate from old SQLite: \(error)")
            }
        }

        // 2. Migrate from JSON files (check all locations)
        for jsonPath in jsonPaths where fm.fileExists(atPath: jsonPath.path) {
            logger.info("[LiveDatabase] Found old JSON at: \(jsonPath.path)")
            do {
                let data = try Data(contentsOf: jsonPath)
                let utterances = try JSONDecoder().decode([LegacyJSONUtterance].self, from: data)

                try dbQueue.write { db in
                    for legacy in utterances {
                        guard !legacy.text.isEmpty else { continue }

                        // Convert timeIntervalSinceReferenceDate to Unix timestamp
                        let unixTimestamp = legacy.timestamp + 978307200 // Jan 1, 2001 → Jan 1, 1970

                        // Check for duplicate by timestamp (within 1 second)
                        let exists = try Int.fetchOne(db, sql: """
                            SELECT COUNT(*) FROM dictations WHERE ABS(createdAt - ?) < 1
                            """, arguments: [unixTimestamp]) ?? 0

                        if exists > 0 { continue }

                        try db.execute(
                            sql: """
                                INSERT INTO dictations (
                                    createdAt, text, mode, appBundleID, appName, windowTitle,
                                    durationSeconds, transcriptionModel, audioFilename,
                                    transcriptionStatus, promotionStatus, createdInTalkieView
                                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'success', 'none', 0)
                                """,
                            arguments: [
                                unixTimestamp,
                                legacy.text,
                                legacy.metadata.routingMode ?? "typing",
                                legacy.metadata.activeAppBundleID,
                                legacy.metadata.activeAppName,
                                legacy.metadata.activeWindowTitle,
                                legacy.durationSeconds,
                                legacy.metadata.whisperModel,
                                legacy.metadata.audioFilename
                            ]
                        )
                        migratedCount += 1
                    }
                }
                logger.info("[LiveDatabase] Migrated records from JSON (total now: \(migratedCount))")

                // Rename JSON to mark as migrated
                let backupPath = jsonPath.deletingPathExtension().appendingPathExtension("migrated.json")
                try? fm.moveItem(at: jsonPath, to: backupPath)

            } catch {
                logger.error("[LiveDatabase] Failed to migrate from JSON: \(error)")
            }
        }

        if migratedCount > 0 {
            logger.info("[LiveDatabase] Migration complete: \(migratedCount) total records")
        }
    }
}

// MARK: - Legacy JSON Model (for migration only)

private struct LegacyJSONUtterance: Codable {
    let id: UUID
    var text: String
    let timestamp: Double  // timeIntervalSinceReferenceDate
    let durationSeconds: Double?
    var metadata: LegacyJSONMetadata
}

private struct LegacyJSONMetadata: Codable {
    var activeAppBundleID: String?
    var activeAppName: String?
    var activeWindowTitle: String?
    var routingMode: String?
    var whisperModel: String?
    var audioFilename: String?
}
