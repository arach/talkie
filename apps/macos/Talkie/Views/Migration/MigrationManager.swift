//
//  MigrationManager.swift
//  Talkie
//
//  DEPRECATED: Core Data → GRDB migration now handled by TalkieSync bridge sync.
//  This manager is kept for backward compatibility but migration is automatic.
//

import SwiftUI
import AppKit
import TalkieKit

private let log = Log(.database)

/// DEPRECATED: Migration is now automatic via TalkieSync bridge sync
/// This manager is kept for backward compatibility only
@MainActor
final class MigrationManager: ObservableObject {
    static let shared = MigrationManager()

    @Published var isShowingMigration = false

    private var migrationWindow: NSWindow?

    private init() {
        log.info("MigrationManager: Migration now handled automatically by TalkieSync")
    }

    // MARK: - Public API

    /// Show the migration window
    /// NOTE: Migration is now automatic - this shows a status dialog instead
    func showMigration() {
        log.info("MigrationManager.showMigration() called - migration is automatic via TalkieSync")

        // Show info alert instead of full migration UI
        let alert = NSAlert()
        alert.messageText = "Migration Status"
        alert.informativeText = "Data migration is now handled automatically by the TalkieSync service. Your memos are synchronized in the background.\n\nTo force a sync, go to Settings > Data > Sync Now."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Close the migration window
    func closeMigration() {
        migrationWindow?.close()
        migrationWindow = nil
        isShowingMigration = false
    }

    // MARK: - Migration State

    /// Check if migration is needed
    /// NOTE: Migration is now automatic via TalkieSync - always returns false
    var needsMigration: Bool {
        // Migration is automatic via TalkieSync bridge sync
        // Check if bridge sync has completed at least once
        let bridgeSyncComplete = UserDefaults.standard.bool(forKey: "talkiesync_bridge_complete")
        if bridgeSyncComplete {
            return false
        }

        // Check with TalkieSync if we have Core Data records but no GRDB records
        // This is an async check so we return false and let TalkieSync handle it
        Task {
            let coreDataCount = await SyncClient.shared.getRemoteMemoCount()
            // Only trigger if count is actually available (>= 0) and non-zero
            if coreDataCount > 0 {
                log.info("TalkieSync reports \(coreDataCount) Core Data records - bridge sync needed")
                do {
                    let syncedCount = try await SyncClient.shared.runSyncPass()
                    log.info("Bridge sync completed: \(syncedCount) records synced")
                    UserDefaults.standard.set(true, forKey: "talkiesync_bridge_complete")
                } catch {
                    log.error("Bridge sync failed: \(error.localizedDescription)")
                }
            }
        }

        return false
    }

    /// Mark migration as complete
    func markComplete() {
        UserDefaults.standard.set(true, forKey: "grdb_migration_complete")
        UserDefaults.standard.set(true, forKey: "talkiesync_bridge_complete")
        NotificationCenter.default.post(name: NSNotification.Name("MigrationCompleted"), object: nil)
    }

    /// Reset migration flag (for debugging)
    func resetFlag() {
        UserDefaults.standard.removeObject(forKey: "grdb_migration_complete")
        UserDefaults.standard.removeObject(forKey: "talkiesync_bridge_complete")
    }
}
