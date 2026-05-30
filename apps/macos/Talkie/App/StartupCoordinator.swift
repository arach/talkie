//
//  StartupCoordinator.swift
//  Talkie macOS
//
//  Coordinates deferred initialization to optimize startup time
//  Production build focus: minimize time to first UI render
//

import Foundation
import AppKit
import os
import UserNotifications
import Darwin
import TalkieKit

private let logger = Logger(subsystem: "to.talkie.app.mac", category: "Startup")
private let signposter = OSSignposter(subsystem: "to.talkie.app.performance", category: "Startup")

/// Coordinates app startup to minimize time-to-interactive
/// Defers non-critical initialization until after UI is visible
@MainActor
final class StartupCoordinator {
    static let shared = StartupCoordinator()

    private var hasInitialized = false
    private var databaseInitialized = false
    private var databaseInitializationTask: Task<Bool, Never>?
    private var didRunStartupMemoryRelief = false
    private var didScheduleDeferredMaintenance = false
    private var didScheduleWorkflowInitialization = false
    private var didScheduleBridgeAutostart = false
    private var didScheduleWorkflowControlPlane = false
    private var didStartTalkieServer = false

    /// Set to true to skip async startup work (phases 3 & 4) for performance testing
    /// This isolates the critical path: load app → load data → render
    /// WARNING: Setting to true will prevent workflows from loading!
    #if DEBUG
    var skipAsyncStartup = false  // Set to true only for startup performance profiling
    #else
    let skipAsyncStartup = false
    #endif

    private init() {
        AppMode.guard(.lite, "StartupCoordinator")
    }

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
        if let databaseInitializationTask {
            return await databaseInitializationTask.value
        }

        let task = Task { @MainActor [weak self] () -> Bool in
            guard let self else { return false }
            guard !self.databaseInitialized else { return true }

            let startTime = CFAbsoluteTimeGetCurrent()
            let state = signposter.beginInterval("Phase 2: Database")

            do {
                try await DatabaseManager.shared.initialize()
                self.databaseInitialized = true
                self.databaseInitializationTask = nil
                let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                logger.info("⏱️ Startup[2]: Database \(String(format: "%.0f", elapsed))ms (GRDB)")
                signposter.endInterval("Phase 2: Database", state)
                return true
            } catch {
                self.databaseInitializationTask = nil
                let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                logger.error("⏱️ Startup[2]: Database FAILED \(String(format: "%.0f", elapsed))ms - \(error.localizedDescription)")
                signposter.endInterval("Phase 2: Database", state)
                return false
            }
        }

        databaseInitializationTask = task
        return await task.value
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

            // Fetch remote feature flags (non-blocking, uses cached on failure)
            signposter.emitEvent("Feature Flags")
            Task(priority: .utility) {
                await FeatureFlags.shared.refresh()
            }

            // Request local notification permissions for workflow notifications
            signposter.emitEvent("Notifications")
            requestNotificationPermissions()

            // Remote notifications (skip in dev - push requires production entitlements)
            signposter.emitEvent("Remote Notifications")
            #if !DEBUG
            NSApplication.shared.registerForRemoteNotifications()
            #endif

            // Sync timing managed by TalkieSync + CloudKitSyncManager bridge state
            signposter.emitEvent("Sync Engine")

            // Dictation migration/legacy-recovery maintenance can be long-running on large datasets.
            // Schedule it in the background so startup completion is not blocked.
            signposter.emitEvent("Dictation Migration")
            scheduleDeferredMaintenanceIfNeeded()

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            logger.info("⏱️ Startup[3]: Deferred \(String(format: "%.0f", elapsed))ms (flags, notifications, maintenance scheduled)")
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

    /// One-time migration of dictations from live.sqlite to unified recordings table
    private func migrateDictationsIfNeeded() async {
        do {
            let count = try await DictationMigrationService.shared.migrateIfNeeded()
            if count > 0 {
                logger.info("📦 Migrated \(count) dictations to unified recordings")
            }
            logger.info("📦 Dictation migration maintenance complete")
        } catch {
            logger.error("📦 Dictation migration failed: \(error.localizedDescription)")
        }
    }

    private func scheduleDeferredMaintenanceIfNeeded() {
        guard !didScheduleDeferredMaintenance else { return }
        didScheduleDeferredMaintenance = true

        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            let start = CFAbsoluteTimeGetCurrent()
            await self.migrateDictationsIfNeeded()
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            logger.info("⏱️ Deferred maintenance finished in \(String(format: "%.0f", elapsed))ms")
        }
    }

    // NOTE: extractMemoAudioIfNeeded() removed - audio extraction handled by TalkieSync bridge sync

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

            // Helper apps can start after everything else — await so Agent's XPC
            // listener is ready before we start monitoring
            signposter.emitEvent("Helper Apps")
            await ServiceManager.shared.ensureHelpersRunning()

            // XPC connections after UI is ready
            signposter.emitEvent("Engine XPC")
            EngineClient.shared.connect()

            // Only connect to Sync service if auto-sync is enabled
            if SettingsManager.shared.syncOnLaunch {
                signposter.emitEvent("Sync XPC")
                SyncClient.shared.connect()
            }

            // Watch for ingested content from iOS (URLs, OCR, photos)
            signposter.emitEvent("Ingest Watcher")
            IngestWatcher.shared.start()

            // Start service monitoring (Live + Engine status awareness)
            // Uses 30s interval - aware but not aggressive
            signposter.emitEvent("Service Monitor")
            ServiceManager.shared.startMonitoring(interval: 30.0)

            // Connect XPC now that the Agent is ready (ensureHelpersRunning awaited above)
            signposter.emitEvent("Agent XPC Connect")
            ServiceManager.shared.live.connectXPC()

            // Register health check provider for feedback reports
            signposter.emitEvent("Reporter Health")
            TalkieReporter.shared.registerHealthCheck {
                let permissions = PermissionsManager.shared
                let appEnvironment = TalkieEnvironment.current
                let helperEnvironment = ServiceManager.shared.effectiveHelperEnvironment
                let agent = ServiceManager.shared.live
                let engine = ServiceManager.shared.engine
                let agentLastCheck = agent.lastPermissionCheck
                let permissionModel = helperEnvironment == .production
                    ? "production-embedded-login-item"
                    : "standalone-helper"
                let agentPrincipal = helperEnvironment == .production ? "Talkie.app" : "TalkieAgent.app"
                var permissionNotes = [
                    helperEnvironment == .production
                        ? "Production Agent is embedded inside Talkie.app; microphone permission is expected under Talkie."
                        : "Dev Agent runs standalone and may have separate microphone permission.",
                ]

                if !agent.isXPCConnected {
                    permissionNotes.append("Agent XPC is not connected, so Agent permission values may be unknown.")
                }
                if agent.hasMicrophonePermission == nil {
                    permissionNotes.append("No Agent microphone permission snapshot has been received.")
                }

                return ReportHealthCheck(
                    talkieMicrophone: permissions.microphoneStatus.displayName,
                    talkieAccessibility: permissions.accessibilityStatus.displayName,
                    talkieAutomation: permissions.automationStatus.displayName,
                    agentRunning: agent.isRunning,
                    agentConnected: agent.isXPCConnected,
                    agentMic: agent.hasMicrophonePermission.map { $0 ? "Granted" : "Denied" },
                    agentAccessibility: agent.hasAccessibilityPermission.map { $0 ? "Granted" : "Denied" },
                    engineRunning: engine.isRunning,
                    appEnvironment: appEnvironment.displayName,
                    helperEnvironment: helperEnvironment.displayName,
                    permissionModel: permissionModel,
                    talkieBundleId: appEnvironment.talkieBundleId,
                    talkieBundlePath: Self.feedbackPath(Bundle.main.bundlePath),
                    agentBundleId: TalkieHelper.agent.bundleId(for: helperEnvironment),
                    agentLaunchdLabel: TalkieHelper.agent.launchdLabel(for: helperEnvironment),
                    agentXPCService: TalkieHelper.agent.xpcServiceName(for: helperEnvironment),
                    agentObservedPath: Self.feedbackPath(agent.bundlePath),
                    agentPermissionPrincipal: agentPrincipal,
                    agentLastPermissionCheck: agentLastCheck.map { ISO8601DateFormatter().string(from: $0) },
                    agentPermissionSnapshotAgeSeconds: agentLastCheck.map { Int(Date().timeIntervalSince($0)) },
                    permissionNotes: permissionNotes
                )
            }

            // WorkflowService - loads workflow JSON files and GRDB preferences
            signposter.emitEvent("Workflows")
            scheduleWorkflowInitializationIfNeeded()

            // TalkieData - GRDB-only client, no Core Data in main app
            // Core Data + CloudKit sync now lives in TalkieSync service
            signposter.emitEvent("TalkieData")
            let dataStart = CFAbsoluteTimeGetCurrent()
            TalkieData.shared.configure()
            let dataElapsed = (CFAbsoluteTimeGetCurrent() - dataStart) * 1000
            logger.info("⏱️ TalkieData: \(String(format: "%.0f", dataElapsed))ms (GRDB-only)")

            // NOTE: extractMemoAudioIfNeeded() removed - audio extraction happens in TalkieSync bridge

            // Power state monitoring for iOS awareness (after CloudKit is ready)
            signposter.emitEvent("Power State")
            PowerStateManager.shared.setup()

            // Keep direct Mac connection healthy in the background.
            // This should not depend on whether the settings UI entry point is visible.
            signposter.emitEvent("Bridge")
            scheduleBridgeAutostartIfNeeded()

            // Start the local Swift relay whenever the server is enabled so
            // companion surfaces, tray assets, and bridge-forwarded actions are
            // ready even before the settings page is opened.
            signposter.emitEvent("TalkieServer")
            startTalkieServerIfNeeded()

            if SettingsManager.shared.workflowControlPlaneEnabled {
                signposter.emitEvent("Workflow Control Plane")
                scheduleWorkflowControlPlaneIfNeeded()
            }

            // Extension Server is now handled by TalkieServer (port 8765, /extensions WebSocket)
            // See apps/macos/TalkieServer/src/extensions/

            // Ask malloc to return free pages after startup bursts.
            signposter.emitEvent("Memory Relief")
            runStartupMemoryReliefIfNeeded()

            // Markdown file backfill (one-time: creates ~/Documents/Talkie/ if missing)
            await MarkdownFileWriter.backfillIfNeeded()

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            logger.info("⏱️ Startup[4]: Background \(String(format: "%.0f", elapsed))ms (helpers, XPC, sync, power, async services scheduled)")
            signposter.endInterval("Phase 4: Background", state)
        }
    }

    private func scheduleWorkflowInitializationIfNeeded() {
        guard !didScheduleWorkflowInitialization else { return }
        didScheduleWorkflowInitialization = true

        Task(priority: .utility) {
            let workflowStart = CFAbsoluteTimeGetCurrent()
            await WorkflowService.shared.initialize()
            let workflowElapsed = (CFAbsoluteTimeGetCurrent() - workflowStart) * 1000
            logger.info("⏱️ Workflow service: \(String(format: "%.0f", workflowElapsed))ms")
        }
    }

    private func scheduleBridgeAutostartIfNeeded() {
        guard !didScheduleBridgeAutostart else { return }
        didScheduleBridgeAutostart = true

        Task(priority: .utility) {
            let bridgeStart = CFAbsoluteTimeGetCurrent()
            await BridgeManager.shared.checkStatusNow()
            let bridgeElapsed = (CFAbsoluteTimeGetCurrent() - bridgeStart) * 1000
            logger.info("⏱️ Bridge readiness: \(String(format: "%.0f", bridgeElapsed))ms")
        }
    }

    private func scheduleWorkflowControlPlaneIfNeeded() {
        guard !didScheduleWorkflowControlPlane else { return }
        didScheduleWorkflowControlPlane = true

        Task(priority: .utility) {
            let controlPlaneStart = CFAbsoluteTimeGetCurrent()
            await MainActor.run {
                WorkflowControlPlaneService.shared.startIfNeeded()
            }
            let controlPlaneElapsed = (CFAbsoluteTimeGetCurrent() - controlPlaneStart) * 1000
            logger.info("⏱️ Workflow control plane: \(String(format: "%.0f", controlPlaneElapsed))ms")
        }
    }

    private func startTalkieServerIfNeeded() {
        guard !didStartTalkieServer else { return }
        guard SettingsManager.shared.talkieServerEnabled else { return }

        didStartTalkieServer = true

        let liveState = ServiceManager.shared.live
        if !liveState.isXPCConnected {
            liveState.startXPCMonitoring()
        }

        TalkieServer.shared.start()
    }

    private func runStartupMemoryReliefIfNeeded() {
        guard !didRunStartupMemoryRelief else { return }
        didRunStartupMemoryRelief = true

        // Clear stale URLCache entries and prompt malloc to trim reclaimable pages.
        URLCache.shared.removeAllCachedResponses()
        let reclaimedBytes = malloc_zone_pressure_relief(nil, 0)
        logger.info("Startup memory relief reclaimed \(reclaimedBytes) bytes")
    }

    private static func feedbackPath(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }
}
