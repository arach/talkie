//
//  CloudKitDirectSyncEngine.swift
//  TalkieSync
//
//  Direct CloudKit -> GRDB sync path.
//  Avoids NSPersistentCloudKitContainer startup dependency in syncNow hot path.
//

import Foundation
import CloudKit
import GRDB
import CryptoKit
import TalkieKit

private let log = Log(.sync)

final class CloudKitDirectSyncEngine {
    static let shared = CloudKitDirectSyncEngine()
    typealias ProgressHandler = @Sendable (_ progress: Double, _ message: String) -> Void

    struct SyncOptions {
        var limit: Int?
        var since: Date?

        static let all = SyncOptions()
    }

    struct SyncStats {
        let inserted: Int
        let updated: Int
        let deleted: Int
        let skipped: Int
        /// Count of remote records that were parseable and considered for upsert.
        let remoteCount: Int
        let localCount: Int
        let fetchTimeMs: Double
        let totalTimeMs: Double
        let schema: String
        let latestMemoTrace: String
    }

    private enum Schema {
        case coreDataMirrored
        case legacyCustom

        var recordType: String {
            switch self {
            case .coreDataMirrored:
                return "CD_VoiceMemo"
            case .legacyCustom:
                return "VoiceMemo"
            }
        }

        var zoneID: CKRecordZone.ID {
            switch self {
            case .coreDataMirrored:
                return CKRecordZone.ID(
                    zoneName: "com.apple.coredata.cloudkit.zone",
                    ownerName: CKCurrentUserDefaultName
                )
            case .legacyCustom:
                return CKRecordZone.ID(
                    zoneName: "TalkieMemos",
                    ownerName: CKCurrentUserDefaultName
                )
            }
        }

        var createdAtField: String {
            switch self {
            case .coreDataMirrored:
                return "CD_createdAt"
            case .legacyCustom:
                return "createdAt"
            }
        }

        var lastModifiedField: String {
            switch self {
            case .coreDataMirrored:
                return "CD_lastModified"
            case .legacyCustom:
                return "lastModified"
            }
        }

        var desiredKeys: [String] {
            switch self {
            case .coreDataMirrored:
                return [
                    "CD_id", "CD_createdAt", "CD_lastModified",
                    "CD_title", "CD_duration", "CD_sortOrder",
                    "CD_transcription", "CD_notes", "CD_summary", "CD_tasks", "CD_reminders",
                    "CD_fileURL", "CD_waveformData",
                    "CD_isTranscribing", "CD_isProcessingSummary", "CD_isProcessingTasks",
                    "CD_isProcessingReminders", "CD_autoProcessed",
                    "CD_originDeviceId", "CD_macReceivedAt", "CD_cloudSyncedAt",
                    "CD_pendingWorkflowIds", "CD_deletedAt"
                ]
            case .legacyCustom:
                return [
                    "id", "createdAt", "lastModified",
                    "title", "duration", "sortOrder",
                    "transcription", "notes", "summary", "tasks", "reminders",
                    "fileURL", "waveformData",
                    "isTranscribing", "isProcessingSummary", "isProcessingTasks",
                    "isProcessingReminders", "autoProcessed",
                    "originDeviceId", "macReceivedAt", "cloudSyncedAt",
                    "pendingWorkflowIds", "deletedAt"
                ]
            }
        }
    }

    private struct RemoteMemoMetadata {
        let id: UUID
        let createdAt: Date
        let lastModified: Date
        let originDeviceId: String?
    }

    private struct ParsedRemoteMemo {
        let recordID: CKRecord.ID
        let metadata: RemoteMemoMetadata
        var memo: MemoRecord
    }

    private struct RemoteFetchResult {
        let schema: Schema
        let records: [CKRecord]
        let hadPartialFailures: Bool
        let isAuthoritative: Bool
    }

    private struct LocalMemoState {
        let lastModified: Date
        let deletedAt: Date?
        let audioFilePath: String?
        let contentSignature: String
    }

    private struct WriteResult: Sendable {
        let inserted: Int
        let updated: Int
        let deleted: Int
        let skippedUnchanged: Int
        let updatedDueToRemoteNewer: Int
        let updatedDueToContentChange: Int
        let updatedDueToDeletedState: Int
        let updatedDueToAudioPath: Int
        let localCount: Int
    }

    private let containerIdentifier = TalkieEnvironment.current.cloudKitContainerIdentifier
    private let stateLock = NSLock()

    private let uuidRegex = try? NSRegularExpression(
        pattern: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
    )

    private var grdbPool: DatabasePool?
    private var lastRemoteMemoCountValue: Int = -1
    private var lastLatestMemoTraceValue: String = "none"
    private var audioDirectoryURL: URL {
        SyncConfig.folderURL.appendingPathComponent("Audio", isDirectory: true)
    }

    private init() {
        setupGRDB()
    }

    var lastRemoteMemoCount: Int {
        stateLock.withLock { lastRemoteMemoCountValue }
    }

    var lastLatestMemoTrace: String {
        stateLock.withLock { lastLatestMemoTraceValue }
    }

    func ensureReady() -> Bool {
        if grdbPool != nil {
            return true
        }
        setupGRDB()
        return grdbPool != nil
    }

    func checkiCloudAvailability() async -> (available: Bool, error: String?) {
        let container = CKContainer(identifier: containerIdentifier)
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                return (true, nil)
            case .noAccount:
                return (false, "No iCloud account signed in")
            case .restricted:
                return (false, "iCloud is restricted")
            case .couldNotDetermine:
                return (false, "Could not determine iCloud status")
            case .temporarilyUnavailable:
                return (false, "iCloud temporarily unavailable")
            @unknown default:
                return (false, "Unknown iCloud status")
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func syncNow(progress: ProgressHandler? = nil) async throws -> SyncStats {
        try await syncNow(options: .all, progress: progress)
    }

    func syncNow(options: SyncOptions, progress: ProgressHandler? = nil) async throws -> SyncStats {
        guard ensureReady(), let pool = grdbPool else {
            throw SyncProviderError.unknown("GRDB not initialized")
        }

        let startedAt = CFAbsoluteTimeGetCurrent()
        let remoteFetchStartedAt = CFAbsoluteTimeGetCurrent()
        progress?(0.05, "Scanning CloudKit for remote memo changes...")

        let remote = try await fetchRemoteMemos(options: options)
        let fetchTimeMs = (CFAbsoluteTimeGetCurrent() - remoteFetchStartedAt) * 1000

        var latestRemoteCreatedAt: Date = .distantPast
        var latestRemoteTrace = "none"
        var parsedRemoteMemos: [ParsedRemoteMemo] = []
        parsedRemoteMemos.reserveCapacity(remote.records.count)
        var parseSkipped = 0
        let fetchedRemoteCount = remote.records.count

        for record in remote.records {
            guard let metadata = parseMetadata(from: record),
                  let memo = mapMemo(from: record, metadata: metadata) else {
                parseSkipped += 1
                continue
            }

            if metadata.createdAt > latestRemoteCreatedAt {
                latestRemoteCreatedAt = metadata.createdAt
                latestRemoteTrace = formatTrace(
                    id: metadata.id,
                    createdAt: metadata.createdAt,
                    originDeviceId: metadata.originDeviceId
                )
            }

            parsedRemoteMemos.append(
                ParsedRemoteMemo(recordID: record.recordID, metadata: metadata, memo: memo)
            )
        }
        progress?(
            0.22,
            "Remote scan complete: \(fetchedRemoteCount) record(s), " +
            "\(parsedRemoteMemos.count) usable"
        )

        if parseSkipped > 0 {
            log.warning(
                "CloudKit skipped \(parseSkipped) unparseable \(remote.schema.recordType) " +
                "record(s) (fetched: \(fetchedRemoteCount), usable: \(parsedRemoteMemos.count))"
            )
        }

        let existingStates = try await fetchExistingStates(pool: pool)
        let database = CKContainer(identifier: containerIdentifier).privateCloudDatabase

        var hydratedMemos: [MemoRecord] = []
        hydratedMemos.reserveCapacity(parsedRemoteMemos.count)
        var audioHydrationAttempts = 0
        var audioHydrationSuccesses = 0
        let hydrationProgressStep = max(1, parsedRemoteMemos.count / 8)
        for (index, parsed) in parsedRemoteMemos.enumerated() {
            var memo = parsed.memo
            let localAudioPath = existingStates[memo.id]?.audioFilePath

            if shouldHydrateAudio(memo: memo, localAudioPath: localAudioPath) {
                audioHydrationAttempts += 1
                if let hydratedAudioPath = await fetchAndStoreAudioFile(
                    for: parsed.recordID,
                    schema: remote.schema,
                    memoID: memo.id,
                    in: database
                ) {
                    memo.audioFilePath = hydratedAudioPath
                    audioHydrationSuccesses += 1
                }
            }

            hydratedMemos.append(memo)
            if !parsedRemoteMemos.isEmpty,
               (index == 0 || (index + 1) % hydrationProgressStep == 0 || index + 1 == parsedRemoteMemos.count) {
                let progressValue = 0.22 + (Double(index + 1) / Double(parsedRemoteMemos.count)) * 0.56
                progress?(progressValue, "Reconciling memo \(index + 1)/\(parsedRemoteMemos.count)...")
            }
        }
        if audioHydrationAttempts > 0 {
            log.info(
                "Audio hydration attempts: \(audioHydrationAttempts), " +
                "successes: \(audioHydrationSuccesses), " +
                "failures: \(audioHydrationAttempts - audioHydrationSuccesses)"
            )
        }

        let memosToWrite = hydratedMemos
        let remoteIDs = Set(memosToWrite.map(\.id))
        progress?(0.82, "Applying reconciled changes to local database...")
        let isFilteredSync = options.limit != nil || options.since != nil
        let canReconcileMissingRemoteIDs = remote.isAuthoritative && !remote.hadPartialFailures && parseSkipped == 0 && !isFilteredSync
        if !canReconcileMissingRemoteIDs {
            log.warning(
                "Skipping remote-missing deletion reconciliation " +
                "(authoritative: \(remote.isAuthoritative), " +
                "partialFailures: \(remote.hadPartialFailures), parseSkipped: \(parseSkipped))"
            )
        }

        let writeResult: WriteResult = try await pool.write { db in
            var inserted = 0
            var updated = 0
            var skippedUnchanged = 0
            var updatedDueToRemoteNewer = 0
            var updatedDueToContentChange = 0
            var updatedDueToDeletedState = 0
            var updatedDueToAudioPath = 0

            for memo in memosToWrite {
                let externalRefID = memo.id.uuidString.lowercased()
                let remoteSignature = syncSignature(for: memo)
                if let localState = existingStates[memo.id] {
                    let deletedStateChanged = localState.deletedAt != memo.deletedAt
                    let audioPathChanged = memo.audioFilePath != nil && localState.audioFilePath != memo.audioFilePath
                    let contentChanged = localState.contentSignature != remoteSignature

                    if !deletedStateChanged && !audioPathChanged && !contentChanged {
                        skippedUnchanged += 1
                        try? upsertSyncInboxRecord(
                            in: db,
                            provider: "cloudkit",
                            entityType: "voice_memo",
                            externalRefID: externalRefID,
                            remoteModifiedAt: memo.lastModified,
                            canonicalHash: remoteSignature,
                            status: "applied"
                        )
                        continue
                    }

                    if contentChanged && !deletedStateChanged && !audioPathChanged {
                        updatedDueToContentChange += 1
                        if memo.lastModified > localState.lastModified {
                            updatedDueToRemoteNewer += 1
                        }
                    }

                    if deletedStateChanged {
                        updatedDueToDeletedState += 1
                    }
                    if audioPathChanged {
                        updatedDueToAudioPath += 1
                    }
                }

                try memo.syncUpsert(in: db)
                if existingStates[memo.id] == nil {
                    inserted += 1
                } else {
                    updated += 1
                }
                try? upsertSyncInboxRecord(
                    in: db,
                    provider: "cloudkit",
                    entityType: "voice_memo",
                    externalRefID: externalRefID,
                    remoteModifiedAt: memo.lastModified,
                    canonicalHash: remoteSignature,
                    status: "applied"
                )
            }

            var deleted = 0
            if canReconcileMissingRemoteIDs {
                deleted = try reconcileMissingRemoteMemos(
                    in: db,
                    remoteIDs: remoteIDs,
                    deletedAt: Date()
                )
            }

            let localCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM voice_memos WHERE deletedAt IS NULL"
            ) ?? 0
            return WriteResult(
                inserted: inserted,
                updated: updated,
                deleted: deleted,
                skippedUnchanged: skippedUnchanged,
                updatedDueToRemoteNewer: updatedDueToRemoteNewer,
                updatedDueToContentChange: updatedDueToContentChange,
                updatedDueToDeletedState: updatedDueToDeletedState,
                updatedDueToAudioPath: updatedDueToAudioPath,
                localCount: localCount
            )
        }

        if writeResult.updated > 0 {
            log.info(
                "Write diagnostics: updated=\(writeResult.updated) " +
                "[remoteNewer=\(writeResult.updatedDueToRemoteNewer), " +
                "content=\(writeResult.updatedDueToContentChange), " +
                "deletedState=\(writeResult.updatedDueToDeletedState), " +
                "audioPath=\(writeResult.updatedDueToAudioPath)]"
            )
        }
        progress?(0.95, "Finalizing sync...")

        let totalTimeMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        let stats = SyncStats(
            inserted: writeResult.inserted,
            updated: writeResult.updated,
            deleted: writeResult.deleted,
            skipped: writeResult.skippedUnchanged + parseSkipped,
            remoteCount: memosToWrite.filter({ $0.deletedAt == nil }).count,
            localCount: writeResult.localCount,
            fetchTimeMs: fetchTimeMs,
            totalTimeMs: totalTimeMs,
            schema: remote.schema.recordType,
            latestMemoTrace: latestRemoteTrace
        )

        stateLock.withLock {
            lastRemoteMemoCountValue = stats.remoteCount
            lastLatestMemoTraceValue = stats.latestMemoTrace
        }
        progress?(1.0, "Sync finalized")

        return stats
    }

    /// Fetch audio for a specific memo from CloudKit (targeted, not a full sync).
    func fetchAudioForMemo(memoID: UUID) async -> (success: Bool, error: String?) {
        guard ensureReady(), let pool = grdbPool else {
            return (false, "GRDB not initialized")
        }

        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase
        let schema = Schema.coreDataMirrored

        // Query for the specific record by scanning the zone.
        // CD_id is stored as binary UUID data, so we fetch all records and match locally.
        let query = CKQuery(recordType: schema.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: schema.createdAtField, ascending: false)]

        do {
            var targetRecordID: CKRecord.ID?

            // Page through results to find the matching record
            var cursor: CKQueryOperation.Cursor?
            repeat {
                let pageResult: (
                    matchResults: [(CKRecord.ID, Result<CKRecord, Error>)],
                    queryCursor: CKQueryOperation.Cursor?
                )

                if let cursor {
                    pageResult = try await database.records(
                        continuingMatchFrom: cursor,
                        desiredKeys: ["CD_id"]
                    )
                } else {
                    pageResult = try await database.records(
                        matching: query,
                        inZoneWith: schema.zoneID,
                        desiredKeys: ["CD_id"],
                        resultsLimit: 200
                    )
                }

                for (recordID, result) in pageResult.matchResults {
                    guard case .success(let record) = result else { continue }
                    if let recordUUID = cloudUUID(from: record["CD_id"]),
                       recordUUID == memoID {
                        targetRecordID = recordID
                        break
                    }
                }

                if targetRecordID != nil { break }
                cursor = pageResult.queryCursor
            } while cursor != nil

            guard let targetRecordID else {
                return (false, "Memo not found in CloudKit")
            }

            // Fetch audio using existing helper
            guard let filename = await fetchAndStoreAudioFile(
                for: targetRecordID,
                schema: schema,
                memoID: memoID,
                in: database
            ) else {
                return (false, "No audio data in CloudKit record")
            }

            // Update GRDB
            try await pool.write { db in
                try db.execute(
                    sql: "UPDATE voice_memos SET audioFilePath = ? WHERE id = ?",
                    arguments: [filename, memoID.uuidString]
                )
            }

            log.info("Fetched audio for memo \(memoID): \(filename)")
            return (true, nil)
        } catch {
            log.error("fetchAudioForMemo failed for \(memoID): \(error.localizedDescription)")
            return (false, error.localizedDescription)
        }
    }

    private func reconcileMissingRemoteMemos(
        in db: Database,
        remoteIDs: Set<UUID>,
        deletedAt: Date
    ) throws -> Int {
        let localCloudBackedIDs = try UUID.fetchAll(
            db,
            sql: """
                SELECT id
                FROM voice_memos
                WHERE deletedAt IS NULL
                  AND cloudSyncedAt IS NOT NULL
                """
        )

        var deleted = 0
        for localID in localCloudBackedIDs where !remoteIDs.contains(localID) {
            try db.execute(
                sql: """
                    UPDATE voice_memos
                    SET deletedAt = ?, lastModified = ?
                    WHERE id = ? AND deletedAt IS NULL
                    """,
                arguments: [deletedAt, deletedAt, localID]
            )
            if db.changesCount > 0 {
                deleted += db.changesCount
            }
        }

        return deleted
    }

    private func setupGRDB() {
        do {
            try FileManager.default.createDirectory(
                at: SyncConfig.folderURL,
                withIntermediateDirectories: true
            )

            var config = Configuration()
            config.busyMode = .timeout(5.0)
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA journal_mode = WAL")
            }

            let pool = try DatabasePool(path: SyncConfig.grdbURL.path, configuration: config)
            try pool.write { db in
                try ensureVoiceMemoSchema(in: db)
                try ensureSyncInboxSchema(in: db)
                try ensureRecordingsExternalReferenceColumns(in: db)
            }
            grdbPool = pool
            log.info("CloudKitDirectSyncEngine GRDB ready at \(SyncConfig.grdbURL.path)")
        } catch {
            grdbPool = nil
            log.error("CloudKitDirectSyncEngine failed to open GRDB: \(error.localizedDescription)")
        }
    }

    private func ensureVoiceMemoSchema(in db: Database) throws {
        try db.create(table: "voice_memos", ifNotExists: true) { t in
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
            t.column("deletedAt", .datetime)
            t.column("revisionHistoryJSON", .text)
        }

        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_memos_created_at ON voice_memos(createdAt)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_memos_title ON voice_memos(title)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_memos_duration ON voice_memos(duration)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_memos_deleted_at ON voice_memos(deletedAt)")
        try ensureMemoChangeHistorySchema(in: db)
    }

    private func ensureSyncInboxSchema(in db: Database) throws {
        try db.create(table: "sync_inbox_records", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("provider", .text).notNull()
            t.column("entityType", .text).notNull()
            t.column("externalRefID", .text).notNull()
            t.column("remoteModifiedAt", .datetime)
            t.column("canonicalHash", .text)
            t.column("payloadJSON", .text)
            t.column("status", .text).notNull().defaults(to: "pending")
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
    }

    private func upsertSyncInboxRecord(
        in db: Database,
        provider: String,
        entityType: String,
        externalRefID: String,
        remoteModifiedAt: Date?,
        canonicalHash: String?,
        status: String
    ) throws {
        let now = Date()
        try db.execute(
            sql: """
                INSERT INTO sync_inbox_records (
                    id, provider, entityType, externalRefID,
                    remoteModifiedAt, canonicalHash, status,
                    firstSeenAt, lastSeenAt, appliedAt, attemptCount
                ) VALUES (
                    lower(hex(randomblob(16))), ?, ?, ?,
                    ?, ?, ?,
                    ?, ?, ?, 1
                )
                ON CONFLICT (provider, entityType, externalRefID)
                DO UPDATE SET
                    remoteModifiedAt = excluded.remoteModifiedAt,
                    canonicalHash = excluded.canonicalHash,
                    status = excluded.status,
                    lastSeenAt = excluded.lastSeenAt,
                    appliedAt = CASE WHEN excluded.status = 'applied' THEN excluded.appliedAt ELSE appliedAt END,
                    attemptCount = attemptCount + 1
                """,
            arguments: [
                provider, entityType, externalRefID,
                remoteModifiedAt, canonicalHash, status,
                now, now, status == "applied" ? now : nil
            ]
        )
    }

    private func ensureRecordingsExternalReferenceColumns(in db: Database) throws {
        guard try db.tableExists("recordings") else { return }

        try addColumnIfMissing(
            table: "recordings",
            column: "externalProvider",
            sqlType: "TEXT",
            in: db
        )
        try addColumnIfMissing(
            table: "recordings",
            column: "externalEntityType",
            sqlType: "TEXT",
            in: db
        )
        try addColumnIfMissing(
            table: "recordings",
            column: "externalRefID",
            sqlType: "TEXT",
            in: db
        )
        try addColumnIfMissing(
            table: "recordings",
            column: "externalCanonicalHash",
            sqlType: "TEXT",
            in: db
        )
        try addColumnIfMissing(
            table: "recordings",
            column: "externalRemoteModifiedAt",
            sqlType: "DATETIME",
            in: db
        )
        try addColumnIfMissing(
            table: "recordings",
            column: "externalLastSeenAt",
            sqlType: "DATETIME",
            in: db
        )

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
    }

    private func addColumnIfMissing(
        table: String,
        column: String,
        sqlType: String,
        in db: Database
    ) throws {
        let exists = try (Bool.fetchOne(
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

        guard !exists else { return }
        try db.execute(sql: "ALTER TABLE \(table) ADD COLUMN \(column) \(sqlType)")
    }

    private func ensureMemoChangeHistorySchema(in db: Database) throws {
        try db.create(table: "memo_change_history", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("memoId", .text).notNull()
            t.column("eventType", .text).notNull()
            t.column("source", .text).notNull().defaults(to: "database")
            t.column("timestamp", .datetime).notNull()
            t.column("changedFields", .text).notNull().defaults(to: "")
            t.column("detailsJSON", .text)
        }

        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_memo_change_history_memo_id_timestamp ON memo_change_history(memoId, timestamp DESC)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_memo_change_history_timestamp ON memo_change_history(timestamp DESC)")

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
    }

    private func fetchExistingStates(pool: DatabasePool) async throws -> [UUID: LocalMemoState] {
        try await pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, createdAt, lastModified, title, duration, sortOrder,
                           transcription, notes, summary, tasks, reminders,
                           audioFilePath, waveformData,
                           isTranscribing, isProcessingSummary, isProcessingTasks,
                           isProcessingReminders, autoProcessed,
                           originDeviceId, macReceivedAt, cloudSyncedAt,
                           deletedAt, pendingWorkflowIds
                    FROM voice_memos
                    """
            )
            var map: [UUID: LocalMemoState] = [:]
            map.reserveCapacity(rows.count)

            for row in rows {
                let rawID = row["id"]
                guard let id = cloudUUID(from: rawID),
                      let lastModified: Date = row["lastModified"] else {
                    continue
                }
                let deletedAt: Date? = row["deletedAt"]
                let audioFilePath: String? = row["audioFilePath"]
                let localMemo = MemoRecord(
                    id: id,
                    createdAt: row["createdAt"] ?? lastModified,
                    lastModified: lastModified,
                    title: row["title"],
                    duration: row["duration"] ?? 0,
                    sortOrder: row["sortOrder"] ?? 0,
                    transcription: row["transcription"],
                    notes: row["notes"],
                    summary: row["summary"],
                    tasks: row["tasks"],
                    reminders: row["reminders"],
                    audioFilePath: audioFilePath,
                    waveformData: row["waveformData"],
                    isTranscribing: row["isTranscribing"] ?? false,
                    isProcessingSummary: row["isProcessingSummary"] ?? false,
                    isProcessingTasks: row["isProcessingTasks"] ?? false,
                    isProcessingReminders: row["isProcessingReminders"] ?? false,
                    autoProcessed: row["autoProcessed"] ?? false,
                    originDeviceId: row["originDeviceId"],
                    macReceivedAt: row["macReceivedAt"],
                    cloudSyncedAt: row["cloudSyncedAt"],
                    deletedAt: deletedAt,
                    pendingWorkflowIds: row["pendingWorkflowIds"],
                    revisionHistoryJSON: nil
                )
                map[id] = LocalMemoState(
                    lastModified: lastModified,
                    deletedAt: deletedAt,
                    audioFilePath: audioFilePath,
                    contentSignature: syncSignature(for: localMemo)
                )
            }
            return map
        }
    }

    private func shouldHydrateAudio(
        memo: MemoRecord,
        localAudioPath: String?
    ) -> Bool {
        guard memo.deletedAt == nil else { return false }
        guard !hasLocalAudioFile(localAudioPath) else { return false }
        if let remoteAudioPath = memo.audioFilePath, !remoteAudioPath.isEmpty,
           hasLocalAudioFile(remoteAudioPath) {
            return false
        }

        // Require at least one known audio hint before issuing a payload fetch.
        // This allows recovery when local GRDB has a path but remote fileURL is missing.
        // A non-zero duration counts as a hint — iOS recordings may lack CD_fileURL
        // but still have audio stored as a CKAsset in CD_audioData.
        guard localAudioPath != nil || memo.audioFilePath != nil || memo.duration > 0 else { return false }
        return true
    }

    private func hasLocalAudioFile(_ path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }

        if path.hasPrefix("/") {
            return FileManager.default.fileExists(atPath: path)
        }

        let candidateURL = audioDirectoryURL.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: candidateURL.path)
    }

    private func fetchAndStoreAudioFile(
        for recordID: CKRecord.ID,
        schema: Schema,
        memoID: UUID,
        in database: CKDatabase
    ) async -> String? {
        let desiredAudioKeys: [String] = {
            switch schema {
            case .coreDataMirrored:
                // Core Data stores large binary data as CKAssets with _ckAsset suffix
                return ["CD_audioData", "CD_audioData_ckAsset"]
            case .legacyCustom:
                return ["audioAsset", "audioData"]
            }
        }()

        let fetchResults: [CKRecord.ID: Result<CKRecord, any Error>]
        do {
            fetchResults = try await database.records(for: [recordID], desiredKeys: desiredAudioKeys)
        } catch {
            log.warning("Audio payload fetch failed for memo \(memoID): \(error.localizedDescription)")
            return nil
        }

        guard let fetchResult = fetchResults[recordID] else {
            log.warning("Audio payload fetch missing result for memo \(memoID)")
            return nil
        }

        let record: CKRecord
        switch fetchResult {
        case .success(let fetchedRecord):
            record = fetchedRecord
        case .failure(let ckError as CKError)
            where ckError.code == .unknownItem || ckError.code == .zoneNotFound:
            log.warning("Audio payload unavailable for memo \(memoID): \(ckError.localizedDescription)")
            return nil
        case .failure(let error):
            log.warning("Audio payload unavailable for memo \(memoID): \(error.localizedDescription)")
            return nil
        }

        guard let audioData = extractAudioData(from: record) else {
            return nil
        }

        do {
            try FileManager.default.createDirectory(
                at: audioDirectoryURL,
                withIntermediateDirectories: true
            )
            let filename = "\(memoID.uuidString).m4a"
            let destinationURL = audioDirectoryURL.appendingPathComponent(filename)
            try audioData.write(to: destinationURL, options: .atomic)
            return filename
        } catch {
            log.warning("Audio payload save failed for memo \(memoID): \(error.localizedDescription)")
            return nil
        }
    }

    private func extractAudioData(from record: CKRecord) -> Data? {
        let candidates: [Any?] = [
            record["CD_audioData_ckAsset"],
            record["CD_audioData"],
            record["audioData"],
            record["audioAsset"]
        ]

        for candidate in candidates {
            if let data = candidate as? Data {
                return data
            }
            if let nsData = candidate as? NSData {
                return nsData as Data
            }
            if let asset = candidate as? CKAsset,
               let assetURL = asset.fileURL,
               let data = try? Data(contentsOf: assetURL) {
                return data
            }
        }

        return nil
    }

    private func fetchRemoteMemos(options: SyncOptions = .all) async throws -> RemoteFetchResult {
        let cd = try await fetchRecords(schema: .coreDataMirrored, options: options)
        if !cd.records.isEmpty {
            return RemoteFetchResult(
                schema: .coreDataMirrored,
                records: cd.records,
                hadPartialFailures: cd.hadPartialFailures,
                isAuthoritative: cd.isAuthoritative
            )
        }

        let legacy = try await fetchRecords(schema: .legacyCustom, options: options)
        if !legacy.records.isEmpty {
            return RemoteFetchResult(
                schema: .legacyCustom,
                records: legacy.records,
                hadPartialFailures: legacy.hadPartialFailures,
                isAuthoritative: legacy.isAuthoritative
            )
        }

        let authoritativeSchema: Schema = {
            if cd.isAuthoritative {
                return .coreDataMirrored
            }
            if legacy.isAuthoritative {
                return .legacyCustom
            }
            return .coreDataMirrored
        }()

        return RemoteFetchResult(
            schema: authoritativeSchema,
            records: [],
            hadPartialFailures: cd.hadPartialFailures || legacy.hadPartialFailures,
            isAuthoritative: cd.isAuthoritative || legacy.isAuthoritative
        )
    }

    private func fetchRecords(
        schema: Schema,
        options: SyncOptions = .all
    ) async throws -> (records: [CKRecord], hadPartialFailures: Bool, isAuthoritative: Bool) {
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase

        let predicate: NSPredicate
        if let since = options.since {
            // Use lastModifiedField (CD_lastModified) — tracks when the memo was last edited on any device.
            // This catches both new records AND edits to existing ones (unlike createdAtField which is immutable).
            predicate = NSPredicate(format: "%K >= %@", schema.lastModifiedField, since as NSDate)
        } else {
            predicate = NSPredicate(value: true)
        }

        let query = CKQuery(recordType: schema.recordType, predicate: predicate)
        // Sort by lastModifiedField for incremental fetches (most recently changed first),
        // createdAtField for full syncs (stable ordering).
        let sortKey = options.since != nil ? schema.lastModifiedField : schema.createdAtField
        query.sortDescriptors = [NSSortDescriptor(key: sortKey, ascending: false)]

        let limit = options.limit
        var cursor: CKQueryOperation.Cursor?
        var records: [CKRecord] = []
        var hadPartialFailures = false

        repeat {
            let pageSize: Int
            if let limit {
                let remaining = limit - records.count
                if remaining <= 0 { break }
                pageSize = min(remaining, 200)
            } else {
                pageSize = 200
            }

            let pageResult: (
                matchResults: [(CKRecord.ID, Result<CKRecord, Error>)],
                queryCursor: CKQueryOperation.Cursor?
            )

            do {
                if let cursor {
                    pageResult = try await database.records(
                        continuingMatchFrom: cursor,
                        desiredKeys: schema.desiredKeys
                    )
                } else {
                    pageResult = try await database.records(
                        matching: query,
                        inZoneWith: schema.zoneID,
                        desiredKeys: schema.desiredKeys,
                        resultsLimit: pageSize
                    )
                }
            } catch let ckError as CKError where ckError.code == .zoneNotFound {
                log.info("CloudKit zone not found for \(schema.recordType): \(schema.zoneID.zoneName)")
                // Non-authoritative empty: never treat schema/zone absence as clean remote state.
                return ([], true, false)
            } catch let ckError as CKError where ckError.code == .unknownItem {
                log.info("CloudKit record type not found: \(schema.recordType)")
                // Non-authoritative empty: never treat schema/record-type absence as clean remote state.
                return ([], true, false)
            }

            for (_, result) in pageResult.matchResults {
                switch result {
                case .success(let record):
                    records.append(record)
                    if let limit, records.count >= limit { break }
                case .failure(let error):
                    hadPartialFailures = true
                    log.warning("CloudKit partial record failure (\(schema.recordType)): \(error.localizedDescription)")
                }
            }

            // Stop pagination if we've reached the limit
            if let limit, records.count >= limit {
                break
            }

            cursor = pageResult.queryCursor
        } while cursor != nil

        log.info("CloudKit fetched \(records.count) \(schema.recordType) record(s)" +
                 (options.limit != nil || options.since != nil ? " (filtered)" : ""))
        // Filtered fetches are not authoritative for deletion reconciliation
        let isAuthoritative = options.limit == nil && options.since == nil
        return (records, hadPartialFailures, isAuthoritative)
    }

    private func parseMetadata(from record: CKRecord) -> RemoteMemoMetadata? {
        guard let id = cloudUUID(from: field("id", in: record) ?? record.recordID.recordName) else {
            return nil
        }

        let createdAt = cloudDate(from: field("createdAt", in: record))
            ?? record.creationDate
            ?? Date()
        let lastModified = cloudDate(from: field("lastModified", in: record))
            ?? record.modificationDate
            ?? createdAt
        let originDeviceId = nonEmptyString(from: field("originDeviceId", in: record))

        return RemoteMemoMetadata(
            id: id,
            createdAt: createdAt,
            lastModified: lastModified,
            originDeviceId: originDeviceId
        )
    }

    private func mapMemo(from record: CKRecord, metadata: RemoteMemoMetadata) -> MemoRecord? {
        MemoRecord(
            id: metadata.id,
            createdAt: metadata.createdAt,
            lastModified: metadata.lastModified,
            title: nonEmptyString(from: field("title", in: record)),
            duration: cloudDouble(from: field("duration", in: record)) ?? 0,
            sortOrder: cloudInt(from: field("sortOrder", in: record)) ?? 0,
            transcription: nonEmptyString(from: field("transcription", in: record)),
            notes: nonEmptyString(from: field("notes", in: record)),
            summary: nonEmptyString(from: field("summary", in: record)),
            tasks: nonEmptyString(from: field("tasks", in: record)),
            reminders: nonEmptyString(from: field("reminders", in: record)),
            audioFilePath: normalizedAudioFilePath(
                from: nonEmptyString(from: field("fileURL", in: record)),
                memoID: metadata.id
            ),
            waveformData: field("waveformData", in: record) as? Data,
            isTranscribing: cloudBool(from: field("isTranscribing", in: record)) ?? false,
            isProcessingSummary: cloudBool(from: field("isProcessingSummary", in: record)) ?? false,
            isProcessingTasks: cloudBool(from: field("isProcessingTasks", in: record)) ?? false,
            isProcessingReminders: cloudBool(from: field("isProcessingReminders", in: record)) ?? false,
            autoProcessed: cloudBool(from: field("autoProcessed", in: record)) ?? false,
            originDeviceId: metadata.originDeviceId,
            macReceivedAt: cloudDate(from: field("macReceivedAt", in: record)),
            cloudSyncedAt: cloudDate(from: field("cloudSyncedAt", in: record)) ?? Date(),
            deletedAt: cloudDate(from: field("deletedAt", in: record)),
            pendingWorkflowIds: nonEmptyString(from: field("pendingWorkflowIds", in: record)),
            revisionHistoryJSON: nil
        )
    }

    private func normalizedAudioFilePath(from rawValue: String?, memoID: UUID) -> String? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }

        if rawValue.hasPrefix("file://"), let fileURL = URL(string: rawValue) {
            let name = fileURL.lastPathComponent
            return name.isEmpty ? nil : name
        }

        if rawValue.contains("/") {
            let name = URL(fileURLWithPath: rawValue).lastPathComponent
            return name.isEmpty ? nil : name
        }

        return rawValue
    }

    private func field(_ key: String, in record: CKRecord) -> Any? {
        if let value = record["CD_\(key)"] {
            return value
        }
        return record[key]
    }

    private func nonEmptyString(from value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        return raw.isEmpty ? nil : raw
    }

    private func cloudBool(from value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    private func cloudInt(from value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Int64 { return Int(value) }
        if let value = value as? Int32 { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private func cloudDouble(from value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Float { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private func cloudDate(from value: Any?) -> Date? {
        if let value = value as? Date { return value }
        if let value = value as? NSDate { return value as Date }
        return nil
    }

    private func cloudUUID(from value: Any?) -> UUID? {
        if let value = value as? UUID {
            return value
        }
        if let value = value as? Data {
            return uuidFromData(value)
        }
        if let value = value as? String {
            if let uuid = UUID(uuidString: value) {
                return uuid
            }
            return parseUUID(from: value)
        }
        return nil
    }

    private func uuidFromData(_ data: Data) -> UUID? {
        guard data.count == 16 else { return nil }
        return data.withUnsafeBytes { bytes in
            let buffer = bytes.bindMemory(to: UInt8.self)
            guard let base = buffer.baseAddress else { return nil }
            return UUID(uuid: (
                base[0], base[1], base[2], base[3],
                base[4], base[5], base[6], base[7],
                base[8], base[9], base[10], base[11],
                base[12], base[13], base[14], base[15]
            ))
        }
    }

    private func parseUUID(from text: String) -> UUID? {
        guard let uuidRegex else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = uuidRegex.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text) else {
            return nil
        }
        return UUID(uuidString: String(text[swiftRange]))
    }

    private func formatTrace(id: UUID, createdAt: Date, originDeviceId: String?) -> String {
        let origin = (originDeviceId?.isEmpty == false) ? originDeviceId! : "unknown-origin"
        return "\(id.uuidString) @ \(ISO8601DateFormatter().string(from: createdAt)) [\(origin)]"
    }

    /// Content-only signature for change detection.
    /// Only includes fields that originate from the recording source (device/CloudKit).
    /// Excludes:
    /// - Transient processing flags, waveformData, pendingWorkflowIds
    /// - `summary`, `tasks`, `reminders` — generated locally by auto-processing,
    ///   not synced via CloudKit. Including them caused every auto-processed memo
    ///   to appear as "updated" on every sync cycle (CloudKit has nil, local has content).
    private func syncSignature(for memo: MemoRecord) -> String {
        var components: [String] = []
        components.reserveCapacity(8)
        components.append(memo.title ?? "")
        components.append("\(memo.duration.bitPattern)")
        components.append("\(memo.sortOrder)")
        components.append(memo.transcription ?? "")
        components.append(memo.notes ?? "")
        components.append(memo.originDeviceId ?? "")

        let payload = components.joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func hashData(_ data: Data?) -> String {
        guard let data else { return "nil" }
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
