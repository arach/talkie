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
    /// App Group identifier shared with main Talkie app
    static let appGroupID = "group.com.jdi.talkie"

    /// Database filename
    static let dbFilename = "live.sqlite"

    /// Folder name within container
    static let folderName = "TalkieLive"

    /// The resolved database URL (App Group preferred, fallback to local)
    static let databaseURL: URL = {
        let fm = FileManager.default

        // Prefer App Group container for sharing with Talkie
        if let groupContainer = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            let folderURL = groupContainer.appendingPathComponent(folderName, isDirectory: true)
            try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let dbURL = folderURL.appendingPathComponent(dbFilename)
            logger.info("[LiveDatabase] Using App Group path: \(dbURL.path)")
            return dbURL
        }

        // Fallback to local Application Support (dev mode / no entitlement)
        logger.warning("[LiveDatabase] App Group not available, using local storage")
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let folderURL = appSupport.appendingPathComponent(folderName, isDirectory: true)
            try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
            return folderURL.appendingPathComponent(dbFilename)
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
                    t.column("whisperModel", .text)
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
    static func store(_ utterance: LiveUtterance) -> Int64? {
        do {
            return try shared.write { db -> Int64? in
                var mutable = utterance
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
                    sql: "UPDATE utterances SET metadata = ? WHERE id = ?",
                    arguments: [metadataJSON, id]
                )
            }
            logger.debug("[LiveDatabase] Updated metadata for utterance \(id)")
        } catch {
            logger.error("[LiveDatabase] updateMetadata error: \(error)")
        }
    }

    static func fetch(id: Int64) -> LiveUtterance? {
        try? shared.read { db in
            try LiveUtterance.fetchOne(db, id: id)
        }
    }

    static func all() -> [LiveUtterance] {
        (try? shared.read { db in
            try LiveUtterance
                .order(LiveUtterance.Columns.createdAt.desc)
                .fetchAll(db)
        }) ?? []
    }

    static func recent(limit: Int = 100) -> [LiveUtterance] {
        (try? shared.read { db in
            try LiveUtterance
                .order(LiveUtterance.Columns.createdAt.desc)
                .limit(limit)
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
        AudioStorage.deleteAll()
        try? shared.write { db in
            _ = try LiveUtterance.deleteAll(db)
        }
    }

    static func count() -> Int {
        (try? shared.read { db in
            try LiveUtterance.fetchCount(db)
        }) ?? 0
    }

    static func prune(olderThanHours hours: Int) {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 60 * 60)
        let cutoffTS = cutoff.timeIntervalSince1970

        // Get audio filenames for utterances that will be deleted
        let audioFilenames: [String] = (try? shared.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT audioFilename FROM utterances WHERE createdAt < ? AND audioFilename IS NOT NULL",
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
                sql: "DELETE FROM utterances WHERE createdAt < ?",
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
                sql: "UPDATE utterances SET promotionStatus = ?, talkieMemoID = ? WHERE id = ?",
                arguments: [PromotionStatus.memo.rawValue, talkieMemoID, id]
            )
        }
    }

    static func markAsCommand(id: Int64?, commandID: String) {
        guard let id else { return }
        try? shared.write { db in
            try db.execute(
                sql: "UPDATE utterances SET promotionStatus = ?, commandID = ? WHERE id = ?",
                arguments: [PromotionStatus.command.rawValue, commandID, id]
            )
        }
    }

    static func markAsIgnored(id: Int64?) {
        guard let id else { return }
        try? shared.write { db in
            try db.execute(
                sql: "UPDATE utterances SET promotionStatus = ? WHERE id = ?",
                arguments: [PromotionStatus.ignored.rawValue, id]
            )
        }
    }

    static func resetPromotion(id: Int64?) {
        guard let id else { return }
        try? shared.write { db in
            try db.execute(
                sql: "UPDATE utterances SET promotionStatus = ?, talkieMemoID = NULL, commandID = NULL WHERE id = ?",
                arguments: [PromotionStatus.none.rawValue, id]
            )
        }
    }
}

// MARK: - Filtered Queries

extension LiveDatabase {
    static func needsAction(limit: Int = 100) -> [LiveUtterance] {
        (try? shared.read { db in
            try LiveUtterance
                .filter(LiveUtterance.Columns.promotionStatus == PromotionStatus.none.rawValue)
                .order(LiveUtterance.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []
    }

    static func byStatus(_ status: PromotionStatus, limit: Int = 100) -> [LiveUtterance] {
        (try? shared.read { db in
            try LiveUtterance
                .filter(LiveUtterance.Columns.promotionStatus == status.rawValue)
                .order(LiveUtterance.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []
    }

    static func countNeedsAction() -> Int {
        (try? shared.read { db in
            try LiveUtterance
                .filter(LiveUtterance.Columns.promotionStatus == PromotionStatus.none.rawValue)
                .fetchCount(db)
        }) ?? 0
    }
}

// MARK: - Queue Methods

extension LiveDatabase {
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

    static func countQueued() -> Int {
        (try? shared.read { db in
            try LiveUtterance
                .filter(LiveUtterance.Columns.createdInTalkieView == 1)
                .filter(LiveUtterance.Columns.pasteTimestamp == nil)
                .filter(LiveUtterance.Columns.promotionStatus == PromotionStatus.none.rawValue)
                .fetchCount(db)
        }) ?? 0
    }

    static func markPasted(id: Int64?) {
        guard let id else { return }
        let now = Date().timeIntervalSince1970
        try? shared.write { db in
            try db.execute(
                sql: "UPDATE utterances SET pasteTimestamp = ? WHERE id = ?",
                arguments: [now, id]
            )
        }
    }
}

// MARK: - Transcription Retry Methods

extension LiveDatabase {
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

    static func markTranscriptionSuccess(id: Int64?, text: String, perfEngineMs: Int?, model: String?) {
        guard let id else { return }
        try? shared.write { db in
            try db.execute(
                sql: """
                    UPDATE utterances
                    SET transcriptionStatus = ?, transcriptionError = NULL,
                        text = ?, wordCount = ?, perfEngineMs = ?, whisperModel = ?
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
                sql: "UPDATE utterances SET transcriptionStatus = ?, transcriptionError = ? WHERE id = ?",
                arguments: [TranscriptionStatus.failed.rawValue, error, id]
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

        // 1. Check App Group container (where old PastLives.sqlite likely lives)
        if let groupContainer = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            let groupFolder = groupContainer.appendingPathComponent(folderName, isDirectory: true)
            oldDbPaths.append(groupFolder.appendingPathComponent("PastLives.sqlite"))
            jsonPaths.append(groupFolder.appendingPathComponent("utterances.json"))
            logger.info("[LiveDatabase] Checking App Group for old data: \(groupFolder.path)")
        }

        // 2. Check ~/Library/Application Support/TalkieLive/
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appSupportFolder = appSupport.appendingPathComponent("TalkieLive")
            oldDbPaths.append(appSupportFolder.appendingPathComponent("PastLives.sqlite"))
            jsonPaths.append(appSupportFolder.appendingPathComponent("utterances.json"))
            logger.info("[LiveDatabase] Checking App Support for old data: \(appSupportFolder.path)")
        }

        // Log existing count but continue to check for additional old data
        let existingCount = (try? dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM utterances")
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
                            SELECT COUNT(*) FROM utterances WHERE ABS(createdAt - ?) < 1
                            """, arguments: [createdAt]) ?? 0

                        if exists > 0 { continue }

                        try db.execute(
                            sql: """
                                INSERT INTO utterances (
                                    createdAt, text, mode, appBundleID, appName, windowTitle,
                                    durationSeconds, wordCount, whisperModel, audioFilename,
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
                            SELECT COUNT(*) FROM utterances WHERE ABS(createdAt - ?) < 1
                            """, arguments: [unixTimestamp]) ?? 0

                        if exists > 0 { continue }

                        try db.execute(
                            sql: """
                                INSERT INTO utterances (
                                    createdAt, text, mode, appBundleID, appName, windowTitle,
                                    durationSeconds, whisperModel, audioFilename,
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
