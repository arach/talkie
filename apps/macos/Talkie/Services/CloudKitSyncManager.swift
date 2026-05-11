//
//  CloudKitSyncManager.swift
//  Talkie macOS
//
//  SIMPLIFIED: UI status tracking only.
//  Actual sync operations handled by TalkieSync XPC service.
//
//  This manager:
//  - Tracks sync status for UI display
//  - Observes SyncClient callbacks
//  - Maintains sync history in GRDB
//
//  Does NOT:
//  - Initialize Core Data
//  - Perform CloudKit operations
//  - Run timers or background schedulers
//

import Foundation
import Observation
import GRDB
import TalkieKit

private let log = Log(.sync)

@MainActor
@Observable
class CloudKitSyncManager {
    static let shared = CloudKitSyncManager()

    // MARK: - UI State

    var isSyncing = false
    var lastSyncDate: Date?
    var lastChangeCount: Int = 0
    var syncHistory: [SyncEvent] = []

    private let maxHistoryCount = 50
    private let maxPersistedCount = 100
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    // Static cached formatter for status display
    @ObservationIgnored private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private init() {
        StartupProfiler.shared.mark("singleton.CloudKitSyncManager.start")

        // Observe SyncClient for status updates
        setupSyncClientObserver()

        // Load persisted history from GRDB after DB is ready
        DatabaseManager.shared.afterInitialized { [weak self] in
            await self?.loadPersistedState()
        }

        StartupProfiler.shared.mark("singleton.CloudKitSyncManager.done")
    }

    // MARK: - Setup

    /// Configure is now a no-op - Core Data lives in TalkieSync
    /// Kept for backward compatibility during migration
    @available(*, deprecated, message: "CloudKitSyncManager no longer needs configuration - sync handled by TalkieSync")
    func configure(with context: Any) {
        log.info("CloudKitSyncManager.configure() called - delegating to TalkieSync")
        // No-op: Sync history is now kept in memory only
    }

    /// Setup observer for SyncClient status changes
    private func setupSyncClientObserver() {
        // Observe SyncClient state changes
        // SyncClient already handles XPC callbacks, we just mirror its state
        NotificationCenter.default.addObserver(
            forName: .syncDataAvailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRefreshFromSyncClient()
            }
        }

        // Also observe sync completion to reset isSyncing
        NotificationCenter.default.addObserver(
            forName: .talkieSyncCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRefreshFromSyncClient()
            }
        }
    }

    /// Coalesce bursts of sync notifications into a single UI refresh.
    private func scheduleRefreshFromSyncClient() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(75))
            self?.refreshFromSyncClient()
        }
    }

    /// Mirror SyncClient state to our observable properties
    private func refreshFromSyncClient() {
        let client = SyncClient.shared
        let newIsSyncing = client.isSyncing
        let newLastSyncDate = client.lastSyncDate

        if isSyncing != newIsSyncing {
            isSyncing = newIsSyncing
        }
        if lastSyncDate != newLastSyncDate {
            lastSyncDate = newLastSyncDate
        }
    }

    // MARK: - Sync Operations (delegated to TalkieSync)

    /// Trigger a sync - delegates to TalkieSync via SyncClient
    func syncNow() {
        guard !isSyncing else {
            log.info("Sync already in progress, skipping")
            return
        }

        Task {
            do {
                isSyncing = true
                SyncStatusManager.shared.setSyncing()
                NotificationCenter.default.post(name: .talkieSyncStarted, object: nil)

                // Use runSyncOnce so this path captures rich activity logs + persisted
                // SyncEvent activity details, matching the status-bar Sync UX.
                try await SyncClient.shared.runSyncOnce(keepRunning: SettingsManager.shared.syncOnLaunch)

                isSyncing = false
                refreshFromSyncClient()
                SyncStatusManager.shared.setSynced()
            } catch {
                log.error("Sync failed: \(error.localizedDescription)")
                isSyncing = false
                SyncStatusManager.shared.setError(error.localizedDescription)
            }
        }
    }

    /// Force a full sync - delegates to TalkieSync
    func forceFullSync() {
        syncNow()
    }

    /// Force sync CoreData → GRDB - delegates to TalkieSync
    func forceSyncToGRDB() {
        Task {
            do {
                _ = try await SyncClient.shared.runSyncPass()
                scheduleRefreshFromSyncClient()
            } catch {
                log.error("Bridge sync failed: \(error.localizedDescription)")
            }
        }
    }

    /// Full sync ALL CoreData memos to GRDB - delegates to TalkieSync
    func fullSyncToGRDB() {
        log.info("🔄 Requesting full bridge sync via TalkieSync...")
        forceSyncToGRDB()
    }

    // MARK: - Sync History

    func addSyncEvent(_ event: SyncEvent) {
        log.info("📊 Adding sync event: \(event.status.rawValue) at \(event.timestamp)")
        syncHistory.insert(event, at: 0)

        if syncHistory.count > maxHistoryCount {
            syncHistory = Array(syncHistory.prefix(maxHistoryCount))
        }

        // Persist to GRDB (fire-and-forget)
        Task.detached { [maxPersistedCount] in
            do {
                let db = try DatabaseManager.shared.database()
                try await db.write { db in
                    try event.insert(db)

                    // Update lastSyncTimestamp on success
                    if event.status == .success {
                        try db.execute(
                            sql: "UPDATE sync_metadata SET lastSyncTimestamp = ? WHERE id = 1",
                            arguments: [event.timestamp]
                        )
                    }

                    // Prune old events beyond limit
                    let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_history") ?? 0
                    if count > maxPersistedCount {
                        try db.execute(
                            sql: """
                                DELETE FROM sync_history WHERE id IN (
                                    SELECT id FROM sync_history
                                    ORDER BY timestamp ASC
                                    LIMIT ?
                                )
                                """,
                            arguments: [count - maxPersistedCount]
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    log.warning("Failed to persist sync event: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Persistence

    /// Load persisted sync history and lastSyncDate from GRDB
    private func loadPersistedState() async {
        do {
            let db = try DatabaseManager.shared.database()

            // Load last 50 events
            let events: [SyncEvent] = try await db.read { db in
                try SyncEvent
                    .order(SyncEvent.Columns.timestamp.desc)
                    .limit(maxHistoryCount)
                    .fetchAll(db)
            }

            // Load lastSyncTimestamp from metadata
            let lastSync: Date? = try await db.read { db in
                let metadata = try SyncMetadata.get(db)
                return metadata.lastSyncTimestamp
            }

            // Only populate if we don't already have in-memory data
            // (e.g., from a sync that happened during startup)
            if syncHistory.isEmpty {
                syncHistory = events
            }
            if lastSyncDate == nil {
                lastSyncDate = lastSync
            }

            log.info("Loaded \(events.count) persisted sync events, lastSync: \(lastSync?.description ?? "nil")")
        } catch {
            log.warning("Failed to load persisted sync state: \(error.localizedDescription)")
        }
    }

    /// Get sync status for display
    var statusDescription: String {
        if isSyncing {
            return "Syncing..."
        } else if let date = lastSyncDate {
            return "Synced \(Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date()))"
        } else {
            return "Not synced"
        }
    }

    // MARK: - Deprecated Methods

    /// Reset sync token - now handled by TalkieSync
    @available(*, deprecated, message: "Sync token managed by TalkieSync")
    func resetSyncToken() {
        log.warning("resetSyncToken() called - sync token now managed by TalkieSync")
    }

    /// Record activity - no longer needed
    @available(*, deprecated, message: "No longer needed - sync managed by TalkieSync")
    func recordActivity() {
        // No-op
    }

    // MARK: - Bridge Sync (deprecated - use TalkieSync)

    @available(*, deprecated, message: "Bridge sync now handled by TalkieSync")
    func syncCoreDataToGRDB(context: Any, fullSync: Bool = false) async {
        log.warning("syncCoreDataToGRDB() called - redirecting to TalkieSync")
        forceSyncToGRDB()
    }

    @available(*, deprecated, message: "Bridge sync now handled by TalkieSync")
    func syncCoreDataToRecordings(context: Any, fullSync: Bool = false) async {
        log.warning("syncCoreDataToRecordings() called - redirecting to TalkieSync")
        forceSyncToGRDB()
    }

    @available(*, deprecated, message: "Conversion now handled by TalkieSync")
    func convertToMemoModel(_ cdMemo: Any) -> MemoModel {
        fatalError("convertToMemoModel() called - this should be handled by TalkieSync")
    }
}
