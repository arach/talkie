//
//  TalkieObject.swift
//  TalkieKit
//
//  Unified content model — the core data primitive.
//  Single source of truth for all voice content objects.
//  Shared across all targets: main app, Agent, CLI.
//

import Foundation
import GRDB

// MARK: - TalkieObject Model

public struct TalkieObject: Identifiable, Codable, Hashable, Sendable {
    // MARK: - Identity

    public let id: UUID
    public var type: TalkieObjectType

    // MARK: - Content

    public var text: String?           // Transcript text
    public var title: String?          // User-set title (memos only)
    public var notes: String?          // User annotations (memos only)

    // MARK: - Audio

    public var duration: Double        // Duration in seconds
    public var audioFilename: String?  // Legacy: filename in Audio directory (new recordings use {id}.m4a)

    // MARK: - Timestamps

    public var createdAt: Date
    public var lastModified: Date?
    public var deletedAt: Date?        // Soft delete (memos only)

    // MARK: - Origin (immutable after creation)

    public let source: RecordingSource
    public let sourceDeviceId: String?

    // MARK: - Promotion

    public var promotedAt: Date?       // When dictation became memo (nil if always memo)

    // MARK: - Transcription

    public var transcriptionStatus: RecordingTranscriptionStatus
    public var transcriptionError: String?
    public var transcriptionModel: String?

    // MARK: - AI Processing (memos only)

    public var summary: String?
    public var tasks: String?
    public var reminders: String?
    public var isProcessingSummary: Bool
    public var isProcessingTasks: Bool
    public var isProcessingReminders: Bool
    public var autoProcessed: Bool

    // MARK: - Sync (memos only)

    public var cloudSyncedAt: Date?

    // MARK: - Workflows

    public var pendingWorkflowIds: String?

    // MARK: - Assets (consolidated JSON blob)

    public var assetsJSON: String?         // JSON-encoded TalkieObjectAssets

    // MARK: - Segment (child of a note)

    public var parentId: UUID?         // Links segment → parent note
    public var segmentIndex: Int?      // Order within note (0-based)

    // MARK: - Metadata (dictation context)

    public var metadataJSON: String?   // Stored as JSON string in DB

    // MARK: - Initializer

    public init(
        id: UUID = UUID(),
        type: TalkieObjectType = .dictation,
        text: String? = nil,
        title: String? = nil,
        notes: String? = nil,
        duration: Double = 0,
        audioFilename: String? = nil,
        createdAt: Date = Date(),
        lastModified: Date? = nil,
        deletedAt: Date? = nil,
        source: RecordingSource = .mac,
        sourceDeviceId: String? = nil,
        promotedAt: Date? = nil,
        transcriptionStatus: RecordingTranscriptionStatus = .success,
        transcriptionError: String? = nil,
        transcriptionModel: String? = nil,
        summary: String? = nil,
        tasks: String? = nil,
        reminders: String? = nil,
        isProcessingSummary: Bool = false,
        isProcessingTasks: Bool = false,
        isProcessingReminders: Bool = false,
        autoProcessed: Bool = false,
        cloudSyncedAt: Date? = nil,
        pendingWorkflowIds: String? = nil,
        assetsJSON: String? = nil,
        parentId: UUID? = nil,
        segmentIndex: Int? = nil,
        metadataJSON: String? = nil
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.title = title
        self.notes = notes
        self.duration = duration
        self.audioFilename = audioFilename
        self.createdAt = createdAt
        self.lastModified = lastModified
        self.deletedAt = deletedAt
        self.source = source
        self.sourceDeviceId = sourceDeviceId
        self.promotedAt = promotedAt
        self.transcriptionStatus = transcriptionStatus
        self.transcriptionError = transcriptionError
        self.transcriptionModel = transcriptionModel
        self.summary = summary
        self.tasks = tasks
        self.reminders = reminders
        self.isProcessingSummary = isProcessingSummary
        self.isProcessingTasks = isProcessingTasks
        self.isProcessingReminders = isProcessingReminders
        self.autoProcessed = autoProcessed
        self.cloudSyncedAt = cloudSyncedAt
        self.pendingWorkflowIds = pendingWorkflowIds
        self.assetsJSON = assetsJSON
        self.parentId = parentId
        self.segmentIndex = segmentIndex
        self.metadataJSON = metadataJSON
    }
}

// MARK: - GRDB Record

extension TalkieObject: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "recordings"

    /// Use INSERT OR REPLACE to handle unique constraint conflicts gracefully
    public static let persistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .replace,
        update: .replace
    )

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let type = Column(CodingKeys.type)
        public static let text = Column(CodingKeys.text)
        public static let title = Column(CodingKeys.title)
        public static let notes = Column(CodingKeys.notes)
        public static let duration = Column(CodingKeys.duration)
        public static let audioFilename = Column(CodingKeys.audioFilename)
        public static let createdAt = Column(CodingKeys.createdAt)
        public static let lastModified = Column(CodingKeys.lastModified)
        public static let deletedAt = Column(CodingKeys.deletedAt)
        public static let source = Column(CodingKeys.source)
        public static let sourceDeviceId = Column(CodingKeys.sourceDeviceId)
        public static let promotedAt = Column(CodingKeys.promotedAt)
        public static let transcriptionStatus = Column(CodingKeys.transcriptionStatus)
        public static let transcriptionError = Column(CodingKeys.transcriptionError)
        public static let transcriptionModel = Column(CodingKeys.transcriptionModel)
        public static let summary = Column(CodingKeys.summary)
        public static let tasks = Column(CodingKeys.tasks)
        public static let reminders = Column(CodingKeys.reminders)
        public static let isProcessingSummary = Column(CodingKeys.isProcessingSummary)
        public static let isProcessingTasks = Column(CodingKeys.isProcessingTasks)
        public static let isProcessingReminders = Column(CodingKeys.isProcessingReminders)
        public static let autoProcessed = Column(CodingKeys.autoProcessed)
        public static let cloudSyncedAt = Column(CodingKeys.cloudSyncedAt)
        public static let pendingWorkflowIds = Column(CodingKeys.pendingWorkflowIds)
        public static let assetsJSON = Column(CodingKeys.assetsJSON)
        public static let parentId = Column(CodingKeys.parentId)
        public static let segmentIndex = Column(CodingKeys.segmentIndex)
        public static let metadataJSON = Column(CodingKeys.metadataJSON)
    }
}

// MARK: - Computed Properties

extension TalkieObject {

    // MARK: Type Checks

    public var isMemo: Bool { type == .memo }
    public var isDictation: Bool { type == .dictation }
    public var isNote: Bool { type == .note }
    public var isSegment: Bool { type == .segment }
    public var isSelection: Bool { type == .selection }
    public var wasPromoted: Bool { promotedAt != nil }
    public var isDeleted: Bool { deletedAt != nil }

    // MARK: Audio

    /// Whether this recording has an audio file
    public var hasAudio: Bool {
        audioFilename != nil
    }

    // MARK: Display

    /// Display title (falls back to timestamp if no title)
    public var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        return TalkieDate.displayDateTime(createdAt)
    }

    /// Word count from transcript
    public var wordCount: Int {
        guard let transcript = text, !transcript.isEmpty else { return 0 }
        return transcript.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    /// Preview snippet of transcript (first ~80 chars)
    public var transcriptPreview: String? {
        guard let transcript = text, !transcript.isEmpty else { return nil }
        let cleaned = transcript
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= 80 {
            return cleaned
        }
        let truncated = String(cleaned.prefix(80))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        return truncated + "..."
    }

    // MARK: Processing State

    public var isProcessing: Bool {
        isProcessingSummary || isProcessingTasks || isProcessingReminders
    }

    public var isTranscribing: Bool {
        transcriptionStatus == .pending
    }

    // MARK: Metadata

    /// Parsed assets (computed from JSON)
    public var assets: TalkieObjectAssets? {
        TalkieObjectAssets.from(json: assetsJSON)
    }

    /// Parsed word-level timestamps
    public var timedTranscription: TimedTranscription? {
        assets?.segments
    }

    /// Parsed screenshot metadata
    public var screenshots: [RecordingScreenshot] {
        assets?.screenshots ?? []
    }

    /// Parsed clip metadata
    public var clips: [RecordingClip] {
        assets?.clips ?? []
    }

    /// Parsed file attachments
    public var attachments: [RecordingAttachment] {
        assets?.attachments ?? []
    }

    /// Parsed metadata (computed from JSON)
    public var metadata: RecordingMetadata? {
        RecordingMetadata.from(json: metadataJSON)
    }

    /// Whether this recording was refined by a context rule
    public var wasRefined: Bool {
        metadata?.refinement != nil
    }

    /// App context (for dictations)
    public var appContext: AppContext? {
        metadata?.app
    }

    /// Performance metrics (for dictations)
    public var performanceMetrics: PerformanceMetrics? {
        metadata?.performance
    }
}

// MARK: - Factory Methods

extension TalkieObject {

    /// Create a new memo recording
    public static func newMemo(
        id: UUID = UUID(),
        text: String? = nil,
        title: String? = nil,
        duration: Double = 0,
        source: RecordingSource = .mac,
        sourceDeviceId: String? = nil
    ) -> TalkieObject {
        TalkieObject(
            id: id,
            type: .memo,
            text: text,
            title: title,
            duration: duration,
            source: source,
            sourceDeviceId: sourceDeviceId,
            transcriptionStatus: text != nil ? .success : .pending
        )
    }

    /// Create a new dictation recording
    public static func newDictation(
        id: UUID = UUID(),
        text: String,
        duration: Double = 0,
        transcriptionModel: String? = nil,
        metadata: RecordingMetadata? = nil
    ) -> TalkieObject {
        TalkieObject(
            id: id,
            type: .dictation,
            text: text,
            duration: duration,
            source: .live,
            transcriptionStatus: .success,
            transcriptionModel: transcriptionModel,
            metadataJSON: metadata?.toJSON()
        )
    }

    /// Create a new note recording (text-only, no audio)
    public static func newNote(
        id: UUID = UUID(),
        text: String,
        title: String? = nil
    ) -> TalkieObject {
        TalkieObject(
            id: id,
            type: .note,
            text: text,
            title: title,
            duration: 0,
            source: .mac,
            transcriptionStatus: .success
        )
    }

    /// Create a new capture (screenshot-first TalkieObject, optional canonical text + provenance)
    public static func newCapture(
        id: UUID = UUID(),
        text: String = "",
        title: String? = nil
    ) -> TalkieObject {
        TalkieObject(
            id: id,
            type: .capture,
            text: text,
            title: title,
            duration: 0,
            source: .mac,
            transcriptionStatus: .success
        )
    }

    /// Create a new segment recording (child of a note)
    public static func newSegment(
        parentId: UUID,
        segmentIndex: Int,
        text: String,
        duration: Double,
        audioFilename: String?,
        transcriptionModel: String?
    ) -> TalkieObject {
        TalkieObject(
            id: UUID(),
            type: .segment,
            text: text,
            duration: duration,
            audioFilename: audioFilename,
            source: .mac,
            transcriptionStatus: .success,
            transcriptionModel: transcriptionModel,
            parentId: parentId,
            segmentIndex: segmentIndex
        )
    }

    /// Promote this dictation to a memo
    public mutating func promoteToMemo() {
        guard type == .dictation else { return }
        type = .memo
        promotedAt = Date()
        cloudSyncedAt = nil // Trigger sync on next pass
    }

    /// Promote this note to a memo (enables CloudKit sync)
    public mutating func promoteNoteToMemo() {
        guard type == .note else { return }
        type = .memo
        promotedAt = Date()
        cloudSyncedAt = nil // Trigger sync on next pass
    }
}
