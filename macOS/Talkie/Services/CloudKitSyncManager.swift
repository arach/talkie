//
//  CloudKitSyncManager.swift
//  Talkie macOS
//
//  Simple CloudKit sync manager - syncs every minute while app is open.
//  NSPersistentCloudKitContainer handles the actual sync; this is for UI feedback.
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

    private var syncTimer: Timer?
    private var remoteChangeObserver: NSObjectProtocol?
    private var debounceTimer: Timer?
    private let syncInterval: TimeInterval = 60 // 1 minute - simple and predictable
    private let debounceInterval: TimeInterval = 3.0 // Coalesce rapid notifications

    private init() {}

    func configure(with context: NSManagedObjectContext) {
        self.viewContext = context

        // Start periodic sync timer (every minute while app is open)
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncNow()
            }
        }

        // Listen for remote store changes (real-time updates from other devices)
        // Only sync if there are actual transactions, not just CloudKit housekeeping
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }

            // Check if there are actual changes worth syncing
            let hasRealChanges = self.checkForRealChanges(notification: notification)

            #if DEBUG
            self.logRemoteChangeNotification(notification, hasRealChanges: hasRealChanges)
            #endif

            // Only schedule sync if there are real data changes
            if hasRealChanges {
                Task { @MainActor in
                    self.scheduleDebounceSync()
                }
            }
        }

        logger.info("CloudKitSyncManager configured (sync every \(Int(self.syncInterval))s)")

        if serverChangeToken != nil {
            logger.info("Existing server change token found - will fetch delta")
        } else {
            logger.info("No server change token - will perform full sync")
        }
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
        // Use DispatchQueue to defer @Published updates and avoid
        // "Publishing changes from within view updates" warnings
        DispatchQueue.main.async {
            self.isSyncing = true
            SyncStatusManager.shared.setSyncing()
        }

        NotificationCenter.default.post(name: .talkieSyncStarted, object: nil)

        logger.info("Starting CloudKit sync...")

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
                PersistenceController.markMemosAsReceivedByMac(context: context)
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
