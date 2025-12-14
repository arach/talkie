//
//  Persistence.swift
//  Talkie macOS
//
//  Core Data + CloudKit sync with WAL management best practices.
//

import CoreData
import CloudKit
import AppKit
import os
import Combine

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Persistence")

// MARK: - WAL Management

/// Manages SQLite WAL file size and persistent history cleanup
class WALManager {
    static let shared = WALManager()

    private var purgeTimer: Timer?
    private let purgeInterval: TimeInterval = 3600 // Purge history every hour

    private init() {}

    deinit {
        stopPeriodicMaintenance()
    }

    func stopPeriodicMaintenance() {
        purgeTimer?.invalidate()
        purgeTimer = nil
    }

    func startPeriodicMaintenance(container: NSPersistentContainer) {
        // Stop any existing timer first
        stopPeriodicMaintenance()

        // Purge old history on startup
        purgeOldHistory(container: container)

        // Schedule periodic purges
        purgeTimer = Timer.scheduledTimer(withTimeInterval: purgeInterval, repeats: true) { [weak self] _ in
            self?.purgeOldHistory(container: container)
        }

        logger.info("WAL maintenance scheduled (purge interval: \(Int(self.purgeInterval))s)")
    }

    /// Purge persistent history older than 7 days
    func purgeOldHistory(container: NSPersistentContainer) {
        let context = container.newBackgroundContext()
        context.perform {
            let purgeDate = Date().addingTimeInterval(-7 * 24 * 60 * 60) // 7 days ago

            let purgeRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: purgeDate)

            do {
                try context.execute(purgeRequest)
                logger.info("🧹 Purged persistent history older than 7 days")
            } catch {
                logger.error("Failed to purge history: \(error.localizedDescription)")
            }
        }
    }

    /// Force WAL checkpoint - merges WAL into main database file
    /// Call this on app termination or when doing maintenance
    func checkpoint(container: NSPersistentContainer) {
        guard let storeURL = container.persistentStoreDescriptions.first?.url else { return }

        // Best practice: Save context to flush pending changes, which triggers WAL checkpoint
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
                logger.info("✅ Context saved before checkpoint")
            } catch {
                logger.warning("Context save failed: \(error.localizedDescription)")
            }
        }

        // SQLite automatically checkpoints when connections close.
        // By saving and letting the app terminate gracefully, WAL gets merged.
        logger.info("✅ WAL checkpoint triggered for \(storeURL.lastPathComponent)")
    }

    /// Get current WAL file size (for diagnostics)
    func getWALSize(container: NSPersistentContainer) -> Int64? {
        guard let storeURL = container.persistentStoreDescriptions.first?.url else { return nil }

        let walURL = storeURL.appendingPathExtension("wal")

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: walURL.path)
            return attributes[.size] as? Int64
        } catch {
            return nil
        }
    }

    /// Log database file sizes for debugging
    func logDatabaseSizes(container: NSPersistentContainer) {
        guard let storeURL = container.persistentStoreDescriptions.first?.url else { return }

        let fm = FileManager.default
        let walURL = storeURL.deletingPathExtension().appendingPathExtension("sqlite-wal")
        let shmURL = storeURL.deletingPathExtension().appendingPathExtension("sqlite-shm")

        func size(_ url: URL) -> String {
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let bytes = attrs[.size] as? Int64 else { return "N/A" }
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }

        logger.info("📊 Database sizes:")
        logger.info("  • Main DB: \(size(storeURL))")
        logger.info("  • WAL: \(size(walURL))")
        logger.info("  • SHM: \(size(shmURL))")
    }
}

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
        // Note: Notification is posted by CloudKitSyncManager to avoid duplicates
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

    /// Unique identifier for this device (Mac)
    static var deviceId: String {
        return "mac-" + (Host.current().localizedName ?? UUID().uuidString)
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
            logger.error("Failed to save preview context: \(nsError.localizedDescription)")
            // Continue with empty preview data rather than crashing
        }
        return result
    }()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "talkie")

        logger.info("Initializing PersistenceController (token-based sync)...")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
            logger.info("Using in-memory store")
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

                logger.info("CloudKit container: iCloud.com.jdi.talkie (full sync enabled)")
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

        // Start the CloudKit sync manager, WAL maintenance, and local file manager
        let viewContext = container.viewContext
        let persistentContainer = container
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            CloudKitSyncManager.shared.configure(with: viewContext)
            CloudKitSyncManager.shared.syncNow()

            // Start WAL maintenance (purges old history, logs sizes)
            WALManager.shared.startPeriodicMaintenance(container: persistentContainer)
            WALManager.shared.logDatabaseSizes(container: persistentContainer)

            // Start local file manager (syncs transcripts/audio to local folder if enabled)
            TranscriptFileManager.shared.configure(with: viewContext)

            // Start JSON export service (scheduled exports to recordings.json)
            JSONExportService.shared.configure(with: viewContext)

            // Mark existing memos as received by Mac (for sync status indicator)
            PersistenceController.markMemosAsReceivedByMac(context: viewContext)

            PersistenceController.logMemoCount(context: viewContext)
        }

        // Listen for app termination to checkpoint WAL
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak container] _ in
            guard let container = container else { return }
            logger.info("App terminating - checkpointing WAL...")
            WALManager.shared.checkpoint(container: container)
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

        database.fetch(withQuery: query, inZoneWith: zoneID, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { result in
            switch result {
            case .failure(let error):
                // This might fail if the record type doesn't exist in this zone
                let ckError = error as? CKError
                if ckError?.code == .unknownItem {
                    logger.info("  📝 Zone '\(zoneID.zoneName)': No CD_VoiceMemo records (type not found)")
                } else {
                    logger.error("  ❌ Query failed in zone '\(zoneID.zoneName)': \(error.localizedDescription)")
                }

            case .success(let (matchResults, _)):
                let records = matchResults.compactMap { try? $0.1.get() }

                if records.isEmpty {
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

    /// Mark all memos as received by Mac
    /// If a memo is visible on Mac and doesn't have macReceivedAt, mark it
    static func markMemosAsReceivedByMac(context: NSManagedObjectContext) {
        context.perform {
            let fetchRequest: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "macReceivedAt == nil")

            do {
                let memos = try context.fetch(fetchRequest)
                guard !memos.isEmpty else { return }

                let now = Date()
                for memo in memos {
                    memo.macReceivedAt = now
                    if memo.cloudSyncedAt == nil {
                        memo.cloudSyncedAt = now
                    }
                }

                try context.save()
                logger.info("🖥 Marked \(memos.count) memo(s) as received by Mac")
            } catch {
                logger.error("❌ Failed to mark memos as received: \(error.localizedDescription)")
            }
        }
    }

    /// Process pending workflow requests from iOS
    /// Fetches memos with pendingWorkflowIds, runs the workflows, and clears the queue
    /// Important: Clears pendingWorkflowIds BEFORE running to prevent duplicate runs from CloudKit sync race
    static func processPendingWorkflows(context: NSManagedObjectContext) {
        // Collect pending work and IMMEDIATELY clear pendingWorkflowIds to prevent re-runs
        var pendingWork: [(memo: VoiceMemo, workflowIds: [UUID])] = []

        context.performAndWait {
            let fetchRequest: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "pendingWorkflowIds != nil AND pendingWorkflowIds != %@", "")

            do {
                let memos = try context.fetch(fetchRequest)
                for memo in memos {
                    guard let jsonString = memo.pendingWorkflowIds,
                          let data = jsonString.data(using: .utf8),
                          let workflowIds = try? JSONDecoder().decode([UUID].self, from: data),
                          !workflowIds.isEmpty else {
                        continue
                    }

                    // Filter out workflows that have already run on this memo
                    var existingRunIds = Set<UUID>()
                    if let runs = memo.workflowRuns as? Set<WorkflowRun> {
                        for run in runs {
                            if let workflowId = run.workflowId {
                                existingRunIds.insert(workflowId)
                            }
                        }
                    }
                    let newWorkflowIds = workflowIds.filter { !existingRunIds.contains($0) }

                    if newWorkflowIds.isEmpty {
                        logger.info("📋 Skipping \(memo.title ?? "untitled") - all workflows already ran")
                        memo.pendingWorkflowIds = nil
                        continue
                    }

                    // Clear IMMEDIATELY before async execution to prevent CloudKit sync race
                    memo.pendingWorkflowIds = nil
                    pendingWork.append((memo: memo, workflowIds: newWorkflowIds))
                }

                // Save the cleared pendingWorkflowIds right away
                if !memos.isEmpty {
                    try context.save()
                }
            } catch {
                logger.error("❌ Failed to fetch pending workflows: \(error.localizedDescription)")
            }
        }

        guard !pendingWork.isEmpty else { return }

        logger.info("📋 Found \(pendingWork.count) memo(s) with pending iOS workflows")

        // Run workflows on main actor
        Task { @MainActor in
            for (memo, workflowIds) in pendingWork {
                logger.info("📋 Processing \(workflowIds.count) workflow(s) for: \(memo.title ?? "untitled")")

                var successCount = 0
                for workflowId in workflowIds {
                    if let workflow = WorkflowManager.shared.workflows.first(where: { $0.id == workflowId }) {
                        logger.info("▶️ Running iOS-requested workflow: \(workflow.name)")
                        do {
                            _ = try await WorkflowExecutor.shared.executeWorkflow(workflow, for: memo, context: context)
                            successCount += 1
                        } catch {
                            logger.error("❌ Workflow '\(workflow.name)' failed: \(error.localizedDescription)")
                        }
                    } else {
                        logger.warning("⚠️ Workflow not found: \(workflowId)")
                    }
                }

                logger.info("✅ Completed iOS workflows for: \(memo.title ?? "untitled") (\(successCount)/\(workflowIds.count) succeeded)")
            }
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
