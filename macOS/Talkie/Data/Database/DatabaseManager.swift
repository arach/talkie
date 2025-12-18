//
//  DatabaseManager.swift
//  Talkie
//
//  GRDB database setup and management
//  Local SQLite database with proper indexing for performance
//

import Foundation
import GRDB

// MARK: - Database Manager

@MainActor
final class DatabaseManager {
    static let shared = DatabaseManager()

    private var dbQueue: DatabaseQueue?

    /// Database file location
    private static var databaseURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let talkieDir = appSupport.appendingPathComponent("Talkie", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: talkieDir, withIntermediateDirectories: true)

        return talkieDir.appendingPathComponent("talkie.sqlite")
    }

    private init() {}

    /// Initialize database (call on app launch)
    func initialize() throws {
        let dbQueue = try DatabaseQueue(path: Self.databaseURL.path)

        // Configure database
        var config = Configuration()
        config.prepareDatabase { db in
            // Enable foreign keys
            try db.execute(sql: "PRAGMA foreign_keys = ON")

            // Performance optimizations
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            try db.execute(sql: "PRAGMA temp_store = MEMORY")
            try db.execute(sql: "PRAGMA cache_size = -64000")  // 64MB cache
        }

        // Run migrations
        try migrator.migrate(dbQueue)

        self.dbQueue = dbQueue
    }

    /// Get database queue (must call initialize() first)
    func database() throws -> DatabaseQueue {
        guard let db = dbQueue else {
            throw DatabaseError.notInitialized
        }
        return db
    }

    // MARK: - Migrations

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // Migration v1: Initial schema
        migrator.registerMigration("v1_initial_schema") { db in
            // Create voice_memos table
            try db.create(table: "voice_memos") { t in
                t.column("id", .text).primaryKey()
                t.column("createdAt", .datetime).notNull()
                t.column("lastModified", .datetime).notNull()
                t.column("title", .text)
                t.column("duration", .double).notNull().defaults(to: 0)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("transcription", .text)
                t.column("notes", .text)
                t.column("summary", .text)
                t.column("tasks", .text)
                t.column("reminders", .text)
                t.column("audioFilePath", .text)
                t.column("waveformData", .blob)
                t.column("isTranscribing", .boolean).notNull().defaults(to: false)
                t.column("isProcessingSummary", .boolean).notNull().defaults(to: false)
                t.column("isProcessingTasks", .boolean).notNull().defaults(to: false)
                t.column("isProcessingReminders", .boolean).notNull().defaults(to: false)
                t.column("autoProcessed", .boolean).notNull().defaults(to: false)
                t.column("originDeviceId", .text)
                t.column("macReceivedAt", .datetime)
                t.column("cloudSyncedAt", .datetime)
                t.column("pendingWorkflowIds", .text)
            }

            // Create transcript_versions table
            try db.create(table: "transcript_versions") { t in
                t.column("id", .text).primaryKey()
                t.column("memoId", .text).notNull()
                    .references("voice_memos", onDelete: .cascade)
                t.column("version", .integer).notNull()
                t.column("content", .text).notNull()
                t.column("sourceType", .text).notNull()
                t.column("engine", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("transcriptionDurationMs", .integer).notNull().defaults(to: 0)
            }

            // Create workflow_runs table
            try db.create(table: "workflow_runs") { t in
                t.column("id", .text).primaryKey()
                t.column("memoId", .text).notNull()
                    .references("voice_memos", onDelete: .cascade)
                t.column("workflowId", .text).notNull()
                t.column("workflowName", .text).notNull()
                t.column("workflowIcon", .text)
                t.column("output", .text)
                t.column("status", .text).notNull().defaults(to: "completed")
                t.column("runDate", .datetime).notNull()
                t.column("modelId", .text)
                t.column("providerName", .text)
                t.column("stepOutputsJSON", .text)
            }

            // CRITICAL: Create indexes for performance
            // These make sorting/filtering 10-100x faster

            // Most common query: Sort by createdAt DESC (newest first)
            try db.create(index: "idx_memos_created_at",
                         on: "voice_memos",
                         columns: ["createdAt"])

            // Sort by title
            try db.create(index: "idx_memos_title",
                         on: "voice_memos",
                         columns: ["title"])

            // Sort by duration
            try db.create(index: "idx_memos_duration",
                         on: "voice_memos",
                         columns: ["duration"])

            // Foreign key lookups
            try db.create(index: "idx_transcript_versions_memo_id",
                         on: "transcript_versions",
                         columns: ["memoId"])

            try db.create(index: "idx_workflow_runs_memo_id",
                         on: "workflow_runs",
                         columns: ["memoId"])

            // Workflow runs sorted by date
            try db.create(index: "idx_workflow_runs_date",
                         on: "workflow_runs",
                         columns: ["runDate"])

            // Full-text search on transcription
            try db.create(virtualTable: "memos_fts", using: FTS5()) { t in
                t.column("title")
                t.column("transcription")
                t.column("notes")
            }
        }

        return migrator
    }
}

// MARK: - Errors

enum DatabaseError: Error {
    case notInitialized
    case migrationFailed(Error)
    case queryFailed(Error)
}
