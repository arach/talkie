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
    let grdb: Int
    let live: Int
    let timestamp: Date

    var needsBridgeSync: Bool {
        grdb == 0 && coreData > 0
    }

    var isHealthy: Bool {
        // Healthy = GRDB roughly matches CoreData (within 10% or small absolute diff)
        guard coreData > 0 else { return true }
        let diff = abs(coreData - grdb)
        return diff <= 10 || Double(diff) / Double(coreData) < 0.1
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
        log.info("   • GRDB: \(inventory.grdb) memos")
        log.info("   • Live: \(inventory.live) dictations")
        log.info("   • Healthy: \(inventory.isHealthy)")

        // 2. Reconcile if needed
        if inventory.needsBridgeSync {
            log.info("🔄 [TalkieData] GRDB empty but CoreData has data - syncing...")
            isSyncing = true
            await runBridgeSync()
            isSyncing = false

            // Re-inventory after sync
            self.inventory = await takeInventory()
            log.info("✅ [TalkieData] Bridge sync complete - GRDB now has \(self.inventory?.grdb ?? 0) memos")
        }

        // 3. Mark ready
        isReady = true
        log.info("✅ [TalkieData] Data layer ready")

        // Notify UI
        NotificationCenter.default.post(name: .talkieDataReady, object: nil)
    }

    // MARK: - Inventory

    /// Count records in all data sources
    func takeInventory() async -> DataInventory {
        async let coreDataCount = countCoreData()
        async let grdbCount = countGRDB()
        async let liveCount = countLive()

        return DataInventory(
            cloudKit: nil, // CloudKit count is expensive, skip for now
            coreData: await coreDataCount,
            grdb: await grdbCount,
            live: await liveCount,
            timestamp: Date()
        )
    }

    private func countCoreData() async -> Int {
        guard let context = coreDataContext else { return 0 }

        return await context.perform {
            let request: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
            return (try? context.count(for: request)) ?? 0
        }
    }

    private func countGRDB() async -> Int {
        do {
            return try await GRDBRepository().countMemos()
        } catch {
            log.error("Failed to count GRDB: \(error.localizedDescription)")
            return 0
        }
    }

    private func countLive() async -> Int {
        // LiveDatabase uses static methods
        return LiveDatabase.count()
    }

    // MARK: - Bridge Sync (CoreData → GRDB)

    /// Copy all memos from CoreData to GRDB
    func runBridgeSync() async {
        guard let context = coreDataContext else {
            log.error("Cannot run bridge sync - no CoreData context")
            return
        }

        // Use CloudKitSyncManager's existing sync method
        await CloudKitSyncManager.shared.syncCoreDataToGRDB(context: context)
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
