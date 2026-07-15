//
//  TalkieApp.swift
//  Talkie macOS
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI
import AppKit
import CoreData
import OSLog
import TalkieKit

private let startupLogger = Log(.system)
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
                    TalkieConsole.critical("[EarlyThemeInit] Theme set to: %@", themeName)
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
    @State private var navigationState = NavigationState()
    @State private var chromeBarHeader = ChromeBarHeader()
    @State private var settings = SettingsManager.shared
    @State private var showCommandPalette = false
    @State private var showKeyboardHelp = false
    @State private var showReportSheet = false
    @State private var showVoiceCommand = SettingsManager.shared.isVoiceCommandPresented
    @State private var bridgeManager = BridgeManager.shared

    var body: some View {
        rootContent
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
            // App-wide image lightbox (.scopeExpandable adopters)
            .overlay { ScopeLightboxHost() }
            // App-wide user-action snackbar (delete+undo, save errors).
            // Distinct from ExtensionToastOverlay which is for milestones.
            .overlay(alignment: .bottomLeading) { ToastHost() }
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

    private var rootContent: some View {
        // Show UI immediately - GRDB is source of truth
        // CoreData + CloudKit sync layer initializes in background
        AppNavigation()
            .withNavigationState(navigationState)
            .withChromeBarHeader(chromeBarHeader)
            .environment(SettingsManager.shared)
            .environment(EngineClient.shared)
            .environment(AgentSettings.shared)
            .environment(CloudKitSyncManager.shared)
            .environment(SystemEventManager.shared)
            .environment(RelativeTimeTicker.shared)
            .frame(minWidth: 900, minHeight: 600)
            .tint(SettingsManager.shared.accentColor.color)
            .refreshThemeOnAppearanceChange()
            .background {
                NavigationWindowActivationView(navigationState: navigationState)
                    .frame(width: 0, height: 0)
            }
            .onAppear {
                Task { @MainActor in
                    NavigationState.activate(navigationState, reason: "root-appear")
                }
            }
    }
}

private struct TalkieCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Replace the default New file group with a single "New Window"
        // item. SwiftUI's WindowGroup already lets us spawn additional
        // instances. Windows share app data/services, but each root window
        // owns its own NavigationState so sidebar routing and back stacks do
        // not mirror each other.
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                openWindow(id: "main")
            }
            .keyboardShortcut("n", modifiers: .command)
        }

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

        // Find — routes to the library search field. ⌘F was advertised
        // in onboarding ("Use ⌘F to search across all your transcriptions")
        // but never bound; this is the binding catching up to the promise.
        // Added after `.pasteboard` so cut/copy/paste stay untouched.
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find…") {
                NavigationState.shared.navigate(to: .recordings)
                NotificationCenter.default.post(name: .focusLibrarySearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
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

@MainActor
private struct NavigationWindowActivationView: NSViewRepresentable {
    let navigationState: NavigationState

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attachWhenReady(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.navigationState = navigationState
        context.coordinator.attachWhenReady(from: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(navigationState: navigationState)
    }

    @MainActor
    final class Coordinator {
        var navigationState: NavigationState
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []

        init(navigationState: NavigationState) {
            self.navigationState = navigationState
        }

        deinit {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func attachWhenReady(from view: NSView) {
            guard let window = view.window else {
                Task { @MainActor [weak self, weak view] in
                    guard let self, let view else { return }
                    self.attachWhenReady(from: view)
                }
                return
            }

            guard self.window !== window else {
                if window.isKeyWindow || window.isMainWindow {
                    activate(reason: "window-update")
                }
                return
            }

            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
            self.window = window

            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.activate(reason: "window-key")
                }
            })

            observers.append(center.addObserver(
                forName: NSWindow.didBecomeMainNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.activate(reason: "window-main")
                }
            })

            if window.isKeyWindow || window.isMainWindow {
                activate(reason: "window-attached")
            }
        }

        private func activate(reason: String) {
            NavigationState.activate(navigationState, reason: reason)
        }
    }
}

private struct BridgePairingApprovalPrompt: View {
    let bridgeManager: BridgeManager

    var body: some View {
        if let pairing = bridgeManager.pendingPairings.first {
            HStack(spacing: 14) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.current.accent)
                    .frame(width: 40, height: 40)
                    .background(Theme.current.accent.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Pair \(pairing.name)?")
                        .font(Theme.current.fontSMMedium)
                        .foregroundStyle(Theme.current.foreground)

                    Text("Allow this iPhone to use Mac Bridge on this Mac.")
                        .font(Theme.current.fontXS)
                        .foregroundStyle(Theme.current.foregroundSecondary)
                }

                Spacer(minLength: 16)

                Button("Decline", role: .cancel) {
                    Task { await bridgeManager.rejectPairing(pairing.deviceId) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Approve") {
                    Task { await bridgeManager.approvePairing(pairing.deviceId) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Theme.current.accent)
            }
            .padding(14)
            .frame(maxWidth: 600)
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.current.border, lineWidth: 1)
            }
            .shadow(color: Theme.current.background.opacity(0.32), radius: 20, y: 10)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
