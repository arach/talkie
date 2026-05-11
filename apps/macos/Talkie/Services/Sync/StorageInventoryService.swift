//
//  StorageInventoryService.swift
//  Talkie
//
//  Queries all storage layers and produces MemoStorageStatus for each memo.
//  Used by DataInventoryView to show users where their data lives.
//

import Foundation
import Observation
import GRDB
import CoreData
import TalkieKit

private let log = Log(.sync)

/// Service that inventories memo storage across all layers
@MainActor
@Observable
final class StorageInventoryService {
    static let shared = StorageInventoryService()

    // MARK: - State

    /// All memo statuses (sorted by status priority, then date)
    private(set) var memos: [MemoStorageStatus] = []

    /// Summary statistics
    private(set) var summary: StorageInventorySummary?

    /// Loading state
    private(set) var isLoading = false

    /// Last refresh timestamp
    private(set) var lastRefresh: Date?

    /// Error from last refresh
    private(set) var lastError: String?

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Refresh inventory from all storage layers
    func refresh() async {
        guard !isLoading else {
            log.debug("Inventory refresh already in progress, skipping")
            return
        }

        isLoading = true
        lastError = nil

        do {
            log.info("Starting storage inventory refresh...")

            // Gather data from all sources concurrently
            async let grdbMemos = fetchGRDBMemos()
            async let coreDataIDs = fetchCoreDataIDs()
            async let audioFiles = scanAudioDirectory()

            let (grdb, coreData, files) = await (grdbMemos, coreDataIDs, audioFiles)

            // Build status for each memo
            var statuses: [MemoStorageStatus] = []

            // Start with GRDB memos (source of truth)
            for memo in grdb {
                let audioPath = memo.audioFilePath
                let audioExists = audioPath.map { files.keys.contains($0) } ?? false
                let audioSize = audioPath.flatMap { files[$0] }

                let status = MemoStorageStatus(
                    id: memo.id,
                    title: memo.title ?? "Untitled",
                    createdAt: memo.createdAt,
                    duration: memo.duration,
                    hasLocalAudioFile: audioExists,
                    localAudioSize: audioSize,
                    localAudioPath: audioPath,
                    hasLocalDBRecord: true,
                    hasTranscription: memo.transcription != nil && !memo.transcription!.isEmpty,
                    hasSyncDBRecord: coreData.contains(memo.id),
                    syncDBHasAudio: coreData.contains(memo.id),  // Assume if in CoreData, has audio ref
                    hasRemoteRecord: nil,  // CloudKit check is expensive, do lazily
                    cloudSyncedAt: memo.cloudSyncedAt
                )
                statuses.append(status)
            }

            // Check for memos in CoreData but not in GRDB (needs download)
            let grdbIDs = Set(grdb.map(\.id))
            let missingFromGRDB = coreData.subtracting(grdbIDs)

            for id in missingFromGRDB {
                // These are in sync DB but not local - pending download
                let status = MemoStorageStatus(
                    id: id,
                    title: "Pending Download",
                    createdAt: Date(),  // Unknown, will update when downloaded
                    duration: 0,
                    hasLocalAudioFile: false,
                    localAudioSize: nil,
                    localAudioPath: nil,
                    hasLocalDBRecord: false,
                    hasTranscription: false,
                    hasSyncDBRecord: true,
                    syncDBHasAudio: true,
                    hasRemoteRecord: true,
                    cloudSyncedAt: nil
                )
                statuses.append(status)
            }

            // Sort by status priority (issues first), then by date
            statuses.sort(by: MemoStorageStatus.sortByStatusThenDate)

            // Update state
            self.memos = statuses
            self.summary = StorageInventorySummary(from: statuses)
            self.lastRefresh = Date()

            log.info("Inventory complete: \(statuses.count) memos, \(self.summary?.syncedCount ?? 0) synced, \(self.summary?.issueCount ?? 0) issues")

        } catch {
            log.error("Inventory refresh failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }

        isLoading = false
    }

    /// Check CloudKit status for a specific memo (expensive, do on-demand)
    func checkCloudKitStatus(for id: UUID) async -> Bool? {
        // TODO: Implement CloudKit record existence check
        // This would query CKDatabase to see if record exists
        // For now, assume if hasSyncDBRecord is true, it's in CloudKit
        return nil
    }

    // MARK: - Data Fetching

    /// Fetch all memos from GRDB
    private func fetchGRDBMemos() async -> [MemoModel] {
        do {
            let db = try DatabaseManager.shared.database()
            return try await db.read { db in
                try MemoModel.fetchAll(db)
            }
        } catch {
            log.error("Failed to fetch GRDB memos: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetch Core Data memo count from TalkieSync
    /// Note: We can no longer get individual IDs - Core Data lives in TalkieSync
    /// For inventory purposes, we just need the count
    private func fetchCoreDataIDs() async -> Set<UUID> {
        // Get count from TalkieSync via XPC
        // Since we can't get individual IDs anymore, return empty set
        // The inventory will show based on what we have locally
        let count = await SyncClient.shared.getRemoteMemoCount()
        log.debug("CoreData: \(count >= 0 ? "\(count) memos" : "unavailable") (via TalkieSync)")
        // Return empty - we no longer have direct Core Data access
        return []
    }

    /// Scan audio directory and return filename -> size mapping
    private func scanAudioDirectory() async -> [String: Int64] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var files: [String: Int64] = [:]
                let fm = FileManager.default
                let audioDir = AudioStorage.audioDirectory

                guard let contents = try? fm.contentsOfDirectory(
                    at: audioDir,
                    includingPropertiesForKeys: [.fileSizeKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    continuation.resume(returning: [:])
                    return
                }

                for fileURL in contents {
                    let filename = fileURL.lastPathComponent
                    if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        files[filename] = Int64(size)
                    }
                }

                log.debug("Scanned \(files.count) audio files")
                continuation.resume(returning: files)
            }
        }
    }

    // MARK: - Filtering

    /// Get memos with issues (not healthy)
    var memosWithIssues: [MemoStorageStatus] {
        memos.filter { !$0.status.isHealthy }
    }

    /// Get memos that are local-only (not synced)
    var localOnlyMemos: [MemoStorageStatus] {
        memos.filter { $0.status == .localOnly }
    }

    /// Get memos that are fully synced
    var syncedMemos: [MemoStorageStatus] {
        memos.filter { $0.status == .synced }
    }

    /// Get memos pending upload
    var pendingUploadMemos: [MemoStorageStatus] {
        memos.filter { $0.status == .pendingUpload }
    }

    /// Get memos pending download
    var pendingDownloadMemos: [MemoStorageStatus] {
        memos.filter { $0.status == .pendingDownload }
    }

    /// Get memos with missing audio
    var audioMissingMemos: [MemoStorageStatus] {
        memos.filter { $0.status == .audioMissing }
    }
}

// MARK: - Actions (Sync of N)

extension StorageInventoryService {

    // MARK: - Single Memo Actions

    /// Attempt to fix a memo with missing audio by re-downloading from CloudKit
    func attemptAudioRecovery(for memoId: UUID) async -> Bool {
        log.info("Attempting audio recovery for memo: \(memoId)")

        // Use the sync infrastructure to pull this memo
        await syncDownload(ids: [memoId])

        // Refresh inventory to see if it worked
        await refresh()

        // Check if audio now exists
        if let memo = memos.first(where: { $0.id == memoId }) {
            return memo.hasLocalAudioFile
        }

        return false
    }

    /// Force upload a local-only memo to CloudKit (sync of 1)
    func forceUpload(memoId: UUID) async {
        await syncUpload(ids: [memoId])
    }

    /// Force download a memo from CloudKit (sync of 1)
    func forceDownload(memoId: UUID) async {
        await syncDownload(ids: [memoId])
    }

    // MARK: - Batch Actions (Sync of N)

    /// Sync upload multiple memos to CloudKit
    /// Uses the same infrastructure as full sync
    func syncUpload(ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        log.info("Sync upload requested for \(ids.count) memos")

        // For now, CloudKit sync is all-or-nothing via NSPersistentCloudKitContainer
        // The container will pick up local changes and push them
        // TODO: When we add S3/Vercel providers, use ConnectionManager.shared.upload()
        CloudKitSyncManager.shared.syncNow()

        await refresh()
    }

    /// Sync download memos from CloudKit
    /// Triggers full bridge sync via TalkieSync (we can't sync individual IDs anymore)
    func syncDownload(ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        log.info("Sync download requested for \(ids.count) memos - triggering bridge sync")

        // Trigger bridge sync via TalkieSync - this will sync ALL memos, not just specific IDs
        do {
            _ = try await SyncClient.shared.runSyncPass()
        } catch {
            log.error("Bridge sync failed: \(error.localizedDescription)")
        }

        await refresh()
    }

    /// Bulk upload all local-only memos
    func uploadAllLocalOnly() async {
        let localOnlyIds = Set(localOnlyMemos.map(\.id))
        guard !localOnlyIds.isEmpty else {
            log.info("No local-only memos to upload")
            return
        }

        log.info("Uploading \(localOnlyIds.count) local-only memos")
        await syncUpload(ids: localOnlyIds)
    }

    /// Bulk download all pending-download memos
    func downloadAllPending() async {
        let pendingIds = Set(pendingDownloadMemos.map(\.id))
        guard !pendingIds.isEmpty else {
            log.info("No pending-download memos to fetch")
            return
        }

        log.info("Downloading \(pendingIds.count) pending memos")
        await syncDownload(ids: pendingIds)
    }

    /// Attempt recovery for all memos with missing audio
    func recoverAllMissingAudio() async -> Int {
        let missingIds = audioMissingMemos.map(\.id)
        guard !missingIds.isEmpty else {
            log.info("No memos with missing audio")
            return 0
        }

        log.info("Attempting recovery for \(missingIds.count) memos with missing audio")
        await syncDownload(ids: Set(missingIds))

        await refresh()

        // Count how many were recovered
        let stillMissing = audioMissingMemos.count
        let recovered = missingIds.count - stillMissing
        log.info("Recovered \(recovered) of \(missingIds.count) audio files")

        return recovered
    }
}
