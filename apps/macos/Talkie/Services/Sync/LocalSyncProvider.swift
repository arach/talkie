import Foundation

/// Local-only "sync" provider - always available, no-op sync
class LocalSyncProvider: SyncProvider {
    let method: SyncMethod = .local

    var isAvailable: Bool {
        get async { true }
    }

    var lastSyncDate: Date? {
        get async { Date() }
    }

    func checkConnection() async -> ConnectionStatus {
        .available
    }

    func pushChanges(_ changes: [MemoChange]) async throws {
        // Local storage already has changes - no-op
    }

    func pullChanges(since: Date?) async throws -> [MemoChange] {
        // Nothing to pull from local - no-op
        return []
    }

    func fullSync() async throws {
        // No-op for local
    }
}
