//
//  Persistence.swift
//  Talkie macOS
//
//  Created by Claude Code on 2025-11-23.
//

import CoreData
import CloudKit
import os

private let logger = Logger(subsystem: "jdi.talkie-os-mac", category: "Persistence")

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

        logger.info("Initializing PersistenceController...")

        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
            logger.info("Using in-memory store")
        } else {
            // Configure CloudKit sync
            if let description = container.persistentStoreDescriptions.first {
                // Set the CloudKit container identifier explicitly
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: "iCloud.com.jdi.talkie"
                )
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

                logger.info("CloudKit container: iCloud.com.jdi.talkie")
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
                logger.info("Store URL: \(storeDescription.url?.absoluteString ?? "nil")")

                if let cloudKitOptions = storeDescription.cloudKitContainerOptions {
                    logger.info("CloudKit container ID: \(cloudKitOptions.containerIdentifier)")
                } else {
                    logger.warning("No CloudKit container options set!")
                }
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Listen for remote change notifications
        let viewContext = container.viewContext
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { notification in
            logger.info("Remote change notification received from iCloud")
            PersistenceController.logMemoCount(context: viewContext)
        }

        // Check iCloud account status
        PersistenceController.checkiCloudStatus()

        // Log initial memo count after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
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
                // Now fetch detailed zone and database info
                fetchCloudKitDatabaseInfo(container: container)
            case .noAccount:
                logger.warning("⚠️ iCloud account status: No Account - user not signed into iCloud")
            case .restricted:
                logger.warning("⚠️ iCloud account status: Restricted")
            case .couldNotDetermine:
                logger.warning("⚠️ iCloud account status: Could not determine")
            case .temporarilyUnavailable:
                logger.warning("⚠️ iCloud account status: Temporarily unavailable")
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
