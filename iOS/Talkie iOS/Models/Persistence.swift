//
//  Persistence.swift
//  talkie
//
//  Created by Arach Tchoupani on 2025-11-23.
//

import CoreData
import CloudKit

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

        AppLogger.persistence.info("🚀 Initializing PersistenceController...")

        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
            AppLogger.persistence.info("Using in-memory store")
        } else {
            // Configure CloudKit sync
            if let description = container.persistentStoreDescriptions.first {
                // Set the CloudKit container identifier explicitly
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: "iCloud.com.jdi.talkie"
                )
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

                AppLogger.persistence.info("☁️ CloudKit container: iCloud.com.jdi.talkie")
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
                } else {
                    AppLogger.persistence.warning("⚠️ No CloudKit container options set!")
                }
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Listen for remote change notifications
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { _ in
            AppLogger.persistence.info("📥 Remote change notification received from iCloud")
        }

        // Listen for Core Data save notifications to track CloudKit sync
        NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: container.viewContext,
            queue: .main
        ) { notification in
            let inserted = (notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>)?.count ?? 0
            let updated = (notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject>)?.count ?? 0
            let deleted = (notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject>)?.count ?? 0
            AppLogger.persistence.info("💾 Core Data saved - inserted: \(inserted), updated: \(updated), deleted: \(deleted)")
        }

        // Check iCloud account status
        PersistenceController.checkiCloudStatus()

        // Log initial memo count after a short delay
        let viewContext = container.viewContext
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            PersistenceController.logMemoCount(context: viewContext)
        }
    }

    private static func checkiCloudStatus() {
        let container = CKContainer(identifier: "iCloud.com.jdi.talkie")

        // Log build configuration (Development vs Production environment)
        #if DEBUG
        AppLogger.persistence.info("🔧 Build Configuration: DEBUG (uses CloudKit Development environment)")
        #else
        AppLogger.persistence.info("🚀 Build Configuration: RELEASE (uses CloudKit Production environment)")
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

        database.perform(query, inZoneWith: zoneID) { records, error in
            if let error = error {
                // This might fail if the record type doesn't exist in this zone
                let ckError = error as? CKError
                if ckError?.code == .unknownItem {
                    AppLogger.persistence.info("  📝 Zone '\(zoneID.zoneName)': No CD_VoiceMemo records (type not found)")
                } else {
                    AppLogger.persistence.error("  ❌ Query failed in zone '\(zoneID.zoneName)': \(error.localizedDescription)")
                }
                return
            }

            guard let records = records else {
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

    private static func logMemoCount(context: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()

        do {
            let memos = try context.fetch(fetchRequest)
            AppLogger.persistence.info("📊 Total VoiceMemos in database: \(memos.count)")
            for memo in memos.prefix(3) {
                AppLogger.persistence.info("  - \(memo.title ?? "Untitled") (created: \(memo.createdAt?.description ?? "nil"))")
            }
            if memos.count > 3 {
                AppLogger.persistence.info("  ... and \(memos.count - 3) more")
            }
        } catch {
            AppLogger.persistence.error("❌ Failed to fetch memos: \(error.localizedDescription)")
        }
    }
}
