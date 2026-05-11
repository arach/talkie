//
//  TalkieData.swift
//  Talkie
//
//  Consolidated data layer - single entry point for understanding
//  and managing all data sources in the app.
//
//  ARCHITECTURE: This is a GRDB-only client. Core Data lives in TalkieSync.
//  - UI reads/writes: GRDB via LocalRepository
//  - Sync: TalkieSync XPC service (owns Core Data + CloudKit)
//  - Bridge sync (CD → GRDB): TalkieSync writes, we just refresh
//

import Foundation
import Observation
import TalkieKit

private let log = Log(.database)

/// Snapshot of data across all sources
struct DataInventory {
    let coreData: Int       // Count from TalkieSync (via XPC), -1 means unavailable
    let local: Int          // Local repository (GRDB)
    let live: Int           // Live dictations
    let pendingSync: Int    // Count of pending sync operations (from ChangeTracker)
    let timestamp: Date

    /// Whether Core Data count is available (not connected or not ready returns -1)
    var isCoreDataAvailable: Bool { coreData >= 0 }

    /// True if local is empty but CoreData has data
    var needsBridgeSync: Bool {
        isCoreDataAvailable && local == 0 && coreData > 0
    }

    var isHealthy: Bool {
        // Has pending sync operations = needs sync
        if pendingSync > 0 {
            return false
        }

        // Can't assess health if Core Data isn't available
        guard isCoreDataAvailable else { return true }

        // Healthy = counts match (within tolerance for timing)
        return abs(coreData - local) <= 5
    }
}

@MainActor
@Observable
class TalkieData {
    static let shared = TalkieData()
    private let mirrorRepairTolerance = 1

    // Current state
    var inventory: DataInventory?
    var isReady = false
    var isSyncing = false
    var lastError: String?

    private let recordingRepo = TalkieObjectRepository()
    @ObservationIgnored private var syncObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var mirrorRepairTask: Task<Void, Never>?

    private init() {}

    // MARK: - Setup

    /// Configure TalkieData - no longer needs Core Data context
    /// Core Data lives exclusively in TalkieSync service
    func configure() {
        log.info("📊 [TalkieData] configure() - GRDB-only mode")

        startMirrorRepairObserversIfNeeded()

        // Run startup inventory after GRDB is initialized
        DatabaseManager.shared.afterInitialized { [weak self] in
            guard let self else { return }
            log.info("📊 [TalkieData] Database ready, starting runStartupChecks...")
            await self.runStartupChecks()
        }
    }

    /// Legacy configure method for backward compatibility during migration
    /// The context parameter is ignored - Core Data now lives in TalkieSync
    @available(*, deprecated, message: "Use configure() instead - Core Data moved to TalkieSync")
    func configure(with context: Any) {
        configure()
    }

    // MARK: - Startup Checks

    /// Run on app launch - quick count-based inventory and bridge sync if needed
    func runStartupChecks() async {
        await reconcileMemoMirrorIfNeeded(reason: "startup")

        let localCount = await countLocal()
        let memoRecordingCount = await countMemoRecordings()
        let liveCount = await countLive()
        let pendingCount = await countPendingSync()

        // Get Core Data count from TalkieSync (via XPC)
        // Returns -1 if TalkieSync is not connected or Core Data not ready
        let coreDataCount = await SyncClient.shared.getRemoteMemoCount()

        self.inventory = DataInventory(
            coreData: coreDataCount,
            local: localCount,
            live: liveCount,
            pendingSync: pendingCount,
            timestamp: Date()
        )

        let cdLabel = coreDataCount >= 0 ? "\(coreDataCount)" : "unavailable"
        log.info("📊 [TalkieData] Ready: \(localCount) memos (recordings mirror: \(memoRecordingCount)), \(liveCount) dictations (CoreData via TalkieSync: \(cdLabel))")

        // Trigger bridge sync if GRDB is empty but CoreData has data
        // Only if Core Data count is actually available (not -1)
        let needsSync = coreDataCount > 0 && localCount == 0
        if needsSync {
            log.info("📊 [TalkieData] GRDB empty but CoreData has \(coreDataCount) memos - triggering bridge sync via TalkieSync")
            do {
                let syncedCount = try await SyncClient.shared.runSyncPass()
                log.info("📊 [TalkieData] Bridge sync completed: \(syncedCount) memos synced")
            } catch {
                log.error("📊 [TalkieData] Bridge sync failed: \(error.localizedDescription)")
                lastError = error.localizedDescription
            }
        }

        isReady = true
        NotificationCenter.default.post(name: .talkieDataReady, object: nil)
    }

    // MARK: - Inventory

    /// Count records in all data sources
    func takeInventory() async -> DataInventory {
        async let localCount = countLocal()
        async let liveCount = countLive()
        async let pendingCount = countPendingSync()
        let coreDataCount = await SyncClient.shared.getRemoteMemoCount()

        return DataInventory(
            coreData: coreDataCount,
            local: await localCount,
            live: await liveCount,
            pendingSync: await pendingCount,
            timestamp: Date()
        )
    }

    private func countLive() async -> Int {
        (try? await recordingRepo.countDictations()) ?? 0
    }

    private func countMemoRecordings() async -> Int {
        (try? await recordingRepo.countMemoRecordings()) ?? 0
    }

    private func countLocal() async -> Int {
        do {
            let repo = LocalRepository()
            return try await repo.countMemos()
        } catch is CancellationError {
            log.debug("Local memo count cancelled")
            return inventory?.local ?? 0
        } catch {
            log.error("Failed to count local memos: \(error.localizedDescription)")
            return 0
        }
    }

    private func countPendingSync() async -> Int {
        do {
            // Count all pending operations across all providers
            let pending = try await ChangeTracker.shared.allPendingOperations()
            return pending.count
        } catch {
            log.error("Failed to count pending sync operations: \(error.localizedDescription)")
            return 0
        }
    }

    // MARK: - Bridge Sync (CoreData → GRDB)

    /// Trigger bridge sync via TalkieSync XPC
    func runBridgeSync() async {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let count = try await SyncClient.shared.runSyncPass()
            log.info("📊 [TalkieData] Bridge sync: \(count) memos synced")
        } catch {
            log.error("📊 [TalkieData] Bridge sync failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    // MARK: - Manual Refresh

    /// Force a full re-inventory and sync if needed
    func refresh() async {
        await runStartupChecks()
    }

    // MARK: - Mirror Repair

    /// Ensure unified recordings has memo rows mirrored from voice_memos.
    private func reconcileMemoMirrorIfNeeded(reason: String) async {
        do {
            let refreshed = try await recordingRepo.refreshMemoRecordingsMirrorFields()
            if refreshed > 0 {
                log.info("📊 [TalkieData] Memo mirror fields refreshed (\(reason)): \(refreshed) row(s)")
                await RecordingsViewModel.shared.refresh()
            }
        } catch is CancellationError {
            log.debug("📊 [TalkieData] Memo mirror field refresh cancelled (\(reason))")
            return
        } catch {
            log.error("📊 [TalkieData] Memo mirror field refresh failed: \(error.localizedDescription)")
        }

        let initialMemoCount = await countLocal()
        let initialRecordingMemoCount = await countMemoRecordings()
        let initialDelta = abs(initialMemoCount - initialRecordingMemoCount)

        guard initialDelta > 0 else { return }
        guard initialDelta > mirrorRepairTolerance else {
            log.debug("📊 [TalkieData] Memo mirror minor drift (\(reason)): voice_memos=\(initialMemoCount), recordings.memo=\(initialRecordingMemoCount) (delta=\(initialDelta)) — skipping rebuild")
            return
        }

        let isSyncDrivenCheck = reason == "syncDataAvailable" || reason == "talkieSyncCompleted"
        var memoCount = initialMemoCount
        var recordingMemoCount = initialRecordingMemoCount

        // Sync notifications can arrive before mirror writes settle. Re-check once
        // before doing an expensive full rebuild.
        if isSyncDrivenCheck {
            try? await Task.sleep(for: .milliseconds(300))
            memoCount = await countLocal()
            recordingMemoCount = await countMemoRecordings()
            let confirmedDelta = abs(memoCount - recordingMemoCount)

            guard confirmedDelta > 0 else { return }
            guard confirmedDelta > mirrorRepairTolerance else {
                log.debug("📊 [TalkieData] Memo mirror drift resolved (\(reason)): voice_memos=\(memoCount), recordings.memo=\(recordingMemoCount) (delta=\(confirmedDelta))")
                return
            }
        }

        log.warning("📊 [TalkieData] Memo mirror mismatch (\(reason)): voice_memos=\(memoCount), recordings.memo=\(recordingMemoCount) — rebuilding")
        do {
            let inserted = try await recordingRepo.rebuildMemoRecordingsMirror()
            log.info("📊 [TalkieData] Memo mirror rebuilt: inserted \(inserted) memo rows into recordings")
            await RecordingsViewModel.shared.refresh()
        } catch {
            log.error("📊 [TalkieData] Memo mirror rebuild failed: \(error.localizedDescription)")
        }
    }

    private func startMirrorRepairObserversIfNeeded() {
        guard syncObservers.isEmpty else { return }

        let center = NotificationCenter.default
        let queue = OperationQueue.main

        let dataAvailableObserver = center.addObserver(
            forName: .syncDataAvailable,
            object: nil,
            queue: queue
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleMirrorRepair(reason: "syncDataAvailable")
            }
        }

        let syncCompletedObserver = center.addObserver(
            forName: .talkieSyncCompleted,
            object: nil,
            queue: queue
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleMirrorRepair(reason: "talkieSyncCompleted")
            }
        }

        syncObservers.append(dataAvailableObserver)
        syncObservers.append(syncCompletedObserver)
    }

    private func scheduleMirrorRepair(reason: String) {
        mirrorRepairTask?.cancel()
        mirrorRepairTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            await self?.reconcileMemoMirrorIfNeeded(reason: reason)
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let talkieDataReady = Notification.Name("talkieDataReady")
}
