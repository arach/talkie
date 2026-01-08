//
//  talkieApp.swift
//  talkie
//
//  Created by Arach Tchoupani on 2025-11-23.
//

import SwiftUI
import BackgroundTasks

@main
struct talkieApp: App {
    // Wire up AppDelegate for push notification handling
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let persistenceController = PersistenceController.shared
    @ObservedObject private var deepLinkManager = DeepLinkManager.shared

    // First launch detection
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false

    // Splash screen - shown until main view is ready
    @State private var isLoading = true

    // MARK: - Boot Metrics
    private static let bootStart = Date()
    @State private var bootLogged = false

    // MARK: - Background Task Identifiers
    static let refreshTaskIdentifier = "jdi.talkie-os.refresh"
    static let syncTaskIdentifier = "jdi.talkie-os.sync"

    // Notification for triggering onboarding from Settings
    static let showOnboardingNotification = Notification.Name("showOnboarding")

    init() {
        let initStart = Date()
        registerBackgroundTasks()

        // Initialize ConnectionManager and register sync providers
        Task {
            let manager = ConnectionManager.shared
            manager.register(LocalSyncProvider())
            manager.register(iCloudSyncProvider())
            await manager.checkAllConnections()
        }

        let initDuration = Date().timeIntervalSince(initStart)
        AppLogger.app.info("📱 App.init: \(String(format: "%.0f", initDuration * 1000))ms")
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isLoading {
                    SplashView()
                        .transition(.opacity)
                } else {
                    VoiceMemoListView()
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                        .environmentObject(deepLinkManager)
                        .onOpenURL { url in
                            deepLinkManager.handle(url: url)
                        }
                        .onAppear {
                            // Show onboarding on first launch
                            if !hasSeenOnboarding {
                                showOnboarding = true
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: Self.showOnboardingNotification)) { _ in
                            showOnboarding = true
                        }
                        .fullScreenCover(isPresented: $showOnboarding) {
                            OnboardingView(
                                hasSeenOnboarding: $hasSeenOnboarding,
                                onStartRecording: {
                                    // Trigger recording via deep link manager
                                    deepLinkManager.pendingAction = .record
                                }
                            )
                        }
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isLoading)
            .onAppear {
                // Log boot time once
                if !bootLogged {
                    bootLogged = true
                    let bootDuration = Date().timeIntervalSince(Self.bootStart)
                    AppLogger.app.info("📱 BOOT COMPLETE in \(String(format: "%.2f", bootDuration))s")
                }

                // Transition immediately - no artificial delay
                withAnimation {
                    isLoading = false
                }
            }
        }
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
                try persistenceController.container.viewContext.save()
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
                let context = persistenceController.container.newBackgroundContext()
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
