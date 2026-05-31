//
//  talkieApp.swift
//  talkie
//
//  Created by Arach Tchoupani on 2025-11-23.
//

import SwiftUI
import BackgroundTasks
import CoreData
import TalkieMobileKit

@main
struct talkieApp: App {
    // Wire up AppDelegate for push notification handling
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Async-loaded persistence controller (non-blocking startup)
    @State private var persistenceController: PersistenceController?
    @State private var mainInterfaceVisible = false
    @ObservedObject private var deepLinkManager = DeepLinkManager.shared
    @State private var appSettings = TalkieAppSettings.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    // First launch detection
    private static let isScreenshotMode = ProcessInfo.processInfo.arguments.contains("-FASTLANE_SNAPSHOT")
    @State private var screenshotSplashVisible: Bool = {
        // Show splash overlay unless --screenshotSkipSplash is passed
        return isScreenshotMode && !ProcessInfo.processInfo.arguments.contains("--screenshotSkipSplash")
    }()

    // MARK: - Boot Metrics
    private static let bootStart = Date()
    @State private var bootLogged = false

    // MARK: - Background Task Identifiers
    static let refreshTaskIdentifier = TalkieMobileRuntimeIdentifiers.refreshTaskIdentifier
    static let syncTaskIdentifier = TalkieMobileRuntimeIdentifiers.syncTaskIdentifier

    // Notification for triggering onboarding from Settings
    static let showOnboardingNotification = Notification.Name("showOnboarding")

    init() {
        let initStart = Date()
        Self.logPhase("bg-task-register", from: initStart) { registerBackgroundTasks() }
        Self.logPhase("app-settings-load", from: initStart) { _ = TalkieAppSettings.shared }
        Self.logPhase("workflow-mirror-sync", from: initStart) {
            _ = TalkieAppConfigurationStore.shared.synchronizePinnedWorkflowMirror()
        }
        Self.logPhase("theme-override-check", from: initStart) { applyScreenshotThemeOverrideIfNeeded() }
        Self.logPhase("network-reachability-start", from: initStart) { NetworkReachability.shared.start() }

        // Initialize ConnectionManager and register sync providers (async, non-blocking)
        Task {
            let manager = ConnectionManager.shared
            manager.register(LocalSyncProvider())
            manager.register(iCloudSyncProvider())
            await manager.checkAllConnections()
        }

        let initDuration = Date().timeIntervalSince(initStart)
        AppLogger.app.info("📱 App.init: \(String(format: "%.0f", initDuration * 1000))ms")
    }

    /// Run `work` and log the elapsed time as a boot-phase marker.
    /// `elapsed` is wall time since the start of `init()` so phase rows
    /// in the console form a cumulative timeline.
    private static func logPhase(_ name: String, from start: Date, _ work: () -> Void) {
        let before = Date()
        work()
        let phase = Date().timeIntervalSince(before) * 1000
        let elapsed = Date().timeIntervalSince(start) * 1000
        AppLogger.app.info("📱  · \(name): +\(String(format: "%.0f", phase))ms (t=\(String(format: "%.0f", elapsed))ms)")
    }

    var body: some Scene {
        WindowGroup {
            @Bindable var appSettings = appSettings
            ZStack {
                if let controller = persistenceController, mainInterfaceVisible {
                    // Database ready - show main content
                    AppShellNext { HomeNextView() }
                        .environment(\.managedObjectContext, controller.container.viewContext)
                        .environmentObject(deepLinkManager)
                        .environmentObject(themeManager)
                        .onAppear {
                            if !appSettings.hasSeenOnboarding && !Self.isScreenshotMode {
                                AppShellRouter.shared.openOnboarding()
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: Self.showOnboardingNotification)) { _ in
                            AppShellRouter.shared.openOnboarding()
                        }
                        .transition(.opacity)
                } else {
                    // Hold splash until the main interface is actually ready to appear.
                    SplashView()
                        .transition(.opacity)
                }

            }
            .animation(Self.isScreenshotMode ? nil : .easeInOut(duration: 0.3), value: persistenceController != nil)
            .overlay {
                // Screenshot splash — sits on top of everything, auto-dismisses
                if screenshotSplashVisible {
                    SplashView()
                        .ignoresSafeArea()
                        .task {
                            try? await Task.sleep(for: .seconds(5))
                            screenshotSplashVisible = false
                        }
                }
            }
            .onOpenURL { url in
                AppLogger.app.info("📱 onOpenURL received: \(url.absoluteString)")
                deepLinkManager.handle(url: url)
            }
            .onAppear {
                // Check for launch URL from environment (set by build script)
                if let launchURL = ProcessInfo.processInfo.environment["TALKIE_OPEN_URL"],
                   let url = URL(string: launchURL) {
                    AppLogger.app.info("📱 Launch URL from environment: \(launchURL)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        deepLinkManager.handle(url: url)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
                appSettings.refreshPinnedWorkflowMirror()
            }
            .task {
                // Load database
                let loadStart = Date()
                let controller = await PersistenceController.loadAsync()
                let loadDuration = Date().timeIntervalSince(loadStart)
                AppLogger.app.info("📱 Database loaded in \(String(format: "%.0f", loadDuration * 1000))ms (async, non-blocking)")

                // Seed demo data for screenshots
                if Self.isScreenshotMode {
                    Self.seedScreenshotData(context: controller.container.viewContext)
                }

                await MainActor.run { persistenceController = controller }

                if !mainInterfaceVisible {
                    try? await Task.sleep(for: .milliseconds(180))
                    await MainActor.run {
                        withAnimation(Self.isScreenshotMode ? nil : .easeInOut(duration: 0.2)) {
                            mainInterfaceVisible = true
                        }
                    }
                }

                // Log total boot time
                if !bootLogged {
                    bootLogged = true
                    let bootDuration = Date().timeIntervalSince(Self.bootStart)
                    AppLogger.app.info("📱 BOOT COMPLETE in \(String(format: "%.2f", bootDuration))s")
                }
            }
            // Drive the whole app's light/dark from the in-app Appearance
            // setting. nil (= .system / "Auto") defers to the OS appearance.
            .preferredColorScheme(themeManager.appearanceMode.colorScheme)
        }
    }

    // MARK: - Screenshot Theme Override

    private func applyScreenshotThemeOverrideIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let themeFlagIndex = arguments.firstIndex(of: "--screenshotTheme"),
            arguments.indices.contains(themeFlagIndex + 1),
            let theme = AppTheme(rawValue: arguments[themeFlagIndex + 1])
        else { return }

        themeManager.apply(theme: theme)
        AppLogger.app.info("📸 Screenshot theme override: \(theme.rawValue)")
    }

    // MARK: - Screenshot Demo Data

    private static func seedScreenshotData(context: NSManagedObjectContext) {
        // Only seed if no memos exist yet
        let request = VoiceMemo.fetchRequest()
        let count = (try? context.count(for: request)) ?? 0
        guard count == 0 else { return }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let demoFile = docs.appendingPathComponent("demo-screenshot.m4a")

        let titles = [
            ("Meeting notes — product roadmap Q1", "We discussed the new onboarding flow, API rate limits, and the timeline for the v3 launch. Sarah will own the design spec, target is end of March."),
            ("Idea: offline-first sync architecture", "What if we treat the local database as the source of truth and let CloudKit be a sync layer? GRDB for speed, Core Data just for the bridge. Need to prototype the conflict resolution."),
            ("Quick thought on keyboard shortcuts", "The dictation keyboard needs a long-press gesture to switch between voice and text mode. Should feel like a walkie-talkie — press and hold to talk, release to send."),
        ]

        for (i, (title, transcript)) in titles.enumerated() {
            let memo = VoiceMemo(context: context)
            memo.id = UUID()
            memo.title = title
            memo.createdAt = Date().addingTimeInterval(-Double((i + 1) * 7200))
            memo.duration = 14.86
            memo.transcription = transcript
            memo.sortOrder = Int32(-memo.createdAt!.timeIntervalSince1970)

            // Point to demo audio file if it exists, otherwise use a placeholder path
            if FileManager.default.fileExists(atPath: demoFile.path) {
                memo.fileURL = demoFile.lastPathComponent
            } else {
                memo.fileURL = "demo-screenshot.m4a"
            }
        }

        try? context.save()
        AppLogger.app.info("📸 Seeded \(titles.count) demo memos for screenshots")
    }

    // MARK: - Background Task Registration

    private func registerBackgroundTasks() {
        // Register app refresh task
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskIdentifier, using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }

        // Register sync processing task
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.syncTaskIdentifier, using: nil) { task in
            self.handleSync(task: task as! BGProcessingTask)
        }
    }

    // MARK: - Background Task Handlers

    private func handleAppRefresh(task: BGAppRefreshTask) {
        // Schedule the next refresh
        scheduleAppRefresh()

        // Create a task for the refresh work
        let refreshTask = Task {
            // Perform lightweight refresh work here
            // e.g., check for updates, sync small amounts of data
            do {
                // Trigger iCloud sync
                if let controller = persistenceController {
                    try controller.container.viewContext.save()
                }
            } catch {
                AppLogger.app.error("Background refresh failed: \(error.localizedDescription)")
            }
        }

        // Handle task expiration
        task.expirationHandler = {
            refreshTask.cancel()
        }

        // Mark task complete when done
        Task {
            await refreshTask.value
            task.setTaskCompleted(success: true)
        }
    }

    private func handleSync(task: BGProcessingTask) {
        // Schedule the next sync
        scheduleSync()

        // Create a task for iCloud sync work
        let syncTask = Task {
            do {
                guard let controller = persistenceController else { return }
                let context = controller.container.newBackgroundContext()
                try await context.perform {
                    // Trigger Core Data to sync with iCloud
                    if context.hasChanges {
                        try context.save()
                    }
                }
                AppLogger.app.info("Background iCloud sync completed")
            } catch {
                AppLogger.app.error("Background sync failed: \(error.localizedDescription)")
            }
        }

        // Handle task expiration
        task.expirationHandler = {
            syncTask.cancel()
        }

        // Mark task complete when done
        Task {
            await syncTask.value
            task.setTaskCompleted(success: true)
        }
    }

    // MARK: - Schedule Background Tasks

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // 1 hour (reduced from 15 min)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            AppLogger.app.error("Could not schedule app refresh: \(error.localizedDescription)")
        }
    }

    func scheduleSync() {
        let request = BGProcessingTaskRequest(identifier: Self.syncTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = true // Only sync when charging
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60) // 4 hours (reduced from 1 hour)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            AppLogger.app.error("Could not schedule sync: \(error.localizedDescription)")
        }
    }
}
