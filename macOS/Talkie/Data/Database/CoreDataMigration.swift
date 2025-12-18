//
//  CoreDataMigration.swift
//  Talkie
//
//  Migration tool: Core Data → GRDB
//  Safely migrates all existing memos, transcripts, and workflows
//

import Foundation
import CoreData
import GRDB

// MARK: - Migration Manager

@MainActor
final class CoreDataMigration {
    private let coreDataContext: NSManagedObjectContext
    private let repository: GRDBRepository

    init(coreDataContext: NSManagedObjectContext, repository: GRDBRepository = GRDBRepository()) {
        self.coreDataContext = coreDataContext
        self.repository = repository
    }

    // MARK: - Migration

    /// Migrate all data from Core Data to GRDB
    /// Returns: (successCount, failureCount, errors)
    func migrate() async -> (success: Int, failed: Int, errors: [Error]) {
        var successCount = 0
        var failedCount = 0
        var errors: [Error] = []

        print("🚀 Starting Core Data → GRDB migration...")

        do {
            // Fetch all Core Data memos
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "VoiceMemo")
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

            let coreDataMemos = try coreDataContext.fetch(fetchRequest)
            print("📦 Found \(coreDataMemos.count) memos in Core Data")

            // Migrate each memo
            for (index, cdMemo) in coreDataMemos.enumerated() {
                let memoTitle = (cdMemo.value(forKey: "title") as? String) ?? "Untitled"
                let memoId = cdMemo.value(forKey: "id") as? UUID

                do {
                    try await migrateMemo(cdMemo)
                    successCount += 1

                    if (index + 1) % 10 == 0 {
                        print("✅ Migrated \(index + 1)/\(coreDataMemos.count) memos...")
                    }
                } catch {
                    failedCount += 1
                    errors.append(error)
                    print("❌ Failed to migrate memo [\(memoId?.uuidString ?? "NO-ID")] '\(memoTitle)': \(error)")
                }
            }

            print("✨ Migration complete! Success: \(successCount), Failed: \(failedCount)")

        } catch {
            print("💥 Migration failed: \(error)")
            errors.append(error)
        }

        return (successCount, failedCount, errors)
    }

    // MARK: - Migrate Single Memo

    private func migrateMemo(_ cdMemo: NSManagedObject) async throws {
        // Convert Core Data object → Swift struct
        guard let id = cdMemo.value(forKey: "id") as? UUID else {
            throw MigrationError.missingID
        }

        let createdAt = cdMemo.value(forKey: "createdAt") as? Date ?? Date()
        let lastModified = cdMemo.value(forKey: "lastModified") as? Date ?? Date()
        let title = cdMemo.value(forKey: "title") as? String
        let duration = cdMemo.value(forKey: "duration") as? Double ?? 0
        let sortOrder = cdMemo.value(forKey: "sortOrder") as? Int ?? 0
        let transcription = cdMemo.value(forKey: "transcription") as? String
        let notes = cdMemo.value(forKey: "notes") as? String
        let summary = cdMemo.value(forKey: "summary") as? String
        let tasks = cdMemo.value(forKey: "tasks") as? String
        let reminders = cdMemo.value(forKey: "reminders") as? String

        // Audio: Copy file or data
        var audioFilePath: String?
        if let fileURL = cdMemo.value(forKey: "fileURL") as? String {
            // Copy audio file to new storage location
            audioFilePath = try copyAudioFile(from: fileURL, memoId: id)
        } else if let audioData = cdMemo.value(forKey: "audioData") as? Data {
            // Save audio data to file
            audioFilePath = try saveAudioData(audioData, memoId: id)
        }

        let waveformData = cdMemo.value(forKey: "waveformData") as? Data

        let isTranscribing = cdMemo.value(forKey: "isTranscribing") as? Bool ?? false
        let isProcessingSummary = cdMemo.value(forKey: "isProcessingSummary") as? Bool ?? false
        let isProcessingTasks = cdMemo.value(forKey: "isProcessingTasks") as? Bool ?? false
        let isProcessingReminders = cdMemo.value(forKey: "isProcessingReminders") as? Bool ?? false
        let autoProcessed = cdMemo.value(forKey: "autoProcessed") as? Bool ?? false

        let originDeviceId = cdMemo.value(forKey: "originDeviceId") as? String
        let macReceivedAt = cdMemo.value(forKey: "macReceivedAt") as? Date
        let cloudSyncedAt = cdMemo.value(forKey: "cloudSyncedAt") as? Date
        let pendingWorkflowIds = cdMemo.value(forKey: "pendingWorkflowIds") as? String

        // Create Swift struct
        let memo = MemoModel(
            id: id,
            createdAt: createdAt,
            lastModified: lastModified,
            title: title,
            duration: duration,
            sortOrder: sortOrder,
            transcription: transcription,
            notes: notes,
            summary: summary,
            tasks: tasks,
            reminders: reminders,
            audioFilePath: audioFilePath,
            waveformData: waveformData,
            isTranscribing: isTranscribing,
            isProcessingSummary: isProcessingSummary,
            isProcessingTasks: isProcessingTasks,
            isProcessingReminders: isProcessingReminders,
            autoProcessed: autoProcessed,
            originDeviceId: originDeviceId,
            macReceivedAt: macReceivedAt,
            cloudSyncedAt: cloudSyncedAt,
            pendingWorkflowIds: pendingWorkflowIds
        )

        // Save to GRDB
        try await repository.saveMemo(memo)

        // Migrate transcript versions
        if let transcriptVersions = cdMemo.value(forKey: "transcriptVersions") as? Set<NSManagedObject> {
            for cdVersion in transcriptVersions {
                try await migrateTranscriptVersion(cdVersion, memoId: id)
            }
        }

        // Migrate workflow runs
        if let workflowRuns = cdMemo.value(forKey: "workflowRuns") as? Set<NSManagedObject> {
            for cdRun in workflowRuns {
                try await migrateWorkflowRun(cdRun, memoId: id)
            }
        }
    }

    // MARK: - Migrate Relationships

    private func migrateTranscriptVersion(_ cdVersion: NSManagedObject, memoId: UUID) async throws {
        guard let id = cdVersion.value(forKey: "id") as? UUID else {
            throw MigrationError.missingID
        }

        let version = cdVersion.value(forKey: "version") as? Int ?? 1
        let content = cdVersion.value(forKey: "content") as? String ?? ""
        let sourceType = cdVersion.value(forKey: "sourceType") as? String ?? "system_ios"
        let engine = cdVersion.value(forKey: "engine") as? String
        let createdAt = cdVersion.value(forKey: "createdAt") as? Date ?? Date()
        let transcriptionDurationMs = cdVersion.value(forKey: "transcriptionDurationMs") as? Int64 ?? 0

        let transcriptVersion = TranscriptVersionModel(
            id: id,
            memoId: memoId,
            version: version,
            content: content,
            sourceType: sourceType,
            engine: engine,
            createdAt: createdAt,
            transcriptionDurationMs: transcriptionDurationMs
        )

        try await repository.saveTranscriptVersion(transcriptVersion)
    }

    private func migrateWorkflowRun(_ cdRun: NSManagedObject, memoId: UUID) async throws {
        guard let id = cdRun.value(forKey: "id") as? UUID,
              let workflowId = cdRun.value(forKey: "workflowId") as? UUID else {
            throw MigrationError.missingID
        }

        let workflowName = cdRun.value(forKey: "workflowName") as? String ?? "Unnamed Workflow"
        let workflowIcon = cdRun.value(forKey: "workflowIcon") as? String
        let output = cdRun.value(forKey: "output") as? String
        let status = cdRun.value(forKey: "status") as? String ?? "completed"
        let runDate = cdRun.value(forKey: "runDate") as? Date ?? Date()
        let modelId = cdRun.value(forKey: "modelId") as? String
        let providerName = cdRun.value(forKey: "providerName") as? String
        let stepOutputsJSON = cdRun.value(forKey: "stepOutputsJSON") as? String

        let workflowRun = WorkflowRunModel(
            id: id,
            memoId: memoId,
            workflowId: workflowId,
            workflowName: workflowName,
            workflowIcon: workflowIcon,
            output: output,
            status: status,
            runDate: runDate,
            modelId: modelId,
            providerName: providerName,
            stepOutputsJSON: stepOutputsJSON
        )

        try await repository.saveWorkflowRun(workflowRun)
    }

    // MARK: - Audio File Handling

    private func copyAudioFile(from urlString: String, memoId: UUID) throws -> String {
        guard let sourceURL = URL(string: urlString) else {
            throw MigrationError.invalidFileURL
        }

        let audioDir = try audioStorageDirectory()
        let fileName = "\(memoId.uuidString).m4a"
        let destinationURL = audioDir.appendingPathComponent(fileName)

        // Copy file
        if FileManager.default.fileExists(atPath: sourceURL.path) {
            try? FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }

        // Return relative path
        return fileName
    }

    private func saveAudioData(_ data: Data, memoId: UUID) throws -> String {
        let audioDir = try audioStorageDirectory()
        let fileName = "\(memoId.uuidString).m4a"
        let destinationURL = audioDir.appendingPathComponent(fileName)

        try data.write(to: destinationURL)

        return fileName
    }

    private func audioStorageDirectory() throws -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let audioDir = appSupport.appendingPathComponent("Talkie/Audio", isDirectory: true)

        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        return audioDir
    }
}

// MARK: - Errors

enum MigrationError: Error {
    case missingID
    case invalidFileURL
    case audioFileCopyFailed
}
