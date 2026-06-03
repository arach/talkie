//
//  Persistence.swift
//  talkie
//
//  Clean CloudKit sync without persistent history tracking bloat.
//

import CoreData
import CloudKit
import TalkieMobileKit
#if os(iOS)
import UIKit
import WidgetKit
#else
import AppKit
#endif

struct PersistenceController {
    private static var processUsesLocalStore: Bool {
        let processInfo = ProcessInfo.processInfo
        return processInfo.arguments.contains("-FASTLANE_SNAPSHOT")
            || processInfo.environment["FASTLANE_SNAPSHOT"] == "1"
    }

    static let shared = PersistenceController(inMemory: processUsesLocalStore)

    /// True when persistent stores have finished loading
    static var isReady: Bool = false

    /// Load persistence controller asynchronously (non-blocking)
    /// Use this instead of `shared` during app startup to avoid blocking the main thread
    static func loadAsync(inMemory: Bool = false) async -> PersistenceController {
        await withCheckedContinuation { continuation in
            // Dispatch to background to avoid blocking main thread during init
            DispatchQueue.global(qos: .userInitiated).async {
                // The singleton chooses a local-only store when the process
                // is launched for screenshots/UI tests, so every caller sees
                // the same seeded context.
                let controller = PersistenceController.shared
                DispatchQueue.main.async {
                    continuation.resume(returning: controller)
                }
            }
        }
    }

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

        for i in 0..<3 {
            let note = ComposeNote(context: viewContext)
            note.id = UUID()
            note.createdAt = Date().addingTimeInterval(-Double(i * 5400))
            note.lastModified = Date().addingTimeInterval(-Double(i * 1800))
            note.title = "Compose Note \(i + 1)"
            note.content = [
                "Ship the compose notes list and polish the tray edge.",
                "Follow up on the QR copy changes and clean the onboarding text.",
                "Plan a lighter-weight Mac handoff for direct provider setup."
            ][i]
        }

        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let cloudKitUnavailableReason = inMemory ? nil : CloudKitContainerProvider.unavailableReason

        if inMemory || cloudKitUnavailableReason != nil {
            let localContainer = NSPersistentContainer(name: "talkie")
            if let description = localContainer.persistentStoreDescriptions.first {
                if inMemory {
                    description.url = URL(fileURLWithPath: "/dev/null")
                }
                description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
                description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
            }
            container = localContainer

            if inMemory {
                AppLogger.persistence.info("Core Data using ephemeral local store")
            } else if let cloudKitUnavailableReason {
                AppLogger.persistence.info("Core Data using persistent local store: \(cloudKitUnavailableReason)")
            }
        } else {
            // Signed builds with a valid CloudKit configuration can use CloudKit;
            // simulator and other unsigned/dev contexts stay local-only.
            let cloudContainer = NSPersistentCloudKitContainer(name: "talkie")
            if let description = cloudContainer.persistentStoreDescriptions.first {
                let containerIdentifier = TalkieMobileRuntimeIdentifiers.cloudKitContainerIdentifier
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: containerIdentifier
                )
                description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
                description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
                AppLogger.persistence.info("Core Data using CloudKit store: \(containerIdentifier)")
            }
            container = cloudContainer
        }

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                AppLogger.persistence.error("Core Data failed: \(error.localizedDescription)")
            } else {
                AppLogger.persistence.info("Core Data loaded store: \(storeDescription.url?.lastPathComponent ?? "unknown")")
                PersistenceController.isReady = true
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // In-memory screenshot/preview stores are intentionally local-only.
        if !inMemory && cloudKitUnavailableReason == nil {
            setupCloudKitSyncMonitoring()
        }

        // Log memo count after store is ready
        let viewContext = container.viewContext
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            PersistenceController.logMemoCount(context: viewContext)
        }
    }

    /// Monitor CloudKit sync events to update cloudSyncedAt on memos
    private func setupCloudKitSyncMonitoring() {
        let containerRef = container

        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
                return
            }

            // Capture event details before entering MainActor context
            let eventType = event.type
            let eventSucceeded = event.succeeded
            let eventError = event.error

            Task { @MainActor in
                if eventSucceeded {
                    // Track successful sync (silently - success is the norm)
                    CloudKitSyncHealth.shared.recordSuccess(type: eventType)

                    if eventType == .export {
                        PersistenceController.markRecentMemosAsSynced(context: containerRef.viewContext)
                    } else if eventType == .import {
                        PersistenceController.refreshWidgetData(context: containerRef.viewContext)
                        // Release faulted objects after import to prevent memory accumulation
                        // CloudKit sync can fault in large audioData blobs
                        PersistenceController.releaseAllFaultedObjects(context: containerRef.viewContext)
                    }
                } else {
                    // Track failure - only log if persistent (3+ consecutive failures)
                    let health = CloudKitSyncHealth.shared
                    health.recordFailure(type: eventType, error: eventError)

                    // Only log when failures become persistent
                    if health.consecutiveFailures == 3 {
                        let typeDesc = eventType == .export ? "export" : (eventType == .import ? "import" : "setup")
                        let errorMessage = eventError?.localizedDescription ?? "Unknown error"
                        AppLogger.sync.warning("☁️ CloudKit \(typeDesc) failing persistently: \(errorMessage)")
                    }
                }
            }
        }
    }

    /// Mark all memos without cloudSyncedAt as synced
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
            } catch {
                // Silently fail - sync status is non-critical
            }
        }
    }

    // MARK: - Memory Management

    /// Refresh a memo to release faulted data (like audioData) from memory
    /// Call this after playback or when navigating away from detail view
    static func releaseMemoData(_ memo: VoiceMemo, context: NSManagedObjectContext) {
        context.refresh(memo, mergeChanges: false)
        AppLogger.persistence.debug("Released faulted data for memo: \(memo.title ?? "untitled")")
    }

    /// Release all faulted objects from the context to free memory
    /// Call this periodically or after CloudKit sync
    static func releaseAllFaultedObjects(context: NSManagedObjectContext) {
        context.refreshAllObjects()
        AppLogger.persistence.debug("Released all faulted objects from context")
    }

    private static func logMemoCount(context: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()

        do {
            let count = try context.count(for: fetchRequest)
            AppLogger.persistence.info("📝 \(count) memo(s) in database")

            #if os(iOS)
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)]
            fetchRequest.fetchLimit = 10
            let recentMemos = try context.fetch(fetchRequest)
            updateWidgetData(count: count, recentMemos: recentMemos)
            #endif
        } catch {
            // Silently fail - logging is non-critical
        }
    }

    // MARK: - Widget Support

    #if os(iOS)
    /// App Group identifier for sharing data with widgets
    static let appGroupIdentifier = TalkieMobileRuntimeIdentifiers.appGroupIdentifier

    /// Snapshot of a memo for widget display
    struct WidgetMemoSnapshot: Codable {
        let id: String
        let title: String
        let duration: TimeInterval
        let hasTranscription: Bool
        let hasAIProcessing: Bool
        let isSynced: Bool
        let createdAt: Date
        let fileSize: Int      // bytes
        let audioFormat: String // M4A, WAV, etc.
        let isSeenByMac: Bool  // whether Mac has received this memo
        let actionCount: Int   // number of completed workflow actions
    }

    /// Update the widget with the current memo count and recent memos
    static func updateWidgetData(count: Int, recentMemos: [VoiceMemo]) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

        // Save count
        defaults.set(count, forKey: "memoCount")
        defaults.set(Date(), forKey: "lastUpdated")

        // Save recent memos as JSON
        let snapshots = recentMemos.prefix(10).map { memo in
            // Estimate file size from duration (avoid loading audioData blob into memory)
            let fileSize = Int(memo.duration * 16000) // ~16KB/sec for M4A

            // Get audio format from filename extension
            let audioFormat: String
            if let filename = memo.fileURL {
                let ext = (filename as NSString).pathExtension.uppercased()
                audioFormat = ext.isEmpty ? "M4A" : ext
            } else {
                audioFormat = "M4A"
            }

            // Count completed workflow actions
            let actionCount: Int
            if let runs = memo.workflowRuns as? Set<WorkflowRun> {
                actionCount = runs.filter { $0.status == "completed" }.count
            } else {
                actionCount = 0
            }

            return WidgetMemoSnapshot(
                id: memo.id?.uuidString ?? UUID().uuidString,
                title: memo.title ?? "Untitled",
                duration: memo.duration,
                hasTranscription: memo.transcription != nil && !memo.transcription!.isEmpty,
                hasAIProcessing: memo.summary != nil && !memo.summary!.isEmpty,
                isSynced: memo.cloudSyncedAt != nil,
                createdAt: memo.createdAt ?? Date(),
                fileSize: fileSize,
                audioFormat: audioFormat,
                isSeenByMac: memo.macReceivedAt != nil,
                actionCount: actionCount
            )
        }

        if let data = try? JSONEncoder().encode(Array(snapshots)) {
            defaults.set(data, forKey: "recentMemos")
        }

        defaults.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Legacy method for compatibility
    static func updateWidgetMemoCount(_ count: Int) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

        defaults.set(count, forKey: "memoCount")
        defaults.set(Date(), forKey: "lastUpdated")
        defaults.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Call this when memos are added/deleted to update widget
    static func refreshWidgetData(context: NSManagedObjectContext) {
        context.perform {
            let fetchRequest: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)]
            fetchRequest.fetchLimit = 10

            do {
                let recentMemos = try context.fetch(fetchRequest)
                let countRequest: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
                let count = try context.count(for: countRequest)
                updateWidgetData(count: count, recentMemos: recentMemos)
            } catch {
                // Silently fail - widget update is non-critical
            }
        }
    }
    #endif
}

// MARK: - CloudKit Sync Health Tracking

/// Tracks CloudKit sync health for debugging and retry logic
@MainActor
final class CloudKitSyncHealth: ObservableObject {
    static let shared = CloudKitSyncHealth()

    /// Recent sync events (last 20)
    @Published private(set) var recentEvents: [SyncEvent] = []

    /// Current sync health status
    @Published private(set) var status: SyncHealthStatus = .healthy

    /// Last successful export timestamp
    @Published private(set) var lastSuccessfulExport: Date?

    /// Last successful import timestamp
    @Published private(set) var lastSuccessfulImport: Date?

    /// Consecutive failure count
    @Published private(set) var consecutiveFailures: Int = 0

    /// Maximum events to keep in history
    private let maxEvents = 20

    /// Track pending recovery check to prevent concurrent checks
    private var pendingRecoveryCheck: Task<Void, Never>?

    /// Notification posted when sync health changes
    static let healthDidChangeNotification = Notification.Name("CloudKitSyncHealthDidChange")

    struct SyncEvent: Identifiable {
        let id = UUID()
        let date: Date
        let type: NSPersistentCloudKitContainer.EventType
        let succeeded: Bool
        let errorMessage: String?

        var typeDescription: String {
            switch type {
            case .setup: return "Setup"
            case .import: return "Import"
            case .export: return "Export"
            @unknown default: return "Unknown"
            }
        }
    }

    enum SyncHealthStatus: String {
        case healthy = "Healthy"
        case degraded = "Degraded"  // 1-2 failures
        case unhealthy = "Unhealthy"  // 3+ consecutive failures

        var icon: String {
            switch self {
            case .healthy: return "checkmark.icloud.fill"
            case .degraded: return "exclamationmark.icloud"
            case .unhealthy: return "xmark.icloud.fill"
            }
        }
    }

    private init() {}

    func recordSuccess(type: NSPersistentCloudKitContainer.EventType) {
        let event = SyncEvent(date: Date(), type: type, succeeded: true, errorMessage: nil)
        addEvent(event)

        consecutiveFailures = 0

        if type == .export {
            lastSuccessfulExport = Date()
        } else if type == .import {
            lastSuccessfulImport = Date()
        }

        updateStatus()
    }

    func recordFailure(type: NSPersistentCloudKitContainer.EventType, error: Error?) {
        let event = SyncEvent(
            date: Date(),
            type: type,
            succeeded: false,
            errorMessage: error?.localizedDescription
        )
        addEvent(event)

        consecutiveFailures += 1
        updateStatus()

        // Schedule retry after failures (NSPersistentCloudKitContainer has internal retry,
        // but we can trigger a refresh if network recovers)
        if consecutiveFailures >= 3 {
            scheduleRecoveryCheck()
        }
    }

    private func addEvent(_ event: SyncEvent) {
        recentEvents.insert(event, at: 0)
        if recentEvents.count > maxEvents {
            recentEvents.removeLast()
        }
    }

    private func updateStatus() {
        let oldStatus = status

        switch consecutiveFailures {
        case 0:
            status = .healthy
        case 1...2:
            status = .degraded
        default:
            status = .unhealthy
        }

        if status != oldStatus {
            NotificationCenter.default.post(name: Self.healthDidChangeNotification, object: self)
        }
    }

    private func scheduleRecoveryCheck() {
        // Cancel any pending recovery check to prevent concurrent checks
        pendingRecoveryCheck?.cancel()

        // After 3+ failures, schedule a check when network might have recovered
        // This uses exponential backoff: 30s, 60s, 120s, max 5 min
        let delay = min(30.0 * pow(2.0, Double(consecutiveFailures - 3)), 300.0)

        pendingRecoveryCheck = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard !Task.isCancelled, self != nil else { return }

            #if targetEnvironment(simulator)
            AppLogger.sync.info("Skipping CloudKit recovery check on simulator")
            return
            #else
            // Check if iCloud is available now
            guard let container = CloudKitContainerProvider.container() else {
                let reason = CloudKitContainerProvider.unavailableReason ?? "CloudKit unavailable"
                AppLogger.sync.info("CloudKit recovery check skipped: \(reason)")
                return
            }

            let status = try? await container.accountStatus()
            if status == .available {
                AppLogger.sync.info("☁️ Network recovered, CloudKit should auto-retry")
                // NSPersistentCloudKitContainer will auto-retry on next Core Data save
            }
            #endif
        }
    }

    /// Reset health tracking (e.g., after user action)
    func reset() {
        consecutiveFailures = 0
        status = .healthy
        recentEvents.removeAll()
    }
}
