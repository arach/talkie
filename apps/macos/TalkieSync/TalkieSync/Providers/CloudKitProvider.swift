//
//  CloudKitProvider.swift
//  TalkieSync
//
//  iCloud sync provider using direct CloudKit -> GRDB sync.
//

import Foundation
import TalkieKit

private let log = Log(.sync)

/// iCloud sync provider backed by CloudKitDirectSyncEngine.
final class CloudKitProvider: SyncProvider {
    let id = "icloud"
    let displayName = "iCloud"

    private(set) var isEnabled = true
    private(set) var connectionStatus: ProviderConnectionStatus = .disconnected
    private(set) var lastSyncDate: Date?

    init() {}

    // MARK: - SyncProvider

    func configure(_ config: Data?) async throws {
        log.info("CloudKit provider configured (direct mode)")
    }

    func checkConnection() async -> ProviderConnectionStatus {
        connectionStatus = .connecting
        let (available, error) = await CloudKitDirectSyncEngine.shared.checkiCloudAvailability()
        if available {
            connectionStatus = .connected
        } else {
            connectionStatus = .error(error ?? "iCloud unavailable")
        }
        return connectionStatus
    }

    func sync() async throws -> SyncResult {
        if !connectionStatus.isConnected {
            _ = await checkConnection()
            guard connectionStatus.isConnected else {
                throw SyncProviderError.notAuthenticated
            }
        }

        log.info("Starting CloudKit direct sync...")
        let stats = try await CloudKitDirectSyncEngine.shared.syncNow()
        lastSyncDate = Date()
        log.info("CloudKit direct sync completed: +\(stats.inserted) new, ~\(stats.updated) updated, -\(stats.deleted) deleted")
        return SyncResult(recordsPulled: stats.inserted + stats.updated + stats.deleted)
    }

    func pushChanges() async throws -> SyncResult {
        // Direct mode currently focuses on remote -> local pull.
        // Keep API contract while we are read-only from TalkieSync.
        return SyncResult()
    }

    func pullChanges() async throws -> SyncResult {
        return try await sync()
    }

    func disconnect() async {
        // Can't really disconnect from iCloud - it's system-level
        connectionStatus = .disconnected
        log.info("CloudKit provider disconnected (soft)")
    }
}
