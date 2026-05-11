//
//  ChangeTracker.swift
//  Talkie
//
//  Tracks local changes that need to be synced to cloud providers.
//  Logs create/update/delete operations to sync_operations table.
//

import Foundation
import GRDB
import TalkieKit

private let log = Log(.sync)
private enum ChangeTrackerDefaults {
    static let syncedRetentionLimit = 1000
}

private enum SyncOperationState: String {
    case pending
    case synced
    case failed
}

// MARK: - Sync Operation Model

/// Represents a local change that needs to be synced to a provider
struct SyncOperation: Codable, FetchableRecord, PersistableRecord {
    var id: UUID
    var memoId: UUID
    var operation: String  // "create", "update", "delete"
    var timestamp: Date
    var provider: String   // "icloud", "s3", "vercel", etc.
    var status: String     // "pending", "synced", "failed"
    var retryCount: Int
    var errorMessage: String?

    enum Columns {
        static let id = Column("id")
        static let memoId = Column("memoId")
        static let operation = Column("operation")
        static let timestamp = Column("timestamp")
        static let provider = Column("provider")
        static let status = Column("status")
        static let retryCount = Column("retryCount")
        static let errorMessage = Column("errorMessage")
    }

    static let databaseTableName = "sync_operations"

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id.uuidString
        container["memoId"] = memoId.uuidString
        container["operation"] = operation
        container["timestamp"] = timestamp
        container["provider"] = provider
        container["status"] = status
        container["retryCount"] = retryCount
        container["errorMessage"] = errorMessage
    }
}

// MARK: - Change Tracker

/// Tracks local changes and logs them for sync
@MainActor
final class ChangeTracker {
    static let shared = ChangeTracker()

    private init() {}

    // MARK: - Logging Changes

    /// Log a memo change that needs to be synced
    /// - Parameters:
    ///   - memoId: ID of the memo that changed
    ///   - operation: Type of change ("create", "update", "delete")
    ///   - providers: Which providers to sync to (defaults to all enabled)
    func logChange(
        memoId: UUID,
        operation: String,
        providers: [SyncMethod]? = nil
    ) async throws {
        let enabledProviders = providers ?? self.enabledProviders()

        guard !enabledProviders.isEmpty else {
            log.debug("No enabled providers, skipping change log for memo \(memoId)")
            return
        }

        let db = try DatabaseManager.shared.database()
        try await db.write { db in
            for provider in enabledProviders {
                let op = SyncOperation(
                    id: UUID(),
                    memoId: memoId,
                    operation: operation,
                    timestamp: Date(),
                    provider: provider.rawValue,
                    status: SyncOperationState.pending.rawValue,
                    retryCount: 0,
                    errorMessage: nil
                )
                try op.insert(db)
            }
        }

        log.debug("Logged \(operation) for memo \(memoId) to \(enabledProviders.count) provider(s)")
    }

    /// Convenience method for logging create operation
    func logCreate(memoId: UUID, providers: [SyncMethod]? = nil) async throws {
        try await logChange(memoId: memoId, operation: "create", providers: providers)
    }

    /// Convenience method for logging update operation
    func logUpdate(memoId: UUID, providers: [SyncMethod]? = nil) async throws {
        try await logChange(memoId: memoId, operation: "update", providers: providers)
    }

    /// Convenience method for logging delete operation
    func logDelete(memoId: UUID, providers: [SyncMethod]? = nil) async throws {
        try await logChange(memoId: memoId, operation: "delete", providers: providers)
    }

    // MARK: - Querying Operations

    /// Get pending operations for a specific provider
    func pendingOperations(for provider: SyncMethod, limit: Int? = nil) async throws -> [SyncOperation] {
        let db = try DatabaseManager.shared.database()
        return try await db.read { db in
            var query = SyncOperation
                .filter(SyncOperation.Columns.provider == provider.rawValue)
                .filter(SyncOperation.Columns.status == SyncOperationState.pending.rawValue)
                .order(SyncOperation.Columns.timestamp)

            if let limit = limit {
                query = query.limit(limit)
            }

            return try query.fetchAll(db)
        }
    }

    /// Get all pending operations across all providers
    func allPendingOperations(limit: Int? = nil) async throws -> [SyncOperation] {
        let db = try DatabaseManager.shared.database()
        return try await db.read { db in
            var query = SyncOperation
                .filter(SyncOperation.Columns.status == SyncOperationState.pending.rawValue)
                .order(SyncOperation.Columns.timestamp)

            if let limit = limit {
                query = query.limit(limit)
            }

            return try query.fetchAll(db)
        }
    }

    /// Get count of pending operations for a provider
    func pendingCount(for provider: SyncMethod) async throws -> Int {
        let db = try DatabaseManager.shared.database()
        return try await db.read { db in
            try SyncOperation
                .filter(SyncOperation.Columns.provider == provider.rawValue)
                .filter(SyncOperation.Columns.status == SyncOperationState.pending.rawValue)
                .fetchCount(db)
        }
    }

    // MARK: - Marking Operations

    /// Mark operations as successfully synced
    func markSynced(operationIds: [UUID]) async throws {
        guard !operationIds.isEmpty else { return }
        let ids = operationIds.map(\.uuidString)

        let db = try DatabaseManager.shared.database()
        try await db.write { db in
            _ = try SyncOperation
                .filter(ids.contains(SyncOperation.Columns.id))
                .updateAll(
                    db,
                    SyncOperation.Columns.status.set(to: SyncOperationState.synced.rawValue)
                )
        }

        log.debug("Marked \(operationIds.count) operation(s) as synced")
    }

    /// Mark an operation as failed with error message
    func markFailed(operationId: UUID, error: String) async throws {
        let db = try DatabaseManager.shared.database()
        try await db.write { db in
            try db.execute(
                sql: """
                    UPDATE sync_operations
                    SET status = ?,
                        retryCount = retryCount + 1,
                        errorMessage = ?
                    WHERE id = ?
                    """,
                arguments: [SyncOperationState.failed.rawValue, error, operationId.uuidString]
            )
        }

        log.warning("Marked operation \(operationId) as failed: \(error)")
    }

    /// Reset failed operations to pending for retry
    func retryFailed(provider: SyncMethod, maxRetries: Int = 3) async throws -> Int {
        let db = try DatabaseManager.shared.database()
        let count = try await db.write { db -> Int in
            try db.execute(
                sql: """
                    UPDATE sync_operations
                    SET status = ?
                    WHERE provider = ?
                      AND status = ?
                      AND retryCount < ?
                    """,
                arguments: [SyncOperationState.pending.rawValue, provider.rawValue, SyncOperationState.failed.rawValue, maxRetries]
            )
            return db.changesCount
        }

        if count > 0 {
            log.info("Reset \(count) failed operation(s) for retry (\(provider.rawValue))")
        }

        return count
    }

    // MARK: - Cleanup

    /// Clean up old synced operations (keep last 1000 per provider)
    func cleanupOldOperations() async throws {
        let db = try DatabaseManager.shared.database()
        try await db.write { db in
            // Keep last N synced operations across providers.
            try db.execute(sql: """
                DELETE FROM sync_operations
                WHERE status = ?
                  AND id NOT IN (
                    SELECT id FROM sync_operations
                    WHERE status = ?
                    ORDER BY timestamp DESC
                    LIMIT ?
                  )
                """, arguments: [
                    SyncOperationState.synced.rawValue,
                    SyncOperationState.synced.rawValue,
                    ChangeTrackerDefaults.syncedRetentionLimit
                ])
        }
    }

    // MARK: - Helpers

    /// Get currently enabled sync providers from settings
    private func enabledProviders() -> [SyncMethod] {
        let iCloudEnabled = SettingsManager.shared.iCloudSyncEnabled
        guard iCloudEnabled else { return [] }

        // TODO(sync): Expand this when provider selection UI lands.
        return [.iCloud]
    }
}
