//
//  UnifiedDashboard.swift
//  Talkie
//
//  Unified home dashboard combining memos, dictations, and activity
//

import SwiftUI
import CoreData
import Combine
import AppKit

// MARK: - Unified Activity Item

enum ActivityItemType {
    case memo
    case dictation
}

struct UnifiedActivityItem: Identifiable {
    let id: String
    let type: ActivityItemType
    let title: String
    let preview: String?
    let date: Date
    let appName: String?
    let appBundleID: String?
    let isSuccess: Bool

    // Original references
    var memo: VoiceMemo?
    var dictation: Dictation?
}

// MARK: - Unified Dashboard

struct UnifiedDashboard: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)],
        predicate: nil
    )
    private var allMemos: FetchedResults<VoiceMemo>

    // Singletons
    private let dictationStore = DictationStore.shared
    private let liveState = ServiceManager.shared.live
    private let serviceMonitor = ServiceManager.shared.engine
    private let syncManager = CloudKitSyncManager.shared

    // State
    @State private var unifiedActivity: [UnifiedActivityItem] = []
    @State private var activityData: [DayActivity] = []
    @State private var streak: Int = 0
    @State private var todayMemos: Int = 0
    @State private var todayDictations: Int = 0
    @State private var totalWords: Int = 0
    @State private var isLiveRunning: Bool = false
    @State private var serviceState: TalkieServiceState = .unknown
    @State private var pendingRetryCount: Int = 0

    private var todayTotal: Int { todayMemos + todayDictations }
    private var hasActivity: Bool { !unifiedActivity.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                header

                if hasActivity {
                    // Row 1: Streak + Today + Quick Stat
                    statsRow

                    // Row 2: Activity Heatmap + Quick Actions (side by side)
                    HStack(alignment: .top, spacing: 20) {
                        // Quick Actions (always visible, compact)
                        quickActionsCompact
                            .frame(width: 200)

                        // Activity Heatmap (if enough data)
                        if activityData.count > 7 {
                            activityHeatmap
                        }
                    }

                    // Row 3: Unified Recent Activity
                    recentActivitySection

                    // Row 4: System Status (compact)
                    systemStatusRow
                } else {
                    welcomeCard
                }

                Spacer(minLength: 40)
            }
            .padding(24)
        }
        .background(Theme.current.background)
        .onAppear {
            loadData()
            isLiveRunning = liveState.isRunning
            serviceState = serviceMonitor.state
            pendingRetryCount = LiveDatabase.countNeedsRetry()
        }
        .onChange(of: dictationStore.dictations.count) { _, _ in
            loadData()
            pendingRetryCount = LiveDatabase.countNeedsRetry()
        }
        .onChange(of: allMemos.count) { _, _ in
            loadData()
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            // Refresh pending count periodically in case cleared elsewhere
            let newCount = LiveDatabase.countNeedsRetry()
            if newCount != pendingRetryCount {
                pendingRetryCount = newCount
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DASHBOARD")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundColor(Theme.current.foregroundMuted)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Home")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Theme.current.foreground)

                if streak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: streak >= 7 ? "flame.fill" : "flame")
                            .foregroundColor(.orange)
                        Text("\(streak) day streak")
                            .foregroundColor(.orange)
                    }
                    .font(.system(size: 13, weight: .medium))
                }
            }
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 12) {
            // Today
            CompactStatCard(
                icon: "calendar",
                value: "\(todayTotal)",
                label: "Today",
                detail: todayTotal == 0 ? "Get started!" : "\(todayMemos) memos, \(todayDictations) dictations",
                color: todayTotal > 0 ? .green : Theme.current.foregroundMuted
            )

            // Total Memos
            CompactStatCard(
                icon: "doc.text.fill",
                value: formatNumber(allMemos.count),
                label: "Memos",
                detail: "Voice recordings",
                color: .blue
            )

            // Total Dictations
            CompactStatCard(
                icon: "waveform",
                value: formatNumber(dictationStore.dictations.count),
                label: "Dictations",
                detail: "Quick captures",
                color: .purple
            )

            // Words
            CompactStatCard(
                icon: "text.word.spacing",
                value: formatNumber(totalWords),
                label: "Words",
                detail: "Total transcribed",
                color: .cyan
            )
        }
    }

    // MARK: - Activity Heatmap

    private var activityHeatmap: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ACTIVITY")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundColor(Theme.current.foregroundMuted)

                Spacer()

                // Legend
                HStack(spacing: 4) {
                    Text("Less")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.current.foregroundMuted)

                    ForEach([0, 1, 2, 3, 4], id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(activityColor(for: level))
                            .frame(width: 10, height: 10)
                    }

                    Text("More")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.current.foregroundMuted)
                }
            }

            // Grid - 13 weeks (quarter view)
            ActivityHeatmapGrid(data: activityData)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.current.surface1)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Theme.current.divider, lineWidth: 1)
                )
        )
    }

    // MARK: - Recent Activity (Side by Side)

    private var recentActivitySection: some View {
        HStack(alignment: .top, spacing: 16) {
            // Recent Memos
            recentMemosCard

            // Recent Dictations
            recentDictationsCard
        }
    }

    private var recentMemosCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RECENT MEMOS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundColor(Theme.current.foregroundMuted)

                Spacer()

                Text("\(min(allMemos.count, 8)) latest")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            VStack(spacing: 0) {
                if allMemos.isEmpty {
                    emptyMemoState
                } else {
                    ForEach(Array(allMemos.prefix(8))) { memo in
                        MemoActivityRow(memo: memo) {
                            // Navigate to All Memos with this memo selected
                            NotificationCenter.default.post(
                                name: .init("NavigateToMemo"),
                                object: memo.id
                            )
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.current.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Theme.current.divider, lineWidth: 1)
                    )
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var recentDictationsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RECENT DICTATIONS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundColor(Theme.current.foregroundMuted)

                Spacer()

                Text("\(min(dictationStore.dictations.count, 8)) latest")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            VStack(spacing: 0) {
                if dictationStore.dictations.isEmpty {
                    emptyDictationState
                } else {
                    ForEach(Array(dictationStore.dictations.prefix(8))) { dictation in
                        DictationActivityRow(dictation: dictation) {
                            // Navigate to Live Recent with this dictation selected
                            NotificationCenter.default.post(
                                name: .init("NavigateToDictation"),
                                object: dictation.id
                            )
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.current.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Theme.current.divider, lineWidth: 1)
                    )
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyMemoState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 24))
                .foregroundColor(Theme.current.foregroundMuted)
            Text("No memos yet")
                .font(.system(size: 12))
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var emptyDictationState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 24))
                .foregroundColor(Theme.current.foregroundMuted)
            Text("No dictations yet")
                .font(.system(size: 12))
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Quick Actions (Compact - for sidebar)

    private var quickActionsCompact: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QUICK ACTIONS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundColor(Theme.current.foregroundMuted)

            VStack(spacing: 6) {
                CompactActionButton(icon: "mic.fill", title: "Record", color: .green) {
                    // Trigger recording
                }
                CompactActionButton(icon: "doc.badge.plus", title: "New Memo", color: .blue) {
                    // Create memo
                }
                CompactActionButton(icon: "wand.and.stars", title: "Workflows", color: .orange) {
                    NotificationCenter.default.post(name: .init("NavigateToWorkflows"), object: nil)
                }
                CompactActionButton(icon: "gear", title: "Settings", color: .secondary) {
                    NotificationCenter.default.post(name: .navigateToSettings, object: nil)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.current.surface1)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Theme.current.divider, lineWidth: 1)
                )
        )
    }

    // MARK: - Quick Actions (Full width - legacy)

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("QUICK ACTIONS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundColor(Theme.current.foregroundMuted)

            HStack(spacing: 12) {
                DashboardActionCard(
                    icon: "mic.fill",
                    title: "Record",
                    subtitle: "Start dictating",
                    color: .green
                ) {
                    // Trigger recording
                }

                DashboardActionCard(
                    icon: "doc.badge.plus",
                    title: "New Memo",
                    subtitle: "Create memo",
                    color: .blue
                ) {
                    // Create memo
                }

                DashboardActionCard(
                    icon: "wand.and.stars",
                    title: "Workflows",
                    subtitle: "Automate",
                    color: .orange
                ) {
                    NotificationCenter.default.post(name: .init("NavigateToWorkflows"), object: nil)
                }

                DashboardActionCard(
                    icon: "gear",
                    title: "Settings",
                    subtitle: "Configure",
                    color: .gray
                ) {
                    NotificationCenter.default.post(name: .navigateToSettings, object: nil)
                }
            }
        }
    }

    // MARK: - System Status (Compact)

    private var systemStatusRow: some View {
        HStack(spacing: 16) {
            // Live Dictation
            SystemStatusPill(
                icon: "mic.circle.fill",
                label: "Live",
                isActive: isLiveRunning
            )

            // AI Engine
            SystemStatusPill(
                icon: "cpu",
                label: "AI",
                isActive: serviceState == .running
            )

            // Cloud Sync
            SystemStatusPill(
                icon: "icloud.fill",
                label: "Sync",
                isActive: syncManager.lastSyncDate != nil
            )

            // Pending transcriptions - show only when there are items
            if pendingRetryCount > 0 {
                Button(action: handlePendingTap) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text("\(pendingRetryCount) pending")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.orange))
                }
                .buttonStyle(.plain)
                .help("Click to retry, Option+click to dismiss")
            }

            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func handlePendingTap() {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.option) {
            // Option+click: Clear/dismiss pending items
            clearPendingTranscriptions()
        } else {
            // Regular click: Trigger retry via notification to TalkieLive
            // Since we can't directly call TalkieLive's TranscriptionRetryManager,
            // we'll just refresh and let the engine auto-retry on reconnect
            NotificationCenter.default.post(name: .init("RetryPendingTranscriptions"), object: nil)
            // For now, just refresh the count
            pendingRetryCount = LiveDatabase.countNeedsRetry()
        }
    }

    private func clearPendingTranscriptions() {
        // Mark all pending items as dismissed
        let pending = LiveDatabase.fetchNeedsRetry()
        for item in pending {
            LiveDatabase.markTranscriptionFailed(id: item.id, error: "Dismissed from Talkie")
        }
        pendingRetryCount = 0
    }

    // MARK: - Welcome Card

    private var welcomeCard: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            VStack(spacing: 8) {
                Text("Welcome to Talkie")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Theme.current.foreground)

                Text("Your voice-powered productivity companion.\nPress your hotkey to start dictating anywhere.")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 16) {
                Button("Set Up Hotkey") {
                    NotificationCenter.default.post(name: .navigateToSettings, object: nil)
                }
                .buttonStyle(.borderedProminent)

                Button("Learn More") {
                    // Show onboarding
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(48)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.current.surface1)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Theme.current.divider, lineWidth: 1)
                )
        )
    }

    // MARK: - Data Loading

    private func loadData() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Build unified activity from memos + dictations
        var items: [UnifiedActivityItem] = []

        // Add memos
        for memo in allMemos {
            guard let createdAt = memo.createdAt else { continue }
            items.append(UnifiedActivityItem(
                id: memo.id?.uuidString ?? UUID().uuidString,
                type: .memo,
                title: memo.title ?? "Untitled Memo",
                preview: memo.transcription?.prefix(100).description,
                date: createdAt,
                appName: nil,
                appBundleID: nil,
                isSuccess: true,
                memo: memo,
                dictation: nil
            ))
        }

        // Add dictations
        for dictation in dictationStore.dictations {
            items.append(UnifiedActivityItem(
                id: dictation.id.uuidString,
                type: .dictation,
                title: dictation.metadata.activeAppName ?? "Dictation",
                preview: dictation.text.isEmpty ? nil : String(dictation.text.prefix(100)),
                date: dictation.timestamp,
                appName: dictation.metadata.activeAppName,
                appBundleID: dictation.metadata.activeAppBundleID,
                isSuccess: !dictation.text.isEmpty,
                memo: nil,
                dictation: dictation
            ))
        }

        // Sort by date descending
        unifiedActivity = items.sorted { $0.date > $1.date }

        // Calculate stats
        todayMemos = allMemos.filter { memo in
            guard let createdAt = memo.createdAt else { return false }
            return calendar.isDateInToday(createdAt)
        }.count

        todayDictations = dictationStore.dictations.filter {
            calendar.isDateInToday($0.timestamp)
        }.count

        totalWords = dictationStore.dictations.reduce(0) { $0 + $1.wordCount }
            + allMemos.reduce(0) { $0 + ($1.transcription?.split(separator: " ").count ?? 0) }

        // Calculate streak
        streak = calculateStreak()

        // Build activity heatmap data
        activityData = buildActivityData()
    }

    private func calculateStreak() -> Int {
        let calendar = Calendar.current
        var currentStreak = 0
        var checkDate = calendar.startOfDay(for: Date())

        // Get all activity dates
        var activityDates = Set<Date>()

        for memo in allMemos {
            if let date = memo.createdAt {
                activityDates.insert(calendar.startOfDay(for: date))
            }
        }

        for dictation in dictationStore.dictations {
            activityDates.insert(calendar.startOfDay(for: dictation.timestamp))
        }

        // Count consecutive days
        while activityDates.contains(checkDate) {
            currentStreak += 1
            guard let prevDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prevDay
        }

        return currentStreak
    }

    private func buildActivityData() -> [DayActivity] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weeksToShow = 13

        // Count activity per day
        var countByDay: [Date: Int] = [:]

        for memo in allMemos {
            if let date = memo.createdAt {
                let day = calendar.startOfDay(for: date)
                countByDay[day, default: 0] += 1
            }
        }

        for dictation in dictationStore.dictations {
            let day = calendar.startOfDay(for: dictation.timestamp)
            countByDay[day, default: 0] += 1
        }

        let maxCount = max(countByDay.values.max() ?? 1, 1)

        // Build 13 weeks of data
        let todayWeekday = calendar.component(.weekday, from: today)
        let daysBack = (weeksToShow - 1) * 7 + (todayWeekday - 1)
        guard let startDate = calendar.date(byAdding: .day, value: -daysBack, to: today) else { return [] }

        var data: [DayActivity] = []
        var currentDate = startDate

        while currentDate <= today {
            let count = countByDay[currentDate] ?? 0
            let level = ActivityLevel.from(count: count, max: maxCount)
            data.append(DayActivity(date: currentDate, count: count, level: level))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        return data
    }

    private func activityColor(for level: Int) -> Color {
        switch level {
        case 0: return TalkieTheme.surfaceCard
        case 1: return Color.green.opacity(0.3)
        case 2: return Color.green.opacity(0.5)
        case 3: return Color.green.opacity(0.7)
        default: return Color.green
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1000 {
            return String(format: "%.1fk", Double(n) / 1000)
        }
        return "\(n)"
    }
}

// MARK: - Memo Activity Row

struct MemoActivityRow: View {
    let memo: VoiceMemo
    var onSelect: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        Button(action: { onSelect?() }) {
        HStack(spacing: 10) {
            // Provenance icon (where it came from) - neutral color, icon is enough
            Image(systemName: memo.source.icon)
                .font(.system(size: 12))
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(width: 18)

            // Title/Preview
            Text(memoTitle)
                .font(.system(size: 12))
                .foregroundColor(Theme.current.foreground)
                .lineLimit(1)

            Spacer()

            // Duration (more useful than source badge)
            if memo.duration > 0 {
                Text(formatDuration(memo.duration))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            // Time ago
            if let date = memo.createdAt {
                Text(timeAgo(from: date))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            if isHovered {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.current.foregroundMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Theme.current.surfaceHover : Color.clear)
        )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return String(format: "%d:%02d", mins, secs)
        }
        return String(format: "0:%02d", secs)
    }

    private var memoTitle: String {
        if let title = memo.title, !title.isEmpty {
            return title
        } else if let transcription = memo.transcription, !transcription.isEmpty {
            return String(transcription.prefix(60))
        }
        return "Untitled Memo"
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }
}

// MARK: - Dictation Activity Row

struct DictationActivityRow: View {
    let dictation: Dictation
    var onSelect: (() -> Void)?

    @State private var isHovered = false

    private var isSuccess: Bool {
        !dictation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Button(action: { onSelect?() }) {
        HStack(spacing: 10) {
            // Status dot
            Circle()
                .fill(isSuccess ? Color.green : Color.red.opacity(0.7))
                .frame(width: 6, height: 6)

            // App icon
            if let bundleID = dictation.metadata.activeAppBundleID {
                AppIconView(bundleIdentifier: bundleID, size: 18)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "app")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .frame(width: 18, height: 18)
            }

            // Text preview
            Text(dictation.text.isEmpty ? "No transcription" : String(dictation.text.prefix(60)))
                .font(.system(size: 12))
                .foregroundColor(Theme.current.foreground)
                .lineLimit(1)

            Spacer()

            // Time ago
            Text(timeAgo(from: dictation.timestamp))
                .font(.system(size: 11))
                .foregroundColor(Theme.current.foregroundMuted)

            if isHovered {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.current.foregroundMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Theme.current.surfaceHover : Color.clear)
        )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }
}

// MARK: - Compact Stat Card

struct CompactStatCard: View {
    let icon: String
    let value: String
    let label: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(color)

                Spacer()
            }

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(Theme.current.foreground)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.current.foregroundSecondary)

                Text(detail)
                    .font(.system(size: 9))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.current.surface1)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Theme.current.divider, lineWidth: 1)
                )
        )
    }
}

// MARK: - Unified Activity Row

struct UnifiedActivityRow: View {
    let item: UnifiedActivityItem

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Type indicator
            Circle()
                .fill(item.isSuccess ? (item.type == .memo ? Color.blue : Color.green) : Color.red.opacity(0.7))
                .frame(width: 8, height: 8)

            // Icon
            if item.type == .memo {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                    .frame(width: 20)
            } else if let bundleID = item.appBundleID {
                AppIconView(bundleIdentifier: bundleID, size: 20)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 14))
                    .foregroundColor(.purple)
                    .frame(width: 20)
            }

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview ?? item.title)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.current.foreground)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(item.type == .memo ? "Memo" : "Dictation")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(item.type == .memo ? .blue : .purple)

                    if let appName = item.appName {
                        Text("in \(appName)")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                }
            }

            Spacer()

            // Time ago
            Text(timeAgo(from: item.date))
                .font(.system(size: 11))
                .foregroundColor(Theme.current.foregroundMuted)

            if isHovered {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.current.foregroundMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Theme.current.surfaceHover : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }
}

// MARK: - Dashboard Action Card

struct DashboardActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(color)

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.current.foreground)

                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(Theme.current.foregroundMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? color.opacity(0.1) : Theme.current.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isHovered ? color.opacity(0.3) : Theme.current.divider, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - System Status Pill

struct SystemStatusPill: View {
    let icon: String
    let label: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? Color.green : Color.red.opacity(0.7))
                .frame(width: 6, height: 6)

            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(Theme.current.foregroundSecondary)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.current.foregroundSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Theme.current.surface1)
                .overlay(
                    Capsule()
                        .strokeBorder(Theme.current.divider, lineWidth: 1)
                )
        )
    }
}

// MARK: - Activity Heatmap Grid

struct ActivityHeatmapGrid: View {
    let data: [DayActivity]

    private let cellSize: CGFloat = 12
    private let spacing: CGFloat = 2
    private let weeksToShow = 13

    var body: some View {
        let grid = buildGrid()

        HStack(alignment: .top, spacing: spacing) {
            // Day labels
            VStack(alignment: .trailing, spacing: spacing) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 8))
                        .foregroundColor(Theme.current.foregroundMuted)
                        .frame(height: cellSize)
                }
            }
            .frame(width: 12)

            // Grid
            HStack(alignment: .top, spacing: spacing) {
                ForEach(0..<weeksToShow, id: \.self) { weekIndex in
                    if weekIndex < grid.count {
                        VStack(spacing: spacing) {
                            ForEach(0..<7, id: \.self) { dayIndex in
                                if dayIndex < grid[weekIndex].count {
                                    let day = grid[weekIndex][dayIndex]
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(day.count < 0 ? Color.clear : day.level.color)
                                        .frame(width: cellSize, height: cellSize)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(height: 7 * cellSize + 6 * spacing)
    }

    private func buildGrid() -> [[DayActivity]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today)

        var dataByDate: [Date: DayActivity] = [:]
        for day in data {
            dataByDate[calendar.startOfDay(for: day.date)] = day
        }

        let daysBack = (weeksToShow - 1) * 7 + (todayWeekday - 1)
        guard let startDate = calendar.date(byAdding: .day, value: -daysBack, to: today) else { return [] }

        var grid: [[DayActivity]] = []
        var currentDate = startDate

        for _ in 0..<weeksToShow {
            var week: [DayActivity] = []
            for _ in 0..<7 {
                if currentDate <= today {
                    if let existing = dataByDate[currentDate] {
                        week.append(existing)
                    } else {
                        week.append(DayActivity(date: currentDate, count: 0, level: .none))
                    }
                } else {
                    week.append(DayActivity(date: currentDate, count: -1, level: .none))
                }
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
            }
            grid.append(week)
        }

        return grid
    }
}

// MARK: - Compact Action Button

private struct CompactActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(color)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.current.foreground)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .opacity(isHovered ? 1 : 0.5)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Theme.current.surfaceHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview

#Preview {
    UnifiedDashboard()
        .frame(width: 800, height: 700)
}
