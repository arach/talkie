//
//  Persistence.swift
//  Talkie macOS
//
//  Clean token-based CloudKit sync without persistent history tracking bloat.
//

import CoreData
import CloudKit
import os
import Combine

private let logger = Logger(subsystem: "jdi.talkie-os-mac", category: "Persistence")

// MARK: - Sync Status Manager

@MainActor
class SyncStatusManager: ObservableObject {
    static let shared = SyncStatusManager()

    enum SyncState: Equatable {
        case idle
        case syncing
        case synced
        case error(String)
    }

    @Published var state: SyncState = .idle
    @Published var lastSyncDate: Date?
    @Published var iCloudAvailable: Bool = false
    @Published var pendingChanges: Int = 0

    private var displayTimer: Timer?

    private init() {
        // Update display every 30s so "Just now" becomes "30s ago" etc.
        displayTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.objectWillChange.send()
            }
        }
    }

    func setSyncing() {
        state = .syncing
    }

    func setSynced(changes: Int = 0) {
        lastSyncDate = Date()
        state = .synced
        pendingChanges = 0

        if changes > 0 {
            // Post notification for console
            NotificationCenter.default.post(
                name: .talkieSyncCompleted,
                object: nil,
                userInfo: ["changes": changes]
            )
        }
    }

    func setCloudAvailable(_ available: Bool) {
        iCloudAvailable = available
        if available && state == .idle {
            state = .synced
            lastSyncDate = Date()
        }
    }

    func setError(_ message: String) {
        state = .error(message)
    }

    var lastSyncAgo: String {
        guard let lastSync = lastSyncDate else {
            return "—"
        }

        let interval = Date().timeIntervalSince(lastSync)

        if interval < 10 {
            return "just now"
        } else if interval < 60 {
            return "\(Int(interval))s ago"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
    }
}

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext

        // Create sample voice memos for preview
        for i in 0..<5 {
            let memo = VoiceMemo(context: viewContext)
            memo.id = UUID()
            memo.title = "Sample Recording \(i + 1)"
            memo.createdAt = Date().addingTimeInterval(-Double(i * 3600))
            memo.duration = Double.random(in: 30...180)
            memo.fileURL = "sample_\(i).m4a"
            memo.sortOrder = Int32(-Date().addingTimeInterval(-Double(i * 3600)).timeIntervalSince1970)

            if i % 2 == 0 {
                memo.transcription = "This is a sample transcription for recording \(i + 1)."
            }
        }

        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "talkie")

        logger.info("Initializing PersistenceController (token-based sync)...")

        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
            logger.info("Using in-memory store")
        } else {
            // Configure CloudKit sync - WITHOUT persistent history tracking
            // This dramatically reduces WAL bloat and unnecessary disk I/O
            if let description = container.persistentStoreDescriptions.first {
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: "iCloud.com.jdi.talkie"
                )
                // NOTE: We intentionally DO NOT set:
                // - NSPersistentHistoryTrackingKey (causes WAL bloat)
                // - NSPersistentStoreRemoteChangeNotificationPostOptionKey (constant notifications)
                // Instead, we use CloudKit's server change tokens for efficient delta sync

                logger.info("CloudKit container: iCloud.com.jdi.talkie (token-based sync)")
                logger.info("Store URL: \(description.url?.absoluteString ?? "nil")")
            }
        }

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                logger.error("Core Data store failed to load: \(error.localizedDescription)")
                logger.error("Error details: \(error.userInfo)")
            } else {
                logger.info("Core Data loaded successfully")
                logger.info("Store type: \(storeDescription.type)")

                if let cloudKitOptions = storeDescription.cloudKitContainerOptions {
                    logger.info("CloudKit container ID: \(cloudKitOptions.containerIdentifier)")
                }
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Check iCloud account status and start initial sync
        PersistenceController.checkiCloudStatus()

        // Start the CloudKit sync manager
        let viewContext = container.viewContext
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            CloudKitSyncManager.shared.configure(with: viewContext)
            CloudKitSyncManager.shared.syncNow()

            PersistenceController.logMemoCount(context: viewContext)
        }
    }

    private static func checkiCloudStatus() {
        let container = CKContainer(identifier: "iCloud.com.jdi.talkie")

        // Log build configuration (Development vs Production environment)
        #if DEBUG
        logger.info("🔧 Build Configuration: DEBUG (uses CloudKit Development environment)")
        #else
        logger.info("🚀 Build Configuration: RELEASE (uses CloudKit Production environment)")
        #endif

        container.accountStatus { status, error in
            if let error = error {
                logger.error("❌ iCloud account error: \(error.localizedDescription)")
                return
            }

            switch status {
            case .available:
                logger.info("✅ iCloud account status: Available")
                Task { @MainActor in
                    SyncStatusManager.shared.setCloudAvailable(true)
                }
                // Now fetch detailed zone and database info
                fetchCloudKitDatabaseInfo(container: container)
            case .noAccount:
                logger.warning("⚠️ iCloud account status: No Account - user not signed into iCloud")
                Task { @MainActor in
                    SyncStatusManager.shared.setCloudAvailable(false)
                    SyncStatusManager.shared.setError("No iCloud account")
                }
            case .restricted:
                logger.warning("⚠️ iCloud account status: Restricted")
                Task { @MainActor in
                    SyncStatusManager.shared.setCloudAvailable(false)
                    SyncStatusManager.shared.setError("iCloud restricted")
                }
            case .couldNotDetermine:
                logger.warning("⚠️ iCloud account status: Could not determine")
                Task { @MainActor in
                    SyncStatusManager.shared.setCloudAvailable(false)
                }
            case .temporarilyUnavailable:
                logger.warning("⚠️ iCloud account status: Temporarily unavailable")
                Task { @MainActor in
                    SyncStatusManager.shared.setCloudAvailable(false)
                    SyncStatusManager.shared.setError("iCloud unavailable")
                }
            @unknown default:
                logger.warning("⚠️ iCloud account status: Unknown")
            }
        }
    }

    private static func fetchCloudKitDatabaseInfo(container: CKContainer) {
        let privateDB = container.privateCloudDatabase

        // Log database scope
        logger.info("📦 CloudKit Database Scope: Private Database")
        logger.info("📦 Container ID: \(container.containerIdentifier ?? "unknown")")

        // Fetch all record zones to understand structure
        privateDB.fetchAllRecordZones { zones, error in
            if let error = error {
                logger.error("❌ Failed to fetch zones: \(error.localizedDescription)")
                return
            }

            guard let zones = zones else {
                logger.warning("⚠️ No zones returned")
                return
            }

            logger.info("🗂️ Found \(zones.count) CloudKit zone(s):")
            for zone in zones {
                logger.info("  📁 Zone: \(zone.zoneID.zoneName) (owner: \(zone.zoneID.ownerName))")

                // Query records in each zone
                queryRecordsInZone(database: privateDB, zoneID: zone.zoneID)
            }
        }
    }

    private static func queryRecordsInZone(database: CKDatabase, zoneID: CKRecordZone.ID) {
        // Core Data + CloudKit uses a zone named "com.apple.coredata.cloudkit.zone"
        // Query for CD_VoiceMemo records (Core Data prefixes with CD_)
        let query = CKQuery(recordType: "CD_VoiceMemo", predicate: NSPredicate(value: true))

        database.perform(query, inZoneWith: zoneID) { records, error in
            if let error = error {
                // This might fail if the record type doesn't exist in this zone
                let ckError = error as? CKError
                if ckError?.code == .unknownItem {
                    logger.info("  📝 Zone '\(zoneID.zoneName)': No CD_VoiceMemo records (type not found)")
                } else {
                    logger.error("  ❌ Query failed in zone '\(zoneID.zoneName)': \(error.localizedDescription)")
                }
                return
            }

            guard let records = records else {
                logger.info("  📝 Zone '\(zoneID.zoneName)': No records returned")
                return
            }

            logger.info("  📝 Zone '\(zoneID.zoneName)': Found \(records.count) CD_VoiceMemo record(s)")

            // Log first few record details
            for record in records.prefix(3) {
                let title = record["CD_title"] as? String ?? "Untitled"
                let createdAt = record.creationDate?.description ?? "unknown"
                logger.info("    • \(title) (created: \(createdAt), recordID: \(record.recordID.recordName.prefix(20))...)")
            }
            if records.count > 3 {
                logger.info("    ... and \(records.count - 3) more records")
            }
        }
    }

    private static func logMemoCount(context: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()

        do {
            let memos = try context.fetch(fetchRequest)
            logger.info("Total VoiceMemos in database: \(memos.count)")
            for memo in memos.prefix(5) {
                logger.info("  - \(memo.title ?? "Untitled") (created: \(memo.createdAt?.description ?? "nil"))")
            }
            if memos.count > 5 {
                logger.info("  ... and \(memos.count - 5) more")
            }
        } catch {
            logger.error("Failed to fetch memos: \(error.localizedDescription)")
        }
    }
}

// MARK: - Custom Notifications

extension Notification.Name {
    /// Posted when a sync operation completes with changes
    static let talkieSyncCompleted = Notification.Name("talkieSyncCompleted")
    /// Posted when sync starts
    static let talkieSyncStarted = Notification.Name("talkieSyncStarted")
}
