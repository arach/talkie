//
//  RecordingRepository.swift
//  Talkie
//
//  Unified repository for all recordings (memos and dictations)
//  Single data access layer for the recordings table
//

import Foundation
import GRDB
import TalkieKit

private let log = Log(.database)
private enum SyncTrackingOperation: Sendable {
    case create
    case update
    case delete
}

private struct PendingSyncChange: Sendable {
    let memoId: UUID
    let operation: SyncTrackingOperation
}

// MARK: - Recording Repository

actor TalkieObjectRepository {
    private let dbManager: DatabaseManager

    init(dbManager: DatabaseManager = .shared) {
        self.dbManager = dbManager
    }

    /// Internal helper: gets DB queue, waiting for initialization if needed.
    /// Eliminates notInitialized errors from startup race conditions.
    private func db() async throws -> DatabaseQueue {
        try await dbManager.databaseWhenReady()
    }

    // MARK: - Fetch Recordings

    /// Fetch recordings with filtering, sorting, and pagination
    func fetchRecordings(
        sortBy: RecordingSortField = .createdAt,
        ascending: Bool = false,
        limit: Int = 50,
        offset: Int = 0,
        searchQuery: String? = nil,
        filters: Set<RecordingFilter> = []
    ) async throws -> [TalkieObject] {
        let startTime = Date()
        let db = try await db()

        log.debug("Executing query: sort=\(sortBy), limit=\(limit), offset=\(offset), filters=\(filters.count)")

        let result = try await db.read { db in
            // Start with non-deleted recordings only, excluding segments
            var request = TalkieObject.all()
                .filter(TalkieObject.Columns.deletedAt == nil)
                .filter(TalkieObject.Columns.type != TalkieObjectType.segment.rawValue)

            // Apply search filter
            if let query = searchQuery, !query.isEmpty {
                request = request.filter(
                    TalkieObject.Columns.title.like("%\(query)%") ||
                    TalkieObject.Columns.text.like("%\(query)%") ||
                    TalkieObject.Columns.notes.like("%\(query)%")
                )
            }

            // Apply filters
            request = self.applyFilters(request, filters: filters)

            // Apply sorting
            switch sortBy {
            case .createdAt:
                request = ascending
                    ? request.order(TalkieObject.Columns.createdAt.asc)
                    : request.order(TalkieObject.Columns.createdAt.desc)

            case .title:
                request = ascending
                    ? request.order(TalkieObject.Columns.title.collating(.nocase).asc)
                    : request.order(TalkieObject.Columns.title.collating(.nocase).desc)

            case .duration:
                request = ascending
                    ? request.order(TalkieObject.Columns.duration.asc)
                    : request.order(TalkieObject.Columns.duration.desc)

            case .type:
                // Memos first (alphabetically: 'd' > 'm' so ascending puts memos first)
                request = ascending
                    ? request.order(TalkieObject.Columns.type.asc, TalkieObject.Columns.createdAt.desc)
                    : request.order(TalkieObject.Columns.type.desc, TalkieObject.Columns.createdAt.desc)
            }

            // Apply pagination
            request = request.limit(limit, offset: offset)

            return try request.fetchAll(db)
        }

        let elapsed = Date().timeIntervalSince(startTime)
        log.debug("Query completed in \(Int(elapsed * 1000))ms, returned \(result.count) recordings")

        return result
    }

    /// Fetch recordings using raw SQL WHERE clause (for semantic filters)
    func fetchRecordingsWithSQL(
        whereClause: String,
        sortBy: RecordingSortField = .createdAt,
        ascending: Bool = false,
        limit: Int = 50,
        offset: Int = 0,
        requester: String = "unknown",
        queryLabel: String? = nil,
        requestID: String? = nil
    ) async throws -> [TalkieObject] {
        let startTime = Date()
        let db = try await db()
        let reqID = requestID ?? String(UUID().uuidString.prefix(8))
        let summary = summarizeWhereClause(whereClause, fallback: queryLabel)

        // Build ORDER BY clause
        let orderBy: String
        switch sortBy {
        case .createdAt:
            orderBy = ascending ? "createdAt ASC" : "createdAt DESC"
        case .title:
            orderBy = ascending ? "title COLLATE NOCASE ASC" : "title COLLATE NOCASE DESC"
        case .duration:
            orderBy = ascending ? "duration ASC" : "duration DESC"
        case .type:
            orderBy = ascending ? "type ASC, createdAt DESC" : "type DESC, createdAt DESC"
        }

        // Build full query with deletedAt filter and segment exclusion always included
        let sql = """
            SELECT * FROM recordings
            WHERE deletedAt IS NULL AND type != 'segment' AND (\(whereClause))
            ORDER BY \(orderBy)
            LIMIT ? OFFSET ?
            """

        log.debug("db.query[\(reqID)] \(requester) fetch start: \(summary), sort=\(sortBy), limit=\(limit), offset=\(offset)")

        let result = try await db.read { db in
            try TalkieObject.fetchAll(db, sql: sql, arguments: [limit, offset])
        }

        let elapsed = Date().timeIntervalSince(startTime)
        log.debug("db.query[\(reqID)] \(requester) fetch done: \(Int(elapsed * 1000))ms, rows=\(result.count)")

        return result
    }

    /// Count recordings using raw SQL WHERE clause
    func countRecordingsWithSQL(
        whereClause: String,
        requester: String = "unknown",
        queryLabel: String? = nil,
        requestID: String? = nil
    ) async throws -> Int {
        let startTime = Date()
        let db = try await db()
        let reqID = requestID ?? String(UUID().uuidString.prefix(8))
        let summary = summarizeWhereClause(whereClause, fallback: queryLabel)

        let sql = """
            SELECT COUNT(*) FROM recordings
            WHERE deletedAt IS NULL AND type != 'segment' AND (\(whereClause))
            """

        log.debug("db.query[\(reqID)] \(requester) count start: \(summary)")

        let count = try await db.read { db in
            try Int.fetchOne(db, sql: sql) ?? 0
        }

        let elapsed = Date().timeIntervalSince(startTime)
        log.debug("db.query[\(reqID)] \(requester) count done: \(Int(elapsed * 1000))ms, total=\(count)")

        return count
    }

    /// Fetch a single recording by ID
    func fetchRecording(id: UUID) async throws -> TalkieObject? {
        let db = try await db()

        return try await db.read { db in
            try TalkieObject
                .filter(TalkieObject.Columns.id == id)
                .fetchOne(db)
        }
    }

    /// Fetch recordings by type
    func fetchByType(_ type: TalkieObjectType, limit: Int = 100) async throws -> [TalkieObject] {
        let db = try await db()

        return try await db.read { db in
            try TalkieObject
                .filter(TalkieObject.Columns.type == type.rawValue)
                .filter(TalkieObject.Columns.deletedAt == nil)
                .order(TalkieObject.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Fetch recordings by source
    func fetchBySource(_ source: RecordingSource, limit: Int = 100) async throws -> [TalkieObject] {
        let db = try await db()

        return try await db.read { db in
            try TalkieObject
                .filter(TalkieObject.Columns.source == source.rawValue)
                .filter(TalkieObject.Columns.deletedAt == nil)
                .order(TalkieObject.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Count

    /// Count recordings with optional filters (excludes segments)
    func countRecordings(
        searchQuery: String? = nil,
        filters: Set<RecordingFilter> = []
    ) async throws -> Int {
        let db = try await db()

        return try await db.read { db in
            var request = TalkieObject.all()
                .filter(TalkieObject.Columns.deletedAt == nil)
                .filter(TalkieObject.Columns.type != TalkieObjectType.segment.rawValue)

            if let query = searchQuery, !query.isEmpty {
                request = request.filter(
                    TalkieObject.Columns.title.like("%\(query)%") ||
                    TalkieObject.Columns.text.like("%\(query)%")
                )
            }

            request = self.applyFilters(request, filters: filters)

            return try request.fetchCount(db)
        }
    }

    /// Count memos only
    func countMemos() async throws -> Int {
        try await countRecordings(filters: [.type(.memo)])
    }

    /// Count dictations only
    func countDictations() async throws -> Int {
        try await countRecordings(filters: [.type(.dictation)])
    }

    /// Count memo rows in the unified recordings table.
    func countMemoRecordings() async throws -> Int {
        let db = try await db()

        return try await db.read { db in
            try TalkieObject
                .filter(TalkieObject.Columns.type == TalkieObjectType.memo.rawValue)
                .fetchCount(db)
        }
    }

    /// Rebuild memo rows in unified recordings from the source-of-truth voice_memos table.
    /// Returns the number of memo rows inserted into `recordings`.
    func rebuildMemoRecordingsMirror() async throws -> Int {
        let db = try await db()

        return try await db.write { db in
            _ = try TalkieObject
                .filter(TalkieObject.Columns.type == TalkieObjectType.memo.rawValue)
                .deleteAll(db)

            try db.execute(sql: """
                INSERT INTO recordings (
                    id, type, text, title, notes,
                    duration, hasAudio,
                    createdAt, lastModified, deletedAt, pinnedAt, starredAt,
                    source, sourceDeviceId,
                    promotedAt,
                    transcriptionStatus, transcriptionError, transcriptionModel,
                    summary, tasks, reminders,
                    isProcessingSummary, isProcessingTasks, isProcessingReminders, autoProcessed,
                    cloudSyncedAt, pendingWorkflowIds, metadataJSON, audioFilename
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
                    pinnedAt,
                    starredAt,
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
                    NULL,
                    audioFilePath
                FROM voice_memos
            """)

            return db.changesCount
        }
    }

    /// Refresh memo fields in unified recordings from source-of-truth voice_memos.
    /// This keeps memo mirror rows current even when row counts match (content-only drift).
    /// Also inserts memo rows that exist in `voice_memos` but are missing in `recordings`.
    /// Returns number of inserted + updated rows in `recordings`.
    func refreshMemoRecordingsMirrorFields() async throws -> Int {
        let db = try await db()

        return try await db.write { db in
            try db.execute(sql: """
                INSERT INTO recordings (
                    id, type, text, title, notes,
                    duration, hasAudio,
                    createdAt, lastModified, deletedAt, pinnedAt, starredAt,
                    source, sourceDeviceId,
                    promotedAt,
                    transcriptionStatus, transcriptionError, transcriptionModel,
                    summary, tasks, reminders,
                    isProcessingSummary, isProcessingTasks, isProcessingReminders, autoProcessed,
                    cloudSyncedAt, pendingWorkflowIds, metadataJSON, audioFilename
                )
                SELECT
                    vm.id,
                    'memo',
                    vm.transcription,
                    vm.title,
                    vm.notes,
                    vm.duration,
                    CASE WHEN vm.audioFilePath IS NOT NULL AND vm.audioFilePath != '' THEN 1 ELSE 0 END,
                    vm.createdAt,
                    vm.lastModified,
                    vm.deletedAt,
                    vm.pinnedAt,
                    vm.starredAt,
                    CASE
                        WHEN vm.originDeviceId LIKE 'mac-%' THEN 'mac'
                        WHEN vm.originDeviceId LIKE 'watch-%' THEN 'watch'
                        WHEN vm.originDeviceId LIKE 'live-%' THEN 'live'
                        ELSE 'iphone'
                    END,
                    vm.originDeviceId,
                    NULL,
                    CASE
                        WHEN vm.isTranscribing = 1 THEN 'pending'
                        WHEN COALESCE(vm.audioFilePath, '') != '' AND COALESCE(vm.transcription, '') = '' THEN 'failed'
                        ELSE 'success'
                    END,
                    CASE
                        WHEN vm.isTranscribing = 1 THEN NULL
                        WHEN COALESCE(vm.audioFilePath, '') != '' AND COALESCE(vm.transcription, '') = '' THEN 'Transcript missing, but audio is still available. Retry transcription from this Mac.'
                        ELSE NULL
                    END,
                    NULL,
                    vm.summary,
                    vm.tasks,
                    vm.reminders,
                    vm.isProcessingSummary,
                    vm.isProcessingTasks,
                    vm.isProcessingReminders,
                    vm.autoProcessed,
                    vm.cloudSyncedAt,
                    vm.pendingWorkflowIds,
                    NULL,
                    vm.audioFilePath
                FROM voice_memos vm
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM recordings r
                    WHERE r.id = vm.id
                      AND r.type = 'memo'
                )
            """)
            let inserted = db.changesCount

            try db.execute(sql: """
                UPDATE recordings
                SET
                    text = (SELECT vm.transcription FROM voice_memos vm WHERE vm.id = recordings.id),
                    title = (SELECT vm.title FROM voice_memos vm WHERE vm.id = recordings.id),
                    notes = (SELECT vm.notes FROM voice_memos vm WHERE vm.id = recordings.id),
                    duration = COALESCE((SELECT vm.duration FROM voice_memos vm WHERE vm.id = recordings.id), duration),
                    hasAudio = CASE
                        WHEN COALESCE((SELECT vm.audioFilePath FROM voice_memos vm WHERE vm.id = recordings.id), '') != ''
                        THEN 1 ELSE 0
                    END,
                    lastModified = (SELECT vm.lastModified FROM voice_memos vm WHERE vm.id = recordings.id),
                    deletedAt = (SELECT vm.deletedAt FROM voice_memos vm WHERE vm.id = recordings.id),
                    source = CASE
                        WHEN COALESCE((SELECT vm.originDeviceId FROM voice_memos vm WHERE vm.id = recordings.id), '') LIKE 'mac-%' THEN 'mac'
                        WHEN COALESCE((SELECT vm.originDeviceId FROM voice_memos vm WHERE vm.id = recordings.id), '') LIKE 'watch-%' THEN 'watch'
                        WHEN COALESCE((SELECT vm.originDeviceId FROM voice_memos vm WHERE vm.id = recordings.id), '') LIKE 'live-%' THEN 'live'
                        ELSE 'iphone'
                    END,
                    sourceDeviceId = (SELECT vm.originDeviceId FROM voice_memos vm WHERE vm.id = recordings.id),
                    transcriptionStatus = CASE
                        WHEN COALESCE((SELECT vm.isTranscribing FROM voice_memos vm WHERE vm.id = recordings.id), 0) = 1 THEN 'pending'
                        WHEN COALESCE((SELECT vm.audioFilePath FROM voice_memos vm WHERE vm.id = recordings.id), '') != ''
                         AND COALESCE((SELECT vm.transcription FROM voice_memos vm WHERE vm.id = recordings.id), '') = '' THEN 'failed'
                        ELSE 'success'
                    END,
                    transcriptionError = CASE
                        WHEN COALESCE((SELECT vm.isTranscribing FROM voice_memos vm WHERE vm.id = recordings.id), 0) = 1 THEN NULL
                        WHEN COALESCE((SELECT vm.audioFilePath FROM voice_memos vm WHERE vm.id = recordings.id), '') != ''
                         AND COALESCE((SELECT vm.transcription FROM voice_memos vm WHERE vm.id = recordings.id), '') = '' THEN 'Transcript missing, but audio is still available. Retry transcription from this Mac.'
                        ELSE NULL
                    END,
                    transcriptionModel = NULL,
                    summary = (SELECT vm.summary FROM voice_memos vm WHERE vm.id = recordings.id),
                    tasks = (SELECT vm.tasks FROM voice_memos vm WHERE vm.id = recordings.id),
                    reminders = (SELECT vm.reminders FROM voice_memos vm WHERE vm.id = recordings.id),
                    isProcessingSummary = COALESCE((SELECT vm.isProcessingSummary FROM voice_memos vm WHERE vm.id = recordings.id), 0),
                    isProcessingTasks = COALESCE((SELECT vm.isProcessingTasks FROM voice_memos vm WHERE vm.id = recordings.id), 0),
                    isProcessingReminders = COALESCE((SELECT vm.isProcessingReminders FROM voice_memos vm WHERE vm.id = recordings.id), 0),
                    autoProcessed = COALESCE((SELECT vm.autoProcessed FROM voice_memos vm WHERE vm.id = recordings.id), 0),
                    cloudSyncedAt = (SELECT vm.cloudSyncedAt FROM voice_memos vm WHERE vm.id = recordings.id),
                    pendingWorkflowIds = (SELECT vm.pendingWorkflowIds FROM voice_memos vm WHERE vm.id = recordings.id),
                    pinnedAt = (SELECT vm.pinnedAt FROM voice_memos vm WHERE vm.id = recordings.id),
                    starredAt = (SELECT vm.starredAt FROM voice_memos vm WHERE vm.id = recordings.id),
                    metadataJSON = NULL,
                    audioFilename = (SELECT vm.audioFilePath FROM voice_memos vm WHERE vm.id = recordings.id)
                WHERE type = 'memo'
                  AND EXISTS (SELECT 1 FROM voice_memos vm WHERE vm.id = recordings.id)
            """)
            let updated = db.changesCount
            return inserted + updated
        }
    }

    // MARK: - Save Operations

    /// Save a recording (insert or update)
    /// Uses GRDB's save() which tries UPDATE first, then INSERT OR REPLACE on conflict.
    func saveRecording(_ recording: TalkieObject) async throws {
        try await saveRecording(recording, trackSyncChanges: true)
    }

    private func saveRecording(_ recording: TalkieObject, trackSyncChanges: Bool) async throws {
        let db = try await db()

        let pendingChange: PendingSyncChange? = try await db.write { db in
            let existing = try TalkieObject.fetchOne(db, key: recording.id)
            var mutableRecording = recording
            try mutableRecording.save(db)

            guard trackSyncChanges, recording.isMemo else { return nil }
            let operation: SyncTrackingOperation
            if let existing, existing.isMemo {
                operation = .update
            } else {
                operation = .create
            }
            return PendingSyncChange(memoId: recording.id, operation: operation)
        }

        if let pendingChange {
            await trackSyncChange(pendingChange)
        }

        log.info("💾 Saved recording id=\(recording.id.uuidString.prefix(8)), type=\(recording.type.rawValue)")

        MarkdownFileWriter.write(recording)
    }

    /// Save multiple recordings in a single transaction
    func saveRecordings(_ recordings: [TalkieObject], trackSyncChanges: Bool = true) async throws {
        let db = try await db()

        let pendingChanges: [PendingSyncChange] = try await db.write { db in
            var pending: [PendingSyncChange] = []
            pending.reserveCapacity(recordings.count)

            for var recording in recordings {
                let existing = try TalkieObject.fetchOne(db, key: recording.id)
                try recording.save(db)

                guard trackSyncChanges, recording.isMemo else { continue }
                let operation: SyncTrackingOperation
                if let existing, existing.isMemo {
                    operation = .update
                } else {
                    operation = .create
                }
                pending.append(PendingSyncChange(memoId: recording.id, operation: operation))
            }

            return pending
        }

        if trackSyncChanges {
            for pendingChange in pendingChanges {
                await trackSyncChange(pendingChange)
            }
        }

        log.info("💾 Saved \(recordings.count) recordings")
    }

    // MARK: - Partial Update Operations

    /// Update only the notes field of a recording (avoids full-row replace race conditions)
    func updateNotes(id: UUID, notes: String?) async throws {
        let db = try await db()
        try await db.write { db in
            try db.execute(
                sql: "UPDATE recordings SET notes = ?, lastModified = ? WHERE id = ?",
                arguments: [notes, Date(), id]
            )
        }
        log.info("📝 Updated notes for id=\(id.uuidString.prefix(8))")
    }

    /// Update only the title and text fields of a recording
    func updateTitleAndText(id: UUID, title: String?, text: String?) async throws {
        let db = try await db()
        let updated = try await db.write { db -> TalkieObject? in
            try db.execute(
                sql: "UPDATE recordings SET title = ?, text = ?, lastModified = ? WHERE id = ?",
                arguments: [title, text, Date(), id]
            )
            guard db.changesCount > 0 else { return nil }
            return try TalkieObject.fetchOne(db, key: id)
        }
        if let object = updated {
            log.info("✏️ Updated title/text for id=\(id.uuidString.prefix(8))")
            MarkdownFileWriter.write(object)
        } else {
            log.warning("⚠️ updateTitleAndText: no row matched id=\(id.uuidString.prefix(8))")
        }
    }

    /// Update only the assetsJSON field of a recording
    func updateAssets(id: UUID, assetsJSON: String?) async throws {
        let db = try await db()
        try await db.write { db in
            try db.execute(
                sql: "UPDATE recordings SET assetsJSON = ?, lastModified = ? WHERE id = ?",
                arguments: [assetsJSON, Date(), id]
            )
        }
        log.info("📎 Updated assets for id=\(id.uuidString.prefix(8))")
    }

    // MARK: - Pin / Star

    /// Toggle pinned state on a recording. For memos the change is mirrored
    /// to `voice_memos` so a later mirror-refresh doesn't overwrite it.
    /// Returns the updated record (or nil if not found).
    @discardableResult
    func setRecordingPinned(id: UUID, pinned: Bool) async throws -> TalkieObject? {
        let db = try await db()
        return try await db.write { db -> TalkieObject? in
            guard var recording = try TalkieObject.fetchOne(db, key: id) else {
                log.warning("📌 Pin id=\(id.uuidString.prefix(8)) — recording not found")
                return nil
            }
            let timestamp = pinned ? Date() : nil
            recording.pinnedAt = timestamp
            recording.lastModified = Date()
            try recording.update(db)
            if recording.isMemo {
                try db.execute(
                    sql: "UPDATE voice_memos SET pinnedAt = ?, lastModified = ? WHERE id = ?",
                    arguments: [timestamp, Date(), id]
                )
            }
            return recording
        }
    }

    /// Toggle starred state on a recording. Memo writes mirror to `voice_memos`.
    @discardableResult
    func setRecordingStarred(id: UUID, starred: Bool) async throws -> TalkieObject? {
        let db = try await db()
        return try await db.write { db -> TalkieObject? in
            guard var recording = try TalkieObject.fetchOne(db, key: id) else {
                log.warning("⭐ Star id=\(id.uuidString.prefix(8)) — recording not found")
                return nil
            }
            let timestamp = starred ? Date() : nil
            recording.starredAt = timestamp
            recording.lastModified = Date()
            try recording.update(db)
            if recording.isMemo {
                try db.execute(
                    sql: "UPDATE voice_memos SET starredAt = ?, lastModified = ? WHERE id = ?",
                    arguments: [timestamp, Date(), id]
                )
            }
            return recording
        }
    }

    // MARK: - Delete Operations

    /// Soft delete a recording (set deletedAt timestamp) - for memos
    func softDeleteRecording(id: UUID) async throws {
        let db = try await db()

        let deletedType = try await db.write { db -> TalkieObjectType? in
            if var recording = try TalkieObject.fetchOne(db, key: id) {
                let type = recording.type
                recording.deletedAt = Date()
                try recording.update(db)
                log.info("🗑️ Soft delete id=\(id.uuidString.prefix(8)), success")
                return type
            } else {
                log.warning("🗑️ Soft delete id=\(id.uuidString.prefix(8)), recording not found")
                return nil
            }
        }

        if let type = deletedType {
            MarkdownFileWriter.delete(id: id, type: type)
            if type == .memo {
                await trackSyncChange(PendingSyncChange(memoId: id, operation: .update))
            }
        }
    }

    /// Hard delete a recording (permanent) - for dictations or after user confirms
    func hardDeleteRecording(id: UUID) async throws {
        let db = try await db()

        let deletedInfo = try await db.write { db -> (isMemo: Bool, type: TalkieObjectType)? in
            let existing = try TalkieObject.fetchOne(db, key: id)

            try TalkieObject
                .filter(TalkieObject.Columns.id == id)
                .deleteAll(db)

            guard let existing else {
                log.warning("🗑️ Hard delete id=\(id.uuidString.prefix(8)), recording not found")
                return nil
            }
            return (existing.isMemo, existing.type)
        }

        if let info = deletedInfo {
            MarkdownFileWriter.delete(id: id, type: info.type)
            if info.isMemo {
                await trackSyncChange(PendingSyncChange(memoId: id, operation: .delete))
            }
        }

        log.info("🗑️ Hard delete id=\(id.uuidString.prefix(8))")
    }

    /// Delete recordings older than a given date (for TTL cleanup)
    func deleteRecordingsOlderThan(_ date: Date, type: TalkieObjectType? = nil) async throws -> Int {
        let db = try await db()

        return try await db.write { db in
            var request = TalkieObject
                .filter(TalkieObject.Columns.createdAt < date)

            if let type = type {
                request = request.filter(TalkieObject.Columns.type == type.rawValue)
            }

            let count = try request.deleteAll(db)
            log.info("🗑️ Deleted \(count) recordings older than \(date)")
            return count
        }
    }

    /// Restore a soft-deleted recording
    func restoreRecording(id: UUID) async throws {
        let db = try await db()

        let shouldTrackRestore = try await db.write { db -> Bool in
            if var recording = try TalkieObject.fetchOne(db, key: id) {
                let isMemo = recording.isMemo
                recording.deletedAt = nil
                try recording.update(db)
                log.info("♻️ Restore id=\(id.uuidString.prefix(8)), success")
                return isMemo
            } else {
                log.warning("♻️ Restore id=\(id.uuidString.prefix(8)), recording not found")
                return false
            }
        }

        if shouldTrackRestore {
            await trackSyncChange(PendingSyncChange(memoId: id, operation: .update))
        }
    }

    /// Fetch recordings pending deletion
    func fetchPendingDeletions() async throws -> [TalkieObject] {
        let db = try await db()

        return try await db.read { db in
            try TalkieObject
                .filter(TalkieObject.Columns.deletedAt != nil)
                .order(TalkieObject.Columns.deletedAt.desc)
                .fetchAll(db)
        }
    }

    // MARK: - Promotion (Dictation → Memo)

    /// Promote a dictation to a memo
    func promoteToMemo(id: UUID) async throws -> TalkieObject? {
        let db = try await db()

        return try await db.write { db in
            guard var recording = try TalkieObject.fetchOne(db, key: id) else {
                log.warning("⬆️ Promote id=\(id.uuidString.prefix(8)), recording not found")
                return nil
            }

            guard recording.type == .dictation else {
                log.warning("⬆️ Promote id=\(id.uuidString.prefix(8)), already a memo")
                return recording
            }

            recording.type = .memo
            recording.promotedAt = Date()
            recording.cloudSyncedAt = nil // Trigger CloudKit sync on next pass

            try recording.update(db)
            log.info("⬆️ Promoted id=\(id.uuidString.prefix(8)) to memo")

            return recording
        }
    }

    // MARK: - CloudKit Sync Support

    /// Fetch memos that need CloudKit sync (type = memo, cloudSyncedAt < lastModified or nil)
    func fetchMemosNeedingSync() async throws -> [TalkieObject] {
        let db = try await db()

        return try await db.read { db in
            try TalkieObject
                .filter(TalkieObject.Columns.type == TalkieObjectType.memo.rawValue)
                .filter(TalkieObject.Columns.deletedAt == nil)
                .filter(
                    TalkieObject.Columns.cloudSyncedAt == nil ||
                    TalkieObject.Columns.cloudSyncedAt < TalkieObject.Columns.lastModified
                )
                .order(TalkieObject.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    /// Mark a recording as synced
    func markSynced(id: UUID) async throws {
        let db = try await db()

        try await db.write { db in
            if var recording = try TalkieObject.fetchOne(db, key: id) {
                recording.cloudSyncedAt = Date()
                try recording.update(db)
            }
        }
    }

    // MARK: - Search

    /// Full-text search across recordings (excludes segments)
    func searchRecordings(query: String, limit: Int = 50) async throws -> [TalkieObject] {
        let db = try await db()

        return try await db.read { db in
            // Simple LIKE search for now (FTS integration later)
            try TalkieObject
                .filter(TalkieObject.Columns.deletedAt == nil)
                .filter(TalkieObject.Columns.type != TalkieObjectType.segment.rawValue)
                .filter(
                    TalkieObject.Columns.title.like("%\(query)%") ||
                    TalkieObject.Columns.text.like("%\(query)%") ||
                    TalkieObject.Columns.notes.like("%\(query)%")
                )
                .order(TalkieObject.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Aggregations

    /// Total duration of all recordings
    func totalDuration(type: TalkieObjectType? = nil) async throws -> Double {
        let db = try await db()

        return try await db.read { db in
            var sql = "SELECT COALESCE(SUM(duration), 0) as total FROM recordings WHERE deletedAt IS NULL"
            var arguments: [DatabaseValue] = []

            if let type = type {
                sql += " AND type = ?"
                arguments.append(type.rawValue.databaseValue)
            }

            let row = try Row.fetchOne(db, sql: sql, arguments: StatementArguments(arguments))
            return row?["total"] ?? 0.0
        }
    }

    /// Count recordings created today
    func countRecordingsToday(type: TalkieObjectType? = nil) async throws -> Int {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())

        var filters: Set<RecordingFilter> = []
        if let type = type {
            filters.insert(.type(type))
        }

        let db = try await db()

        return try await db.read { db in
            var request = TalkieObject.all()
                .filter(TalkieObject.Columns.deletedAt == nil)
                .filter(TalkieObject.Columns.createdAt >= startOfDay)

            request = self.applyFilters(request, filters: filters)

            return try request.fetchCount(db)
        }
    }

    // MARK: - Helper: Apply Filters

    nonisolated private func applyFilters(
        _ request: QueryInterfaceRequest<TalkieObject>,
        filters: Set<RecordingFilter>
    ) -> QueryInterfaceRequest<TalkieObject> {
        guard !filters.isEmpty else { return request }

        var filteredRequest = request

        for filter in filters {
            switch filter {
            case .type(let type):
                filteredRequest = filteredRequest.filter(TalkieObject.Columns.type == type.rawValue)

            case .source(let source):
                filteredRequest = filteredRequest.filter(TalkieObject.Columns.source == source.rawValue)

            case .hasAudio:
                filteredRequest = filteredRequest.filter(TalkieObject.Columns.audioFilename != nil)

            case .shortRecordings:
                filteredRequest = filteredRequest.filter(TalkieObject.Columns.duration < 30.0)

            case .pendingTranscription:
                filteredRequest = filteredRequest.filter(
                    TalkieObject.Columns.transcriptionStatus == RecordingTranscriptionStatus.pending.rawValue ||
                    TalkieObject.Columns.transcriptionStatus == RecordingTranscriptionStatus.failed.rawValue
                )

            case .hasWorkflows:
                // This would require a subquery or join - skip for now
                // Could add a workflowCount column later for efficiency
                break
            }
        }

        return filteredRequest
    }

    nonisolated private func summarizeWhereClause(_ whereClause: String, fallback: String?) -> String {
        if let fallback, !fallback.isEmpty {
            return fallback
        }

        let normalized = whereClause
            .replacing("\n", with: " ")
            .replacing("\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized == "1=1" { return "all" }
        if normalized.localizedStandardContains("type = 'memo'") { return "memos" }
        if normalized.localizedStandardContains("type = 'dictation'") { return "dictations" }

        return String(normalized.prefix(72))
    }
}

// MARK: - Segment Support

extension TalkieObjectRepository {

    /// Fetch segments for a parent note, ordered by segmentIndex
    func fetchSegments(forNoteId noteId: UUID) async throws -> [TalkieObject] {
        let db = try await db()

        return try await db.read { db in
            try TalkieObject
                .filter(TalkieObject.Columns.type == TalkieObjectType.segment.rawValue)
                .filter(TalkieObject.Columns.parentId == noteId)
                .order(TalkieObject.Columns.segmentIndex.asc)
                .fetchAll(db)
        }
    }

    /// Count segments for a parent note
    func countSegments(forNoteId noteId: UUID) async throws -> Int {
        let db = try await db()

        return try await db.read { db in
            try TalkieObject
                .filter(TalkieObject.Columns.type == TalkieObjectType.segment.rawValue)
                .filter(TalkieObject.Columns.parentId == noteId)
                .fetchCount(db)
        }
    }

    /// Delete segments for a parent note (with audio file cleanup)
    func deleteSegments(forNoteId noteId: UUID) async throws {
        let db = try await db()

        // Fetch segments to get audio filenames
        let segments = try await fetchSegments(forNoteId: noteId)

        // Delete audio files
        for segment in segments {
            if let filename = segment.audioFilename {
                AudioStorage.delete(filename: filename)
            }
        }

        // Delete records
        try await db.write { db in
            try TalkieObject
                .filter(TalkieObject.Columns.type == TalkieObjectType.segment.rawValue)
                .filter(TalkieObject.Columns.parentId == noteId)
                .deleteAll(db)
        }

        if !segments.isEmpty {
            log.info("🗑️ Deleted \(segments.count) segments for note \(noteId.uuidString.prefix(8))")
        }
    }

    /// Delete orphaned segments (segments whose parent note/memo no longer exists)
    func pruneOrphanedSegments() async throws -> Int {
        let db = try await db()

        return try await db.write { db in
            // Get audio filenames for orphaned segments
            let orphanedAudio = try String.fetchAll(
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

            // Delete audio files
            for filename in orphanedAudio {
                AudioStorage.delete(filename: filename)
            }

            // Delete orphaned records
            try db.execute(
                sql: """
                    DELETE FROM recordings WHERE type = 'segment'
                      AND parentId NOT IN (
                          SELECT id FROM recordings WHERE type IN ('note', 'memo')
                      )
                    """
            )

            let count = db.changesCount
            if count > 0 {
                log.info("🗑️ Pruned \(count) orphaned segments")
            }
            return count
        }
    }
}

// MARK: - Continue Memo (segment-based continuation)

extension TalkieObjectRepository {

    /// Promote a memo to segmented: create segment 0 from its current audio/transcript,
    /// so the original recording becomes a container for multiple segments.
    /// Only call this once — before the first continuation.
    func promoteMemoToSegmented(memoId: UUID) async throws {
        let db = try await db()

        guard let memo = try await fetchRecording(id: memoId) else {
            throw RepositoryError.notFound(memoId)
        }

        guard memo.isMemo else {
            throw RepositoryError.invalidOperation("Can only continue memos")
        }

        // Check if already promoted (has segments)
        let existingCount = try await countSegments(forNoteId: memoId)
        if existingCount > 0 {
            log.debug("Memo \(memoId.uuidString.prefix(8)) already has \(existingCount) segments, skipping promotion")
            return
        }

        // Create segment 0 from the memo's current state
        var segment0 = TalkieObject.newSegment(
            parentId: memoId,
            segmentIndex: 0,
            text: memo.text ?? "",
            duration: memo.duration,
            audioFilename: memo.audioFilename,
            transcriptionModel: memo.transcriptionModel
        )
        segment0.createdAt = memo.createdAt
        segment0.lastModified = memo.createdAt
        // Carry over timed transcription
        segment0.assetsJSON = memo.assetsJSON

        try await db.write { db in
            try segment0.save(db)
        }

        log.info("📎 Promoted memo \(memoId.uuidString.prefix(8)) — created segment 0")
    }

    /// Add a new segment to an existing memo. Handles promotion if this is the first continuation.
    /// Returns the created segment.
    @discardableResult
    func addSegment(
        parentId: UUID,
        text: String,
        duration: Double,
        audioFilename: String?,
        transcriptionModel: String?,
        assets: TalkieObjectAssets? = nil
    ) async throws -> TalkieObject {
        // Auto-promote if this is the first continuation
        try await promoteMemoToSegmented(memoId: parentId)

        let db = try await db()
        let segmentIndex = try await countSegments(forNoteId: parentId)

        var segment = TalkieObject.newSegment(
            parentId: parentId,
            segmentIndex: segmentIndex,
            text: text,
            duration: duration,
            audioFilename: audioFilename,
            transcriptionModel: transcriptionModel
        )

        if let assets {
            segment.assetsJSON = assets.toJSON()
        }

        try await db.write { db in
            try segment.save(db)
        }

        log.info("📎 Added segment \(segmentIndex) to memo \(parentId.uuidString.prefix(8))")

        // Refresh parent aggregates
        try await refreshParentAggregates(memoId: parentId)

        return segment
    }

    /// Recalculate parent memo's text and duration from all its segments.
    func refreshParentAggregates(memoId: UUID) async throws {
        let db = try await db()
        let segments = try await fetchSegments(forNoteId: memoId)

        guard !segments.isEmpty else {
            log.warning("refreshParentAggregates: no segments found for memo \(memoId.uuidString.prefix(8))")
            return
        }

        let combinedText = segments
            .compactMap { $0.text }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let totalDuration = segments.reduce(0.0) { $0 + $1.duration }

        try await db.write { db in
            try db.execute(
                sql: """
                    UPDATE recordings
                    SET text = ?, duration = ?, lastModified = ?
                    WHERE id = ?
                    """,
                arguments: [combinedText, totalDuration, Date(), memoId]
            )
        }

        log.info("📊 Refreshed aggregates for memo \(memoId.uuidString.prefix(8)): \(segments.count) segments, \(String(format: "%.1f", totalDuration))s total")
    }
}

enum RepositoryError: LocalizedError {
    case notFound(UUID)
    case invalidOperation(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let id): return "Recording not found: \(id)"
        case .invalidOperation(let msg): return msg
        }
    }
}

// MARK: - Content History (append-only edit log)

extension TalkieObjectRepository {

    /// Append a content snapshot. Never updates, never deletes — append only.
    func appendContentSnapshot(
        recordingId: UUID,
        title: String?,
        text: String,
        source: ContentSnapshot.Source
    ) async throws {
        let db = try await db()
        let snapshot = ContentSnapshot(
            recordingId: recordingId,
            title: title,
            text: text,
            source: source
        )
        try await db.write { db in
            try snapshot.insert(db)
        }
    }

    /// Fetch content history for a recording, newest first.
    func fetchContentHistory(for recordingId: UUID, limit: Int = 50) async throws -> [ContentSnapshot] {
        let db = try await db()
        return try await db.read { db in
            try ContentSnapshot
                .filter(ContentSnapshot.Columns.recordingId == recordingId)
                .order(ContentSnapshot.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Get the previous content snapshot (for undo). Returns the one before the latest.
    func previousContentSnapshot(for recordingId: UUID) async throws -> ContentSnapshot? {
        let db = try await db()
        return try await db.read { db in
            try ContentSnapshot
                .filter(ContentSnapshot.Columns.recordingId == recordingId)
                .order(ContentSnapshot.Columns.createdAt.desc)
                .limit(1, offset: 1)
                .fetchOne(db)
        }
    }

    /// Undo to the previous snapshot. Appends a new "undo" snapshot and updates the recording.
    func undoContent(for recordingId: UUID) async throws -> ContentSnapshot? {
        guard let previous = try await previousContentSnapshot(for: recordingId) else {
            return nil
        }

        // Append an undo snapshot (the log stays append-only)
        try await appendContentSnapshot(
            recordingId: recordingId,
            title: previous.title,
            text: previous.text,
            source: .undo
        )

        // Update the recording's current content
        try await updateTitleAndText(
            id: recordingId,
            title: previous.title,
            text: previous.text
        )

        return previous
    }
}

// MARK: - Transcript Version Support

extension TalkieObjectRepository {

    /// Fetch transcript versions for a recording
    func fetchTranscriptVersions(for recordingId: UUID) async throws -> [TranscriptVersionModel] {
        let db = try await db()

        return try await db.read { db in
            try TranscriptVersionModel
                .filter(TranscriptVersionModel.Columns.memoId == recordingId)
                .order(TranscriptVersionModel.Columns.version.desc)
                .fetchAll(db)
        }
    }

    /// Save a new transcript version for a recording
    func saveTranscriptVersion(
        for recordingId: UUID,
        content: String,
        sourceType: TranscriptVersionModel.SourceType,
        engine: String? = nil
    ) async throws {
        let db = try await db()

        try await db.write { db in
            // Get next version number
            let maxVersion = try TranscriptVersionModel
                .filter(TranscriptVersionModel.Columns.memoId == recordingId)
                .select(max(TranscriptVersionModel.Columns.version))
                .fetchOne(db) ?? 0

            let version = TranscriptVersionModel(
                memoId: recordingId,
                version: maxVersion + 1,
                content: content,
                sourceType: sourceType.rawValue,
                engine: engine
            )
            try version.insert(db)
        }
    }

    /// Fetch workflow runs for a recording
    func fetchWorkflowRuns(for recordingId: UUID) async throws -> [WorkflowRunModel] {
        let db = try await db()

        return try await db.read { db in
            try WorkflowRunModel
                .filter(WorkflowRunModel.Columns.memoId == recordingId)
                .order(WorkflowRunModel.Columns.runDate.desc)
                .fetchAll(db)
        }
    }
}

// MARK: - Migration Support

extension TalkieObjectRepository {

    /// Import a MemoModel into the recordings table
    /// Preserves original audioFilePath as audioFilename (no renaming)
    func importMemo(_ memo: MemoModel) async throws {
        let recording = TalkieObject(from: memo)
        try await saveRecording(recording, trackSyncChanges: false)
    }

    /// Import a LiveDictation into the recordings table
    /// Skips import if a dictation with the same timestamp already exists
    /// Uses atomic check-and-insert to prevent race conditions
    /// Preserves original audioFilename (no renaming)
    func importDictation(_ dictation: LiveDictation) async throws {
        let db = try await db()

        // Generate recording ID
        let recordingID = UUID()

        // Atomic check-and-insert in single write transaction
        let wasInserted = try await db.write { db -> Bool in
            // Check if a dictation with this exact timestamp already exists
            let existingCount = try TalkieObject
                .filter(TalkieObject.Columns.type == TalkieObjectType.dictation.rawValue)
                .filter(TalkieObject.Columns.source == RecordingSource.live.rawValue)
                .filter(TalkieObject.Columns.createdAt == dictation.createdAt)
                .fetchCount(db)

            if existingCount > 0 {
                return false  // Already exists, skip
            }

            // Insert new recording - preserves original audioFilename
            var recording = TalkieObject(from: dictation, withID: recordingID)
            try recording.insert(db)
            return true
        }

        if wasInserted {
            log.info("💾 Imported dictation (id: \(recordingID), audioFilename: \(dictation.audioFilename ?? "nil"))")
        } else {
            log.debug("⏭️ Skipping duplicate dictation import (createdAt: \(dictation.createdAt))")
        }
    }

    /// Bulk import memos (for migration)
    func importMemos(_ memos: [MemoModel]) async throws {
        let recordings = memos.map { TalkieObject(from: $0) }
        try await saveRecordings(recordings, trackSyncChanges: false)
    }

    /// Repair recordings with missing audioFilename by scanning audio directory
    /// Matches recordings by ID pattern in filename
    /// Returns the number of records repaired
    func repairMissingAudioFilenames() async throws -> Int {
        let db = try await db()

        // Get all audio files in the audio directory
        let audioFiles = AudioStorage.allFilenames()

        // Build a lookup map: UUID string prefix -> full filename
        var audioFileMap: [String: String] = [:]
        for filename in audioFiles {
            // Extract UUID from filename patterns like "recording_UUID.m4a" or "UUID.m4a"
            let components = filename.replacingOccurrences(of: ".m4a", with: "")
                .replacingOccurrences(of: "recording_", with: "")
                .split(separator: "_")
            if let firstPart = components.first {
                audioFileMap[String(firstPart)] = filename
            }
        }

        return try await db.write { db in
            // Fetch all recordings where audioFilename is nil
            let recordings = try TalkieObject
                .filter(TalkieObject.Columns.audioFilename == nil)
                .fetchAll(db)

            var repairedCount = 0

            for var recording in recordings {
                // Try to match by recording ID
                let idStr = recording.id.uuidString
                if let audioFilename = audioFileMap[idStr] ?? audioFileMap[idStr.lowercased()] {
                    recording.audioFilename = audioFilename
                    try recording.update(db)
                    repairedCount += 1
                    log.debug("🔧 Repaired audioFilename for recording \(recording.id.uuidString.prefix(8)) -> \(audioFilename)")
                }
            }

            if repairedCount > 0 {
                log.info("🔧 Repaired \(repairedCount) recordings with missing audioFilename")
            }

            return repairedCount
        }
    }
}

// MARK: - Sync Tracking

private extension TalkieObjectRepository {
    func trackSyncChange(_ change: PendingSyncChange) async {
        do {
            switch change.operation {
            case .create:
                try await ChangeTracker.shared.logCreate(memoId: change.memoId)
            case .update:
                try await ChangeTracker.shared.logUpdate(memoId: change.memoId)
            case .delete:
                try await ChangeTracker.shared.logDelete(memoId: change.memoId)
            }
        } catch {
            log.warning("⚠️ Failed to track sync change (\(change.operation)) for memo \(change.memoId.uuidString.prefix(8)): \(error.localizedDescription)")
        }
    }
}

// MARK: - Dictation Stats (replaces LiveDatabase stats methods)

extension TalkieObjectRepository {

    /// Count dictations from last 7 days
    func countDictationsThisWeek() async throws -> Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let db = try await db()

        return try await db.read { db in
            try TalkieObject
                .filter(TalkieObject.Columns.type == TalkieObjectType.dictation.rawValue)
                .filter(TalkieObject.Columns.deletedAt == nil)
                .filter(TalkieObject.Columns.createdAt >= weekAgo)
                .fetchCount(db)
        }
    }

    /// Sum of all word counts for dictations (computed from text)
    func totalDictationWords() async throws -> Int {
        let db = try await db()

        return try await db.read { db in
            // Fetch only text column as strings (not full TalkieObject structs)
            let request = TalkieObject
                .filter(TalkieObject.Columns.type == TalkieObjectType.dictation.rawValue)
                .filter(TalkieObject.Columns.deletedAt == nil)
                .select(TalkieObject.Columns.text)

            let texts = try String.fetchAll(db, request)

            return texts.reduce(0) { total, text in
                total + text.split(separator: " ").count
            }
        }
    }

    /// Calculate current streak (consecutive days with dictations)
    func calculateDictationStreak() async throws -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yearAgo = calendar.date(byAdding: .day, value: -365, to: today) ?? today

        let db = try await db()

        let daysWithDictations: Set<Date> = try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT date(createdAt, 'localtime') as day
                    FROM recordings
                    WHERE type = 'dictation' AND deletedAt IS NULL AND createdAt >= ?
                    """,
                arguments: [yearAgo]
            )

            var dates: Set<Date> = []
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"

            for row in rows {
                if let dayStr = row["day"] as? String,
                   let date = formatter.date(from: dayStr) {
                    dates.insert(calendar.startOfDay(for: date))
                }
            }
            return dates
        }

        // Count consecutive days from today (or yesterday if no activity today)
        var checkDate = today
        if !daysWithDictations.contains(today) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
            checkDate = yesterday
        }

        var streak = 0
        while daysWithDictations.contains(checkDate) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
            if streak > 365 { break }
        }
        return streak
    }

    /// Top apps by dictation count
    func topDictationApps(limit: Int = 5) async throws -> [(name: String, bundleID: String?, count: Int)] {
        let db = try await db()

        return try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT
                        json_extract(metadataJSON, '$.app.name') as appName,
                        json_extract(metadataJSON, '$.app.bundleId') as appBundleID,
                        COUNT(*) as cnt
                    FROM recordings
                    WHERE type = 'dictation' AND deletedAt IS NULL
                    AND json_extract(metadataJSON, '$.app.name') IS NOT NULL
                    AND json_extract(metadataJSON, '$.app.name') != ''
                    GROUP BY json_extract(metadataJSON, '$.app.name')
                    ORDER BY cnt DESC
                    LIMIT ?
                    """,
                arguments: [limit]
            )
            return rows.map { row in
                (
                    name: row["appName"] as String? ?? "",
                    bundleID: row["appBundleID"] as String?,
                    count: row["cnt"] as Int? ?? 0
                )
            }
        }
    }

    /// Activity data for contribution graph (counts per day)
    func dictationActivityByDay(days: Int = 91) async throws -> [String: Int] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let db = try await db()

        return try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT date(createdAt, 'localtime') as day, COUNT(*) as cnt
                    FROM recordings
                    WHERE type = 'dictation' AND deletedAt IS NULL AND createdAt >= ?
                    GROUP BY day
                    """,
                arguments: [cutoff]
            )

            var result: [String: Int] = [:]
            for row in rows {
                if let day = row["day"] as? String {
                    let count: Int
                    if let int64 = row["cnt"] as? Int64 {
                        count = Int(int64)
                    } else if let int = row["cnt"] as? Int {
                        count = int
                    } else {
                        continue
                    }
                    result[day] = count
                }
            }
            return result
        }
    }

    /// Count dictations that need transcription retry
    func countDictationsNeedingRetry() async throws -> Int {
        let db = try await db()

        return try await db.read { db in
            try TalkieObject
                .filter(TalkieObject.Columns.type == TalkieObjectType.dictation.rawValue)
                .filter(TalkieObject.Columns.deletedAt == nil)
                .filter(
                    TalkieObject.Columns.transcriptionStatus == RecordingTranscriptionStatus.failed.rawValue ||
                    TalkieObject.Columns.transcriptionStatus == RecordingTranscriptionStatus.pending.rawValue
                )
                .filter(TalkieObject.Columns.audioFilename != nil)
                .fetchCount(db)
        }
    }

    /// Count queued dictations (created in Talkie view, not yet pasted)
    func countQueuedDictations() async throws -> Int {
        let db = try await db()

        return try await db.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM recordings
                    WHERE type = 'dictation' AND deletedAt IS NULL
                    AND json_extract(metadataJSON, '$.queue.createdInTalkieView') = 1
                    AND json_extract(metadataJSON, '$.queue.pasteTimestamp') IS NULL
                    AND (json_extract(metadataJSON, '$.promotion.status') IS NULL
                         OR json_extract(metadataJSON, '$.promotion.status') = 'none')
                    """
            ) ?? 0
        }
    }

    /// Fetch recent dictations
    func fetchRecentDictations(limit: Int = 100) async throws -> [TalkieObject] {
        try await fetchByType(.dictation, limit: limit)
    }

    /// Fetch dictations since a given date (for incremental updates)
    func fetchDictationsSince(date: Date) async throws -> [TalkieObject] {
        let db = try await db()

        return try await db.read { db in
            try TalkieObject
                .filter(TalkieObject.Columns.type == TalkieObjectType.dictation.rawValue)
                .filter(TalkieObject.Columns.deletedAt == nil)
                .filter(TalkieObject.Columns.createdAt > date)
                .order(TalkieObject.Columns.createdAt.asc)
                .fetchAll(db)
        }
    }

    /// Search dictations by text
    func searchDictations(query: String, limit: Int = 50) async throws -> [TalkieObject] {
        guard !query.isEmpty else {
            return try await fetchRecentDictations(limit: limit)
        }

        let db = try await db()

        return try await db.read { db in
            try TalkieObject
                .filter(TalkieObject.Columns.type == TalkieObjectType.dictation.rawValue)
                .filter(TalkieObject.Columns.deletedAt == nil)
                .filter(TalkieObject.Columns.text.like("%\(query)%"))
                .order(TalkieObject.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Fetch all dictations (for migration/repair)
    func fetchAllDictations() async throws -> [TalkieObject] {
        let db = try await db()

        return try await db.read { db in
            try TalkieObject
                .filter(TalkieObject.Columns.type == TalkieObjectType.dictation.rawValue)
                .filter(TalkieObject.Columns.deletedAt == nil)
                .order(TalkieObject.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }
}
