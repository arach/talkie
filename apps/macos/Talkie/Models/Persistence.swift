//
//  Persistence.swift
//  Talkie macOS
//
//  MIGRATED: Core Data + CloudKit sync now lives in TalkieSync service.
//  This file retains only UI status tracking.
//
//  Architecture:
//  - TalkieSync: Owns Core Data + CloudKit (NSPersistentCloudKitContainer)
//  - Talkie: GRDB-only client, reads sync status via SyncClient XPC
//

import Foundation
import Observation
import TalkieKit

private let log = Log(.sync)

// MARK: - Sync Status Manager

/// UI-facing sync status tracking
/// Observes SyncClient and provides status for views
@MainActor
@Observable
class SyncStatusManager {
    static let shared = SyncStatusManager()

    enum SyncState: Equatable {
        case idle
        case syncing
        case synced
        case error(String)
    }

    var state: SyncState = .idle
    var lastSyncDate: Date?
    var iCloudAvailable: Bool = false
    var pendingChanges: Int = 0

    // Tracked property that views observe - incremented to trigger re-render
    var displayRefreshTick: Int = 0

    @ObservationIgnored private var displayTimer: Timer?

    private init() {
        // Update display every 30s so "Just now" becomes "30s ago" etc.
        displayTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.displayRefreshTick += 1
            }
        }

        // Observe SyncClient for state updates
        setupSyncClientObserver()
    }

    private func setupSyncClientObserver() {
        // Listen for sync data available notifications
        NotificationCenter.default.addObserver(
            forName: .syncDataAvailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFromSyncClient()
            }
        }
    }

    private func refreshFromSyncClient() {
        let client = SyncClient.shared
        if client.isSyncing {
            state = .syncing
        } else if let error = client.syncError {
            state = .error(error)
        } else {
            state = .synced
            lastSyncDate = client.lastSyncDate
        }
        iCloudAvailable = client.iCloudAvailable
    }

    func setSyncing() {
        state = .syncing
    }

    func setSynced(changes: Int = 0) {
        lastSyncDate = Date()
        state = .synced
        pendingChanges = 0
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
        // Access displayRefreshTick to ensure view re-renders when timer fires
        _ = displayRefreshTick
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

// MARK: - Deprecated PersistenceController

/// DEPRECATED: Core Data now lives in TalkieSync service
/// This stub exists only for backward compatibility during migration
@available(*, deprecated, message: "Core Data moved to TalkieSync - use GRDB via LocalRepository")
struct PersistenceController {
    static let shared = PersistenceController()

    /// Always returns false - Core Data not loaded in main app
    static var isReady: Bool { false }

    /// Device identifier for sync
    static var deviceId: String {
        return "mac-" + (Host.current().localizedName ?? UUID().uuidString)
    }

    private init() {
        log.warning("PersistenceController accessed - Core Data now lives in TalkieSync")
    }

    // MARK: - Deprecated Methods

    @available(*, deprecated, message: "Use TalkieSync for workflow processing")
    static func processPendingWorkflows(context: Any) {
        log.warning("processPendingWorkflows() called - should be handled by TalkieSync")
    }

    @available(*, deprecated, message: "Use TalkieSync for memo marking")
    static func markMemosAsReceivedByMac(context: Any) {
        log.warning("markMemosAsReceivedByMac() called - should be handled by TalkieSync")
    }
}

// MARK: - Custom Notifications

extension Notification.Name {
    /// Posted when a sync operation completes with changes
    static let talkieSyncCompleted = Notification.Name("talkieSyncCompleted")
    /// Posted when sync starts
    static let talkieSyncStarted = Notification.Name("talkieSyncStarted")
    /// Posted when Core Data persistent stores finish loading (legacy - from TalkieSync now)
    static let persistentStoresDidLoad = Notification.Name("persistentStoresDidLoad")
}
