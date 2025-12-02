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

private let logger = Logger(subsystem: "jdi.talkie-os-mac", category: "CloudKitSync")

@MainActor
class CloudKitSyncManager: ObservableObject {
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

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var lastChangeCount: Int = 0

    // MARK: - Timers and Schedulers
    private var syncTimer: Timer?
    private var remoteChangeObserver: NSObjectProtocol?
    private var debounceTimer: Timer?
    private let syncInterval: TimeInterval = 60 // 1 minute - simple and predictable
    private let debounceInterval: TimeInterval = 3.0 // Coalesce rapid notifications

    // Background activity scheduler - wakes app even when terminated
    private var backgroundActivityScheduler: NSBackgroundActivityScheduler?
    private let backgroundSyncInterval: TimeInterval = 2 * 60 // 2 minutes for background (tighter for testing)

    // App Nap prevention - keeps sync running when app loses focus
    private var appNapActivity: NSObjectProtocol?

    private init() {}

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

        logger.info("CloudKitSyncManager configured - foreground: \(Int(self.syncInterval))s, background: \(Int(self.backgroundSyncInterval))s")

        if serverChangeToken != nil {
            logger.info("Existing server change token found - will fetch delta")
        } else {
            logger.info("No server change token - will perform full sync")
        }

        // Run one-time migration to mark all existing memos as auto-processed
        // This ensures auto-run only affects future memos
        Task {
            await migrateExistingMemosIfNeeded(context: context)
        }
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

            let now = Date()
            let nextExpected = now.addingTimeInterval(self.backgroundSyncInterval)
            logger.info("Background scheduler fired at \(timeFormatter.string(from: now)) - next expected ~\(timeFormatter.string(from: nextExpected))")

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

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let now = Date()
        let nextSync = now.addingTimeInterval(syncInterval)
        logger.info("Timer sync at \(timeFormatter.string(from: now)) - next at \(timeFormatter.string(from: nextSync))")

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

        logger.info("Starting sync at \(timeFormatter.string(from: startTime))...")

        do {
            let changes = try await fetchChanges()

            DispatchQueue.main.async {
                self.lastSyncDate = Date()
                self.lastChangeCount = changes
                self.isSyncing = false
                SyncStatusManager.shared.setSynced(changes: changes)
            }

            NotificationCenter.default.post(
                name: .talkieSyncCompleted,
                object: nil,
                userInfo: ["changes": changes]
            )

            // Mark memos from other devices as received by Mac
            if let context = self.viewContext {
                // If we detected changes, wait a moment for NSPersistentCloudKitContainer
                // to import them into Core Data. Our manual fetch is just for tracking -
                // the actual import is done asynchronously by the container.
                if changes > 0 {
                    logger.info("Waiting for Core Data import...")
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                    context.refreshAllObjects() // Refresh after import
                }

                PersistenceController.markMemosAsReceivedByMac(context: context)
                // Process any pending workflow requests from iOS
                PersistenceController.processPendingWorkflows(context: context)
                // Check for "Hey Talkie" triggers in newly synced memos
                await self.processTriggers(context: context)
            }

            if changes > 0 {
                logger.info("Sync completed: \(changes) change(s)")
            } else {
                logger.info("Sync completed: no changes")
            }

        } catch {
            logger.error("Sync failed: \(error.localizedDescription)")

            DispatchQueue.main.async {
                self.isSyncing = false
                SyncStatusManager.shared.setError(error.localizedDescription)
            }
        }
    }

    // MARK: - Auto-Run Workflow Processing

    /// Process auto-run workflows for newly synced memos
    private func processTriggers(context: NSManagedObjectContext) async {
        // One-time migration: mark all existing memos as processed
        // This ensures we only process memos created after this feature shipped
        await migrateExistingMemosIfNeeded(context: context)

        // IMPORTANT: Refresh the context to see changes from NSPersistentCloudKitContainer
        // Without this, the context may have stale data cached and miss new memos
        context.refreshAllObjects()

        // Find memos needing processing:
        // 1. autoProcessed == false (new iOS app with schema fix)
        // 2. OR recently created from iOS (within 10 min) that haven't been processed
        //    This handles memos from old iOS app that didn't have autoProcessed attribute
        let tenMinutesAgo = Date().addingTimeInterval(-10 * 60)

        let request = VoiceMemo.fetchRequest()
        // Memos explicitly marked as not processed, OR recent iOS memos
        request.predicate = NSPredicate(
            format: "autoProcessed == NO OR (createdAt > %@ AND originDeviceId != nil AND originDeviceId != %@)",
            tenMinutesAgo as NSDate,
            PersistenceController.deviceId
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)]
        request.fetchLimit = 10

        do {
            let allCandidates = try context.fetch(request)

            // Filter to only memos that actually need processing
            // (recent iOS memos that haven't been auto-run yet)
            let memos = allCandidates.filter { memo in
                // If explicitly marked as not processed, include it
                if !memo.autoProcessed {
                    return true
                }
                // If it's a recent iOS memo, check if it has any workflow runs
                // If no workflow runs, it needs processing
                let hasWorkflowRuns = (memo.workflowRuns?.count ?? 0) > 0
                return !hasWorkflowRuns
            }

            // Debug: check recent memos to understand what's happening
            let recentRequest = VoiceMemo.fetchRequest()
            recentRequest.sortDescriptors = [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)]
            recentRequest.fetchLimit = 3
            if let recentMemos = try? context.fetch(recentRequest) {
                for memo in recentMemos {
                    let origin = memo.originDeviceId ?? "local"
                    let isFromiOS = origin != PersistenceController.deviceId && origin != "local"
                    logger.info("Recent memo: '\(memo.title ?? "Untitled")' autoProcessed=\(memo.autoProcessed) hasTranscript=\(memo.currentTranscript != nil) origin=\(isFromiOS ? "iOS" : "local")")
                }
            }

            logger.info("processTriggers: Found \(memos.count) unprocessed memo(s) (checked \(allCandidates.count) candidates)")

            for memo in memos {
                logger.info("Processing memo: '\(memo.title ?? "Untitled")' (hasTranscript: \(memo.currentTranscript != nil))")
                // AutoRunProcessor handles all checks (transcript, settings, etc.)
                await AutoRunProcessor.shared.processNewMemo(memo, context: context)
            }

            if !memos.isEmpty {
                try context.save()
                logger.info("Processed auto-run workflows for \(memos.count) memo(s)")
            }
        } catch {
            logger.error("Failed to process auto-run workflows: \(error.localizedDescription)")
        }
    }

    private static let autoRunMigrationKey = "autoRunMigrationCompleted"

    /// One-time migration: mark all existing memos as trigger-processed
    /// This ensures the auto-run feature is forward-only
    private func migrateExistingMemosIfNeeded(context: NSManagedObjectContext) async {
        guard !UserDefaults.standard.bool(forKey: Self.autoRunMigrationKey) else { return }

        let request = VoiceMemo.fetchRequest()
        request.predicate = NSPredicate(format: "autoProcessed == NO OR autoProcessed == nil")

        do {
            let memos = try context.fetch(request)
            for memo in memos {
                memo.autoProcessed = true
            }
            if !memos.isEmpty {
                try context.save()
                logger.info("Auto-run migration: marked \(memos.count) existing memo(s) as processed")
            }
            UserDefaults.standard.set(true, forKey: Self.autoRunMigrationKey)
        } catch {
            logger.error("Auto-run migration failed: \(error.localizedDescription)")
        }
    }

    private func fetchChanges() async throws -> Int {
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

                    if totalChanges > 0 {
                        logger.info("Fetched \(changedRecords.count) changed, \(deletedRecordIDs.count) deleted")
                    }

                    // Note: NSPersistentCloudKitContainer handles the actual Core Data import
                    // automatically. We're just tracking changes for UI feedback.
                    // The records we fetched here are informational - Core Data's mirroring
                    // will handle the actual database updates.

                    continuation.resume(returning: totalChanges)

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

    #if DEBUG
    /// Log details about remote change notifications for debugging (dev builds only)
    private func logRemoteChangeNotification(_ notification: Notification, hasRealChanges: Bool) {
        var details: [String] = []

        // Extract store URL if available
        if let storeURL = notification.userInfo?["storeURL"] as? URL {
            details.append("store: \(storeURL.lastPathComponent)")
        }

        // Extract store UUID
        if let storeUUID = notification.userInfo?["NSStoreUUID"] as? String {
            details.append("uuid: \(storeUUID.prefix(8))...")
        }

        // Show whether this will trigger a sync
        details.append(hasRealChanges ? "→ SYNC" : "→ skip")

        let detailString = details.joined(separator: " | ")
        logger.info("📡 RemoteChange: \(detailString)")

        // Now fetch actual persistent history to see what changed
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
                      let transactions = result.result as? [NSPersistentHistoryTransaction] else {
                    logger.info("   └─ History: no transactions")
                    return
                }

                if transactions.isEmpty {
                    logger.info("   └─ History: 0 transactions (housekeeping only)")
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
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Synced \(formatter.localizedString(for: date, relativeTo: Date()))"
        } else {
            return "Not synced"
        }
    }
}
