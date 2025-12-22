//
//  CloudKitSyncManager.swift
//  Talkie macOS
//
//  CloudKit sync manager with background activity support.
//  - Foreground: Timer-based sync every minute
//  - Background (app running but not focused): Continues via disabled App Nap
//  - Terminated: NSBackgroundActivityScheduler wakes app for periodic sync
//
//  NSPersistentCloudKitContainer handles the actual sync; this manages timing and UI.
//

import Foundation
import CloudKit
import CoreData
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "CloudKitSync")

@MainActor
@Observable
class CloudKitSyncManager {
    static let shared = CloudKitSyncManager()

    private let container = CKContainer(identifier: "iCloud.com.jdi.talkie")
    private let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
    private var viewContext: NSManagedObjectContext?

    // Server change token - persisted to UserDefaults
    private var serverChangeToken: CKServerChangeToken? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "CloudKitServerChangeToken") else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
        }
        set {
            if let token = newValue,
               let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
                UserDefaults.standard.set(data, forKey: "CloudKitServerChangeToken")
            } else {
                UserDefaults.standard.removeObject(forKey: "CloudKitServerChangeToken")
            }
        }
    }

    var isSyncing = false
    var lastSyncDate: Date?
    var lastChangeCount: Int = 0
    var syncHistory: [SyncEvent] = []

    private let maxHistoryCount = 50 // Keep last 50 sync events

    // MARK: - Timers and Schedulers
    @ObservationIgnored private var syncTimer: Timer?
    @ObservationIgnored private var remoteChangeObserver: NSObjectProtocol?
    @ObservationIgnored private var syncIntervalObserver: NSObjectProtocol?
    @ObservationIgnored private var debounceTimer: Timer?
    @ObservationIgnored private let debounceInterval: TimeInterval = 3.0 // Coalesce rapid notifications

    // Sync interval from settings (default 10 minutes)
    private var syncInterval: TimeInterval {
        SettingsManager.shared.syncIntervalSeconds
    }

    // Background activity scheduler - wakes app even when terminated
    @ObservationIgnored private var backgroundActivityScheduler: NSBackgroundActivityScheduler?
    // Background sync at 1.5x foreground interval
    private var backgroundSyncInterval: TimeInterval {
        syncInterval * 1.5
    }

    // App Nap prevention - keeps sync running when app loses focus
    @ObservationIgnored private var appNapActivity: NSObjectProtocol?

    // Static cached formatter for status display
    @ObservationIgnored private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private init() {
        loadSyncHistory()
    }

    deinit {
        // Defensive cleanup - singleton shouldn't deinit but if it does, clean up
        // Access to main actor properties is unsafe here, but cleanup is critical
        Task { @MainActor in
            syncTimer?.invalidate()
            debounceTimer?.invalidate()
            backgroundActivityScheduler?.invalidate()
            if let activity = appNapActivity {
                ProcessInfo.processInfo.endActivity(activity)
            }
            if let observer = remoteChangeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = syncIntervalObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    func configure(with context: NSManagedObjectContext) {
        self.viewContext = context

        let now = Date()
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        // MARK: - Foreground Sync (Timer-based, every minute)
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncNow()
            }
        }
        let nextForegroundSync = now.addingTimeInterval(syncInterval)
        logger.info("Foreground timer started - next sync at \(timeFormatter.string(from: nextForegroundSync)) (every \(Int(self.syncInterval))s)")

        // MARK: - Background Sync (App running but not focused)
        // Disable App Nap so timers continue running when app loses focus
        startAppNapPrevention()

        // MARK: - Terminated Sync (App not running)
        // NSBackgroundActivityScheduler can wake the app for periodic maintenance
        setupBackgroundActivityScheduler()

        // Listen for remote store changes (real-time updates from other devices)
        // Only sync if there are actual transactions, not just CloudKit housekeeping
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }

            // Dispatch to main actor for Swift 6 compatibility
            Task { @MainActor in
                // Check if there are actual changes worth syncing
                let hasRealChanges = self.checkForRealChanges(notification: notification)

                #if DEBUG
                self.logRemoteChangeNotification(notification, hasRealChanges: hasRealChanges)
                #endif

                // Only schedule sync if there are real data changes
                if hasRealChanges {
                    self.scheduleDebounceSync()
                }
            }
        }

        // Listen for sync interval setting changes
        syncIntervalObserver = NotificationCenter.default.addObserver(
            forName: .syncIntervalDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.restartSyncTimers()
            }
        }

        logger.info("CloudKitSyncManager configured - foreground: \(Int(self.syncInterval))s, background: \(Int(self.backgroundSyncInterval))s")

        if serverChangeToken != nil {
            logger.info("Existing server change token found - will fetch delta")
        } else {
            logger.info("No server change token - will perform full sync")
        }

        // Run one-time migrations
        MigrationRunner.shared.runPending(context: context)
    }

    /// Restarts sync timers when the sync interval setting changes
    private func restartSyncTimers() {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let now = Date()

        // Restart foreground timer
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncNow()
            }
        }
        let nextSync = now.addingTimeInterval(syncInterval)
        logger.info("Sync timer restarted - next sync at \(timeFormatter.string(from: nextSync)) (every \(Int(self.syncInterval))s / \(Int(self.syncInterval/60))min)")

        // Restart background scheduler
        backgroundActivityScheduler?.invalidate()
        setupBackgroundActivityScheduler()
    }

    // MARK: - App Nap Prevention

    /// Prevents App Nap from throttling the app when it loses focus.
    /// This ensures sync timers continue running when user switches to another app.
    private func startAppNapPrevention() {
        // End any existing activity
        if let existingActivity = appNapActivity {
            ProcessInfo.processInfo.endActivity(existingActivity)
        }

        // Start an activity that FULLY prevents App Nap
        // .latencyCritical tells macOS this activity needs timely execution
        // .idleDisplaySleepDisabled keeps display awake (optional, can remove if not wanted)
        // The key is NOT using .userInitiatedAllowingIdleSystemSleep which still allows throttling
        appNapActivity = ProcessInfo.processInfo.beginActivity(
            options: [.latencyCritical, .automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "Talkie needs to sync voice memos from iOS in real-time"
        )

        logger.info("App Nap FULLY disabled - timers will fire even when app loses focus")
    }

    /// Stops App Nap prevention (called on deinit or when explicitly disabled)
    private func stopAppNapPrevention() {
        if let activity = appNapActivity {
            ProcessInfo.processInfo.endActivity(activity)
            appNapActivity = nil
            logger.info("App Nap prevention disabled")
        }
    }

    // MARK: - Background Activity Scheduler

    /// Sets up NSBackgroundActivityScheduler to wake the app periodically
    /// even when it's been terminated. macOS will launch the app briefly to run the sync.
    private func setupBackgroundActivityScheduler() {
        let scheduler = NSBackgroundActivityScheduler(identifier: "com.jdi.talkie.background-sync")

        // Configure the scheduler
        scheduler.repeats = true
        scheduler.interval = backgroundSyncInterval  // 2 minutes
        scheduler.tolerance = 30  // Allow 30s flexibility for system optimization
        scheduler.qualityOfService = .userInitiated  // Higher priority for faster response

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        scheduler.schedule { [weak self] completion in
            guard let self = self else {
                completion(.finished)
                return
            }

            // Background scheduler fired - sync silently

            // Perform sync on main actor
            Task { @MainActor in
                await self.performSync()
                completion(.finished)
            }
        }

        self.backgroundActivityScheduler = scheduler

        let now = Date()
        let firstExpected = now.addingTimeInterval(backgroundSyncInterval)
        logger.info("Background scheduler started - first expected ~\(timeFormatter.string(from: firstExpected)) (every \(Int(self.backgroundSyncInterval))s +/- 30s)")
    }

    /// Invalidates the background activity scheduler
    private func stopBackgroundActivityScheduler() {
        backgroundActivityScheduler?.invalidate()
        backgroundActivityScheduler = nil
        logger.info("Background activity scheduler stopped")
    }

    /// Record user activity (called when user triggers manual sync)
    func recordActivity() {
        // No-op now, but kept for API compatibility
    }

    /// Trigger a sync immediately
    func syncNow() {
        guard !isSyncing else {
            logger.info("Sync already in progress, skipping")
            return
        }

        Task {
            await performSync()
        }
    }

    /// Force a full sync (ignores existing token)
    func forceFullSync() {
        serverChangeToken = nil
        syncNow()
    }

    /// Schedule a debounced sync - coalesces rapid CloudKit notifications
    private func scheduleDebounceSync() {
        // Cancel any existing debounce timer
        debounceTimer?.invalidate()

        // Schedule a new sync after the debounce interval
        // If more notifications come in, the timer resets
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.syncNow()
            }
        }
    }

    /// Check if a remote change notification has actual data changes (not just housekeeping)
    private func checkForRealChanges(notification: Notification) -> Bool {
        guard let token = notification.userInfo?[NSPersistentHistoryTokenKey] as? NSPersistentHistoryToken,
              let context = viewContext else {
            return false
        }

        // Query persistent history synchronously to check for real changes
        var hasChanges = false
        context.performAndWait {
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
            do {
                if let result = try context.execute(request) as? NSPersistentHistoryResult,
                   let transactions = result.result as? [NSPersistentHistoryTransaction] {
                    // Check if any transaction has actual changes
                    hasChanges = transactions.contains { transaction in
                        if let changes = transaction.changes, !changes.isEmpty {
                            return true
                        }
                        return false
                    }
                }
            } catch {
                // If we can't check, assume there might be changes
                hasChanges = true
            }
        }
        return hasChanges
    }

    private func performSync() async {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let startTime = Date()

        // Use DispatchQueue to defer @Published updates and avoid
        // "Publishing changes from within view updates" warnings
        DispatchQueue.main.async {
            self.isSyncing = true
            SyncStatusManager.shared.setSyncing()
        }

        NotificationCenter.default.post(name: .talkieSyncStarted, object: nil)
        logger.info("[\(timeFormatter.string(from: startTime))] Sync starting...")

        do {
            let result = try await fetchChanges()
            let duration = Date().timeIntervalSince(startTime)

            DispatchQueue.main.async {
                self.lastSyncDate = Date()
                self.lastChangeCount = result.changeCount
                self.isSyncing = false
                SyncStatusManager.shared.setSynced(changes: result.changeCount)

                // Add to sync history
                let event = SyncEvent(
                    timestamp: startTime,
                    status: .success,
                    itemCount: result.changeCount,
                    duration: duration,
                    errorMessage: nil,
                    details: result.details
                )
                self.addSyncEvent(event)
            }

            NotificationCenter.default.post(
                name: .talkieSyncCompleted,
                object: nil,
                userInfo: ["changes": result.changeCount]
            )

            // Mark memos from other devices as received by Mac
            if let context = self.viewContext {
                // If we detected changes, give Core Data a moment to import them
                // NSPersistentCloudKitContainer handles import automatically; we just need to refresh
                if result.changeCount > 0 {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                    context.refreshAllObjects()

                    // BRIDGE 1: Sync Core Data → GRDB
                    await self.syncCoreDataToGRDB(context: context)
                }

                // Process auto-run workflows for unprocessed memos
                await self.processTriggers(context: context)

                // Mark iOS memos as received (for UI display purposes)
                PersistenceController.markMemosAsReceivedByMac(context: context)
                // Process any pending workflow requests from iOS
                PersistenceController.processPendingWorkflows(context: context)
            }

            // Log completion with duration
            let durationStr = String(format: "%.1fs", duration)
            if result.changeCount > 0 {
                logger.info("[\(timeFormatter.string(from: Date()))] Sync complete: \(result.changeCount) change(s) in \(durationStr)")
            } else {
                logger.info("[\(timeFormatter.string(from: Date()))] Sync complete: no changes (\(durationStr))")
            }

        } catch {
            let duration = Date().timeIntervalSince(startTime)
            logger.error("Sync failed: \(error.localizedDescription)")

            DispatchQueue.main.async {
                self.isSyncing = false
                SyncStatusManager.shared.setError(error.localizedDescription)

                // Add failed sync to history
                let event = SyncEvent(
                    timestamp: startTime,
                    status: .failed,
                    itemCount: 0,
                    duration: duration,
                    errorMessage: error.localizedDescription,
                    details: []
                )
                self.addSyncEvent(event)
            }
        }
    }

    // MARK: - Auto-Run Workflow Processing

    /// Process auto-run workflows for unprocessed memos
    /// Includes memos without transcripts (System Transcribe will handle them)
    /// Note: Context should already be refreshed by caller - no need to refresh again
    private func processTriggers(context: NSManagedObjectContext) async {
        // Query: unprocessed memos with audio data
        // Note: We include memos WITHOUT transcripts because System Transcribe (Phase 1) handles those
        let request = VoiceMemo.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "audioData != nil"),  // Has audio to process
            NSPredicate(format: "autoProcessed == NO")
        ])
        request.sortDescriptors = [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)]
        request.fetchLimit = 10

        do {
            let memos = try context.fetch(request)

            if !memos.isEmpty {
                logger.info("Found \(memos.count) unprocessed memo(s)")
                for memo in memos {
                    let hasTranscript = memo.transcription != nil && !memo.transcription!.isEmpty
                    logger.info("Auto-run: '\(memo.title ?? "Untitled")' (has transcript: \(hasTranscript))")
                    await AutoRunProcessor.shared.processNewMemo(memo, context: context)
                }
            }
        } catch {
            logger.error("Failed to process auto-run workflows: \(error.localizedDescription)")
        }
    }

    // Result of fetchChanges with detailed record information
    private struct FetchResult {
        let changeCount: Int
        let details: [SyncRecordDetail]
    }

    private func fetchChanges() async throws -> FetchResult {
        let database = container.privateCloudDatabase

        // Configure the fetch operation
        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        configuration.previousServerChangeToken = serverChangeToken

        let options = [zoneID: configuration]
        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID], configurationsByRecordZoneID: options)

        var changedRecords: [CKRecord] = []
        var deletedRecordIDs: [CKRecord.ID] = []
        var newToken: CKServerChangeToken?

        return try await withCheckedThrowingContinuation { continuation in

            operation.recordWasChangedBlock = { recordID, result in
                switch result {
                case .success(let record):
                    changedRecords.append(record)
                case .failure(let error):
                    logger.warning("Failed to fetch record \(recordID.recordName): \(error.localizedDescription)")
                }
            }

            operation.recordWithIDWasDeletedBlock = { recordID, recordType in
                deletedRecordIDs.append(recordID)
            }

            operation.recordZoneChangeTokensUpdatedBlock = { zoneID, token, _ in
                newToken = token
            }

            operation.recordZoneFetchResultBlock = { zoneID, result in
                switch result {
                case .success(let (token, _, _)):
                    newToken = token
                case .failure(let error):
                    // Zone might not exist yet - that's OK
                    if let ckError = error as? CKError, ckError.code == .zoneNotFound {
                        logger.info("CloudKit zone not found - will be created on first save")
                    } else {
                        logger.warning("Zone fetch error: \(error.localizedDescription)")
                    }
                }
            }

            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    // Save the new token for next sync
                    if let token = newToken {
                        Task { @MainActor in
                            self.serverChangeToken = token
                        }
                    }

                    let totalChanges = changedRecords.count + deletedRecordIDs.count

                    // Build detailed record information for UI
                    var details: [SyncRecordDetail] = []

                    // Process changed records
                    for record in changedRecords {
                        let typeName = record.recordType.replacingOccurrences(of: "CD_", with: "")
                        let title = record["CD_title"] as? String ?? "Untitled"
                        let modDate = record.modificationDate

                        // Determine if this is a new record or modification
                        // (For simplicity, treat all as modified - we don't have creation date easily)
                        let changeType: SyncRecordDetail.ChangeType = .modified

                        let detail = SyncRecordDetail(
                            id: record.recordID.recordName,
                            recordType: typeName,
                            title: title,
                            modificationDate: modDate,
                            changeType: changeType
                        )
                        details.append(detail)
                    }

                    // Process deleted records
                    for recordID in deletedRecordIDs {
                        let detail = SyncRecordDetail(
                            id: recordID.recordName,
                            recordType: "Unknown", // We don't have type info for deleted records
                            title: recordID.recordName,
                            modificationDate: nil,
                            changeType: .deleted
                        )
                        details.append(detail)
                    }

                    if totalChanges > 0 {
                        // Group changed records by type for useful logging
                        var typeCount: [String: Int] = [:]
                        for record in changedRecords {
                            let typeName = record.recordType.replacingOccurrences(of: "CD_", with: "")
                            typeCount[typeName, default: 0] += 1
                        }
                        let typeSummary = typeCount.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
                        logger.info("Fetched: \(typeSummary)\(deletedRecordIDs.count > 0 ? ", \(deletedRecordIDs.count) deleted" : "")")

                        // Debug: print top 3 records
                        for (i, record) in changedRecords.prefix(3).enumerated() {
                            let typeName = record.recordType.replacingOccurrences(of: "CD_", with: "")
                            let title = record["CD_title"] as? String ?? "?"
                            let modDate = record.modificationDate.map { "\($0)" } ?? "?"
                            logger.info("  [\(i+1)] \(typeName): '\(title)' modified: \(modDate)")
                        }

                    }

                    // Note: NSPersistentCloudKitContainer handles the actual Core Data import
                    // automatically. We're just tracking changes for UI feedback.
                    // The records we fetched here are informational - Core Data's mirroring
                    // will handle the actual database updates.

                    continuation.resume(returning: FetchResult(changeCount: totalChanges, details: details))

                case .failure(let error):
                    // Handle token reset if needed
                    if let ckError = error as? CKError, ckError.code == .changeTokenExpired {
                        logger.warning("Change token expired - will reset and retry")
                        Task { @MainActor in
                            self.serverChangeToken = nil
                        }
                    }
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }
    }

    /// Clear the sync token (for debugging/reset)
    func resetSyncToken() {
        serverChangeToken = nil
        logger.info("Sync token reset - next sync will fetch all records")
    }

    // MARK: - Sync History Management

    private func loadSyncHistory() {
        Task {
            do {
                let db = try await DatabaseManager.shared.database()
                let events = try await db.read { db in
                    try SyncEvent
                        .order(SyncEvent.Columns.timestamp.desc)
                        .limit(maxHistoryCount)
                        .fetchAll(db)
                }
                await MainActor.run {
                    self.syncHistory = events
                }
            } catch {
                logger.error("Failed to load sync history from database: \(error.localizedDescription)")
                await MainActor.run {
                    self.syncHistory = []
                }
            }
        }
    }

    private func addSyncEvent(_ event: SyncEvent) {
        // Add to beginning of in-memory array (most recent first)
        syncHistory.insert(event, at: 0)

        // Limit in-memory history size
        if syncHistory.count > maxHistoryCount {
            syncHistory = Array(syncHistory.prefix(maxHistoryCount))
        }

        // Persist to database
        Task {
            do {
                let db = try await DatabaseManager.shared.database()
                try await db.write { db in
                    try event.insert(db)

                    // Clean up old events (keep last 50 in database too)
                    let oldEventIDs = try SyncEvent
                        .order(SyncEvent.Columns.timestamp.desc)
                        .select(SyncEvent.Columns.id)
                        .limit(maxHistoryCount, offset: maxHistoryCount)
                        .fetchAll(db) as [String]

                    if !oldEventIDs.isEmpty {
                        try SyncEvent.deleteAll(db, ids: oldEventIDs)
                    }
                }
            } catch {
                logger.error("Failed to save sync event to database: \(error.localizedDescription)")
            }
        }
    }

    /// Get the most recent sync timestamp for throttling
    func getLastSyncTimestamp() async -> Date? {
        do {
            let db = try await DatabaseManager.shared.database()
            return try await db.read { db in
                try SyncEvent
                    .order(SyncEvent.Columns.timestamp.desc)
                    .limit(1)
                    .fetchOne(db)?.timestamp
            }
        } catch {
            logger.error("Failed to get last sync timestamp: \(error.localizedDescription)")
            return nil
        }
    }

    #if DEBUG
    /// Log details about remote change notifications for debugging (dev builds only)
    /// Only logs when there are actual changes to reduce noise
    private func logRemoteChangeNotification(_ notification: Notification, hasRealChanges: Bool) {
        // Skip logging housekeeping notifications - too noisy
        guard hasRealChanges else { return }

        var details: [String] = []

        // Extract store URL if available
        if let storeURL = notification.userInfo?["storeURL"] as? URL {
            details.append("store: \(storeURL.lastPathComponent)")
        }

        let detailString = details.joined(separator: " | ")
        logger.info("RemoteChange: \(detailString)")

        // Fetch actual persistent history to see what changed
        if let token = notification.userInfo?[NSPersistentHistoryTokenKey] as? NSPersistentHistoryToken,
           let context = viewContext {
            fetchHistoryDetails(since: token, context: context)
        }
    }

    /// Fetch and log persistent history details to see actual changes
    private func fetchHistoryDetails(since token: NSPersistentHistoryToken, context: NSManagedObjectContext) {
        context.perform {
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)

            do {
                guard let result = try context.execute(request) as? NSPersistentHistoryResult,
                      let transactions = result.result as? [NSPersistentHistoryTransaction],
                      !transactions.isEmpty else {
                    // No transactions - skip logging
                    return
                }

                for (i, transaction) in transactions.enumerated() {
                    let changes = transaction.changes ?? []
                    let author = transaction.author ?? "unknown"
                    let contextName = transaction.contextName ?? "unnamed"

                    // Group changes by entity and type
                    var insertCount = 0
                    var updateCount = 0
                    var deleteCount = 0
                    var entities: Set<String> = []

                    for change in changes {
                        entities.insert(change.changedObjectID.entity.name ?? "?")
                        switch change.changeType {
                        case .insert: insertCount += 1
                        case .update: updateCount += 1
                        case .delete: deleteCount += 1
                        @unknown default: break
                        }
                    }

                    let entityList = entities.joined(separator: ", ")
                    let changesSummary = [
                        insertCount > 0 ? "+\(insertCount)" : nil,
                        updateCount > 0 ? "~\(updateCount)" : nil,
                        deleteCount > 0 ? "-\(deleteCount)" : nil
                    ].compactMap { $0 }.joined(separator: " ")

                    logger.info("   └─ Tx[\(i)]: author=\(author) context=\(contextName) entities=[\(entityList)] changes=\(changesSummary.isEmpty ? "none" : changesSummary)")
                }
            } catch {
                logger.error("   └─ History fetch failed: \(error.localizedDescription)")
            }
        }
    }
    #endif

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

    // MARK: - Bridge 1: Core Data → GRDB Sync

    /// Sync Core Data changes to GRDB (phone → Mac data flow)
    /// Called after CloudKit pushes changes to Core Data
    private func syncCoreDataToGRDB(context: NSManagedObjectContext) async {
        logger.info("🌉 [Bridge 1] Starting Core Data → GRDB sync")
        let syncStart = Date()

        let repository = GRDBRepository()
        var createdCount = 0
        var updatedCount = 0
        var errorCount = 0

        await context.perform {
            // Query all VoiceMemo entities (we'll use lastModified for change detection)
            let fetchRequest: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \VoiceMemo.lastModified, ascending: false)]

            do {
                let cdMemos = try context.fetch(fetchRequest)
                logger.info("🌉 [Bridge 1] Found \(cdMemos.count) memo(s) in Core Data")

                for cdMemo in cdMemos {
                    guard let memoId = cdMemo.id else {
                        logger.warning("🌉 [Bridge 1] Skipping memo with nil ID")
                        continue
                    }

                    Task {
                        do {
                            // Check if exists in GRDB
                            let existingMemo = try await repository.fetchMemo(id: memoId)

                            if let existing = existingMemo {
                                // Compare timestamps - Core Data wins (source of truth from phone)
                                let cdModified = cdMemo.lastModified ?? Date.distantPast
                                let grdbModified = existing.memo.lastModified

                                if cdModified > grdbModified {
                                    logger.info("🌉 [Bridge 1] Updating memo in GRDB: '\(cdMemo.title ?? "Untitled")' (CD: \(cdModified) > GRDB: \(grdbModified))")
                                    let memoModel = self.convertToMemoModel(cdMemo)
                                    try await repository.saveMemo(memoModel)
                                    updatedCount += 1
                                    logger.info("✅ [Bridge 1] Updated: \(memoId)")
                                } else {
                                    logger.info("⏭️ [Bridge 1] Skipping memo (GRDB is newer): '\(cdMemo.title ?? "Untitled")'")
                                }
                            } else {
                                // New memo - create in GRDB
                                logger.info("🌉 [Bridge 1] Creating new memo in GRDB: '\(cdMemo.title ?? "Untitled")'")
                                let memoModel = self.convertToMemoModel(cdMemo)
                                try await repository.saveMemo(memoModel)
                                createdCount += 1
                                logger.info("✅ [Bridge 1] Created: \(memoId)")
                            }
                        } catch {
                            logger.error("❌ [Bridge 1] Failed to sync memo \(memoId): \(error.localizedDescription)")
                            errorCount += 1
                        }
                    }
                }
            } catch {
                logger.error("❌ [Bridge 1] Failed to fetch Core Data memos: \(error.localizedDescription)")
            }
        }

        // Wait a moment for all async tasks to complete
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        let duration = Date().timeIntervalSince(syncStart)
        logger.info("🌉 [Bridge 1] Complete: \(createdCount) created, \(updatedCount) updated, \(errorCount) errors (\(String(format: "%.1fs", duration)))")
    }

    /// Convert Core Data VoiceMemo to GRDB MemoModel
    private func convertToMemoModel(_ cdMemo: VoiceMemo) -> MemoModel {
        let id = cdMemo.id ?? UUID()
        let createdAt = cdMemo.createdAt ?? Date()
        let lastModified = cdMemo.lastModified ?? Date()

        // Convert sort order (Core Data uses Int32, GRDB uses Int)
        let sortOrder = Int(cdMemo.sortOrder)

        logger.info("🔄 [Bridge 1] Converting memo: '\(cdMemo.title ?? "Untitled")' (id: \(id))")

        return MemoModel(
            id: id,
            createdAt: createdAt,
            lastModified: lastModified,
            title: cdMemo.title,
            duration: cdMemo.duration,
            sortOrder: sortOrder,
            transcription: cdMemo.transcription,
            notes: cdMemo.notes,
            summary: cdMemo.summary,
            tasks: cdMemo.tasks,
            reminders: cdMemo.reminders,
            audioFilePath: cdMemo.fileURL, // Core Data stores path as string
            waveformData: cdMemo.waveformData,
            isTranscribing: cdMemo.isTranscribing,
            isProcessingSummary: cdMemo.isProcessingSummary,
            isProcessingTasks: cdMemo.isProcessingTasks,
            isProcessingReminders: cdMemo.isProcessingReminders,
            autoProcessed: cdMemo.autoProcessed,
            originDeviceId: cdMemo.originDeviceId,
            macReceivedAt: cdMemo.macReceivedAt,
            cloudSyncedAt: cdMemo.cloudSyncedAt,
            pendingWorkflowIds: cdMemo.pendingWorkflowIds
        )
    }
}
