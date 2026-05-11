//
//  SyncCoordinator.swift
//  Talkie
//
//  Orchestrates multi-provider sync operations.
//  Handles push (local → cloud) and pull (cloud → local) for all enabled providers.
//

import Foundation
import GRDB
import TalkieKit

private let log = Log(.sync)
private enum SyncCoordinatorDefaults {
    static let pendingOperationBatchLimit = 100
}

// MARK: - Sync Coordinator

/// Coordinates sync operations across multiple cloud providers
@MainActor
final class SyncCoordinator {
    static let shared = SyncCoordinator()

    private var providers: [SyncMethod: any SyncProvider] = [:]
    private var isSyncing = false

    private init() {
        registerProvider(iCloudSyncProvider())
    }

    // MARK: - Provider Management

    /// Register a sync provider
    func registerProvider(_ provider: any SyncProvider) {
        providers[provider.method] = provider
        log.info("Registered sync provider: \(provider.method.rawValue)")
    }

    /// Get all registered providers
    func allProviders() -> [any SyncProvider] {
        Array(providers.values)
    }

    /// Get provider by method
    func provider(for method: SyncMethod) -> (any SyncProvider)? {
        providers[method]
    }

    // MARK: - Sync Operations

    /// Run full sync for all providers (push + pull)
    func syncAll() async throws {
        guard !isSyncing else {
            log.debug("Sync already in progress, skipping")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        log.info("┌─ SyncCoordinator: Starting full sync ────────────")

        for provider in providers.values {
            do {
                guard isProviderEnabled(provider.method) else {
                    log.debug("│ Provider \(provider.method.rawValue) disabled, skipping")
                    continue
                }

                // Check if provider is available
                guard await provider.isAvailable else {
                    log.warning("│ Provider \(provider.method.rawValue) not available, skipping")
                    continue
                }

                log.info("│ Syncing with \(provider.method.rawValue)...")

                // Push local changes
                try await pushChanges(to: provider)

                // Pull remote changes
                try await pullChanges(from: provider)

            } catch {
                log.error("│ Error syncing with \(provider.method.rawValue): \(error.localizedDescription)")
                // Continue with other providers
            }
        }

        log.info("└─ SyncCoordinator: Full sync complete ────────────")
    }

    /// Push local changes to a specific provider
    func pushChanges(to provider: any SyncProvider) async throws {
        // Get pending operations for this provider
        let pendingOps = try await ChangeTracker.shared.pendingOperations(
            for: provider.method,
            limit: SyncCoordinatorDefaults.pendingOperationBatchLimit
        )

        guard !pendingOps.isEmpty else {
            log.debug("│   No pending changes to push")
            return
        }

        log.info("│   Pushing \(pendingOps.count) change(s)...")

        // Convert to MemoChange format
        var changes: [MemoChange] = []
        var pushableOperationIds: [UUID] = []
        let db = try DatabaseManager.shared.database()

        for op in pendingOps {
            // For delete operations, we don't need the memo data
            if op.operation == "delete" {
                changes.append(MemoChange(
                    id: op.memoId,
                    type: .delete,
                    memo: nil,
                    timestamp: op.timestamp
                ))
                pushableOperationIds.append(op.id)
                continue
            }

            // For create/update, fetch the memo from GRDB
            let memo: MemoRecord? = try await db.read { db in
                try MemoRecord.fetchOne(db, key: op.memoId.uuidString)
            }

            guard let memo = memo else {
                log.warning("│   Memo \(op.memoId) not found in GRDB, skipping")
                try await ChangeTracker.shared.markFailed(
                    operationId: op.id,
                    error: "Memo not found in local database"
                )
                continue
            }

            // Convert to DTO
            let dto = MemoSyncDTO(
                id: memo.id,
                title: memo.title,
                duration: memo.duration,
                transcription: memo.transcription,
                notes: memo.notes,
                summary: memo.summary,
                createdAt: memo.createdAt,
                lastModified: memo.lastModified,
                originDeviceId: memo.originDeviceId,
                hasAudio: memo.audioFilePath != nil
            )

            changes.append(MemoChange(
                id: memo.id,
                type: op.operation == "create" ? .create : .update,
                memo: dto,
                timestamp: op.timestamp
            ))
            pushableOperationIds.append(op.id)
        }

        guard !changes.isEmpty else {
            log.debug("│   No valid changes to push after filtering")
            return
        }

        // Push to provider
        do {
            try await provider.pushChanges(changes)
        } catch {
            log.error("│   Push failed: \(error.localizedDescription)")
            // Mark only pushed operations as failed.
            for operationId in pushableOperationIds {
                try? await ChangeTracker.shared.markFailed(
                    operationId: operationId,
                    error: error.localizedDescription
                )
            }
            throw error
        }

        do {
            try await ChangeTracker.shared.markSynced(operationIds: pushableOperationIds)
        } catch {
            // Push already succeeded; avoid rewriting statuses to failed.
            // Operations remain pending and may be retried safely.
            log.error("│   Push succeeded but failed to mark synced: \(error.localizedDescription)")
            throw error
        }

        log.info("│   Pushed \(changes.count) change(s) successfully")
    }

    /// Pull remote changes from a specific provider
    func pullChanges(from provider: any SyncProvider) async throws {
        log.info("│   Pulling changes...")

        // Get last sync date for this provider
        let lastSync = await provider.lastSyncDate

        // Pull changes since last sync
        let changes = try await provider.pullChanges(since: lastSync)

        guard !changes.isEmpty else {
            log.debug("│   No remote changes to pull")
            return
        }

        log.info("│   Pulled \(changes.count) change(s), applying to GRDB...")

        let db = try DatabaseManager.shared.database()
        var applied = 0
        var skipped = 0

        for change in changes {
            do {
                switch change.type {
                case .create, .update:
                    guard let memo = change.memo else {
                        log.warning("│   Change has no memo data, skipping")
                        skipped += 1
                        continue
                    }

                    // Last-write-wins conflict policy:
                    // If the local memo has a newer timestamp, keep local and skip remote.
                    let localMemo: MemoRecord? = try await db.read { db in
                        try MemoRecord.fetchOne(db, key: memo.id.uuidString)
                    }

                    if let local = localMemo, local.lastModified > memo.lastModified {
                        log.debug("│   Local version newer (last-write-wins), keeping local: \(memo.id)")
                        skipped += 1
                        continue
                    }

                    let resolvedAudioPath = resolveAudioFilePath(
                        for: memo,
                        localAudioPath: localMemo?.audioFilePath
                    )

                    // Apply change to GRDB
                    try await db.write { db in
                        let record = MemoRecord(
                            id: memo.id,
                            createdAt: memo.createdAt,
                            lastModified: memo.lastModified,
                            title: memo.title,
                            duration: memo.duration,
                            transcription: memo.transcription,
                            notes: memo.notes,
                            summary: memo.summary,
                            audioFilePath: resolvedAudioPath,
                            originDeviceId: memo.originDeviceId
                        )
                        try record.save(db)
                    }

                    applied += 1

                case .delete:
                    // Delete from GRDB and clean up local audio payload.
                    let localAudioPath: String? = try await db.read { db in
                        try String.fetchOne(
                            db,
                            sql: "SELECT audioFilePath FROM voice_memos WHERE id = ?",
                            arguments: [change.id.uuidString]
                        )
                    }

                    try await db.write { db in
                        try db.execute(
                            sql: "DELETE FROM voice_memos WHERE id = ?",
                            arguments: [change.id.uuidString]
                        )
                    }

                    if let audioPath = localAudioPath, !audioPath.isEmpty {
                        AudioStorage.delete(filename: audioPath)
                    }

                    applied += 1
                }
            } catch {
                log.error("│   Error applying change \(change.id): \(error.localizedDescription)")
                skipped += 1
            }
        }

        log.info("│   Applied \(applied) change(s), skipped \(skipped)")

        // Notify UI of new data if any changes applied
        if applied > 0 {
            NotificationCenter.default.post(name: .syncDataAvailable, object: nil)
        }
    }

    /// Sync with a specific provider
    func sync(provider method: SyncMethod) async throws {
        guard let provider = providers[method] else {
            throw SyncCoordinatorError.providerNotRegistered(method)
        }

        guard isProviderEnabled(method) else {
            log.debug("Sync provider \(method.rawValue) is disabled, skipping")
            return
        }

        guard !isSyncing else {
            log.debug("Sync already in progress, skipping")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        log.info("Syncing with \(method.rawValue)...")

        // Check availability
        guard await provider.isAvailable else {
            throw SyncCoordinatorError.providerNotAvailable(method)
        }

        // Push and pull
        try await pushChanges(to: provider)
        try await pullChanges(from: provider)

        log.info("Sync with \(method.rawValue) complete")
    }

    // MARK: - Audio Resolution

    private func resolveAudioFilePath(for memo: MemoSyncDTO, localAudioPath: String?) -> String? {
        guard memo.hasAudio else { return nil }

        let canonicalFilename = "\(memo.id.uuidString).m4a"
        if AudioStorage.exists(filename: canonicalFilename) {
            return canonicalFilename
        }

        if let localAudioPath, AudioStorage.exists(filename: localAudioPath) {
            return localAudioPath
        }

        // Audio download via provider is not implemented in this foundation slice.
        log.warning("│   Remote memo \(memo.id) has audio, but no local file exists yet")
        return nil
    }

    // MARK: - Settings

    private func isProviderEnabled(_ method: SyncMethod) -> Bool {
        switch method {
        case .iCloud:
            return SettingsManager.shared.iCloudSyncEnabled
        default:
            return true
        }
    }
}

// MARK: - Errors

enum SyncCoordinatorError: Error, LocalizedError {
    case providerNotRegistered(SyncMethod)
    case providerNotAvailable(SyncMethod)

    var errorDescription: String? {
        switch self {
        case .providerNotRegistered(let method):
            return "Sync provider not registered: \(method.rawValue)"
        case .providerNotAvailable(let method):
            return "Sync provider not available: \(method.rawValue)"
        }
    }
}
