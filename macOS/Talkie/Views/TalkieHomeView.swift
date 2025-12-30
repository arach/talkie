//
//  TalkieHomeView.swift
//  Talkie macOS
//
//  Main home/dashboard view for Talkie app
//  Shows quick stats, recent activity, quick actions, and service health
//

import SwiftUI

struct TalkieHomeView: View {
    // GRDB-backed ViewModel for memo data
    private var memosVM: MemosViewModel { MemosViewModel.shared }

    // Singleton references - use let for @Observable singletons (not @State which breaks observation)
    private let syncManager = CloudKitSyncManager.shared
    private let liveState = ServiceManager.shared.live
    private let serviceMonitor = ServiceManager.shared.engine
    private let eventManager = SystemEventManager.shared
    private let dictationStore = DictationStore.shared
    private let settings = SettingsManager.shared  // For theme observation

    // Cached state - only updates when specific properties change
    @State private var recentMemos: [MemoModel] = []
    @State private var recentDictations: [Dictation] = []
    @State private var isLiveRunning: Bool = false
    @State private var serviceState: TalkieServiceState = .unknown
    @State private var isSyncing: Bool = false
    @State private var lastSyncDate: Date?
    @State private var lastChangeCount: Int = 0
    @State private var workflowEventCount: Int = 0

    var body: some View {
        TalkieSection("Home") {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Header
                    headerView

                    // Quick Stats
                    quickStatsSection

                    // Recent Activity
                    recentActivitySection

                    // Quick Actions
                    quickActionsSection

                    // Capabilities Status (moved lower, less prominent)
                    capabilitiesSection

                    Spacer(minLength: Spacing.xxl)
                }
                .padding(Spacing.lg)
            }
            .background(Theme.current.background)
        }
        // Force view rebuild when theme changes
        .id("home-\(settings.currentTheme?.rawValue ?? "default")")
        .task {
            // Load stats from GRDB
            await memosVM.loadStats()
            await memosVM.loadMemos()
            recentMemos = Array(memosVM.memos.prefix(10))
        }
        .onAppear {
            liveState.startMonitoring()
            serviceMonitor.startMonitoring()

            // Initialize cached state
            isLiveRunning = liveState.isRunning
            serviceState = serviceMonitor.state
            isSyncing = syncManager.isSyncing
            lastSyncDate = syncManager.lastSyncDate
            lastChangeCount = syncManager.lastChangeCount
            workflowEventCount = eventManager.events.filter { $0.type == .workflow }.count
        }
        .onChange(of: liveState.isRunning) { _, newValue in
            isLiveRunning = newValue
        }
        .onChange(of: serviceMonitor.state) { _, newValue in
            serviceState = newValue
        }
        .onChange(of: syncManager.isSyncing) { _, newValue in
            isSyncing = newValue
        }
        .onChange(of: syncManager.lastSyncDate) { _, newValue in
            lastSyncDate = newValue
        }
        .onChange(of: syncManager.lastChangeCount) { _, newValue in
            lastChangeCount = newValue
        }
        .onChange(of: eventManager.events.count) { _, _ in
            workflowEventCount = eventManager.events.filter { $0.type == .workflow }.count
        }
        .onChange(of: memosVM.totalCount) { _, _ in
            // Reload recent memos when count changes (e.g., new memo added)
            Task {
                await memosVM.loadMemos()
                recentMemos = Array(memosVM.memos.prefix(10))
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        let isLinear = settings.isLinearTheme
        let theme = settings.currentTheme

        return VStack(alignment: .leading, spacing: isLinear ? 0 : Spacing.xs) {
            #if DEBUG
            // Debug: show actual theme value
            Text("Theme: \(theme?.rawValue ?? "nil") | isLinear: \(isLinear ? "YES" : "NO")")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.red)
            #endif

            if !isLinear {
                Text("HOME")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(Tracking.wide)
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            Text("Dashboard")
                .font(.system(size: isLinear ? 28 : 24, weight: isLinear ? .semibold : .bold))
                .foregroundColor(Theme.current.foreground)
        }
    }

    // MARK: - Quick Stats Section

    private var quickStatsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Quick Stats")

            HStack(spacing: Spacing.md) {
                StatCard(
                    icon: "square.stack.3d.up.fill",
                    value: "\(memosVM.totalCount)",
                    label: "Total Memos",
                    color: .blue
                )

                StatCard(
                    icon: "waveform",
                    value: memosVM.formattedTotalDuration,
                    label: "Recording Time",
                    color: .purple
                )

                StatCard(
                    icon: "calendar",
                    value: "\(memosVM.thisWeekCount)",
                    label: "This Week",
                    color: .green
                )

                StatCard(
                    icon: "wand.and.stars",
                    value: "\(totalWorkflowRuns)",
                    label: "Workflows",
                    color: .orange
                )
            }
        }
    }

    // MARK: - Capabilities Status Section

    private var capabilitiesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Capabilities")

            HStack(spacing: Spacing.md) {
                // Live Dictation Capability
                ServiceHealthCard(
                    icon: "mic.circle.fill",
                    title: "Live Dictation",
                    isHealthy: isLiveRunning,
                    statusText: isLiveRunning ? "Enabled" : "Disabled",
                    detailText: isLiveRunning
                        ? "Press hotkey to dictate anywhere"
                        : "TalkieLive enables instant voice recording",
                    action: isLiveRunning ? nil : { launchTalkieLive() },
                    actionLabel: "Enable"
                )

                // AI Transcription Capability
                ServiceHealthCard(
                    icon: "text.bubble.fill",
                    title: "AI Transcription",
                    isHealthy: serviceState == .running,
                    statusText: serviceState == .running ? "Ready" : "Offline",
                    detailText: serviceState == .running
                        ? "Speech-to-text powered by local AI"
                        : "TalkieEngine provides AI transcription",
                    action: serviceState == .running ? nil : { Task { await serviceMonitor.launch() } },
                    actionLabel: "Start"
                )

                // iCloud Sync Capability
                ServiceHealthCard(
                    icon: "icloud.fill",
                    title: "Cloud Sync",
                    isHealthy: lastSyncDate != nil,
                    statusText: syncStatusText,
                    detailText: syncDetailText ?? "Sync memos across all your devices"
                )
            }
        }
    }

    // MARK: - Recent Activity Section

    private var recentActivitySection: some View {
        let isLinear = settings.isLinearTheme

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                sectionHeader("Recent Activity")
                Spacer()
                Text("\(recentMemos.count) recent")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            VStack(spacing: 0) {
                if recentMemos.isEmpty {
                    emptyStateView
                } else {
                    ForEach(recentMemos.prefix(10)) { memo in
                        RecentMemoRow(memo: memo)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(isLinear ? Color(white: 0.04) : Theme.current.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(isLinear ? Color.white.opacity(0.08) : Theme.current.divider, lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Quick Actions Section

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Quick Actions")

            HStack(spacing: Spacing.md) {
                QuickActionButton(
                    icon: "square.stack",
                    title: "All Memos",
                    subtitle: "\(memosVM.totalCount) total",
                    action: { navigateToAllMemos() }
                )

                QuickActionButton(
                    icon: "wand.and.stars",
                    title: "Workflows",
                    subtitle: "Manage automation",
                    action: { navigateToWorkflows() }
                )

                QuickActionButton(
                    icon: "gear",
                    title: "Settings",
                    subtitle: "Configure app",
                    action: { navigateToSettings() }
                )
            }
        }
    }

    // MARK: - Helper Views

    private func sectionHeader(_ title: String) -> some View {
        let isLinear = settings.isLinearTheme

        return Text(isLinear ? title : title.uppercased())
            .font(.system(size: isLinear ? 11 : 10, weight: isLinear ? .medium : .bold))
            .tracking(isLinear ? 0 : Tracking.wide)
            .foregroundColor(isLinear ? Theme.current.foregroundSecondary : Theme.current.foregroundMuted)
    }

    private var emptyStateView: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 32))
                .foregroundColor(Theme.current.foregroundMuted)

            Text("No memos yet")
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundSecondary)

            Text("Record on iPhone to sync")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }

    // MARK: - Computed Properties

    private var totalWorkflowRuns: Int {
        // Use cached count from @State
        workflowEventCount
    }

    private var syncStatusText: String {
        if isSyncing {
            return "Syncing..."
        } else if let lastSync = lastSyncDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: lastSync, relativeTo: Date())
        } else {
            return "Not synced"
        }
    }

    private var syncDetailText: String? {
        if lastSyncDate != nil {
            if lastChangeCount > 0 {
                return "\(lastChangeCount) changes synced"
            }
        }
        return nil
    }

    // MARK: - Helper Methods

    private func launchTalkieLive() {
        let appPath = "/Applications/TalkieLive.app"
        if FileManager.default.fileExists(atPath: appPath) {
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: appPath),
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }

    private func navigateToAllMemos() {
        NotificationCenter.default.post(name: .init("NavigateToAllMemos"), object: nil)
    }

    private func navigateToWorkflows() {
        NotificationCenter.default.post(name: .init("NavigateToWorkflows"), object: nil)
    }

    private func navigateToSettings() {
        NotificationCenter.default.post(name: .navigateToSettings, object: nil)
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    @State private var isHovered = false
    private let settings = SettingsManager.shared
    private var isLinear: Bool { settings.isLinearTheme }

    var body: some View {
        VStack(spacing: isLinear ? Spacing.md : Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: isLinear ? 20 : 24, weight: .medium))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: isLinear ? 32 : 28, weight: .bold, design: isLinear ? .default : .rounded))
                .foregroundColor(Theme.current.foreground)

            Text(label)
                .font(.system(size: isLinear ? 11 : 10, weight: .medium))
                .foregroundColor(isLinear ? Theme.current.foregroundSecondary : Theme.current.foregroundMuted)
                .textCase(isLinear ? .none : .uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isLinear ? Spacing.xl : Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(cardBorder, lineWidth: 1)
        )
        .shadow(
            color: isLinear && isHovered ? color.opacity(0.25) : Color.clear,
            radius: isLinear && isHovered ? 20 : 0,
            x: 0, y: 0
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var cardBackground: Color {
        if isLinear {
            return isHovered ? Color(white: 0.06) : Color(white: 0.04)
        }
        return isHovered ? Theme.current.surfaceHover : Theme.current.surface1
    }

    private var cardBorder: Color {
        if isLinear {
            return isHovered ? color.opacity(0.5) : Color.white.opacity(0.08)
        }
        return color.opacity(0.2)
    }
}

// MARK: - Recent Memo Row

struct RecentMemoRow: View {
    let memo: MemoModel

    @State private var isHovered = false
    private let settings = SettingsManager.shared
    private var isLinear: Bool { settings.isLinearTheme }

    var body: some View {
        HStack(spacing: isLinear ? Spacing.md : Spacing.sm) {
            // Icon
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: isLinear ? 16 : 12))
                .foregroundColor(isLinear ? LinearStyle.glowColor : .blue)
                .frame(width: isLinear ? 24 : 20)

            // Title or transcription preview
            Text(memoTitle)
                .font(isLinear ? Theme.current.fontBody : Theme.current.fontSM)
                .foregroundColor(Theme.current.foreground)
                .lineLimit(1)

            Spacer()

            // Time ago
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                RelativeTimeLabel(date: memo.createdAt, formatter: formatTimeAgo)
                    .font(isLinear ? Theme.current.fontSM : Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            // Chevron on hover
            if isHovered {
                Image(systemName: "chevron.right")
                    .font(.system(size: isLinear ? 10 : 9, weight: .medium))
                    .foregroundColor(isLinear && isHovered ? LinearStyle.glowColor : Theme.current.foregroundMuted)
            }
        }
        .padding(.vertical, isLinear ? Spacing.sm : Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(rowBackground)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            // Navigate to memo detail
            NotificationCenter.default.post(
                name: .init("NavigateToMemoDetail"),
                object: memo.id
            )
        }
    }

    private var rowBackground: Color {
        if isLinear {
            return isHovered ? Color.white.opacity(0.05) : Color.clear
        }
        return isHovered ? Theme.current.surfaceHover : Color.clear
    }

    private var memoTitle: String {
        if let title = memo.title, !title.isEmpty {
            return title
        } else if let transcription = memo.transcription, !transcription.isEmpty {
            return String(transcription.prefix(50))
        } else {
            return "Untitled Memo"
        }
    }

    private func formatTimeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)

        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            return "\(seconds / 60)m ago"
        } else if seconds < 86400 {
            return "\(seconds / 3600)h ago"
        } else {
            return "\(seconds / 86400)d ago"
        }
    }
}

// MARK: - Quick Action Button

private struct QuickActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    @State private var isHovered = false
    private let settings = SettingsManager.shared
    private var isLinear: Bool { settings.isLinearTheme }

    var body: some View {
        Button(action: action) {
            HStack(spacing: isLinear ? Spacing.md : Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: isLinear ? 22 : 20, weight: .medium))
                    .foregroundColor(isLinear ? LinearStyle.glowColor : .accentColor)
                    .frame(width: isLinear ? 36 : 32)

                VStack(alignment: .leading, spacing: isLinear ? 4 : 2) {
                    Text(title)
                        .font(isLinear ? Theme.current.fontBody : Theme.current.fontSM)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.current.foreground)

                    Text(subtitle)
                        .font(isLinear ? Theme.current.fontSM : Theme.current.fontXS)
                        .foregroundColor(isLinear ? Theme.current.foregroundSecondary : Theme.current.foregroundMuted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: isLinear ? 12 : 11, weight: .medium))
                    .foregroundColor(isLinear && isHovered ? LinearStyle.glowColor : Theme.current.foregroundMuted)
                    .opacity(isHovered ? 1 : 0.5)
            }
            .padding(isLinear ? Spacing.lg : Spacing.md)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(cardBorder, lineWidth: 1)
            )
            .shadow(
                color: isLinear && isHovered ? LinearStyle.glowColor.opacity(0.15) : Color.clear,
                radius: isLinear && isHovered ? 12 : 0,
                x: 0, y: 0
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private var cardBackground: Color {
        if isLinear {
            return isHovered ? Color(white: 0.06) : Color(white: 0.04)
        }
        return isHovered ? Theme.current.surfaceHover : Theme.current.surface1
    }

    private var cardBorder: Color {
        if isLinear {
            return isHovered ? LinearStyle.glowColor.opacity(0.3) : Color.white.opacity(0.08)
        }
        return Theme.current.divider
    }
}

// MARK: - Preview

#Preview {
    TalkieHomeView()
        .frame(width: 900, height: 700)
}
