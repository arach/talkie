//
//  UnifiedDatabase.swift
//  TalkieAgent
//
//  Single source of truth for TalkieAgent dictations.
//  Uses the unified recordings table in talkie.sqlite.
//
//  Database path is defined in TalkieKit/DatabasePaths.swift
//

import Foundation
import GRDB
import TalkieKit

private let log = Log(.database)

// MARK: - Unified Database

enum UnifiedDatabase {
    /// Database URL from shared TalkieKit constants
    /// ~/Library/Application Support/Talkie/talkie.sqlite
    static var databaseURL: URL { TalkieDatabase.databaseURL }

    /// Shared database queue for unified storage
    static let shared: DatabaseQueue = {
        do {
            let fm = FileManager.default

            // Migrate from legacy filename if needed (talkie_grdb.sqlite → talkie.sqlite)
            if TalkieDatabase.migrateFilenameIfNeeded() {
                log.info("[UnifiedDatabase] Migrated from talkie_grdb.sqlite to talkie.sqlite")
            }

            // Ensure parent directory exists
            try fm.createDirectory(at: TalkieDatabase.folderURL, withIntermediateDirectories: true)

            // Configure for WAL mode (concurrent reads/writes)
            // CRITICAL: busy_timeout ensures writes retry instead of failing instantly
            // when Talkie is mid-read on the same database
            var config = Configuration()
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA journal_mode = WAL")
                try db.execute(sql: "PRAGMA synchronous = NORMAL")
                try db.execute(sql: "PRAGMA busy_timeout = 10000")      // Retry for 10 seconds on lock contention
                try db.execute(sql: "PRAGMA temp_store = MEMORY")       // Faster temp tables
                try db.execute(sql: "PRAGMA cache_size = -32000")       // 128MB cache for dictations
                try db.execute(sql: "PRAGMA journal_size_limit = 67108864")  // Cap WAL at 64MB
            }

            let dbPath = databaseURL.path

            let dbQueue = try DatabaseQueue(path: dbPath, configuration: config)
            log.info("[UnifiedDatabase] Opened: \(dbPath)")

            // Ensure recordings table exists (Talkie runs full migrations, we just need the table)
            try ensureRecordingsTable(dbQueue)

            return dbQueue
        } catch {
            log.error("[UnifiedDatabase] Failed to open: \(error.localizedDescription)")
            log.error("[UnifiedDatabase] Falling back to in-memory database")

            do {
                let memoryDb = try DatabaseQueue()
                try ensureRecordingsTable(memoryDb)
                return memoryDb
            } catch {
                log.fault("[UnifiedDatabase] In-memory also failed: \(error)")
                return try! DatabaseQueue()
            }
        }
    }()

    /// Ensure recordings table exists (minimal migration for TalkieAgent)
    /// Full migration is owned by Talkie - this just creates the table if missing
    private static func ensureRecordingsTable(_ dbQueue: DatabaseQueue) throws {
        try dbQueue.write { db in
            // Check if table already exists
            if try db.tableExists("recordings") {
                log.info("[UnifiedDatabase] Recordings table exists")

                // Check if columns exist, add if missing
                let columns = try db.columns(in: "recordings")
                let columnNames = Set(columns.map { $0.name })

                if !columnNames.contains("audioFilename") {
                    log.info("[UnifiedDatabase] Adding audioFilename column...")
                    try db.execute(sql: "ALTER TABLE recordings ADD COLUMN audioFilename TEXT")
                    log.info("[UnifiedDatabase] audioFilename column added")
                }
                if !columnNames.contains("assetsJSON") {
                    log.info("[UnifiedDatabase] Adding assetsJSON column...")
                    try db.execute(sql: "ALTER TABLE recordings ADD COLUMN assetsJSON TEXT")
                    log.info("[UnifiedDatabase] assetsJSON column added")

                    // Migrate data from legacy columns into assetsJSON
                    if columnNames.contains("segmentsJSON") || columnNames.contains("screenshotsJSON") {
                        log.info("[UnifiedDatabase] Migrating legacy segmentsJSON/screenshotsJSON into assetsJSON...")
                        let rows = try Row.fetchAll(db, sql: """
                            SELECT id, segmentsJSON, screenshotsJSON FROM recordings
                            WHERE segmentsJSON IS NOT NULL OR screenshotsJSON IS NOT NULL
                        """)
                        for row in rows {
                            let rowId: String = row["id"]
                            let segments: String? = row["segmentsJSON"]
                            let screenshots: String? = row["screenshotsJSON"]
                            let assetsJSON = LiveRecording.buildAssetsJSON(segmentsJSON: segments, screenshotsJSON: screenshots)
                            try db.execute(
                                sql: "UPDATE recordings SET assetsJSON = ? WHERE id = ?",
                                arguments: [assetsJSON, rowId]
                            )
                        }
                        log.info("[UnifiedDatabase] Migrated \(rows.count) rows to assetsJSON")
                    }
                }
                if !columnNames.contains("parentId") {
                    log.info("[UnifiedDatabase] Adding parentId column...")
                    try db.execute(sql: "ALTER TABLE recordings ADD COLUMN parentId TEXT")
                    log.info("[UnifiedDatabase] parentId column added")
                }
                if !columnNames.contains("segmentIndex") {
                    log.info("[UnifiedDatabase] Adding segmentIndex column...")
                    try db.execute(sql: "ALTER TABLE recordings ADD COLUMN segmentIndex INTEGER")
                    log.info("[UnifiedDatabase] segmentIndex column added")
                }

                return
            }

            // Create the recordings table (matching Talkie's schema)
            log.info("[UnifiedDatabase] Creating recordings table...")
            try db.create(table: "recordings") { t in
                t.column("id", .text).primaryKey()
                t.column("type", .text).notNull().defaults(to: "dictation")
                t.column("text", .text)
                t.column("title", .text)
                t.column("notes", .text)
                t.column("duration", .double).notNull().defaults(to: 0)
                t.column("audioFilename", .text)  // Actual audio filename (may differ from {id}.m4a)
                t.column("createdAt", .datetime).notNull()
                t.column("lastModified", .datetime)
                t.column("deletedAt", .datetime)
                t.column("source", .text).notNull()
                t.column("sourceDeviceId", .text)
                t.column("promotedAt", .datetime)
                t.column("transcriptionStatus", .text).defaults(to: "success")
                t.column("transcriptionError", .text)
                t.column("transcriptionModel", .text)
                t.column("summary", .text)
                t.column("tasks", .text)
                t.column("reminders", .text)
                t.column("isProcessingSummary", .boolean).notNull().defaults(to: false)
                t.column("isProcessingTasks", .boolean).notNull().defaults(to: false)
                t.column("isProcessingReminders", .boolean).notNull().defaults(to: false)
                t.column("autoProcessed", .boolean).notNull().defaults(to: false)
                t.column("cloudSyncedAt", .datetime)
                t.column("pendingWorkflowIds", .text)
                t.column("metadataJSON", .text)
                t.column("assetsJSON", .text)
                t.column("parentId", .text)
                t.column("segmentIndex", .integer)
            }

            // Create essential indexes
            try db.create(index: "idx_recordings_createdAt", on: "recordings", columns: ["createdAt"], ifNotExists: true)
            try db.create(index: "idx_recordings_type", on: "recordings", columns: ["type"], ifNotExists: true)

            log.info("[UnifiedDatabase] Recordings table created")
        }
    }
}

// MARK: - LiveRecording (Write-Only Model for TalkieAgent)

/// Simplified recording model for TalkieAgent writes
/// Full Recording model lives in Talkie - this is just for writing dictations
struct LiveRecording: Identifiable {
    let id: UUID
    var type: String = "dictation"
    var text: String
    var duration: Double
    var audioFilename: String?  // Actual audio filename (stored, not computed)
    var createdAt: Date
    var source: String = "live"
    var sourceDeviceId: String? = "live-auto"
    var transcriptionStatus: String
    var transcriptionError: String?
    var transcriptionModel: String?
    var notes: String?
    var metadataJSON: String?
    var assetsJSON: String?
    var parentId: String?       // Links segment → parent note (UUID string)
    var segmentIndex: Int?      // Order within note (0-based)

    /// Whether this recording has audio
    var hasAudio: Bool {
        audioFilename != nil
    }

    /// Create from a LiveDictation (for compatibility during transition)
    init(from dictation: LiveDictation) {
        self.id = UUID()
        self.text = dictation.text
        self.duration = dictation.durationSeconds ?? 0
        self.audioFilename = dictation.audioFilename  // Store actual filename
        self.createdAt = dictation.createdAt
        self.transcriptionStatus = dictation.transcriptionStatus.rawValue
        self.transcriptionError = dictation.transcriptionError
        self.transcriptionModel = dictation.transcriptionModel
        self.metadataJSON = Self.buildMetadataJSON(from: dictation)
    }

    /// Create a new dictation recording
    init(
        id: UUID = UUID(),
        text: String,
        duration: Double = 0,
        audioFilename: String? = nil,
        transcriptionStatus: String = "success",
        transcriptionError: String? = nil,
        transcriptionModel: String? = nil,
        appBundleID: String? = nil,
        appName: String? = nil,
        windowTitle: String? = nil,
        perfEngineMs: Int? = nil,
        perfEndToEndMs: Int? = nil,
        perfInAppMs: Int? = nil,
        sessionId: String? = nil,
        mode: String? = nil,
        browserURL: String? = nil,
        documentURL: String? = nil,
        terminalWorkingDir: String? = nil
    ) {
        self.id = id
        self.text = text
        self.duration = duration
        self.audioFilename = audioFilename
        self.createdAt = Date()
        self.transcriptionStatus = transcriptionStatus
        self.transcriptionError = transcriptionError
        self.transcriptionModel = transcriptionModel
        self.metadataJSON = Self.buildMetadataJSON(
            appBundleID: appBundleID,
            appName: appName,
            windowTitle: windowTitle,
            perfEngineMs: perfEngineMs,
            perfEndToEndMs: perfEndToEndMs,
            perfInAppMs: perfInAppMs,
            sessionId: sessionId,
            mode: mode,
            browserURL: browserURL,
            documentURL: documentURL,
            terminalWorkingDir: terminalWorkingDir
        )
    }

    /// Build metadata JSON from dictation fields
    private static func buildMetadataJSON(from dictation: LiveDictation) -> String? {
        return buildMetadataJSON(
            appBundleID: dictation.appBundleID,
            appName: dictation.appName,
            windowTitle: dictation.windowTitle,
            perfEngineMs: dictation.perfEngineMs,
            perfEndToEndMs: dictation.perfEndToEndMs,
            perfInAppMs: dictation.perfInAppMs,
            sessionId: dictation.sessionID,
            mode: dictation.mode,
            browserURL: dictation.metadata?["browserURL"],
            documentURL: dictation.metadata?["documentURL"],
            terminalWorkingDir: dictation.metadata?["terminalWorkingDir"],
            refinementRawText: dictation.metadata?["refinement.rawText"],
            refinementRefined: dictation.metadata?["refinement.refined"],
            refinementPrompt: dictation.metadata?["refinement.prompt"],
            refinementRuleName: dictation.metadata?["refinement.ruleName"],
            refinementModel: dictation.metadata?["refinement.model"],
            refinementLatencyMs: dictation.metadata?["refinement.latencyMs"]
        )
    }

    /// Build metadata JSON from individual fields
    private static func buildMetadataJSON(
        appBundleID: String?,
        appName: String?,
        windowTitle: String?,
        perfEngineMs: Int?,
        perfEndToEndMs: Int?,
        perfInAppMs: Int?,
        sessionId: String?,
        mode: String?,
        browserURL: String?,
        documentURL: String?,
        terminalWorkingDir: String?,
        refinementRawText: String? = nil,
        refinementRefined: String? = nil,
        refinementPrompt: String? = nil,
        refinementRuleName: String? = nil,
        refinementModel: String? = nil,
        refinementLatencyMs: String? = nil
    ) -> String? {
        var metadata: [String: Any] = [:]

        // App context
        var app: [String: String] = [:]
        if let bundleId = appBundleID { app["bundleId"] = bundleId }
        if let name = appName { app["name"] = name }
        if let title = windowTitle { app["windowTitle"] = title }
        if !app.isEmpty { metadata["app"] = app }

        // Performance metrics
        var perf: [String: Any] = [:]
        if let ms = perfEngineMs { perf["engineMs"] = ms }
        if let ms = perfEndToEndMs { perf["endToEndMs"] = ms }
        if let ms = perfInAppMs { perf["inAppMs"] = ms }
        if let sid = sessionId { perf["sessionId"] = sid }
        if !perf.isEmpty { metadata["performance"] = perf }

        // Rich context
        var context: [String: String] = [:]
        if let url = browserURL { context["browserURL"] = url }
        if let url = documentURL { context["documentURL"] = url }
        if let dir = terminalWorkingDir { context["terminalWorkingDir"] = dir }
        if !context.isEmpty { metadata["context"] = context }

        // Routing info
        if let mode = mode {
            metadata["routing"] = ["mode": mode]
        }

        // Refinement info
        var refinement: [String: String] = [:]
        if let raw = refinementRawText { refinement["rawText"] = raw }
        if let refined = refinementRefined { refinement["refined"] = refined }
        if let prompt = refinementPrompt { refinement["prompt"] = prompt }
        if let rule = refinementRuleName { refinement["ruleName"] = rule }
        if let model = refinementModel { refinement["model"] = model }
        if let latency = refinementLatencyMs { refinement["latencyMs"] = latency }
        if !refinement.isEmpty { metadata["refinement"] = refinement }

        guard !metadata.isEmpty else { return nil }

        do {
            let data = try JSONSerialization.data(withJSONObject: metadata)
            let json = String(data: data, encoding: .utf8)
            return json
        } catch {
            return nil
        }
    }

    // MARK: - Assets JSON Helpers

    /// Build a consolidated assetsJSON string from separate segment, screenshot, and provenance inputs.
    static func buildAssetsJSON(
        segmentsJSON: String? = nil,
        screenshotsJSON: String? = nil,
        textProvenance: [ProvenanceSegment]? = nil
    ) -> String? {
        let screenshots = RecordingScreenshot.fromArray(json: screenshotsJSON)
        let provenance = textProvenance?.isEmpty == false ? textProvenance : nil

        let assets = TalkieObjectAssets(
            segments: TimedTranscription.from(json: segmentsJSON),
            screenshots: screenshots,
            clips: [],
            attachments: [],
            textProvenance: provenance
        )

        return assets.isEmpty ? nil : assets.toJSON()
    }

    /// Convenience: set assetsJSON from separate segment, screenshot, and provenance values.
    mutating func setAssets(
        segmentsJSON: String? = nil,
        screenshotsJSON: String? = nil,
        textProvenance: [ProvenanceSegment]? = nil
    ) {
        self.assetsJSON = Self.buildAssetsJSON(
            segmentsJSON: segmentsJSON,
            screenshotsJSON: screenshotsJSON,
            textProvenance: textProvenance
        )
    }
}

// MARK: - GRDB Conformance

extension LiveRecording: FetchableRecord, PersistableRecord {
    static let databaseTableName = "recordings"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let type = Column(CodingKeys.type)
        static let text = Column(CodingKeys.text)
        static let duration = Column(CodingKeys.duration)
        static let audioFilename = Column(CodingKeys.audioFilename)
        static let createdAt = Column(CodingKeys.createdAt)
        static let source = Column(CodingKeys.source)
        static let sourceDeviceId = Column(CodingKeys.sourceDeviceId)
        static let transcriptionStatus = Column(CodingKeys.transcriptionStatus)
        static let transcriptionError = Column(CodingKeys.transcriptionError)
        static let transcriptionModel = Column(CodingKeys.transcriptionModel)
        static let notes = Column(CodingKeys.notes)
        static let metadataJSON = Column(CodingKeys.metadataJSON)
        static let assetsJSON = Column(CodingKeys.assetsJSON)
        static let parentId = Column(CodingKeys.parentId)
        static let segmentIndex = Column(CodingKeys.segmentIndex)
    }

    enum CodingKeys: String, CodingKey {
        case id, type, text, duration, audioFilename, createdAt
        case source, sourceDeviceId
        case transcriptionStatus, transcriptionError, transcriptionModel
        case notes, metadataJSON, assetsJSON
        case parentId, segmentIndex
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id.uuidString
        container["type"] = type
        container["text"] = text
        container["duration"] = duration
        container["audioFilename"] = audioFilename
        container["createdAt"] = createdAt
        container["source"] = source
        container["sourceDeviceId"] = sourceDeviceId
        container["transcriptionStatus"] = transcriptionStatus
        container["transcriptionError"] = transcriptionError
        container["transcriptionModel"] = transcriptionModel
        container["notes"] = notes
        container["metadataJSON"] = metadataJSON
        container["assetsJSON"] = assetsJSON
        container["parentId"] = parentId
        container["segmentIndex"] = segmentIndex
    }

    init(row: Row) throws {
        // Handle both text UUIDs ("A1B2C3D4-...") and binary UUIDs (16-byte blob from Core Data)
        let rawValue = row["id"] as DatabaseValue
        let uuid: UUID
        switch rawValue.storage {
        case .string(let idString):
            guard let parsed = UUID(uuidString: idString) else {
                throw DatabaseError(message: "Invalid UUID string: \(idString)")
            }
            uuid = parsed
        case .blob(let data) where data.count == 16:
            uuid = UUID(uuid: data.withUnsafeBytes { $0.load(as: uuid_t.self) })
        default:
            throw DatabaseError(message: "Unexpected id column type: \(rawValue)")
        }
        id = uuid
        type = row["type"] ?? "dictation"
        text = row["text"] ?? ""
        duration = row["duration"] ?? 0
        audioFilename = row["audioFilename"]
        createdAt = row["createdAt"] ?? Date()
        transcriptionStatus = row["transcriptionStatus"] ?? "success"
        transcriptionError = row["transcriptionError"]
        transcriptionModel = row["transcriptionModel"]
        notes = row["notes"]
        metadataJSON = row["metadataJSON"]
        assetsJSON = row["assetsJSON"]
        parentId = row["parentId"]
        segmentIndex = row["segmentIndex"]
    }
}

// MARK: - Write Operations

extension UnifiedDatabase {

    /// Store a new dictation recording
    @discardableResult
    static func store(_ recording: LiveRecording) -> UUID? {
        do {
            try shared.write { db in
                try recording.insert(db)
            }
            log.info("[UnifiedDatabase] Stored recording \(recording.id.uuidString.prefix(8))")
            return recording.id
        } catch {
            log.error("[UnifiedDatabase] Store failed: \(error)")
            return nil
        }
    }

    /// Update transcription result
    static func updateTranscription(id: UUID, text: String, model: String?) {
        do {
            try shared.write { db in
                try db.execute(
                    sql: """
                        UPDATE recordings SET
                            text = ?,
                            transcriptionModel = ?,
                            transcriptionStatus = 'success',
                            transcriptionError = NULL
                        WHERE id = ?
                        """,
                    arguments: [text, model, id.uuidString]
                )
            }
            log.info("[UnifiedDatabase] Updated transcription for \(id.uuidString.prefix(8))")
        } catch {
            log.error("[UnifiedDatabase] updateTranscription failed: \(error)")
        }
    }

    /// Mark transcription as failed
    static func markTranscriptionFailed(id: UUID, error: String) {
        do {
            try shared.write { db in
                try db.execute(
                    sql: "UPDATE recordings SET transcriptionStatus = 'failed', transcriptionError = ? WHERE id = ?",
                    arguments: [error, id.uuidString]
                )
            }
        } catch {
            log.error("[UnifiedDatabase] markTranscriptionFailed error: \(error)")
        }
    }

    /// Update metadata for a recording
    static func updateMetadata(id: UUID, metadataJSON: String?) {
        do {
            try shared.write { db in
                try db.execute(
                    sql: "UPDATE recordings SET metadataJSON = ? WHERE id = ?",
                    arguments: [metadataJSON, id.uuidString]
                )
            }
        } catch {
            // busy_timeout (10s) handles SQLite lock contention at the driver level
            // If we still fail after that, log and move on - metadata update is non-critical
            log.error("[UnifiedDatabase] updateMetadata error: \(error)")
        }
    }

    static func appendTextProvenance(id: UUID, segments: [ProvenanceSegment]) {
        guard !segments.isEmpty else { return }

        do {
            try shared.write { db in
                let existingJSON: String? = try String.fetchOne(
                    db,
                    sql: "SELECT assetsJSON FROM recordings WHERE id = ?",
                    arguments: [id.uuidString]
                )

                var assets = TalkieObjectAssets.from(json: existingJSON) ?? TalkieObjectAssets(
                    screenshots: [],
                    clips: [],
                    attachments: []
                )
                var existingProvenance = assets.textProvenance ?? []
                existingProvenance.append(contentsOf: segments)
                assets.textProvenance = existingProvenance

                try db.execute(
                    sql: "UPDATE recordings SET assetsJSON = ? WHERE id = ?",
                    arguments: [assets.toJSON(), id.uuidString]
                )
            }

            log.info("[UnifiedDatabase] Appended \(segments.count) provenance segment(s) to \(id.uuidString.prefix(8))")
        } catch {
            log.error("[UnifiedDatabase] appendTextProvenance error: \(error)")
        }
    }

    /// Merge enriched metadata into an existing record, preserving keys
    /// already present (like refinement info set during initial store).
    static func mergeMetadata(id: UUID, enrichedJSON: String?) {
        guard let enrichedJSON else {
            return
        }
        do {
            try shared.write { db in
                // Read existing metadata
                let existingJSON: String? = try String.fetchOne(
                    db,
                    sql: "SELECT metadataJSON FROM recordings WHERE id = ?",
                    arguments: [id.uuidString]
                )

                let merged: String
                if let existingJSON,
                   let existingData = existingJSON.data(using: .utf8),
                   var existingDict = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any],
                   let enrichedData = enrichedJSON.data(using: .utf8),
                   let enrichedDict = try? JSONSerialization.jsonObject(with: enrichedData) as? [String: Any] {
                    // Enriched values win, but preserve keys not in enriched (like refinement)
                    for (key, value) in enrichedDict {
                        existingDict[key] = value
                    }
                    let data = try JSONSerialization.data(withJSONObject: existingDict)
                    merged = String(data: data, encoding: .utf8) ?? enrichedJSON
                } else {
                    merged = enrichedJSON
                }

                try db.execute(
                    sql: "UPDATE recordings SET metadataJSON = ? WHERE id = ?",
                    arguments: [merged, id.uuidString]
                )
            }
        } catch {
            log.error("[UnifiedDatabase] mergeMetadata error: \(error)")
        }
    }

    /// Merge additional screenshots into an existing dictation record's assetsJSON.
    /// Combines with any existing screenshots (e.g., from during-recording captures).
    /// Returns true if the record was found and updated.
    @discardableResult
    static func mergeScreenshots(id: UUID, screenshotsJSON newJSON: String) -> Bool {
        do {
            var updated = false
            try shared.write { db in
                // Fetch existing assetsJSON
                let existingAssets: String? = try String.fetchOne(
                    db,
                    sql: "SELECT assetsJSON FROM recordings WHERE id = ?",
                    arguments: [id.uuidString]
                )

                // Parse existing assets or start fresh
                var assetsDict: [String: Any] = [:]
                if let existingJSON = existingAssets,
                   let data = existingJSON.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    assetsDict = parsed
                }

                // Merge screenshots
                let newArray: [[String: Any]]
                if let newData = newJSON.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: newData) as? [[String: Any]] {
                    newArray = parsed
                } else {
                    newArray = []
                }

                if var existingScreenshots = assetsDict["screenshots"] as? [[String: Any]], !existingScreenshots.isEmpty {
                    existingScreenshots.append(contentsOf: newArray)
                    assetsDict["screenshots"] = existingScreenshots
                } else {
                    assetsDict["screenshots"] = newArray
                }

                let mergedData = try JSONSerialization.data(withJSONObject: assetsDict)
                let mergedStr = String(data: mergedData, encoding: .utf8)

                try db.execute(
                    sql: "UPDATE recordings SET assetsJSON = ? WHERE id = ?",
                    arguments: [mergedStr, id.uuidString]
                )
                updated = db.changesCount > 0
            }
            if updated {
                log.info("[UnifiedDatabase] Merged screenshots for \(id.uuidString.prefix(8))")
            } else {
                log.warning("[UnifiedDatabase] mergeScreenshots: record not found \(id.uuidString.prefix(8))")
            }
            return updated
        } catch {
            log.error("[UnifiedDatabase] mergeScreenshots failed: \(error)")
            return false
        }
    }

    /// Fetch recent dictations (excludes failed/empty transcriptions)
    static func recentDictations(limit: Int = 100) -> [LiveRecording] {
        do {
            return try shared.read { db in
                let results = try LiveRecording
                    .filter(Column("type") == "dictation")
                    .filter(Column("text") != "")
                    .order(Column("createdAt").desc)
                    .limit(limit)
                    .fetchAll(db)
                return results
            }
        } catch {
            log.error("[UnifiedDatabase] recentDictations failed: \(error)")
            return []
        }
    }

    /// Count dictations
    static func countDictations() -> Int {
        (try? shared.read { db in
            try LiveRecording
                .filter(Column("type") == "dictation")
                .fetchCount(db)
        }) ?? 0
    }

    /// Delete a recording by ID
    static func delete(id: UUID) {
        // Look up the actual audio filename first
        let audioFilename: String? = try? shared.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT audioFilename FROM recordings WHERE id = ?",
                arguments: [id.uuidString]
            )
        }

        // Delete audio file if it exists
        if let filename = audioFilename {
            AudioStorage.delete(filename: filename)
        }

        // Delete record
        try? shared.write { db in
            try db.execute(
                sql: "DELETE FROM recordings WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    /// Prune old dictations (TTL cleanup)
    static func pruneDictations(olderThanHours hours: Int) {
        guard hours > 0 else { return }

        let cutoff = Date().addingTimeInterval(-Double(hours) * 60 * 60)

        // Get IDs and audio filenames to delete
        let toDelete: [(id: String, audioFilename: String?)] = (try? shared.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, audioFilename FROM recordings
                    WHERE type = 'dictation' AND createdAt < ?
                    """,
                arguments: [cutoff]
            ).map { row in
                (id: row["id"] as String, audioFilename: row["audioFilename"] as String?)
            }
        }) ?? []

        // Delete audio files
        for item in toDelete {
            if let filename = item.audioFilename {
                AudioStorage.delete(filename: filename)
            }
        }

        // Delete records
        try? shared.write { db in
            try db.execute(
                sql: "DELETE FROM recordings WHERE type = 'dictation' AND createdAt < ?",
                arguments: [cutoff]
            )
        }

        if !toDelete.isEmpty {
            log.info("[UnifiedDatabase] Pruned \(toDelete.count) old dictations")
        }
    }

    /// Store a new segment recording (child of a note)
    @discardableResult
    static func storeSegment(
        text: String,
        duration: Double,
        audioFilename: String?,
        transcriptionModel: String?,
        parentId: UUID,
        segmentIndex: Int
    ) -> UUID? {
        var recording = LiveRecording(
            text: text,
            duration: duration,
            audioFilename: audioFilename,
            transcriptionModel: transcriptionModel
        )
        recording.type = "segment"
        recording.source = "mac"
        recording.sourceDeviceId = nil
        recording.parentId = parentId.uuidString
        recording.segmentIndex = segmentIndex
        return store(recording)
    }

    /// Fetch segments for a parent note, ordered by segmentIndex
    static func fetchSegments(parentId: UUID) -> [LiveRecording] {
        (try? shared.read { db in
            try LiveRecording
                .filter(Column("type") == "segment")
                .filter(Column("parentId") == parentId.uuidString)
                .order(Column("segmentIndex").asc)
                .fetchAll(db)
        }) ?? []
    }

    /// Count segments for a parent note
    static func countSegments(parentId: UUID) -> Int {
        (try? shared.read { db in
            try LiveRecording
                .filter(Column("type") == "segment")
                .filter(Column("parentId") == parentId.uuidString)
                .fetchCount(db)
        }) ?? 0
    }

    /// Delete segments for a parent note (with audio file cleanup)
    static func deleteSegments(parentId: UUID) {
        // Get audio filenames first
        let audioFilenames: [String] = (try? shared.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT audioFilename FROM recordings
                    WHERE type = 'segment' AND parentId = ? AND audioFilename IS NOT NULL
                    """,
                arguments: [parentId.uuidString]
            )
        }) ?? []

        // Delete audio files
        for filename in audioFilenames {
            AudioStorage.delete(filename: filename)
        }

        // Delete records
        try? shared.write { db in
            try db.execute(
                sql: "DELETE FROM recordings WHERE type = 'segment' AND parentId = ?",
                arguments: [parentId.uuidString]
            )
        }

        if !audioFilenames.isEmpty {
            log.info("[UnifiedDatabase] Deleted \(audioFilenames.count) segments for parent \(parentId.uuidString.prefix(8))")
        }
    }

    /// Delete orphaned segments (segments whose parent note/memo no longer exists)
    static func pruneOrphanedSegments() {
        // Get audio filenames for orphaned segments
        let orphanedAudio: [String] = (try? shared.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT audioFilename FROM recordings
                    WHERE type = 'segment'
                      AND audioFilename IS NOT NULL
                      AND parentId NOT IN (
                          SELECT id FROM recordings WHERE type IN ('note', 'memo')
                      )
                    """
            )
        }) ?? []

        // Delete audio files
        for filename in orphanedAudio {
            AudioStorage.delete(filename: filename)
        }

        // Delete orphaned records
        let count: Int = (try? shared.write { db in
            try db.execute(
                sql: """
                    DELETE FROM recordings WHERE type = 'segment'
                      AND parentId NOT IN (
                          SELECT id FROM recordings WHERE type IN ('note', 'memo')
                      )
                    """
            )
            return db.changesCount
        }) ?? 0

        if count > 0 {
            log.info("[UnifiedDatabase] Pruned \(count) orphaned segments")
        }
    }

    /// Delete all dictations (clear history)
    static func deleteAllDictations() {
        // Get all audio filenames for cleanup
        let audioFilenames: [String] = (try? shared.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT audioFilename FROM recordings WHERE type = 'dictation' AND audioFilename IS NOT NULL"
            )
        }) ?? []

        // Delete audio files
        for filename in audioFilenames {
            AudioStorage.delete(filename: filename)
        }

        // Count before delete for logging
        let count = countDictations()

        // Delete records
        try? shared.write { db in
            try db.execute(sql: "DELETE FROM recordings WHERE type = 'dictation'")
        }

        log.info("[UnifiedDatabase] Deleted all \(count) dictations")
    }

    /// Search dictations by text
    static func searchDictations(query: String, limit: Int = 100) -> [LiveRecording] {
        (try? shared.read { db in
            try LiveRecording
                .filter(Column("type") == "dictation")
                .filter(Column("text").like("%\(query)%"))
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []
    }

    /// Fetch a single recording by ID
    static func fetch(id: UUID) -> LiveRecording? {
        try? shared.read { db in
            try LiveRecording
                .filter(Column("id") == id.uuidString)
                .fetchOne(db)
        }
    }
}

// MARK: - Metadata Helpers

extension LiveRecording {
    /// Parsed metadata structure for queue/promotion fields
    struct ParsedMetadata {
        var app: AppInfo?
        var performance: PerformanceInfo?
        var queue: QueueInfo?
        var promotion: PromotionInfo?
        var context: ContextInfo?
        var routing: RoutingInfo?

        struct AppInfo {
            var bundleId: String?
            var name: String?
            var windowTitle: String?
        }

        struct PerformanceInfo {
            var engineMs: Int?
            var endToEndMs: Int?
            var inAppMs: Int?
            var sessionId: String?
        }

        struct QueueInfo {
            var createdInTalkieView: Bool = false
            var pasteTimestamp: Double?
        }

        struct PromotionInfo {
            var status: String = "none"
            var memoId: String?
            var commandId: String?
        }

        struct ContextInfo {
            var browserURL: String?
            var documentURL: String?
            var terminalWorkingDir: String?
        }

        struct RoutingInfo {
            var mode: String?
        }

        init() {}

        init(from json: String?) {
            guard let json = json,
                  let data = json.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            // Parse app info
            if let appDict = dict["app"] as? [String: Any] {
                var appInfo = AppInfo()
                appInfo.bundleId = appDict["bundleId"] as? String
                appInfo.name = appDict["name"] as? String
                appInfo.windowTitle = appDict["windowTitle"] as? String
                self.app = appInfo
            }

            // Parse performance info
            if let perfDict = dict["performance"] as? [String: Any] {
                var perfInfo = PerformanceInfo()
                perfInfo.engineMs = perfDict["engineMs"] as? Int
                perfInfo.endToEndMs = perfDict["endToEndMs"] as? Int
                perfInfo.inAppMs = perfDict["inAppMs"] as? Int
                perfInfo.sessionId = perfDict["sessionId"] as? String
                self.performance = perfInfo
            }

            // Parse queue info
            if let queueDict = dict["queue"] as? [String: Any] {
                var queueInfo = QueueInfo()
                queueInfo.createdInTalkieView = (queueDict["createdInTalkieView"] as? Bool) ?? false
                queueInfo.pasteTimestamp = queueDict["pasteTimestamp"] as? Double
                self.queue = queueInfo
            }

            // Parse promotion info
            if let promoDict = dict["promotion"] as? [String: Any] {
                var promoInfo = PromotionInfo()
                promoInfo.status = (promoDict["status"] as? String) ?? "none"
                promoInfo.memoId = promoDict["memoId"] as? String
                promoInfo.commandId = promoDict["commandId"] as? String
                self.promotion = promoInfo
            }

            // Parse context info
            if let contextDict = dict["context"] as? [String: Any] {
                var contextInfo = ContextInfo()
                contextInfo.browserURL = contextDict["browserURL"] as? String
                contextInfo.documentURL = contextDict["documentURL"] as? String
                contextInfo.terminalWorkingDir = contextDict["terminalWorkingDir"] as? String
                self.context = contextInfo
            }

            // Parse routing info
            if let routingDict = dict["routing"] as? [String: Any] {
                var routingInfo = RoutingInfo()
                routingInfo.mode = routingDict["mode"] as? String
                self.routing = routingInfo
            }
        }

        /// Convert back to JSON string
        func toJSON() -> String? {
            var dict: [String: Any] = [:]

            if let app = app {
                var appDict: [String: String] = [:]
                if let bundleId = app.bundleId { appDict["bundleId"] = bundleId }
                if let name = app.name { appDict["name"] = name }
                if let windowTitle = app.windowTitle { appDict["windowTitle"] = windowTitle }
                if !appDict.isEmpty { dict["app"] = appDict }
            }

            if let perf = performance {
                var perfDict: [String: Any] = [:]
                if let ms = perf.engineMs { perfDict["engineMs"] = ms }
                if let ms = perf.endToEndMs { perfDict["endToEndMs"] = ms }
                if let ms = perf.inAppMs { perfDict["inAppMs"] = ms }
                if let sid = perf.sessionId { perfDict["sessionId"] = sid }
                if !perfDict.isEmpty { dict["performance"] = perfDict }
            }

            if let queue = queue {
                var queueDict: [String: Any] = [:]
                queueDict["createdInTalkieView"] = queue.createdInTalkieView
                if let ts = queue.pasteTimestamp { queueDict["pasteTimestamp"] = ts }
                dict["queue"] = queueDict
            }

            if let promo = promotion {
                var promoDict: [String: Any] = [:]
                promoDict["status"] = promo.status
                if let memoId = promo.memoId { promoDict["memoId"] = memoId }
                if let commandId = promo.commandId { promoDict["commandId"] = commandId }
                dict["promotion"] = promoDict
            }

            if let context = context {
                var contextDict: [String: String] = [:]
                if let url = context.browserURL { contextDict["browserURL"] = url }
                if let url = context.documentURL { contextDict["documentURL"] = url }
                if let dir = context.terminalWorkingDir { contextDict["terminalWorkingDir"] = dir }
                if !contextDict.isEmpty { dict["context"] = contextDict }
            }

            if let routing = routing {
                var routingDict: [String: String] = [:]
                if let mode = routing.mode { routingDict["mode"] = mode }
                if !routingDict.isEmpty { dict["routing"] = routingDict }
            }

            guard !dict.isEmpty else { return nil }

            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return nil
        }
    }

    /// Parse metadata from JSON
    var parsedMetadata: ParsedMetadata {
        ParsedMetadata(from: metadataJSON)
    }

    /// App bundle ID from metadata
    var appBundleID: String? {
        parsedMetadata.app?.bundleId
    }

    /// Whether this recording was created in Talkie view
    var createdInTalkieView: Bool {
        parsedMetadata.queue?.createdInTalkieView ?? false
    }

    /// Paste timestamp from metadata
    var pasteTimestamp: Date? {
        guard let ts = parsedMetadata.queue?.pasteTimestamp else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    /// Promotion status from metadata
    var promotionStatus: String {
        parsedMetadata.promotion?.status ?? "none"
    }

    /// Talkie memo ID from metadata
    var talkieMemoID: String? {
        parsedMetadata.promotion?.memoId
    }

    /// Command ID from metadata
    var commandID: String? {
        parsedMetadata.promotion?.commandId
    }

    /// Whether this recording is queued (created in Talkie, never pasted, not promoted)
    var isQueued: Bool {
        createdInTalkieView && pasteTimestamp == nil && promotionStatus == "none"
    }

    /// Whether this recording needs action (not promoted, not ignored)
    var needsAction: Bool {
        promotionStatus == "none"
    }

    /// Whether this recording can be retried
    var canRetryTranscription: Bool {
        (transcriptionStatus == "failed" || transcriptionStatus == "pending") && hasAudio
    }
}

// MARK: - Queue Methods

extension UnifiedDatabase {

    /// Fetch queued recordings (created in Talkie view, not pasted, not promoted)
    /// Uses SQL-based filtering for efficiency
    static func fetchQueued() -> [LiveRecording] {
        do {
            return try shared.read { db in
                try LiveRecording
                    .filter(Column("type") == "dictation")
                    .filter(sql: """
                        json_extract(metadataJSON, '$.queue.createdInTalkieView') = 1
                        AND json_extract(metadataJSON, '$.queue.pasteTimestamp') IS NULL
                        AND (json_extract(metadataJSON, '$.promotion.status') = 'none'
                             OR json_extract(metadataJSON, '$.promotion.status') IS NULL)
                    """)
                    .order(Column("createdAt").desc)
                    .limit(100)
                    .fetchAll(db)
            }
        } catch {
            log.error("[UnifiedDatabase] fetchQueued failed: \(error)")
            return []
        }
    }

    /// Count queued recordings efficiently using SQL
    static func countQueued() -> Int {
        do {
            return try shared.read { db in
                try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM recordings
                    WHERE type = 'dictation'
                      AND json_extract(metadataJSON, '$.queue.createdInTalkieView') = 1
                      AND json_extract(metadataJSON, '$.queue.pasteTimestamp') IS NULL
                      AND (json_extract(metadataJSON, '$.promotion.status') = 'none'
                           OR json_extract(metadataJSON, '$.promotion.status') IS NULL)
                """) ?? 0
            }
        } catch {
            log.error("[UnifiedDatabase] countQueued failed: \(error)")
            return 0
        }
    }

    /// Mark a recording as pasted
    static func markPasted(id: UUID) {
        do {
            try shared.write { db in
                // Fetch current metadataJSON
                let currentJSON: String? = try String.fetchOne(
                    db,
                    sql: "SELECT metadataJSON FROM recordings WHERE id = ?",
                    arguments: [id.uuidString]
                )

                // Parse and update
                var metadata = LiveRecording.ParsedMetadata(from: currentJSON)
                if metadata.queue == nil {
                    metadata.queue = .init()
                }
                metadata.queue?.pasteTimestamp = Date().timeIntervalSince1970

                // Write back
                try db.execute(
                    sql: "UPDATE recordings SET metadataJSON = ? WHERE id = ?",
                    arguments: [metadata.toJSON(), id.uuidString]
                )
            }
            log.info("[UnifiedDatabase] Marked recording \(id.uuidString.prefix(8)) as pasted")
        } catch {
            log.error("[UnifiedDatabase] markPasted failed: \(error)")
        }
    }
}

// MARK: - Promotion Methods

extension UnifiedDatabase {

    /// Mark recording as promoted to memo
    static func markAsMemo(id: UUID, talkieMemoID: String) {
        updatePromotionStatus(id: id, status: "memo", memoId: talkieMemoID, commandId: nil)
    }

    /// Mark recording as promoted to command
    static func markAsCommand(id: UUID, commandID: String) {
        updatePromotionStatus(id: id, status: "command", memoId: nil, commandId: commandID)
    }

    /// Mark recording as ignored
    static func markAsIgnored(id: UUID) {
        updatePromotionStatus(id: id, status: "ignored", memoId: nil, commandId: nil)
    }

    /// Reset promotion status
    static func resetPromotion(id: UUID) {
        updatePromotionStatus(id: id, status: "none", memoId: nil, commandId: nil)
    }

    /// Internal helper to update promotion status in metadataJSON
    private static func updatePromotionStatus(id: UUID, status: String, memoId: String?, commandId: String?) {
        do {
            try shared.write { db in
                // Fetch current metadataJSON
                let currentJSON: String? = try String.fetchOne(
                    db,
                    sql: "SELECT metadataJSON FROM recordings WHERE id = ?",
                    arguments: [id.uuidString]
                )

                // Parse and update
                var metadata = LiveRecording.ParsedMetadata(from: currentJSON)
                if metadata.promotion == nil {
                    metadata.promotion = .init()
                }
                metadata.promotion?.status = status
                metadata.promotion?.memoId = memoId
                metadata.promotion?.commandId = commandId

                // Write back
                try db.execute(
                    sql: "UPDATE recordings SET metadataJSON = ? WHERE id = ?",
                    arguments: [metadata.toJSON(), id.uuidString]
                )
            }
            log.info("[UnifiedDatabase] Updated promotion status to '\(status)' for \(id.uuidString.prefix(8))")
        } catch {
            log.error("[UnifiedDatabase] updatePromotionStatus failed: \(error)")
        }
    }
}

// MARK: - Transcription Retry Methods

extension UnifiedDatabase {

    /// Fetch recordings that need transcription retry
    static func fetchNeedsRetry() -> [LiveRecording] {
        (try? shared.read { db in
            try LiveRecording
                .filter(Column("type") == "dictation")
                .filter(
                    Column("transcriptionStatus") == "failed" ||
                    Column("transcriptionStatus") == "pending"
                )
                .filter(Column("audioFilename") != nil)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }) ?? []
    }

    /// Count recordings that need transcription retry
    static func countNeedsRetry() -> Int {
        (try? shared.read { db in
            try LiveRecording
                .filter(Column("type") == "dictation")
                .filter(
                    Column("transcriptionStatus") == "failed" ||
                    Column("transcriptionStatus") == "pending"
                )
                .filter(Column("audioFilename") != nil)
                .fetchCount(db)
        }) ?? 0
    }

    /// Mark transcription as successful with updated text and performance data
    static func markTranscriptionSuccess(id: UUID, text: String, perfEngineMs: Int?, model: String?) {
        do {
            try shared.write { db in
                // Update basic transcription fields
                try db.execute(
                    sql: """
                        UPDATE recordings SET
                            text = ?,
                            transcriptionModel = ?,
                            transcriptionStatus = 'success',
                            transcriptionError = NULL
                        WHERE id = ?
                        """,
                    arguments: [text, model, id.uuidString]
                )

                // Update performance data in metadataJSON if provided
                if let perfEngineMs = perfEngineMs {
                    let currentJSON: String? = try String.fetchOne(
                        db,
                        sql: "SELECT metadataJSON FROM recordings WHERE id = ?",
                        arguments: [id.uuidString]
                    )

                    var metadata = LiveRecording.ParsedMetadata(from: currentJSON)
                    if metadata.performance == nil {
                        metadata.performance = .init()
                    }
                    metadata.performance?.engineMs = perfEngineMs

                    try db.execute(
                        sql: "UPDATE recordings SET metadataJSON = ? WHERE id = ?",
                        arguments: [metadata.toJSON(), id.uuidString]
                    )
                }
            }
            log.info("[UnifiedDatabase] Marked transcription success for \(id.uuidString.prefix(8))")
        } catch {
            log.error("[UnifiedDatabase] markTranscriptionSuccess failed: \(error)")
        }
    }
}

// MARK: - Filtered Queries

extension UnifiedDatabase {

    /// Fetch all dictations ordered by creation date (newest first)
    static func all() -> [LiveRecording] {
        recentDictations(limit: Int.max)
    }

    /// Fetch dictations by app bundle ID
    /// Since appBundleID is in metadataJSON, we fetch all and filter in memory
    static func byApp(_ bundleID: String) -> [LiveRecording] {
        let all = recentDictations(limit: 10000)
        return all.filter { $0.appBundleID == bundleID }
    }

    /// Fetch recordings that need action (promotion status = none)
    static func needsAction(limit: Int = 100) -> [LiveRecording] {
        let all = recentDictations(limit: limit * 2)  // Fetch extra to account for filtering
        return Array(all.filter { $0.needsAction }.prefix(limit))
    }

    /// Fetch recordings by promotion status
    static func byStatus(_ status: String, limit: Int = 100) -> [LiveRecording] {
        let all = recentDictations(limit: limit * 2)
        return Array(all.filter { $0.promotionStatus == status }.prefix(limit))
    }

    /// Count recordings that need action
    static func countNeedsAction() -> Int {
        let all = recentDictations(limit: 10000)
        return all.filter { $0.needsAction }.count
    }
}
