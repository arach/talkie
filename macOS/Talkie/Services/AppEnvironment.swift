//
//  AppEnvironment.swift
//  Talkie
//
//  Centralized app environment detection and helper app management
//  Handles finding debug vs release builds of TalkieLive and TalkieEngine
//

import Foundation
import AppKit
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "AppEnvironment")

@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    // MARK: - Build Configuration

    enum BuildMode {
        case debug
        case release

        var description: String {
            switch self {
            case .debug: return "Debug"
            case .release: return "Release"
            }
        }
    }

    var buildMode: BuildMode {
        #if DEBUG
        return .debug
        #else
        return .release
        #endif
    }

    var isDebug: Bool {
        buildMode == .debug
    }

    // MARK: - Helper App Paths

    enum HelperApp {
        case talkieLive
        case talkieEngine

        var bundleIdentifier: String {
            switch self {
            case .talkieLive: return "jdi.TalkieLive"
            case .talkieEngine: return "jdi.TalkieEngine"
            }
        }

        var appName: String {
            switch self {
            case .talkieLive: return "TalkieLive.app"
            case .talkieEngine: return "TalkieEngine.app"
            }
        }
    }

    /// Find the best build of a helper app
    /// In debug mode: prefers debug builds from DerivedData
    /// In release mode: uses /Applications install
    func findApp(_ app: HelperApp) -> URL? {
        // Debug mode: check stable dev builds first
        if isDebug {
            if let path = findDebugBuild(for: app) {
                return path
            }
        }

        // Fall back to installed version
        let installedPath = URL(fileURLWithPath: "/Applications/\(app.appName)")
        if FileManager.default.fileExists(atPath: installedPath.path) {
            return installedPath
        }

        logger.warning("\(app.appName) not found")
        return nil
    }

    /// Launch a helper app (finds best build automatically)
    func launch(_ app: HelperApp) -> Bool {
        guard let appURL = findApp(app) else {
            logger.error("Cannot launch \(app.appName): not found")
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        // Silent launch - no log needed for normal operation
        return true
    }

    // MARK: - Private Helpers

    private func findDebugBuild(for app: HelperApp) -> URL? {
        // First check stable dev builds location
        let stableDebugPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Talkie/Debug")
            .appendingPathComponent(app.appName)

        if FileManager.default.fileExists(atPath: stableDebugPath.path) {
            return stableDebugPath
        }

        // Fall back to searching DerivedData
        let derivedDataPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")

        guard let enumerator = FileManager.default.enumerator(
            at: derivedDataPath,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == app.appName &&
               fileURL.path.contains("Build/Products/Debug") {
                return fileURL
            }
        }

        return nil
    }

    // MARK: - Process Management

    /// Check if a helper app is running
    func isRunning(_ app: HelperApp) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == app.bundleIdentifier }
    }

    /// Get PID of running helper app
    func getPID(_ app: HelperApp) -> pid_t? {
        let runningApps = NSWorkspace.shared.runningApplications
        if let runningApp = runningApps.first(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
            return runningApp.processIdentifier
        }
        return nil
    }

    /// Terminate a helper app
    func terminate(_ app: HelperApp) -> Bool {
        guard let pid = getPID(app) else {
            logger.warning("Cannot terminate \(app.appName): not running")
            return false
        }

        kill(pid, SIGTERM)
        logger.info("Terminated \(app.appName) (PID: \(pid))")
        return true
    }

    /// Restart a helper app
    func restart(_ app: HelperApp) {
        logger.info("Restarting \(app.appName)")

        // Terminate if running
        _ = terminate(app)

        // Wait briefly, then relaunch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            _ = self.launch(app)
        }
    }
}
