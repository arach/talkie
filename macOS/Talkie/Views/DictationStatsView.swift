//
//  DictationStatsView.swift
//  Talkie
//
//  Stats view for dictations - queries SQL directly for fast, accurate counts
//

import SwiftUI

struct DictationStatsView: View {
    /// Callback when user wants to see all dictations
    var onSelectDictation: ((Dictation?) -> Void)?

    private let dictationStore = DictationStore.shared
    private let settings = SettingsManager.shared

    // Stats queried directly from SQL (fast aggregates)
    @State private var todayCount = 0
    @State private var weekCount = 0
    @State private var totalWords = 0
    @State private var streak = 0
    @State private var topApps: [(name: String, bundleID: String?, count: Int)] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Header
                headerView

                // Quick Stats
                quickStatsSection

                // Recent Dictations
                recentDictationsSection

                // Top Apps
                if !topApps.isEmpty {
                    topAppsSection
                }

                Spacer(minLength: Spacing.xxl)
            }
            .padding(Spacing.lg)
        }
        .background(Theme.current.background)
        .id("dictation-stats-\(settings.currentTheme?.rawValue ?? "default")")
        .onAppear {
            loadStats()
            dictationStore.refresh()
        }
    }

    /// Load stats directly from SQL (fast aggregates, no caching layer)
    private func loadStats() {
        todayCount = LiveDatabase.countToday()
        weekCount = LiveDatabase.countWeek()
        totalWords = LiveDatabase.totalWords()
        streak = LiveDatabase.calculateStreak()
        topApps = LiveDatabase.topApps(limit: 5)
        print("DictationStatsView.loadStats: today=\(todayCount), week=\(weekCount), words=\(totalWords), streak=\(streak)")
    }

    // MARK: - Header

    private var headerView: some View {
        let isLinear = settings.isLinearTheme

        return VStack(alignment: .leading, spacing: isLinear ? 0 : Spacing.xs) {
            if !isLinear {
                Text("VOICE STATS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(Tracking.wide)
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            Text("Dictation Stats")
                .font(.system(size: isLinear ? 28 : 24, weight: isLinear ? .semibold : .bold))
                .foregroundColor(Theme.current.foreground)
        }
    }

    // MARK: - Quick Stats

    private var quickStatsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Quick Stats")

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
        let isLinear = settings.isLinearTheme
        let recentDictations = Array(dictationStore.dictations.prefix(5))

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                sectionHeader("Recent Dictations")
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
                    .fill(isLinear ? Color(white: 0.04) : Theme.current.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(isLinear ? Color.white.opacity(0.08) : Theme.current.divider, lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Top Apps

    private var topAppsSection: some View {
        let isLinear = settings.isLinearTheme

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Top Apps")

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
                    .fill(isLinear ? Color(white: 0.04) : Theme.current.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(isLinear ? Color.white.opacity(0.08) : Theme.current.divider, lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        let isLinear = settings.isLinearTheme

        return Text(isLinear ? title : title.uppercased())
            .font(.system(size: isLinear ? 11 : 10, weight: isLinear ? .medium : .bold))
            .tracking(isLinear ? 0 : Tracking.wide)
            .foregroundColor(isLinear ? Theme.current.foregroundSecondary : Theme.current.foregroundMuted)
    }

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

    private func formatWords(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000)
        }
        return "\(count)"
    }
}

// MARK: - Recent Dictation Row

private struct RecentDictationRow: View {
    let dictation: Dictation
    let onTap: () -> Void

    @State private var isHovered = false
    private let settings = SettingsManager.shared
    private var isLinear: Bool { settings.isLinearTheme }

    var body: some View {
        HStack(spacing: isLinear ? Spacing.md : Spacing.sm) {
            // App icon or default
            appIcon
                .frame(width: isLinear ? 24 : 20, height: isLinear ? 24 : 20)

            // Text preview
            Text(dictation.text.prefix(50) + (dictation.text.count > 50 ? "..." : ""))
                .font(isLinear ? Theme.current.fontBody : Theme.current.fontSM)
                .foregroundColor(Theme.current.foreground)
                .lineLimit(1)

            Spacer()

            // Time ago
            Text(formatTimeAgo(dictation.timestamp))
                .font(isLinear ? Theme.current.fontSM : Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)

            // Chevron on hover
            if isHovered {
                Image(systemName: "chevron.right")
                    .font(.system(size: isLinear ? 10 : 9, weight: .medium))
                    .foregroundColor(Theme.current.foregroundMuted)
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
            onTap()
        }
    }

    private var rowBackground: Color {
        if isLinear {
            return isHovered ? Color.white.opacity(0.05) : Color.clear
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
                .font(.system(size: isLinear ? 16 : 12))
                .foregroundColor(isLinear ? LinearStyle.glowColor : .blue)
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
    private var isLinear: Bool { settings.isLinearTheme }

    var body: some View {
        HStack(spacing: isLinear ? Spacing.md : Spacing.sm) {
            // Rank
            Text("\(rank)")
                .font(.system(size: isLinear ? 14 : 12, weight: .bold, design: .rounded))
                .foregroundColor(rankColor)
                .frame(width: 20)

            // App icon
            appIcon
                .frame(width: isLinear ? 24 : 20, height: isLinear ? 24 : 20)

            // App name
            Text(name)
                .font(isLinear ? Theme.current.fontBody : Theme.current.fontSM)
                .foregroundColor(Theme.current.foreground)

            Spacer()

            // Count
            Text("\(count) dictations")
                .font(isLinear ? Theme.current.fontSM : Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .padding(.vertical, isLinear ? Spacing.sm : Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(isHovered ? (isLinear ? Color.white.opacity(0.05) : Theme.current.surfaceHover) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private var rankColor: Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return Theme.current.foregroundMuted
        }
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
                .font(.system(size: isLinear ? 16 : 12))
                .foregroundColor(Theme.current.foregroundMuted)
        }
    }
}

// MARK: - Preview

#Preview {
    DictationStatsView()
        .frame(width: 800, height: 600)
}
