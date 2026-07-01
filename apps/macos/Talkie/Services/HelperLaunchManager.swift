//
//  HelperLaunchManager.swift
//  Talkie
//
//  Unified launch/terminate/LaunchAgent management for helper processes.
//  Extracts duplicated lifecycle code from ServiceManager into a focused manager.
//
//  Key improvement: dev builds also use launchctl so MachServices are registered,
//  fixing the "sync says Running but can't connect" bug.
//

import Foundation
import TalkieKit

private let log = Log(.system)

private struct DevBuildExpectation: Equatable {
    let version: String
    let build: String

    var displayVersion: String {
        "\(version) (\(build))"
    }

    func matches(_ identity: TalkieBundleBuildIdentity) -> Bool {
        identity.version == version && identity.build == build
    }
}

@MainActor
public final class HelperLaunchManager {
    public static let shared = HelperLaunchManager()

    /// Last resolved debug build path per helper.
    /// We still re-scan on each launch; this cache is for change logging only.
    private var resolvedDebugPaths: [TalkieHelper: URL] = [:]

    private init() {}

    /// Path to ~/Library/LaunchAgents
    public var userLaunchAgentsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }

    // MARK: - Launch

    /// Launch a helper process.
    ///
    /// - Production: Uses bundled plist + launchctl bootstrap
    /// - Dev: Generates plist with direct executable, installs to
    ///        ~/Library/LaunchAgents, and bootstraps via launchctl.
    ///
    /// The `mode` parameter controls whether launchd keeps the helper alive
    /// (`.alwaysOn`) or launches it once without auto-restart (`.attached`).
    /// `.onDemand` short-circuits the call — the user is in charge of starting it.
    ///
    /// Skips launching if an instance from a different environment is already running
    /// unless `resolvingConflicts` is true, in which case the conflicting jobs
    /// are booted out before the requested environment is launched.
    public func launch(
        _ kind: TalkieHelper,
        mode: HelperLifecycleMode? = nil,
        resolvingConflicts: Bool = false
    ) async throws {
        let resolvedMode = mode ?? SettingsManager.shared.lifecycleMode(for: kind)
        if resolvedMode == .onDemand {
            log.info("[\(kind.displayName)] Skipping launch — lifecycle mode is on-demand")
            return
        }

        let env = ServiceManager.shared.effectiveHelperEnvironment
        log.info("[\(kind.displayName)] Launching (\(env.displayName), mode: \(resolvedMode.rawValue))...")

        if resolvingConflicts {
            await bootoutLegacyLabels(for: kind, environment: env)
        }

        let conflicts = conflictingEnvironments(for: kind, launching: env)
        if !conflicts.isEmpty {
            let names = conflicts.map(\.displayName).joined(separator: ", ")
            if resolvingConflicts {
                log.info("[\(kind.displayName)] Switching from \(names) to \(env.displayName)")
                for otherEnv in conflicts {
                    for label in launchdLabels(for: kind, environment: otherEnv) {
                        await bootout(label: label)
                    }
                }
            } else {
                log.warning("[\(kind.displayName)] Skipping launch — \(names) instance already loaded. Kill it first to use \(env.displayName).")
                return
            }
        }

        if env == .production {
            // Production: use bundled plist
            let label = kind.plistLabel
            let destPlist = userLaunchAgentsDir.appendingPathComponent("\(label).plist")
            if FileManager.default.fileExists(atPath: destPlist.path) {
                await bootstrap(label: label, plistPath: destPlist)
            } else {
                try installLaunchAgent(for: kind)
            }
        } else {
            // Dev: generate plist + bootstrap via launchctl
            try await launchDevHelper(kind, env: env, mode: resolvedMode)
        }
    }

    /// Launch a dev helper via launchctl with a generated plist.
    ///
    /// The plist launches the executable directly so launchd owns the process
    /// and MachService routing works.
    ///
    /// Idempotent: if an installed plist already points at the same executable
    /// and the job is loaded, we skip the bootout+reinstall (which would otherwise
    /// kill a healthy Agent on every Talkie launch) and just kickstart it.
    private func launchDevHelper(_ kind: TalkieHelper, env: TalkieEnvironment, mode: HelperLifecycleMode) async throws {
        // Generate plist with direct executable
        let plistURL = try generateDevPlist(for: kind, env: env, mode: mode)
        let label = kind.bundleId(for: env)
        let destPlist = userLaunchAgentsDir.appendingPathComponent("\(label).plist")

        try FileManager.default.createDirectory(at: userLaunchAgentsDir, withIntermediateDirectories: true)

        let newExecutable = firstProgramArgument(of: plistURL)
        let newKeepAlive = keepAliveFlag(of: plistURL)
        let newManifest = devManifest(of: plistURL)
        let installed = FileManager.default.fileExists(atPath: destPlist.path)
        let existingExecutable = installed ? firstProgramArgument(of: destPlist) : nil
        let existingKeepAlive = installed ? keepAliveFlag(of: destPlist) : nil
        let existingManifest = installed ? devManifest(of: destPlist) : nil

        let pathUnchanged = existingExecutable != nil && existingExecutable == newExecutable
        let modeUnchanged = existingKeepAlive == newKeepAlive
        let manifestUnchanged: Bool
        if let existingManifest, let newManifest {
            manifestUnchanged = NSDictionary(dictionary: existingManifest)
                .isEqual(NSDictionary(dictionary: newManifest))
        } else {
            manifestUnchanged = false
        }
        let alreadyLoaded = isAgentLoaded(label: label)

        if pathUnchanged && modeUnchanged && manifestUnchanged && alreadyLoaded {
            log.info("[\(kind.displayName)] Dev plist unchanged and job loaded — skipping reinstall")
            await bootstrap(label: label, plistPath: destPlist)
            return
        }

        // Path changed or job not loaded — do a clean reinstall
        if FileManager.default.fileExists(atPath: destPlist.path) {
            await bootout(label: label)
            try FileManager.default.removeItem(at: destPlist)
        }

        try FileManager.default.copyItem(at: plistURL, to: destPlist)
        log.info("[\(kind.displayName)] Installed dev plist to ~/Library/LaunchAgents/\(label).plist")

        await bootstrap(label: label, plistPath: destPlist)
    }

    /// Read the first `ProgramArguments` entry (the executable path) from a plist on disk.
    /// Returns nil if the plist can't be parsed or has no ProgramArguments.
    private func firstProgramArgument(of plistURL: URL) -> String? {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let args = plist["ProgramArguments"] as? [String],
              let first = args.first else {
            return nil
        }
        return first
    }

    /// Read the `KeepAlive` flag from a plist on disk. Returns nil when absent or unparsable.
    private func keepAliveFlag(of plistURL: URL) -> Bool? {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return plist["KeepAlive"] as? Bool
    }

    /// Read the persisted dev build identity embedded in a generated launchd plist.
    private func devManifest(of plistURL: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let manifest = plist["TalkieDevManifest"] as? [String: Any],
              !manifest.isEmpty else {
            return nil
        }
        return manifest
    }

    // MARK: - Terminate

    /// Terminate a helper via SIGTERM with SIGKILL fallback
    public func terminate(_ kind: TalkieHelper, pid: pid_t) {
        log.info("[\(kind.displayName)] Terminating (PID: \(pid))")
        Darwin.kill(pid, SIGTERM)

        // Force kill after 2 seconds if still running
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if Darwin.kill(pid, 0) == 0 {
                log.warning("[\(kind.displayName)] Force killing PID \(pid)")
                Darwin.kill(pid, SIGKILL)
            }
            ServiceManager.shared.refreshStatus()
        }
    }

    // MARK: - LaunchAgent Management

    /// Install a launch agent plist to ~/Library/LaunchAgents and bootstrap it
    public func installLaunchAgent(for kind: TalkieHelper) throws {
        let label = kind.plistLabel

        // Guard: don't install prod agent if dev instance is already running
        if let conflict = conflictingEnvironment(for: kind, launching: .production) {
            log.warning("[\(kind.displayName)] Skipping install — \(conflict) instance already loaded.")
            return
        }

        let destPlist = userLaunchAgentsDir.appendingPathComponent("\(label).plist")

        // Already installed?
        if FileManager.default.fileExists(atPath: destPlist.path) {
            if isAgentLoaded(label: label) {
                log.info("[\(kind.displayName)] Already loaded")
                return
            }
            // Installed but not loaded — bootstrap it
            Task { await bootstrap(label: label, plistPath: destPlist) }
            return
        }

        // Find bundled plist
        guard let sourcePlist = Bundle.main.resourceURL?
                .appendingPathComponent("LaunchAgents")
                .appendingPathComponent("\(label).plist"),
              FileManager.default.fileExists(atPath: sourcePlist.path) else {
            log.error("[\(kind.displayName)] Bundled plist not found for \(label)")
            throw HelperLaunchError.plistNotFound(label)
        }

        // Copy to ~/Library/LaunchAgents
        try FileManager.default.createDirectory(at: userLaunchAgentsDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sourcePlist, to: destPlist)
        log.info("[\(kind.displayName)] Installed \(label).plist")

        // Bootstrap
        Task { await bootstrap(label: label, plistPath: destPlist) }
    }

    /// Bootstrap a launch agent via launchctl.
    ///
    /// Tries non-destructive `bootstrap` first (registers + starts the plist).
    /// If already registered, falls back to `kickstart` (starts the job if stopped,
    /// no-op if already running). Never uses `-k` flag to avoid killing healthy
    /// instances which would trigger TalkieSync's crash loop detection.
    public func bootstrap(label: String, plistPath: URL) async {
        let uid = getuid()
        let plistPathString = plistPath.path

        await Task.detached {
            // 1. Try bootstrap first (non-destructive: registers plist + starts the job)
            //    Fails if already registered, which is fine — we'll kickstart instead.
            let bootstrap = Process()
            bootstrap.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            bootstrap.arguments = ["bootstrap", "gui/\(uid)", plistPathString]
            bootstrap.standardOutput = FileHandle.nullDevice
            bootstrap.standardError = FileHandle.nullDevice

            do {
                try bootstrap.run()
                bootstrap.waitUntilExit()
                if bootstrap.terminationStatus == 0 {
                    log.info("[HelperLaunchManager] Bootstrapped \(label)")
                    await MainActor.run { ServiceManager.shared.refreshStatus() }
                    return
                }
            } catch {
                log.warning("[HelperLaunchManager] Bootstrap failed for \(label): \(error.localizedDescription)")
            }

            // 2. Already registered — kickstart WITHOUT -k (start if stopped, no-op if running)
            //    The -k flag kills+restarts which triggers crash loop detection — never use it here.
            let kickstart = Process()
            kickstart.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            kickstart.arguments = ["kickstart", "gui/\(uid)/\(label)"]
            kickstart.standardOutput = FileHandle.nullDevice
            kickstart.standardError = FileHandle.nullDevice

            do {
                try kickstart.run()
                kickstart.waitUntilExit()
                if kickstart.terminationStatus == 0 {
                    log.info("[HelperLaunchManager] Kickstarted \(label)")
                } else {
                    log.debug("[HelperLaunchManager] Kickstart returned \(kickstart.terminationStatus) for \(label) (may already be running)")
                }
            } catch {
                log.error("[HelperLaunchManager] Failed to kickstart \(label): \(error.localizedDescription)")
            }

            await MainActor.run { ServiceManager.shared.refreshStatus() }
        }.value
    }

    /// Bootout a launch agent via launchctl
    public func bootout(label: String) async {
        let uid = getuid()

        await Task.detached {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["bootout", "gui/\(uid)/\(label)"]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
                task.waitUntilExit()
                log.info("[HelperLaunchManager] Booted out \(label)")
            } catch {
                log.warning("[HelperLaunchManager] Bootout failed for \(label): \(error.localizedDescription)")
            }
        }.value
    }

    /// Uninstall a launch agent (bootout + remove plist).
    /// Cleans up both production and dev plists.
    public func uninstallLaunchAgent(for kind: TalkieHelper) async {
        // Clean up all environment variants (production, dev)
        for env in TalkieEnvironment.allCases {
            let label = kind.bundleId(for: env)
            let plist = userLaunchAgentsDir.appendingPathComponent("\(label).plist")

            if FileManager.default.fileExists(atPath: plist.path) {
                await bootout(label: label)
                do {
                    try FileManager.default.removeItem(at: plist)
                    log.info("[\(kind.displayName)] Removed \(label).plist")
                } catch {
                    log.error("[\(kind.displayName)] Failed to remove plist: \(error.localizedDescription)")
                }
            }
        }

        ServiceManager.shared.refreshStatus()
    }

    /// Check if a launch agent is loaded via launchctl
    public func isAgentLoaded(label: String) -> Bool {
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

    // MARK: - Dev Plist Generation

    /// Generate a launchd plist for a dev build, pointing at the stable dev install.
    ///
    /// The generated plist includes the correct MachServices entry so launchd
    /// registers the XPC service name. The `mode` parameter controls whether
    /// launchd keeps the helper alive (`RunAtLoad`/`KeepAlive` set for `.alwaysOn`,
    /// cleared for `.attached`).
    public func generateDevPlist(for kind: TalkieHelper, env: TalkieEnvironment = .dev, mode: HelperLifecycleMode = .alwaysOn) throws -> URL {
        guard let appURL = resolveDebugBuild(for: kind, env: env) else {
            throw HelperLaunchError.debugBuildNotFound(kind.appName)
        }

        let executablePath = appURL
            .appendingPathComponent("Contents/MacOS")
            .appendingPathComponent(kind.executableName)
            .path

        guard FileManager.default.fileExists(atPath: executablePath) else {
            throw HelperLaunchError.executableNotFound(executablePath)
        }

        let label = kind.bundleId(for: env)
        let xpcService = kind.xpcServiceName(for: env)

        // Launch the executable directly so launchd owns the process and
        // MachService routing works.
        var programArguments = [executablePath]
        if kind == .sync {
            // Improve CloudKit/CoreData crash diagnostics in dev launch-agent runs.
            // This helps surface setup failures beyond a generic SIGTRAP.
            programArguments += ["-com.apple.CoreData.CloudKitDebug", "1"]
        }

        // KeepAlive semantics:
        //   .alwaysOn → launchd restarts on exit, starts at load
        //   .attached → launchd loads the plist but does not restart if it exits
        //   .onDemand → caller short-circuits before reaching plist generation
        let keepAlive = (mode == .alwaysOn)
        let devManifest = devLaunchManifest(
            for: appURL,
            kind: kind,
            env: env,
            executablePath: executablePath
        )
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": programArguments,
            "MachServices": [
                xpcService: true
            ],
            "RunAtLoad": keepAlive,
            "KeepAlive": keepAlive,
            "LimitLoadToSessionType": "Aqua",
            "StandardOutPath": "/tmp/\(label).stdout.log",
            "StandardErrorPath": "/tmp/\(label).stderr.log",
            "TalkieDevManifest": devManifest,
        ]

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label).plist")

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: tempURL)

        log.info("[\(kind.displayName)] Generated dev plist at \(tempURL.path)")
        log.debug("[\(kind.displayName)]   executable: \(executablePath)")
        log.debug("[\(kind.displayName)]   version: \(devManifest["version"] ?? "unknown") (\(devManifest["build"] ?? "unknown"))")
        log.debug("[\(kind.displayName)]   MachService: \(xpcService)")

        return tempURL
    }

    // MARK: - Conflict Detection

    /// Loaded helper environments other than the one we are trying to launch.
    private func conflictingEnvironments(for kind: TalkieHelper, launching env: TalkieEnvironment) -> [TalkieEnvironment] {
        TalkieEnvironment.allCases.filter { otherEnv in
            otherEnv != env && launchdLabels(for: kind, environment: otherEnv).contains { label in
                isAgentLoaded(label: label)
            }
        }
    }

    /// Check if a different environment's instance is already loaded for this helper.
    /// Returns the conflicting environment's display name, or nil if no conflict.
    private func conflictingEnvironment(for kind: TalkieHelper, launching env: TalkieEnvironment) -> String? {
        conflictingEnvironments(for: kind, launching: env).first?.displayName
    }

    // MARK: - Private

    private func bootoutLegacyLabels(for kind: TalkieHelper, environment env: TalkieEnvironment) async {
        let currentLabel = kind.launchdLabel(for: env)
        for label in legacyLaunchdLabels(for: kind, environment: env) where isAgentLoaded(label: label) {
            log.info("[\(kind.displayName)] Booting out legacy launchd label \(label) before launching \(currentLabel)")
            await bootout(label: label)
        }
    }

    private func launchdLabels(for kind: TalkieHelper, environment env: TalkieEnvironment) -> [String] {
        uniqueLabels([kind.launchdLabel(for: env)] + legacyLaunchdLabels(for: kind, environment: env))
    }

    private func legacyLaunchdLabels(for kind: TalkieHelper, environment env: TalkieEnvironment) -> [String] {
        var labels = [kind.xpcServiceName(for: env)]

        if kind == .agent {
            labels.append(legacyLiveLabel(for: env))
            labels.append(legacyLiveXPCLabel(for: env))
        }

        return uniqueLabels(labels).filter { $0 != kind.launchdLabel(for: env) }
    }

    private func legacyLiveLabel(for env: TalkieEnvironment) -> String {
        switch env {
        case .production: return "to.talkie.app.agent"
        case .dev: return "to.talkie.app.agent.dev"
        }
    }

    private func legacyLiveXPCLabel(for env: TalkieEnvironment) -> String {
        switch env {
        case .production: return "to.talkie.app.agent.xpc"
        case .dev: return "to.talkie.app.agent.xpc.dev"
        }
    }

    private func uniqueLabels(_ labels: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        for label in labels where seen.insert(label).inserted {
            result.append(label)
        }

        return result
    }

    private func currentAppBuildExpectation() -> DevBuildExpectation? {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              !version.isEmpty,
              !build.isEmpty else {
            return nil
        }

        return DevBuildExpectation(version: version, build: build)
    }

    private func devLaunchManifest(
        for appURL: URL,
        kind: TalkieHelper,
        env: TalkieEnvironment,
        executablePath: String
    ) -> [String: Any] {
        let identity = TalkieDevBuildManifestStore.bundleIdentity(for: appURL)
        let sidecar = TalkieDevBuildManifestStore.readAppManifest(for: appURL)
        let executableURL = URL(fileURLWithPath: executablePath)
        let modifiedAt = (try? executableURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

        var manifest: [String: Any] = [
            "schemaVersion": sidecar?.schemaVersion ?? 1,
            "product": sidecar?.product ?? kind.displayName,
            "environment": env.rawValue,
            "bundleIdentifier": sidecar?.bundleIdentifier ?? identity?.bundleIdentifier ?? kind.bundleId(for: env),
            "version": sidecar?.version ?? identity?.version ?? "unknown",
            "build": sidecar?.build ?? identity?.build ?? "unknown",
            "installedPath": sidecar?.installedPath ?? appURL.path,
            "executablePath": executablePath,
        ]

        if let sourcePath = sidecar?.sourcePath {
            manifest["sourcePath"] = sourcePath
        }
        if let builtAt = sidecar?.builtAt {
            manifest["builtAt"] = builtAt
        }
        if let installedAt = sidecar?.installedAt {
            manifest["installedAt"] = installedAt
        }
        if let gitBranch = sidecar?.gitBranch {
            manifest["gitBranch"] = gitBranch
        }
        if let gitCommit = sidecar?.gitCommit {
            manifest["gitCommit"] = gitCommit
        }
        if let workspaceRoot = sidecar?.workspaceRoot {
            manifest["workspaceRoot"] = workspaceRoot
        }
        if let modifiedAt {
            manifest["executableModifiedAt"] = iso8601String(modifiedAt)
        }

        return manifest
    }

    private func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Resolve the debug build path for a helper.
    /// Dev helper launch always uses the stable install path written by run.sh.
    private func resolveDebugBuild(for kind: TalkieHelper, env: TalkieEnvironment) -> URL? {
        let expectedBuild = currentAppBuildExpectation()

        let stableApp = kind.userInstalledAppURL(for: env)
        let stableExecutable = stableApp
            .appendingPathComponent("Contents/MacOS")
            .appendingPathComponent(kind.executableName)
        guard FileManager.default.fileExists(atPath: stableExecutable.path) else {
            log.warning("[\(kind.displayName)] Stable dev install missing executable: \(stableExecutable.path)")
            return nil
        }
        guard stableDevAppMatches(
            stableApp,
            appName: kind.appName,
            expectedBundleId: kind.bundleId(for: env),
            expectedBuild: expectedBuild
        ) else {
            return nil
        }

        if resolvedDebugPaths[kind] != stableApp {
            log.info("[\(kind.displayName)] Using stable dev install: \(stableApp.path)")
        }
        resolvedDebugPaths[kind] = stableApp
        return stableApp
    }

    /// Find the stable dev install for a helper.
    ///
    /// Dev helper launch is intentionally not a search. `run.sh` is responsible
    /// for installing the chosen build at a stable path before launchd sees it.
    private func findDebugBuild(
        appName: String,
        executableName: String? = nil,
        environment: TalkieEnvironment = .dev,
        expectedBundleId: String? = nil,
        expectedBuild: DevBuildExpectation? = nil
    ) -> URL? {
        let resolvedExecutableName: String = executableName ?? {
            if appName.hasSuffix(".app") {
                return String(appName.dropLast(4))
            }
            return appName
        }()

        let stableApp = environment.userInstalledAppURL(named: appName)
        let executableURL = stableApp
            .appendingPathComponent("Contents/MacOS")
            .appendingPathComponent(resolvedExecutableName)
        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            log.warning("[HelperLaunchManager] Stable dev install missing executable for \(appName): \(executableURL.path)")
            return nil
        }

        guard stableDevAppMatches(
            stableApp,
            appName: appName,
            expectedBundleId: expectedBundleId,
            expectedBuild: expectedBuild
        ) else { return nil }

        log.debug("[HelperLaunchManager] Using stable dev install for \(appName): \(stableApp.path)")
        return stableApp
    }

    private func stableDevAppMatches(
        _ appURL: URL,
        appName: String,
        expectedBundleId: String?,
        expectedBuild: DevBuildExpectation?
    ) -> Bool {
        guard expectedBundleId != nil || expectedBuild != nil else {
            return true
        }

        guard let identity = TalkieDevBuildManifestStore.bundleIdentity(for: appURL) else {
            log.warning("[HelperLaunchManager] Stable dev install for \(appName) has no readable bundle version identity: \(appURL.path)")
            return false
        }

        if let expectedBundleId,
           let bundleIdentifier = identity.bundleIdentifier,
           bundleIdentifier != expectedBundleId {
            log.warning("[HelperLaunchManager] Stable dev install for \(appName) has bundle \(bundleIdentifier), expected \(expectedBundleId)")
            return false
        }

        if let expectedBuild, !expectedBuild.matches(identity) {
            log.warning("[HelperLaunchManager] Stable dev install for \(appName) is \(identity.displayVersion), expected Talkie \(expectedBuild.displayVersion)")
            return false
        }

        return true
    }

}

// MARK: - Errors

public enum HelperLaunchError: Error, LocalizedError {
    case plistNotFound(String)
    case debugBuildNotFound(String)
    case executableNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .plistNotFound(let label):
            return "Bundled plist not found for \(label)"
        case .debugBuildNotFound(let appName):
            return "Debug build not found for \(appName)"
        case .executableNotFound(let path):
            return "Executable not found at \(path)"
        }
    }
}
