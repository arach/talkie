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

    // MARK: - Background Task Identifiers
    static let refreshTaskIdentifier = "jdi.talkie-os.refresh"
    static let syncTaskIdentifier = "jdi.talkie-os.sync"

    // Notification for triggering onboarding from Settings
    static let showOnboardingNotification = Notification.Name("showOnboarding")

    init() {
        registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
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
                    OnboardingView(hasSeenOnboarding: $hasSeenOnboarding)
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
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            AppLogger.app.error("Could not schedule app refresh: \(error.localizedDescription)")
        }
    }

    func scheduleSync() {
        let request = BGProcessingTaskRequest(identifier: Self.syncTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // 1 hour

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            AppLogger.app.error("Could not schedule sync: \(error.localizedDescription)")
        }
    }
}
