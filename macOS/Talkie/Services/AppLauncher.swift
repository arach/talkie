//
//  AppLauncher.swift
//  Talkie macOS
//
//  Manages embedded helper apps (TalkieLive, TalkieEngine) as login items
//  Uses SMAppService for modern macOS login item management
//

import Foundation
import AppKit
import ServiceManagement
import os
import TalkieKit

private let logger = Logger(subsystem: "jdi.talkie.core", category: "AppLauncher")

// MARK: - App Launcher

@MainActor
final class AppLauncher: ObservableObject {
    static let shared = AppLauncher()

    // Bundle identifiers for helper apps (environment-aware)
    static var engineBundleId: String { TalkieEnvironment.current.engineBundleId }
    static var liveBundleId: String { TalkieEnvironment.current.liveBundleId }

    // Published state for UI
    @Published private(set) var engineStatus: HelperStatus = .unknown
    @Published private(set) var liveStatus: HelperStatus = .unknown

    // Status polling timer
    private var statusTimer: Timer?

    enum HelperStatus: String {
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
    }

    private init() {
        refreshStatus()
        startStatusPolling()
    }

    deinit {
        statusTimer?.invalidate()
    }

    // MARK: - Status Polling

    private func startStatusPolling() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }
    }

    func refreshStatus() {
        engineStatus = getHelperStatus(bundleId: Self.engineBundleId)
        liveStatus = getHelperStatus(bundleId: Self.liveBundleId)
    }

    private func getHelperStatus(bundleId: String) -> HelperStatus {
        // Check if helper exists in embedded location
        guard embeddedHelperURL(for: bundleId) != nil else {
            // Fall back to checking /Applications
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil {
                // App exists in /Applications (legacy installation)
                if isAppRunning(bundleId: bundleId) {
                    return .running
                }
                return .notRunning
            }
            return .notFound
        }

        // Check SMAppService status
        let service = SMAppService.loginItem(identifier: bundleId)
        switch service.status {
        case .enabled:
            return isAppRunning(bundleId: bundleId) ? .running : .enabled
        case .notRegistered:
            return .notRegistered
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .unknown
        }
    }

    private func isAppRunning(bundleId: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first != nil
    }

    // MARK: - Helper App Paths

    /// Returns the URL for an embedded helper app
    private func embeddedHelperURL(for bundleId: String) -> URL? {
        guard let mainBundle = Bundle.main.bundleURL as URL? else { return nil }

        let appName: String
        switch bundleId {
        case Self.engineBundleId:
            appName = "TalkieEngine.app"
        case Self.liveBundleId:
            appName = "TalkieLive.app"
        default:
            return nil
        }

        let helperURL = mainBundle
            .appendingPathComponent("Contents")
            .appendingPathComponent("Library")
            .appendingPathComponent("LoginItems")
            .appendingPathComponent(appName)

        return FileManager.default.fileExists(atPath: helperURL.path) ? helperURL : nil
    }

    // MARK: - Registration

    /// Register all helper apps as login items
    func registerHelpers() {
        registerEngine()
        registerLive()
    }

    /// Register TalkieEngine as a login item
    func registerEngine() {
        do {
            let service = SMAppService.loginItem(identifier: Self.engineBundleId)
            try service.register()
            logger.info("TalkieEngine registered as login item")

            // Launch immediately after registration
            launchEngine()
        } catch {
            logger.error("Failed to register TalkieEngine: \(error.localizedDescription)")
        }
        refreshStatus()
    }

    /// Register TalkieLive as a login item
    func registerLive() {
        do {
            let service = SMAppService.loginItem(identifier: Self.liveBundleId)
            try service.register()
            logger.info("TalkieLive registered as login item")

            // Launch immediately after registration
            launchLive()
        } catch {
            logger.error("Failed to register TalkieLive: \(error.localizedDescription)")
        }
        refreshStatus()
    }

    // MARK: - Unregistration

    /// Unregister all helper apps
    func unregisterHelpers() {
        unregisterEngine()
        unregisterLive()
    }

    func unregisterEngine() {
        do {
            let service = SMAppService.loginItem(identifier: Self.engineBundleId)
            try service.unregister()
            logger.info("TalkieEngine unregistered")
        } catch {
            logger.error("Failed to unregister TalkieEngine: \(error.localizedDescription)")
        }
        refreshStatus()
    }

    func unregisterLive() {
        do {
            let service = SMAppService.loginItem(identifier: Self.liveBundleId)
            try service.unregister()
            logger.info("TalkieLive unregistered")
        } catch {
            logger.error("Failed to unregister TalkieLive: \(error.localizedDescription)")
        }
        refreshStatus()
    }

    // MARK: - Launch/Terminate

    /// Launch TalkieEngine based on current environment
    func launchEngine() {
        // Guard: don't launch if already running
        if isAppRunning(bundleId: Self.engineBundleId) {
            logger.info("TalkieEngine already running, skipping launch")
            refreshStatus()
            return
        }

        let environment = TalkieEnvironment.current

        switch environment {
        case .production, .staging:
            // Launch app from expected location
            launchHelper(bundleId: Self.engineBundleId)

        case .dev:
            // For dev, try launching via launchd daemon first
            logger.info("Starting dev engine via launchctl...")
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["start", Self.engineBundleId]
            try? task.run()
        }

        // Refresh status after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshStatus()
        }
    }

    /// Launch TalkieLive
    func launchLive() {
        // Guard: don't launch if already running
        if isAppRunning(bundleId: Self.liveBundleId) {
            logger.info("TalkieLive already running, skipping launch")
            refreshStatus()
            return
        }
        launchHelper(bundleId: Self.liveBundleId)
    }

    private func launchHelper(bundleId: String) {
        // First try embedded location
        if let helperURL = embeddedHelperURL(for: bundleId) {
            launchApp(at: helperURL)
            return
        }

        // Fall back to /Applications (legacy)
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            launchApp(at: appURL)
            return
        }

        logger.error("Helper app not found: \(bundleId)")
    }

    private func launchApp(at url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false  // Don't bring to foreground
        config.addsToRecentItems = false

        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
            if let error = error {
                logger.error("Failed to launch \(url.lastPathComponent): \(error.localizedDescription)")
            } else {
                logger.info("Launched \(url.lastPathComponent)")
            }
        }

        // Refresh status after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshStatus()
        }
    }

    /// Terminate TalkieEngine
    func terminateEngine() {
        terminateHelper(bundleId: Self.engineBundleId)
    }

    /// Terminate TalkieLive
    func terminateLive() {
        terminateHelper(bundleId: Self.liveBundleId)
    }

    private func terminateHelper(bundleId: String) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        for app in apps {
            app.terminate()
            logger.info("Terminated \(bundleId)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshStatus()
        }
    }

    // MARK: - Setup

    /// Called on app launch to ensure helpers are set up
    func ensureHelpersRunning() {
        refreshStatus()

        // Auto-register if not registered
        if engineStatus == .notRegistered || engineStatus == .notFound {
            // Only auto-register if embedded helper exists
            if embeddedHelperURL(for: Self.engineBundleId) != nil {
                registerEngine()
            }
        } else if engineStatus == .enabled {
            // Registered but not running - launch it
            launchEngine()
        }

        if liveStatus == .notRegistered || liveStatus == .notFound {
            if embeddedHelperURL(for: Self.liveBundleId) != nil {
                registerLive()
            }
        } else if liveStatus == .enabled {
            launchLive()
        }
    }

    // MARK: - Open System Settings

    /// Opens Login Items in System Settings
    func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Helper Status Extensions

extension AppLauncher.HelperStatus {
    var displayColor: String {
        switch self {
        case .running, .enabled:
            return "green"
        case .requiresApproval, .notRegistered:
            return "orange"
        case .notFound, .notRunning, .unknown:
            return "red"
        }
    }

    var icon: String {
        switch self {
        case .running:
            return "checkmark.circle.fill"
        case .enabled:
            return "checkmark.circle"
        case .requiresApproval:
            return "exclamationmark.triangle.fill"
        case .notRegistered:
            return "minus.circle"
        case .notFound:
            return "xmark.circle"
        case .notRunning:
            return "circle.dashed"
        case .unknown:
            return "questionmark.circle"
        }
    }
}
