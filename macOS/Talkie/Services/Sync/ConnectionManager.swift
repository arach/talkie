import Foundation
import TalkieKit

private let log = Log(.sync)

/// Manages available sync providers and orchestrates sync operations
@Observable
class ConnectionManager {
    static let shared = ConnectionManager()

    // MARK: - State

    /// Status of each sync method
    private(set) var methodStatus: [SyncMethod: ConnectionStatus] = [:]

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
            if method == .iCloud && !isICloudEnabled {
                await MainActor.run {
                    methodStatus[method] = .unavailable(reason: "Disabled by user")
                }
                continue
            }

            let status = await provider.checkConnection()
            await MainActor.run {
                methodStatus[method] = status
            }
        }
        await updateActiveProvider()
    }

    /// Update active provider based on availability and preference
    private func updateActiveProvider() async {
        for method in preferredMethods {
            // Skip if user disabled this method
            if method == .iCloud && !isICloudEnabled {
                continue
            }

            if let provider = providers[method],
               methodStatus[method] == .available {
                await MainActor.run {
                    activeProvider = provider
                }
                log.info("Active sync provider: \(method.rawValue)")
                return
            }
        }
        // Fallback to local
        await MainActor.run {
            activeProvider = providers[.local]
        }
    }

    // MARK: - User Preferences

    /// Check if iCloud sync is enabled by user
    private var isICloudEnabled: Bool {
        UserDefaults.standard.object(forKey: SyncSettingsKey.iCloudEnabled) as? Bool ?? true
    }

    // MARK: - Sync Operations

    /// Sync using active provider
    func sync() async throws {
        guard let provider = activeProvider else {
            log.warning("No active sync provider")
            return
        }

        await MainActor.run {
            methodStatus[provider.method] = .syncing
        }

        defer {
            Task { @MainActor in
                methodStatus[provider.method] = .available
            }
        }

        try await provider.fullSync()
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
