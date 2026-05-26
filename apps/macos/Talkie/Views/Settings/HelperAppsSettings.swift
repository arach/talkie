//
//  HelperAppsSettings.swift
//  Talkie macOS
//
//  Settings view for managing helper apps (TalkieAgent, TalkieSync)
//

import SwiftUI
import TalkieKit

// MARK: - Detail Level

/// Controls how much information is shown for helper apps
enum HelperDetailLevel: String, CaseIterable {
    case minimal    // Just status dots - is it working?
    case standard   // Current view with buttons
    case developer  // Full diagnostic info, logs, JSON state

    var icon: String {
        switch self {
        case .minimal: return "circle.fill"
        case .standard: return "list.bullet"
        case .developer: return "terminal"
        }
    }

    var label: String {
        switch self {
        case .minimal: return "Simple"
        case .standard: return "Standard"
        case .developer: return "Technical"
        }
    }
}

// MARK: - Top-Level Tab

enum HelperAppsTab: String, CaseIterable {
    case services = "SERVICES"
    case settings = "SETTINGS"
    case performance = "PERFORMANCE"

    var icon: String {
        switch self {
        case .services: return "app.connected.to.app.below.fill"
        case .settings: return "gearshape"
        case .performance: return "gauge.with.dots.needle.bottom.50percent"
        }
    }

    var color: Color {
        switch self {
        case .services: return .green
        case .settings: return .blue
        case .performance: return .purple
        }
    }
}

struct HelperAppsSettingsView: View {
    private let serviceManager = ServiceManager.shared
    @State private var isRefreshing = false
    @State private var detailLevel: HelperDetailLevel = .standard
    @State private var selectedTab: HelperAppsTab = .services
    @State private var unregisteredHotkeys: [HotKeyStatusInfo] = []

    var body: some View {
        SettingsPageContainer {
            HStack {
                SettingsPageHeader(
                    icon: "app.connected.to.app.below.fill",
                    title: "HELPER APPS",
                    subtitle: "Manage background services that power Talkie features."
                )
                Spacer()

                if selectedTab == .services {
                    // Detail level picker (only relevant for services tab)
                    Picker("", selection: $detailLevel) {
                        ForEach(HelperDetailLevel.allCases, id: \.self) { level in
                            Image(systemName: level.icon)
                                .tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)
                    .help("Detail level: \(detailLevel.label)")
                }

                Button(action: {
                    isRefreshing = true
                    serviceManager.refreshStatus()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        isRefreshing = false
                    }
                }) {
                    Group {
                        if isRefreshing {
                            BrailleSpinner(speed: 0.08)
                                .font(.system(size: 12))
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                        }
                    }
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(width: 24, height: 24)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(CornerRadius.xs)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
        } content: {
            // Tab bar
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(HelperAppsTab.allCases, id: \.self) { tab in
                        helperTabItem(tab)
                    }
                    Spacer()
                }
                .padding(.horizontal, Spacing.sm)

                Rectangle()
                    .fill(Theme.current.divider)
                    .frame(height: 1)
            }
            .settingsSectionCard(padding: 0)

            // Tab content (lazy — only loads the selected tab)
            Group {
                switch selectedTab {
                case .services:
                    servicesContent
                case .settings:
                    settingsContent
                case .performance:
                    PerformanceSettingsView()
                }
            }
            .id(selectedTab)
        }
        .onAppear {
            serviceManager.live.startMonitoring()
            // Check for hotkey registration issues
            Task {
                let statuses = await serviceManager.live.getHotkeyStatus()
                await MainActor.run {
                    unregisteredHotkeys = statuses.filter { !$0.isRegistered }
                }
            }
        }
    }

    // MARK: - Tab Item

    @ViewBuilder
    private func helperTabItem(_ tab: HelperAppsTab) -> some View {
        let isSelected = selectedTab == tab

        Button(action: { selectedTab = tab }) {
            VStack(spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 11))
                    Text(tab.rawValue)
                        .font(Theme.current.fontXSBold)
                }
                .foregroundColor(isSelected ? tab.color : Theme.current.foregroundSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xs)

                Rectangle()
                    .fill(isSelected ? tab.color : Color.clear)
                    .frame(height: 2)
                    .cornerRadius(1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Services Tab

    @ViewBuilder
    private var servicesContent: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.green)
                    .frame(width: 3, height: 14)

                Text("BACKGROUND SERVICES")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            VStack(spacing: Spacing.sm) {
                // TalkieAgent now owns voice capture and embedded transcription
                HelperAppRow(
                    name: "Agent",
                    description: "Voice capture, instant actions, and local transcription",
                    bundleId: ServiceManager.liveBundleId,
                    status: serviceManager.liveStatus,
                    processId: serviceManager.live.processId,
                    environment: serviceManager.live.connectedMode,
                    settingsURL: URL(string: "\(TalkieEnvironment.current.liveURLScheme)://settings"),
                    performanceURL: URL(string: "\(TalkieEnvironment.current.liveURLScheme)://performance"),
                    onShowSettings: nil,
                    onLaunch: { serviceManager.launchLive(resolvingConflicts: true) },
                    onTerminate: { serviceManager.terminateLive() },
                    onRegister: { serviceManager.registerLive() },
                    onUnregister: { serviceManager.unregisterLive() },
                    onReconnect: { serviceManager.live.reconnect() },
                    uptime: serviceManager.live.uptime,
                    bundlePath: serviceManager.live.bundlePath,
                    detailLevel: detailLevel
                )

                // TalkieSync - iCloud sync service
                HelperAppRow(
                    name: "Sync",
                    description: "iCloud sync and backup service",
                    bundleId: ServiceManager.syncBundleId,
                    status: serviceManager.syncStatus,
                    processId: serviceManager.sync.processId,
                    environment: serviceManager.sync.connectedMode,
                    settingsURL: URL(string: "\(TalkieEnvironment.current.syncURLScheme)://settings"),
                    performanceURL: URL(string: "\(TalkieEnvironment.current.syncURLScheme)://performance"),
                    onShowSettings: nil,
                    onLaunch: { serviceManager.launchSync() },
                    onTerminate: { serviceManager.terminateSync() },
                    onRegister: { serviceManager.registerSync() },
                    onUnregister: { serviceManager.unregisterSync() },
                    onReconnect: { SyncClient.shared.reconnect() },
                    uptime: serviceManager.sync.uptime,
                    bundlePath: serviceManager.sync.bundlePath,
                    detailLevel: detailLevel
                )
            }
        }
        .settingsSectionCard(padding: Spacing.md)

        // Hotkey issue alert — only shown when there's a problem
        if !unregisteredHotkeys.isEmpty {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(unregisteredHotkeys.count) hotkey\(unregisteredHotkeys.count == 1 ? "" : "s") not registered")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.orange)

                    Text(unregisteredHotkeys.map(\.label).joined(separator: ", "))
                        .font(.system(size: 10))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Button("Open Agent Settings") {
                    if let url = URL(string: "\(TalkieEnvironment.current.liveURLScheme)://settings/shortcuts") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.accentColor)
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(Color.orange.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Settings Tab

    private var settingsContent: some View {
        Group {
            // Remote Engine
            RemoteEngineSettingsSection()

            // Helper lifecycle modes — per-helper control over how launchd manages them
            HelperLifecycleSection()

            // System Settings
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.blue)
                        .frame(width: 3, height: 14)

                    Text("SYSTEM SETTINGS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Button(action: {
                    serviceManager.openLoginItemsSettings()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "gear")
                            .font(Theme.current.fontXS)
                        Text("OPEN LOGIN ITEMS & LAUNCH AGENTS")
                            .font(Theme.current.fontXSMedium)
                    }
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.xs)
                }
                .buttonStyle(.plain)
            }
            .settingsSectionCard(padding: Spacing.md)

            // Launch Agents
            LaunchAgentsSection(serviceManager: serviceManager)

            // About
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.cyan)
                        .frame(width: 3, height: 14)

                    Text("ABOUT HELPERS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "info.circle")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("Helper apps run in the background to provide voice capture and AI processing. They automatically start when you log in.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: Spacing.md)
        }
    }
}

// MARK: - Helper App Row

private struct HelperAppRow: View {
    let name: String
    let description: String
    let bundleId: String
    let status: ServiceManager.HelperStatus
    let processId: pid_t?
    let environment: TalkieEnvironment?
    let settingsURL: URL?
    let performanceURL: URL?
    let onShowSettings: (() -> Void)?  // XPC-based settings (preferred over URL)
    let onLaunch: () -> Void
    let onTerminate: () -> Void
    let onRegister: () -> Void
    let onUnregister: () -> Void
    var onReconnect: (() -> Void)? = nil  // Force XPC reconnect (for picking up new instances)
    var uptime: TimeInterval = 0
    var bundlePath: String? = nil
    var detailLevel: HelperDetailLevel = .standard

    @State private var isHovered = false
    @State private var isActionInProgress = false

    private var statusColor: Color {
        switch status {
        case .running, .enabled:
            return .green
        case .requiresApproval, .notRegistered:
            return .orange
        case .notFound, .notRunning, .unknown:
            return .red
        }
    }

    private var isRunning: Bool {
        status == .running
    }

    var body: some View {
        switch detailLevel {
        case .minimal:
            minimalView
        case .standard:
            standardView
        case .developer:
            developerView
        }
    }

    // MARK: - Minimal View (clean with helpful context)

    /// One-liner description of what this helper does
    private var helperDescription: String {
        switch name {
        case "Engine":
            return "Transcribes your voice locally, runs in the background"
        case "Agent":
            return "Lives in your menu bar for quick dictation"
        case "Sync":
            return "Keeps your memos synced across devices"
        default:
            return description
        }
    }

    /// Where this helper lives
    private var helperLocation: String {
        switch name {
        case "Engine": return "background"
        case "Agent": return "menu bar"
        case "Sync": return "background"
        default: return "background"
        }
    }

    private var currentEnvironment: TalkieEnvironment {
        TalkieEnvironment.current
    }

    private var hasCrossEnvironmentConnection: Bool {
        guard let env = environment else { return false }
        return env != currentEnvironment
    }

    private var visibleProcessId: pid_t? {
        guard let pid = processId else { return nil }
        if hasCrossEnvironmentConnection && !isRunning {
            return nil
        }
        return pid
    }

    private var helperStatusMessage: String {
        if let env = environment, env != currentEnvironment {
            return "\(currentEnvironment.displayName) \(name) is blocked while the \(env.displayName.lowercased()) helper is loaded. Launch \(name) to switch environments."
        }
        return "Launch restores \(helperLocation) features for Talkie."
    }

    private var minimalView: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header: status + name + location hint
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

                Text(name)
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)

                Text("·")
                    .foregroundColor(.secondary.opacity(0.5))

                Text(helperLocation)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))

                Spacer()

                // Status text
                Text(isRunning ? "Running" : "Stopped")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(statusColor.opacity(0.8))
            }

            // Description
            Text(helperDescription)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)

            // Actions row: settings-type on left, actions on right
            HStack(spacing: Spacing.sm) {
                // Left side: Settings-like buttons
                HStack(spacing: Spacing.xs) {
                    if isRunning, settingsURL != nil || onShowSettings != nil {
                        Button(action: {
                            if let showSettings = onShowSettings { showSettings() }
                            else if let url = settingsURL { NSWorkspace.shared.open(url) }
                        }) {
                            Image(systemName: "gear")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .frame(width: 24, height: 24)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("Settings")
                    }

                    if isRunning, let url = performanceURL {
                        Button(action: { NSWorkspace.shared.open(url) }) {
                            Image(systemName: "gauge.with.needle")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .frame(width: 24, height: 24)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("Performance")
                    }
                }

                Spacer()

                // Right side: Action buttons
                HStack(spacing: Spacing.xs) {
                    if isRunning {
                        if let reconnect = onReconnect {
                            Button(action: reconnect) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 12))
                                    .foregroundColor(.cyan)
                                    .frame(width: 24, height: 24)
                                    .background(Color.cyan.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .help("Reconnect")
                        }

                        Button(action: onTerminate) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .frame(width: 24, height: 24)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("Stop")
                    } else {
                        Button(action: onLaunch) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                                .frame(width: 24, height: 24)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("Start")
                    }
                }
            }
        }
        .padding(Spacing.sm)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
    }

    // MARK: - Standard View (current design)

    private var standardView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isRunning ? "waveform.badge.magnifyingglass" : "app.dashed")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(statusColor.opacity(isRunning ? 0.16 : 0.10))
                    )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(name)
                            .font(Theme.current.fontTitle)
                            .foregroundStyle(Theme.current.foreground)

                        HelperSummaryBadge(
                            title: status.rawValue,
                            systemImage: status.icon,
                            tone: isRunning ? .success : .neutral
                        )
                    }

                    Text(description)
                        .font(Theme.current.fontXS)
                        .foregroundStyle(Theme.current.foregroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    helperMetaRow
                }

                Spacer(minLength: 0)
            }

            if isRunning {
                runningActionPanel
            } else {
                stoppedActionPanel
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(isHovered ? Theme.current.surfaceHover : Theme.current.surface1)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .strokeBorder(
                            isRunning ? statusColor.opacity(0.16) : Theme.current.divider.opacity(0.85),
                            lineWidth: 1
                        )
                )
        )
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var helperMetaRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                helperMetaBadges
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    helperMetaBadges
                }
            }
        }
    }

    @ViewBuilder
    private var helperMetaBadges: some View {
        if let pid = visibleProcessId {
            HelperSummaryBadge(
                title: "PID \(String(pid))",
                systemImage: "number",
                tone: .neutral
            )
        }

        if let env = environment, env != .production || env != currentEnvironment {
            HelperSummaryBadge(
                title: env.displayName,
                systemImage: "server.rack",
                tone: env == .dev ? .accent : .warning
            )
        }

        if isRunning, uptime > 0 {
            HelperSummaryBadge(
                title: formattedUptime,
                systemImage: "clock",
                tone: .neutral
            )
        }
    }

    @ViewBuilder
    private var runningActionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Open")
                    .font(Theme.current.fontXS)
                    .foregroundStyle(Theme.current.foregroundSecondary)

                HStack(spacing: 8) {
                    if onShowSettings != nil || settingsURL != nil {
                        HelperControlButton(
                            title: "Settings",
                            systemImage: "gearshape",
                            tone: .neutral,
                            action: openSettings
                        )
                    }

                    if let url = performanceURL {
                        HelperControlButton(
                            title: "Performance",
                            systemImage: "gauge.with.dots.needle.bottom.50percent",
                            tone: .warning
                        ) {
                            NSWorkspace.shared.open(url)
                        }
                    }

                    if let reconnect = onReconnect {
                        HelperControlButton(
                            title: "Reconnect",
                            systemImage: "arrow.triangle.2.circlepath",
                            tone: .info,
                            isDisabled: isActionInProgress
                        ) {
                            performTimedAction {
                                reconnect()
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Controls")
                    .font(Theme.current.fontXS)
                    .foregroundStyle(Theme.current.foregroundSecondary)

                HStack(spacing: 8) {
                    HelperControlButton(
                        title: "Restart",
                        systemImage: "arrow.clockwise",
                        tone: .accent,
                        prominent: true,
                        isDisabled: isActionInProgress,
                        action: restartService
                    )

                    HelperControlButton(
                        title: "Quit",
                        systemImage: "stop.fill",
                        tone: .danger,
                        prominent: true,
                        isDisabled: isActionInProgress
                    ) {
                        performTimedAction {
                            onTerminate()
                        }
                    }

                    helperServiceMenu

                    if isActionInProgress {
                        BrailleSpinner(size: 12)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(Theme.current.background.opacity(0.32))
        )
    }

    private var stoppedActionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Controls")
                .font(Theme.current.fontXS)
                .foregroundStyle(Theme.current.foregroundSecondary)

            HStack(spacing: 10) {
                HelperControlButton(
                    title: "Launch \(name)",
                    systemImage: "play.fill",
                    tone: .success,
                    prominent: true,
                    isDisabled: isActionInProgress
                ) {
                    performTimedAction(delay: .seconds(2)) {
                        onLaunch()
                    }
                }

                helperServiceMenu

                Spacer(minLength: 0)

                if isActionInProgress {
                    BrailleSpinner(size: 12)
                }
            }

            Text(helperStatusMessage)
                .font(Theme.current.fontXS)
                .foregroundStyle(Theme.current.foregroundSecondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(Theme.current.background.opacity(0.32))
        )
    }

    private var helperServiceMenu: some View {
        Menu {
            if status == .notRegistered || status == .notFound {
                Button(action: onRegister) {
                    Label("Enable Background Service", systemImage: "checkmark.circle")
                }
            } else {
                Button(action: onUnregister) {
                    Label("Disable Background Service", systemImage: "xmark.circle")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                Text("More")
                    .font(Theme.current.fontXS)
            }
            .foregroundStyle(Theme.current.foregroundSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(Theme.current.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(Theme.current.divider, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func openSettings() {
        if let showSettings = onShowSettings {
            showSettings()
        } else if let url = settingsURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func performTimedAction(delay: Duration = .seconds(1), action: @escaping () -> Void) {
        isActionInProgress = true
        action()
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            isActionInProgress = false
        }
    }

    private func restartService() {
        isActionInProgress = true
        onTerminate()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            onLaunch()
            try? await Task.sleep(for: .seconds(1))
            isActionInProgress = false
        }
    }

    // MARK: - Developer View (all CTAs + diagnostic info)

    private var developerView: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header row (same as standard)
            HStack(spacing: 12) {
                // Compact icon with status
                Image(systemName: isRunning ? "app.badge.checkmark.fill" : "app.fill")
                    .font(.system(size: 20))
                    .foregroundColor(statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)

                        Text(status.rawValue)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(statusColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(statusColor.opacity(0.15))
                            .cornerRadius(2)
                    }

                    // Inline technical info
                    HStack(spacing: 6) {
                        if let pid = visibleProcessId {
                            Text("PID:\(pid)")
                                .font(.system(size: 9, design: .monospaced))
                        }
                        if let env = environment {
                            Text(env.rawValue)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(env == .dev ? .purple : .orange)
                        }
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                }

                Spacer()

                // Status badge
                HStack(spacing: 4) {
                    Image(systemName: status.icon)
                        .font(.system(size: 9))
                    Text(status.rawValue)
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(statusColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.1))
                .cornerRadius(CornerRadius.xs)
            }

            // All action buttons (same as standard, compact style)
            HStack(spacing: Spacing.xs) {
                if isRunning {
                    if onShowSettings != nil || settingsURL != nil {
                        devButton("gear", "Settings", .purple) {
                            if let showSettings = onShowSettings { showSettings() }
                            else if let url = settingsURL { NSWorkspace.shared.open(url) }
                        }
                    }

                    devButton("stop.fill", "Stop", .secondary, action: onTerminate)
                    devButton("arrow.clockwise", "Restart", .blue) {
                        onTerminate()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { onLaunch() }
                    }

                    if let reconnect = onReconnect {
                        devButton("arrow.triangle.2.circlepath", "Reconnect", .cyan, action: reconnect)
                    }

                    if let url = performanceURL {
                        devButton("gauge.with.needle", "Perf", .orange) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } else {
                    devButton("play.fill", "Start", .green, action: onLaunch)
                }

                Spacer()

                // More menu
                Menu {
                    if status == .notRegistered || status == .notFound {
                        Button(action: onRegister) {
                            Label("Enable Background Service", systemImage: "checkmark.circle")
                        }
                    } else {
                        Button(action: onUnregister) {
                            Label("Disable Background Service", systemImage: "xmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .padding(4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
            }

            // Diagnostic block (dev-only)
            VStack(alignment: .leading, spacing: 2) {
                diagnosticRow("bundle", bundleId)
                if let pid = visibleProcessId {
                    diagnosticRow("pid", String(pid))
                }
                if let env = environment {
                    diagnosticRow("env", env.rawValue)
                }
                diagnosticRow("status", status.rawValue)
                if isRunning && uptime > 0 {
                    diagnosticRow("uptime", formattedUptime)
                }
                if let path = bundlePath {
                    diagnosticRow("path", abbreviatePath(path))
                }
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.secondary.opacity(0.8))
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.2))
            .cornerRadius(4)
        }
        .padding(Spacing.sm)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
    }

    private func devButton(_ icon: String, _ label: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                Text(label.uppercased())
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .cornerRadius(3)
        }
        .buttonStyle(.plain)
    }

    private var formattedUptime: String {
        let total = Int(uptime)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    private func abbreviatePath(_ path: String) -> String {
        // Shorten DerivedData paths for readability
        if let range = path.range(of: "DerivedData/") {
            return "…/" + path[range.lowerBound...]
        }
        return path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }

    private func diagnosticRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundColor(.secondary.opacity(0.5))
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

private enum HelperControlTone {
    case neutral
    case success
    case info
    case warning
    case accent
    case danger

    @MainActor
    var foreground: Color {
        switch self {
        case .neutral: return Theme.current.foreground
        case .success: return .green
        case .info: return .cyan
        case .warning: return .orange
        case .accent: return .blue
        case .danger: return .red
        }
    }

    /// All tones share the theme-neutral surface fill — the colored
    /// tinted backgrounds (`Color.orange.opacity(0.12)` etc.) read as
    /// candy on light cream paper. Color signal now lives in the icon
    /// foreground and a thin border, not the fill.
    @MainActor
    var background: Color {
        Theme.current.surface1
    }

    @MainActor
    var border: Color {
        switch self {
        case .neutral: return Theme.current.divider
        case .success: return Color.green.opacity(0.18)
        case .info:    return Color.cyan.opacity(0.18)
        case .warning: return Color.orange.opacity(0.20)
        case .accent:  return Color.blue.opacity(0.20)
        case .danger:  return Color.red.opacity(0.22)
        }
    }
}

private struct HelperSummaryBadge: View {
    let title: String
    let systemImage: String
    let tone: HelperControlTone

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))

            Text(title)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .lineLimit(1)
        }
        .foregroundStyle(tone.foreground.opacity(0.88))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(tone.background)
                .overlay(
                    Capsule()
                        .strokeBorder(tone.border, lineWidth: 1)
                )
        )
    }
}

private struct HelperControlButton: View {
    let title: String
    let systemImage: String
    let tone: HelperControlTone
    var prominent: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(tone.foreground.opacity(isDisabled ? 0.5 : 1))
            .frame(maxWidth: prominent ? .infinity : nil)
            .padding(.horizontal, prominent ? 12 : 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(tone.background.opacity(isDisabled ? 0.55 : 1))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(tone.border.opacity(isDisabled ? 0.5 : 1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}


// MARK: - Launch Agents Section

private struct LaunchAgentsSection: View {
    let serviceManager: ServiceManager
    @State private var agentInfos: [LaunchAgentInfo] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.orange)
                    .frame(width: 3, height: 14)

                Text("LAUNCH AGENTS")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Button(action: {
                    serviceManager.revealLaunchAgentsInFinder()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 9))
                        Text("REVEAL")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.xs)
                }
                .buttonStyle(.plain)
            }

            // Directory path
            HStack(spacing: Spacing.xs) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange.opacity(0.7))

                Text(serviceManager.launchAgentsDirectory.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.xs)

            // Agent rows
            VStack(spacing: 4) {
                ForEach(agentInfos) { info in
                    LaunchAgentRow(info: info, serviceManager: serviceManager)
                }
            }

            // Info text
            HStack(alignment: .top, spacing: Spacing.xs) {
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(0.6))

                Text("Launch agents auto-start helpers at login. In dev mode, Talkie regenerates environment-specific launch agents against the latest debug build.")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(0.6))
            }
            .padding(.top, 2)
        }
        .settingsSectionCard(padding: Spacing.md)
        .onAppear {
            agentInfos = serviceManager.launchAgentInfos
        }
    }
}

private struct LaunchAgentRow: View {
    let info: LaunchAgentInfo
    let serviceManager: ServiceManager

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            // Label
            VStack(alignment: .leading, spacing: 1) {
                Text(info.displayName)
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foreground)

                Text(info.label)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(0.7))
            }

            Spacer()

            // Status badge
            Text(info.statusDescription.uppercased())
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(statusColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.15))
                .cornerRadius(CornerRadius.xs)

            // Reveal button (only if installed)
            if info.isInstalled {
                Button(action: {
                    serviceManager.revealPlistInFinder(path: info.plistPath)
                }) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .buttonStyle(.plain)
                .help("Reveal plist in Finder")
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.xs)
    }

    private var statusColor: Color {
        switch info.statusColor {
        case "green": return .green
        case "orange": return .orange
        default: return .gray
        }
    }
}

// MARK: - Remote Engine Settings

private struct RemoteEngineSettingsSection: View {
    @Environment(SettingsManager.self) private var settingsManager
    @State private var connectionStatus: RemoteConnectionStatus = .idle
    @State private var latencyMs: Int?

    private enum RemoteConnectionStatus: Equatable {
        case idle
        case testing
        case success
        case failed(String)
    }

    var body: some View {
        @Bindable var settings = settingsManager

        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.teal)
                    .frame(width: 3, height: 14)

                Text("REMOTE TRANSCRIPTION")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                // Connection status indicator
                if settingsManager.remoteEngineEnabled {
                    connectionStatusBadge
                }
            }

            // Description
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "network")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Text("Offload transcription to a remote TalkieAgent instance over the network (e.g., Mac Mini via Tailscale).")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.sm)
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.sm)

            // Toggle
            HStack {
                Toggle(isOn: $settings.remoteEngineEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use Remote Agent")
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)
                        Text("When enabled, transcription routes through a remote TalkieAgent instance instead of the local embedded transcription service.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(.teal)
            }
            .padding(Spacing.sm)
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.sm)

            // Host & Port (only when enabled)
            if settingsManager.remoteEngineEnabled {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    // Host field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("HOST")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        TextField("mac-mini.tail1234.ts.net", text: $settings.remoteEngineHost)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }

                    // Port field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PORT")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        TextField("19821", value: $settings.remoteEnginePort, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 100)
                    }

                    // Test Connection button
                    HStack(spacing: Spacing.sm) {
                        Button(action: testConnection) {
                            HStack(spacing: 4) {
                                if connectionStatus == .testing {
                                    BrailleSpinner(size: 10)
                                } else {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .font(.system(size: 9))
                                }
                                Text("TEST CONNECTION")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundColor(.teal)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 6)
                            .background(Color.teal.opacity(0.12))
                            .cornerRadius(CornerRadius.xs)
                        }
                        .buttonStyle(.plain)
                        .disabled(settingsManager.remoteEngineHost.isEmpty || connectionStatus == .testing)

                        if let ms = latencyMs, connectionStatus == .success {
                            Text("\(ms)ms")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.green)
                        }

                        if case .failed(let msg) = connectionStatus {
                            Text(msg)
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)

                // Note about Engine restart
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 9))
                        .foregroundColor(.orange.opacity(0.7))

                    Text("The remote TalkieAgent must have remote access enabled and be restarted for changes to take effect.")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(0.7))
                }
                .padding(.top, 2)
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    // MARK: - Connection Status Badge

    @ViewBuilder
    private var connectionStatusBadge: some View {
        let (color, text): (Color, String) = {
            if EngineClient.shared.isConnected && EngineClient.shared.isRemoteMode {
                return (.green, "CONNECTED")
            } else if !settingsManager.remoteEngineHost.isEmpty {
                return (.orange, "DISCONNECTED")
            } else {
                return (.gray, "NOT CONFIGURED")
            }
        }()

        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.1))
        .cornerRadius(CornerRadius.xs)
    }

    // MARK: - Test Connection

    private func testConnection() {
        connectionStatus = .testing
        latencyMs = nil

        let host = settingsManager.remoteEngineHost
        let port = settingsManager.remoteEnginePort

        Task {
            let transport = WebSocketEngineTransport()
            let start = Date()

            do {
                try await transport.connect(host: host, port: port)
                let elapsed = Date().timeIntervalSince(start)
                latencyMs = Int(elapsed * 1000)
                connectionStatus = .success
                transport.disconnect()
            } catch {
                connectionStatus = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: - Helper Lifecycle Section

private struct HelperLifecycleSection: View {
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.indigo)
                    .frame(width: 3, height: 14)

                Text("LIFECYCLE")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "info.circle")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Text("Choose how each helper is managed. Always-on runs via launchd across reboots; attached ties the helper to Talkie; on-demand leaves startup to you.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.sm)
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.sm)

            VStack(spacing: Spacing.xs) {
                HelperLifecycleRow(helper: .agent)
                HelperLifecycleRow(helper: .sync)
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }
}

private struct HelperLifecycleRow: View {
    @Environment(SettingsManager.self) private var settingsManager
    let helper: TalkieHelper

    private var binding: Binding<HelperLifecycleMode> {
        switch helper {
        case .agent:
            return Binding(
                get: { settingsManager.agentLifecycle },
                set: { settingsManager.agentLifecycle = $0 }
            )
        case .sync:
            return Binding(
                get: { settingsManager.syncLifecycle },
                set: { settingsManager.syncLifecycle = $0 }
            )
        case .engine:
            return .constant(helper.defaultLifecycleMode)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(helper.displayName)
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)
                Text(binding.wrappedValue.summary)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            Spacer()

            Picker("", selection: binding) {
                ForEach(HelperLifecycleMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 140)
        }
        .padding(Spacing.sm)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
    }
}

// MARK: - Preview

#Preview {
    HelperAppsSettingsView()
        .environment(SettingsManager.shared)
        .frame(width: 500, height: 400)
        .padding()
}
