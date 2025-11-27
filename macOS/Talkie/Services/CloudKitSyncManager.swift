//
//  CloudKitSyncManager.swift
//  Talkie macOS
//
//  Token-based CloudKit sync - fetches only changed records since last sync.
//  No persistent history tracking = no WAL bloat.
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
    private let syncInterval: TimeInterval = 300 // 5 minutes

    private init() {}

    func configure(with context: NSManagedObjectContext) {
        self.viewContext = context

        // Start periodic sync timer
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncNow()
            }
        }

        logger.info("CloudKitSyncManager configured (sync interval: \(Int(self.syncInterval))s)")

        if serverChangeToken != nil {
            logger.info("Existing server change token found - will fetch delta")
        } else {
            logger.info("No server change token - will perform full sync")
        }
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
