import Foundation
import CloudKit
import TalkieMobileKit

private let log = Log(.sync)

/// iCloud sync provider - wraps existing Core Data + CloudKit sync
class iCloudSyncProvider: SyncProvider {
    let method: SyncMethod = .iCloud

    var isAvailable: Bool {
        get async {
            await checkiCloudStatus()
        }
    }

    var lastSyncDate: Date? {
        // Could track this via UserDefaults or Core Data metadata
        UserDefaults.standard.object(forKey: "icloud_last_sync") as? Date
    }

    func checkConnection() async -> ConnectionStatus {
        let available = await checkiCloudStatus()
        if available {
            return .available
        } else {
            return .unavailable(reason: "iCloud not signed in")
        }
    }

    func pushChanges(_ changes: [MemoChange]) async throws {
        // Existing NSPersistentCloudKitContainer handles push via Core Data
        // This is a placeholder for future direct CloudKit access
        log.debug("iCloud push: \(changes.count) changes (delegated to Core Data)")
    }

    func pullChanges(since: Date?) async throws -> [MemoChange] {
        // Existing NSPersistentCloudKitContainer handles pull via Core Data
        // This is a placeholder for future direct CloudKit access
        log.debug("iCloud pull since: \(since?.description ?? "beginning")")
        return []
    }

    func fullSync() async throws {
        // Core Data + CloudKit handles sync automatically
        // Could trigger explicit sync if needed
        log.info("iCloud full sync requested (handled by Core Data)")

        // Update last sync timestamp
        UserDefaults.standard.set(Date(), forKey: "icloud_last_sync")
    }

    // MARK: - Private

    private func checkiCloudStatus() async -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        guard let container = CloudKitContainerProvider.container() else {
            let reason = CloudKitContainerProvider.unavailableReason ?? "CloudKit unavailable"
            log.info("iCloud unavailable: \(reason)")
            return false
        }

        return await withCheckedContinuation { continuation in
            container.accountStatus { status, _ in
                continuation.resume(returning: status == .available)
            }
        }
        #endif
    }
}
