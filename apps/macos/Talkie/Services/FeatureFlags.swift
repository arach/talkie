//
//  FeatureFlags.swift
//  Talkie macOS
//
//  Runtime feature flags with local defaults and remote override capability.
//  Flags default to safe values (features OFF) and can be enabled remotely.
//

import Foundation
import os
import TalkieKit

private let log = Log(.system)

/// Feature flags for controlling app functionality
/// Supports both compile-time defaults and runtime remote overrides
@MainActor @Observable
final class FeatureFlags {
    static let shared = FeatureFlags()

    // MARK: - Configuration

    /// Base URL for feature flags API
    private let flagsURL = "https://api.usetalkie.com/api/flags"

    /// Timeout for remote flag fetch (seconds)
    private let fetchTimeout: TimeInterval = 5.0

    /// Cache duration for remote flags (seconds)
    private let cacheDuration: TimeInterval = 86400 // 24 hours

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

    /// Safe defaults used when remote flags unavailable
    /// All defaults should be conservative (features OFF)
    private let defaults: [String: Bool] = [
        "showConnectionCenter": false,
        "showExtensionAPI": false,
        "paywallEnabled": false,
        "showProFeatures": false,
        "enableCloudSync": false,
        "enableAutoUpdates": true,  // Updates should be ON by default
        "showDebugInfo": false,
        "enableCapture": false,      // Master: tray, drain-to-recording, capture system
        "enableCameraBubble": false, // Sub: floating camera preview, clip recording
        "enableScreenshots": false,  // Sub: Hyper+S chord, screenshot capture
        "enableCaptureRichUI": false, // Sub: richer screenshot overlay/preview visuals
        "enableNotchComposer": false, // TLK-027: Agent owns live notch/island rendering
        "enableVoiceForegrounding": false, // Experimental mic processing for voice over background audio
    ]

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
    private let childFlags: [String: [String]] = [
        "enableCapture": ["enableCameraBubble", "enableScreenshots"],
        "enableScreenshots": ["enableCaptureRichUI"],
    ]

    /// All top-level flag keys (excludes children), sorted alphabetically
    var allFlagKeys: [String] {
        let children = Set(childFlags.values.flatMap { $0 })
        return defaults.keys.filter { !children.contains($0) }.sorted()
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
    func refresh() async {
        guard !isFetching else {
            log.debug("Flag refresh already in progress, skipping")
            return
        }

        // Check cache validity
        if let lastFetch = lastFetchDate,
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

            log.info("Feature flags refreshed: \(flags.count) flags")
        } catch {
            lastError = error
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
                    await self.refresh()
                }
            }
        }
    }

    /// Fetch flags from API with timeout
    private func fetchFlags() async throws -> [String: Bool] {
        guard let url = URL(string: flagsURL) else {
            throw FeatureFlagError.invalidURL
        }

        // Add app version for targeting
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        components.queryItems = [
            URLQueryItem(name: "version", value: version),
            URLQueryItem(name: "build", value: build),
            URLQueryItem(name: "platform", value: "macos"),
        ]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = fetchTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw FeatureFlagError.serverError
        }

        // Parse response
        let decoder = JSONDecoder()
        let flagsResponse = try decoder.decode(FlagsResponse.self, from: data)

        return flagsResponse.flags
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
    private let sharedFlagKeys: [String: String] = [
        "enableCapture": AgentSettingsKey.featureCaptureEnabled,
        "enableNotchComposer": AgentSettingsKey.featureNotchComposerEnabled,
        "enableVoiceForegrounding": AgentSettingsKey.featureVoiceForegroundingEnabled,
    ]

    /// Write resolved flag value to TalkieSharedSettings so Agent can read it.
    private func syncToSharedDefaults(_ key: String) {
        guard let sharedKey = sharedFlagKeys[key] else { return }
        TalkieSharedSettings.set(flag(key), forKey: sharedKey)
    }

    /// Sync all cross-process flags on startup.
    func syncAllToSharedDefaults() {
        for (key, sharedKey) in sharedFlagKeys {
            TalkieSharedSettings.set(flag(key), forKey: sharedKey)
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
        syncAllToSharedDefaults()
        log.info("Feature flags cache cleared")
    }
}

// MARK: - Response Models

private struct FlagsResponse: Decodable {
    let flags: [String: Bool]
}

// MARK: - Errors

enum FeatureFlagError: LocalizedError {
    case invalidURL
    case serverError
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid flags URL"
        case .serverError: return "Server returned an error"
        case .decodingError: return "Failed to decode flags response"
        }
    }
}
