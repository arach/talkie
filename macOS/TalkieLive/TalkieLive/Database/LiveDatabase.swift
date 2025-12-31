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

                log.info("[LiveDatabase] Created performance indexes")
            }

            // v4: Rename table utterances → dictations (terminology clarification)
            migrator.registerMigration("v4_rename_to_dictations") { db in
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

            // v5: Denormalized daily stats for O(1) HomeView queries
            migrator.registerMigration("v5_daily_stats") { db in
                // Daily aggregates - one row per day
                try db.create(table: "daily_stats") { t in
                    t.column("date", .text).primaryKey()  // "2024-12-31" format
                    t.column("dictationCount", .integer).notNull().defaults(to: 0)
                    t.column("wordCount", .integer).notNull().defaults(to: 0)
                    t.column("durationSeconds", .double).notNull().defaults(to: 0)
                }

                // Per-app daily stats for top apps calculation
                try db.create(table: "daily_app_stats") { t in
                    t.column("date", .text).notNull()
                    t.column("appBundleID", .text).notNull()
                    t.column("appName", .text)
                    t.column("count", .integer).notNull().defaults(to: 0)
                    t.primaryKey(["date", "appBundleID"])
                }

                // Backfill from existing dictations (use localtime to match runtime DateFormatter)
                try db.execute(sql: """
                    INSERT INTO daily_stats (date, dictationCount, wordCount, durationSeconds)
                    SELECT
                        date(createdAt, 'unixepoch', 'localtime') as date,
                        COUNT(*) as dictationCount,
                        COALESCE(SUM(wordCount), 0) as wordCount,
                        COALESCE(SUM(durationSeconds), 0) as durationSeconds
                    FROM dictations
                    GROUP BY date(createdAt, 'unixepoch', 'localtime')
                """)

                try db.execute(sql: """
                    INSERT INTO daily_app_stats (date, appBundleID, appName, count)
                    SELECT
                        date(createdAt, 'unixepoch', 'localtime') as date,
                        appBundleID,
                        appName,
                        COUNT(*) as count
                    FROM dictations
                    WHERE appBundleID IS NOT NULL
                    GROUP BY date(createdAt, 'unixepoch', 'localtime'), appBundleID
                """)

                log.info("[LiveDatabase] Created daily_stats tables with backfill")
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
    /// Store utterance and return its ID (for fire-and-forget enrichment)
    @discardableResult
    static func store(_ utterance: LiveDictation) -> Int64? {
        do {
            let insertedId = try shared.write { db -> Int64? in
                let mutable = utterance
                try mutable.insert(db)
                // Use lastInsertedRowID as fallback if didInsert didn't populate id
                let insertedId = mutable.id ?? db.lastInsertedRowID
                log.debug( "Stored dictation", detail: "ID: \(insertedId)")
                return insertedId
            }

            // Async update denormalized stats (fire-and-forget)
            Task.detached(priority: .utility) {
                updateDailyStats(for: utterance, increment: true)
            }

            return insertedId
        } catch {
            log.error( "Store failed", error: error)
            return nil
        }
    }

    /// Update metadata fields for an existing utterance (used by fire-and-forget enrichment)
    static func updateMetadata(id: Int64, metadata: DictationMetadata) {
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
            log.debug("[LiveDatabase] Updated metadata for utterance \(id)")
        } catch {
            log.error("[LiveDatabase] updateMetadata error: \(error)")
        }
    }

    static func fetch(id: Int64) -> LiveDictation? {
        try? shared.read { db in
            try LiveDictation.fetchOne(db, id: id)
        }
    }

    static func all() -> [LiveDictation] {
        do {
            let results = try shared.read { db in
                try LiveDictation
                    .order(LiveDictation.Columns.createdAt.desc)
                    .fetchAll(db)
            }
            log.info("[LiveDatabase] all() - fetched \(results.count) dictations from database")
            if !results.isEmpty {
                log.info("   First 3:")
                for (i, d) in results.prefix(3).enumerated() {
                    log.info("   [\(i)] \(d.text.prefix(50))... at \(d.createdAt)")
                }
            }
            return results
        } catch {
            log.error("[LiveDatabase] all() error: \(error)")
            return []
        }
    }

    static func recent(limit: Int = 100) -> [LiveDictation] {
        (try? shared.read { db in
            try LiveDictation
                .order(LiveDictation.Columns.createdAt.desc)
                .limit(limit)
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

        // Async update denormalized stats (fire-and-forget)
        Task.detached(priority: .utility) {
            updateDailyStats(for: utterance, increment: false)
        }
    }

    static func deleteAll() {
        AudioStorage.deleteAll()
        try? shared.write { db in
            _ = try LiveDictation.deleteAll(db)
            // Clear denormalized stats too
            try db.execute(sql: "DELETE FROM daily_stats")
            try db.execute(sql: "DELETE FROM daily_app_stats")
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

// MARK: - Denormalized Stats

extension LiveDatabase {
    /// Date formatter for daily stats keys (yyyy-MM-dd)
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    /// Update daily stats after insert/delete (called async)
    static func updateDailyStats(for dictation: LiveDictation, increment: Bool) {
        let date = dateFormatter.string(from: dictation.createdAt)
        let delta = increment ? 1 : -1
        let wordDelta = (dictation.wordCount ?? 0) * delta
        let durationDelta = (dictation.durationSeconds ?? 0) * Double(delta)

        do {
            try shared.write { db in
                // Update daily_stats with UPSERT
                try db.execute(
                    sql: """
                        INSERT INTO daily_stats (date, dictationCount, wordCount, durationSeconds)
                        VALUES (?, ?, ?, ?)
                        ON CONFLICT(date) DO UPDATE SET
                            dictationCount = MAX(0, dictationCount + ?),
                            wordCount = MAX(0, wordCount + ?),
                            durationSeconds = MAX(0, durationSeconds + ?)
                        """,
                    arguments: [
                        date,
                        max(0, delta), max(0, wordDelta), max(0, durationDelta),  // INSERT values
                        delta, wordDelta, durationDelta  // UPDATE deltas
                    ]
                )

                // Update daily_app_stats if we have app info
                if let bundleID = dictation.appBundleID {
                    try db.execute(
                        sql: """
                            INSERT INTO daily_app_stats (date, appBundleID, appName, count)
                            VALUES (?, ?, ?, ?)
                            ON CONFLICT(date, appBundleID) DO UPDATE SET
                                count = MAX(0, count + ?),
                                appName = COALESCE(?, appName)
                            """,
                        arguments: [
                            date, bundleID, dictation.appName, max(0, delta),  // INSERT
                            delta, dictation.appName  // UPDATE
                        ]
                    )
                }
            }
        } catch {
            log.error("[LiveDatabase] updateDailyStats error: \(error)")
        }
    }

    /// Aggregated stats from denormalized tables (O(days) instead of O(dictations))
    struct AggregatedStats {
        var totalDictations: Int = 0
        var totalWords: Int = 0
        var totalDurationSeconds: Double = 0
        var todayCount: Int = 0
        var weekCount: Int = 0
        var daysWithActivity: Int = 0
        var streak: Int = 0
        var topApps: [(name: String, bundleID: String, count: Int)] = []
        var dailyActivity: [(date: String, count: Int)] = []
    }

    /// Fetch aggregated stats using SQL (fast O(days) queries)
    static func fetchAggregatedStats() -> AggregatedStats {
        var stats = AggregatedStats()

        do {
            try shared.read { db in
                let today = dateFormatter.string(from: Date())
                let weekAgo = dateFormatter.string(from: Date().addingTimeInterval(-7 * 24 * 60 * 60))
                let yearAgo = dateFormatter.string(from: Date().addingTimeInterval(-365 * 24 * 60 * 60))

                // Total stats (all time)
                if let row = try Row.fetchOne(db, sql: """
                    SELECT
                        COALESCE(SUM(dictationCount), 0) as total,
                        COALESCE(SUM(wordCount), 0) as words,
                        COALESCE(SUM(durationSeconds), 0) as duration,
                        COUNT(*) as daysActive
                    FROM daily_stats
                    WHERE dictationCount > 0
                    """) {
                    stats.totalDictations = row["total"]
                    stats.totalWords = row["words"]
                    stats.totalDurationSeconds = row["duration"]
                    stats.daysWithActivity = row["daysActive"]
                }

                // Today's count
                if let row = try Row.fetchOne(db, sql: """
                    SELECT COALESCE(dictationCount, 0) as count FROM daily_stats WHERE date = ?
                    """, arguments: [today]) {
                    stats.todayCount = row["count"]
                }

                // Week count
                if let row = try Row.fetchOne(db, sql: """
                    SELECT COALESCE(SUM(dictationCount), 0) as count FROM daily_stats WHERE date >= ?
                    """, arguments: [weekAgo]) {
                    stats.weekCount = row["count"]
                }

                // Streak calculation (walk backwards from today)
                let activeDates = try String.fetchAll(db, sql: """
                    SELECT date FROM daily_stats
                    WHERE dictationCount > 0 AND date <= ?
                    ORDER BY date DESC
                    """, arguments: [today])

                stats.streak = calculateStreakFromDates(activeDates, today: today)

                // Top apps (all time)
                let appRows = try Row.fetchAll(db, sql: """
                    SELECT appName, appBundleID, SUM(count) as total
                    FROM daily_app_stats
                    GROUP BY appBundleID
                    ORDER BY total DESC
                    LIMIT 10
                    """)
                stats.topApps = appRows.map { row in
                    (name: row["appName"] ?? row["appBundleID"] ?? "Unknown",
                     bundleID: row["appBundleID"] ?? "",
                     count: row["total"])
                }

                // Daily activity for grid (last year)
                let activityRows = try Row.fetchAll(db, sql: """
                    SELECT date, dictationCount FROM daily_stats
                    WHERE date >= ?
                    ORDER BY date
                    """, arguments: [yearAgo])
                stats.dailyActivity = activityRows.map { row in
                    (date: row["date"] ?? "", count: row["dictationCount"] ?? 0)
                }
            }
        } catch {
            log.error("[LiveDatabase] fetchAggregatedStats error: \(error)")
        }

        return stats
    }

    /// Calculate streak from sorted date strings (descending)
    private static func calculateStreakFromDates(_ dates: [String], today: String) -> Int {
        guard !dates.isEmpty else { return 0 }

        var streak = 0
        var expectedDate = today

        for date in dates {
            if date == expectedDate {
                streak += 1
                // Calculate previous day
                if let d = dateFormatter.date(from: date) {
                    expectedDate = dateFormatter.string(from: d.addingTimeInterval(-24 * 60 * 60))
                }
            } else if date < expectedDate {
                // Gap found - streak broken
                break
            }
        }

        return streak
    }

    /// Rebuild all stats from source data (for periodic consistency check)
    static func rebuildDailyStats() {
        do {
            try shared.write { db in
                // Clear existing stats
                try db.execute(sql: "DELETE FROM daily_stats")
                try db.execute(sql: "DELETE FROM daily_app_stats")

                // Rebuild from dictations (use localtime to match runtime DateFormatter)
                try db.execute(sql: """
                    INSERT INTO daily_stats (date, dictationCount, wordCount, durationSeconds)
                    SELECT
                        date(createdAt, 'unixepoch', 'localtime') as date,
                        COUNT(*) as dictationCount,
                        COALESCE(SUM(wordCount), 0) as wordCount,
                        COALESCE(SUM(durationSeconds), 0) as durationSeconds
                    FROM dictations
                    GROUP BY date(createdAt, 'unixepoch', 'localtime')
                """)

                try db.execute(sql: """
                    INSERT INTO daily_app_stats (date, appBundleID, appName, count)
                    SELECT
                        date(createdAt, 'unixepoch', 'localtime') as date,
                        appBundleID,
                        appName,
                        COUNT(*) as count
                    FROM dictations
                    WHERE appBundleID IS NOT NULL
                    GROUP BY date(createdAt, 'unixepoch', 'localtime'), appBundleID
                """)

                log.info("[LiveDatabase] Rebuilt daily stats tables")
            }
        } catch {
            log.error("[LiveDatabase] rebuildDailyStats error: \(error)")
        }
    }
}
