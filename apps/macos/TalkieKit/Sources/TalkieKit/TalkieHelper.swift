//
//  TalkieHelper.swift
//  TalkieKit
//
//  Single enum that consolidates all per-helper identity lookups.
//  Replaces scattered properties on TalkieEnvironment with parameterized lookups.
//

import Foundation

/// Identifies a Talkie helper process (Agent, Engine, Sync).
///
/// Use this with a `TalkieEnvironment` to get environment-aware bundle IDs,
/// XPC service names, launchd labels, etc.
///
/// ```swift
/// let bundleId = TalkieHelper.sync.bundleId(for: .dev)
/// // → "to.talkie.app.sync.dev"
/// ```
public enum TalkieHelper: String, CaseIterable, Sendable {
    case agent     // TalkieAgent
    case engine    // TalkieEngine
    case sync      // TalkieSync

    // MARK: - Display

    public var displayName: String {
        switch self {
        case .agent: return "TalkieAgent"
        case .engine: return "TalkieEngine"
        case .sync: return "TalkieSync"
        }
    }

    public var appName: String {
        "\(displayName).app"
    }

    public var executableName: String {
        displayName
    }

    // MARK: - Lifecycle

    /// Whether this helper should be kept alive by launchd (restarted on exit)
    /// or launched on-demand via MachServices XPC only.
    public var keepAlive: Bool {
        switch self {
        case .agent, .engine, .sync: return true
        }
    }

    /// Default lifecycle mode when the user hasn't chosen one.
    public var defaultLifecycleMode: HelperLifecycleMode {
        switch self {
        case .agent: return .alwaysOn
        case .engine: return .alwaysOn
        case .sync: return .attached
        }
    }

    // MARK: - Bundle ID base (without environment suffix)

    private var bundleIdBase: String {
        switch self {
        case .agent: return "to.talkie.app.agent"
        case .engine: return "to.talkie.app.engine"
        case .sync: return "to.talkie.app.sync"
        }
    }

    // MARK: - Environment-aware lookups

    /// Bundle identifier for this helper in the given environment
    public func bundleId(for env: TalkieEnvironment) -> String {
        switch env {
        case .production: return bundleIdBase
        case .dev: return "\(bundleIdBase).dev"
        }
    }

    /// XPC Mach service name for this helper in the given environment
    public func xpcServiceName(for env: TalkieEnvironment) -> String {
        switch env {
        case .production: return "\(bundleIdBase).xpc"
        case .dev: return "\(bundleIdBase).xpc.dev"
        }
    }

    /// Launchd label for this helper in the given environment (same as bundle ID)
    public func launchdLabel(for env: TalkieEnvironment) -> String {
        bundleId(for: env)
    }

    /// URL scheme for this helper in the given environment
    public func urlScheme(for env: TalkieEnvironment) -> String {
        let base: String
        switch self {
        case .agent: base = "talkieagent"
        case .engine: base = "talkieengine"
        case .sync: base = "talkiesync"
        }

        switch env {
        case .production: return base
        case .dev: return "\(base)-dev"
        }
    }

    public func userInstalledAppURL(for env: TalkieEnvironment) -> URL {
        env.userInstalledAppURL(named: appName)
    }

    /// Distributed notification name for XPC readiness signal
    public func xpcReadyNotificationName(for env: TalkieEnvironment) -> Notification.Name {
        Notification.Name("\(xpcServiceName(for: env)).ready")
    }

    /// The production launchd label (without environment suffix) used for bundled plist filenames.
    /// For environment-specific labels (dev), use `bundleId(for:)` instead.
    public var plistLabel: String {
        bundleIdBase
    }
}

/// How a helper's runtime is managed relative to Talkie.app.
public enum HelperLifecycleMode: String, Codable, Sendable, CaseIterable {
    /// Runs independently of Talkie.app via launchd KeepAlive.
    case alwaysOn
    /// Starts with Talkie.app, stops when Talkie.app quits.
    case attached
    /// User manually starts/stops; Talkie lifecycle does not touch it.
    case onDemand

    public var displayName: String {
        switch self {
        case .alwaysOn: return "Always on"
        case .attached: return "Attached"
        case .onDemand: return "On demand"
        }
    }

    public var summary: String {
        switch self {
        case .alwaysOn: return "Runs independently of Talkie.app."
        case .attached: return "Starts with Talkie, stops with Talkie."
        case .onDemand: return "Only runs when you start it."
        }
    }
}
