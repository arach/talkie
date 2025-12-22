//
//  HomeView.swift
//  TalkieLive
//
//  Home dashboard with GitHub-style activity timeline
//

import SwiftUI

// MARK: - Home View

struct HomeView: View {
    @ObservedObject private var store = DictationStore.shared
    @State private var activityData: [DayActivity] = []
    @State private var stats = HomeStats()

    #if DEBUG
    @State private var debugActivityLevel: ActivityViewLevel? = nil
    #endif

    // Navigation callbacks
    var onSelectUtterance: ((Utterance) -> Void)?
    var onSelectApp: ((String, String?) -> Void)?  // (appName, bundleID)

    private var activityLevel: ActivityViewLevel {
        #if DEBUG
        return debugActivityLevel ?? ActivityViewLevel.from(daysWithActivity: stats.daysWithActivity)
        #else
        return ActivityViewLevel.from(daysWithActivity: stats.daysWithActivity)
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            let containerWidth = max(geometry.size.width, 320)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LIVE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.5)
                            .foregroundColor(TalkieTheme.textTertiary)

                        Text("Home")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(TalkieTheme.textPrimary)
                    }
                    .padding(.horizontal, GridLayout.padding)
                    .padding(.top, 20)

                    // Row 1: Insight (2 slots) | Streak (1 slot) | Today (1 slot)
                    HStack(spacing: GridLayout.gutter) {
                        InsightCard(insight: stats.insight)
                            .frame(width: GridLayout.width(slots: 2, in: containerWidth))

                        StreakCard(streak: stats.streak)
                            .frame(width: GridLayout.width(slots: 1, in: containerWidth))

                        TodayCard(count: stats.todayCount)
                            .frame(width: GridLayout.width(slots: 1, in: containerWidth))
                    }
                    .padding(.horizontal, GridLayout.padding)

                    // Row 2: Recent (2 slots) | Top Apps (2 slots)
                    HStack(alignment: .top, spacing: GridLayout.gutter) {
                        RecentActivityCard(
                            utterances: Array(store.utterances.prefix(5)),
                            onSelectUtterance: onSelectUtterance
                        )
                        .frame(width: GridLayout.width(slots: 2, in: containerWidth))

                        TopAppsCard(apps: stats.topApps, onSelectApp: onSelectApp)
                            .frame(width: GridLayout.width(slots: 2, in: containerWidth))
                    }
                    .padding(.horizontal, GridLayout.padding)

                    // Row 3: Activity (2-3 slots) | Stats (1 slot)
                    HStack(alignment: .top, spacing: GridLayout.gutter) {
                        AdaptiveActivityCard(
                            data: activityData,
                            stats: stats,
                            level: activityLevel,
                            debugBinding: {
                                #if DEBUG
                                return Binding(
                                    get: { debugActivityLevel ?? activityLevel },
                                    set: { debugActivityLevel = $0 }
                                )
                                #else
                                return nil
                                #endif
                            }(),
                            onResetDebug: {
                                #if DEBUG
                                debugActivityLevel = nil
                                #endif
                            }
                        )
                        .frame(width: GridLayout.width(slots: activityLevel.columns, in: containerWidth))

                        // Stats column (always show - slot 3 for quarterly, slot 4 for yearly)
                        CumulativeStatsCard(stats: stats)
                            .frame(width: GridLayout.width(slots: 1, in: containerWidth))
                    }
                    .padding(.horizontal, GridLayout.padding)

                    Spacer(minLength: 40)
                }
            }
        }
        .background(TalkieTheme.surface)
        .onAppear {
            loadActivityData()
        }
        .onChange(of: store.utterances.count) { _, _ in
            loadActivityData()
        }
    }

    private func loadActivityData() {
        let utterances = store.utterances
        let calendar = Calendar.current

        // Calculate unique days with activity
        var uniqueDays = Set<Date>()
        var earliestDate: Date?
        for u in utterances {
            let day = calendar.startOfDay(for: u.timestamp)
            uniqueDays.insert(day)
            if earliestDate == nil || day < earliestDate! {
                earliestDate = day
            }
        }

        // Calculate stats
        stats = HomeStats(
            totalRecordings: utterances.count,
            totalWords: utterances.map { $0.wordCount }.reduce(0, +),
            totalDuration: utterances.compactMap { $0.durationSeconds }.reduce(0, +),
            todayCount: utterances.filter { calendar.isDateInToday($0.timestamp) }.count,
            weekCount: utterances.filter {
                guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) else { return false }
                return $0.timestamp >= weekAgo
            }.count,
            streak: calculateStreak(utterances),
            topApps: calculateTopApps(utterances),
            insight: generateInsight(utterances),
            daysWithActivity: uniqueDays.count,
            firstActivityDate: earliestDate
        )

        // Build activity data for full year (allows switching between views)
        activityData = buildActivityData(from: utterances, weeks: 52)
    }

    private func generateInsight(_ utterances: [Utterance]) -> Insight? {
        guard !utterances.isEmpty else { return nil }

        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recentUtterances = utterances.filter { $0.timestamp >= weekAgo }

        guard !recentUtterances.isEmpty else {
            return Insight(
                iconName: "hand.wave",
                iconColor: .green,
                message: "Welcome back!",
                detail: "Ready to get things done? Hold your hotkey to start."
            )
        }

        // Categorize apps
        let devApps = Set(["Xcode", "VS Code", "Visual Studio Code", "Cursor", "Terminal", "iTerm", "Warp", "GitHub Desktop", "Tower", "Sublime Text", "IntelliJ IDEA", "PyCharm", "WebStorm"])
        let socialApps = Set(["Messages", "Slack", "Discord", "Telegram", "WhatsApp", "FaceTime", "Zoom", "Teams", "Microsoft Teams"])
        let creativeApps = Set(["Figma", "Sketch", "Photoshop", "Illustrator", "Final Cut Pro", "Logic Pro", "GarageBand", "Premiere Pro", "After Effects", "Blender"])
        let writingApps = Set(["Notion", "Notes", "Bear", "Obsidian", "Ulysses", "iA Writer", "Pages", "Word", "Google Docs"])
        let browserApps = Set(["Safari", "Chrome", "Arc", "Firefox", "Brave", "Edge"])

        var devCount = 0
        var socialCount = 0
        var creativeCount = 0
        var writingCount = 0
        var browserCount = 0

        for u in recentUtterances {
            if let app = u.metadata.activeAppName {
                if devApps.contains(app) { devCount += 1 }
                else if socialApps.contains(app) { socialCount += 1 }
                else if creativeApps.contains(app) { creativeCount += 1 }
                else if writingApps.contains(app) { writingCount += 1 }
                else if browserApps.contains(app) { browserCount += 1 }
            }
        }

        let totalCategorized = devCount + socialCount + creativeCount + writingCount + browserCount

        // Generate encouraging insight based on dominant activity
        if devCount > 0 && devCount >= totalCategorized / 2 {
            return Insight(
                iconName: "laptopcomputer",
                iconColor: .purple,
                message: "In the zone!",
                detail: "You've been doing great dev work this week. Keep building!"
            )
        }

        if socialCount > 0 && socialCount >= totalCategorized / 2 {
            return Insight(
                iconName: "bubble.left.and.bubble.right",
                iconColor: .blue,
                message: "Staying connected!",
                detail: "Great week for collaboration and catching up with people."
            )
        }

        if creativeCount > 0 && creativeCount >= totalCategorized / 2 {
            return Insight(
                iconName: "paintbrush",
                iconColor: .pink,
                message: "Creative flow!",
                detail: "You've been in creative mode. Love to see it!"
            )
        }

        if writingCount > 0 && writingCount >= totalCategorized / 2 {
            return Insight(
                iconName: "pencil.line",
                iconColor: .indigo,
                message: "Writing mode!",
                detail: "You've been getting a lot done in writing apps. Keep it up!"
            )
        }

        if browserCount > 0 && browserCount >= totalCategorized / 2 {
            return Insight(
                iconName: "magnifyingglass",
                iconColor: .teal,
                message: "Research mode!",
                detail: "Doing your homework and exploring. Curiosity is a superpower!"
            )
        }

        // Streak-based insights
        let streak = calculateStreak(utterances)
        if streak >= 7 {
            return Insight(
                iconName: "flame.fill",
                iconColor: .orange,
                message: "\(streak) day streak!",
                detail: "You're on fire! Using voice to get things done is a superpower."
            )
        }

        if streak >= 3 {
            return Insight(
                iconName: "bolt.fill",
                iconColor: .yellow,
                message: "Building momentum!",
                detail: "\(streak) days in a row. You're making this a habit!"
            )
        }

        // Time-based insights
        let hour = calendar.component(.hour, from: Date())
        let todayCount = recentUtterances.filter { calendar.isDateInToday($0.timestamp) }.count

        // "Productive morning" - before noon with good activity
        if hour < 12 && todayCount >= 8 {
            return Insight(
                iconName: "sun.max.fill",
                iconColor: .orange,
                message: "Productive morning!",
                detail: "\(todayCount) actions already and it's not even noon."
            )
        }

        // Volume-based insights (afternoon/evening)
        if todayCount >= 10 {
            return Insight(
                iconName: "arrow.up.right",
                iconColor: .green,
                message: "Productive day!",
                detail: "You've driven \(todayCount) actions today. Impressive!"
            )
        }

        // Default encouraging message
        return Insight(
            iconName: "sparkles",
            iconColor: .cyan,
            message: "Keep going!",
            detail: "\(recentUtterances.count) actions this week. You're getting things done!"
        )
    }

    private func calculateTopApps(_ utterances: [Utterance]) -> [(name: String, bundleID: String?, count: Int)] {
        // Track both counts and bundle IDs
        var appData: [String: (bundleID: String?, count: Int)] = [:]

        for u in utterances {
            if let appName = u.metadata.activeAppName, !appName.isEmpty {
                let existing = appData[appName]
                let bundleID = existing?.bundleID ?? u.metadata.activeAppBundleID
                let count = (existing?.count ?? 0) + 1
                appData[appName] = (bundleID, count)
            }
        }

        return appData
            .sorted { $0.value.count > $1.value.count }
            .prefix(5)
            .map { (name: $0.key, bundleID: $0.value.bundleID, count: $0.value.count) }
    }

    private func calculateStreak(_ utterances: [Utterance]) -> Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())

        // Group by day
        var byDay: [Date: [Utterance]] = [:]
        for u in utterances {
            let day = calendar.startOfDay(for: u.timestamp)
            byDay[day, default: []].append(u)
        }

        // Count consecutive days
        while byDay[checkDate] != nil {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = previousDay
        }

        return streak
    }

    private func buildActivityData(from utterances: [Utterance], weeks: Int) -> [DayActivity] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Group utterances by day
        var byDay: [Date: [Utterance]] = [:]
        for u in utterances {
            let day = calendar.startOfDay(for: u.timestamp)
            byDay[day, default: []].append(u)
        }

        // Find max count for normalization (minimum 1 to avoid division by zero)
        let maxCount = max(byDay.values.map { $0.count }.max() ?? 1, 1)

        // GitHub style: weeks as columns, days as rows (Sun-Sat)
        // Current day should be at bottom-right
        // We need to go back to find the start of the grid

        // Get current weekday (1 = Sunday, 7 = Saturday in gregorian)
        let currentWeekday = calendar.component(.weekday, from: today)

        // Calculate how many days back to go for full weeks + partial current week
        // We want `weeks` complete columns plus the current partial week
        let daysInCurrentWeek = currentWeekday // Days from Sunday to today (inclusive)
        let totalDays = (weeks - 1) * 7 + daysInCurrentWeek

        // Start date
        guard let startDate = calendar.date(byAdding: .day, value: -(totalDays - 1), to: today) else {
            return []
        }

        // Build array for each day from start to today
        var data: [DayActivity] = []
        var currentDate = startDate

        while currentDate <= today {
            let count = byDay[currentDate]?.count ?? 0
            let level = ActivityLevel.from(count: count, max: maxCount)
            data.append(DayActivity(date: currentDate, count: count, level: level))

            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }

        return data
    }
}

// MARK: - Data Models

struct HomeStats {
    var totalRecordings: Int = 0
    var totalWords: Int = 0
    var totalDuration: Double = 0
    var todayCount: Int = 0
    var weekCount: Int = 0
    var streak: Int = 0
    var topApps: [(name: String, bundleID: String?, count: Int)] = []
    var insight: Insight?
    var daysWithActivity: Int = 0  // Total unique days with recordings
    var firstActivityDate: Date?   // When user started

    /// Estimated time saved vs typing (4x speedup factor)
    /// Typing: ~40 WPM, Voice: ~160 WPM
    /// Time saved = (words / 40 WPM) - (words / 160 WPM) = words * 0.01875 minutes
    var timeSavedSeconds: Double {
        // Time it would take to type at 40 WPM
        let typingTimeMinutes = Double(totalWords) / 40.0
        // Time it took to speak at ~160 WPM (4x faster)
        let speakingTimeMinutes = Double(totalWords) / 160.0
        // Time saved in seconds
        return (typingTimeMinutes - speakingTimeMinutes) * 60.0
    }
}

// Activity view sizing based on user engagement
enum ActivityViewLevel: CaseIterable {
    case quarterly  // < 90 days - 2 slots (~13 weeks)
    case yearly     // >= 90 days - 3 slots + 1 stats slot (full year)

    static func from(daysWithActivity: Int) -> ActivityViewLevel {
        if daysWithActivity < 90 {
            return .quarterly
        } else {
            return .yearly
        }
    }

    var weeksToShow: Int {
        switch self {
        case .quarterly: return 13  // ~3 months
        case .yearly: return 52     // Full year
        }
    }

    var label: String {
        switch self {
        case .quarterly: return "Quarter"
        case .yearly: return "Year"
        }
    }

    /// Horizontal slots: Quarterly = 2, Yearly = 3 (+ 1 stats)
    var columns: Int {
        switch self {
        case .quarterly: return 2
        case .yearly: return 3  // Grid takes 3, stats takes 1
        }
    }
}

struct Insight {
    let iconName: String
    let iconColor: Color
    let message: String
    let detail: String
}

struct DayActivity: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
    let level: ActivityLevel
}

enum ActivityLevel: Int {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3
    case intense = 4

    static func from(count: Int, max: Int) -> ActivityLevel {
        guard count > 0, max > 0 else { return .none }
        let ratio = Double(count) / Double(max)
        switch ratio {
        case 0: return .none
        case 0..<0.25: return .low
        case 0.25..<0.5: return .medium
        case 0.5..<0.75: return .high
        default: return .intense
        }
    }

    var color: Color {
        switch self {
        case .none: return Color(white: 0.1)
        case .low: return Color.green.opacity(0.3)
        case .medium: return Color.green.opacity(0.5)
        case .high: return Color.green.opacity(0.7)
        case .intense: return Color.green
        }
    }
}

// MARK: - Grid System

/// 4-column grid with consistent spacing
enum GridLayout {
    static let columns = 4
    static let gutter: CGFloat = 12
    static let padding: CGFloat = 24

    /// Calculate width for N slots within a container
    static func width(slots: Int, in containerWidth: CGFloat) -> CGFloat {
        let safeWidth = max(containerWidth, padding * 2 + gutter * CGFloat(columns - 1) + 100)
        let availableWidth = safeWidth - (padding * 2) - (gutter * CGFloat(columns - 1))
        let singleSlot = max(0, availableWidth / CGFloat(columns))
        return max(100, singleSlot * CGFloat(slots) + gutter * CGFloat(max(0, slots - 1)))
    }
}

/// Standard card heights
private let statCardHeight: CGFloat = 100

// MARK: - Streak Card

struct StreakCard: View {
    let streak: Int

    private var streakColor: Color {
        switch streak {
        case 0: return TalkieTheme.textTertiary
        case 1...2: return .orange.opacity(0.6)
        case 3...6: return .orange
        case 7...13: return .orange
        case 14...29: return .red.opacity(0.8)
        default: return .red  // 30+ days
        }
    }

    private var flameIcon: String {
        if streak >= 7 { return "flame.fill" }
        else if streak >= 3 { return "flame" }
        else { return "flame" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title - top left, all caps
            Text("STREAK")
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundColor(TalkieTheme.textTertiary)

            Spacer()

            // Content - centered
            HStack(spacing: 6) {
                if streak > 0 {
                    Image(systemName: flameIcon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(streakColor)
                }

                Text("\(streak)")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(streak > 0 ? streakColor : TalkieTheme.textPrimary)
            }
            .frame(maxWidth: .infinity)

            Text(streak == 1 ? "day" : "days")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(TalkieTheme.textTertiary)
                .frame(maxWidth: .infinity)

            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: statCardHeight)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(TalkieTheme.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(TalkieTheme.border, lineWidth: 1)
                )
        )
    }
}

// MARK: - Today Card

struct TodayCard: View {
    let count: Int

    private var countColor: Color {
        switch count {
        case 0: return TalkieTheme.textTertiary
        case 1...9: return TalkieTheme.textPrimary
        case 10...49: return .green
        case 50...99: return .green
        case 100...199: return .orange
        default: return .red  // 200+ dictations
        }
    }

    private var activityIcon: String? {
        switch count {
        case 0: return nil
        case 1...9: return nil
        case 10...49: return "checkmark.circle"
        case 50...99: return "bolt"
        case 100...199: return "bolt.fill"
        default: return "flame.fill"  // 200+
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title - top left, all caps
            Text("TODAY")
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundColor(TalkieTheme.textTertiary)

            Spacer()

            // Content - centered
            HStack(spacing: 6) {
                if let icon = activityIcon {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(countColor)
                }

                Text("\(count)")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(countColor)
            }
            .frame(maxWidth: .infinity)

            Text(count == 1 ? "dictation" : "dictations")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(TalkieTheme.textTertiary)
                .frame(maxWidth: .infinity)

            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: statCardHeight)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(TalkieTheme.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(TalkieTheme.border, lineWidth: 1)
                )
        )
    }
}

// MARK: - Cumulative Stats Card (for yearly view)

struct CumulativeStatsCard: View {
    let stats: HomeStats

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            Text("TOTAL")
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundColor(TalkieTheme.textTertiary)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 16) {
                // Total words
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatNumber(stats.totalWords))
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(TalkieTheme.textPrimary)
                    Text("words")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(TalkieTheme.textTertiary)
                }

                // Total dictations
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(stats.totalRecordings)")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(TalkieTheme.textPrimary)
                    Text("dictations")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(TalkieTheme.textTertiary)
                }

                // Time saved
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatDuration(stats.timeSavedSeconds))
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                    Text("saved")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
            }

            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(TalkieTheme.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(TalkieTheme.border, lineWidth: 1)
                )
        )
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1000 {
            return String(format: "%.1fk", Double(n) / 1000)
        }
        return "\(n)"
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
}

// MARK: - Insight Card (2-slot width)

struct InsightCard: View {
    let insight: Insight?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title - top left, all caps (same as other cards)
            Text("INSIGHT")
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundColor(TalkieTheme.textTertiary)

            Spacer()

            // Content
            HStack(spacing: 12) {
                if let insight = insight {
                    Image(systemName: insight.iconName)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(insight.iconColor)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(insight.message)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(TalkieTheme.textPrimary)

                        Text(insight.detail)
                            .font(.system(size: 11))
                            .foregroundColor(TalkieTheme.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer()
                } else {
                    // Empty state
                    Image(systemName: "hand.wave")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.green)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ready to go!")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(TalkieTheme.textPrimary)

                        Text("Hold your hotkey to start recording.")
                            .font(.system(size: 11))
                            .foregroundColor(TalkieTheme.textSecondary)
                    }

                    Spacer()
                }
            }

            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: statCardHeight)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(TalkieTheme.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(TalkieTheme.border, lineWidth: 1)
                )
        )
    }
}

// MARK: - Adaptive Activity Card

struct AdaptiveActivityCard: View {
    let data: [DayActivity]
    let stats: HomeStats
    let level: ActivityViewLevel
    var debugBinding: Binding<ActivityViewLevel>?
    var onResetDebug: (() -> Void)?

    private let cellSize: CGFloat = 12
    private let cellSpacing: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title row
            HStack {
                Text("ACTIVITY")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundColor(TalkieTheme.textTertiary)

                #if DEBUG
                if let binding = debugBinding {
                    Spacer()
                    Picker("", selection: binding) {
                        Text("Q").tag(ActivityViewLevel.quarterly)
                        Text("Y").tag(ActivityViewLevel.yearly)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 60)

                    if binding.wrappedValue != level {
                        Button(action: { onResetDebug?() }) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 9))
                                .foregroundColor(TalkieTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                #endif
            }

            // Subheader with legend
            HStack {
                Text(headerText)
                    .font(.system(size: 11))
                    .foregroundColor(TalkieTheme.textSecondary)

                Spacer()

                // Legend
                HStack(spacing: 4) {
                    Text("Less")
                        .font(.system(size: 9))
                        .foregroundColor(TalkieTheme.textTertiary)

                    ForEach(ActivityLevel.allCases, id: \.rawValue) { activityLevel in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(activityLevel.color)
                            .frame(width: 10, height: 10)
                    }

                    Text("More")
                        .font(.system(size: 9))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
            }

            // Grid - adaptive based on level
            switch level {
            case .quarterly:
                QuarterlyActivityGrid(data: data, cellSize: cellSize, spacing: cellSpacing)
            case .yearly:
                GeometryReader { geo in
                    ActivityGrid(data: data, cellSize: cellSize, spacing: cellSpacing, containerWidth: geo.size.width)
                }
                .frame(height: 7 * cellSize + 6 * cellSpacing)
            }

            // Month labels
            MonthLabelsAdaptive(level: level, cellSize: cellSize, spacing: cellSpacing)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(TalkieTheme.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(TalkieTheme.border, lineWidth: 1)
                )
        )
    }

    private var headerText: String {
        switch level {
        case .quarterly:
            return "\(stats.totalRecordings) dictations this quarter"
        case .yearly:
            return "\(stats.totalRecordings) dictations this year"
        }
    }
}

// Monthly: Compact single row (last 30 days) - fits in ~1 slot
struct MonthlyActivityGrid: View {
    let data: [DayActivity]
    let cellSize: CGFloat
    let spacing: CGFloat

    private let daysToShow = 30

    var body: some View {
        let recentDays = getRecentDays()

        HStack(spacing: spacing) {
            ForEach(Array(recentDays.enumerated()), id: \.offset) { _, day in
                ActivityCell(day: day, size: cellSize)
            }
        }
        .frame(height: cellSize)
    }

    private func getRecentDays() -> [DayActivity] {
        // Get the most recent 30 days from data
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var dataByDate: [Date: DayActivity] = [:]
        for day in data {
            dataByDate[calendar.startOfDay(for: day.date)] = day
        }

        var result: [DayActivity] = []
        for i in (0..<daysToShow).reversed() {
            if let date = calendar.date(byAdding: .day, value: -i, to: today) {
                if let existing = dataByDate[date] {
                    result.append(existing)
                } else {
                    result.append(DayActivity(date: date, count: 0, level: .none))
                }
            }
        }
        return result
    }
}

// Quarterly: ~13 weeks grid
struct QuarterlyActivityGrid: View {
    let data: [DayActivity]
    let cellSize: CGFloat
    let spacing: CGFloat

    private let weeksToShow = 13

    var body: some View {
        let grid = buildGrid()

        HStack(alignment: .top, spacing: spacing) {
            // Day labels
            VStack(alignment: .trailing, spacing: spacing) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.system(size: 8))
                        .foregroundColor(TalkieTheme.textTertiary)
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
                                    ActivityCell(day: grid[weekIndex][dayIndex], size: cellSize)
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
        buildActivityGrid(from: data, weeks: weeksToShow)
    }
}

// Shared grid builder
private func buildActivityGrid(from data: [DayActivity], weeks: Int) -> [[DayActivity]] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let todayWeekday = calendar.component(.weekday, from: today)

    var dataByDate: [Date: DayActivity] = [:]
    for day in data {
        dataByDate[calendar.startOfDay(for: day.date)] = day
    }

    let daysBack = (weeks - 1) * 7 + (todayWeekday - 1)
    guard let startDate = calendar.date(byAdding: .day, value: -daysBack, to: today) else {
        return []
    }

    var grid: [[DayActivity]] = []
    var currentDate = startDate

    for _ in 0..<weeks {
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

// Adaptive month labels
struct MonthLabelsAdaptive: View {
    let level: ActivityViewLevel
    let cellSize: CGFloat
    let spacing: CGFloat

    private let dayLabelWidth: CGFloat = 12

    var body: some View {
        let months = getMonths()
        let weekWidth = cellSize + spacing
        let weeksPerMonth = CGFloat(level.weeksToShow) / CGFloat(months.count)

        HStack(spacing: 0) {
            Spacer().frame(width: dayLabelWidth + spacing)

            ForEach(Array(months.enumerated()), id: \.offset) { _, month in
                Text(month)
                    .font(.system(size: 9))
                    .foregroundColor(TalkieTheme.textTertiary)
                    .frame(width: weeksPerMonth * weekWidth, alignment: .leading)
            }
        }
    }

    private func getMonths() -> [String] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        var months: [String] = []
        let today = Date()

        let monthsToShow: Int
        switch level {
        case .quarterly: monthsToShow = 3
        case .yearly: monthsToShow = 12
        }

        for i in (0..<monthsToShow).reversed() {
            if let date = calendar.date(byAdding: .month, value: -i, to: today) {
                months.append(formatter.string(from: date))
            }
        }

        return months
    }
}

// MARK: - Activity Graph Card (Legacy - Full Year)

struct ActivityGraphCard: View {
    let data: [DayActivity]
    let stats: HomeStats

    private let cellSize: CGFloat = 14
    private let cellSpacing: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("\(stats.weekCount) recordings in the last 7 days")
                    .font(.system(size: 12))
                    .foregroundColor(TalkieTheme.textSecondary)

                Spacer()

                // Legend
                HStack(spacing: 4) {
                    Text("Less")
                        .font(.system(size: 9))
                        .foregroundColor(TalkieTheme.textTertiary)

                    ForEach(ActivityLevel.allCases, id: \.rawValue) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(level.color)
                            .frame(width: 10, height: 10)
                    }

                    Text("More")
                        .font(.system(size: 9))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
            }

            // Grid - full width, 53 weeks (full year)
            GeometryReader { geo in
                ActivityGrid(data: data, cellSize: cellSize, spacing: cellSpacing, containerWidth: geo.size.width)
            }
            .frame(height: 7 * cellSize + 6 * cellSpacing)

            // Month labels
            MonthLabelsFixed(cellSize: cellSize, spacing: cellSpacing)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(TalkieTheme.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(TalkieTheme.border, lineWidth: 1)
                )
        )
    }
}

extension ActivityLevel: CaseIterable {}

struct ActivityGrid: View {
    let data: [DayActivity]
    let cellSize: CGFloat
    let spacing: CGFloat
    let containerWidth: CGFloat

    private let dayLabelWidth: CGFloat = 28
    private let weeksInYear = 53

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            // Day labels (all 7 days)
            VStack(alignment: .trailing, spacing: spacing) {
                Text("Sun").font(.system(size: 9)).foregroundColor(TalkieTheme.textTertiary).frame(height: cellSize)
                Text("Mon").font(.system(size: 9)).foregroundColor(TalkieTheme.textTertiary).frame(height: cellSize)
                Text("Tue").font(.system(size: 9)).foregroundColor(TalkieTheme.textTertiary).frame(height: cellSize)
                Text("Wed").font(.system(size: 9)).foregroundColor(TalkieTheme.textTertiary).frame(height: cellSize)
                Text("Thu").font(.system(size: 9)).foregroundColor(TalkieTheme.textTertiary).frame(height: cellSize)
                Text("Fri").font(.system(size: 9)).foregroundColor(TalkieTheme.textTertiary).frame(height: cellSize)
                Text("Sat").font(.system(size: 9)).foregroundColor(TalkieTheme.textTertiary).frame(height: cellSize)
            }
            .frame(width: dayLabelWidth)

            // Build full 53-week grid with data mapped in
            let grid = buildFullYearGrid()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(0..<weeksInYear, id: \.self) { weekIndex in
                        VStack(spacing: spacing) {
                            ForEach(0..<7, id: \.self) { dayIndex in
                                let cellData = grid[weekIndex][dayIndex]
                                ActivityCell(day: cellData, size: cellSize)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Build a full 53-week grid (371 days) ending on today
    /// Each cell has data if available, otherwise shows as empty (gray)
    private func buildFullYearGrid() -> [[DayActivity]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today) // 1 = Sunday

        // Map existing data by date for O(1) lookup
        var dataByDate: [Date: DayActivity] = [:]
        for day in data {
            dataByDate[calendar.startOfDay(for: day.date)] = day
        }

        // Calculate start date: go back 52 full weeks + days to reach Sunday
        // We want exactly 53 columns (weeks), ending with today in the last column
        let daysBack = (weeksInYear - 1) * 7 + (todayWeekday - 1)
        guard let startDate = calendar.date(byAdding: .day, value: -daysBack, to: today) else {
            return Array(repeating: Array(repeating: DayActivity(date: today, count: 0, level: .none), count: 7), count: weeksInYear)
        }

        var grid: [[DayActivity]] = []
        var currentDate = startDate

        for _ in 0..<weeksInYear {
            var week: [DayActivity] = []
            for _ in 0..<7 {
                if currentDate <= today {
                    // Use existing data or create empty placeholder
                    if let existing = dataByDate[currentDate] {
                        week.append(existing)
                    } else {
                        week.append(DayActivity(date: currentDate, count: 0, level: .none))
                    }
                } else {
                    // Future dates - show as empty/invisible
                    week.append(DayActivity(date: currentDate, count: -1, level: .none))
                }
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
            }
            grid.append(week)
        }

        return grid
    }
}

struct ActivityCell: View {
    let day: DayActivity
    let size: CGFloat

    @State private var isHovered = false

    private var isFutureDate: Bool {
        day.count < 0
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(isFutureDate ? Color.clear : day.level.color)
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(
                        isFutureDate ? Color.clear :
                        isHovered ? TalkieTheme.textSecondary : TalkieTheme.border.opacity(0.3),
                        lineWidth: isHovered ? 1 : 0.5
                    )
            )
            .onHover { hovering in
                if !isFutureDate {
                    isHovered = hovering
                }
            }
            .popover(isPresented: $isHovered, arrowEdge: .top) {
                ActivityTooltip(day: day)
            }
    }
}

struct ActivityTooltip: View {
    let day: DayActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formattedDate)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(TalkieTheme.textPrimary)

            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(day.level.color)
                    .frame(width: 8, height: 8)

                Text(countText)
                    .font(.system(size: 10))
                    .foregroundColor(TalkieTheme.textSecondary)
            }
        }
        .padding(8)
        .background(TalkieTheme.surfaceElevated)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: day.date)
    }

    private var countText: String {
        if day.count == 0 {
            return "No recordings"
        } else if day.count == 1 {
            return "1 recording"
        } else {
            return "\(day.count) recordings"
        }
    }
}

/// Fixed month labels - each month gets equal space (~4.4 weeks each)
struct MonthLabelsFixed: View {
    let cellSize: CGFloat
    let spacing: CGFloat

    private let dayLabelWidth: CGFloat = 28
    private let weeksInYear = 53

    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: dayLabelWidth + spacing)

            // Get the 12 months starting from ~1 year ago
            let months = getLast12Months()
            let weekWidth = cellSize + spacing
            let weeksPerMonth = CGFloat(weeksInYear) / 12.0

            ForEach(Array(months.enumerated()), id: \.offset) { _, month in
                Text(month)
                    .font(.system(size: 9))
                    .foregroundColor(TalkieTheme.textTertiary)
                    .frame(width: weeksPerMonth * weekWidth, alignment: .leading)
            }
        }
    }

    private func getLast12Months() -> [String] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        var months: [String] = []
        let today = Date()

        // Start from 11 months ago and go to current month
        for i in (0..<12).reversed() {
            if let date = calendar.date(byAdding: .month, value: -i, to: today) {
                months.append(formatter.string(from: date))
            }
        }

        return months
    }
}

// MARK: - Quick Stats Row

struct QuickStatsRow: View {
    let stats: HomeStats

    var body: some View {
        HStack(spacing: 12) {
            QuickStatCard(
                icon: "flame.fill",
                value: "\(stats.streak)",
                label: "Day Streak",
                color: .orange
            )

            QuickStatCard(
                icon: "waveform",
                value: "\(stats.todayCount)",
                label: "Today",
                color: .cyan
            )

            QuickStatCard(
                icon: "text.word.spacing",
                value: formatNumber(stats.totalWords),
                label: "Total Words",
                color: .purple
            )

            QuickStatCard(
                icon: "bolt.fill",
                value: formatTimeSaved(stats.timeSavedSeconds),
                label: "Time Saved",
                color: .green
            )
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1000 {
            return String(format: "%.1fk", Double(n) / 1000)
        }
        return "\(n)"
    }

    private func formatTimeSaved(_ seconds: Double) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        }
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct QuickStatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(TalkieTheme.textPrimary)

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(TalkieTheme.textTertiary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? TalkieTheme.hover : TalkieTheme.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isHovered ? color.opacity(0.3) : TalkieTheme.border, lineWidth: 1)
                )
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Top Apps Card

/// Standard row height for list items (Recent, Top Apps)
private let listRowHeight: CGFloat = 32

struct TopAppsCard: View {
    let apps: [(name: String, bundleID: String?, count: Int)]
    var onSelectApp: ((String, String?) -> Void)?  // (appName, bundleID)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TOP APPS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundColor(TalkieTheme.textTertiary)

                Spacer()

                if !apps.isEmpty {
                    Text("this week")
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textMuted)
                }
            }

            if apps.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 24))
                            .foregroundColor(TalkieTheme.textMuted)
                        Text("No app data yet")
                            .font(.system(size: 12))
                            .foregroundColor(TalkieTheme.textTertiary)
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(apps.enumerated()), id: \.offset) { index, app in
                        TopAppRow(
                            rank: index + 1,
                            name: app.name,
                            bundleID: app.bundleID,
                            count: app.count,
                            onSelect: onSelectApp
                        )
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(TalkieTheme.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(TalkieTheme.border, lineWidth: 1)
                )
        )
    }
}

struct TopAppRow: View {
    let rank: Int
    let name: String
    let bundleID: String?
    let count: Int
    var onSelect: ((String, String?) -> Void)?  // (appName, bundleID)

    @State private var isHovered = false

    var body: some View {
        Button(action: {
            onSelect?(name, bundleID)
        }) {
            HStack(spacing: 8) {
                Text("\(rank)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(TalkieTheme.textMuted)
                    .frame(width: 12)

                // Show actual app icon if bundle ID available
                if let bundleID = bundleID {
                    AppIconView(bundleIdentifier: bundleID, size: 20)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "app")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .frame(width: 20, height: 20)
                }

                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isHovered ? TalkieTheme.textPrimary : TalkieTheme.textSecondary)
                    .lineLimit(1)

                Spacer()

                Text("\(count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(TalkieTheme.textTertiary)

                // Arrow indicator on hover
                if isHovered {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
            }
            .frame(height: listRowHeight)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? TalkieTheme.hover : Color.clear)
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

// MARK: - Recent Activity Card

struct RecentActivityCard: View {
    let utterances: [Utterance]
    var onSelectUtterance: ((Utterance) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RECENT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundColor(TalkieTheme.textTertiary)

                Spacer()

                Text("\(utterances.count) latest")
                    .font(.system(size: 10))
                    .foregroundColor(TalkieTheme.textMuted)
            }

            if utterances.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.badge.plus")
                            .font(.system(size: 24))
                            .foregroundColor(TalkieTheme.textMuted)
                        Text("No recordings yet")
                            .font(.system(size: 12))
                            .foregroundColor(TalkieTheme.textTertiary)
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(utterances) { utterance in
                        RecentActivityRow(utterance: utterance, onSelect: onSelectUtterance)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(TalkieTheme.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(TalkieTheme.border, lineWidth: 1)
                )
        )
    }
}

struct RecentActivityRow: View {
    let utterance: Utterance
    var onSelect: ((Utterance) -> Void)?
    @ObservedObject private var settings = LiveSettings.shared

    @State private var isHovered = false

    /// Status: success (has text), failure (empty/error)
    private var isSuccess: Bool {
        !utterance.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Button(action: {
            onSelect?(utterance)
        }) {
            HStack(spacing: 8) {
                // 1. Status indicator (like rank # in Top Apps)
                Circle()
                    .fill(isSuccess ? Color.green : Color.red.opacity(0.7))
                    .frame(width: 6, height: 6)
                    .frame(width: 12)

                // 2. App icon (like app icon in Top Apps)
                if let bundleID = utterance.metadata.activeAppBundleID {
                    AppIconView(bundleIdentifier: bundleID, size: 20)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "app")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .frame(width: 20, height: 20)
                }

                // 3. Text preview (like app name in Top Apps) - scales with fontSize setting
                Text(utterance.text.isEmpty ? "No transcription" : String(utterance.text.prefix(50)) + (utterance.text.count > 50 ? "..." : ""))
                    .font(settings.fontSize.smFont)
                    .foregroundColor(isHovered ? TalkieTheme.textPrimary : TalkieTheme.textSecondary)
                    .lineLimit(1)

                Spacer()

                // 4. Time ago (like count in Top Apps)
                Text(timeAgo(from: utterance.timestamp))
                    .font(.system(size: settings.fontSize.sm, weight: .medium, design: .rounded))
                    .foregroundColor(TalkieTheme.textTertiary)

                // Arrow indicator on hover
                if isHovered {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
            }
            .frame(height: listRowHeight)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? TalkieTheme.hover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(utterance.text, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                withAnimation {
                    DictationStore.shared.delete(utterance)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            return "\(seconds / 60)m"
        } else if seconds < 86400 {
            return "\(seconds / 3600)h"
        } else {
            return "\(seconds / 86400)d"
        }
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .frame(width: 600, height: 700)
}
