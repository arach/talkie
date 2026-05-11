import Foundation
import TalkieKit

private let log = Log(.sync)

/// iCloud sync provider - uses TalkieSync XPC service for sync operations
///
/// This provider delegates both availability checks and sync execution
/// to the TalkieSync helper service via SyncClient XPC.
class iCloudSyncProvider: SyncProvider {
    let method: SyncMethod = .iCloud

    var isAvailable: Bool {
        get async {
            let status = await checkConnection()
            if case .available = status {
                return true
            }
            return false
        }
    }

    var lastSyncDate: Date? {
        get async {
            await MainActor.run {
                SyncClient.shared.lastSyncDate
            }
        }
    }

    func checkConnection() async -> ConnectionStatus {
        // Talkie should not directly inspect CloudKit. Ask TalkieSync only.
        guard await SyncClient.shared.ping() else {
            return .unavailable(reason: "TalkieSync not connected")
        }

        let availability = await SyncClient.shared.checkiCloudAvailability()
        guard availability.available else {
            return .unavailable(reason: availability.error ?? "iCloud unavailable in TalkieSync")
        }

        return .available
    }

    func pushChanges(_ changes: [MemoChange]) async throws {
        // Push handled by Core Data → CloudKit automatic sync
        // TalkieSync owns the Core Data stack now
        log.debug("iCloud push: \(changes.count) changes (handled by TalkieSync)")
    }

    func pullChanges(since: Date?) async throws -> [MemoChange] {
        // Pull handled by TalkieSync bridge sync
        log.debug("iCloud pull since: \(since?.description ?? "beginning")")
        return []
    }

    func fullSync() async throws {
        // Use TalkieSync XPC service for sync - no fallback
        // TalkieSync owns Core Data + CloudKit, main app is GRDB-only
        log.info("┌─ SYNC REQUEST ─────────────────────────────")
        log.info("│ Path: TalkieSync (XPC)")

        try await SyncClient.shared.runSyncOnce(keepRunning: SettingsManager.shared.syncOnLaunch)
        log.info("└─ DONE via TalkieSync")
    }
}
