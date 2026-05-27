//
//  Recording.swift
//  Talkie
//
//  App-specific extensions on TalkieObject.
//  Core model + types live in TalkieKit for cross-target sharing.
//

import Foundation
import SwiftUI
import GRDB
import TalkieKit

// MARK: - GRDB Associations (app-internal models)

extension TalkieObject {
    static let transcriptVersions = hasMany(TranscriptVersionModel.self, key: "recordingId")
    static let workflowRuns = hasMany(WorkflowRunModel.self, key: "recordingId")
}

// MARK: - Audio (depends on AudioStorage)

extension TalkieObject {

    /// URL to audio file (nil if no audio)
    var audioURL: URL? {
        guard let filename = audioFilename else { return nil }
        return AudioStorage.audioDirectory.appendingPathComponent(filename)
    }

    /// Load audio data from file (lazy, for playback)
    var audioData: Data? {
        guard let url = audioURL else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Audio file path - always {id}.m4a (for compatibility)
    var audioFilePath: String? {
        guard hasAudio else { return nil }
        return "\(id.uuidString).m4a"
    }
}

// MARK: - MemoModel Compatibility

extension TalkieObject {

    /// Current transcript (alias for text, for compatibility)
    var currentTranscript: String? { text }

    /// Transcription (alias for text, for compatibility)
    var transcription: String? { text }

    /// Origin device ID (alias for sourceDeviceId, for compatibility)
    var originDeviceId: String? { sourceDeviceId }

    /// Is pending deletion (alias for isDeleted)
    var isPendingDeletion: Bool { isDeleted }

    /// Convert Recording to MemoModel for workflow execution compatibility
    func toMemoModel() -> MemoModel {
        MemoModel(
            id: id,
            createdAt: createdAt,
            lastModified: lastModified ?? createdAt,
            title: title,
            duration: duration,
            sortOrder: 0,
            transcription: text,
            notes: notes,
            summary: summary,
            tasks: tasks,
            reminders: reminders,
            audioFilePath: audioFilePath,
            waveformData: nil,
            isTranscribing: transcriptionStatus == .pending,
            isProcessingSummary: isProcessingSummary,
            isProcessingTasks: isProcessingTasks,
            isProcessingReminders: isProcessingReminders,
            autoProcessed: autoProcessed,
            originDeviceId: sourceDeviceId,
            macReceivedAt: nil,
            cloudSyncedAt: cloudSyncedAt,
            deletedAt: deletedAt,
            pinnedAt: pinnedAt,
            starredAt: starredAt,
            pendingWorkflowIds: pendingWorkflowIds
        )
    }
}

// MARK: - Migration Helpers

extension TalkieObject {

    /// Create from existing MemoModel (for migration)
    init(from memo: MemoModel) {
        let audioFilename = memo.audioFilePath

        self.init(
            id: memo.id,
            type: .memo,
            text: memo.transcription,
            title: memo.title,
            notes: memo.notes,
            duration: memo.duration,
            audioFilename: audioFilename,
            createdAt: memo.createdAt,
            lastModified: memo.lastModified,
            deletedAt: memo.deletedAt,
            pinnedAt: memo.pinnedAt,
            starredAt: memo.starredAt,
            source: RecordingSource.from(originDeviceId: memo.originDeviceId),
            sourceDeviceId: memo.originDeviceId,
            promotedAt: nil,
            transcriptionStatus: memo.derivedTranscriptionStatus,
            transcriptionError: memo.derivedTranscriptionError,
            transcriptionModel: nil,
            summary: memo.summary,
            tasks: memo.tasks,
            reminders: memo.reminders,
            isProcessingSummary: memo.isProcessingSummary,
            isProcessingTasks: memo.isProcessingTasks,
            isProcessingReminders: memo.isProcessingReminders,
            autoProcessed: memo.autoProcessed,
            cloudSyncedAt: memo.cloudSyncedAt,
            pendingWorkflowIds: memo.pendingWorkflowIds,
            metadataJSON: nil
        )
    }

    /// Create from existing LiveDictation (for migration)
    init(from dictation: LiveDictation, withID recordingID: UUID = UUID()) {
        let audioFilename = dictation.audioFilename
        var metadata = RecordingMetadata()
        metadata.app = AppContext(
            bundleId: dictation.appBundleID,
            name: dictation.appName,
            windowTitle: dictation.windowTitle
        )
        metadata.performance = PerformanceMetrics(
            engineMs: dictation.perfEngineMs,
            endToEndMs: dictation.perfEndToEndMs,
            inAppMs: dictation.perfInAppMs,
            sessionId: dictation.sessionID
        )
        metadata.routing = RoutingInfo(
            mode: dictation.mode,
            wasRouted: dictation.pasteTimestamp != nil,
            pasteTimestamp: dictation.pasteTimestamp?.timeIntervalSince1970
        )

        if let existingMeta = dictation.metadata {
            if let browserURL = existingMeta["browserURL"] {
                metadata.context = RichContext(browserURL: browserURL)
            }
        }

        let wasPromoted = dictation.promotionStatus == .memo

        self.init(
            id: recordingID,
            type: wasPromoted ? .memo : .dictation,
            text: dictation.text,
            title: nil,
            notes: nil,
            duration: dictation.durationSeconds ?? 0,
            audioFilename: audioFilename,
            createdAt: dictation.createdAt,
            lastModified: nil,
            deletedAt: nil,
            source: .live,
            sourceDeviceId: "live-auto",
            promotedAt: wasPromoted ? dictation.createdAt : nil,
            transcriptionStatus: RecordingTranscriptionStatus(rawValue: dictation.transcriptionStatus.rawValue) ?? .success,
            transcriptionError: dictation.transcriptionError,
            transcriptionModel: dictation.transcriptionModel,
            summary: nil,
            tasks: nil,
            reminders: nil,
            isProcessingSummary: false,
            isProcessingTasks: false,
            isProcessingReminders: false,
            autoProcessed: false,
            cloudSyncedAt: nil,
            pendingWorkflowIds: nil,
            metadataJSON: metadata.toJSON()
        )
    }
}
