//
//  CloudKitSyncEngine.swift
//  Talkie
//
//  CloudKit sync engine - Background layer that syncs GRDB ↔ CloudKit
//  Decoupled from views, works silently in background
//

import Foundation
import CloudKit

// MARK: - CloudKit Sync Engine

@MainActor
final class CloudKitSyncEngine: ObservableObject {
    static let shared = CloudKitSyncEngine()

    // MARK: - Published State

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: Error?

    // MARK: - Dependencies

    private let repository: GRDBRepository
    private let container: CKContainer
    private let database: CKDatabase

    // MARK: - Configuration

    private let recordZoneID = CKRecordZone.ID(zoneName: "TalkieMemos", ownerName: CKCurrentUserDefaultName)
    private var syncTimer: Timer?

    // MARK: - Init

    init(repository: GRDBRepository = GRDBRepository()) {
        self.repository = repository
        self.container = CKContainer(identifier: "iCloud.com.jdi.talkie")
        self.database = container.privateCloudDatabase
    }

    // MARK: - Public API

    /// Start periodic background sync (every 5 minutes)
    func startPeriodicSync() {
        // Initial sync
        Task {
            await performFullSync()
        }

        // Periodic sync
        syncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performFullSync()
            }
        }
    }

    /// Stop periodic sync
    func stopPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    /// Manual sync trigger
    func sync() async {
        await performFullSync()
    }

    // MARK: - Sync Logic

    private func performFullSync() async {
        guard !isSyncing else {
            print("⏭️ Sync already in progress, skipping...")
            return
        }

        isSyncing = true
        syncError = nil

        do {
            // Step 1: Pull changes from CloudKit
            print("⬇️ Pulling changes from CloudKit...")
            try await pullChangesFromCloudKit()

            // Step 2: Push local changes to CloudKit
            print("⬆️ Pushing local changes to CloudKit...")
            try await pushChangesToCloudKit()

            lastSyncDate = Date()
            print("✅ Sync complete")

        } catch {
            print("❌ Sync failed: \(error)")
            syncError = error
        }

        isSyncing = false
    }

    // MARK: - Pull Changes from CloudKit

    private func pullChangesFromCloudKit() async throws {
        do {
            // Fetch all memo records from CloudKit
            let query = CKQuery(recordType: "VoiceMemo", predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]

            let (matchResults, _) = try await database.records(matching: query)

            // Process each record
            for (recordID, result) in matchResults {
                switch result {
                case .success(let record):
                    try await processCloudKitRecord(record)
                case .failure(let error):
                    print("⚠️ Failed to fetch record \(recordID): \(error)")
                }
            }

        } catch {
            print("❌ Pull failed: \(error)")
            throw error
        }
    }

    private func processCloudKitRecord(_ record: CKRecord) async throws {
        // Convert CKRecord → MemoModel
        guard let memo = MemoModel.fromCKRecord(record) else {
            print("⚠️ Failed to convert record to memo")
            return
        }

        // Check if we have this memo locally
        if let existingMemo = try await repository.fetchMemo(id: memo.id) {
            // Conflict resolution: Use latest based on lastModified
            if memo.lastModified > existingMemo.memo.lastModified {
                print("📥 Updating local memo from CloudKit: \(memo.id)")
                try await repository.saveMemo(memo)
            } else {
                print("⏭️ Local memo is newer, skipping: \(memo.id)")
            }
        } else {
            // New memo from CloudKit
            print("📥 Creating new local memo from CloudKit: \(memo.id)")
            try await repository.saveMemo(memo)
        }
    }

    // MARK: - Push Changes to CloudKit

    private func pushChangesToCloudKit() async throws {
        do {
            // Fetch memos that need syncing (modified since last sync)
            let memosToSync = try await fetchMemosNeedingSync()

            guard !memosToSync.isEmpty else {
                print("✅ No local changes to push")
                return
            }

            print("📤 Pushing \(memosToSync.count) memos to CloudKit...")

            // Convert to CKRecords and save
            let records = memosToSync.map { $0.toCKRecord() }

            // Save in batches (CloudKit limit: 400 records per batch)
            let batchSize = 400
            for batch in records.chunked(into: batchSize) {
                let (saveResults, _) = try await database.modifyRecords(saving: batch, deleting: [])

                // Mark successful saves
                for (recordID, result) in saveResults {
                    switch result {
                    case .success(let record):
                        print("✅ Pushed memo: \(recordID.recordName)")
                        // Update cloudSyncedAt timestamp
                        if let memoID = UUID(uuidString: recordID.recordName),
                           var memo = try await repository.fetchMemo(id: memoID)?.memo {
                            memo.cloudSyncedAt = Date()
                            try await repository.saveMemo(memo)
                        }
                    case .failure(let error):
                        print("❌ Failed to push memo \(recordID): \(error)")
                    }
                }
            }

        } catch {
            print("❌ Push failed: \(error)")
            throw error
        }
    }

    private func fetchMemosNeedingSync() async throws -> [MemoModel] {
        // For now, fetch all memos (we'll optimize this later with a "needsSync" flag)
        // In production, you'd track which memos changed since last sync
        let allMemos = try await repository.fetchMemos(
            sortBy: .timestamp,
            ascending: false,
            limit: 10000,  // Fetch all for sync
            offset: 0,
            searchQuery: nil,
            filters: []  // No filters for sync
        )

        // Filter to memos that haven't been synced or modified since last sync
        return allMemos.filter { memo in
            guard let lastSync = lastSyncDate else { return true }  // Never synced
            return memo.lastModified > lastSync
        }
    }
}

// MARK: - Array Extension (Chunking)

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
