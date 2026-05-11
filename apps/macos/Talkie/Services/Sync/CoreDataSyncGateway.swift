//
//  CoreDataSyncGateway.swift
//  Talkie macOS
//
//  DEPRECATED: Core Data now lives in TalkieSync XPC service.
//  This class is kept for backward compatibility but returns empty/nil for all operations.
//
//  For sync operations, use:
//  - SyncClient.shared.syncNow() for sync
//  - SyncClient.shared.runSyncPass() for bridge sync
//  - SyncClient.shared.getRemoteMemoCount() for record count
//

import Foundation
import TalkieKit

private let log = Log(.sync)

/// DEPRECATED: Wrapper around Core Data - now lives in TalkieSync
/// All Core Data operations should go through SyncClient XPC
@available(*, deprecated, message: "Core Data moved to TalkieSync - use SyncClient for sync operations")
@MainActor
class CoreDataSyncGateway {
    static let shared = CoreDataSyncGateway()

    private init() {
        log.warning("CoreDataSyncGateway initialized - this class is deprecated")
    }

    /// Always returns false - Core Data not loaded in main app
    var isReady: Bool {
        false
    }

    /// Always returns nil - Core Data not available in main app
    var context: Any? {
        log.warning("CoreDataSyncGateway.context accessed - Core Data lives in TalkieSync")
        return nil
    }

    // MARK: - Deprecated Methods (no-ops)

    @available(*, deprecated, message: "Use SyncClient for sync operations")
    func withContext<T>(_ operation: (Any) throws -> T) rethrows -> T? {
        log.warning("CoreDataSyncGateway.withContext called - returning nil")
        return nil
    }

    @available(*, deprecated, message: "Use SyncClient for sync operations")
    func performSync(_ operation: @escaping (Any) -> Void) {
        log.warning("CoreDataSyncGateway.performSync called - no-op")
    }

    @available(*, deprecated, message: "Use SyncClient for sync operations")
    func markMemosAsReceivedByMac() {
        log.warning("CoreDataSyncGateway.markMemosAsReceivedByMac called - handled by TalkieSync")
    }

    @available(*, deprecated, message: "Use LocalRepository.fetchAllIDs() for GRDB IDs")
    func fetchAllMemoIDs() async -> Set<UUID> {
        log.warning("CoreDataSyncGateway.fetchAllMemoIDs called - returning empty set")
        return []
    }
}
