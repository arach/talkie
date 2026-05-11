//
//  MemoRecord.swift
//  TalkieKit
//
//  Database record for voice memos - shared between Talkie and TalkieSync.
//  This is the canonical schema definition for the voice_memos table.
//
//  Design:
//  - Pure data struct, no UI dependencies
//  - GRDB FetchableRecord + PersistableRecord for database operations
//  - Factory methods for creating from different sources (CloudKit, Live, etc.)
//  - Talkie's MemoModel builds on top of this for UI-specific features
//

import Foundation
import GRDB

// MARK: - MemoRecord

/// Database record for voice memos
/// Shared by Talkie (UI) and TalkieSync (sync service)
public struct MemoRecord: Codable, Sendable, Identifiable, Hashable {

    // MARK: - Core Properties

    public var id: UUID
    public var createdAt: Date
    public var lastModified: Date
    public var title: String?
    public var duration: Double
    public var sortOrder: Int

    // MARK: - Content

    public var transcription: String?
    public var notes: String?
    public var summary: String?
    public var tasks: String?
    public var reminders: String?

    // MARK: - Audio

    /// Relative path to audio file
    public var audioFilePath: String?
    /// Binary waveform data for visualization
    public var waveformData: Data?

    // MARK: - Processing State

    public var isTranscribing: Bool
    public var isProcessingSummary: Bool
    public var isProcessingTasks: Bool
    public var isProcessingReminders: Bool
    public var autoProcessed: Bool

    // MARK: - Provenance

    /// Device identifier (e.g., "mac-MacBook Pro", "live-auto", or iPhone device name)
    public var originDeviceId: String?
    public var macReceivedAt: Date?

    // MARK: - Sync

    public var cloudSyncedAt: Date?

    // MARK: - Soft Delete

    public var deletedAt: Date?

    // MARK: - Workflows

    public var pendingWorkflowIds: String?

    // MARK: - Interstitial

    public var revisionHistoryJSON: String?

    // MARK: - Initializer

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        lastModified: Date = Date(),
        title: String? = nil,
        duration: Double = 0,
        sortOrder: Int = 0,
        transcription: String? = nil,
        notes: String? = nil,
        summary: String? = nil,
        tasks: String? = nil,
        reminders: String? = nil,
        audioFilePath: String? = nil,
        waveformData: Data? = nil,
        isTranscribing: Bool = false,
        isProcessingSummary: Bool = false,
        isProcessingTasks: Bool = false,
        isProcessingReminders: Bool = false,
        autoProcessed: Bool = false,
        originDeviceId: String? = nil,
        macReceivedAt: Date? = nil,
        cloudSyncedAt: Date? = nil,
        deletedAt: Date? = nil,
        pendingWorkflowIds: String? = nil,
        revisionHistoryJSON: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.lastModified = lastModified
        self.title = title
        self.duration = duration
        self.sortOrder = sortOrder
        self.transcription = transcription
        self.notes = notes
        self.summary = summary
        self.tasks = tasks
        self.reminders = reminders
        self.audioFilePath = audioFilePath
        self.waveformData = waveformData
        self.isTranscribing = isTranscribing
        self.isProcessingSummary = isProcessingSummary
        self.isProcessingTasks = isProcessingTasks
        self.isProcessingReminders = isProcessingReminders
        self.autoProcessed = autoProcessed
        self.originDeviceId = originDeviceId
        self.macReceivedAt = macReceivedAt
        self.cloudSyncedAt = cloudSyncedAt
        self.deletedAt = deletedAt
        self.pendingWorkflowIds = pendingWorkflowIds
        self.revisionHistoryJSON = revisionHistoryJSON
    }
}

// MARK: - GRDB Record

extension MemoRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "voice_memos"

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let createdAt = Column(CodingKeys.createdAt)
        public static let lastModified = Column(CodingKeys.lastModified)
        public static let title = Column(CodingKeys.title)
        public static let duration = Column(CodingKeys.duration)
        public static let sortOrder = Column(CodingKeys.sortOrder)
        public static let transcription = Column(CodingKeys.transcription)
        public static let notes = Column(CodingKeys.notes)
        public static let summary = Column(CodingKeys.summary)
        public static let tasks = Column(CodingKeys.tasks)
        public static let reminders = Column(CodingKeys.reminders)
        public static let audioFilePath = Column(CodingKeys.audioFilePath)
        public static let waveformData = Column(CodingKeys.waveformData)
        public static let isTranscribing = Column(CodingKeys.isTranscribing)
        public static let isProcessingSummary = Column(CodingKeys.isProcessingSummary)
        public static let isProcessingTasks = Column(CodingKeys.isProcessingTasks)
        public static let isProcessingReminders = Column(CodingKeys.isProcessingReminders)
        public static let autoProcessed = Column(CodingKeys.autoProcessed)
        public static let originDeviceId = Column(CodingKeys.originDeviceId)
        public static let macReceivedAt = Column(CodingKeys.macReceivedAt)
        public static let cloudSyncedAt = Column(CodingKeys.cloudSyncedAt)
        public static let deletedAt = Column(CodingKeys.deletedAt)
        public static let pendingWorkflowIds = Column(CodingKeys.pendingWorkflowIds)
        public static let revisionHistoryJSON = Column(CodingKeys.revisionHistoryJSON)
    }
}

// MARK: - Database Operations

extension MemoRecord {

    /// Upsert a record (insert or update based on ID)
    /// Used by sync operations to merge incoming data
    public func upsert(in db: Database) throws {
        // Check if record exists
        if try MemoRecord.fetchOne(db, key: id) != nil {
            // Update existing - preserve local-only fields
            try db.execute(
                sql: """
                    UPDATE voice_memos SET
                        createdAt = ?,
                        title = ?,
                        lastModified = ?,
                        duration = ?,
                        sortOrder = ?,
                        transcription = ?,
                        notes = ?,
                        summary = ?,
                        tasks = ?,
                        reminders = ?,
                        audioFilePath = ?,
                        waveformData = ?,
                        isTranscribing = ?,
                        isProcessingSummary = ?,
                        isProcessingTasks = ?,
                        isProcessingReminders = ?,
                        autoProcessed = ?,
                        originDeviceId = ?,
                        cloudSyncedAt = ?,
                        macReceivedAt = ?,
                        deletedAt = ?,
                        pendingWorkflowIds = ?,
                        revisionHistoryJSON = ?
                    WHERE id = ?
                    """,
                arguments: [
                    createdAt,
                    title,
                    lastModified,
                    duration,
                    sortOrder,
                    transcription,
                    notes,
                    summary,
                    tasks,
                    reminders,
                    audioFilePath,
                    waveformData,
                    isTranscribing,
                    isProcessingSummary,
                    isProcessingTasks,
                    isProcessingReminders,
                    autoProcessed,
                    originDeviceId,
                    cloudSyncedAt,
                    macReceivedAt,
                    deletedAt,
                    pendingWorkflowIds,
                    revisionHistoryJSON,
                    id
                ]
            )
        } else {
            // Insert new record
            try insert(db)
        }
    }

    /// Sync-safe upsert: only updates sync-relevant fields, preserving local-only state.
    ///
    /// Preserved fields (NOT overwritten by sync):
    /// - `waveformData` — locally generated, not synced
    /// - `isTranscribing/isProcessingSummary/isProcessingTasks/isProcessingReminders` — local processing state
    /// - `autoProcessed` — local processing flag
    /// - `pendingWorkflowIds` — local workflow state
    /// - `revisionHistoryJSON` — local UI state
    /// - `audioFilePath` — preserved when remote value is NULL (via COALESCE)
    /// - `summary`, `tasks`, `reminders` — generated locally by auto-processing,
    ///   preserved when remote value is NULL (via COALESCE)
    public func syncUpsert(in db: Database) throws {
        if try MemoRecord.fetchOne(db, key: id) != nil {
            try db.execute(
                sql: """
                    UPDATE voice_memos SET
                        createdAt = ?,
                        title = ?,
                        lastModified = ?,
                        duration = ?,
                        sortOrder = ?,
                        transcription = ?,
                        notes = ?,
                        summary = COALESCE(?, summary),
                        tasks = COALESCE(?, tasks),
                        reminders = COALESCE(?, reminders),
                        audioFilePath = COALESCE(?, audioFilePath),
                        originDeviceId = ?,
                        cloudSyncedAt = ?,
                        macReceivedAt = ?,
                        deletedAt = ?
                    WHERE id = ?
                    """,
                arguments: [
                    createdAt,
                    title,
                    lastModified,
                    duration,
                    sortOrder,
                    transcription,
                    notes,
                    summary,
                    tasks,
                    reminders,
                    audioFilePath,
                    originDeviceId,
                    cloudSyncedAt,
                    macReceivedAt,
                    deletedAt,
                    id
                ]
            )
        } else {
            try insert(db)
        }
    }

    /// Fetch by ID
    public static func fetch(id: UUID, from db: Database) throws -> MemoRecord? {
        try MemoRecord.fetchOne(db, key: id)
    }

    /// Fetch all records, ordered by creation date (newest first)
    public static func fetchAll(from db: Database) throws -> [MemoRecord] {
        try MemoRecord
            .order(Columns.createdAt.desc)
            .fetchAll(db)
    }

    /// Fetch all IDs (for sync comparison)
    public static func fetchAllIds(from db: Database) throws -> Set<UUID> {
        let ids = try UUID.fetchAll(db, sql: "SELECT id FROM voice_memos")
        return Set(ids)
    }
}

// MARK: - Factory: CloudKit / Core Data

extension MemoRecord {

    /// Create from Core Data managed object (CloudKit sync)
    /// - Parameter cdObject: NSManagedObject from Core Data's VoiceMemo entity
    /// - Returns: MemoRecord ready for GRDB insertion
    public static func fromCoreData(_ cdObject: NSObject) -> MemoRecord? {
        // Use KVC to extract values (works with NSManagedObject)
        guard let id = cdObject.value(forKey: "id") as? UUID else {
            return nil
        }

        let now = Date()

        return MemoRecord(
            id: id,
            createdAt: cdObject.value(forKey: "createdAt") as? Date ?? now,
            lastModified: cdObject.value(forKey: "lastModified") as? Date ?? now,
            title: cdObject.value(forKey: "title") as? String,
            duration: cdObject.value(forKey: "duration") as? Double ?? 0,
            sortOrder: cdObject.value(forKey: "sortOrder") as? Int ?? 0,
            transcription: cdObject.value(forKey: "transcription") as? String,
            notes: cdObject.value(forKey: "notes") as? String,
            summary: cdObject.value(forKey: "summary") as? String,
            tasks: cdObject.value(forKey: "tasks") as? String,
            reminders: cdObject.value(forKey: "reminders") as? String,
            audioFilePath: cdObject.value(forKey: "fileURL") as? String,  // Core Data uses "fileURL"
            waveformData: cdObject.value(forKey: "waveformData") as? Data,
            isTranscribing: cdObject.value(forKey: "isTranscribing") as? Bool ?? false,
            isProcessingSummary: cdObject.value(forKey: "isProcessingSummary") as? Bool ?? false,
            isProcessingTasks: cdObject.value(forKey: "isProcessingTasks") as? Bool ?? false,
            isProcessingReminders: cdObject.value(forKey: "isProcessingReminders") as? Bool ?? false,
            autoProcessed: cdObject.value(forKey: "autoProcessed") as? Bool ?? false,
            originDeviceId: cdObject.value(forKey: "originDeviceId") as? String,
            macReceivedAt: cdObject.value(forKey: "macReceivedAt") as? Date ?? now,
            cloudSyncedAt: cdObject.value(forKey: "cloudSyncedAt") as? Date,
            deletedAt: nil,
            pendingWorkflowIds: cdObject.value(forKey: "pendingWorkflowIds") as? String,
            revisionHistoryJSON: nil
        )
    }
}

// MARK: - Validation

extension MemoRecord {

    /// Validate record before insertion
    /// Returns nil if valid, error message if invalid
    public func validate() -> String? {
        // ID is required (should always be set)
        if id == UUID(uuidString: "00000000-0000-0000-0000-000000000000") {
            return "Invalid UUID"
        }

        // Duration should be non-negative
        if duration < 0 {
            return "Duration cannot be negative"
        }

        return nil
    }
}
