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
//  │    • Bundle IDs        → jdi.talkie.live vs jdi.talkie.live.dev             │
//  │    • XPC Services      → jdi.talkie.live.xpc vs jdi.talkie.live.xpc.dev     │
//  │    • Settings Storage  → com.jdi.talkie.shared vs .shared.dev               │
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
    case staging = "staging"
    case dev = "dev"

    /// Detect current environment from bundle identifier
    public static var current: TalkieEnvironment {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            return .dev  // Default to dev if no bundle ID (shouldn't happen)
        }

        // Check for staging suffix
        if bundleId.hasSuffix(".staging") {
            return .staging
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
        case .staging: return "Staging"
        case .dev: return "Dev"
        }
    }

    public var badge: String {
        switch self {
        case .production: return "PROD"
        case .staging: return "STAGE"
        case .dev: return "DEV"
        }
    }

    // MARK: - Bundle Identifiers

    /// Talkie main app bundle ID
    public var talkieBundleId: String {
        switch self {
        case .production: return "jdi.talkie.core"
        case .staging: return "jdi.talkie.core.staging"
        case .dev: return "jdi.talkie.core.dev"
        }
    }

    /// TalkieLive menu bar app bundle ID
    public var liveBundleId: String {
        switch self {
        case .production: return "jdi.talkie.live"
        case .staging: return "jdi.talkie.live.staging"
        case .dev: return "jdi.talkie.live.dev"
        }
    }

    /// TalkieEngine background service bundle ID
    public var engineBundleId: String {
        switch self {
        case .production: return "jdi.talkie.engine"
        case .staging: return "jdi.talkie.engine.staging"
        case .dev: return "jdi.talkie.engine.dev"
        }
    }

    // MARK: - XPC Service Names

    /// TalkieEngine XPC service name
    public var engineXPCService: String {
        switch self {
        case .production: return "jdi.talkie.engine.xpc"
        case .staging: return "jdi.talkie.engine.xpc.staging"
        case .dev: return "jdi.talkie.engine.xpc.dev"
        }
    }

    /// TalkieLive XPC service name (if needed in future)
    public var liveXPCService: String {
        switch self {
        case .production: return "jdi.talkie.live.xpc"
        case .staging: return "jdi.talkie.live.xpc.staging"
        case .dev: return "jdi.talkie.live.xpc.dev"
        }
    }

    // MARK: - Launchd Labels

    /// Launchd label for TalkieEngine (same as bundle ID)
    public var engineLaunchdLabel: String {
        engineBundleId
    }

    /// Launchd label for TalkieLive (same as bundle ID)
    public var liveLaunchdLabel: String {
        liveBundleId
    }

    // MARK: - URL Schemes

    /// Talkie URL scheme (e.g., "talkie", "talkie-staging", "talkie-dev")
    public var talkieURLScheme: String {
        switch self {
        case .production: return "talkie"
        case .staging: return "talkie-staging"
        case .dev: return "talkie-dev"
        }
    }

    /// TalkieLive URL scheme
    public var liveURLScheme: String {
        switch self {
        case .production: return "talkielive"
        case .staging: return "talkielive-staging"
        case .dev: return "talkielive-dev"
        }
    }

    /// TalkieEngine URL scheme
    public var engineURLScheme: String {
        switch self {
        case .production: return "talkieengine"
        case .staging: return "talkieengine-staging"
        case .dev: return "talkieengine-dev"
        }
    }

    // MARK: - App Locations

    /// Typical installation location for this environment
    public var expectedInstallLocation: String {
        switch self {
        case .production:
            return "/Applications/Talkie.app"
        case .staging:
            return "~/Applications/Staging/Talkie.app"
        case .dev:
            return "~/Library/Developer/Xcode/DerivedData/.../Talkie.app"
        }
    }

    // MARK: - Settings & Storage

    /// UserDefaults suite name for shared settings between Talkie and TalkieLive
    public var sharedSettingsSuite: String {
        switch self {
        case .production: return "com.jdi.talkie.shared"
        case .staging: return "com.jdi.talkie.shared.staging"
        case .dev: return "com.jdi.talkie.shared.dev"
        }
    }

    /// Application Support directory name for this environment
    public var appSupportDirectoryName: String {
        switch self {
        case .production: return "Talkie"
        case .staging: return "Talkie.staging"
        case .dev: return "Talkie.dev"
        }
    }

    /// Full path to Application Support directory for this environment
    public var appSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appSupportDirectoryName)
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
    /// Ensures dev/staging/prod hotkeys don't conflict at the OS level
    public var hotkeySignaturePrefix: String {
        switch self {
        case .production: return "TL"  // TLIV, TLPT, etc.
        case .staging: return "SL"     // SLIV, SLPT, etc.
        case .dev: return "DL"         // DLIV, DLPT, etc.
        }
    }

    /// Default hotkey modifiers - dev/staging add extra modifier to avoid muscle-memory conflicts
    public var defaultHotkeyModifiers: UInt32 {
        switch self {
        case .production: return UInt32(cmdKey | optionKey)              // ⌥⌘
        case .staging: return UInt32(cmdKey | optionKey | shiftKey)      // ⇧⌥⌘
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
        case .staging: return "orange"
        case .dev: return "red"
        }
    }
}

// MARK: - Convenience Global

/// Current environment for this process
public let currentEnvironment = TalkieEnvironment.current
