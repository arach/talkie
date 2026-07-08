//
//  FeatureFlags.swift
//  Talkie macOS
//
//  Runtime feature flags with local defaults and remote override capability.
//  Product defaults ship in the binary; remote flags can override post-release.
//

import Foundation
import TalkieKit

private let log = Log(.system)

/// Feature flags for controlling app functionality
/// Supports both compile-time defaults and runtime remote overrides
@MainActor @Observable
final class FeatureFlags {
    static let shared = FeatureFlags()

    // MARK: - Configuration

    /// Cache duration for remote flags (seconds)
    private let cacheDuration: TimeInterval = RuntimeFeatureFlags.cacheDuration

    /// Max retries on transient failure
    private let maxRetries = 2

    /// Delay between retries (seconds)
    private let retryDelay: TimeInterval = 60

    // MARK: - State

    /// Last successful fetch timestamp
    private(set) var lastFetchDate: Date?

    /// Whether a fetch is currently in progress
    private(set) var isFetching = false

    /// Last fetch error (if any)
    private(set) var lastError: Error?

    /// Current retry count for transient failures
    private var retryCount = 0

    // MARK: - Local Defaults (compile-time fallbacks)

    /// Product defaults used when remote flags are unavailable.
    /// Experimental or paid surfaces stay off; shipped local features can default on.
    private let defaults = RuntimeFeatureFlags.defaults

    // MARK: - Remote Overrides

    /// Flags fetched from remote server
    private var remoteFlags: [String: Bool] = [:]

    /// Local user overrides (set via settings UI, take highest precedence)
    private var localOverrides: [String: Bool] = [:]

    /// UserDefaults key for persisted remote flags
    private let persistedFlagsKey = "featureFlags.remote"
    private let lastFetchKey = "featureFlags.lastFetch"
    private let localOverridesKey = "featureFlags.localOverrides"

    // MARK: - Public Flag Accessors

    /// Show Connection Center in Settings (iOS bridge, Tailscale, etc.)
    var showConnectionCenter: Bool {
        flag("showConnectionCenter")
    }

    /// Show Extension API badge in Compose (TalkieServer integration)
    var showExtensionAPI: Bool {
        flag("showExtensionAPI")
    }

    /// Enable paywall gate for premium features
    var paywallEnabled: Bool {
        flag("paywallEnabled")
    }

    /// Show Pro features UI (even if locked behind paywall)
    var showProFeatures: Bool {
        flag("showProFeatures")
    }

    /// Enable CloudKit sync features
    var enableCloudSync: Bool {
        flag("enableCloudSync")
    }

    /// Enable automatic update checks
    var enableAutoUpdates: Bool {
        flag("enableAutoUpdates")
    }

    /// Show debug info in Settings
    var showDebugInfo: Bool {
        flag("showDebugInfo")
    }

    /// Master gate for the entire capture system (tray, drain-to-recording, shortcuts)
    var enableCapture: Bool {
        flag("enableCapture")
    }

    /// Enable camera bubble and clip recording (requires enableCapture)
    var enableCameraBubble: Bool {
        enableCapture && flag("enableCameraBubble")
    }

    /// Enable screenshot capture via Hyper+S chord (requires enableCapture)
    var enableScreenshots: Bool {
        enableCapture && flag("enableScreenshots")
    }

    /// Enable richer screenshot visuals (requires screenshot capture)
    var enableCaptureRichUI: Bool {
        enableScreenshots && flag("enableCaptureRichUI")
    }

    /// Legacy Talkie-owned notch composer. Agent owns live notch/island rendering by default.
    var enableNotchComposer: Bool {
        flag("enableNotchComposer")
    }

    /// Experimental mic processing for making speech more prominent over local background audio
    var enableVoiceForegrounding: Bool {
        flag("enableVoiceForegrounding")
    }

    // MARK: - Initialization

    private init() {
        // Load persisted flags from UserDefaults
        loadPersistedFlags()
        loadLocalOverrides()
    }

    // MARK: - Flag Resolution

    /// Get flag value: local override > remote override > compile-time default
    private func flag(_ key: String) -> Bool {
        // User's local override takes highest precedence (set via settings UI)
        if let local = localOverrides[key] {
            return local
        }
        // Remote override
        if let remote = remoteFlags[key] {
            return remote
        }
        // Fall back to compile-time default
        return defaults[key] ?? false
    }

    /// Check if a specific flag is overridden remotely
    func isRemoteOverride(_ key: String) -> Bool {
        remoteFlags[key] != nil
    }

    /// Parent → children relationships for hierarchical display
    private let childFlags = RuntimeFeatureFlags.childFlags

    /// All top-level flag keys (excludes children), sorted alphabetically
    var allFlagKeys: [String] {
        RuntimeFeatureFlags.topLevelKeys
    }

    /// Children of a given flag key (empty if none)
    func children(of key: String) -> [String] {
        childFlags[key] ?? []
    }

    /// Get all current flag values (for debugging)
    var allFlags: [String: Bool] {
        var result = defaults
        for (key, value) in remoteFlags {
            result[key] = value
        }
        for (key, value) in localOverrides {
            result[key] = value
        }
        return result
    }

    var remoteFlagCount: Int {
        remoteFlags.count
    }

    var localOverrideCount: Int {
        localOverrides.count
    }

    /// Check if a flag has a local override set
    func isLocalOverride(_ key: String) -> Bool {
        localOverrides[key] != nil
    }

    /// Get the compile-time default value for a flag
    func defaultValue(_ key: String) -> Bool {
        defaults[key] ?? false
    }

    /// Source of the current flag value
    func flagSource(_ key: String) -> String {
        if localOverrides[key] != nil { return "local" }
        if remoteFlags[key] != nil { return "remote" }
        return "default"
    }

    // MARK: - Remote Fetch

    /// Fetch latest flags from remote server
    /// Non-blocking, fires notification on completion
    func refresh(force: Bool = false) async {
        guard !isFetching else {
            log.debug("Flag refresh already in progress, skipping")
            return
        }

        // Check cache validity
        if !force,
           let lastFetch = lastFetchDate,
           Date().timeIntervalSince(lastFetch) < cacheDuration {
            log.debug("Using cached flags (fetched \(Int(Date().timeIntervalSince(lastFetch)))s ago)")
            return
        }

        isFetching = true
        defer { isFetching = false }

        do {
            let flags = try await fetchFlags()
            remoteFlags = flags
            lastFetchDate = Date()
            lastError = nil
            retryCount = 0

            // Persist for offline use
            persistFlags()

            // Re-sync to Agent so it sees the fresh values
            syncAllToSharedDefaults()
            persistSharedSnapshot()

            log.info("Feature flags refreshed: \(flags.count) flags")
        } catch {
            lastError = error
            persistSharedError(error.localizedDescription)
            log.warning("Failed to fetch feature flags: \(error.localizedDescription)")
            // Keep using cached/persisted flags on failure

            // Schedule retry on transient failure
            if retryCount < maxRetries {
                retryCount += 1
                let attempt = retryCount
                log.info("Scheduling flag fetch retry \(attempt)/\(maxRetries) in \(Int(retryDelay))s")
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(self?.retryDelay ?? 60))
                    guard let self else { return }
                    // Clear cache gate so refresh() doesn't short-circuit
                    self.lastFetchDate = nil
                    await self.refresh(force: true)
                }
            }
        }
    }

    /// Fetch flags from API with timeout
    private func fetchFlags() async throws -> [String: Bool] {
        return try await RuntimeFeatureFlags.fetchRemoteFlags()
    }

    // MARK: - Persistence

    private func loadPersistedFlags() {
        if let data = UserDefaults.standard.data(forKey: persistedFlagsKey),
           let flags = try? JSONDecoder().decode([String: Bool].self, from: data) {
            remoteFlags = flags
            log.debug("Loaded \(flags.count) persisted feature flags")
        }

        if let lastFetch = UserDefaults.standard.object(forKey: lastFetchKey) as? Date {
            lastFetchDate = lastFetch
        }
    }

    private func persistFlags() {
        if let data = try? JSONEncoder().encode(remoteFlags) {
            UserDefaults.standard.set(data, forKey: persistedFlagsKey)
        }
        UserDefaults.standard.set(lastFetchDate, forKey: lastFetchKey)
    }

    private func persistSharedSnapshot() {
        if let data = try? JSONEncoder().encode(remoteFlags) {
            TalkieSharedSettings.set(data, forKey: AgentSettingsKey.featureFlagsRemotePayload)
        }
        if let lastFetchDate {
            TalkieSharedSettings.set(lastFetchDate, forKey: AgentSettingsKey.featureFlagsLastFetch)
        }
        TalkieSharedSettings.set(remoteFlags.count, forKey: AgentSettingsKey.featureFlagsRemoteCount)
        TalkieSharedSettings.removeObject(forKey: AgentSettingsKey.featureFlagsLastError)
    }

    private func persistSharedError(_ message: String) {
        TalkieSharedSettings.set(message, forKey: AgentSettingsKey.featureFlagsLastError)
    }

    // MARK: - Local Overrides

    /// Set a local override for a flag (persisted, takes precedence over remote)
    func setLocalOverride(_ key: String, value: Bool) {
        localOverrides[key] = value
        persistLocalOverrides()
        syncToSharedDefaults(key)
        log.info("Feature flag '\(key)' locally set to \(value)")
    }

    /// Remove a local override (reverts to remote/default)
    func clearLocalOverride(_ key: String) {
        localOverrides.removeValue(forKey: key)
        persistLocalOverrides()
        syncToSharedDefaults(key)
        log.info("Feature flag '\(key)' local override cleared")
    }

    private func loadLocalOverrides() {
        if let data = UserDefaults.standard.data(forKey: localOverridesKey),
           let overrides = try? JSONDecoder().decode([String: Bool].self, from: data) {
            localOverrides = overrides
            log.debug("Loaded \(overrides.count) local flag overrides")
        }
    }

    private func persistLocalOverrides() {
        if let data = try? JSONEncoder().encode(localOverrides) {
            UserDefaults.standard.set(data, forKey: localOverridesKey)
        }
    }

    // MARK: - Cross-Process Sync

    /// Map of feature flag keys to their shared defaults keys.
    /// Only flags that other processes need to read go here.
    private let sharedFlagKeys = RuntimeFeatureFlags.sharedSettingsKeys

    /// Write resolved flag value to TalkieSharedSettings so Agent can read it.
    private func syncToSharedDefaults(_ key: String) {
        guard let sharedKey = sharedFlagKeys[key] else { return }
        let resolvedValue = flag(key)
        let previousObject = TalkieSharedSettings.object(forKey: sharedKey)
        let previousValue = (previousObject as? Bool) ?? (previousObject as? NSNumber)?.boolValue
        TalkieSharedSettings.set(resolvedValue, forKey: sharedKey)

        guard previousValue != resolvedValue else { return }

        if sharedKey == AgentSettingsKey.featureCaptureEnabled {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("to.talkie.agentHotkeysDidChange"),
                object: "featureCaptureEnabled",
                userInfo: nil,
                deliverImmediately: true
            )
        }
    }

    /// Sync all cross-process flags on startup.
    func syncAllToSharedDefaults() {
        for key in sharedFlagKeys.keys {
            syncToSharedDefaults(key)
        }
    }

    /// Clear all persisted flags (for testing)
    func clearCache() {
        remoteFlags = [:]
        localOverrides = [:]
        lastFetchDate = nil
        UserDefaults.standard.removeObject(forKey: persistedFlagsKey)
        UserDefaults.standard.removeObject(forKey: lastFetchKey)
        UserDefaults.standard.removeObject(forKey: localOverridesKey)
        TalkieSharedSettings.removeObject(forKey: AgentSettingsKey.featureFlagsRemotePayload)
        TalkieSharedSettings.removeObject(forKey: AgentSettingsKey.featureFlagsLastFetch)
        TalkieSharedSettings.removeObject(forKey: AgentSettingsKey.featureFlagsLastError)
        TalkieSharedSettings.removeObject(forKey: AgentSettingsKey.featureFlagsRemoteCount)
        syncAllToSharedDefaults()
        log.info("Feature flags cache cleared")
    }
}
