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

    private init() {}

    // MARK: - Phase 1: Critical (before UI)

    /// Initialize only what's needed to show UI
    /// This runs synchronously on main thread
    func initializeCritical() {
        guard !hasInitialized else { return }

        let state = signposter.beginInterval("Phase 1: Critical")
        logger.info("⚡️ Phase 1: Critical initialization")

        // Configure window appearance to match theme before SwiftUI renders
        // This prevents the "flicker" of default colors before theme loads
        configureWindowAppearance()

        hasInitialized = true
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
        guard !databaseInitialized else {
            logger.info("✓ Database already initialized (skipping duplicate)")
            return true
        }

        let state = signposter.beginInterval("Phase 2: Database")
        logger.info("⚡️ Phase 2: Database initialization (async)")

        do {
            try await DatabaseManager.shared.initialize()
            logger.info("✅ Database ready")
            databaseInitialized = true
            signposter.endInterval("Phase 2: Database", state)
            return true
        } catch {
            logger.error("❌ Database initialization failed: \(error.localizedDescription)")
            signposter.endInterval("Phase 2: Database", state)
            return false
        }
    }

    // MARK: - Phase 3: Deferred (after UI is visible)

    /// Initialize non-critical services after UI is interactive
    /// This runs with a small delay to let UI settle
    func initializeDeferred() {
        logger.info("⚡️ Phase 3: Deferred initialization")

        Task { @MainActor in
            let state = signposter.beginInterval("Phase 3: Deferred")

            // Small delay to ensure UI is responsive first
            try? await Task.sleep(for: .milliseconds(300))

            // Request local notification permissions for workflow notifications
            signposter.emitEvent("Notifications")
            logger.info("  → Local notification permissions")
            requestNotificationPermissions()

            // CloudKit can wait - not needed for local UI
            signposter.emitEvent("CloudKit")
            logger.info("  → CloudKit subscription setup")
            setupCloudKitSubscription()

            // Remote notifications can wait
            signposter.emitEvent("Remote Notifications")
            logger.info("  → Remote notifications")
            NSApplication.shared.registerForRemoteNotifications()

            // CloudKit sync can wait
            signposter.emitEvent("Sync Engine")
            logger.info("  → CloudKit sync engine")
            CloudKitSyncEngine.shared.startPeriodicSync()

            logger.info("✅ Deferred initialization complete")
            signposter.endInterval("Phase 3: Deferred", state)
        }
    }

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                logger.info("✅ Local notification permissions granted")
            } else if let error = error {
                logger.warning("⚠️ Notification permission error: \(error.localizedDescription)")
            } else {
                logger.info("ℹ️ Local notification permissions denied")
            }
        }
    }

    // MARK: - Phase 4: Background (lowest priority)

    /// Initialize background services that aren't immediately needed
    /// This runs with a larger delay
    func initializeBackground() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))

            let state = signposter.beginInterval("Phase 4: Background")
            logger.info("⚡️ Phase 4: Background initialization")

            // Helper apps can start after everything else
            signposter.emitEvent("Helper Apps")
            logger.info("  → Helper apps")
            ServiceManager.shared.ensureHelpersRunning()

            // XPC connection after UI is ready
            signposter.emitEvent("Engine XPC")
            logger.info("  → Engine XPC connection")
            EngineClient.shared.connect()

            logger.info("✅ Background initialization complete")
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
        privateDB.fetch(withSubscriptionID: subscriptionID) { existingSubscription, error in
            if existingSubscription != nil {
                logger.info("✅ CloudKit subscription exists")
                return
            }

            // Would create subscription here if needed
            logger.info("ℹ️ CloudKit subscription would be created")
        }
    }
}

import CloudKit
