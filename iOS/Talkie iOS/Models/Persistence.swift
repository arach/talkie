//
//  Persistence.swift
//  talkie
//
//  Clean CloudKit sync without persistent history tracking bloat.
//

import CoreData
import CloudKit
#if os(iOS)
import UIKit
import WidgetKit
#else
import AppKit
#endif

struct PersistenceController {
    static let shared = PersistenceController()

    /// Unique identifier for this device
    static var deviceId: String {
        #if os(iOS)
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        // macOS device identifier
        return "mac-" + (Host.current().localizedName ?? UUID().uuidString)
        #endif
    }

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

        AppLogger.persistence.info("🚀 Initializing PersistenceController...")

        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
            AppLogger.persistence.info("Using in-memory store")
        } else {
            // Configure CloudKit sync - MUST enable history tracking for proper sync!
            // NSPersistentCloudKitContainer requires these options to function correctly.
            if let description = container.persistentStoreDescriptions.first {
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: "iCloud.com.jdi.talkie"
                )

                // REQUIRED: Enable persistent history tracking for CloudKit mirroring
                // Without this, changes won't be pushed to CloudKit!
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)

                // REQUIRED: Enable remote change notifications for real-time sync
                // Without this, we won't receive updates from other devices!
                description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

                AppLogger.persistence.info("☁️ CloudKit container: iCloud.com.jdi.talkie (full sync enabled)")
                AppLogger.persistence.info("📂 Store URL: \(description.url?.absoluteString ?? "nil")")
            }
        }

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                AppLogger.persistence.error("❌ Core Data store failed to load: \(error.localizedDescription)")
                AppLogger.persistence.error("Error details: \(error.userInfo)")
            } else {
                AppLogger.persistence.info("✅ Core Data loaded successfully")
                AppLogger.persistence.info("Store type: \(storeDescription.type)")

                if let cloudKitOptions = storeDescription.cloudKitContainerOptions {
                    AppLogger.persistence.info("☁️ CloudKit container ID: \(cloudKitOptions.containerIdentifier)")
                }
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Check iCloud account status
        PersistenceController.checkiCloudStatus()

        // Log initial memo count after a short delay
        let viewContext = container.viewContext
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            PersistenceController.logMemoCount(context: viewContext)
        }

        // Monitor CloudKit sync events to track when memos are synced
        setupCloudKitSyncMonitoring()
        // Note: automaticallyMergesChangesFromParent handles CloudKit updates automatically
        // Detail view refreshes on appear to get latest state
    }

    /// Monitor CloudKit sync events to update cloudSyncedAt on memos
    private func setupCloudKitSyncMonitoring() {
        let containerRef = container // Capture strong reference

        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
                AppLogger.persistence.warning("☁️ CloudKit event notification received but no event in userInfo")
                return
            }

            // Log all CloudKit events for debugging
            let eventTypeName: String
            switch event.type {
            case .setup: eventTypeName = "setup"
            case .import: eventTypeName = "import"
            case .export: eventTypeName = "export"
            @unknown default: eventTypeName = "unknown"
            }

            if let error = event.error {
                AppLogger.persistence.error("☁️ CloudKit \(eventTypeName) FAILED: \(error.localizedDescription)")

                // Check for specific CloudKit errors
                if let ckError = error as? CKError {
                    AppLogger.persistence.error("  CKError code: \(ckError.code.rawValue)")
                    if ckError.code == .serverRecordChanged {
                        AppLogger.persistence.error("  Server record changed - conflict detected")
                    } else if ckError.code == .networkUnavailable || ckError.code == .networkFailure {
                        AppLogger.persistence.error("  Network issue - will retry when connected")
                    } else if ckError.code == .quotaExceeded {
                        AppLogger.persistence.error("  iCloud quota exceeded!")
                    }
                }
            } else if event.succeeded {
                AppLogger.persistence.info("☁️ CloudKit \(eventTypeName) succeeded")

                // We care about successful export events (data pushed to CloudKit)
                if event.type == .export {
                    AppLogger.persistence.info("☁️ Export succeeded - marking memos as synced")
                    PersistenceController.markRecentMemosAsSynced(context: containerRef.viewContext)
                }
            } else {
                AppLogger.persistence.info("☁️ CloudKit \(eventTypeName) in progress...")
            }
        }

        AppLogger.persistence.info("☁️ CloudKit sync monitoring initialized")
    }

    /// Mark all memos without cloudSyncedAt as synced
    /// Called when CloudKit export succeeds - if export worked, all local data is in CloudKit
    static func markRecentMemosAsSynced(context: NSManagedObjectContext) {
        context.perform {
            let fetchRequest: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "cloudSyncedAt == nil")

            do {
                let unsyncedMemos = try context.fetch(fetchRequest)
                guard !unsyncedMemos.isEmpty else { return }

                let now = Date()
                for memo in unsyncedMemos {
                    memo.cloudSyncedAt = now
                }

                try context.save()
                AppLogger.persistence.info("☁️ Marked \(unsyncedMemos.count) memo(s) as synced to iCloud")
            } catch {
                AppLogger.persistence.error("❌ Failed to mark memos as synced: \(error.localizedDescription)")
            }
        }
    }

    private static func checkiCloudStatus() {
        let container = CKContainer(identifier: "iCloud.com.jdi.talkie")

        // Log build configuration (Development vs Production environment)
        #if DEBUG
        AppLogger.persistence.info("🔧 Build Configuration: DEBUG (uses CloudKit Development environment)")
        #else
        AppLogger.persistence.info("🚀 Build Configuration: RELEASE (uses CloudKit Production environment)")
        AppLogger.persistence.info("⚠️ Ensure CloudKit schema is deployed to Production via CloudKit Dashboard!")
        #endif

        container.accountStatus { status, error in
            if let error = error {
                AppLogger.persistence.error("❌ iCloud account error: \(error.localizedDescription)")
                return
            }

            switch status {
            case .available:
                AppLogger.persistence.info("✅ iCloud account status: Available")
                // Now fetch detailed zone and database info
                fetchCloudKitDatabaseInfo(container: container)
            case .noAccount:
                AppLogger.persistence.warning("⚠️ iCloud account status: No Account - user not signed into iCloud")
            case .restricted:
                AppLogger.persistence.warning("⚠️ iCloud account status: Restricted")
            case .couldNotDetermine:
                AppLogger.persistence.warning("⚠️ iCloud account status: Could not determine")
            case .temporarilyUnavailable:
                AppLogger.persistence.warning("⚠️ iCloud account status: Temporarily unavailable")
            @unknown default:
                AppLogger.persistence.warning("⚠️ iCloud account status: Unknown")
            }
        }
    }

    private static func fetchCloudKitDatabaseInfo(container: CKContainer) {
        let privateDB = container.privateCloudDatabase

        // Log database scope
        AppLogger.persistence.info("📦 CloudKit Database Scope: Private Database")
        AppLogger.persistence.info("📦 Container ID: \(container.containerIdentifier ?? "unknown")")

        // Fetch all record zones to understand structure
        privateDB.fetchAllRecordZones { zones, error in
            if let error = error {
                AppLogger.persistence.error("❌ Failed to fetch zones: \(error.localizedDescription)")
                return
            }

            guard let zones = zones else {
                AppLogger.persistence.warning("⚠️ No zones returned")
                return
            }

            AppLogger.persistence.info("🗂️ Found \(zones.count) CloudKit zone(s):")
            for zone in zones {
                AppLogger.persistence.info("  📁 Zone: \(zone.zoneID.zoneName) (owner: \(zone.zoneID.ownerName))")

                // Query records in each zone
                queryRecordsInZone(database: privateDB, zoneID: zone.zoneID)
            }
        }
    }

    private static func queryRecordsInZone(database: CKDatabase, zoneID: CKRecordZone.ID) {
        // Core Data + CloudKit uses a zone named "com.apple.coredata.cloudkit.zone"
        // Query for CD_VoiceMemo records (Core Data prefixes with CD_)
        let query = CKQuery(recordType: "CD_VoiceMemo", predicate: NSPredicate(value: true))

        database.fetch(withQuery: query, inZoneWith: zoneID, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { result in
            switch result {
            case .failure(let error):
                // This might fail if the record type doesn't exist in this zone
                let ckError = error as? CKError
                if ckError?.code == .unknownItem {
                    AppLogger.persistence.info("  📝 Zone '\(zoneID.zoneName)': No CD_VoiceMemo records (type not found)")
                } else {
                    AppLogger.persistence.error("  ❌ Query failed in zone '\(zoneID.zoneName)': \(error.localizedDescription)")
                }
                return

            case .success(let (matchResults, _)):
                let records = matchResults.compactMap { try? $0.1.get() }
                if records.isEmpty {
                    AppLogger.persistence.info("  📝 Zone '\(zoneID.zoneName)': No records returned")
                    return
                }

                AppLogger.persistence.info("  📝 Zone '\(zoneID.zoneName)': Found \(records.count) CD_VoiceMemo record(s)")

                // Log first few record details
                for record in records.prefix(3) {
                    let title = record["CD_title"] as? String ?? "Untitled"
                    let createdAt = record.creationDate?.description ?? "unknown"
                    AppLogger.persistence.info("    • \(title) (created: \(createdAt), recordID: \(record.recordID.recordName.prefix(20))...)")
                }
                if records.count > 3 {
                    AppLogger.persistence.info("    ... and \(records.count - 3) more records")
                }
            }
        }
    }

    private static func logMemoCount(context: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)]

        do {
            let memos = try context.fetch(fetchRequest)
            AppLogger.persistence.info("📊 Total VoiceMemos in database: \(memos.count)")
            for memo in memos.prefix(3) {
                AppLogger.persistence.info("  - \(memo.title ?? "Untitled") (created: \(memo.createdAt?.description ?? "nil"))")
            }
            if memos.count > 3 {
                AppLogger.persistence.info("  ... and \(memos.count - 3) more")
            }

            // Update widget with memo count and recent memos
            #if os(iOS)
            updateWidgetData(count: memos.count, recentMemos: Array(memos.prefix(5)))
            #endif
        } catch {
            AppLogger.persistence.error("❌ Failed to fetch memos: \(error.localizedDescription)")
        }
    }

    // MARK: - Widget Support

    #if os(iOS)
    /// App Group identifier for sharing data with widgets
    static let appGroupIdentifier = "group.com.jdi.talkie"

    /// Snapshot of a memo for widget display
    struct WidgetMemoSnapshot: Codable {
        let id: String
        let title: String
        let duration: TimeInterval
        let hasTranscription: Bool
        let hasAIProcessing: Bool
        let isSynced: Bool
        let createdAt: Date
    }

    /// Update the widget with the current memo count and recent memos
    static func updateWidgetData(count: Int, recentMemos: [VoiceMemo]) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            AppLogger.persistence.warning("⚠️ Could not access App Group UserDefaults")
            return
        }

        // Save count
        defaults.set(count, forKey: "memoCount")
        defaults.set(Date(), forKey: "lastUpdated")

        // Save recent memos as JSON
        let snapshots = recentMemos.prefix(5).map { memo in
            WidgetMemoSnapshot(
                id: memo.id?.uuidString ?? UUID().uuidString,
                title: memo.title ?? "Untitled",
                duration: memo.duration,
                hasTranscription: memo.transcription != nil && !memo.transcription!.isEmpty,
                hasAIProcessing: memo.summary != nil && !memo.summary!.isEmpty,
                isSynced: memo.cloudSyncedAt != nil,
                createdAt: memo.createdAt ?? Date()
            )
        }

        if let data = try? JSONEncoder().encode(Array(snapshots)) {
            defaults.set(data, forKey: "recentMemos")
        }

        defaults.synchronize()

        // Tell WidgetKit to refresh
        WidgetCenter.shared.reloadAllTimelines()
        AppLogger.persistence.info("📱 Widget updated with \(count) memos")
    }

    /// Legacy method for compatibility
    static func updateWidgetMemoCount(_ count: Int) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            AppLogger.persistence.warning("⚠️ Could not access App Group UserDefaults")
            return
        }

        defaults.set(count, forKey: "memoCount")
        defaults.set(Date(), forKey: "lastUpdated")
        defaults.synchronize()

        // Tell WidgetKit to refresh
        WidgetCenter.shared.reloadAllTimelines()
        AppLogger.persistence.info("📱 Widget updated with memo count: \(count)")
    }

    /// Call this when memos are added/deleted to update widget
    static func refreshWidgetData(context: NSManagedObjectContext) {
        context.perform {
            let fetchRequest: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)]
            fetchRequest.fetchLimit = 5

            do {
                let recentMemos = try context.fetch(fetchRequest)
                let countRequest: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
                let count = try context.count(for: countRequest)
                updateWidgetData(count: count, recentMemos: recentMemos)
            } catch {
                AppLogger.persistence.error("❌ Failed to get memos for widget: \(error.localizedDescription)")
            }
        }
    }
    #endif
}
