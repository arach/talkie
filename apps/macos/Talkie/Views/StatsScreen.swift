//
//  StatsScreen.swift
//  Talkie
//
//  Stats view for dictations - queries SQL directly for fast, accurate counts
//

import SwiftUI
import TalkieKit

struct StatsScreen: View {
    /// Callback when user wants to see all dictations
    var onSelectDictation: ((Dictation?) -> Void)?

    private let dictationStore = DictationStore.shared
    private let settings = SettingsManager.shared
    private let recordingRepo = TalkieObjectRepository()

    // Stats queried directly from SQL (fast aggregates)
    @State private var todayCount = 0
    @State private var weekCount = 0
    @State private var totalWords = 0
    @State private var streak = 0
    @State private var topApps: [(name: String, bundleID: String?, count: Int)] = []

    // Storage stats
    @State private var totalDictations = 0
    @State private var deviceStorageBytes: Int64 = 0
    @State private var workflowRunsCount = 0

    var body: some View {
        TalkiePage("Stats", style: .pageOnly) {
            // Overview stats
            quickStatsSection

            // Storage & Files
            storageSection

            // Recent Dictations
            recentDictationsSection

            // Top Apps
            if !topApps.isEmpty {
                topAppsSection
            }
        }
        .id("dictation-stats-\(settings.currentTheme?.rawValue ?? "default")")
        .task {
            await loadStats()
            loadStorageStats()
            dictationStore.refresh()
        }
        .onAppear {
            Task {
                await loadStats()
                loadStorageStats()
                dictationStore.refresh()
            }
        }
    }

    /// Load stats directly from SQL (fast aggregates, no caching layer)
    private func loadStats() async {
        do {
            async let today = recordingRepo.countRecordingsToday(type: .dictation)
            async let week = recordingRepo.countDictationsThisWeek()
            async let words = recordingRepo.totalDictationWords()
            async let streakVal = recordingRepo.calculateDictationStreak()
            async let apps = recordingRepo.topDictationApps(limit: 5)

            let results = try await (today, week, words, streakVal, apps)
            await MainActor.run {
                todayCount = results.0
                weekCount = results.1
                totalWords = results.2
                streak = results.3
                topApps = results.4
            }
        } catch {
            print("StatsScreen.loadStats error: \(error)")
        }
    }

    // MARK: - Overview

    private var quickStatsSection: some View {
        ContentSection("Overview") {
            HStack(spacing: Spacing.md) {
                StatCard(
                    icon: "flame.fill",
                    value: "\(streak)",
                    label: "Day Streak",
                    color: .orange
                )

                StatCard(
                    icon: "calendar.badge.clock",
                    value: "\(todayCount)",
                    label: "Today",
                    color: .blue
                )

                StatCard(
                    icon: "calendar",
                    value: "\(weekCount)",
                    label: "This Week",
                    color: .green
                )

                StatCard(
                    icon: "text.word.spacing",
                    value: formatWords(totalWords),
                    label: "Total Words",
                    color: .purple
                )
            }
        }
    }

    // MARK: - Recent Dictations

    private var recentDictationsSection: some View {
        let isTechnical = settings.isTechnicalTheme
        let recentDictations = Array(dictationStore.dictations.prefix(5))

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                SectionTitle(title: "Recent Dictations")
                Spacer()
                if !recentDictations.isEmpty {
                    Button {
                        onSelectDictation?(nil)
                    } label: {
                        Text("View All")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: 0) {
                if recentDictations.isEmpty {
                    emptyStateView
                } else {
                    ForEach(recentDictations) { dictation in
                        RecentDictationRow(dictation: dictation) {
                            onSelectDictation?(dictation)
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(isTechnical ? Color(white: 0.04) : Theme.current.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(isTechnical ? Theme.current.foreground.opacity(0.08) : Theme.current.divider, lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Top Apps

    private var topAppsSection: some View {
        let isTechnical = settings.isTechnicalTheme

        return ContentSection("Top Apps") {
            VStack(spacing: 0) {
                ForEach(Array(topApps.enumerated()), id: \.offset) { index, app in
                    TopAppRow(
                        rank: index + 1,
                        name: app.name,
                        bundleID: app.bundleID,
                        count: app.count
                    )
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(isTechnical ? Color(white: 0.04) : Theme.current.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(isTechnical ? Theme.current.foreground.opacity(0.08) : Theme.current.divider, lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Helpers

    private var emptyStateView: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 32))
                .foregroundColor(Theme.current.foregroundMuted)

            Text("No dictations yet")
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundSecondary)

            Text("Press your hotkey to start dictating")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }

    private func formatNumber(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private func formatWords(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000)
        }
        return "\(count)"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Storage Section

    private var storageSection: some View {
        ContentSection("Storage & Activity") {
            HStack(spacing: Spacing.md) {
                StatCard(
                    icon: "doc.fill",
                    value: formatNumber(totalDictations),
                    label: "Dictations",
                    color: .blue
                )

                StatCard(
                    icon: "internaldrive",
                    value: formatBytes(deviceStorageBytes),
                    label: "Device Storage",
                    color: .gray
                )

                StatCard(
                    icon: "bolt.fill",
                    value: formatNumber(workflowRunsCount),
                    label: "Actions Ran",
                    color: .orange
                )
            }
        }
    }

    // MARK: - Data Loading

    private func loadStorageStats() {
        // Count total dictations
        Task {
            let count = try? await recordingRepo.countDictations()
            await MainActor.run {
                totalDictations = count ?? 0
            }
        }

        // Calculate storage used by audio files
        Task {
            let bytes = await calculateStorageUsed()
            await MainActor.run {
                deviceStorageBytes = bytes
            }
        }

        // Count workflow runs
        Task {
            let count = await countWorkflowRuns()
            await MainActor.run {
                workflowRunsCount = count
            }
        }
    }

    private func calculateStorageUsed() async -> Int64 {
        // Get audio storage directory
        guard let audioDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Talkie")
            .appendingPathComponent("Audio") else {
            return 0
        }

        var totalSize: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: audioDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
            }
        }
        return totalSize
    }

    private func countWorkflowRuns() async -> Int {
        do {
            let db = try await DatabaseManager.shared.databaseWhenReady()
            return try await db.read { db in
                try WorkflowRunModel.fetchCount(db)
            }
        } catch {
            return 0
        }
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color  // kept for compatibility but using neutral colors

    @State private var isHovered = false
    private let settings = SettingsManager.shared
    private var isTechnical: Bool { settings.isTechnicalTheme }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            // Icon - neutral color
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.current.foregroundSecondary)

            // Value - New York serif (light weight via theme)
            Text(value)
                .font(settings.fontStat)
                .foregroundColor(Theme.current.foreground)

            // Label
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.current.foregroundSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .background(
            ZStack {
                // Base fill
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(isTechnical ? Color(white: 0.04) : Theme.current.surface1)

                // Subtle glass shimmer on hover
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isHovered ? 0.08 : 0.03),
                                Color.white.opacity(0.01),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Border
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .strokeBorder(
                        Theme.current.border.opacity(isHovered ? 0.2 : 0.08),
                        lineWidth: 1
                    )
            }
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Recent Dictation Row

private struct RecentDictationRow: View {
    let dictation: Dictation
    let onTap: () -> Void

    @State private var isHovered = false
    private let settings = SettingsManager.shared
    private var isTechnical: Bool { settings.isTechnicalTheme }

    var body: some View {
        HStack(spacing: isTechnical ? Spacing.md : Spacing.sm) {
            // App icon or default
            appIcon
                .frame(width: isTechnical ? 24 : 20, height: isTechnical ? 24 : 20)

            // Text preview
            Text(dictation.text.prefix(50) + (dictation.text.count > 50 ? "..." : ""))
                .font(isTechnical ? Theme.current.fontBody : Theme.current.fontSM)
                .foregroundColor(Theme.current.foreground)
                .lineLimit(1)

            Spacer()

            // Time ago
            Text(formatTimeAgo(dictation.timestamp))
                .font(isTechnical ? Theme.current.fontSM : Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)

            // Chevron on hover
            if isHovered {
                Image(systemName: "chevron.right")
                    .font(.system(size: isTechnical ? 10 : 9, weight: .medium))
                    .foregroundColor(Theme.current.foregroundMuted)
            }
        }
        .padding(.vertical, isTechnical ? Spacing.sm : Spacing.xs)
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
            onTap()
        }
    }

    private var rowBackground: Color {
        if isTechnical {
            return isHovered ? Theme.current.foreground.opacity(0.05) : Color.clear
        }
        return isHovered ? Theme.current.surfaceHover : Color.clear
    }

    @ViewBuilder
    private var appIcon: some View {
        if let bundleID = dictation.metadata.activeAppBundleID,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let icon = NSWorkspace.shared.icon(forFile: appURL.path) as NSImage? {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: isTechnical ? 16 : 12))
                .foregroundColor(isTechnical ? TechnicalStyle.accent : .blue)
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

// MARK: - Top App Row

private struct TopAppRow: View {
    let rank: Int
    let name: String
    let bundleID: String?
    let count: Int

    @State private var isHovered = false
    private let settings = SettingsManager.shared
    private var isTechnical: Bool { settings.isTechnicalTheme }

    var body: some View {
        HStack(spacing: isTechnical ? Spacing.md : Spacing.sm) {
            // Rank
            Text("\(rank)")
                .font(.system(size: isTechnical ? 14 : 12, weight: .bold, design: .rounded))
                .foregroundColor(rankColor)
                .frame(width: 20)

            // App icon
            appIcon
                .frame(width: isTechnical ? 24 : 20, height: isTechnical ? 24 : 20)

            // App name
            Text(name)
                .font(isTechnical ? Theme.current.fontBody : Theme.current.fontSM)
                .foregroundColor(Theme.current.foreground)

            Spacer()

            // Count
            Text("\(count) dictations")
                .font(isTechnical ? Theme.current.fontSM : Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .padding(.vertical, isTechnical ? Spacing.sm : Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(isHovered ? (isTechnical ? Theme.current.foreground.opacity(0.05) : Theme.current.surfaceHover) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private var rankColor: Color {
        Theme.current.foregroundMuted
    }

    @ViewBuilder
    private var appIcon: some View {
        if let bundleID = bundleID,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let icon = NSWorkspace.shared.icon(forFile: appURL.path) as NSImage? {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: isTechnical ? 16 : 12))
                .foregroundColor(Theme.current.foregroundMuted)
        }
    }
}

// MARK: - Preview

#Preview {
    StatsScreen()
        .frame(width: 800, height: 600)
}

// MARK: - Backwards Compatibility Alias
typealias DictationStatsView = StatsScreen
