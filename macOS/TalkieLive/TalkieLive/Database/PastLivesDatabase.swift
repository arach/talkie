//
//  PastLivesDatabase.swift
//  TalkieLive
//
//  SQLite database for storing utterances using GRDB.
//  Uses App Group container for sharing with main Talkie app.
//

import Foundation
import GRDB
import os

private let logger = Logger(subsystem: "jdi.talkie.live", category: "PastLivesDatabase")

enum PastLivesDatabase {
    /// App Group identifier shared with main Talkie app
    static let appGroupID = "group.com.jdi.talkie"

    /// Database filename
    static let dbFilename = "PastLives.sqlite"

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
            logger.info("[PastLivesDatabase] Using App Group path: \(dbURL.path)")
            return dbURL
        }

        // Fallback to local Application Support (dev mode / no entitlement)
        logger.warning("[PastLivesDatabase] App Group not available, using local storage")
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

            // Check for legacy data to migrate
            migrateFromLegacyLocations()

            let dbQueue = try DatabaseQueue(path: databaseURL.path)
            logger.info("[PastLivesDatabase] Opened database at: \(databaseURL.path)")

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

    // MARK: - Legacy Migration

    /// Migrate data from legacy locations (old app support, JSON file)
    private static func migrateFromLegacyLocations() {
        let fm = FileManager.default

        // Skip if database already has data (don't re-migrate)
        if fm.fileExists(atPath: databaseURL.path) {
            return
        }

        // Legacy locations to check
        var legacyPaths: [URL] = []

        // Old Application Support location
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            legacyPaths.append(appSupport.appendingPathComponent("TalkieLive/PastLives.sqlite"))
        }

        // Sandboxed container location
        if let homeDir = fm.urls(for: .libraryDirectory, in: .userDomainMask).first?.deletingLastPathComponent() {
            legacyPaths.append(homeDir.appendingPathComponent("Library/Containers/jdi.talkie.live/Data/Library/Application Support/TalkieLive/PastLives.sqlite"))
        }

        // Try to copy from legacy location
        for legacyPath in legacyPaths {
            if fm.fileExists(atPath: legacyPath.path) && legacyPath != databaseURL {
                do {
                    try fm.copyItem(at: legacyPath, to: databaseURL)
                    logger.info("[PastLivesDatabase] Migrated database from: \(legacyPath.path)")

                    // Also copy WAL and SHM files if they exist
                    let walPath = legacyPath.appendingPathExtension("wal")
                    let shmPath = legacyPath.appendingPathExtension("shm")
                    if fm.fileExists(atPath: walPath.path) {
                        try? fm.copyItem(at: walPath, to: databaseURL.appendingPathExtension("wal"))
                    }
                    if fm.fileExists(atPath: shmPath.path) {
                        try? fm.copyItem(at: shmPath, to: databaseURL.appendingPathExtension("shm"))
                    }
                    return
                } catch {
                    logger.error("[PastLivesDatabase] Failed to migrate from \(legacyPath.path): \(error.localizedDescription)")
                }
            }
        }

        // Try to migrate from JSON (utterances.json)
        migrateFromJSON()
    }

    /// Migrate data from legacy JSON storage
    private static func migrateFromJSON() {
        let fm = FileManager.default

        var jsonPaths: [URL] = []

        // Check Application Support
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            jsonPaths.append(appSupport.appendingPathComponent("TalkieLive/utterances.json"))
        }

        for jsonPath in jsonPaths {
            guard fm.fileExists(atPath: jsonPath.path) else { continue }

            do {
                let data = try Data(contentsOf: jsonPath)
                let utterances = try JSONDecoder().decode([LegacyUtterance].self, from: data)

                guard !utterances.isEmpty else { continue }

                logger.info("[PastLivesDatabase] Migrating \(utterances.count) utterances from JSON")

                // We need to open the database first to insert
                // This will be called before shared is initialized, so we create a temporary connection
                let dbQueue = try DatabaseQueue(path: databaseURL.path)

                // Run migrations first
                var migrator = DatabaseMigrator()
                migrator.registerMigration("createLiveUtterance") { db in
                    try db.create(table: "live_utterance", ifNotExists: true) { t in
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
                        t.column("audioFilename", .text)
                        t.column("promotionStatus", .text).defaults(to: "none")
                        t.column("talkieMemoID", .text)
                        t.column("commandID", .text)
                        t.column("createdInTalkieView", .integer).notNull().defaults(to: 0)
                        t.column("pasteTimestamp", .double)
                        t.column("transcriptionStatus", .text).defaults(to: "success")
                        t.column("transcriptionError", .text)
                    }
                }
                try migrator.migrate(dbQueue)

                // Insert utterances
                try dbQueue.write { db in
                    for legacy in utterances {
                        let utterance = LiveUtterance(
                            createdAt: Date(timeIntervalSinceReferenceDate: legacy.timestamp),
                            text: legacy.text,
                            mode: legacy.metadata.routingMode ?? "typing",
                            appBundleID: legacy.metadata.activeAppBundleID,
                            appName: legacy.metadata.activeAppName,
                            windowTitle: legacy.metadata.activeWindowTitle,
                            durationSeconds: legacy.durationSeconds,
                            whisperModel: legacy.metadata.whisperModel,
                            transcriptionMs: legacy.metadata.transcriptionDurationMs,
                            audioFilename: legacy.metadata.audioFilename
                        )
                        _ = try utterance.inserted(db)
                    }
                }

                logger.info("[PastLivesDatabase] Successfully migrated \(utterances.count) utterances from JSON")

                // Rename JSON file to mark as migrated
                let backupPath = jsonPath.deletingPathExtension().appendingPathExtension("migrated.json")
                try? fm.moveItem(at: jsonPath, to: backupPath)

                return
            } catch {
                logger.error("[PastLivesDatabase] Failed to migrate from JSON: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Legacy JSON Models

/// Legacy utterance from JSON storage
private struct LegacyUtterance: Codable {
    let id: UUID
    var text: String
    let timestamp: TimeInterval
    let durationSeconds: Double?
    var metadata: LegacyMetadata
}

private struct LegacyMetadata: Codable {
    var activeAppBundleID: String?
    var activeAppName: String?
    var activeWindowTitle: String?
    var endAppBundleID: String?
    var endAppName: String?
    var endWindowTitle: String?
    var routingMode: String?
    var wasRouted: Bool?
    var whisperModel: String?
    var transcriptionDurationMs: Int?
    var language: String?
    var confidence: Double?
    var peakAmplitude: Float?
    var averageAmplitude: Float?
    var audioFilename: String?
    var wasEdited: Bool?
    var originalText: String?
}
