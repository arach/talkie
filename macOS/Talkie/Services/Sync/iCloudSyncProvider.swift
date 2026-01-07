import Foundation
import CloudKit
import TalkieKit

private let log = Log(.sync)

/// iCloud sync provider - wraps existing CloudKitSyncManager
class iCloudSyncProvider: SyncProvider {
    let method: SyncMethod = .iCloud

    var isAvailable: Bool {
        get async {
            await checkiCloudStatus()
        }
    }

    var lastSyncDate: Date? {
        CloudKitSyncManager.shared.lastSyncDate
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
        // Existing CloudKitSyncManager handles push via Core Data
        // This is a placeholder for future direct CloudKit access
        log.debug("iCloud push: \(changes.count) changes (delegated to CloudKitSyncManager)")
    }

    func pullChanges(since: Date?) async throws -> [MemoChange] {
        // Existing CloudKitSyncManager handles pull via Core Data
        // This is a placeholder for future direct CloudKit access
        log.debug("iCloud pull since: \(since?.description ?? "beginning")")
        return []
    }

    func fullSync() async throws {
        // Delegate to existing CloudKitSyncManager
        await CloudKitSyncManager.shared.syncNow()
    }

    // MARK: - Private

    private func checkiCloudStatus() async -> Bool {
        await withCheckedContinuation { continuation in
            CKContainer(identifier: "iCloud.com.jdi.talkie").accountStatus { status, _ in
                continuation.resume(returning: status == .available)
            }
        }
    }
}
