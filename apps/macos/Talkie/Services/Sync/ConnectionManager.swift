import Foundation
import TalkieKit

private let log = Log(.sync)

/// Manages available sync providers and orchestrates sync operations
@MainActor
@Observable
final class ConnectionManager {
    static let shared = ConnectionManager()

    // MARK: - State

    /// Status of each sync method
    private(set) var methodStatus: [SyncMethod: ConnectionStatus] = [:]

    /// Whether a sync is currently in progress
    private(set) var isSyncing = false

    /// Result of the last sync operation
    private(set) var lastSyncResult: SyncResult?

    /// User-preferred order of sync methods
    var preferredMethods: [SyncMethod] {
        get { loadPreferredMethods() }
        set { savePreferredMethods(newValue) }
    }

    /// Currently active sync provider (highest priority available)
    private(set) var activeProvider: (any SyncProvider)?

    /// Registered providers
    private var providers: [SyncMethod: any SyncProvider] = [:]

    // MARK: - Init

    private init() {
        // Local is always available
        methodStatus[.local] = .available
    }

    // MARK: - Provider Registration

    /// Register a sync provider
    func register(_ provider: any SyncProvider) {
        providers[provider.method] = provider
        log.info("Registered sync provider: \(provider.method.rawValue)")
    }

    /// Get provider for method
    func provider(for method: SyncMethod) -> (any SyncProvider)? {
        providers[method]
    }

    // MARK: - Connection Checking

    /// Check all registered providers
    func checkAllConnections() async {
        for (method, provider) in providers {
            // Check user preference for iCloud
            if method == .iCloud {
                let isICloudEnabled = self.isICloudEnabled
                if !isICloudEnabled {
                    methodStatus[method] = .unavailable(reason: "Disabled by user")
                    continue
                }
            }

            let status = await provider.checkConnection()
            methodStatus[method] = status
        }
        await updateActiveProvider()
    }

    /// Update active provider based on availability and preference
    private func updateActiveProvider() async {
        for method in preferredMethods {
            // Skip if user disabled this method
            if method == .iCloud {
                let isICloudEnabled = self.isICloudEnabled
                if !isICloudEnabled {
                    continue
                }
            }

            if let provider = providers[method],
               methodStatus[method] == .available {
                activeProvider = provider
                log.info("Active sync provider: \(method.rawValue)")
                return
            }
        }
        // Fallback to local
        activeProvider = providers[.local]
    }

    /// Set the active sync provider to a specific method
    func setActiveProvider(_ method: SyncMethod) async {
        guard let provider = providers[method] else {
            log.warning("Cannot set active provider: \(method.rawValue) not registered")
            return
        }

        // Check availability first
        let status = await provider.checkConnection()
        methodStatus[method] = status

        guard status == .available else {
            log.warning("Cannot set active provider: \(method.rawValue) is not available")
            return
        }

        activeProvider = provider
        log.info("Active sync provider set to: \(method.rawValue)")
    }

    // MARK: - User Preferences

    /// Check if iCloud sync is enabled by user
    private var isICloudEnabled: Bool {
        SettingsManager.shared.iCloudSyncEnabled
    }

    // MARK: - Sync Operations

    /// Sync using active provider
    func sync() async throws {
        guard let provider = activeProvider else {
            log.warning("No active sync provider")
            return
        }

        isSyncing = true
        methodStatus[provider.method] = .syncing

        do {
            try await provider.fullSync()
            lastSyncResult = .success(itemsSynced: 0) // TODO: get actual count from provider
            isSyncing = false
            methodStatus[provider.method] = .available
        } catch {
            lastSyncResult = .failure(error.localizedDescription)
            isSyncing = false
            methodStatus[provider.method] = .available
            throw error
        }
    }

    // MARK: - Persistence

    private func loadPreferredMethods() -> [SyncMethod] {
        guard let data = UserDefaults.standard.data(forKey: "sync_preferred_methods"),
              let methods = try? JSONDecoder().decode([SyncMethod].self, from: data) else {
            // Default order
            return [.iCloud, .bridge, .dropbox, .local]
        }
        return methods
    }

    private func savePreferredMethods(_ methods: [SyncMethod]) {
        if let data = try? JSONEncoder().encode(methods) {
            UserDefaults.standard.set(data, forKey: "sync_preferred_methods")
        }
    }
}
