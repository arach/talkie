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
import TalkieKit

private let startupLogger = Logger(subsystem: "to.talkie.app.performance", category: "Startup")
private let startupSignposter = OSSignposter(subsystem: "to.talkie.app.performance", category: "Startup")

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
                    // SettingsManager will pick this up when it initializes in TalkieApp.init().
                    NSLog("[EarlyThemeInit] Theme set to: %@", themeName)
                }
                break
            }
        }
        return true
    }()
}

// NOTE: Interstitial launch detection moved to main.swift
// Full mode (this file) only runs when NOT launched via interstitial URL
// Lite mode (InterstitialOnlyApp.swift) handles interstitial launches

// Track app startup time with signposts for Instruments
@MainActor
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

// NOTE: @main removed - entry point is now main.swift
// This allows routing to InterstitialOnlyApp for fast interstitial launches
struct TalkieApp: App {
    // Ensure early theme init runs before anything else
    private let _earlyInit = EarlyThemeInit.didRun

    // Wire up AppDelegate for push notification handling
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // CoreData is now a sync-layer-only concern - initialized in background by StartupCoordinator
    // UI reads from GRDB (source of truth), CoreData just syncs to CloudKit

    init() {
        StartupProfiler.shared.markEarly("app.init.start")
        _ = SettingsManager.shared
        _ = ContextRuleStore.shared
        // Kick off DB init immediately - don't wait for view to appear
        Task {
            StartupProfiler.shared.mark("db.grdb.start")
            _ = await StartupCoordinator.shared.initializeDatabase()
            StartupProfiler.shared.mark("db.grdb.ready")
        }

        StartupProfiler.shared.markEarly("app.init.end")
    }

    var body: some Scene {
        // Log time to first body access (once)
        if !StartupTimer.bodyAccessed {
            StartupTimer.bodyAccessed = true
            StartupProfiler.shared.markEarly("app.body.firstAccess")
        }

        return WindowGroup(id: "main") {
            TalkieRootWindow()
        }
        .handlesExternalEvents(matching: [])  // IMPORTANT: Empty set = never create new window for URLs
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            TalkieCommands()
        }
    }

}

private struct TalkieRootWindow: View {
    // Command palette, keyboard help, report sheet, and voice command state
    @State private var settings = SettingsManager.shared
    @State private var showCommandPalette = false
    @State private var showKeyboardHelp = false
    @State private var showReportSheet = false
    @State private var showVoiceCommand = SettingsManager.shared.isVoiceCommandPresented
    @State private var bridgeManager = BridgeManager.shared

    var body: some View {
        // Show UI immediately - GRDB is source of truth
        // CoreData + CloudKit sync layer initializes in background
        AppNavigation()
            .environment(SettingsManager.shared)
            .environment(EngineClient.shared)
            .environment(AgentSettings.shared)
            .environment(CloudKitSyncManager.shared)
            .environment(SystemEventManager.shared)
            .environment(RelativeTimeTicker.shared)
            .frame(minWidth: 900, minHeight: 600)
            .tint(SettingsManager.shared.accentColor.color)
            .refreshThemeOnAppearanceChange()
            // NOTE: URL handling is done via Apple Events in AppDelegate.handleGetURLEvent
            // Do NOT add .onOpenURL here - it causes SwiftUI to spawn new windows
            // DB init now starts in TalkieApp.init() for faster startup
            .sheet(isPresented: Binding(
                get: { OnboardingManager.shared.shouldShowOnboarding },
                set: { OnboardingManager.shared.shouldShowOnboarding = $0 }
            )) {
                Group {
                    if UserDefaults.standard.bool(forKey: "useScopeOnboarding") {
                        ScopeOnboardingView(onFinish: {
                            OnboardingManager.shared.hasCompletedOnboarding = true
                        })
                        .frame(minWidth: 880, minHeight: 600)
                    } else {
                        OnboardingView()
                    }
                }
                .environment(SettingsManager.shared)
                .environment(AgentSettings.shared)
            }
            // Pro Tools onboarding — triggered from Settings → Mode
            // or via talkie://onboarding/pro (CLI: `talkie pro`).
            .sheet(isPresented: Binding(
                get: { ProOnboardingManager.shared.shouldShowProOnboarding },
                set: { ProOnboardingManager.shared.shouldShowProOnboarding = $0 }
            )) {
                ProOnboardingView()
                    .environment(SettingsManager.shared)
            }
            // Keyboard shortcuts help
            .sheet(isPresented: $showKeyboardHelp) {
                KeyboardShortcutsHelpView()
                    .onAppear { SettingsManager.shared.isKeyboardHelpPresented = true }
                    .onDisappear { SettingsManager.shared.isKeyboardHelpPresented = false }
            }
            // Command palette overlay
            .overlay {
                CommandPaletteOverlay(isPresented: $showCommandPalette)
            }
            // Report sheet overlay
            .overlay {
                ReportSheetOverlay(isPresented: $showReportSheet)
            }
            // Extension toasts (milestones, celebrations)
            .overlay {
                if settings.extensionsFrameworkEnabled {
                    ExtensionToastOverlay()
                }
            }
            // Voice command overlay
            .overlay {
                if showVoiceCommand {
                    VoiceCommandOverlay()
                }
            }
            // Mac-side iPhone pairing approval
            .overlay(alignment: .top) {
                BridgePairingApprovalPrompt(bridgeManager: bridgeManager)
                    .padding(.top, 18)
                    .padding(.horizontal, 18)
            }
            // Non-modal shortcut hints (⌘⇧? / ⌃⇧?)
            .overlay(alignment: .topTrailing) {
                if settings.showInlineKeyboardHints {
                    KeyboardHintOverlay {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            settings.showInlineKeyboardHints = false
                        }
                    }
                    .padding(Spacing.lg)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: settings.showInlineKeyboardHints)
            // Listen for command palette trigger from anywhere
            .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) { _ in
                showCommandPalette = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleCommandPalette)) { _ in
                showCommandPalette.toggle()
            }
            // Sync voice command state with SettingsManager
            .onChange(of: SettingsManager.shared.isVoiceCommandPresented) { _, newValue in
                showVoiceCommand = newValue
            }
            .onChange(of: showVoiceCommand) { _, newValue in
                SettingsManager.shared.isVoiceCommandPresented = newValue
            }
            .onReceive(NotificationCenter.default.publisher(for: .showKeyboardHelp)) { _ in
                showKeyboardHelp = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .showVoiceCommand)) { _ in
                showVoiceCommand = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleKeyboardHintOverlay)) { _ in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    settings.showInlineKeyboardHints.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showReportSheet)) { _ in
                showReportSheet = true
            }
            // NOTE: Interstitial cold launch handling moved to main.swift
            // In full mode (this file), we always show the main window normally
    }
}

private struct TalkieCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        // Add sidebar toggle to View menu
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                NotificationCenter.default.post(name: .toggleAppSidebar, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .control])

            Divider()

            Button("Command Palette") {
                NotificationCenter.default.post(name: .toggleCommandPalette, object: nil)
            }
            .keyboardShortcut("k", modifiers: .command)  // Cmd+K (standard)

            Button("Voice Command") {
                NotificationCenter.default.post(name: .showVoiceCommand, object: nil)
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])  // Cmd+Shift+V
        }

        // Replace default Settings menu item with inline navigation
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                NavigationState.shared.navigate(to: .settings)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        // Help menu additions
        CommandGroup(after: .help) {
            Button("Send Feedback…") {
                NotificationCenter.default.post(name: .showReportSheet, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])  // Cmd+Shift+F

            Button("Keyboard Shortcuts") {
                NotificationCenter.default.post(name: .showKeyboardHelp, object: nil)
            }
            .keyboardShortcut("/", modifiers: .shift)  // ? key

            Button("Shortcut Hints") {
                NotificationCenter.default.post(name: .toggleKeyboardHintOverlay, object: nil)
            }
            .keyboardShortcut("/", modifiers: [.command, .shift])

            Button("Recently Deleted") {
                NavigationState.shared.navigate(to: .recentlyDeleted)
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])

            #if DEBUG
            Divider()

            Button("Settings Inspector…") {
                showSettingsInspector()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            #endif
        }
    }
}

private struct BridgePairingApprovalPrompt: View {
    let bridgeManager: BridgeManager

    var body: some View {
        if let pairing = bridgeManager.pendingPairings.first {
            HStack(spacing: 12) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 38, height: 38)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(.rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Approve iPhone Pairing?")
                        .font(Theme.current.fontSMMedium)
                        .foregroundStyle(Theme.current.foreground)

                    Text("\(pairing.name) wants to connect or refresh bridge access.")
                        .font(Theme.current.fontXS)
                        .foregroundStyle(Theme.current.foregroundSecondary)
                }

                Spacer(minLength: 12)

                Button {
                    Task { await bridgeManager.rejectPairing(pairing.deviceId) }
                } label: {
                    Text("Reject")
                        .font(Theme.current.fontXSMedium)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.red.opacity(0.1))
                        .clipShape(.rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button {
                    Task { await bridgeManager.approvePairing(pairing.deviceId) }
                } label: {
                    Text("Approve")
                        .font(Theme.current.fontXSMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.green)
                        .clipShape(.rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .frame(maxWidth: 560)
            .background(.regularMaterial)
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
