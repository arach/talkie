//
//  TalkieApp.swift
//  Talkie macOS
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI
import AppKit
import os

private let signposter = OSSignposter(subsystem: "jdi.talkie.performance", category: "Startup")

// MARK: - Sidebar Toggle Action

struct SidebarToggleAction {
    let toggle: () -> Void
}

struct SidebarToggleKey: FocusedValueKey {
    typealias Value = SidebarToggleAction
}

extension FocusedValues {
    var sidebarToggle: SidebarToggleAction? {
        get { self[SidebarToggleKey.self] }
        set { self[SidebarToggleKey.self] = newValue }
    }
}

// MARK: - Settings Navigation Action

struct SettingsNavigationAction {
    let showSettings: () -> Void
}

struct SettingsNavigationKey: FocusedValueKey {
    typealias Value = SettingsNavigationAction
}

extension FocusedValues {
    var settingsNavigation: SettingsNavigationAction? {
        get { self[SettingsNavigationKey.self] }
        set { self[SettingsNavigationKey.self] = newValue }
    }
}

// MARK: - Live Navigation Action

struct LiveNavigationAction {
    let showLive: () -> Void
}

struct LiveNavigationKey: FocusedValueKey {
    typealias Value = LiveNavigationAction
}

extension FocusedValues {
    var liveNavigation: LiveNavigationAction? {
        get { self[LiveNavigationKey.self] }
        set { self[LiveNavigationKey.self] = newValue }
    }
}

@main
struct TalkieApp: App {
    // Wire up AppDelegate for push notification handling
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let persistenceController = PersistenceController.shared
    // Remove @State from global singletons - they're already observable
    // Reference singletons directly via .shared instead
    @FocusedValue(\.sidebarToggle) var sidebarToggle
    @FocusedValue(\.settingsNavigation) var settingsNavigation
    @FocusedValue(\.liveNavigation) var liveNavigation

    var body: some Scene {
        WindowGroup {
            MigrationGateView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(SettingsManager.shared)
                .environment(EngineClient.shared)
                .environment(LiveSettings.shared)
                .environment(CloudKitSyncManager.shared)
                .environment(SystemEventManager.shared)
                .environment(RelativeTimeTicker.shared)
                .frame(minWidth: 900, minHeight: 600)
                .tint(SettingsManager.shared.accentColor.color)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .sheet(isPresented: Binding(
                    get: { OnboardingManager.shared.shouldShowOnboarding },
                    set: { OnboardingManager.shared.shouldShowOnboarding = $0 }
                )) {
                    OnboardingView()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}

            // Add sidebar toggle to View menu
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    sidebarToggle?.toggle()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }

            // Replace default Settings menu item with inline navigation
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    settingsNavigation?.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            // Performance Monitor (Debug)
            CommandGroup(after: .help) {
                Button("Performance Monitor…") {
                    showPerformanceMonitor()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
    }

    // MARK: - Performance Monitor

    private func showPerformanceMonitor() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: PerformanceDebugView())
        window.title = "Performance Monitor"
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Deep Link Handling (backup for SwiftUI)

    private func handleDeepLink(_ url: URL) {
        // Primary URL handling is done via Apple Events in AppDelegate
        // This is a backup in case SwiftUI's onOpenURL fires
        guard url.scheme == "talkie" else { return }

        if url.host == "live" {
            // Navigate to Live section
            liveNavigation?.showLive()
        } else if url.host == "interstitial",
           let idString = url.pathComponents.dropFirst().first,
           let id = Int64(idString) {
            Task { @MainActor in
                InterstitialManager.shared.show(utteranceId: id)
            }
        }
    }
}

// MARK: - Migration Gate View

/// Shows MigrationView if migration is needed, otherwise shows main app
struct MigrationGateView: View {
    @Environment(\.managedObjectContext) private var coreDataContext
    @State private var needsMigration = false
    @State private var checkComplete = false
    @State private var refreshTrigger = 0

    var body: some View {
        Group {
            if !checkComplete {
                // Show loading while checking
                ProgressView("Initializing database...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if needsMigration {
                // Show migration UI
                MigrationView()
                    .environment(\.managedObjectContext, coreDataContext)
                    .onDisappear {
                        // After migration completes, reload the view
                        checkComplete = false
                        checkMigrationStatus()
                    }
            } else {
                // Show main app
                // Database initialization and CloudKit sync are handled by StartupCoordinator
                TalkieNavigationView()
            }
        }
        .task {
            checkMigrationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MigrationCompleted"))) { _ in
            print("📢 [MigrationGate] Received migration completed notification, refreshing...")
            checkComplete = false
            checkMigrationStatus()
        }
    }

    private func checkMigrationStatus() {
        Task { @MainActor in
            let uiState = signposter.beginInterval("UI First Render")
            print("\n🚀 [App Startup] Initializing Talkie...")

            // Phase 2: Initialize database (async, prevents duplicates)
            let success = await StartupCoordinator.shared.initializeDatabase()

            if !success {
                print("❌ [App Startup] Failed to initialize GRDB")
                // Continue anyway - migration will show error if it fails
            }

            // Check migration status
            signposter.emitEvent("Check Migration")
            let migrationComplete = UserDefaults.standard.bool(forKey: "grdb_migration_complete")
            needsMigration = !migrationComplete
            checkComplete = true

            if needsMigration {
                print("⚠️ [App Startup] Migration required - showing MigrationView")
            } else {
                print("✅ [App Startup] Migration already complete - loading main app\n")
                // CloudKit sync and other services are handled by StartupCoordinator.initializeDeferred()
            }

            signposter.endInterval("UI First Render", uiState)
        }
    }
}
