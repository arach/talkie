//
//  TalkieEnvironment.swift
//  TalkieKit
//
//  SINGLE SOURCE OF TRUTH for all environment-specific configuration.
//
//  ┌─────────────────────────────────────────────────────────────────────────────┐
//  │                        ENVIRONMENT ISOLATION PHILOSOPHY                      │
//  ├─────────────────────────────────────────────────────────────────────────────┤
//  │                                                                              │
//  │  The developer uses their Mac for BOTH production daily work AND development.│
//  │  This means prod and dev instances of Talkie apps run simultaneously.        │
//  │                                                                              │
//  │  To prevent conflicts, EVERYTHING environment-specific flows from here:      │
//  │                                                                              │
//  │    • Bundle IDs        → app-specific production/dev IDs                     │
//  │    • XPC Services      → app-specific production/dev service names           │
//  │    • Settings Storage  → app-specific production/dev suites                  │
//  │    • Database Paths    → ~/Library/Application Support/Talkie vs Talkie.dev │
//  │    • Hotkey Signatures → TLIV vs DLIV (OS-level hotkey routing)             │
//  │    • Default Hotkeys   → ⌥⌘L (prod) vs ⌃⌥⌘L (dev, intentionally awkward)   │
//  │    • URL Schemes       → talkie:// vs talkie-dev://                         │
//  │                                                                              │
//  │  RULE: Never hardcode environment-specific values elsewhere in the codebase. │
//  │        Always derive them from TalkieEnvironment.current.                    │
//  │                                                                              │
//  │  RULE: Prod settings are sacred. Dev can experiment freely without risk.     │
//  │                                                                              │
//  └─────────────────────────────────────────────────────────────────────────────┘
//

import Foundation
import Carbon.HIToolbox

/// Talkie deployment environment - the single source of truth for all environment-specific config
public enum TalkieEnvironment: String, CaseIterable, Sendable {
    case production = "production"
    case dev = "dev"

    /// Detect current environment from bundle identifier
    public static var current: TalkieEnvironment {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            return .dev  // Default to dev if no bundle ID (shouldn't happen)
        }

        // Check for dev suffix
        if bundleId.hasSuffix(".dev") {
            return .dev
        }

        // No suffix = production
        return .production
    }

    // MARK: - Display Names

    public var displayName: String {
        switch self {
        case .production: return "Production"
        case .dev: return "Dev"
        }
    }

    public var badge: String {
        switch self {
        case .production: return "PROD"
        case .dev: return "DEV"
        }
    }

    // MARK: - Parameterized Helper Lookups

    /// Get bundle ID for any helper kind in this environment
    public func bundleId(for kind: TalkieHelper) -> String {
        kind.bundleId(for: self)
    }

    /// Get XPC service name for any helper kind in this environment
    public func xpcServiceName(for kind: TalkieHelper) -> String {
        kind.xpcServiceName(for: self)
    }

    /// Get launchd label for any helper kind in this environment
    public func launchdLabel(for kind: TalkieHelper) -> String {
        kind.launchdLabel(for: self)
    }

    /// Get URL scheme for any helper kind in this environment
    public func urlScheme(for kind: TalkieHelper) -> String {
        kind.urlScheme(for: self)
    }

    // MARK: - Bundle Identifiers

    /// Talkie main app bundle ID
    public var talkieBundleId: String {
        switch self {
        case .production: return "to.talkie.app.mac"
        case .dev: return "to.talkie.app.mac.dev"
        }
    }

    /// TalkieAgent menu bar app bundle ID
    @available(*, deprecated, message: "Use TalkieHelper.agent.bundleId(for:) or env.bundleId(for: .agent)")
    public var liveBundleId: String { bundleId(for: .agent) }

    /// TalkieEngine background service bundle ID
    @available(*, deprecated, message: "Use TalkieHelper.engine.bundleId(for:) or env.bundleId(for: .engine)")
    public var engineBundleId: String { bundleId(for: .engine) }

    /// TalkieSync sync helper bundle ID
    @available(*, deprecated, message: "Use TalkieHelper.sync.bundleId(for:) or env.bundleId(for: .sync)")
    public var syncBundleId: String { bundleId(for: .sync) }

    // MARK: - XPC Service Names

    /// TalkieEngine XPC service name
    @available(*, deprecated, message: "Use TalkieHelper.engine.xpcServiceName(for:)")
    public var engineXPCService: String { xpcServiceName(for: .engine) }

    /// TalkieAgent XPC service name
    @available(*, deprecated, message: "Use TalkieHelper.agent.xpcServiceName(for:)")
    public var liveXPCService: String { xpcServiceName(for: .agent) }

    /// TalkieSync XPC service name
    @available(*, deprecated, message: "Use TalkieHelper.sync.xpcServiceName(for:)")
    public var syncXPCService: String { xpcServiceName(for: .sync) }

    // MARK: - Launchd Labels

    /// Launchd label for TalkieEngine (same as bundle ID)
    @available(*, deprecated, message: "Use TalkieHelper.engine.launchdLabel(for:)")
    public var engineLaunchdLabel: String { launchdLabel(for: .engine) }

    /// Launchd label for TalkieAgent (same as bundle ID)
    @available(*, deprecated, message: "Use TalkieHelper.agent.launchdLabel(for:)")
    public var liveLaunchdLabel: String { launchdLabel(for: .agent) }

    /// Launchd label for TalkieSync (same as bundle ID)
    @available(*, deprecated, message: "Use TalkieHelper.sync.launchdLabel(for:)")
    public var syncLaunchdLabel: String { launchdLabel(for: .sync) }

    // MARK: - URL Schemes

    /// Talkie URL scheme (e.g., "talkie", "talkie-dev")
    public var talkieURLScheme: String {
        switch self {
        case .production: return "talkie"
        case .dev: return "talkie-dev"
        }
    }

    /// TalkieAgent URL scheme
    @available(*, deprecated, message: "Use TalkieHelper.agent.urlScheme(for:)")
    public var liveURLScheme: String { urlScheme(for: .agent) }

    /// TalkieEngine URL scheme
    @available(*, deprecated, message: "Use TalkieHelper.engine.urlScheme(for:)")
    public var engineURLScheme: String { urlScheme(for: .engine) }

    /// TalkieSync URL scheme
    @available(*, deprecated, message: "Use TalkieHelper.sync.urlScheme(for:)")
    public var syncURLScheme: String { urlScheme(for: .sync) }

    // MARK: - App Locations

    /// Typical installation location for this environment
    public var expectedInstallLocation: String {
        switch self {
        case .production:
            return "/Applications/Talkie.app"
        case .dev:
            return userInstalledAppURL(named: "Talkie.app").path
        }
    }

    // MARK: - Settings & Storage

    /// UserDefaults suite name for shared settings between Talkie and TalkieAgent
    public var sharedSettingsSuite: String {
        let baseSuite = configuredIdentifier(
            environmentKey: "TALKIE_MAC_SHARED_SETTINGS_SUITE",
            infoDictionaryKey: "TalkieSharedSettingsSuite",
            fallback: "to.talkie.app.shared"
        )

        return environmentScopedIdentifier(baseSuite)
    }

    /// App Group identifier for macOS helpers and shared containers.
    public var macAppGroupIdentifier: String {
        configuredIdentifier(
            environmentKey: "TALKIE_MAC_APP_GROUP",
            infoDictionaryKey: "TalkieMacAppGroupIdentifier",
            fallback: defaultMacAppGroupIdentifier
        )
    }

    /// Shared CloudKit container identifier for apps/ios/macOS sync.
    public var cloudKitContainerIdentifier: String {
        configuredIdentifier(
            environmentKey: "TALKIE_CLOUDKIT_CONTAINER",
            infoDictionaryKey: "TalkieCloudKitContainerIdentifier",
            fallback: "iCloud.to.talkie"
        )
    }

    private var defaultMacAppGroupIdentifier: String {
        switch self {
        case .production: return "group.to.talkie.app.mac"
        case .dev: return "group.to.talkie.app.mac.dev"
        }
    }

    /// Application Support directory name for this environment
    public var appSupportDirectoryName: String {
        switch self {
        case .production: return "Talkie"
        case .dev: return "Talkie.dev"
        }
    }

    /// Full path to Application Support directory for this environment
    public var appSupportDirectory: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent(appSupportDirectoryName)
    }

    /// Stable user-local app install directory for this environment.
    ///
    /// Dev builds use this as their runnable location so Accessibility, launchd,
    /// and runtime manifests all point at one path instead of whichever DerivedData
    /// build happened to be newest.
    public var userInstalledApplicationsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent(appSupportDirectoryName, isDirectory: true)
    }

    public func userInstalledAppURL(named appName: String) -> URL {
        userInstalledApplicationsDirectory
            .appendingPathComponent(appName, isDirectory: true)
    }

    /// Database directory for this environment
    public var databaseDirectory: URL {
        appSupportDirectory.appendingPathComponent("Database")
    }

    /// Logs directory for this environment
    public var logsDirectory: URL {
        appSupportDirectory.appendingPathComponent("Logs")
    }

    // MARK: - Hotkey Configuration

    /// Hotkey signature prefix (4-char OSType needs 2-char prefix + 2-char suffix)
    /// Ensures dev/prod hotkeys don't conflict at the OS level
    public var hotkeySignaturePrefix: String {
        switch self {
        case .production: return "TL"  // TLIV, TLPT, etc.
        case .dev: return "DL"         // DLIV, DLPT, etc.
        }
    }

    /// Default hotkey modifiers - dev adds an extra modifier to avoid muscle-memory conflicts
    public var defaultHotkeyModifiers: UInt32 {
        switch self {
        case .production: return UInt32(cmdKey | optionKey)              // ⌥⌘
        case .dev: return UInt32(cmdKey | optionKey | controlKey)        // ⌃⌥⌘
        }
    }

    // MARK: - Visual Indicators

    /// Whether to show environment badge in UI
    public var showEnvironmentBadge: Bool {
        self != .production
    }

    /// Color for environment indicator (matches engine badge colors)
    public var indicatorColor: String {
        switch self {
        case .production: return "blue"
        case .dev: return "red"
        }
    }

    // MARK: - Web Services

    /// API base URL (backend for auth, entitlements, data)
    public var apiBaseURL: String {
        switch self {
        case .production: return "https://api.usetalkie.com"
        case .dev: return "https://api.usetalkie.com"      // Use prod API in dev too
        }
    }

    /// Dedicated base URL for the new live-workflow/control-plane API.
    /// This intentionally moves independently from older API consumers.
    public var workflowAPIBaseURL: String {
        configuredServiceURL(
            environmentKey: "TALKIE_WORKFLOW_API_BASE_URL",
            infoDictionaryKey: "TalkieWorkflowAPIBaseURL",
            fallback: "https://api.talkie.to"
        )
    }

    /// Clerk auth domain (hosted sign-in UI - "Account Portal" in Clerk)
    public var authDomain: String {
        switch self {
        case .production: return "https://clerk.usetalkie.com"
        case .dev: return "https://supreme-stallion-9.clerk.accounts.dev"
        }
    }

    /// User portal domain (account, devices, usage dashboard)
    public var portalDomain: String {
        switch self {
        case .production: return "https://my.usetalkie.com"
        case .dev: return "https://my.usetalkie.com"  // No dev portal yet
        }
    }

    /// Cloud services gateway URL
    public var cloudBaseURL: String {
        switch self {
        case .production: return "https://cloud.usetalkie.com"
        case .dev: return "https://cloud.usetalkie.com"  // TBD
        }
    }

    private func configuredServiceURL(
        environmentKey: String,
        infoDictionaryKey: String,
        fallback: String
    ) -> String {
        if let override = ProcessInfo.processInfo.environment[environmentKey]?.trimmedForURLOverride {
            return override
        }

        if let override = Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey) as? String,
           let trimmed = override.trimmedForURLOverride {
            return trimmed
        }

        return fallback
    }

    private func configuredIdentifier(
        environmentKey: String,
        infoDictionaryKey: String,
        fallback: String
    ) -> String {
        if let override = ProcessInfo.processInfo.environment[environmentKey]?.trimmedForIdentifierOverride {
            return override
        }

        if let override = Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey) as? String,
           let trimmed = override.trimmedForIdentifierOverride {
            return trimmed
        }

        return fallback
    }

    private func environmentScopedIdentifier(_ identifier: String) -> String {
        switch self {
        case .production:
            return identifier
        case .dev:
            return identifier.hasSuffix(".dev") ? identifier : "\(identifier).dev"
        }
    }
}

private extension String {
    var trimmedForURLOverride: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmedForIdentifierOverride: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Convenience Global

/// Current environment for this process
public let currentEnvironment = TalkieEnvironment.current
