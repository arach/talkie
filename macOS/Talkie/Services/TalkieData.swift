//
//  TalkieData.swift
//  Talkie
//
//  Consolidated data layer - single entry point for understanding
//  and managing all data sources in the app.
//

import Foundation
import CoreData
import Observation
import TalkieKit

private let log = Log(.database)

/// Snapshot of data across all sources
struct DataInventory {
    let cloudKit: Int?      // nil = unknown/checking
    let coreData: Int
    let local: Int          // Local repository (SQLite)
    let live: Int
    let timestamp: Date
    let coreDataIDs: Set<UUID>
    let localIDs: Set<UUID>

    /// IDs in CoreData but not in local GRDB
    var missingFromLocal: Set<UUID> {
        coreDataIDs.subtracting(localIDs)
    }

    /// True if local is empty but CoreData has data
    var needsBridgeSync: Bool {
        local == 0 && coreData > 0
    }

    /// True if there are CoreData memos not yet in GRDB (UUID mismatch)
    var needsFullSync: Bool {
        !missingFromLocal.isEmpty
    }

    var isHealthy: Bool {
        // Healthy = all CoreData IDs exist in local
        missingFromLocal.isEmpty
    }
}

@MainActor
@Observable
class TalkieData {
    static let shared = TalkieData()

    // Current state
    var inventory: DataInventory?
    var isReady = false
    var isSyncing = false
    var lastError: String?

    private var coreDataContext: NSManagedObjectContext?

    private init() {}

    // MARK: - Setup

    func configure(with context: NSManagedObjectContext) {
        print("📊 [TalkieData] configure() called")
        self.coreDataContext = context

        // Run startup inventory
        Task {
            print("📊 [TalkieData] Starting runStartupChecks task...")
            await runStartupChecks()
        }
    }

    // MARK: - Startup Checks

    /// Run on app launch - inventory all data sources and reconcile if needed
    func runStartupChecks() async {
        log.info("📊 [TalkieData] Running startup inventory...")

        // 1. Take inventory
        let inventory = await takeInventory()
        self.inventory = inventory

        log.info("📊 [TalkieData] Inventory complete:")
        log.info("   • CoreData: \(inventory.coreData) memos")
        log.info("   • Local: \(inventory.local) memos")
        log.info("   • Live: \(inventory.live) dictations")
        log.info("   • Healthy: \(inventory.isHealthy)")

        // 2. Reconcile if needed - smart targeted sync (only missing IDs)
        if inventory.needsFullSync {
            // UUID mismatch detected - some CoreData memos aren't in GRDB
            let missingIDs = inventory.missingFromLocal
            log.info("🔄 [TalkieData] \(missingIDs.count) CoreData memo(s) missing from local - syncing targeted...")
            isSyncing = true
            await syncMissingMemos(ids: missingIDs)
            isSyncing = false

            // Re-inventory after sync
            self.inventory = await takeInventory()
            log.info("✅ [TalkieData] Targeted sync complete - local now has \(self.inventory?.local ?? 0) memos")
        }

        // 3. Mark ready
        isReady = true
        log.info("✅ [TalkieData] Data layer ready")

        // Notify UI
        NotificationCenter.default.post(name: .talkieDataReady, object: nil)
    }

    // MARK: - Inventory

    /// Count records in all data sources and gather IDs for comparison
    func takeInventory() async -> DataInventory {
        async let coreDataInfo = fetchCoreDataInfo()
        async let localInfo = fetchLocalInfo()
        async let liveCount = countLive()

        let (cdCount, cdIDs) = await coreDataInfo
        let (localCount, localIDs) = await localInfo

        return DataInventory(
            cloudKit: nil, // CloudKit count is expensive, skip for now
            coreData: cdCount,
            local: localCount,
            live: await liveCount,
            timestamp: Date(),
            coreDataIDs: cdIDs,
            localIDs: localIDs
        )
    }

    private func fetchCoreDataInfo() async -> (Int, Set<UUID>) {
        guard let context = coreDataContext else { return (0, Set()) }

        return await context.perform {
            let request: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
            guard let memos = try? context.fetch(request) else {
                return (0, Set())
            }
            let ids = Set(memos.compactMap { $0.id })
            return (memos.count, ids)
        }
    }

    private func fetchLocalInfo() async -> (Int, Set<UUID>) {
        do {
            let repo = LocalRepository()
            let count = try await repo.countMemos()
            let ids = try await repo.fetchAllIDs()
            return (count, ids)
        } catch {
            log.error("Failed to fetch local info: \(error.localizedDescription)")
            return (0, Set())
        }
    }

    private func countLive() async -> Int {
        // LiveDatabase uses static methods
        return LiveDatabase.count()
    }

    // MARK: - Bridge Sync (CoreData → GRDB)

    /// Incremental sync - only memos modified since last sync
    func runBridgeSync() async {
        guard let context = coreDataContext else {
            log.error("Cannot run bridge sync - no CoreData context")
            return
        }

        // Use CloudKitSyncManager's existing sync method
        await CloudKitSyncManager.shared.syncCoreDataToGRDB(context: context)
    }

    /// Targeted sync - only sync specific missing UUIDs (smart, not brute force)
    func syncMissingMemos(ids: Set<UUID>) async {
        guard let context = coreDataContext else {
            log.error("Cannot sync missing memos - no CoreData context")
            return
        }
        guard !ids.isEmpty else { return }

        let repository = LocalRepository()
        var syncedCount = 0
        var errorCount = 0

        await context.perform {
            // Fetch only the specific missing memos by UUID
            let fetchRequest: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let missingMemos = try context.fetch(fetchRequest)
                log.info("🎯 [TalkieData] Found \(missingMemos.count) of \(ids.count) missing memos in CoreData")

                for cdMemo in missingMemos {
                    Task {
                        do {
                            let memoModel = CloudKitSyncManager.shared.convertToMemoModel(cdMemo)
                            try await repository.saveMemo(memoModel)
                            syncedCount += 1
                            log.info("✅ [TalkieData] Synced: '\(cdMemo.title ?? "Untitled")'")
                        } catch {
                            errorCount += 1
                            log.error("❌ [TalkieData] Failed to sync memo: \(error.localizedDescription)")
                        }
                    }
                }
            } catch {
                log.error("❌ [TalkieData] Failed to fetch missing memos: \(error.localizedDescription)")
            }
        }

        // Wait for async tasks to complete
        try? await Task.sleep(for: .seconds(1))
        log.info("🎯 [TalkieData] Targeted sync: \(syncedCount) synced, \(errorCount) errors")
    }

    // MARK: - Manual Refresh

    /// Force a full re-inventory and sync if needed
    func refresh() async {
        await runStartupChecks()
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let talkieDataReady = Notification.Name("talkieDataReady")
}
