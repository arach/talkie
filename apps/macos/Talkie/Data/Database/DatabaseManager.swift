//
//  DatabaseManager.swift
//  Talkie
//
//  GRDB database setup and management
//  Local SQLite database with proper indexing for performance
//

import Foundation
import GRDB
import TalkieKit

private let log = Log(.database)

// MARK: - Database Manager

final class DatabaseManager: @unchecked Sendable {
    static let shared = DatabaseManager()

    private var dbQueue: DatabaseQueue?
    private let lock = NSLock()

    /// Callbacks waiting for initialization
    private var pendingCallbacks: [@Sendable () async -> Void] = []

    /// Database file location
    /// Normal: ~/Library/Application Support/Talkie/talkie.sqlite
    /// Sandbox: ~/Library/Application Support/Talkie/sandbox/talkie_sandbox.sqlite
    private static var databaseURL: URL {
        #if DEBUG
        if SettingsManager.isSandboxMode {
            return sandboxDatabaseURL
        }
        #endif
        return TalkieDatabase.databaseURL
    }

    #if DEBUG
    /// Sandbox folder location (for isolated test database)
    static var sandboxFolderURL: URL {
        TalkieDatabase.folderURL.appendingPathComponent("sandbox", isDirectory: true)
    }

    /// Sandbox database location (empty database for testing onboarding flows)
    private static var sandboxDatabaseURL: URL {
        sandboxFolderURL.appendingPathComponent("talkie_sandbox.sqlite")
    }

    /// Whether currently running in sandbox mode
    static var isUsingSandbox: Bool {
        SettingsManager.isSandboxMode
    }
    #endif

    private init() {}

    /// Initialize database (call on app launch)
    /// Runs blocking SQLite operations on background thread to avoid blocking UI
    func initialize() async throws {
        #if DEBUG
        // Sandbox mode: use isolated empty database for testing onboarding
        if Self.isUsingSandbox {
            log.info("🧪 SANDBOX MODE: Using isolated test database", section: "Startup")
            // Ensure sandbox directory exists
            let sandboxDir = Self.sandboxDatabaseURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: sandboxDir, withIntermediateDirectories: true)
        } else {
            // Normal mode: run migrations
            // Step 1: Separate Core Data from GRDB if needed
            if TalkieDatabase.separateCoreDataIfNeeded() {
                log.info("Separated Core Data database to talkie_coredata.sqlite")
            }
            // Step 2: Migrate from legacy filename if needed
            if TalkieDatabase.migrateFilenameIfNeeded() {
                log.info("Migrated database from talkie_grdb.sqlite to talkie.sqlite")
            }
        }
        #else
        // Step 1: Separate Core Data from GRDB if needed
        // Moves Core Data's talkie.sqlite → talkie_coredata.sqlite
        if TalkieDatabase.separateCoreDataIfNeeded() {
            log.info("Separated Core Data database to talkie_coredata.sqlite")
        }

        // Step 2: Migrate from legacy filename if needed (talkie_grdb.sqlite → talkie.sqlite)
        if TalkieDatabase.migrateFilenameIfNeeded() {
            log.info("Migrated database from talkie_grdb.sqlite to talkie.sqlite")
        }
        #endif

        let dbPath = Self.databaseURL.path

        // Check if file exists
        let fileExists = FileManager.default.fileExists(atPath: dbPath)

        // Log concise status - less verbose for fresh installs
        if fileExists {
            log.info("Loading local database...", section: "Startup")
        } else {
            // Fresh install - don't alarm user, iCloud will sync separately
            log.info("Setting up local storage...", section: "Startup")
        }

        // Start a timeout warning task (only warn after 3 seconds)
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                log.warning("Database lock taking long...", section: "Startup")
                log.warning("Check for other Talkie processes", section: "Startup")
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
                        try db.execute(sql: "PRAGMA cache_size = -2000")  // 2MB cache (default)
                        try db.execute(sql: "PRAGMA busy_timeout = 5000")  // Retry on lock contention (cross-process safety)
                        try db.execute(sql: "PRAGMA journal_size_limit = 67108864")  // Cap WAL at 64MB
                    }

                    let queue = try DatabaseQueue(path: dbPath, configuration: config)
                    continuation.resume(returning: queue)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        timeoutTask.cancel()

        let migrator = self.migrator

        // Run migrations on background thread, with concise startup logging.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let appliedBefore = try Self.loadAppliedMigrationIdentifiers(from: dbQueue)
                    try migrator.migrate(dbQueue)
                    let appliedAfter = try Self.loadAppliedMigrationIdentifiers(from: dbQueue)
                    let newlyApplied = appliedAfter.filter { !appliedBefore.contains($0) }

                    if newlyApplied.isEmpty {
                        log.info("Database schema up to date (\(appliedAfter.count) migrations)", section: "Startup")
                    } else {
                        let preview = newlyApplied.prefix(5).joined(separator: ", ")
                        let more = newlyApplied.count > 5 ? " (+\(newlyApplied.count - 5) more)" : ""
                        log.info("Applied \(newlyApplied.count) database migration(s): \(preview)\(more)", section: "Startup")
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        // Single "ready" message - keep it simple
        log.info("Local storage ready", section: "Startup")

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

    private static func loadAppliedMigrationIdentifiers(from dbQueue: DatabaseQueue) throws -> [String] {
        try dbQueue.read { db in
            let migrationsTableExists = try Bool.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) > 0
                    FROM sqlite_master
                    WHERE type = 'table' AND name = 'grdb_migrations'
                    """
            ) ?? false

            guard migrationsTableExists else { return [] }
            return try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
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

    /// Get database queue, waiting for initialization if needed.
    /// Use this from async contexts that may fire before DB is ready (e.g. view .task/.onAppear).
    /// Polls with timeout instead of callback to avoid hanging if init fails.
    func databaseWhenReady() async throws -> DatabaseQueue {
        if isInitialized {
            return try database()
        }
        log.info("databaseWhenReady: waiting for initialization...")
        let deadline = Date().addingTimeInterval(15)
        while !isInitialized && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        if isInitialized {
            log.info("databaseWhenReady: ready")
        } else {
            log.error("databaseWhenReady: timed out after 15s")
        }
        return try database()
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

        // Migration v5: App stats table (single row, fast reads for Home/Stats views)
        migrator.registerMigration("v5_app_stats") { db in
            try db.create(table: "app_stats") { t in
                t.column("id", .integer).primaryKey()
                t.column("dictations_today", .integer).notNull().defaults(to: 0)
                t.column("dictations_week", .integer).notNull().defaults(to: 0)
                t.column("dictations_total", .integer).notNull().defaults(to: 0)
                t.column("words_total", .integer).notNull().defaults(to: 0)
                t.column("streak_days", .integer).notNull().defaults(to: 0)
                t.column("top_apps_json", .text)
                t.column("last_updated", .datetime)
            }

            // Insert default row so first load works (OR IGNORE if already exists)
            try db.execute(sql: "INSERT OR IGNORE INTO app_stats (id) VALUES (1)")
        }

        // Migration v6: Workflow preferences (file-based storage)
        // This table stores user preferences for workflows (pins, order, enabled)
        // The workflow definitions themselves are stored as JSON files
        migrator.registerMigration("v6_workflow_preferences") { db in
            print("📦 Creating workflow_preferences table...")

            try db.create(table: "workflow_preferences") { t in
                // Primary key is the workflow ID (from JSON file)
                t.column("workflowId", .text).primaryKey()

                // User preferences (not stored in JSON files)
                t.column("isEnabled", .boolean).notNull().defaults(to: true)
                t.column("isPinned", .boolean).notNull().defaults(to: false)
                t.column("autoRun", .boolean).notNull().defaults(to: false)
                t.column("autoRunOrder", .integer).notNull().defaults(to: 0)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)

                // Timestamps
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Index for sorting
            try db.create(index: "idx_workflow_prefs_sort",
                         on: "workflow_preferences",
                         columns: ["sortOrder"])

            // Index for pinned workflows
            try db.create(index: "idx_workflow_prefs_pinned",
                         on: "workflow_preferences",
                         columns: ["isPinned"])

            // Index for auto-run order
            try db.create(index: "idx_workflow_prefs_autorun",
                         on: "workflow_preferences",
                         columns: ["autoRun", "autoRunOrder"])

            print("✅ Workflow preferences table created!")
        }

        // Migration v7: Action context fields for workflow preferences
        // Allows actions (single-step workflows) to be shown in specific UI contexts
        migrator.registerMigration("v7_action_contexts") { db in
            print("📦 Adding action context fields to workflow_preferences...")

            // Add showInInterstitial column
            try db.alter(table: "workflow_preferences") { t in
                t.add(column: "showInInterstitial", .boolean).notNull().defaults(to: false)
            }

            // Add showInDrafts column
            try db.alter(table: "workflow_preferences") { t in
                t.add(column: "showInDrafts", .boolean).notNull().defaults(to: false)
            }

            // Add appBundleIDsJSON column (JSON array of bundle IDs)
            try db.alter(table: "workflow_preferences") { t in
                t.add(column: "appBundleIDsJSON", .text).notNull().defaults(to: "[]")
            }

            // Index for interstitial actions
            try db.create(index: "idx_workflow_prefs_interstitial",
                         on: "workflow_preferences",
                         columns: ["showInInterstitial", "isEnabled"])

            // Index for drafts actions
            try db.create(index: "idx_workflow_prefs_drafts",
                         on: "workflow_preferences",
                         columns: ["showInDrafts", "isEnabled"])

            print("✅ Action context fields migration complete!")
        }

        // Migration v8: Unified recordings table
        // Combines voice_memos and dictations into a single table
        migrator.registerMigration("v8_unified_recordings") { db in
            print("📦 Creating unified recordings table...")

            // Create the unified recordings table
            try db.create(table: "recordings") { t in
                // Identity
                t.column("id", .text).primaryKey()
                t.column("type", .text).notNull().defaults(to: "dictation")  // 'memo' | 'dictation'

                // Content
                t.column("text", .text)                    // Transcript text
                t.column("title", .text)                   // User-set title (memos only)
                t.column("notes", .text)                   // User annotations (memos only)

                // Audio (file-based, path derived from ID)
                t.column("duration", .double).notNull().defaults(to: 0)
                t.column("hasAudio", .boolean).notNull().defaults(to: false)

                // Timestamps
                t.column("createdAt", .datetime).notNull()
                t.column("lastModified", .datetime)
                t.column("deletedAt", .datetime)           // Soft delete (memos only)

                // Origin/Provenance (immutable after creation)
                t.column("source", .text).notNull()        // 'mac' | 'iphone' | 'watch' | 'live'
                t.column("sourceDeviceId", .text)

                // Promotion tracking
                t.column("promotedAt", .datetime)          // When dictation became memo

                // Transcription state
                t.column("transcriptionStatus", .text).defaults(to: "success")
                t.column("transcriptionError", .text)
                t.column("transcriptionModel", .text)

                // AI Processing (memos only)
                t.column("summary", .text)
                t.column("tasks", .text)
                t.column("reminders", .text)
                t.column("isProcessingSummary", .boolean).notNull().defaults(to: false)
                t.column("isProcessingTasks", .boolean).notNull().defaults(to: false)
                t.column("isProcessingReminders", .boolean).notNull().defaults(to: false)
                t.column("autoProcessed", .boolean).notNull().defaults(to: false)

                // Sync (memos only)
                t.column("cloudSyncedAt", .datetime)

                // Workflows
                t.column("pendingWorkflowIds", .text)

                // Context metadata (JSON blob for dictation-specific data)
                t.column("metadataJSON", .text)
            }

            // Create indexes for performance
            print("📦 Creating recordings indexes...")

            // Most common query: Sort by createdAt DESC (newest first)
            try db.create(index: "idx_recordings_createdAt",
                         on: "recordings",
                         columns: ["createdAt"])

            // Filter by type
            try db.create(index: "idx_recordings_type",
                         on: "recordings",
                         columns: ["type"])

            // Filter by source
            try db.create(index: "idx_recordings_source",
                         on: "recordings",
                         columns: ["source"])

            // Soft delete filter (partial index for deleted items)
            try db.create(index: "idx_recordings_deletedAt",
                         on: "recordings",
                         columns: ["deletedAt"])

            // CloudKit sync filter (memos that need sync)
            try db.create(index: "idx_recordings_cloudSync",
                         on: "recordings",
                         columns: ["type", "cloudSyncedAt"])

            // Transcription status filter (pending/failed items)
            try db.create(index: "idx_recordings_transcription",
                         on: "recordings",
                         columns: ["transcriptionStatus"])

            // Composite index for common list query: type + createdAt
            try db.create(index: "idx_recordings_type_created",
                         on: "recordings",
                         columns: ["type", "createdAt"])

            // Full-text search on transcript content
            try db.create(virtualTable: "recordings_fts", using: FTS5()) { t in
                t.column("title")
                t.column("text")
                t.column("notes")
            }

            print("✅ Unified recordings table created!")

            // MARK: - Migrate Existing Memos

            print("📦 Migrating existing memos to recordings...")

            // Copy all voice_memos to recordings
            // Derive source from originDeviceId:
            // - NULL or empty → 'iphone' (legacy format)
            // - 'mac-*' → 'mac'
            // - 'watch-*' → 'watch'
            // - 'live-*' → 'live'
            try db.execute(sql: """
                INSERT INTO recordings (
                    id, type, text, title, notes,
                    duration, hasAudio,
                    createdAt, lastModified, deletedAt,
                    source, sourceDeviceId,
                    promotedAt,
                    transcriptionStatus, transcriptionError, transcriptionModel,
                    summary, tasks, reminders,
                    isProcessingSummary, isProcessingTasks, isProcessingReminders, autoProcessed,
                    cloudSyncedAt, pendingWorkflowIds, metadataJSON
                )
                SELECT
                    id,
                    'memo',
                    transcription,
                    title,
                    notes,
                    duration,
                    CASE WHEN audioFilePath IS NOT NULL AND audioFilePath != '' THEN 1 ELSE 0 END,
                    createdAt,
                    lastModified,
                    deletedAt,
                    CASE
                        WHEN originDeviceId LIKE 'mac-%' THEN 'mac'
                        WHEN originDeviceId LIKE 'watch-%' THEN 'watch'
                        WHEN originDeviceId LIKE 'live-%' THEN 'live'
                        ELSE 'iphone'
                    END,
                    originDeviceId,
                    NULL,
                    CASE
                        WHEN isTranscribing = 1 THEN 'pending'
                        WHEN COALESCE(audioFilePath, '') != '' AND COALESCE(transcription, '') = '' THEN 'failed'
                        ELSE 'success'
                    END,
                    CASE
                        WHEN isTranscribing = 1 THEN NULL
                        WHEN COALESCE(audioFilePath, '') != '' AND COALESCE(transcription, '') = '' THEN 'Transcript missing, but audio is still available. Retry transcription from this Mac.'
                        ELSE NULL
                    END,
                    NULL,
                    summary,
                    tasks,
                    reminders,
                    isProcessingSummary,
                    isProcessingTasks,
                    isProcessingReminders,
                    autoProcessed,
                    cloudSyncedAt,
                    pendingWorkflowIds,
                    NULL
                FROM voice_memos
            """)

            let memoCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM recordings WHERE type = 'memo'") ?? 0
            print("✅ Migrated \(memoCount) memos to recordings table!")
        }

        // Migration v9: Add audioFilename column to recordings
        // Preserves original audio filenames from migrated memos
        migrator.registerMigration("v9_audio_filename") { db in
            print("📦 Adding audioFilename column to recordings...")

            // Add audioFilename column
            try db.alter(table: "recordings") { t in
                t.add(column: "audioFilename", .text)
            }

            // Backfill audioFilename from voice_memos.audioFilePath
            // Match by ID since we preserved IDs during v8 migration
            try db.execute(sql: """
                UPDATE recordings
                SET audioFilename = (
                    SELECT audioFilePath FROM voice_memos
                    WHERE voice_memos.id = recordings.id
                )
                WHERE recordings.type = 'memo'
                AND recordings.hasAudio = 1
            """)

            let updatedCount = db.changesCount
            print("✅ Backfilled \(updatedCount) audio filenames!")
        }

        // Migration v10: Backfill audioFilename for dictations from live.sqlite
        // The v8 migration and DictationMigrationService didn't copy audioFilename
        // NOTE: This is a legacy migration - TalkieAgent now writes directly to talkie_grdb.sqlite
        migrator.registerMigration("v10_dictation_audio_filename") { db in
            print("📦 Checking for legacy live.sqlite to backfill audioFilename...")

            // Check if live.sqlite exists
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            let livePath = appSupport
                .appendingPathComponent("Talkie", isDirectory: true)
                .appendingPathComponent("live.sqlite")
                .path

            guard FileManager.default.fileExists(atPath: livePath) else {
                print("✅ No legacy live.sqlite found - skipping backfill")
                return
            }

            // Attach live database
            try db.execute(sql: "ATTACH DATABASE '\(livePath)' AS live")

            // Check if dictations table exists in attached database
            let tableExists = try Bool.fetchOne(db, sql: """
                SELECT COUNT(*) > 0 FROM live.sqlite_master
                WHERE type = 'table' AND name = 'dictations'
            """) ?? false

            guard tableExists else {
                print("✅ No dictations table in live.sqlite - skipping backfill")
                try? db.execute(sql: "DETACH DATABASE live")
                return
            }

            // Update recordings with matching createdAt from dictations
            // live.sqlite uses epoch timestamps, recordings uses ISO dates
            // Convert recordings date to epoch for comparison
            try db.execute(sql: """
                UPDATE recordings
                SET audioFilename = (
                    SELECT d.audioFilename
                    FROM live.dictations d
                    WHERE d.audioFilename IS NOT NULL
                    AND ABS(CAST(strftime('%s', recordings.createdAt) AS REAL) - d.createdAt) <= 1.0
                    LIMIT 1
                )
                WHERE recordings.type = 'dictation'
                AND recordings.hasAudio = 1
                AND recordings.audioFilename IS NULL
            """)

            let updatedCount = db.changesCount
            print("✅ Backfilled \(updatedCount) dictation audio filenames!")

            // Detach live database (non-fatal if locked by another process)
            do {
                try db.execute(sql: "DETACH DATABASE live")
            } catch {
                print("⚠️ Could not detach live database (likely locked): \(error.localizedDescription)")
                // Non-fatal - the update already succeeded
            }
        }

        // Migration v11: Add unique constraint for dictations to prevent duplicates
        // Also clean up any existing duplicates first
        migrator.registerMigration("v11_dictation_unique_constraint") { db in
            print("📦 Adding unique constraint for dictations...")

            // First, delete duplicates keeping the one with audioFilename
            try db.execute(sql: """
                DELETE FROM recordings
                WHERE id IN (
                    SELECT r1.id
                    FROM recordings r1
                    INNER JOIN recordings r2 ON r1.createdAt = r2.createdAt
                    WHERE r1.type = 'dictation' AND r1.source = 'live'
                    AND r2.type = 'dictation' AND r2.source = 'live'
                    AND r1.id <> r2.id
                    AND r1.audioFilename IS NULL
                    AND r2.audioFilename IS NOT NULL
                )
            """)
            let deletedDuplicates = db.changesCount
            if deletedDuplicates > 0 {
                print("✅ Cleaned up \(deletedDuplicates) duplicate dictations")
            }

            // Add unique partial index for live dictations by timestamp
            // This prevents duplicate dictations at the database level
            try db.execute(sql: """
                CREATE UNIQUE INDEX IF NOT EXISTS idx_recordings_dictation_unique
                ON recordings(type, source, createdAt)
                WHERE type = 'dictation' AND source = 'live'
            """)
            print("✅ Added unique constraint for live dictations")
        }

        // Migration v12: Standardize audio filenames to {id}.m4a format
        // Audio is now always stored as {recording_id}.m4a - no more arbitrary filenames
        // hasAudio is computed from filesystem, audioFilename column is deprecated
        migrator.registerMigration("v12_standardize_audio_filenames") { db in
            print("📦 Standardizing audio filenames to {id}.m4a format...")

            // Fetch all recordings with non-standard audio filenames
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, audioFilename FROM recordings
                WHERE audioFilename IS NOT NULL
            """)

            var renamedCount = 0
            var skippedCount = 0

            for row in rows {
                // id is stored as binary UUID (16 bytes), audioFilename as TEXT
                guard let id = row["id"] as UUID?,
                      let oldFilename = row["audioFilename"] as String? else {
                    continue
                }

                let newFilename = "\(id.uuidString).m4a"

                // Skip if already in correct format
                if oldFilename == newFilename {
                    skippedCount += 1
                    continue
                }

                // Rename the audio file
                if AudioStorage.renameToStandardFormat(from: oldFilename, toRecordingID: id) {
                    renamedCount += 1
                } else {
                    // File might not exist or rename failed - that's OK, hasAudio will be false
                    print("⚠️ Could not rename audio for \(id): \(oldFilename)")
                }
            }

            print("✅ Renamed \(renamedCount) audio files, \(skippedCount) already in correct format")

            // Note: We don't drop audioFilename/hasAudio columns - GRDB ignores extra columns
            // Keeping them allows rollback if needed
        }

        // Migration v13: Add revision history support for interstitial sessions
        // Stores full revision history (original text, all LLM edits, accepted/rejected) as JSON
        migrator.registerMigration("v13_revision_history") { db in
            print("📦 Adding revision history support for interstitial sessions...")

            // Add revisionHistoryJSON column to voice_memos
            try db.alter(table: "voice_memos") { t in
                t.add(column: "revisionHistoryJSON", .text)
            }

            print("✅ Revision history column added!")
        }

        migrator.registerMigration("v14_sync_history_counts") { db in
            print("📦 Adding local/remote counts to sync history...")

            // Add count snapshot columns to sync_history
            try db.alter(table: "sync_history") { t in
                t.add(column: "localCount", .integer)
                t.add(column: "remoteCount", .integer)
            }

            print("✅ Sync history counts added!")
        }

        // Migration v15: Multi-provider sync operations tracking
        migrator.registerMigration("v15_sync_operations") { db in
            print("📦 Adding sync operations tracking for multi-provider sync...")

            // Track local changes that need to be synced to cloud providers
            try db.create(table: "sync_operations") { t in
                t.column("id", .text).primaryKey()
                t.column("memoId", .text).notNull()
                    .references("voice_memos", onDelete: .cascade)
                t.column("operation", .text).notNull()  // "create", "update", "delete"
                t.column("timestamp", .datetime).notNull()
                t.column("provider", .text).notNull()   // "icloud", "s3", "vercel", etc.
                t.column("status", .text).notNull().defaults(to: "pending")  // "pending", "synced", "failed"
                t.column("retryCount", .integer).notNull().defaults(to: 0)
                t.column("errorMessage", .text)
            }

            // Index for querying pending operations by provider
            try db.create(index: "idx_sync_ops_provider_status",
                         on: "sync_operations",
                         columns: ["provider", "status", "timestamp"])

            // Index for querying operations by memo
            try db.create(index: "idx_sync_ops_memo_id",
                         on: "sync_operations",
                         columns: ["memoId"])

            print("✅ Sync operations tracking added!")
        }

        // Migration v16: Persist per-run SyncClient activity logs with sync history
        migrator.registerMigration("v16_sync_history_activity_log") { db in
            print("📦 Adding activity log payload to sync history...")
            try db.alter(table: "sync_history") { t in
                t.add(column: "activityJSON", .text)
            }
            print("✅ Sync history activity log payload added!")
        }

        // Migration v17: Memo material-change history
        // Stores only meaningful memo field changes (not sync churn/internal fields).
        migrator.registerMigration("v17_memo_change_history") { db in
            print("📦 Adding memo change history table and triggers...")

            try db.create(table: "memo_change_history", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("memoId", .text).notNull()
                t.column("eventType", .text).notNull()   // create | update | delete | restore | hardDelete
                t.column("source", .text).notNull().defaults(to: "database")
                t.column("timestamp", .datetime).notNull()
                t.column("changedFields", .text).notNull().defaults(to: "")
                t.column("detailsJSON", .text)
            }

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_memo_change_history_memo_id_timestamp
                ON memo_change_history(memoId, timestamp DESC)
                """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_memo_change_history_timestamp
                ON memo_change_history(timestamp DESC)
                """)

            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS trg_voice_memos_history_insert
                AFTER INSERT ON voice_memos
                BEGIN
                    INSERT INTO memo_change_history (
                        id, memoId, eventType, source, timestamp, changedFields
                    ) VALUES (
                        lower(hex(randomblob(16))),
                        NEW.id,
                        'create',
                        'database',
                        CURRENT_TIMESTAMP,
                        'created'
                    );
                END
                """)

            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS trg_voice_memos_history_update
                AFTER UPDATE ON voice_memos
                WHEN
                    COALESCE(OLD.title, '') != COALESCE(NEW.title, '') OR
                    COALESCE(OLD.duration, 0) != COALESCE(NEW.duration, 0) OR
                    COALESCE(OLD.sortOrder, 0) != COALESCE(NEW.sortOrder, 0) OR
                    COALESCE(OLD.transcription, '') != COALESCE(NEW.transcription, '') OR
                    COALESCE(OLD.notes, '') != COALESCE(NEW.notes, '') OR
                    COALESCE(OLD.summary, '') != COALESCE(NEW.summary, '') OR
                    COALESCE(OLD.tasks, '') != COALESCE(NEW.tasks, '') OR
                    COALESCE(OLD.reminders, '') != COALESCE(NEW.reminders, '') OR
                    COALESCE(OLD.deletedAt, '') != COALESCE(NEW.deletedAt, '')
                BEGIN
                    INSERT INTO memo_change_history (
                        id, memoId, eventType, source, timestamp, changedFields
                    ) VALUES (
                        lower(hex(randomblob(16))),
                        NEW.id,
                        CASE
                            WHEN OLD.deletedAt IS NULL AND NEW.deletedAt IS NOT NULL THEN 'delete'
                            WHEN OLD.deletedAt IS NOT NULL AND NEW.deletedAt IS NULL THEN 'restore'
                            ELSE 'update'
                        END,
                        'database',
                        CURRENT_TIMESTAMP,
                        TRIM(
                            (CASE WHEN COALESCE(OLD.title, '') != COALESCE(NEW.title, '') THEN 'title,' ELSE '' END) ||
                            (CASE WHEN COALESCE(OLD.duration, 0) != COALESCE(NEW.duration, 0) THEN 'duration,' ELSE '' END) ||
                            (CASE WHEN COALESCE(OLD.sortOrder, 0) != COALESCE(NEW.sortOrder, 0) THEN 'sortOrder,' ELSE '' END) ||
                            (CASE WHEN COALESCE(OLD.transcription, '') != COALESCE(NEW.transcription, '') THEN 'transcription,' ELSE '' END) ||
                            (CASE WHEN COALESCE(OLD.notes, '') != COALESCE(NEW.notes, '') THEN 'notes,' ELSE '' END) ||
                            (CASE WHEN COALESCE(OLD.summary, '') != COALESCE(NEW.summary, '') THEN 'summary,' ELSE '' END) ||
                            (CASE WHEN COALESCE(OLD.tasks, '') != COALESCE(NEW.tasks, '') THEN 'tasks,' ELSE '' END) ||
                            (CASE WHEN COALESCE(OLD.reminders, '') != COALESCE(NEW.reminders, '') THEN 'reminders,' ELSE '' END) ||
                            (CASE WHEN COALESCE(OLD.deletedAt, '') != COALESCE(NEW.deletedAt, '') THEN 'deletedAt,' ELSE '' END),
                            ','
                        )
                    );
                END
                """)

            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS trg_voice_memos_history_delete
                AFTER DELETE ON voice_memos
                BEGIN
                    INSERT INTO memo_change_history (
                        id, memoId, eventType, source, timestamp, changedFields
                    ) VALUES (
                        lower(hex(randomblob(16))),
                        OLD.id,
                        'hardDelete',
                        'database',
                        CURRENT_TIMESTAMP,
                        'deleted'
                    );
                END
                """)

            print("✅ Memo change history added!")
        }

        // Migration v18: Explicit sync inbox + external reference linkage for recordings
        // - sync_inbox_records: provider-agnostic ingest tracking (sync-only)
        // - recordings.external*: stable external identity + linkage metadata
        migrator.registerMigration("v18_sync_inbox_and_external_refs") { db in
            print("📦 Adding sync inbox table and external recording references...")

            try db.create(table: "sync_inbox_records", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("provider", .text).notNull()          // cloudkit | s3 | ...
                t.column("entityType", .text).notNull()        // voice_memo | ...
                t.column("externalRefID", .text).notNull()     // provider-native stable ID
                t.column("remoteModifiedAt", .datetime)
                t.column("canonicalHash", .text)
                t.column("payloadJSON", .text)
                t.column("status", .text).notNull().defaults(to: "pending") // pending|applied|failed
                t.column("firstSeenAt", .datetime).notNull()
                t.column("lastSeenAt", .datetime).notNull()
                t.column("appliedAt", .datetime)
                t.column("lastError", .text)
                t.column("attemptCount", .integer).notNull().defaults(to: 0)
            }

            try db.execute(sql: """
                CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_inbox_unique_ref
                ON sync_inbox_records(provider, entityType, externalRefID)
                """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_sync_inbox_status_last_seen
                ON sync_inbox_records(status, lastSeenAt DESC)
                """)

            func hasColumn(_ table: String, _ column: String) throws -> Bool {
                try (Bool.fetchOne(
                    db,
                    sql: """
                        SELECT EXISTS(
                            SELECT 1
                            FROM pragma_table_info(?)
                            WHERE name = ?
                        )
                        """,
                    arguments: [table, column]
                )) ?? false
            }

            if try db.tableExists("recordings") {
                if try !hasColumn("recordings", "externalProvider") {
                    try db.execute(sql: "ALTER TABLE recordings ADD COLUMN externalProvider TEXT")
                }
                if try !hasColumn("recordings", "externalEntityType") {
                    try db.execute(sql: "ALTER TABLE recordings ADD COLUMN externalEntityType TEXT")
                }
                if try !hasColumn("recordings", "externalRefID") {
                    try db.execute(sql: "ALTER TABLE recordings ADD COLUMN externalRefID TEXT")
                }
                if try !hasColumn("recordings", "externalCanonicalHash") {
                    try db.execute(sql: "ALTER TABLE recordings ADD COLUMN externalCanonicalHash TEXT")
                }
                if try !hasColumn("recordings", "externalRemoteModifiedAt") {
                    try db.execute(sql: "ALTER TABLE recordings ADD COLUMN externalRemoteModifiedAt DATETIME")
                }
                if try !hasColumn("recordings", "externalLastSeenAt") {
                    try db.execute(sql: "ALTER TABLE recordings ADD COLUMN externalLastSeenAt DATETIME")
                }

                try db.execute(sql: """
                    CREATE UNIQUE INDEX IF NOT EXISTS idx_recordings_external_ref_unique
                    ON recordings(externalProvider, externalEntityType, externalRefID)
                    WHERE externalProvider IS NOT NULL
                      AND externalEntityType IS NOT NULL
                      AND externalRefID IS NOT NULL
                    """)
                try db.execute(sql: """
                    CREATE INDEX IF NOT EXISTS idx_recordings_external_provider_seen
                    ON recordings(externalProvider, externalLastSeenAt DESC)
                    """)

                // Backfill memo rows so existing installs get immediate linkage.
                // Single JOIN avoids redundant EXISTS subqueries per row.
                try db.execute(sql: """
                    UPDATE recordings
                    SET
                        externalProvider      = 'cloudkit',
                        externalEntityType    = 'voice_memo',
                        externalRefID         = lower(hex(recordings.id)),
                        externalRemoteModifiedAt = COALESCE(vm.lastModified, recordings.externalRemoteModifiedAt),
                        externalLastSeenAt       = COALESCE(vm.cloudSyncedAt, vm.lastModified, recordings.externalLastSeenAt)
                    FROM voice_memos vm
                    WHERE vm.id = recordings.id
                      AND vm.cloudSyncedAt IS NOT NULL
                      AND recordings.type = 'memo'
                """)
            }

            print("✅ Sync inbox + external recording references added!")
        }

        // Migration v19: Consolidated assets column (segments, screenshots, clips, attachments)
        migrator.registerMigration("v19_transcription_segments") { db in
            try db.alter(table: "recordings") { t in
                t.add(column: "assetsJSON", .text)        // JSON-encoded TalkieObjectAssets
            }
        }

        // Migration v20: (no-op, consolidated into v19 assetsJSON)
        migrator.registerMigration("v20_video_clips") { _ in }

        // Migration v21: Sync completion stats breakdown in sync_history
        migrator.registerMigration("v21_sync_history_stats") { db in
            try db.alter(table: "sync_history") { t in
                t.add(column: "inserted", .integer)
                t.add(column: "updated", .integer)
                t.add(column: "deleted", .integer)
                t.add(column: "skipped", .integer)
                t.add(column: "fetchTimeMs", .integer)
                t.add(column: "totalTimeMs", .integer)
            }
        }

        // Migration v22: Sync mode tracking (full vs incremental)
        migrator.registerMigration("v22_sync_history_mode") { db in
            try db.alter(table: "sync_history") { t in
                t.add(column: "syncMode", .text)
            }
        }

        // Migration v23: Dictation segments — persistent building blocks of notes
        migrator.registerMigration("v23_dictation_segments") { db in
            // Idempotent: columns may already exist from a partial previous run
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(recordings)").map { $0["name"] as String }
            if !columns.contains("parentId") {
                try db.alter(table: "recordings") { t in
                    t.add(column: "parentId", .text)
                }
            }
            if !columns.contains("segmentIndex") {
                try db.alter(table: "recordings") { t in
                    t.add(column: "segmentIndex", .integer)
                }
            }
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_recordings_parentId ON recordings(parentId)")
        }

        // Migration v24: (no-op, consolidated into v19 assetsJSON)
        migrator.registerMigration("v24_attachments") { _ in }

        // Migration v25: Add assetsJSON column if missing
        // The v19 migration was changed to add assetsJSON instead of segmentsJSON/screenshotsJSON,
        // but existing databases already ran the old v19. This ensures assetsJSON exists and
        // migrates data from the old columns.
        migrator.registerMigration("v25_ensure_assetsJSON") { db in
            // Check if assetsJSON column already exists using raw SQL
            let hasAssets = try Bool.fetchOne(db, sql: """
                SELECT COUNT(*) > 0 FROM pragma_table_info('recordings') WHERE name = 'assetsJSON'
                """) ?? false
            guard !hasAssets else { return }

            try db.alter(table: "recordings") { t in
                t.add(column: "assetsJSON", .text)
            }

            // Migrate existing segmentsJSON/screenshotsJSON data into assetsJSON
            let hasSeg = try Bool.fetchOne(db, sql: """
                SELECT COUNT(*) > 0 FROM pragma_table_info('recordings') WHERE name = 'segmentsJSON'
                """) ?? false
            let hasSS = try Bool.fetchOne(db, sql: """
                SELECT COUNT(*) > 0 FROM pragma_table_info('recordings') WHERE name = 'screenshotsJSON'
                """) ?? false
            guard hasSeg || hasSS else { return }

            // Use raw SQL to build and merge JSON — avoids Row subscript issues
            if hasSeg && hasSS {
                try db.execute(sql: """
                    UPDATE recordings SET assetsJSON =
                        CASE
                            WHEN segmentsJSON IS NOT NULL AND screenshotsJSON IS NOT NULL
                                THEN '{"segments":' || segmentsJSON || ',"screenshots":' || screenshotsJSON || '}'
                            WHEN segmentsJSON IS NOT NULL
                                THEN '{"segments":' || segmentsJSON || '}'
                            WHEN screenshotsJSON IS NOT NULL
                                THEN '{"screenshots":' || screenshotsJSON || '}'
                        END
                    WHERE segmentsJSON IS NOT NULL OR screenshotsJSON IS NOT NULL
                    """)
            } else if hasSeg {
                try db.execute(sql: """
                    UPDATE recordings SET assetsJSON = '{"segments":' || segmentsJSON || '}'
                    WHERE segmentsJSON IS NOT NULL
                    """)
            } else {
                try db.execute(sql: """
                    UPDATE recordings SET assetsJSON = '{"screenshots":' || screenshotsJSON || '}'
                    WHERE screenshotsJSON IS NOT NULL
                    """)
            }
        }

        migrator.registerMigration("v26_transcript_versions_fk_fix") { db in
            // transcript_versions.memoId FK references voice_memos, but notes live
            // in recordings. Recreate the table with FK pointing to recordings.
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM transcript_versions")

            try db.drop(table: "transcript_versions")

            try db.create(table: "transcript_versions") { t in
                t.column("id", .text).primaryKey()
                t.column("memoId", .text).notNull()
                    .references("recordings", column: "id", onDelete: .cascade)
                t.column("version", .integer).notNull()
                t.column("content", .text).notNull()
                t.column("sourceType", .text).notNull()
                t.column("engine", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("transcriptionDurationMs", .integer).notNull().defaults(to: 0)
            }

            try db.create(index: "idx_transcript_versions_memo_id",
                         on: "transcript_versions",
                         columns: ["memoId"])

            // Re-insert rows that have a matching recording (skip orphans)
            for row in rows {
                let memoId = row["memoId"] as? String ?? ""
                let exists = try Bool.fetchOne(db, sql:
                    "SELECT COUNT(*) > 0 FROM recordings WHERE id = ?",
                    arguments: [memoId]) ?? false
                guard exists else { continue }

                try db.execute(sql: """
                    INSERT INTO transcript_versions (id, memoId, version, content, sourceType, engine, createdAt, transcriptionDurationMs)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        row["id"], row["memoId"], row["version"], row["content"],
                        row["sourceType"], row["engine"], row["createdAt"],
                        row["transcriptionDurationMs"]
                    ])
            }
        }

        migrator.registerMigration("v27_content_history") { db in
            try db.create(table: "content_history") { t in
                t.column("id", .blob).primaryKey()
                t.column("recordingId", .blob).notNull()
                    .references("recordings", column: "id", onDelete: .cascade)
                t.column("title", .text)
                t.column("text", .text).notNull()
                t.column("source", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(index: "idx_content_history_recording",
                         on: "content_history",
                         columns: ["recordingId", "createdAt"])
        }

        return migrator
    }

    // MARK: - App Stats

    /// App stats for fast UI rendering (single row)
    struct AppStats {
        var dictationsToday: Int = 0
        var dictationsWeek: Int = 0
        var dictationsTotal: Int = 0
        var wordsTotal: Int = 0
        var streakDays: Int = 0
        var topApps: [(name: String, bundleID: String?, count: Int)] = []
        var lastUpdated: Date?
    }

    /// Fetch app stats (fast - single row read)
    func fetchAppStats() throws -> AppStats {
        let db = try database()
        return try db.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT * FROM app_stats WHERE id = 1")
            var stats = AppStats()
            if let row = row {
                stats.dictationsToday = row["dictations_today"] ?? 0
                stats.dictationsWeek = row["dictations_week"] ?? 0
                stats.dictationsTotal = row["dictations_total"] ?? 0
                stats.wordsTotal = row["words_total"] ?? 0
                stats.streakDays = row["streak_days"] ?? 0
                stats.lastUpdated = row["last_updated"]

                // Decode top apps JSON
                if let json: String = row["top_apps_json"],
                   let data = json.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([[String: String]].self, from: data) {
                    stats.topApps = decoded.compactMap { dict in
                        guard let name = dict["name"], let countStr = dict["count"], let count = Int(countStr) else { return nil }
                        return (name: name, bundleID: dict["bundleID"], count: count)
                    }
                }
            }
            return stats
        }
    }

    /// Update app stats from dictations array
    func updateAppStats(
        dictationsToday: Int,
        dictationsWeek: Int,
        dictationsTotal: Int,
        wordsTotal: Int,
        streakDays: Int,
        topApps: [(name: String, bundleID: String?, count: Int)]
    ) throws {
        let db = try database()

        // Encode top apps to JSON
        let topAppsData = topApps.map { ["name": $0.name, "bundleID": $0.bundleID ?? "", "count": String($0.count)] }
        let topAppsJSON = (try? JSONEncoder().encode(topAppsData)).flatMap { String(data: $0, encoding: .utf8) }

        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE app_stats SET
                        dictations_today = ?,
                        dictations_week = ?,
                        dictations_total = ?,
                        words_total = ?,
                        streak_days = ?,
                        top_apps_json = ?,
                        last_updated = ?
                    WHERE id = 1
                    """,
                arguments: [
                    dictationsToday,
                    dictationsWeek,
                    dictationsTotal,
                    wordsTotal,
                    streakDays,
                    topAppsJSON,
                    Date()
                ]
            )
        }
    }

    /// Increment today, week, and total counts by 1 (cheap, for real-time updates)
    func incrementDictationCounts() throws {
        let db = try database()
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE app_stats SET
                        dictations_today = dictations_today + 1,
                        dictations_week = dictations_week + 1,
                        dictations_total = dictations_total + 1
                    WHERE id = 1
                    """
            )
        }
    }
}

// MARK: - Errors

enum DatabaseError: Error {
    case notInitialized
    case migrationFailed(Error)
    case queryFailed(Error)
}
