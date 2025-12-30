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

/// Static initializer that runs BEFORE TalkieApp is created
/// Used to set theme from CLI arguments before any views are created
private enum EarlyThemeInit {
    static let didRun: Bool = {
        // Parse --theme argument and set UserDefaults BEFORE SettingsManager initializes
        for arg in ProcessInfo.processInfo.arguments {
            if arg.hasPrefix("--theme=") {
                let themeName = String(arg.dropFirst("--theme=".count))
                if let theme = ThemePreset(rawValue: themeName) {
                    // Set UserDefaults first (for persistence)
                    UserDefaults.standard.set(themeName, forKey: "currentTheme")
                    UserDefaults.standard.synchronize()
                    // Also explicitly set SettingsManager property (in case it was already initialized)
                    SettingsManager.shared.currentTheme = theme
                    Theme.invalidate()
                    NSLog("[EarlyThemeInit] Theme set to: %@", themeName)
                }
                break
            }
        }
        return true
    }()
}

@main
struct TalkieApp: App {
    // Ensure early theme init runs before anything else
    private let _earlyInit = EarlyThemeInit.didRun

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

                Button("E2E Trace Viewer…") {
                    showE2ETraceViewer()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
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

    // MARK: - E2E Trace Viewer

    private func showE2ETraceViewer() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: E2ETraceView())
        window.title = "End-to-End Trace Viewer"
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
                InterstitialManager.shared.show(dictationId: id)
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

    // Static guard - persists across view recreations
    private static var hasStartedInit = false

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
                        Self.hasStartedInit = false  // Allow re-init after migration
                        checkMigrationStatus()
                    }
            } else {
                // Show main app
                // Database initialization and CloudKit sync are handled by StartupCoordinator
                // IMPORTANT: Use TalkieNavigationViewNative (native NavigationSplitView)
                // DO NOT switch back to custom navigation implementations
                TalkieNavigationViewNative()
            }
        }
        .task {
            checkMigrationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MigrationCompleted"))) { _ in
            print("📢 [MigrationGate] Received migration completed notification, refreshing...")
            checkComplete = false
            Self.hasStartedInit = false  // Allow re-init after migration
            checkMigrationStatus()
        }
    }

    private func checkMigrationStatus() {
        // Guard against multiple concurrent calls from .task re-evaluation
        guard !Self.hasStartedInit else { return }
        Self.hasStartedInit = true

        Task { @MainActor in
            let uiState = signposter.beginInterval("UI First Render")

            // Phase 2: Initialize database (async, prevents duplicates)
            let success = await StartupCoordinator.shared.initializeDatabase()

            // Check migration status
            signposter.emitEvent("Check Migration")
            let migrationComplete = UserDefaults.standard.bool(forKey: "grdb_migration_complete")
            needsMigration = !migrationComplete
            checkComplete = true

            // Single summary log
            let dbStatus = success ? "✓" : "✗"
            let migrationStatus = needsMigration ? "migration required" : "ready"
            print("[App] GRDB \(dbStatus) | \(migrationStatus)")

            signposter.endInterval("UI First Render", uiState)
        }
    }
}
