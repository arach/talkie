//
//  TalkieHomeView.swift
//  Talkie macOS
//
//  Main home/dashboard view for Talkie app
//  Shows quick stats, recent activity, quick actions, and service health
//

import SwiftUI
import CoreData

struct TalkieHomeView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)],
        predicate: nil
    )
    private var allMemos: FetchedResults<VoiceMemo>

    // Singleton references - use let for @Observable singletons (not @State which breaks observation)
    private let syncManager = CloudKitSyncManager.shared
    private let liveState = ServiceManager.shared.live
    private let serviceMonitor = ServiceManager.shared.engine
    private let eventManager = SystemEventManager.shared
    private let dictationStore = DictationStore.shared

    // Cached state - only updates when specific properties change
    @State private var recentMemos: [VoiceMemo] = []
    @State private var recentDictations: [Utterance] = []
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
        .onAppear {
            loadRecentMemos()
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
        .onChange(of: allMemos.count) { _, _ in
            // Reload recent memos when count changes (e.g., new memo added)
            loadRecentMemos()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("HOME")
                .font(.system(size: 10, weight: .bold))
                .tracking(Tracking.wide)
                .foregroundColor(Theme.current.foregroundMuted)

            Text("Dashboard")
                .font(.system(size: 24, weight: .bold))
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
                    value: "\(allMemos.count)",
                    label: "Total Memos",
                    color: .blue
                )

                StatCard(
                    icon: "waveform",
                    value: totalRecordingTime,
                    label: "Recording Time",
                    color: .purple
                )

                StatCard(
                    icon: "calendar",
                    value: "\(memosThisWeek)",
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
        VStack(alignment: .leading, spacing: Spacing.sm) {
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
                    .fill(Theme.current.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(Theme.current.divider, lineWidth: 1)
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
                    subtitle: "\(allMemos.count) total",
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
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(Tracking.wide)
            .foregroundColor(Theme.current.foregroundMuted)
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

    private var totalRecordingTime: String {
        let total = allMemos.reduce(0.0) { $0 + $1.duration }
        return formatDuration(total)
    }

    private var memosThisWeek: Int {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return allMemos.filter { memo in
            guard let createdAt = memo.createdAt else { return false }
            return createdAt >= weekAgo
        }.count
    }

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

    private func loadRecentMemos() {
        recentMemos = Array(allMemos.prefix(10))
    }

    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(Int(seconds))s"
        }
    }

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

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(Theme.current.foreground)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.current.foregroundMuted)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(isHovered ? Theme.current.surfaceHover : Theme.current.surface1)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .strokeBorder(color.opacity(0.2), lineWidth: 1)
                )
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Recent Memo Row

struct RecentMemoRow: View {
    let memo: VoiceMemo

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Icon
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.blue)
                .frame(width: 20)

            // Title or transcription preview
            Text(memoTitle)
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foreground)
                .lineLimit(1)

            Spacer()

            // Time ago
            TimelineView(.periodic(from: .now, by: 60)) { _ in
            if let createdAt = memo.createdAt {
                RelativeTimeLabel(date: createdAt, formatter: formatTimeAgo)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            } else {
                Text("")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }
            }

            // Chevron on hover
            if isHovered {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.current.foregroundMuted)
            }
        }
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(isHovered ? Theme.current.surfaceHover : Color.clear)
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.current.fontSM)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.current.foreground)

                    Text(subtitle)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .opacity(isHovered ? 1 : 0.5)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(isHovered ? Theme.current.surfaceHover : Theme.current.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(Theme.current.divider, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview

#Preview {
    TalkieHomeView()
        .frame(width: 900, height: 700)
}
