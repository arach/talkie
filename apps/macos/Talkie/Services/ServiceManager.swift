//
//  ServiceManager.swift
//  Talkie
//
//  Unified service state management for TalkieAgent and TalkieEngine.
//  Single source of truth for all service state, lifecycle, and process info.
//
//  Usage:
//    ServiceManager.shared.live.isRunning
//    ServiceManager.shared.live.toggleRecording()
//    ServiceManager.shared.engine.isConnected
//    ServiceManager.shared.launchLive()
//

import Foundation
import AppKit
import Combine
import TalkieKit
import Observation

private let logger = Log(.system)
private let companionRuntimeSignalLog = Log(.xpc)

enum CompanionRuntimeSignal {
    private static let signalFileURL = TalkieEnvironment.current.appSupportDirectory
        .appendingPathComponent("Bridge")
        .appendingPathComponent(".config")
        .appendingPathComponent("companion-runtime.signal")

    static func prepare() {
        do {
            try ensureSignalFileExists(seedReason: "bootstrap")
        } catch {
            companionRuntimeSignalLog.warning("Failed to prepare companion runtime signal", detail: "\(error)")
        }
    }

    static func notify(reason: String) {
        do {
            try ensureSignalFileExists()
            let payload = "at=\(ISO8601DateFormatter().string(from: Date()))\nreason=\(reason)\n"
            guard let data = payload.data(using: .utf8) else { return }
            try data.write(to: signalFileURL, options: .atomic)
        } catch {
            companionRuntimeSignalLog.warning("Failed to write companion runtime signal", detail: "\(error)")
        }
    }

    private static func ensureSignalFileExists(seedReason: String? = nil) throws {
        let directoryURL = signalFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        guard !FileManager.default.fileExists(atPath: signalFileURL.path) else { return }

        let payload = "at=\(ISO8601DateFormatter().string(from: Date()))\nreason=\(seedReason ?? "seed")\n"
        guard let data = payload.data(using: .utf8) else { return }
        try data.write(to: signalFileURL, options: .atomic)
    }
}

// MARK: - Shared Types

public struct ServiceProcessInfo: Identifiable, Equatable {
    public let id = UUID()
    public let pid: Int32
    public let name: String
    public let environment: TalkieEnvironment?
    public let isDaemon: Bool
    public let bundlePath: String?

    public var modeDescription: String {
        isDaemon ? "Daemon" : "Xcode/Direct"
    }

    public var xpcServiceName: String? {
        guard let env = environment else { return nil }
        switch name {
        case "TalkieEngine": return env.liveXPCService
        case "TalkieAgent": return env.liveXPCService
        case "TalkieSync": return env.syncXPCService
        default: return nil
        }
    }

    /// Alias for backwards compatibility
    public var xpcService: String? { xpcServiceName }
}

/// Info about a launch agent plist
public struct LaunchAgentInfo: Identifiable {
    public var id: String { label }
    public let label: String
    public let displayName: String
    public let bundleId: String
    public let plistPath: URL
    public let isInstalled: Bool
    public let isLoaded: Bool

    public var statusDescription: String {
        if !isInstalled { return "Not Installed" }
        return isLoaded ? "Loaded" : "Installed (Not Loaded)"
    }

    public var statusColor: String {
        if !isInstalled { return "gray" }
        return isLoaded ? "green" : "orange"
    }
}

public struct ServiceDebugInfo {
    public let serviceName: String
    public let processId: pid_t?
    public let environment: TalkieEnvironment?
    public let isXPCConnected: Bool
    public let xpcServiceName: String?
    public let bundleId: String?
}

public enum AgentAccessibilityPermissionRequestResult: Equatable, Sendable {
    case granted
    case waitingForUserAction
    case agentUnavailable
}

// MARK: - Service Manager

@MainActor
@Observable
public final class ServiceManager {
    public static let shared = ServiceManager()

    // ─────────────────────────────────────────────────────────────────────────
    // Service State
    // ─────────────────────────────────────────────────────────────────────────

    public let live = AgentServiceState()
    public var agent: AgentServiceState { live }
    public let engine = EngineServiceState()
    public let sync = HelperProcessState(kind: .sync)

    // ─────────────────────────────────────────────────────────────────────────
    // Dev: Multi-process discovery (for DevControlPanel)
    // ─────────────────────────────────────────────────────────────────────────

    public private(set) var allLiveProcesses: [ServiceProcessInfo] = []
    public private(set) var allEngineProcesses: [ServiceProcessInfo] = []
    public private(set) var allSyncProcesses: [ServiceProcessInfo] = []

    /// Aliases for DevControlPanel compatibility
    public var liveProcesses: [ServiceProcessInfo] { allLiveProcesses }
    public var engineProcesses: [ServiceProcessInfo] { allEngineProcesses }
    public var syncProcesses: [ServiceProcessInfo] { allSyncProcesses }

    // ─────────────────────────────────────────────────────────────────────────
    // Helper Status (backwards compatibility with AppLauncher)
    // ─────────────────────────────────────────────────────────────────────────

    /// Helper status for UI display
    public enum HelperStatus: String {
        case unknown = "Unknown"
        case notFound = "Not Found"
        case notRegistered = "Not Registered"
        case enabled = "Enabled"
        case requiresApproval = "Requires Approval"
        case running = "Running"
        case notRunning = "Not Running"

        var isHealthy: Bool {
            self == .enabled || self == .running
        }

        var icon: String {
            switch self {
            case .running: return "checkmark.circle.fill"
            case .enabled: return "checkmark.circle"
            case .requiresApproval: return "exclamationmark.circle.fill"
            case .notRegistered, .notFound: return "xmark.circle"
            case .notRunning: return "pause.circle"
            case .unknown: return "questionmark.circle"
            }
        }
    }

    /// Static bundle ID accessors
    public static var engineBundleId: String { TalkieEnvironment.current.liveBundleId }
    public static var liveBundleId: String { TalkieEnvironment.current.liveBundleId }
    public static var syncBundleId: String { TalkieEnvironment.current.syncBundleId }

    /// Engine status
    public var engineStatus: HelperStatus {
        liveStatus
    }

    /// Live status
    public var liveStatus: HelperStatus {
        if live.isRunning { return .running }
        let env = effectiveHelperEnvironment
        if isLaunchAgentInstalled(label: TalkieHelper.agent.launchdLabel(for: env)) {
            return .notRunning
        }
        return .notRegistered
    }

    /// Sync status
    public var syncStatus: HelperStatus {
        if sync.isRunning { return .running }
        let env = effectiveHelperEnvironment
        if isLaunchAgentInstalled(label: TalkieHelper.sync.launchdLabel(for: env)) {
            return .notRunning
        }
        return .notRegistered
    }

    /// Check if a launch agent plist is installed in ~/Library/LaunchAgents
    private func isLaunchAgentInstalled(label: String) -> Bool {
        let plistPath = userLaunchAgentsDir.appendingPathComponent("\(label).plist")
        return FileManager.default.fileExists(atPath: plistPath.path)
    }

    /// Register Engine as login item (alias)
    public func registerEngine() {
        registerLiveLoginItem()
    }

    /// Register Live as login item (alias)
    public func registerLive() {
        registerLiveLoginItem()
    }

    /// Unregister Engine (alias)
    public func unregisterEngine() {
        unregisterLiveLoginItem()
    }

    /// Unregister Live (alias)
    public func unregisterLive() {
        unregisterLiveLoginItem()
    }

    /// Register Sync as login item (alias)
    public func registerSync() {
        registerSyncLoginItem()
    }

    /// Unregister Sync (alias)
    public func unregisterSync() {
        unregisterSyncLoginItem()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helper Environment Override
    // ─────────────────────────────────────────────────────────────────────────

    private static let helperEnvKey = "helperEnvironmentOverride"

    /// Override which environment's helpers to launch (nil = use current app environment)
    /// Set to .production to always use prod TalkieAgent/TalkieEngine even from dev Talkie
    public var helperEnvironmentOverride: TalkieEnvironment? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Self.helperEnvKey) else { return nil }
            return TalkieEnvironment(rawValue: raw)
        }
        set {
            if let env = newValue {
                UserDefaults.standard.set(env.rawValue, forKey: Self.helperEnvKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.helperEnvKey)
            }
        }
    }

    /// The effective environment used for launching helpers
    public var effectiveHelperEnvironment: TalkieEnvironment {
        helperEnvironmentOverride ?? TalkieEnvironment.current
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private
    // ─────────────────────────────────────────────────────────────────────────

    private var statusTimer: Timer?
    private var postActionRefreshTask: Task<Void, Never>?
    private let postActionRefreshWindowMS = 45_000
    private let postActionRefreshIntervalMS = 2_000

    /// Guards against duplicate TalkieAgent launches from concurrent code paths
    private var isLaunchingLive = false

    private init() {
        AppMode.guard(.lite, "ServiceManager")

        StartupProfiler.shared.mark("singleton.ServiceManager.start")
        CompanionRuntimeSignal.prepare()

        // Listen for iCloud sync setting changes
        NotificationCenter.default.addObserver(
            forName: .iCloudSyncSettingChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSyncSettingChanged()
        }

        // Listen for helper lifecycle mode changes (always-on/attached/on-demand)
        NotificationCenter.default.addObserver(
            forName: .helperLifecycleModeChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let rawHelper = notification.userInfo?["helper"] as? String,
                let helper = TalkieHelper(rawValue: rawHelper),
                let rawMode = notification.userInfo?["mode"] as? String,
                let mode = HelperLifecycleMode(rawValue: rawMode)
            else { return }
            Task { @MainActor in
                await self?.applyLifecycleModeChange(helper: helper, mode: mode)
            }
        }

        // React immediately when any Talkie helper launches or terminates
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleId = app.bundleIdentifier,
                  bundleId.hasPrefix("to.talkie.app.") else { return }
            Task { @MainActor in
                self?.refreshStatus()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleId = app.bundleIdentifier,
                  bundleId.hasPrefix("to.talkie.app.") else { return }
            Task { @MainActor in
                self?.refreshStatus()
            }
        }

        StartupProfiler.shared.mark("singleton.ServiceManager.done")
    }

    /// Apply a lifecycle mode change to a helper.
    ///
    /// - `.alwaysOn` / `.attached` → regenerate the dev plist with the new KeepAlive
    ///   value and bootstrap it. If the helper wasn't running, it starts; if it was
    ///   running under the old plist, `launch` booth out and re-installs first.
    /// - `.onDemand` → bootout the running helper and remove the plist so launchd
    ///   won't bring it back. User starts it manually from here on.
    private func applyLifecycleModeChange(helper: TalkieHelper, mode: HelperLifecycleMode) async {
        logger.info("Applying lifecycle mode \(mode.rawValue) to \(helper.displayName)")

        switch mode {
        case .alwaysOn, .attached:
            // Reinstall with the new KeepAlive and make sure it's up.
            try? await HelperLaunchManager.shared.launch(helper, mode: mode)
        case .onDemand:
            // Tear it down — user owns the lifecycle now.
            let env = effectiveHelperEnvironment
            let label = helper.launchdLabel(for: env)
            await HelperLaunchManager.shared.bootout(label: label)
            // Also remove the plist so launchd forgets the job entirely.
            let plist = HelperLaunchManager.shared.userLaunchAgentsDir
                .appendingPathComponent("\(label).plist")
            if FileManager.default.fileExists(atPath: plist.path) {
                try? FileManager.default.removeItem(at: plist)
                logger.info("Removed \(label).plist (on-demand mode)")
            }
        }

        schedulePostActionStatusRefresh(reason: "lifecycle mode change")
    }

    /// Handle iCloud sync setting toggle
    private func handleSyncSettingChanged() {
        let enabled = SettingsManager.shared.iCloudSyncEnabled
        logger.info("iCloud sync setting changed: \(enabled)")

        if enabled {
            // User enabled sync - register and launch TalkieSync
            registerSync()
            if !sync.isRunning {
                launchSync()
            }
        } else {
            // User disabled sync - stop and unregister TalkieSync
            if sync.isRunning {
                terminateSync()
            }
            unregisterSync()
        }
    }

    // MARK: - Lifecycle Actions

    /// Ensure helper apps are running (called at app launch)
    ///
    /// Async in dev: awaits HelperLaunchManager so the Agent's XPC listener
    /// is ready before the caller starts XPC monitoring.
    public func ensureHelpersRunning() async {
        refreshStatus()
        cleanupLegacyEngineLaunchAgents()

        let env = effectiveHelperEnvironment
        let isProduction = env == .production
        let iCloudEnabled = SettingsManager.shared.iCloudSyncEnabled
        let shouldAutoStartSync = iCloudEnabled && SettingsManager.shared.syncOnLaunch

        if isProduction {
            // Production: install launch agents to ~/Library/LaunchAgents/ and bootstrap.
            // The embedded engine now lives inside TalkieAgent, so there is no standalone engine helper.
            try? await HelperLaunchManager.shared.launch(.agent, resolvingConflicts: true)
            // Only install sync launch agent if iCloud sync is enabled AND auto-sync is on
            if shouldAutoStartSync {
                try? HelperLaunchManager.shared.installLaunchAgent(for: .sync)
            }
        } else {
            // Dev: await Agent launch so XPC monitoring starts after the new listener is ready.
            isLaunchingLive = true
            try? await HelperLaunchManager.shared.launch(.agent)
            try? await Task.sleep(for: .milliseconds(500))
            isLaunchingLive = false
            schedulePostActionStatusRefresh(reason: "launch live")

            // Sync: use HelperLaunchManager (ensures MachServices are registered in dev too)
            if shouldAutoStartSync && !sync.isRunning {
                try? await Task.sleep(for: .milliseconds(500))
                self.launchSync()
            }
        }
    }

    /// Bootout helper launch agents on quit.
    ///
    /// Helpers with lifecycle mode `.attached` are torn down (they're scoped to
    /// Talkie's lifetime). `.alwaysOn` helpers survive via launchd KeepAlive.
    /// `.onDemand` helpers are left alone — user is in charge of them.
    /// Runs synchronously — safe to call from applicationWillTerminate.
    public func bootoutHelpers() {
        let uid = getuid()
        let env = effectiveHelperEnvironment
        let settings = SettingsManager.shared
        let helpers = TalkieHelper.allCases.filter { settings.lifecycleMode(for: $0) == .attached }

        for helper in helpers {
            let label = helper.launchdLabel(for: env)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["bootout", "gui/\(uid)/\(label)"]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
                task.waitUntilExit()
                logger.info("[ServiceManager] Booted out \(label) on quit (attached)")
            } catch {
                // Best-effort — don't block quit
            }
        }

        cleanupLegacyEngineLaunchAgents()
    }

    // MARK: - Classic Launch Agent Management

    /// Path to ~/Library/LaunchAgents
    private var userLaunchAgentsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }

    /// Public accessor for launch agents directory
    public var launchAgentsDirectory: URL { userLaunchAgentsDir }

    /// Get info about all Talkie launch agents
    public var launchAgentInfos: [LaunchAgentInfo] {
        let env = effectiveHelperEnvironment
        let agents = [
            (TalkieHelper.agent.launchdLabel(for: env), "TalkieAgent", env.bundleId(for: .agent)),
            (TalkieHelper.sync.launchdLabel(for: env), "TalkieSync", env.bundleId(for: .sync))
        ]

        return agents.map { label, name, bundleId in
            let plistPath = userLaunchAgentsDir.appendingPathComponent("\(label).plist")
            let isInstalled = FileManager.default.fileExists(atPath: plistPath.path)
            let isLoaded = isInstalled ? isAgentLoaded(label: label) : false

            return LaunchAgentInfo(
                label: label,
                displayName: name,
                bundleId: bundleId,
                plistPath: plistPath,
                isInstalled: isInstalled,
                isLoaded: isLoaded
            )
        }
    }

    /// Reveal launch agents directory in Finder
    public func revealLaunchAgentsInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: userLaunchAgentsDir.path)
    }

    /// Reveal a specific plist in Finder
    public func revealPlistInFinder(path: URL) {
        NSWorkspace.shared.selectFile(path.path, inFileViewerRootedAtPath: path.deletingLastPathComponent().path)
    }

    /// Path to bundled plist templates in Resources/LaunchAgents
    private func bundledPlistURL(for label: String) -> URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent("\(label).plist")
    }

    /// Install a launch agent plist to ~/Library/LaunchAgents if needed
    private func installLaunchAgentIfNeeded(label: String) {
        let destPlist = userLaunchAgentsDir.appendingPathComponent("\(label).plist")

        // Check if already installed and running
        if FileManager.default.fileExists(atPath: destPlist.path) {
            // Plist exists - check if agent is loaded and running
            if isAgentLoaded(label: label) {
                logger.info("[ServiceManager] \(label) already loaded")
                return
            }
            // Plist exists but not loaded - bootstrap it
            bootstrapAgent(label: label, plistPath: destPlist)
            return
        }

        // Need to install plist
        guard let sourcePlist = bundledPlistURL(for: label),
              FileManager.default.fileExists(atPath: sourcePlist.path) else {
            logger.error("[ServiceManager] Bundled plist not found for \(label)")
            return
        }

        do {
            // Ensure ~/Library/LaunchAgents exists
            try FileManager.default.createDirectory(at: userLaunchAgentsDir, withIntermediateDirectories: true)

            // Copy plist to user's LaunchAgents directory
            try FileManager.default.copyItem(at: sourcePlist, to: destPlist)
            logger.info("[ServiceManager] Installed \(label).plist to ~/Library/LaunchAgents/")

            // Bootstrap the agent
            bootstrapAgent(label: label, plistPath: destPlist)
        } catch {
            logger.error("[ServiceManager] Failed to install \(label): \(error.localizedDescription)")
        }
    }

    /// Check if a launch agent is loaded via launchctl
    private func isAgentLoaded(label: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["list", label]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Bootstrap a launch agent via launchctl (async to avoid blocking main thread)
    private func bootstrapAgent(label: String, plistPath: URL) {
        let uid = getuid()
        let plistPathString = plistPath.path

        // Run launchctl operations off the main thread to avoid blocking UI
        Task.detached {
            // First try kickstart (if already registered)
            let kickstart = Process()
            kickstart.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            kickstart.arguments = ["kickstart", "-k", "gui/\(uid)/\(label)"]
            kickstart.standardOutput = FileHandle.nullDevice
            kickstart.standardError = FileHandle.nullDevice

            do {
                try kickstart.run()
                kickstart.waitUntilExit()
                if kickstart.terminationStatus == 0 {
                    logger.info("[ServiceManager] Kickstarted \(label)")
                    await MainActor.run { ServiceManager.shared.schedulePostActionStatusRefresh(reason: "kickstart \(label)") }
                    return
                }
            } catch {
                // Continue to bootstrap
            }

            // Bootstrap the agent
            let bootstrap = Process()
            bootstrap.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            bootstrap.arguments = ["bootstrap", "gui/\(uid)", plistPathString]
            bootstrap.standardOutput = FileHandle.nullDevice
            bootstrap.standardError = FileHandle.nullDevice

            do {
                try bootstrap.run()
                bootstrap.waitUntilExit()
                if bootstrap.terminationStatus == 0 {
                    logger.info("[ServiceManager] Bootstrapped \(label)")
                } else {
                    logger.warning("[ServiceManager] Bootstrap returned \(bootstrap.terminationStatus) for \(label)")
                }
            } catch {
                logger.error("[ServiceManager] Failed to bootstrap \(label): \(error.localizedDescription)")
            }

            await MainActor.run { ServiceManager.shared.schedulePostActionStatusRefresh(reason: "bootstrap \(label)") }
        }
    }

    /// Uninstall a launch agent from ~/Library/LaunchAgents (async to avoid blocking main thread)
    private func uninstallLaunchAgent(label: String) {
        let uid = getuid()
        let destPlist = userLaunchAgentsDir.appendingPathComponent("\(label).plist")
        let destPlistPath = destPlist.path

        // Run launchctl operations off the main thread to avoid blocking UI
        Task.detached {
            // Bootout the agent first
            let bootout = Process()
            bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            bootout.arguments = ["bootout", "gui/\(uid)/\(label)"]
            bootout.standardOutput = FileHandle.nullDevice
            bootout.standardError = FileHandle.nullDevice

            do {
                try bootout.run()
                bootout.waitUntilExit()
                logger.info("[ServiceManager] Booted out \(label)")
            } catch {
                logger.warning("[ServiceManager] Bootout failed for \(label): \(error.localizedDescription)")
            }

            // Remove the plist file
            if FileManager.default.fileExists(atPath: destPlistPath) {
                do {
                    try FileManager.default.removeItem(atPath: destPlistPath)
                    logger.info("[ServiceManager] Removed \(label).plist")
                } catch {
                    logger.error("[ServiceManager] Failed to remove plist: \(error.localizedDescription)")
                }
            }

            await MainActor.run { ServiceManager.shared.schedulePostActionStatusRefresh(reason: "uninstall \(label)") }
        }
    }

    /// Remove any legacy standalone TalkieEngine launch agents now that engine lifetime is tied to TalkieAgent.
    private func cleanupLegacyEngineLaunchAgents() {
        for env in TalkieEnvironment.allCases {
            let label = TalkieHelper.engine.launchdLabel(for: env)
            let plistPath = userLaunchAgentsDir.appendingPathComponent("\(label).plist")
            if FileManager.default.fileExists(atPath: plistPath.path) || isAgentLoaded(label: label) {
                uninstallLaunchAgent(label: label)
            }
        }
    }

    /// Launch TalkieAgent
    ///
    /// For production: Uses launchctl kickstart to ensure MachServices are registered
    /// For dev: Falls back to NSWorkspace.openApplication()
    public func launchLive(forceRefreshInDev: Bool = false, resolvingConflicts: Bool = false) {
        let env = effectiveHelperEnvironment
        let shouldRefresh = env != .production && forceRefreshInDev

        guard (!live.isRunning || shouldRefresh || resolvingConflicts), !isLaunchingLive else {
            logger.info("[ServiceManager] Live already running or launch in progress")
            return
        }
        isLaunchingLive = true

        // Safety timeout: reset flag after 10s in case launch silently fails
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            if let self, self.isLaunchingLive {
                self.isLaunchingLive = false
                logger.info("[ServiceManager] Live launch guard timed out — reset")
            }
        }

        logger.info("[ServiceManager] \(shouldRefresh ? "Refreshing" : "Launching") Live (\(env.displayName))...")

        if shouldRefresh, let pid = live.processId {
            _ = terminateProcess(pid: pid)
        }

        if resolvingConflicts {
            Task {
                do {
                    try await HelperLaunchManager.shared.launch(.agent, resolvingConflicts: true)
                } catch {
                    logger.error("[ServiceManager] Failed to launch Agent with conflict resolution: \(error.localizedDescription)")
                }
            }
        } else if env == .production {
            // Production: kickstart via launchd so MachServices are registered
            let label = TalkieHelper.agent.launchdLabel(for: env)
            let destPlist = userLaunchAgentsDir.appendingPathComponent("\(label).plist")
            if FileManager.default.fileExists(atPath: destPlist.path) {
                bootstrapAgent(label: label, plistPath: destPlist)
            } else {
                // Not installed yet - install and bootstrap
                installLaunchAgentIfNeeded(label: label)
            }
        } else {
            // Dev/staging: regenerate the launch agent against the stable dev install.
            Task {
                try? await HelperLaunchManager.shared.launch(.agent, resolvingConflicts: true)
            }
        }

        schedulePostActionStatusRefresh(reason: "launch live")
    }

    /// Launch and connect to the targeted TalkieAgent, then ask that process for microphone permission.
    ///
    /// This intentionally requests through Agent XPC so TCC attributes the prompt to
    /// the selected helper environment's app bundle and executable path, not Talkie.app.
    public func requestAgentMicrophonePermission() async -> Bool? {
        let env = effectiveHelperEnvironment
        let bundleId = TalkieHelper.agent.bundleId(for: env)
        let xpcService = TalkieHelper.agent.xpcServiceName(for: env)

        logger.info(
            "[Permissions] Preparing Agent microphone permission request",
            detail: "env=\(env.displayName), bundle=\(bundleId), xpc=\(xpcService)"
        )

        refreshStatus()
        live.startXPCMonitoring(autoConnect: false)

        if !live.isXPCConnected {
            launchLive(resolvingConflicts: true)

            for attempt in 1...8 {
                await live.xpcManager?.connect()
                if live.isXPCConnected {
                    logger.info("[Permissions] Agent XPC connected for microphone request", detail: "attempt=\(attempt)")
                    break
                }

                try? await Task.sleep(for: .milliseconds(500))
            }
        }

        guard live.isXPCConnected else {
            logger.warning(
                "[Permissions] Agent microphone request could not connect to target",
                detail: "env=\(env.displayName), bundle=\(bundleId), xpc=\(xpcService)"
            )
            return nil
        }

        let granted = await live.requestMicrophonePermission()
        live.refreshPermissions()

        if let granted {
            logger.info("[Permissions] Agent microphone request completed", detail: "granted=\(granted), bundle=\(bundleId)")
        } else {
            logger.warning("[Permissions] Agent microphone request returned no result", detail: "bundle=\(bundleId)")
        }

        return granted
    }

    /// Launch and connect to the targeted TalkieAgent, then check Accessibility permission.
    ///
    /// Accessibility setup is completed through the install assistant so users can add
    /// the exact app bundle in System Settings without an extra system prompt blocking
    /// the guided drag flow.
    public func requestAgentAccessibilityPermission() async -> AgentAccessibilityPermissionRequestResult {
        let env = effectiveHelperEnvironment
        let bundleId = TalkieHelper.agent.bundleId(for: env)
        let xpcService = TalkieHelper.agent.xpcServiceName(for: env)

        logger.info(
            "[Permissions] Preparing Agent accessibility permission request",
            detail: "env=\(env.displayName), bundle=\(bundleId), xpc=\(xpcService)"
        )

        refreshStatus()
        live.startXPCMonitoring(autoConnect: false)

        if !live.isXPCConnected {
            launchLive(resolvingConflicts: true)

            for attempt in 1...8 {
                await live.xpcManager?.connect()
                if live.isXPCConnected {
                    logger.info("[Permissions] Agent XPC connected for accessibility request", detail: "attempt=\(attempt)")
                    break
                }

                try? await Task.sleep(for: .milliseconds(500))
            }
        }

        guard live.isXPCConnected else {
            logger.warning(
                "[Permissions] Agent accessibility request could not connect to target",
                detail: "env=\(env.displayName), bundle=\(bundleId), xpc=\(xpcService)"
            )
            return .agentUnavailable
        }

        let refreshed = await live.refreshPermissionsNow()

        if refreshed?.accessibility == true {
            logger.info("[Permissions] Agent accessibility request completed", detail: "granted=true, bundle=\(bundleId)")
            return .granted
        }

        if refreshed == nil {
            logger.warning("[Permissions] Agent accessibility request returned no result", detail: "bundle=\(bundleId)")
            return .agentUnavailable
        }

        logger.info(
            "[Permissions] Agent accessibility request is waiting for user action",
            detail: "bundle=\(bundleId)"
        )
        return .waitingForUserAction
    }

    /// Launch TalkieEngine
    public func launchEngine() {
        logger.info("[ServiceManager] Launching embedded engine by starting TalkieAgent")
        launchLive(resolvingConflicts: true)
    }

    /// Open a helper app to a specific route, launching it first if needed.
    public func openHelperRoute(_ helper: TalkieHelper, route: String, activates: Bool = true) {
        // The embedded engine now lives inside TalkieAgent, so its dashboards and traces
        // should resolve through the agent helper boundary.
        let resolvedHelper: TalkieHelper = helper == .engine ? .agent : helper
        let env = effectiveHelperEnvironment
        let bundleId = env.bundleId(for: resolvedHelper)
        let appName = resolvedHelper.appName

        guard let url = URL(string: "\(resolvedHelper.urlScheme(for: env))://\(route)") else {
            logger.error("[ServiceManager] Invalid helper URL for \(appName): \(route)")
            return
        }

        if NSWorkspace.shared.open(url) {
            return
        }

        logger.warning("[ServiceManager] Deep link failed for \(appName), launching helper directly")

        guard let appURL = findHelperAppURL(bundleId: bundleId, appName: appName) else {
            logger.error("[ServiceManager] App not found: \(appName)")
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = activates
        config.addsToRecentItems = false

        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { [weak self] _, error in
            Task { @MainActor in
                if let error {
                    logger.error("[ServiceManager] Failed to launch \(appName): \(error.localizedDescription)")
                    return
                }

                self?.schedulePostActionStatusRefresh(reason: "open \(appName) route")

                // Give Launch Services a moment to register the app's URL handler.
                try? await Task.sleep(for: .milliseconds(700))
                _ = NSWorkspace.shared.open(url)
            }
        }
    }

    /// Launch TalkieSync.
    ///
    /// In dev/staging, `forceRefreshInDev` relaunches even when already running.
    /// This self-heals stale launch-agent state and keeps helper wiring aligned
    /// with the current app build.
    public func launchSync(forceRefreshInDev: Bool = false) {
        let env = effectiveHelperEnvironment

        if env != .production {
            if sync.isRunning && !forceRefreshInDev {
                logger.info("[ServiceManager] Sync already running")
                return
            }
            logger.info("[ServiceManager] \(self.sync.isRunning ? "Refreshing" : "Launching") Sync (\(env.displayName))...")
            Task {
                try? await HelperLaunchManager.shared.launch(.sync, resolvingConflicts: true)
            }
            schedulePostActionStatusRefresh(reason: "launch sync")
            return
        }

        guard !sync.isRunning else {
            logger.info("[ServiceManager] Sync already running")
            return
        }

        Task {
            try? await HelperLaunchManager.shared.launch(.sync, resolvingConflicts: true)
        }
        schedulePostActionStatusRefresh(reason: "launch sync")
    }

    /// Terminate TalkieAgent
    public func terminateLive() {
        guard let pid = live.processId else { return }
        logger.info("[ServiceManager] Terminating Live (PID: \(pid))")
        terminateProcess(pid: pid)
        schedulePostActionStatusRefresh(reason: "terminate live")
    }

    /// Terminate TalkieEngine
    public func terminateEngine() {
        logger.info("[ServiceManager] Terminating embedded engine by stopping TalkieAgent")
        terminateLive()
    }

    /// Terminate TalkieSync
    public func terminateSync() {
        guard let pid = sync.processId else { return }
        HelperLaunchManager.shared.terminate(.sync, pid: pid)
        schedulePostActionStatusRefresh(reason: "terminate sync")
    }

    // MARK: - Login Item / Launch Agent Management

    /// Register TalkieAgent as launch agent (for MachServices + reliable uptime)
    public func registerLiveLoginItem() {
        if effectiveHelperEnvironment == .production {
            installLaunchAgentIfNeeded(label: TalkieHelper.agent.launchdLabel(for: .production))
        } else {
            Task {
                try? await HelperLaunchManager.shared.launch(.agent, resolvingConflicts: true)
            }
        }
        schedulePostActionStatusRefresh(reason: "register live login item")
    }

    /// Register TalkieEngine as launch agent
    public func registerEngineLoginItem() {
        registerLiveLoginItem()
    }

    /// Unregister TalkieAgent from launch agents
    public func unregisterLiveLoginItem() {
        Task {
            await HelperLaunchManager.shared.uninstallLaunchAgent(for: .agent)
        }
        schedulePostActionStatusRefresh(reason: "unregister live login item")
    }

    /// Unregister TalkieEngine from launch agents
    public func unregisterEngineLoginItem() {
        unregisterLiveLoginItem()
    }

    /// Register TalkieSync as launch agent
    public func registerSyncLoginItem() {
        if effectiveHelperEnvironment == .production {
            try? HelperLaunchManager.shared.installLaunchAgent(for: .sync)
        } else {
            Task {
                try? await HelperLaunchManager.shared.launch(.sync, resolvingConflicts: true)
            }
        }
        schedulePostActionStatusRefresh(reason: "register sync login item")
    }

    /// Unregister TalkieSync from launch agents
    public func unregisterSyncLoginItem() {
        Task { await HelperLaunchManager.shared.uninstallLaunchAgent(for: .sync) }
        schedulePostActionStatusRefresh(reason: "unregister sync login item")
    }

    /// Open System Settings to Login Items
    public func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Status Refresh

    /// Refresh all service status
    /// Tracks the PID we last attempted to auto-connect to, preventing
    /// repeated connection attempts to the same unregistered process.
    private var lastAutoConnectPID: pid_t?

    public func refreshStatus() {
        live.refreshProcessState()
        engine.refreshProcessState()
        sync.refreshProcessState()
        // Clear launch-in-progress guard once agent is confirmed running
        if live.isRunning && isLaunchingLive {
            isLaunchingLive = false
        }

        // Auto-connect SyncClient when TalkieSync is detected as running
        // but not yet connected (e.g. after launchctl launch).
        // Only attempt once per detected process (by PID) to avoid spamming
        // connection attempts to Xcode-launched processes without MachServices.
        if sync.isRunning,
           !SyncClient.shared.isConnected,
           !SyncClient.shared.isSyncing,
           let pid = sync.processId,
           pid != lastAutoConnectPID {
            lastAutoConnectPID = pid
            logger.info("[ServiceManager] TalkieSync running (PID \(pid)) but not connected — attempting auto-connect")
            SyncClient.shared.logActivity("TalkieSync detected (PID \(pid)) — auto-connecting...")
            SyncClient.shared.connect()
        } else if !sync.isRunning {
            lastAutoConnectPID = nil
        }
    }

    /// Start periodic status polling
    public func startMonitoring(interval: TimeInterval = 5.0) {
        guard statusTimer == nil else { return }

        refreshStatus()
        live.startXPCMonitoring()

        statusTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }

        logger.info("[ServiceManager] Started monitoring (interval: \(interval)s)")
    }

    /// Stop periodic status polling
    public func stopMonitoring() {
        statusTimer?.invalidate()
        statusTimer = nil
        postActionRefreshTask?.cancel()
        postActionRefreshTask = nil
        logger.info("[ServiceManager] Stopped monitoring")
    }

    // MARK: - Process Discovery (Dev)

    /// Scan for all running Talkie processes (for DevControlPanel)
    public func scanAllProcesses() {
        allLiveProcesses = findProcesses(named: "TalkieAgent")
        allEngineProcesses = findProcesses(named: "TalkieEngine")
        allSyncProcesses = findProcesses(named: "TalkieSync")
    }

    /// Kill a specific process by PID
    public func killProcess(pid: Int32) -> Bool {
        let result = Darwin.kill(pid, SIGTERM)
        Thread.sleep(forTimeInterval: 0.3)

        // Force kill if still running
        if Darwin.kill(pid, 0) == 0 {
            Darwin.kill(pid, SIGKILL)
        }

        schedulePostActionStatusRefresh(reason: "kill process \(pid)")
        scanAllProcesses()
        return result == 0
    }

    /// Alias for scanAllProcesses
    public func scan() {
        scanAllProcesses()
    }

    /// Alias for killProcess
    public func kill(pid: Int32) -> Bool {
        killProcess(pid: pid)
    }

    /// Stop a daemon via launchctl (async to avoid blocking main thread)
    /// Note: Returns immediately, actual stop happens asynchronously
    public func stopDaemon(for process: ServiceProcessInfo) {
        guard process.isDaemon, let env = process.environment else { return }

        let label: String
        switch process.name {
        case "TalkieEngine": label = env.liveBundleId
        case "TalkieAgent": label = env.liveBundleId
        case "TalkieSync": label = env.syncBundleId
        default: return
        }

        let uid = getuid()

        // Run launchctl operations off the main thread
        Task.detached {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["stop", "gui/\(uid)/\(label)"]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus != 0 {
                    logger.warning("[ServiceManager] Stop daemon returned \(task.terminationStatus) for \(label)")
                }
            } catch {
                logger.error("[ServiceManager] Failed to stop daemon: \(error.localizedDescription)")
            }

            try? await Task.sleep(for: .milliseconds(500))
            await MainActor.run {
                let manager = ServiceManager.shared
                manager.scanAllProcesses()
                manager.schedulePostActionStatusRefresh(reason: "stop daemon \(label)")
            }
        }
    }

    /// Restart a daemon via launchctl kickstart -k (async to avoid blocking main thread)
    /// Note: Returns immediately, actual restart happens asynchronously
    public func restartDaemon(for process: ServiceProcessInfo) {
        guard process.isDaemon, let env = process.environment else { return }

        let label: String
        switch process.name {
        case "TalkieEngine": label = env.liveBundleId
        case "TalkieAgent": label = env.liveBundleId
        case "TalkieSync": label = env.syncBundleId
        default: return
        }

        let uid = getuid()

        // Run launchctl operations off the main thread
        Task.detached {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["kickstart", "-k", "gui/\(uid)/\(label)"]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus != 0 {
                    logger.warning("[ServiceManager] Restart daemon returned \(task.terminationStatus) for \(label)")
                }
            } catch {
                logger.error("[ServiceManager] Failed to restart daemon: \(error.localizedDescription)")
            }

            try? await Task.sleep(for: .milliseconds(500))
            await MainActor.run {
                let manager = ServiceManager.shared
                manager.scanAllProcesses()
                manager.schedulePostActionStatusRefresh(reason: "restart daemon \(label)")
            }
        }
    }

    /// Kill all daemon instances of a given service
    /// Note: Returns count of daemon processes found, actual stops happen asynchronously
    public func killAllDaemons(service: String) -> Int {
        let processes: [ServiceProcessInfo]
        switch service {
        case "TalkieEngine": processes = allEngineProcesses
        case "TalkieAgent": processes = allLiveProcesses
        case "TalkieSync": processes = allSyncProcesses
        default: return 0
        }

        var count = 0
        for process in processes where process.isDaemon {
            stopDaemon(for: process)
            count += 1
        }
        return count
    }

    /// Kill all Xcode/direct launch instances of a given service
    public func killAllXcode(service: String) -> Int {
        let processes: [ServiceProcessInfo]
        switch service {
        case "TalkieEngine": processes = allEngineProcesses
        case "TalkieAgent": processes = allLiveProcesses
        case "TalkieSync": processes = allSyncProcesses
        default: return 0
        }

        var killed = 0
        for process in processes where !process.isDaemon {
            if killProcess(pid: process.pid) {
                killed += 1
            }
        }
        return killed
    }

    // MARK: - Private Helpers

    private func launchHelper(bundleId: String, appName: String) {
        // Check if already running by bundle ID to prevent duplicate instances
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        let alive = existing.filter { !$0.isTerminated }
        if !alive.isEmpty {
            logger.info("[ServiceManager] \(appName) already running (bundle: \(bundleId), PIDs: \(alive.map(\.processIdentifier))), skipping launch")
            return
        }

        guard let url = findHelperAppURL(bundleId: bundleId, appName: appName) else {
            logger.error("[ServiceManager] App not found: \(appName)")
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false

        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
            Task { @MainActor in
                if let error = error {
                    logger.error("[ServiceManager] Failed to launch \(appName): \(error.localizedDescription)")
                } else {
                    logger.info("[ServiceManager] Launched \(appName)")
                }
                self?.schedulePostActionStatusRefresh(reason: "launch \(appName)")
            }
        }
    }

    private func findHelperAppURL(bundleId: String, appName: String) -> URL? {
        // 1. Check embedded location (Contents/Library/LoginItems/)
        if let mainBundle = Bundle.main.bundleURL as URL? {
            let embeddedURL = mainBundle
                .appendingPathComponent("Contents/Library/LoginItems")
                .appendingPathComponent(appName)
            if FileManager.default.fileExists(atPath: embeddedURL.path) {
                return embeddedURL
            }
        }

        // 2. Check local debug builds before LaunchServices, which can point at
        // an older registered helper from another checkout or build folder.
        #if DEBUG
        if let debugURL = findDebugBuild(appName: appName) {
            return debugURL
        }
        #endif

        // 3. Check registered applications
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return appURL
        }

        return nil
    }

    private func terminateProcess(pid: Int32) {
        Darwin.kill(pid, SIGTERM)

        // Force kill after 2 seconds if still running
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if Darwin.kill(pid, 0) == 0 {
                logger.warning("[ServiceManager] Force killing PID \(pid)")
                Darwin.kill(pid, SIGKILL)
            }
            self?.refreshStatus()
        }
    }

    private func schedulePostActionStatusRefresh(reason: String) {
        let tickCount = max(1, postActionRefreshWindowMS / postActionRefreshIntervalMS)

        postActionRefreshTask?.cancel()
        refreshStatus()

        logger.info("[ServiceManager] Starting post-action refresh window (\(reason))")

        postActionRefreshTask = Task { [weak self] in
            guard let self else { return }

            defer {
                self.postActionRefreshTask = nil
            }

            for _ in 0..<tickCount {
                try? await Task.sleep(for: .milliseconds(postActionRefreshIntervalMS))
                if Task.isCancelled { return }
                self.refreshStatus()
            }
        }
    }

    private func findDebugBuild(appName: String) -> URL? {
        let executableName = appName.hasSuffix(".app") ? String(appName.dropLast(4)) : appName
        var candidates: [(url: URL, date: Date)] = []
        var seen = Set<String>()
        let env = effectiveHelperEnvironment

        func appendCandidate(_ appURL: URL) {
            guard FileManager.default.fileExists(atPath: appURL.path),
                  seen.insert(appURL.path).inserted else {
                return
            }

            let executableURL = appURL
                .appendingPathComponent("Contents/MacOS")
                .appendingPathComponent(executableName)
            let date = (try? executableURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                ?? (try? appURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                ?? .distantPast
            candidates.append((appURL, date))
        }

        appendCandidate(env.userInstalledAppURL(named: appName))

        if let repoRoot = LocalCheckoutLocator.talkieRepositoryRootURL(compileTimeFilePath: #filePath) {
            let repoBuildRoots = [
                repoRoot
                    .appendingPathComponent("build")
                    .appendingPathComponent("macos"),
                repoRoot.appendingPathComponent("build")
            ]

            for buildRoot in repoBuildRoots {
                appendCandidate(
                    buildRoot
                        .appendingPathComponent(executableName)
                        .appendingPathComponent("Build/Products/Debug")
                        .appendingPathComponent(appName)
                )
            }
        }

        if !allowsDerivedDataFallback {
            return candidates.max(by: { $0.date < $1.date })?.url
        }

        let derivedDataPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")

        guard let enumerator = FileManager.default.enumerator(
            at: derivedDataPath,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let fileURL as URL in enumerator where
            fileURL.lastPathComponent == appName && fileURL.path.contains("Build/Products/Debug") {
            appendCandidate(fileURL)
        }

        return candidates.max(by: { $0.date < $1.date })?.url
    }

    private var allowsDerivedDataFallback: Bool {
        ProcessInfo.processInfo.environment["TALKIE_ALLOW_DERIVEDDATA_FALLBACK"] == "1"
            || UserDefaults.standard.bool(forKey: "ServiceManager.allowDerivedDataFallback")
    }

    private func findProcesses(named processName: String) -> [ServiceProcessInfo] {
        var results: [ServiceProcessInfo] = []

        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }

        var pidBuffer = [Int32](repeating: 0, count: Int(count) * 2)
        let actualCount = proc_listallpids(&pidBuffer, Int32(pidBuffer.count * MemoryLayout<Int32>.size))
        guard actualCount > 0 else { return [] }

        for i in 0..<Int(actualCount) {
            let pid = pidBuffer[i]
            guard pid > 0 else { continue }

            var name = [CChar](repeating: 0, count: 1024)
            let result = proc_name(pid, &name, UInt32(name.count))

            if result > 0 {
                let procName = String(cString: name)
                if procName == processName {
                    let bundlePath = getBundlePath(for: pid)
                    let environment = detectEnvironment(from: bundlePath)
                    let isDaemon = checkIfDaemon(pid: pid)

                    results.append(ServiceProcessInfo(
                        pid: pid,
                        name: procName,
                        environment: environment,
                        isDaemon: isDaemon,
                        bundlePath: bundlePath
                    ))
                }
            }
        }

        return results.sorted { $0.pid < $1.pid }
    }

    private func getBundlePath(for pid: Int32) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let result = proc_pidpath(pid, &pathBuffer, UInt32(4096))
        guard result > 0 else { return nil }
        return String(cString: pathBuffer)
    }

    private func detectEnvironment(from path: String?) -> TalkieEnvironment? {
        guard let path = path else { return nil }

        if path.contains(".dev.app") || path.contains("/Debug/") || path.contains("DerivedData") {
            return .dev
        }
        return .production
    }

    private func checkIfDaemon(pid: Int32) -> Bool {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, ptr, Int32(size))
        }
        guard result == size else { return false }
        return info.pbi_ppid == 1
    }
}

// MARK: - Live Service State

@MainActor
@Observable
public final class AgentServiceState: NSObject, TalkieAgentStateObserverProtocol {
    // ─── Core State ───
    public private(set) var isRunning: Bool = false
    public private(set) var state: LiveState = .idle
    public private(set) var elapsedTime: TimeInterval = 0
    public var isRecording: Bool { state == .listening || state == .transcribing }

    // ─── Process Info ───
    public private(set) var processId: pid_t?
    public private(set) var environment: TalkieEnvironment?
    public private(set) var bundlePath: String?
    public private(set) var launchedAt: Date?
    public private(set) var uptime: TimeInterval = 0

    /// Backwards compatibility alias
    public var connectedMode: TalkieEnvironment? { environment }

    // ─── XPC Connection ───
    public private(set) var isXPCConnected: Bool = false
    public private(set) var audioLevel: Float = 0

    // ─── Permissions (queried via XPC) ───
    public private(set) var hasMicrophonePermission: Bool?
    public private(set) var hasAccessibilityPermission: Bool?
    public private(set) var hasScreenRecordingPermission: Bool?
    public private(set) var lastPermissionCheck: Date?

    /// Refresh agent permissions via XPC. Call on app activation or when permissions may have changed.
    public func refreshPermissions() {
        Task {
            _ = await refreshPermissionsNow()
        }
    }

    /// Refresh agent permissions via XPC and wait for the current snapshot.
    @discardableResult
    public func refreshPermissionsNow() async -> (microphone: Bool, accessibility: Bool, screenRecording: Bool)? {
        guard isXPCConnected else { return nil }
        guard let perms = await checkPermissions() else { return nil }

        hasMicrophonePermission = perms.microphone
        hasAccessibilityPermission = perms.accessibility
        hasScreenRecordingPermission = perms.screenRecording
        lastPermissionCheck = Date()

        return perms
    }

    // ─── Private ───
    private(set) var xpcManager: XPCServiceManager<TalkieAgentXPCServiceProtocol>?
    private var cancellables = Set<AnyCancellable>()
    private var distributedObservers: [NSObjectProtocol] = []
    private var dictationRefreshDebounceTask: Task<Void, Never>?
    private var isDictationRefreshInFlight = false
    private var hasPendingDictationRefresh = false
    private let dictationRefreshDebounceMS = 180

    public override init() {
        super.init()
    }

    // MARK: - Actions

    /// Toggle recording in TalkieAgent
    public func toggleRecording() {
        guard let service = xpcManager?.remoteObjectProxy(errorHandler: { error in
            logger.error("[Agent] Toggle error: \(error.localizedDescription)")
        }) else {
            logger.warning("[Agent] Cannot toggle - not connected")
            return
        }

        service.toggleRecording { success in
            if success {
                logger.info("[Agent] Toggle request sent")
            }
        }
    }

    /// Show TalkieAgent's settings window via XPC
    ///
    /// Uses XPC instead of URL schemes to ensure the correct TalkieAgent instance
    /// (matching the current environment) opens its settings.
    public func showSettings() {
        guard let service = xpcManager?.remoteObjectProxy(errorHandler: { error in
            logger.error("[Agent] showSettings error: \(error.localizedDescription)")
        }) else {
            logger.warning("[Agent] Cannot show settings - not connected")
            return
        }

        service.showSettings { success in
            if success {
                logger.info("[Agent] Settings window opened")
            } else {
                logger.warning("[Agent] Failed to open settings window")
            }
        }
    }

    /// Paste text via TalkieAgent (uses robust AX insertion with clipboard fallback)
    /// - Parameters:
    ///   - text: The text to insert
    ///   - bundleID: Target app bundle ID (nil = frontmost app)
    ///   - completion: Called with success status
    public func pasteText(_ text: String, toAppWithBundleID bundleID: String?, completion: @escaping (Bool) -> Void) {
        guard let service = xpcManager?.remoteObjectProxy(errorHandler: { error in
            logger.error("[Agent] Paste error: \(error.localizedDescription)")
            completion(false)
        }) else {
            logger.warning("[Agent] Cannot paste - not connected to Talkie Agent")
            completion(false)
            return
        }

        service.pasteText(text, toAppWithBundleID: bundleID) { success in
            if success {
                logger.info("[Agent] Paste succeeded")
            } else {
                logger.warning("[Agent] Paste failed")
            }
            completion(success)
        }
    }

    /// Fire-and-forget side channel for screenshots captured while Agent is actively
    /// listening. The tray still owns its normal file, but Agent gets an immediate
    /// recording-scoped copy for post-transcription insertion.
    public func recordLiveScreenshot(
        data: Data,
        capturedAt: Date,
        captureMode: String,
        width: Int,
        height: Int,
        windowTitle: String?,
        appName: String?,
        displayName: String?
    ) {
        guard isRecording else { return }
        guard let service = xpcManager?.remoteObjectProxy(errorHandler: { error in
            logger.debug("[Agent] recordLiveScreenshot XPC error: \(error.localizedDescription)")
        }) else {
            logger.debug("[Agent] Skipping live screenshot side channel - not connected")
            return
        }

        service.recordLiveScreenshot(
            imageData: data,
            capturedAt: capturedAt.timeIntervalSince1970,
            captureMode: captureMode,
            width: width,
            height: height,
            windowTitle: windowTitle,
            appName: appName,
            displayName: displayName
        ) { success in
            if success {
                logger.info("[Agent] Recorded live screenshot for active dictation")
            }
        }
    }

    /// True when agent is connected but missing critical permissions.
    public var hasCriticalPermissionIssue: Bool {
        guard isXPCConnected else { return false }
        return hasMicrophonePermission == false || hasAccessibilityPermission == false
    }

    /// Human-readable list of missing permissions for UI display.
    public var missingPermissions: [String] {
        var missing: [String] = []
        if hasMicrophonePermission == false { missing.append("Microphone") }
        if hasAccessibilityPermission == false { missing.append("Accessibility") }
        return missing
    }

    // MARK: - Diagnostics

    /// Query Agent for status of all registered Carbon hotkeys
    public func getHotkeyStatus() async -> [HotKeyStatusInfo] {
        guard let proxy = xpcManager?.remoteObjectProxy(errorHandler: { error in
            logger.debug("[Agent] getHotkeyStatus XPC error: \(error.localizedDescription)")
        }) else { return [] }

        return await withCheckedContinuation { continuation in
            proxy.getHotkeyStatus { data in
                guard let data, let statuses = try? JSONDecoder().decode([HotKeyStatusInfo].self, from: data) else {
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: statuses)
            }
        }
    }

    // MARK: - Reconnect

    /// Force reconnect - drops current XPC connection and rescans for agent
    public func reconnect() {
        logger.info("[Agent] Force reconnecting...")
        guard let xpcManager else {
            startXPCMonitoring(autoConnect: true)
            return
        }

        xpcManager.disconnect()

        Task {
            try? await Task.sleep(for: .milliseconds(200))
            await xpcManager.connect()
        }
    }

    // MARK: - XPC Monitoring

    /// Start monitoring TalkieAgent XPC connection (backwards compatibility)
    public func startMonitoring() {
        startXPCMonitoring()
    }

    func startXPCMonitoring(autoConnect: Bool = false) {
        startDistributedNotificationMonitoring()
        if let existingManager = xpcManager {
            if autoConnect && !existingManager.isConnected {
                Task {
                    await existingManager.connect()
                }
            }
            return
        }

        xpcManager = XPCServiceManager<TalkieAgentXPCServiceProtocol>(
            serviceNameProvider: { env in env.liveXPCService },
            interfaceProvider: { NSXPCInterface(with: TalkieAgentXPCServiceProtocol.self) },
            exportedInterface: NSXPCInterface(with: TalkieAgentStateObserverProtocol.self),
            exportedObject: self
        )
        xpcManager?.preferredEnvironmentProvider = { ServiceManager.shared.effectiveHelperEnvironment }
        xpcManager?.allowsCrossEnvironmentFallback = false

        xpcManager?.connectionVerifier = { proxy in
            await withCheckedContinuation { continuation in
                var resumed = false

                proxy.getCurrentState { _, _, _ in
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: true)
                }

                DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: false)
                }
            }
        }

        // Auto-launch TalkieAgent if XPC connection fails
        xpcManager?.autoLaunchHandler = {
            logger.info("[Agent] Auto-launching Talkie Agent...")
            ServiceManager.shared.launchLive(resolvingConflicts: true)
        }

        xpcManager?.$connectionInfo
            .map(\.isConnected)
            .removeDuplicates()
            .sink { [weak self] connected in
                self?.isXPCConnected = connected
                if connected {
                    self?.environment = self?.xpcManager?.connectedMode
                    self?.registerAsObserver()
                    logger.info("[Agent] XPC connected")
                } else {
                    logger.info("[Agent] XPC disconnected")
                }
            }
            .store(in: &cancellables)

        if autoConnect {
            Task {
                await xpcManager?.connect()
            }
        }
    }

    /// Trigger XPC connection to TalkieAgent.
    /// Call after ensureHelpersRunning so the Agent's listener is ready.
    func connectXPC() {
        guard let xpcManager else {
            startXPCMonitoring(autoConnect: true)
            return
        }

        Task {
            await xpcManager.connect()
        }
    }

    private func startDistributedNotificationMonitoring() {
        guard distributedObservers.isEmpty else { return }

        let center = DistributedNotificationCenter.default()
        let queue = OperationQueue.main
        let prefix = "to.talkie.app.agent"

        func observe(_ suffix: String, _ handler: @escaping (Notification) -> Void) {
            let name = Notification.Name("\(prefix).\(suffix)")
            let token = center.addObserver(forName: name, object: nil, queue: queue, using: handler)
            distributedObservers.append(token)
        }

        observe("recording.started") { [weak self] _ in
            self?.updateFromNotification(state: .listening)
        }
        observe("recording.stopped") { [weak self] _ in
            self?.updateFromNotification(state: .idle)
        }
        observe("recording.cancelled") { [weak self] _ in
            self?.updateFromNotification(state: .idle)
        }
        observe("transcribing") { [weak self] _ in
            self?.updateFromNotification(state: .transcribing)
        }
        observe("routing") { [weak self] _ in
            self?.updateFromNotification(state: .routing)
        }
        observe("dictation.new") { [weak self] _ in
            self?.scheduleDictationRefresh(reason: "distributed dictation.new")
        }

        logger.info("[Agent] Distributed notification monitoring started")
    }

    private func scheduleDictationRefresh(reason: String) {
        dictationRefreshDebounceTask?.cancel()
        dictationRefreshDebounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(dictationRefreshDebounceMS))
            } catch {
                return
            }
            await self.runDictationRefreshPipeline(reason: reason)
        }
    }

    private func runDictationRefreshPipeline(reason: String) async {
        if isDictationRefreshInFlight {
            hasPendingDictationRefresh = true
            return
        }

        isDictationRefreshInFlight = true
        defer { isDictationRefreshInFlight = false }

        let addedCount = await DictationStore.shared.refreshAndWait()
        if addedCount > 0 {
            await RecordingsViewModel.shared.refresh()
        } else {
            logger.debug("[Agent] Skipping recordings refresh (\(reason)): no new dictations")
        }

        if hasPendingDictationRefresh {
            hasPendingDictationRefresh = false
            await runDictationRefreshPipeline(reason: "coalesced follow-up")
        }
    }

    private func registerAsObserver() {
        guard let service = xpcManager?.remoteObjectProxy(errorHandler: { _ in }) else { return }

        service.registerStateObserver { [weak self] success, pid in
            Task { @MainActor in
                if success {
                    self?.processId = pid
                    logger.info("[Agent] Registered (PID: \(pid))")
                }
            }
        }

        service.getCurrentState { [weak self] stateStr, elapsed, pid in
            Task { @MainActor in
                self?.processId = pid
                self?.updateState(stateStr, elapsed)
            }
        }

        // Piggyback permission check on connect — no periodic polling.
        // Permissions rarely change; one check per XPC session is enough.
        service.getPermissions { [weak self] mic, accessibility, screen in
            Task { @MainActor in
                self?.hasMicrophonePermission = mic
                self?.hasAccessibilityPermission = accessibility
                self?.hasScreenRecordingPermission = screen
                self?.lastPermissionCheck = Date()

                if !mic { logger.warning("[Agent] Health: microphone permission MISSING") }
                if !accessibility { logger.warning("[Agent] Health: accessibility permission MISSING") }
            }
        }
    }

    // MARK: - Permission Check

    /// Check TalkieAgent's permissions via XPC
    /// Returns (microphone, accessibility, screenRecording) or nil if not connected
    public func checkPermissions() async -> (microphone: Bool, accessibility: Bool, screenRecording: Bool)? {
        guard let service = xpcManager?.remoteObjectProxy(errorHandler: { _ in }) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            service.getPermissions { mic, accessibility, screen in
                continuation.resume(returning: (mic, accessibility, screen))
            }
        }
    }

    public func requestMicrophonePermission() async -> Bool? {
        guard let service = xpcManager?.remoteObjectProxy(errorHandler: { _ in }) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            service.requestMicrophonePermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    public func requestAccessibilityPermission() async -> Bool? {
        guard let service = xpcManager?.remoteObjectProxy(errorHandler: { _ in }) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            service.requestAccessibilityPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Retranscription

    /// Retranscribe a dictation via TalkieAgent XPC
    /// TalkieAgent owns the unified database, so all writes must go through XPC
    /// - Parameters:
    ///   - dictationId: The UUID string of the dictation
    ///   - modelId: Model identifier (e.g., "parakeet:v3")
    /// - Returns: New transcript text on success
    /// - Throws: Error if retranscription fails
    public func retranscribe(dictationId: String, modelId: String) async throws -> String {
        guard let service = xpcManager?.remoteObjectProxy(errorHandler: { error in
            logger.error("[Agent] Retranscribe XPC error: \(error.localizedDescription)")
        }) else {
            throw RetranscribeError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            service.retranscribe(dictationId: dictationId, modelId: modelId) { newText, error in
                if let error = error {
                    continuation.resume(throwing: RetranscribeError.failed(error))
                } else if let newText = newText {
                    continuation.resume(returning: newText)
                } else {
                    continuation.resume(throwing: RetranscribeError.emptyResult)
                }
            }
        }
    }

    public enum RetranscribeError: LocalizedError {
        case notConnected
        case failed(String)
        case emptyResult

        public var errorDescription: String? {
            switch self {
            case .notConnected:
                return "Not connected to Talkie Agent"
            case .failed(let message):
                return message
            case .emptyResult:
                return "Retranscription returned empty result"
            }
        }
    }

    // MARK: - Process Detection

    /// Refresh process ID by detecting running TalkieAgent (backwards compatibility)
    public func refreshProcessId() {
        refreshProcessState()
    }

    func refreshProcessState() {
        let env = ServiceManager.shared.effectiveHelperEnvironment

        if let runtimeState = TalkieHelperRuntimeStateStore.validatedState(
            for: .agent,
            environment: env
        ) {
            isRunning = true
            processId = runtimeState.processId
            bundlePath = runtimeState.executablePath
            launchedAt = runtimeState.startedAt
            uptime = Date().timeIntervalSince(runtimeState.startedAt)
            return
        }

        // Fallback: detect via NSRunningApplication (e.g. when state file write failed)
        let bundleId = TalkieHelper.agent.bundleId(for: env)
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        if let app = apps.first(where: { !$0.isTerminated }) {
            isRunning = true
            processId = app.processIdentifier
            bundlePath = app.bundleURL?.path
            if launchedAt == nil {
                launchedAt = talkieProcessStartTime(pid: app.processIdentifier) ?? Date()
            }
            if let launched = launchedAt {
                uptime = Date().timeIntervalSince(launched)
            }
            return
        }

        if !isXPCConnected {
            isRunning = false
            processId = nil
            uptime = 0
            launchedAt = nil
            bundlePath = nil
        }
    }

    // MARK: - URL Notification Handler

    /// Update state from URL notification (preferred over XPC)
    public func updateFromNotification(state newState: LiveState, elapsedTime elapsed: TimeInterval = 0) {
        isRunning = true  // We're receiving notifications, so it's running
        self.elapsedTime = elapsed

        if newState != state {
            state = newState
            logger.info("[Agent] State (notification): \(newState.rawValue)")
            CompanionRuntimeSignal.notify(reason: "agent-notification-\(newState.rawValue)")
        }
    }

    // MARK: - TalkieAgentStateObserverProtocol

    nonisolated public func stateDidChange(state stateString: String, elapsedTime: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            self?.updateState(stateString, elapsedTime)
        }
    }

    nonisolated public func dictationWasAdded() {
        Task { @MainActor [weak self] in
            // Coalesce callback + distributed events into one refresh pipeline.
            self?.scheduleDictationRefresh(reason: "xpc dictationWasAdded")
            CompanionRuntimeSignal.notify(reason: "dictation-added")
        }
    }

    nonisolated public func audioLevelDidChange(level: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.audioLevel = level
        }
    }

    nonisolated public func ambientCommandReceived(command: String, duration: TimeInterval, bufferContext: String?) {
        DispatchQueue.main.async { [weak self] in
            self?.handleAmbientCommand(command, duration: duration, bufferContext: bufferContext)
        }
    }

    nonisolated public func voiceNavigationReceived(intent: String, confidence: Float, rawText: String) {
        DispatchQueue.main.async { [weak self] in
            self?.handleVoiceNavigation(intent: intent, confidence: confidence, rawText: rawText)
        }
    }

    nonisolated public func talkieAgentServerStatusDidChange(_ statusJSON: Data) {
        if let status = try? JSONDecoder().decode(TalkieAgentServerStatus.self, from: statusJSON) {
            Task { @MainActor in
                BridgeManager.shared.updateFromAgentStatus(status)
            }
        }
    }

    /// Legacy callback retained for compatibility. Talkie never mutates Agent-owned live tray items.
    nonisolated public func dictationWasPasted(recordingId: String) {}

    // Live tray drains are now Agent-owned. Talkie stays on durable
    // view/edit/save surfaces and no longer serves tray asset fetch callbacks.

    private func handleAmbientCommand(_ command: String, duration: TimeInterval, bufferContext: String?) {
        logger.info("[Agent] Ambient command received: '\(command.prefix(50))...' (\(String(format: "%.1f", duration))s)")

        // Store for UI (optional)
        lastAmbientCommand = command
        lastAmbientCommandTime = Date()

        // TODO: Route to workflow system
        // For now, just log the command
        // Future: Create synthetic memo or trigger workflow directly
    }

    private func handleVoiceNavigation(intent: String, confidence: Float, rawText: String) {
        logger.info("[Agent] Voice navigation received: \(intent) (confidence: \(String(format: "%.0f%%", confidence * 100)))")

        // Store for UI
        lastVoiceNavigationIntent = intent
        lastVoiceNavigationTime = Date()

        // Route to NavigationState
        NavigationState.shared.handleVoiceNavigation(intent: intent, rawText: rawText)
    }

    // Track last ambient command for UI display
    public private(set) var lastAmbientCommand: String?
    public private(set) var lastAmbientCommandTime: Date?

    // Track last voice navigation for UI display
    public private(set) var lastVoiceNavigationIntent: String?
    public private(set) var lastVoiceNavigationTime: Date?

    private func updateState(_ stateString: String, _ elapsed: TimeInterval) {
        let newState = LiveState(rawValue: stateString) ?? .idle
        self.elapsedTime = elapsed

        if newState != state {
            state = newState
            logger.info("[Agent] State (XPC): \(stateString)")
            CompanionRuntimeSignal.notify(reason: "agent-xpc-\(stateString)")
        }
    }

    // MARK: - Debug Info

    public var debugInfo: ServiceDebugInfo {
        ServiceDebugInfo(
            serviceName: "TalkieAgent",
            processId: processId,
            environment: environment,
            isXPCConnected: isXPCConnected,
            xpcServiceName: environment?.liveXPCService,
            bundleId: environment?.liveBundleId
        )
    }
}

@available(*, deprecated, renamed: "AgentServiceState")
public typealias LiveServiceState = AgentServiceState

/// Engine process state (backwards compatibility with TalkieServiceState)
public enum TalkieServiceState: String {
    case running = "Running"
    case stopped = "Stopped"
    case launching = "Launching..."
    case terminating = "Terminating..."
    case unknown = "Unknown"
}

// MARK: - Engine Service State

@MainActor
@Observable
public final class EngineServiceState {

    // ─── Core State ───
    public private(set) var isRunning: Bool = false
    public private(set) var isConnected: Bool = false
    public private(set) var isLaunching: Bool = false

    /// Computed state for backwards compatibility
    public var state: TalkieServiceState {
        if isLaunching { return .launching }
        if isRunning { return .running }
        return .stopped
    }

    // ─── Process Info ───
    public private(set) var processId: pid_t?
    public private(set) var environment: TalkieEnvironment?
    public private(set) var bundlePath: String?

    // ─── Resource Usage (Dev) ───
    public private(set) var cpuUsage: Double = 0
    public private(set) var memoryUsage: UInt64 = 0
    public private(set) var uptime: TimeInterval = 0
    public private(set) var launchedAt: Date?

    // ─── Engine Status ───
    public private(set) var loadedModelId: String?
    public private(set) var isTranscribing: Bool = false

    public init() {}

    // MARK: - Process Detection

    func refreshProcessState() {
        let live = ServiceManager.shared.live

        isRunning = live.isRunning || live.isXPCConnected
        isConnected = live.isXPCConnected
        environment = live.environment
        processId = live.processId
        bundlePath = live.bundlePath
        launchedAt = live.launchedAt
        uptime = live.uptime

        if let pid = live.processId {
            Task.detached { [weak self] in
                await self?.updateResourceUsage(pid: pid)
            }
        } else {
            cpuUsage = 0
            memoryUsage = 0
        }
    }

    /// Update from EngineClient connection state
    public func updateConnectionState(connected: Bool, environment: TalkieEnvironment?) {
        isConnected = connected
        self.environment = environment
    }

    /// Update from EngineClient status
    public func updateStatus(loadedModel: String?, transcribing: Bool) {
        loadedModelId = loadedModel
        isTranscribing = transcribing
    }

    private nonisolated func updateResourceUsage(pid: pid_t) async {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", "\(pid)", "-o", "%cpu=,rss="]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                let parts = output.split(separator: " ").map { String($0) }
                if parts.count >= 2 {
                    let cpu = Double(parts[0]) ?? 0
                    let memory = (UInt64(parts[1]) ?? 0) * 1024

                    await MainActor.run {
                        self.cpuUsage = cpu
                        self.memoryUsage = memory
                    }
                }
            }
        } catch {
            // Silently fail
        }
    }

    // MARK: - Formatted Properties

    public var formattedMemory: String {
        let mb = Double(memoryUsage) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    public var formattedUptime: String {
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        let seconds = Int(uptime) % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        }
        return String(format: "%ds", seconds)
    }

    // MARK: - Monitoring (backwards compatibility)

    /// Logs from engine (placeholder)
    public private(set) var logs: [TalkieServiceLogEntry] = []

    /// Last error (placeholder)
    public private(set) var lastError: String?

    /// Start monitoring (no-op for now)
    public func startMonitoring() {}

    /// Stop monitoring (no-op for now)
    public func stopMonitoring() {}

    /// Clear logs
    public func clearLogs() {
        logs = []
    }

    /// Terminate engine
    public func terminate() {
        ServiceManager.shared.terminateLive()
    }

    /// Refresh state
    public func refreshState() {
        refreshProcessState()
    }

    /// Restart engine
    public func restart() async {
        ServiceManager.shared.terminateLive()
        try? await Task.sleep(for: .milliseconds(500))
        ServiceManager.shared.launchLive(resolvingConflicts: true)
    }

    // MARK: - Actions

    /// Launch TalkieEngine (delegates to ServiceManager)
    public func launch() async {
        await MainActor.run {
            ServiceManager.shared.launchLive(resolvingConflicts: true)
        }
    }

    // MARK: - Debug Info

    public var debugInfo: ServiceDebugInfo {
        ServiceDebugInfo(
            serviceName: "EmbeddedEngine",
            processId: processId,
            environment: environment,
            isXPCConnected: isConnected,
            xpcServiceName: environment?.liveXPCService,
            bundleId: environment?.liveBundleId
        )
    }
}

// MARK: - Sync Service State (Backwards Compatibility)

/// SyncServiceState is now HelperProcessState — this typealias preserves compatibility
public typealias SyncServiceState = HelperProcessState

// MARK: - Backwards Compatibility

/// Alias for DiscoveredProcess - use ServiceProcessInfo instead
public typealias DiscoveredProcess = ServiceProcessInfo

/// Log entry from TalkieEngine (backwards compatibility)
public struct TalkieServiceLogEntry: Identifiable, Equatable {
    public let id = UUID()
    public let timestamp: Date
    public let level: LogLevel
    public let category: String
    public let message: String

    public enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        case fault = "FAULT"

        var color: String {
            switch self {
            case .debug: return "gray"
            case .info: return "blue"
            case .warning: return "orange"
            case .error: return "red"
            case .fault: return "purple"
            }
        }
    }
}
