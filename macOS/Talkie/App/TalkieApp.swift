//
//  TalkieApp.swift
//  Talkie macOS
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI
import AppKit
import CoreData
import os

private let startupLogger = Logger(subsystem: "jdi.talkie.performance", category: "Startup")
private let startupSignposter = OSSignposter(subsystem: "jdi.talkie.performance", category: "Startup")

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

// Track app startup time with signposts for Instruments
private enum StartupTimer {
    static let appStart = CFAbsoluteTimeGetCurrent()
    static var bodyAccessed = false
    static var persistenceState: OSSignpostIntervalState?

    static func logMilestone(_ name: String) {
        let elapsed = (CFAbsoluteTimeGetCurrent() - appStart) * 1000
        startupLogger.info("⏱️ \(name): \(String(format: "%.0f", elapsed))ms")
    }
}

// Force profiler to initialize early (captures process start time)
private let _profilerInit: Void = { _ = StartupProfiler.shared }()

@main
struct TalkieApp: App {
    // Ensure early theme init runs before anything else
    private let _earlyInit = EarlyThemeInit.didRun

    // Wire up AppDelegate for push notification handling
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // CoreData is now a sync-layer-only concern - initialized in background by StartupCoordinator
    // UI reads from GRDB (source of truth), CoreData just syncs to CloudKit

    init() {
        StartupProfiler.shared.markEarly("app.init.start")
        // No CoreData init here - deferred to background
        StartupProfiler.shared.markEarly("app.init.end")
    }
    // Remove @State from global singletons - they're already observable
    // Reference singletons directly via .shared instead
    @FocusedValue(\.sidebarToggle) var sidebarToggle
    @FocusedValue(\.settingsNavigation) var settingsNavigation
    @FocusedValue(\.liveNavigation) var liveNavigation

    var body: some Scene {
        // Log time to first body access (once)
        if !StartupTimer.bodyAccessed {
            StartupTimer.bodyAccessed = true
            StartupProfiler.shared.markEarly("app.body.firstAccess")
        }

        return WindowGroup(id: "main") {
            // Show UI immediately - GRDB is source of truth
            // CoreData + CloudKit sync layer initializes in background
            TalkieNavigationViewNative()
                .environment(SettingsManager.shared)
                .environment(EngineClient.shared)
                .environment(LiveSettings.shared)
                .environment(CloudKitSyncManager.shared)
                .environment(SystemEventManager.shared)
                .environment(RelativeTimeTicker.shared)
                .frame(minWidth: 900, minHeight: 600)
                .tint(SettingsManager.shared.accentColor.color)
                // NOTE: URL handling is done via Apple Events in AppDelegate.handleGetURLEvent
                // Do NOT add .onOpenURL here - it causes SwiftUI to spawn new windows
                .task {
                    // Background database initialization - non-blocking
                    StartupProfiler.shared.mark("db.grdb.start")
                    _ = await StartupCoordinator.shared.initializeDatabase()
                    StartupProfiler.shared.mark("db.grdb.ready")
                }
                .sheet(isPresented: Binding(
                    get: { OnboardingManager.shared.shouldShowOnboarding },
                    set: { OnboardingManager.shared.shouldShowOnboarding = $0 }
                )) {
                    OnboardingView()
                        .environment(SettingsManager.shared)
                        .environment(LiveSettings.shared)
                }
        }
        .handlesExternalEvents(matching: [])  // IMPORTANT: Empty set = never create new window for URLs
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

}

