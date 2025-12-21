//
//  TalkieEnvironment.swift
//  TalkieKit
//
//  Environment detection and configuration for Talkie suite
//  Ensures production, staging, and dev builds don't collide
//

import Foundation

/// Talkie deployment environment
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
