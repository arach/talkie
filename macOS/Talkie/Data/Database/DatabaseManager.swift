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

final class DatabaseManager {
    static let shared = DatabaseManager()

    private var dbQueue: DatabaseQueue?
    nonisolated(unsafe) private let lock = NSLock()

    /// Callbacks waiting for initialization
    private var pendingCallbacks: [@Sendable () async -> Void] = []

    /// Database file location
    private static var databaseURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let talkieDir = appSupport.appendingPathComponent("Talkie", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: talkieDir, withIntermediateDirectories: true)

        // Use distinct filename to avoid conflict with CoreData's talkie.sqlite
        return talkieDir.appendingPathComponent("talkie_grdb.sqlite")
    }

    private init() {}

    /// Initialize database (call on app launch)
    /// Runs blocking SQLite operations on background thread to avoid blocking UI
    func initialize() async throws {
        let dbPath = Self.databaseURL.path

        // Check if file exists
        let fileExists = FileManager.default.fileExists(atPath: dbPath)

        // Log concise status - less verbose for fresh installs
        await MainActor.run {
            if fileExists {
                StartupLogger.shared.log("Loading local database...")
            } else {
                // Fresh install - don't alarm user, iCloud will sync separately
                StartupLogger.shared.log("Setting up local storage...")
            }
        }

        // Start a timeout warning task (only warn after 3 seconds)
        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                StartupLogger.shared.log("⚠️ Database lock taking long...", isError: true)
                StartupLogger.shared.log("Check for other Talkie processes", isError: true)
            }
        }

        // Run blocking SQLite operations on background thread
        // This prevents the main thread from freezing during file lock acquisition
        let dbQueue: DatabaseQueue = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // Configure database with PRAGMAs during initialization
                    // (must be done outside transactions)
                    var config = Configuration()
                    config.prepareDatabase { db in
                        try db.execute(sql: "PRAGMA foreign_keys = ON")
                        try db.execute(sql: "PRAGMA journal_mode = WAL")
                        try db.execute(sql: "PRAGMA synchronous = NORMAL")
                        try db.execute(sql: "PRAGMA temp_store = MEMORY")
                        try db.execute(sql: "PRAGMA cache_size = -64000")
                    }

                    let queue = try DatabaseQueue(path: dbPath, configuration: config)
                    continuation.resume(returning: queue)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        timeoutTask.cancel()

        // Run migrations on background thread (silently - no UI logging)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                do {
                    try self.migrator.migrate(dbQueue)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        // Single "ready" message - keep it simple
        await MainActor.run { StartupLogger.shared.log("Local storage ready ✓") }

        // Thread-safe assignment and run pending callbacks
        lock.lock()
        self.dbQueue = dbQueue
        let callbacks = pendingCallbacks
        pendingCallbacks.removeAll()
        lock.unlock()

        // Run any queued callbacks now that DB is ready
        for callback in callbacks {
            await callback()
        }
    }

    /// Check if database is initialized (thread-safe)
    var isInitialized: Bool {
        lock.lock()
        defer { lock.unlock() }
        return dbQueue != nil
    }

    /// Run a callback after database is initialized
    /// If already initialized, runs immediately. Otherwise queues for later.
    func afterInitialized(_ callback: @escaping @Sendable () async -> Void) {
        lock.lock()
        if dbQueue != nil {
            lock.unlock()
            Task { await callback() }
        } else {
            pendingCallbacks.append(callback)
            lock.unlock()
        }
    }

    /// Get database queue (must call initialize() first)
    /// Thread-safe accessor
    func database() throws -> DatabaseQueue {
        lock.lock()
        defer { lock.unlock() }

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

        // Migration v2: Add sync_history and sync_metadata tables
        migrator.registerMigration("v2_sync_history") { db in
            // Sync history - audit log for UI display
            try db.create(table: "sync_history") { t in
                t.column("id", .text).primaryKey()
                t.column("timestamp", .datetime).notNull()
                t.column("status", .text).notNull()  // "success", "failed", "partial"
                t.column("itemCount", .integer).notNull()
                t.column("duration", .double)
                t.column("errorMessage", .text)
                t.column("detailsJSON", .text)  // Serialized [SyncRecordDetail]
            }

            // Index for sorting by timestamp (most recent first)
            try db.create(index: "idx_sync_history_timestamp",
                         on: "sync_history",
                         columns: ["timestamp"])

            // Sync metadata - operational state (single row)
            try db.create(table: "sync_metadata") { t in
                t.column("id", .integer).primaryKey()  // Always 1
                t.column("lastSyncTimestamp", .datetime)
                t.column("nextScheduledSync", .datetime)
                t.column("syncInProgress", .boolean).notNull().defaults(to: false)
                t.column("changeToken", .blob)  // Serialized CKServerChangeToken
            }

            // Insert initial row
            try db.execute(
                sql: "INSERT INTO sync_metadata (id, syncInProgress) VALUES (1, 0)"
            )
        }

        // Migration v3: Vercel-compatible workflow tables
        migrator.registerMigration("v3_vercel_workflow_schema") { db in
            // 🧹 Clean slate for workflow execution data (keep memos safe!)
            print("🧹 Cleaning workflow execution data for fresh start...")

            // Drop old workflow execution tables if they exist
            if try db.tableExists("workflow_events") {
                try db.execute(sql: "DROP TABLE workflow_events")
                print("   Dropped workflow_events")
            }
            if try db.tableExists("workflow_steps") {
                try db.execute(sql: "DROP TABLE workflow_steps")
                print("   Dropped workflow_steps")
            }
            if try db.tableExists("workflow_runs") {
                try db.execute(sql: "DELETE FROM workflow_runs")
                print("   Cleared workflow_runs data")
            }

            // Check if workflow_runs table structure exists
            let tableExists = try db.tableExists("workflow_runs")

            if tableExists {
                // ALTER existing table to add new columns
                print("📦 Extending workflow_runs table with Vercel-compatible fields...")

                // Add new columns (if they don't exist)
                try? db.alter(table: "workflow_runs") { t in
                    t.add(column: "createdAt", .datetime)
                    t.add(column: "updatedAt", .datetime)
                    t.add(column: "startedAt", .datetime)
                    t.add(column: "completedAt", .datetime)
                    t.add(column: "inputTranscript", .text)
                    t.add(column: "inputTitle", .text)
                    t.add(column: "inputDate", .datetime)
                    t.add(column: "finalOutputs", .text)
                    t.add(column: "errorMessage", .text)
                    t.add(column: "errorStack", .text)
                    t.add(column: "durationMs", .integer)
                    t.add(column: "stepCount", .integer)
                    t.add(column: "triggerSource", .text)
                    t.add(column: "backendId", .text)
                    t.add(column: "workflowVersion", .integer)
                }

                // No backfill needed - we deleted all old data!
            } else {
                // CREATE new table with full Vercel-compatible schema
                print("📦 Creating new workflow_runs table with Vercel-compatible schema...")
                try db.create(table: "workflow_runs") { t in
                    // Identity
                    t.column("id", .text).primaryKey()
                    t.column("workflowId", .text).notNull()
                    t.column("workflowName", .text).notNull()
                    t.column("workflowVersion", .integer).notNull().defaults(to: 1)
                    t.column("workflowIcon", .text)

                    // Association
                    t.column("memoId", .text).notNull()

                    // Status
                    t.column("status", .text).notNull().defaults(to: "completed")

                    // Timestamps
                    t.column("createdAt", .datetime).notNull()
                    t.column("updatedAt", .datetime).notNull()
                    t.column("startedAt", .datetime)
                    t.column("completedAt", .datetime)
                    t.column("runDate", .datetime).notNull()  // Legacy compat

                    // Execution Context
                    t.column("inputTranscript", .text)
                    t.column("inputTitle", .text)
                    t.column("inputDate", .datetime)

                    // Results
                    t.column("output", .text)  // Legacy
                    t.column("finalOutputs", .text)  // Vercel: JSON outputs
                    t.column("errorMessage", .text)
                    t.column("errorStack", .text)

                    // Metadata
                    t.column("durationMs", .integer)
                    t.column("stepCount", .integer).notNull().defaults(to: 0)
                    t.column("triggerSource", .text).notNull().defaults(to: "manual")

                    // LLM Tracking (legacy)
                    t.column("modelId", .text)
                    t.column("providerName", .text)
                    t.column("stepOutputsJSON", .text)

                    // Backend
                    t.column("backendId", .text).notNull().defaults(to: "local-swift")
                }
            }

            // Indexes for workflow_runs
            try db.create(index: "idx_workflow_runs_memo_id",
                         on: "workflow_runs",
                         columns: ["memoId"],
                         ifNotExists: true)
            try db.create(index: "idx_workflow_runs_status",
                         on: "workflow_runs",
                         columns: ["status"],
                         ifNotExists: true)
            try db.create(index: "idx_workflow_runs_created_at",
                         on: "workflow_runs",
                         columns: ["createdAt"],
                         ifNotExists: true)

            // CREATE workflow_steps table (new!)
            print("📦 Creating workflow_steps table...")
            try db.create(table: "workflow_steps") { t in
                // Identity
                t.column("id", .text).primaryKey()
                t.column("runId", .text).notNull()
                t.column("stepNumber", .integer).notNull()

                // Step Definition
                t.column("stepType", .text).notNull()
                t.column("stepConfig", .text).notNull().defaults(to: "{}")
                t.column("outputKey", .text).notNull()

                // Status
                t.column("status", .text).notNull().defaults(to: "pending")

                // Timestamps
                t.column("createdAt", .datetime).notNull()
                t.column("startedAt", .datetime)
                t.column("completedAt", .datetime)

                // Input/Output
                t.column("inputSnapshot", .text)
                t.column("outputValue", .text)

                // Metadata
                t.column("durationMs", .integer)
                t.column("retryCount", .integer).notNull().defaults(to: 0)

                // LLM-specific
                t.column("providerName", .text)
                t.column("modelId", .text)
                t.column("tokensUsed", .integer)
                t.column("costUsd", .real)

                // Error Handling
                t.column("errorMessage", .text)
                t.column("errorStack", .text)

                // Backend
                t.column("backendId", .text).notNull().defaults(to: "local-swift")

                // Foreign key
                t.foreignKey(["runId"], references: "workflow_runs", columns: ["id"], onDelete: .cascade)
            }

            // Indexes for workflow_steps
            try db.create(index: "idx_workflow_steps_run_id",
                         on: "workflow_steps",
                         columns: ["runId"])
            try db.create(index: "idx_workflow_steps_run_step",
                         on: "workflow_steps",
                         columns: ["runId", "stepNumber"])

            // CREATE workflow_events table (event sourcing!)
            print("📦 Creating workflow_events table...")
            try db.create(table: "workflow_events") { t in
                // Identity
                t.column("id", .text).primaryKey()
                t.column("runId", .text).notNull()
                t.column("sequence", .integer).notNull()

                // Event Type
                t.column("eventType", .text).notNull()

                // Timestamp
                t.column("createdAt", .datetime).notNull()

                // Payload
                t.column("payload", .text).notNull().defaults(to: "{}")

                // Optional Step Reference
                t.column("stepId", .text)

                // Foreign keys
                t.foreignKey(["runId"], references: "workflow_runs", columns: ["id"], onDelete: .cascade)
            }

            // Indexes for workflow_events
            try db.create(index: "idx_workflow_events_run_id",
                         on: "workflow_events",
                         columns: ["runId"])
            try db.create(index: "idx_workflow_events_run_seq",
                         on: "workflow_events",
                         columns: ["runId", "sequence"])
            try db.create(index: "idx_workflow_events_type",
                         on: "workflow_events",
                         columns: ["eventType"])
            try db.create(index: "idx_workflow_events_created_at",
                         on: "workflow_events",
                         columns: ["createdAt"])

            print("✅ Vercel-compatible workflow schema migrated successfully!")
        }

        // Migration v4: Add soft delete support
        migrator.registerMigration("v4_soft_delete") { db in
            print("📦 Adding soft delete support...")

            // Add deletedAt column for soft delete
            try db.alter(table: "voice_memos") { t in
                t.add(column: "deletedAt", .datetime)
            }

            // Index for efficiently filtering out deleted memos
            try db.create(index: "idx_memos_deleted_at",
                         on: "voice_memos",
                         columns: ["deletedAt"])

            print("✅ Soft delete migration complete!")
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
