//
//  StartupCoordinator.swift
//  Talkie macOS
//
//  Coordinates deferred initialization to optimize startup time
//  Production build focus: minimize time to first UI render
//

import Foundation
import AppKit
import CloudKit
import os
import UserNotifications

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Startup")
private let signposter = OSSignposter(subsystem: "jdi.talkie.performance", category: "Startup")

/// Coordinates app startup to minimize time-to-interactive
/// Defers non-critical initialization until after UI is visible
@MainActor
final class StartupCoordinator {
    static let shared = StartupCoordinator()

    private var hasInitialized = false
    private var databaseInitialized = false

    /// Set to true to skip async startup work (phases 3 & 4) for performance testing
    /// This isolates the critical path: load app → load data → render
    #if DEBUG
    var skipAsyncStartup = false  // Set true only for render perf testing
    #else
    let skipAsyncStartup = false
    #endif

    private init() {}

    // MARK: - Phase 1: Critical (before UI)

    /// Initialize only what's needed to show UI
    /// This runs synchronously on main thread
    func initializeCritical() {
        guard !hasInitialized else { return }

        let startTime = CFAbsoluteTimeGetCurrent()
        let state = signposter.beginInterval("Phase 1: Critical")

        // Configure window appearance to match theme before SwiftUI renders
        // This prevents the "flicker" of default colors before theme loads
        configureWindowAppearance()

        hasInitialized = true
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        let appearance = SettingsManager.shared.appearanceMode
        logger.info("⏱️ Startup[1]: Critical \(String(format: "%.0f", elapsed))ms (appearance: \(appearance.rawValue))")
        signposter.endInterval("Phase 1: Critical", state)
    }

    // MARK: - Window Appearance

    private func configureWindowAppearance() {
        // Apply appearance mode from saved preferences
        let settings = SettingsManager.shared

        // Set the application-wide appearance to match user preference
        switch settings.appearanceMode {
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system:
            NSApp.appearance = nil  // Follow system
        }

        // Configure window style for any existing windows
        for window in NSApp.windows {
            window.backgroundColor = NSColor.windowBackgroundColor
            window.isOpaque = true
            // Prevent blur effect when window is inactive by disabling layer caching
            window.contentView?.wantsLayer = true
            window.contentView?.layerContentsRedrawPolicy = .onSetNeedsDisplay
        }
    }

    // MARK: - Phase 2: Database (async, before main content)

    /// Initialize database asynchronously
    /// Returns true if already initialized (to avoid duplicate calls)
    func initializeDatabase() async -> Bool {
        guard !databaseInitialized else { return true }

        let startTime = CFAbsoluteTimeGetCurrent()
        let state = signposter.beginInterval("Phase 2: Database")

        do {
            try await DatabaseManager.shared.initialize()
            databaseInitialized = true
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            logger.info("⏱️ Startup[2]: Database \(String(format: "%.0f", elapsed))ms (GRDB)")
            signposter.endInterval("Phase 2: Database", state)
            return true
        } catch {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            logger.error("⏱️ Startup[2]: Database FAILED \(String(format: "%.0f", elapsed))ms - \(error.localizedDescription)")
            signposter.endInterval("Phase 2: Database", state)
            return false
        }
    }

    // MARK: - Phase 3: Deferred (after UI is visible)

    /// Initialize non-critical services after UI is interactive
    /// This runs with a small delay to let UI settle
    func initializeDeferred() {
        // Skip for performance testing (isolate critical path)
        if skipAsyncStartup {
            logger.info("⏱️ Startup[3]: SKIPPED (skipAsyncStartup=true)")
            return
        }

        Task { @MainActor in
            let startTime = CFAbsoluteTimeGetCurrent()
            let state = signposter.beginInterval("Phase 3: Deferred")

            // Small delay to ensure UI is responsive first
            try? await Task.sleep(for: .milliseconds(300))

            // Request local notification permissions for workflow notifications
            signposter.emitEvent("Notifications")
            requestNotificationPermissions()

            // CloudKit can wait - not needed for local UI
            signposter.emitEvent("CloudKit")
            setupCloudKitSubscription()

            // Remote notifications (fire-and-forget - callback handled by AppDelegate)
            signposter.emitEvent("Remote Notifications")
            NSApplication.shared.registerForRemoteNotifications()

            // CloudKit sync timing managed by CloudKitSyncManager
            signposter.emitEvent("Sync Engine")

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            logger.info("⏱️ Startup[3]: Deferred \(String(format: "%.0f", elapsed))ms (notifications, CloudKit)")
            signposter.endInterval("Phase 3: Deferred", state)
        }
    }

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                logger.warning("Notifications: \(error.localizedDescription)")
            } else if !granted {
                logger.info("Notifications: denied by user")
            }
            // Silent on success - expected case
        }
    }

    // MARK: - Phase 4: Background (lowest priority)

    /// Initialize background services that aren't immediately needed
    /// This runs with a larger delay
    func initializeBackground() {
        // Skip for performance testing (isolate critical path)
        if skipAsyncStartup {
            logger.info("⏱️ Startup[4]: SKIPPED (skipAsyncStartup=true)")
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))

            let startTime = CFAbsoluteTimeGetCurrent()
            let state = signposter.beginInterval("Phase 4: Background")

            // Helper apps can start after everything else
            signposter.emitEvent("Helper Apps")
            ServiceManager.shared.ensureHelpersRunning()

            // XPC connection after UI is ready
            signposter.emitEvent("Engine XPC")
            EngineClient.shared.connect()

            // Start service monitoring (Live + Engine status awareness)
            // Uses 30s interval - aware but not aggressive
            signposter.emitEvent("Service Monitor")
            ServiceManager.shared.startMonitoring(interval: 30.0)

            // WorkflowService - loads workflow JSON files and GRDB preferences
            signposter.emitEvent("Workflows")
            let workflowStart = CFAbsoluteTimeGetCurrent()
            await WorkflowService.shared.initialize()
            let workflowElapsed = (CFAbsoluteTimeGetCurrent() - workflowStart) * 1000
            logger.info("⏱️ Workflow service: \(String(format: "%.0f", workflowElapsed))ms")

            // CloudKit sync manager - UI reads from GRDB, this just syncs to cloud
            signposter.emitEvent("Sync Manager")
            let syncStart = CFAbsoluteTimeGetCurrent()
            _ = PersistenceController.shared  // Triggers CloudKit sync infrastructure
            let syncElapsed = (CFAbsoluteTimeGetCurrent() - syncStart) * 1000
            logger.info("⏱️ Sync manager: \(String(format: "%.0f", syncElapsed))ms")

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            logger.info("⏱️ Startup[4]: Background \(String(format: "%.0f", elapsed))ms (helpers, XPC, sync)")
            signposter.endInterval("Phase 4: Background", state)
        }
    }

    // MARK: - CloudKit Setup (deferred)

    private func setupCloudKitSubscription() {
        // Move from AppDelegate - this doesn't need to block startup
        let container = CKContainer(identifier: "iCloud.com.jdi.talkie")
        let privateDB = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
        let subscriptionID = "talkie-private-db-subscription"

        // Check if subscription already exists (async, non-blocking)
        // Silent on success - only log if we need to create one
        privateDB.fetch(withSubscriptionID: subscriptionID) { existingSubscription, error in
            if existingSubscription == nil && error == nil {
                logger.info("CloudKit: subscription needs creation")
            }
        }
    }
}

import CloudKit
