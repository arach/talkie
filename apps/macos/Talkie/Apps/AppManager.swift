//
//  AppManager.swift
//  Talkie
//
//  Discovers and manages Talkie Apps.
//  Apps are folders with manifest.json + background.js (Chrome extension conventions).
//  Looks in: bundled apps (Resources/Apps/) and user apps (~/Library/Application Support/Talkie/Apps/)
//

import Foundation
import TalkieKit

private let log = Log(.system)

// MARK: - App Manager

@MainActor
final class AppManager {
    private weak var runtime: AppsRuntime?

    init(runtime: AppsRuntime) {
        self.runtime = runtime
    }

    // MARK: - Discovery

    /// Discover all apps from bundled and user directories
    func discoverApps() {
        guard let runtime = runtime else { return }

        var discovered: [String: LoadedApp] = [:]

        // 1. Load bundled apps first (from app bundle)
        if let bundledDir = runtime.bundledAppsDirectory {
            let bundledApps = discoverApps(in: bundledDir, isBundled: true)
            for app in bundledApps {
                discovered[app.id] = app
            }
            log.debug("Discovered \(bundledApps.count) bundled apps")
        }

        // 2. Load user apps (override bundled if same ID)
        let userApps = discoverApps(in: runtime.userAppsDirectory, isBundled: false)
        for app in userApps {
            if discovered[app.id] != nil {
                log.info("User app '\(app.id)' overrides bundled app")
            }
            discovered[app.id] = app
        }
        log.debug("Discovered \(userApps.count) user apps")

        let enabledStates = TalkieSettingsConfigurationStore.shared.configuration.apps.enabledStates

        // 3. Load enabled state from declarative settings, falling back to UserDefaults
        for (id, var app) in discovered {
            if let configuredEnabled = enabledStates[id] {
                app.isEnabled = configuredEnabled
            } else {
                let key = "app.\(id).enabled"
                if UserDefaults.standard.object(forKey: key) != nil {
                    app.isEnabled = UserDefaults.standard.bool(forKey: key)
                } else {
                    // Default: enabled
                    app.isEnabled = true
                }
            }
            discovered[id] = app
        }

        runtime.loadedApps = discovered
        log.info("Total apps discovered: \(discovered.count)")
    }

    /// Discover apps in a specific directory
    private func discoverApps(in directory: URL, isBundled: Bool) -> [LoadedApp] {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }

        var apps: [LoadedApp] = []

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            for item in contents {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    continue
                }

                // Check for manifest.json
                let manifestURL = item.appendingPathComponent("manifest.json")
                guard fileManager.fileExists(atPath: manifestURL.path) else {
                    log.debug("Skipping \(item.lastPathComponent): no manifest.json")
                    continue
                }

                do {
                    let manifest = try AppManifest.load(from: item)
                    try manifest.validate()

                    let app = LoadedApp(
                        id: manifest.id,
                        manifest: manifest,
                        directory: item,
                        isBundled: isBundled
                    )
                    apps.append(app)
                    log.debug("Found app: \(manifest.name) v\(manifest.version)")

                } catch {
                    log.error("Failed to load app from \(item.lastPathComponent): \(error)")
                }
            }
        } catch {
            log.error("Failed to scan directory \(directory.path): \(error)")
        }

        return apps
    }

    // MARK: - App Management

    /// Enable or disable an app
    func setEnabled(_ appId: String, enabled: Bool) {
        guard let runtime = runtime,
              var app = runtime.loadedApps[appId] else { return }

        app.isEnabled = enabled
        runtime.loadedApps[appId] = app

        // Persist preference in the file-backed settings layer and mirror to UserDefaults.
        UserDefaults.standard.set(enabled, forKey: "app.\(appId).enabled")
        TalkieSettingsConfigurationStore.shared.update {
            $0.apps.enabledStates[appId] = enabled
        }

        // Load or unload as needed
        if enabled && !app.isLoaded {
            runtime.loadApp(appId)
        } else if !enabled && app.isLoaded {
            runtime.unloadApp(appId)
        }

        log.info("App '\(appId)' \(enabled ? "enabled" : "disabled")")
    }

    /// Refresh apps list (re-scan directories)
    func refresh() {
        guard let runtime = runtime else { return }

        // Unload all current apps
        for (id, app) in runtime.loadedApps where app.isLoaded {
            runtime.unloadApp(id)
        }

        // Re-discover
        discoverApps()

        // Reload enabled apps
        for (id, app) in runtime.loadedApps where app.isEnabled {
            runtime.loadApp(id)
        }
    }

    /// Open user apps directory in Finder
    func openUserAppsDirectory() {
        guard let runtime = runtime else { return }
        NSWorkspace.shared.open(runtime.userAppsDirectory)
    }

    /// Install an app from a directory (copy to user apps)
    func installApp(from source: URL) throws -> String {
        guard let runtime = runtime else {
            throw AppInstallError.runtimeNotAvailable
        }

        // Load and validate manifest
        let manifest = try AppManifest.load(from: source)
        try manifest.validate()

        let destDir = runtime.userAppsDirectory.appendingPathComponent(manifest.id)
        let fileManager = FileManager.default

        // Remove existing if present
        if fileManager.fileExists(atPath: destDir.path) {
            try fileManager.removeItem(at: destDir)
        }

        // Copy app folder
        try fileManager.copyItem(at: source, to: destDir)

        // Refresh to pick up new app
        refresh()

        log.info("Installed app: \(manifest.name)")
        return manifest.id
    }

    /// Uninstall a user app
    func uninstallApp(_ appId: String) throws {
        guard let runtime = runtime,
              let app = runtime.loadedApps[appId] else {
            throw AppInstallError.appNotFound
        }

        guard !app.isBundled else {
            throw AppInstallError.cannotUninstallBundled
        }

        // Unload first
        if app.isLoaded {
            runtime.unloadApp(appId)
        }

        // Remove from disk
        try FileManager.default.removeItem(at: app.directory)

        // Remove from runtime
        runtime.loadedApps.removeValue(forKey: appId)

        // Clean up preferences
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "app.\(appId).enabled")
        TalkieSettingsConfigurationStore.shared.update {
            $0.apps.enabledStates.removeValue(forKey: appId)
        }

        log.info("Uninstalled app: \(app.manifest.name)")
    }
}

// MARK: - Errors

enum AppInstallError: LocalizedError {
    case runtimeNotAvailable
    case appNotFound
    case cannotUninstallBundled

    var errorDescription: String? {
        switch self {
        case .runtimeNotAvailable:
            return "App runtime not available"
        case .appNotFound:
            return "App not found"
        case .cannotUninstallBundled:
            return "Cannot uninstall bundled apps"
        }
    }
}
