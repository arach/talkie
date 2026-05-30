//
//  HomeScreen.swift
//  Talkie
//
//  Main home dashboard showing stats, recent activity, and quick actions
//

import SwiftUI
import Combine
import AppKit
import TalkieKit

private let homeLog = Log(.ui)

// MARK: - Card Style Modifier

/// Unified card styling - uses Liquid Glass on macOS 26+, falls back to shadow-based on older
struct CardStyle: ViewModifier {
    var cornerRadius: CGFloat = CornerRadius.cardLarge
    var padding: CGFloat = Spacing.cardInset

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .liquidGlassCard(
                cornerRadius: cornerRadius,
                fallbackFill: Theme.current.surface2,
                fallbackStroke: Theme.current.divider
            )
            .clipped() // Prevent content from showing outside bounds during transitions
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat = CornerRadius.cardLarge, padding: CGFloat = Spacing.cardInset) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius, padding: padding))
    }
}

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

    // Original reference (for dictations only - memos navigate by ID)
    var dictation: Dictation?
}

// MARK: - Home Screen

struct HomeScreen: View {
    private static let startupMemoLoadLimit = 8
    private static let maxUnifiedActivityItems = 24
    private static let syncRefreshDedupInterval: TimeInterval = 1.0

    // GRDB-backed ViewModel for memo data
    private var memosVM: MemosViewModel { MemosViewModel.shared }

    // Singletons
    private let dictationStore = DictationStore.shared
    private let liveState = ServiceManager.shared.live
    private let serviceMonitor = ServiceManager.shared.engine
    private let syncManager = CloudKitSyncManager.shared
    private let settings = SettingsManager.shared  // For theme observation
    private let recordingRepo = TalkieObjectRepository()

    // State
    @State private var unifiedActivity: [UnifiedActivityItem] = []
    @State private var activityData: [DayActivity] = []
    @State private var countByDay: [Date: Int] = [:]
    @State private var streak: Int = 0
    @State private var todayMemos: Int = 0
    @State private var todayDictations: Int = 0
    @State private var totalWords: Int = 0
    @State private var showingRecordingView = false
    @State private var showContentSearch = false
    @State private var topApps: [(name: String, bundleID: String?, count: Int)] = []
    @State private var hasPerformedInitialLoad = false
    @State private var lastSyncRefreshAt: Date = .distantPast
    @State private var isStartupProfilingActive = true
    @State private var startupProfilingFallbackTask: Task<Void, Never>?

    // Task tracking for cancellation on view dismissal
    @State private var streakTask: Task<Void, Never>?
    @State private var activityTask: Task<Void, Never>?
    @State private var homeStatsRefreshTask: Task<Void, Never>?

    private var todayTotal: Int { todayMemos + todayDictations }
    private var hasActivity: Bool { !unifiedActivity.isEmpty }

    /// Show onboarding for new users (< 3 days) with limited activity
    private var shouldShowOnboarding: Bool {
        settings.shouldShowOnboardingCards && unifiedActivity.count < 5
    }

    // Grid builder for context-aware layout
    private let gridBuilder = HomeGridBuilder()

    #if DEBUG
    @ObservedObject private var presetManager = HomeGridPresetManager.shared
    #endif

    /// Build the grid based on current context (or active preset in DEBUG)
    private var homeGrid: HomeGrid {
        #if DEBUG
        // Use preset if not in "live" mode
        if presetManager.activePreset != .live {
            return gridBuilder.build(preset: presetManager.activePreset)
        }
        #endif

        // Live data context
        let context = HomeContext(
            isOnboarding: shouldShowOnboarding,
            hasActivity: hasActivity,
            useCalendarWidget: settings.useCalendarWidget,
            helpersRunningCount: helpersRunningCount,
            helpersExpectedCount: helpersExpectedCount,
            todayTotal: todayTotal,
            todayMemos: todayMemos,
            todayDictations: todayDictations,
            totalMemos: memosVM.totalCount,
            totalDictations: dictationStore.cachedCount,
            totalWords: totalWords
        )
        return gridBuilder.build(context: context)
    }

    var body: some View {
        if settings.isScopeTheme {
            // Cream-phosphor Home — homepage-inspired layout. Bypasses
            // the grid/widget system entirely; pulls activity from the
            // same data sources HomeGrid would use.
            ScopeHomeView(
                unifiedActivity: unifiedActivity,
                totalWords: totalWords,
                streak: streak,
                onStartRecording: {
                    // Match HomeGrid: nav to Recordings (which hosts the
                    // overlay) and post the notification it listens for.
                    NavigationState.shared.navigate(to: .recordings)
                    NotificationCenter.default.post(name: .init("ShowRecordingView"), object: nil)
                },
                onOpenLibrary: { NavigationState.shared.navigate(to: .recordings) },
                // Item-specific deep-linking is a follow-up — for now, opening
                // any row in the captures table routes to the Recordings list.
                onOpenItem: { _ in NavigationState.shared.navigate(to: .recordings) }
            )
            .task {
                if !hasPerformedInitialLoad {
                    hasPerformedInitialLoad = true
                    await loadInitialHomeData(refreshSecondaryInsights: true)
                }
            }
            // The Scope path was missing the store-change reactivity the
            // standard path has — once `loadData()` ran on first appear
            // the view never re-pulled, so new dictations / memos never
            // showed up. Mirror the standard path's onChange wiring.
            .onChange(of: dictationStore.dictations.count) { _, _ in
                refreshAfterStoreChange()
            }
            .onChange(of: memosVM.totalCount) { _, _ in
                refreshAfterStoreChange()
            }
            .onReceive(NotificationCenter.default.publisher(for: .syncDataAvailable)) { _ in
                handleSyncDrivenRefresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: .talkieSyncCompleted)) { _ in
                handleSyncDrivenRefresh()
            }
        } else {
            standardHome
        }
    }

    private var standardHome: some View {
        TalkiePage("Home", style: .page) {
            header
        } content: {
            #if DEBUG
            // Sandbox mode banner
            if DatabaseManager.isUsingSandbox {
                HStack(spacing: 8) {
                    Image(systemName: "flask.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("SANDBOX MODE")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                    Text("–")
                    Text("Testing with empty database")
                        .font(.system(size: 12))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.orange.gradient)
                .cornerRadius(8)
            }
            #endif

            // Grid-based layout - same structure for all states
            // Cards are inserted/removed based on context
            HomeGridView(grid: homeGrid)
        }
        .task {
            if isStartupProfilingActive {
                StartupProfiler.shared.mark("home.task.start")
            }

            // Avoid re-running heavy startup work every time Home reappears.
            guard !hasPerformedInitialLoad else {
                loadData()
                if isStartupProfilingActive {
                    StartupProfiler.shared.mark("home.task.done")
                }
                return
            }
            hasPerformedInitialLoad = true
            scheduleStartupProfilingFallbackIfNeeded()

            await loadInitialHomeData(refreshSecondaryInsights: true)
            if isStartupProfilingActive {
                StartupProfiler.shared.mark("home.task.done")
            }
        }
        .onAppear {
            if isStartupProfilingActive {
                StartupProfiler.shared.mark("home.onAppear")
            }
        }
        .onChange(of: dictationStore.dictations.count) { oldCount, newCount in
            refreshAfterStoreChange()
            // Mark ready when dictations are first populated
            if isStartupProfilingActive, oldCount == 0, newCount > 0 {
                finishStartupProfiling(reason: "dictations rendered")
            }
        }
        .onChange(of: memosVM.totalCount) { _, _ in
            refreshAfterStoreChange()
        }
        .onDisappear {
            // Cancel in-flight tasks when view is dismissed
            streakTask?.cancel()
            activityTask?.cancel()
            homeStatsRefreshTask?.cancel()
            startupProfilingFallbackTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncDataAvailable)) { _ in
            handleSyncDrivenRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .talkieSyncCompleted)) { _ in
            handleSyncDrivenRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showContentSearch)) { _ in
            showContentSearch = true
        }
        .overlay {
            ContentSearchOverlay(isPresented: $showContentSearch)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Spacing.md) {
            TalkieText("Home", style: .pageTitle)

            if streak > 0 {
                HStack(spacing: 4) {
                    Image(systemName: streak >= 7 ? "flame.fill" : "flame")
                        .foregroundColor(.orange)
                    Text("\(streak) day streak")
                        .foregroundColor(.orange)
                }
                .font(.system(size: 13, weight: .medium))
            }

            Spacer()

            // Search trigger pill
            SearchTriggerPill()
        }
    }

    // MARK: - Helpers Status (used by HomeGridBuilder)

    /// Snapshot of each helper's expected + running state.
    /// Derived purely from service state + settings — no hardcoded counts.
    private var helperStatuses: [(expected: Bool, running: Bool)] {
        let sync = ServiceManager.shared.sync
        return [
            // Agent: always expected (long-lived helper, launched via launchd KeepAlive)
            (expected: true, running: liveState.isRunning),
            // Sync: only expected when the user has iCloud sync enabled
            (expected: settings.iCloudSyncEnabled, running: sync.isRunning)
        ]
    }

    private var helpersRunningCount: Int {
        helperStatuses.filter { $0.running }.count
    }

    private var helpersExpectedCount: Int {
        helperStatuses.filter { $0.expected }.count
    }

    // MARK: - Data Loading

    @MainActor
    private func waitForHomeDatabase() async -> Bool {
        guard !DatabaseManager.shared.isInitialized else { return true }

        do {
            _ = try await DatabaseManager.shared.databaseWhenReady()
            return true
        } catch {
            homeLog.error("Home database wait failed: \(error.localizedDescription)")
            return false
        }
    }

    @MainActor
    private func loadInitialHomeData(refreshSecondaryInsights: Bool) async {
        guard await waitForHomeDatabase() else { return }

        if isStartupProfilingActive {
            StartupProfiler.shared.mark("home.stats.start")
        }
        await memosVM.loadStats()
        _ = await dictationStore.refreshAndWait()
        await refreshHomeInsights()
        if isStartupProfilingActive {
            StartupProfiler.shared.mark("home.stats.done")
        }

        await memosVM.loadRecentMemos(limit: Self.startupMemoLoadLimit)
        if isStartupProfilingActive {
            StartupProfiler.shared.mark("home.memos.done")
        }

        loadData(refreshSecondaryInsights: refreshSecondaryInsights)
    }

    @MainActor
    private func refreshHomeInsights() async {
        guard DatabaseManager.shared.isInitialized else { return }

        do {
            async let streakQ = recordingRepo.calculateDictationStreak()
            async let topAppsQ = recordingRepo.topDictationApps(limit: 5)

            todayMemos = memosVM.todayCount
            todayDictations = dictationStore.todayCount
            totalWords = dictationStore.totalWordCount
            streak = try await streakQ
            topApps = try await topAppsQ

            if settings.extensionsFrameworkEnabled {
                ExtensionManager.shared.syncWithDatabaseCounts(
                    memoCount: memosVM.totalCount,
                    dictationCount: dictationStore.cachedCount,
                    totalWords: totalWords,
                    streak: streak
                )
            }
        } catch is CancellationError {
        } catch {
            homeLog.error("Failed to refresh home insights: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func refreshAfterStoreChange() {
        loadData()

        homeStatsRefreshTask?.cancel()
        homeStatsRefreshTask = Task {
            guard await waitForHomeDatabase(), !Task.isCancelled else { return }

            await memosVM.loadStats()
            await refreshHomeInsights()

            guard !Task.isCancelled else { return }
            loadData()
        }
    }

    @MainActor
    private func handleSyncDrivenRefresh() {
        let now = Date()
        guard now.timeIntervalSince(lastSyncRefreshAt) >= Self.syncRefreshDedupInterval else {
            return
        }
        lastSyncRefreshAt = now

        Task {
            await memosVM.loadRecentMemos(limit: Self.startupMemoLoadLimit)
            await memosVM.loadStats()
            _ = await dictationStore.refreshAndWait()
            await refreshHomeInsights()
            loadData(refreshSecondaryInsights: true)
        }
    }

    private func loadData(refreshSecondaryInsights: Bool = false) {
        // Build unified activity from memos + dictations
        var items: [UnifiedActivityItem] = []

        // Add memos (from GRDB via MemosViewModel)
        for memo in memosVM.memos.prefix(Self.maxUnifiedActivityItems) {
            items.append(UnifiedActivityItem(
                id: memo.id.uuidString,
                type: .memo,
                title: memo.title ?? "Untitled Memo",
                preview: memo.transcription?.prefix(100).description,
                date: memo.createdAt,
                appName: nil,
                appBundleID: nil,
                isSuccess: true,
                dictation: nil
            ))
        }

        // Add dictations
        for dictation in dictationStore.dictations.prefix(Self.maxUnifiedActivityItems) {
            items.append(UnifiedActivityItem(
                id: dictation.id.uuidString,
                type: .dictation,
                title: dictation.metadata.activeAppName ?? "Dictation",
                preview: dictation.text.isEmpty ? nil : String(dictation.text.prefix(100)),
                date: dictation.timestamp,
                appName: dictation.metadata.activeAppName,
                appBundleID: dictation.metadata.activeAppBundleID,
                isSuccess: !dictation.text.isEmpty,
                dictation: dictation
            ))
        }

        // Sort by date descending
        unifiedActivity = Array(items.sorted { $0.date > $1.date }.prefix(Self.maxUnifiedActivityItems))

        todayMemos = memosVM.todayCount
        todayDictations = dictationStore.todayCount
        totalWords = dictationStore.totalWordCount

        #if DEBUG
        FrameRateMonitor.shared.markNavigationDataVisible(
            section: NavigationSection.home.perfName,
            source: "HomeScreen.loadData",
            detail: "activity=\(unifiedActivity.count) memos=\(memosVM.totalCount) dictations=\(dictationStore.cachedCount)"
        )
        #endif

        guard refreshSecondaryInsights else {
            if settings.extensionsFrameworkEnabled {
                ExtensionManager.shared.syncWithDatabaseCounts(
                    memoCount: memosVM.totalCount,
                    dictationCount: dictationStore.cachedCount,
                    totalWords: totalWords,
                    streak: streak
                )
            }
            return
        }

        // Calculate streak from database (not limited in-memory store)
        streakTask?.cancel()
        streakTask = Task {
            guard DatabaseManager.shared.isInitialized else { return }
            do {
                let streakVal = try await recordingRepo.calculateDictationStreak()
                let apps = try await recordingRepo.topDictationApps(limit: 5)
                await MainActor.run {
                    streak = streakVal
                    topApps = apps
                }
            } catch is CancellationError {
            } catch {
            }
        }

        if settings.extensionsFrameworkEnabled {
            ExtensionManager.shared.syncWithDatabaseCounts(
                memoCount: memosVM.totalCount,
                dictationCount: dictationStore.cachedCount,
                totalWords: totalWords,
                streak: streak
            )
        }

        // Build activity heatmap data.
        activityTask?.cancel()
        activityTask = Task {
            let (data, dayMap) = await buildActivityData()
            if !Task.isCancelled {
                await MainActor.run {
                    activityData = data
                    countByDay = dayMap
                }
            }
        }
    }

    private func buildActivityData() async -> ([DayActivity], [Date: Int]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weeksToShow = 13

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var dayMap: [Date: Int] = [:]

        // Add memo counts from heatmapData (already aggregated)
        for (dateString, count) in memosVM.heatmapData {
            if let date = dateFormatter.date(from: dateString) {
                dayMap[calendar.startOfDay(for: date)] = count
            }
        }

        // Add dictation counts from SQL (fast GROUP BY) - skip if database not ready
        if DatabaseManager.shared.isInitialized,
           let dictationActivity = try? await recordingRepo.dictationActivityByDay(days: 365) {
            for (dateString, count) in dictationActivity {
                if let date = dateFormatter.date(from: dateString) {
                    dayMap[calendar.startOfDay(for: date), default: 0] += count
                }
            }
        }

        let maxCount = max(dayMap.values.max() ?? 1, 1)

        // Build 13 weeks of data
        let todayWeekday = calendar.component(.weekday, from: today)
        let daysBack = (weeksToShow - 1) * 7 + (todayWeekday - 1)
        guard let startDate = calendar.date(byAdding: .day, value: -daysBack, to: today) else { return ([], dayMap) }

        var data: [DayActivity] = []
        var currentDate = startDate

        while currentDate <= today {
            let count = dayMap[currentDate] ?? 0
            let level = ActivityLevel.from(count: count, max: maxCount)
            data.append(DayActivity(date: currentDate, count: count, level: level))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        return (data, dayMap)
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1000 {
            return String(format: "%.1fk", Double(n) / 1000)
        }
        return "\(n)"
    }

    @MainActor
    private func scheduleStartupProfilingFallbackIfNeeded() {
        guard isStartupProfilingActive else { return }
        startupProfilingFallbackTask?.cancel()
        startupProfilingFallbackTask = Task {
            try? await Task.sleep(for: .seconds(4))
            finishStartupProfiling(reason: "fallback timeout")
        }
    }

    @MainActor
    private func finishStartupProfiling(reason: String) {
        guard isStartupProfilingActive else { return }
        startupProfilingFallbackTask?.cancel()
        StartupProfiler.shared.mark("home.dictations.rendered")
        StartupProfiler.shared.mark("home.startup.finalized (\(reason))")
        StartupProfiler.shared.printSummary()
        isStartupProfilingActive = false
    }
}

// MARK: - Memo Activity Row

struct MemoActivityRow: View {
    let memo: MemoModel
    var onSelect: (() -> Void)?

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: { onSelect?() }) {
        HStack(spacing: 8) {
            // Provenance icon (where it came from)
            Image(systemName: memo.source.icon)
                .font(.system(size: 13))
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(width: 20, height: 20)
                .offset(y: isHovered ? -1 : 0)
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .animation(TalkieAnimation.microSpring, value: isHovered)

            // Title/Preview
            Text(memoTitle)
                .font(.system(size: 12))
                .foregroundColor(Theme.current.foreground)
                .lineLimit(1)

            Spacer()

            // Duration
            if memo.duration > 0 {
                Text(formatDuration(memo.duration))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            // Time ago
            Text(timeAgo(from: memo.createdAt))
                .font(.system(size: 10))
                .foregroundColor(Theme.current.foregroundMuted)

            if isHovered {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.current.foregroundMuted)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, Spacing.cardInset)
        .contentShape(Rectangle())
        .background(isHovered ? Theme.current.surfaceHover : Color.clear)
        .padding(.horizontal, -Spacing.cardInset)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .animation(.easeOut(duration: 0.1), value: isFocused)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(memo.transcription ?? "", forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Divider()

            Button {
                let text = memo.transcription ?? ""
                let picker = NSSharingServicePicker(items: [text])
                if let window = NSApp.keyWindow, let contentView = window.contentView {
                    picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
                }
            } label: {
                Label("Share...", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(role: .destructive) {
                Task { await MemosViewModel.shared.deleteMemo(memo) }
            } label: {
                Label("Delete", systemImage: "trash")
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
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: { onSelect?() }) {
        HStack(spacing: 8) {
            // App icon - larger now without status dot
            Group {
                if let bundleID = dictation.metadata.activeAppBundleID {
                    AppIconView(bundleIdentifier: bundleID, size: 20)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "app")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.current.foregroundMuted)
                        .frame(width: 20, height: 20)
                }
            }
            .offset(y: isHovered ? -1 : 0)
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(TalkieAnimation.microSpring, value: isHovered)

            // Text preview
            Text(dictation.text.isEmpty ? "No transcription" : String(dictation.text.prefix(60)))
                .font(.system(size: 12))
                .foregroundColor(dictation.text.isEmpty ? Theme.current.foregroundMuted : Theme.current.foreground)
                .lineLimit(1)

            Spacer()

            // Time ago
            Text(timeAgo(from: dictation.timestamp))
                .font(.system(size: 10))
                .foregroundColor(Theme.current.foregroundMuted)

            if isHovered {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.current.foregroundMuted)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, Spacing.cardInset)
        .contentShape(Rectangle())
        .background(isHovered ? Theme.current.surfaceHover : Color.clear)
        .padding(.horizontal, -Spacing.cardInset)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .animation(.easeOut(duration: 0.1), value: isFocused)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(dictation.text, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Divider()

            Button {
                Task {
                    try? await TalkieObjectRepository().promoteToMemo(id: dictation.id)
                    DictationStore.shared.refresh()
                }
            } label: {
                Label("Promote to Memo", systemImage: "arrow.up.doc")
            }

            Button {
                let picker = NSSharingServicePicker(items: [dictation.text])
                if let window = NSApp.keyWindow, let contentView = window.contentView {
                    picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
                }
            } label: {
                Label("Share...", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(role: .destructive) {
                DictationStore.shared.delete(dictation)
            } label: {
                Label("Delete", systemImage: "trash")
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

// MARK: - Activity Heatmap Grid

struct ActivityHeatmapGrid: View {
    let data: [DayActivity]
    var weeksToShow: Int = 13

    private let spacing: CGFloat = 3
    private let labelWidth: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width - labelWidth - spacing
            // Fixed cell size, expand weeks to fill available width (cap at 26 weeks / ~6 months)
            let cellSize: CGFloat = 13
            let fittableWeeks = min(26, max(weeksToShow, Int((availableWidth + spacing) / (cellSize + spacing))))
            let grid = buildGrid(weeks: fittableWeeks)

            ZStack(alignment: .topLeading) {
                HStack(alignment: .top, spacing: spacing) {
                    // Day labels
                    VStack(alignment: .trailing, spacing: spacing) {
                        ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, day in
                            Text(day)
                                .font(.system(size: 9))
                                .foregroundColor(Theme.current.foregroundMuted)
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                    .frame(width: labelWidth)

                    // Grid
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(0..<fittableWeeks, id: \.self) { weekIndex in
                            if weekIndex < grid.count {
                                VStack(spacing: spacing) {
                                    ForEach(0..<7, id: \.self) { dayIndex in
                                        if dayIndex < grid[weekIndex].count {
                                            let day = grid[weekIndex][dayIndex]
                                            ActivityHeatmapCell(day: day, cellSize: cellSize)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

            }
            .coordinateSpace(name: "heatmapGrid")
            .overlay(alignment: .topLeading) {
                // Tooltip overlay — renders above all cells, not clipped by grid bounds
                HeatmapTooltipOverlay()
            }
        }
        .frame(height: 7 * 13 + 6 * spacing)
    }

    private func buildGrid(weeks: Int? = nil) -> [[DayActivity]] {
        let effectiveWeeks = weeks ?? weeksToShow
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today)

        var dataByDate: [Date: DayActivity] = [:]
        for day in data {
            dataByDate[calendar.startOfDay(for: day.date)] = day
        }

        let daysBack = (effectiveWeeks - 1) * 7 + (todayWeekday - 1)
        guard let startDate = calendar.date(byAdding: .day, value: -daysBack, to: today) else { return [] }

        var grid: [[DayActivity]] = []
        var currentDate = startDate

        for _ in 0..<effectiveWeeks {
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

// MARK: - Heatmap Tooltip State

@Observable
@MainActor
final class HeatmapTooltipState {
    static let shared = HeatmapTooltipState()
    var day: DayActivity?
    var anchor: CGPoint = .zero  // in "heatmapGrid" coordinate space
    private var dismissTask: Task<Void, Never>?
    private init() {}

    func show(day: DayActivity, anchor: CGPoint) {
        dismissTask?.cancel()
        self.day = day
        self.anchor = anchor
    }

    func dismiss(matching date: Date) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            if self.day?.date == date {
                self.day = nil
            }
        }
    }

    private static let tooltipFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var tooltipText: String? {
        guard let day else { return nil }
        let dateStr = Self.tooltipFormatter.string(from: day.date)
        if day.count == 0 {
            return "No contributions — \(dateStr)"
        } else if day.count == 1 {
            return "1 contribution — \(dateStr)"
        } else {
            return "\(day.count) contributions — \(dateStr)"
        }
    }
}

private struct ActivityHeatmapCell: View {
    let day: DayActivity
    let cellSize: CGFloat

    @State private var isHovered = false

    var body: some View {
        if day.count < 0 {
            Color.clear
                .frame(width: cellSize, height: cellSize)
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(day.level.color)
                .frame(width: cellSize, height: cellSize)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.white.opacity(isHovered ? 0.3 : 0), lineWidth: 1)
                )
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: isHovered) { _, hovered in
                                if hovered {
                                    let frame = geo.frame(in: .named("heatmapGrid"))
                                    HeatmapTooltipState.shared.show(
                                        day: day,
                                        anchor: CGPoint(x: frame.midX, y: frame.minY)
                                    )
                                } else {
                                    HeatmapTooltipState.shared.dismiss(matching: day.date)
                                }
                            }
                    }
                }
                .onHover { isHovered = $0 }
                .onTapGesture {
                    NavigationState.shared.navigateToDate(day.date)
                }
        }
    }
}

/// Tooltip overlay rendered above the entire heatmap grid — never clipped by cells.
private struct HeatmapTooltipOverlay: View {
    private var state: HeatmapTooltipState { HeatmapTooltipState.shared }
    @State private var tooltipSize: CGSize = .zero
    private var tune: TooltipTuning { TooltipTuning.shared }

    var body: some View {
        GeometryReader { geo in
            if let text = state.tooltipText {
                let containerWidth = geo.size.width
                let idealX = state.anchor.x - tooltipSize.width / 2
                let margin: CGFloat = 4
                // Clamp so tooltip doesn't overflow left or right edge
                let clampedX = min(max(idealX, margin), containerWidth - tooltipSize.width - margin)
                // Arrow stays centered on the cell regardless of pill shift
                let arrowX = state.anchor.x - clampedX - tune.arrowSize

                VStack(spacing: 0) {
                    Text(text)
                        .font(.system(size: tune.fontSize, weight: .medium))
                        .foregroundColor(Theme.current.foreground)
                        .padding(.horizontal, tune.horizontalPadding)
                        .padding(.vertical, tune.verticalPadding)
                        .background(
                            RoundedRectangle(cornerRadius: tune.cornerRadius)
                                .fill(Theme.current.surfaceBase)
                                .shadow(color: .black.opacity(tune.shadowOpacity), radius: tune.shadowRadius, x: 0, y: 2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: tune.cornerRadius)
                                .stroke(Theme.current.foreground.opacity(0.12), lineWidth: 0.5)
                        )

                    // Down-pointing arrow — offset to stay centered on cell
                    HStack(spacing: 0) {
                        Spacer().frame(width: max(0, arrowX))
                        TooltipArrow(direction: .down)
                            .fill(Theme.current.surfaceBase)
                            .frame(width: tune.arrowSize * 2, height: tune.arrowSize)
                        Spacer().frame(minWidth: 0)
                    }
                    .frame(width: tooltipSize.width > 0 ? tooltipSize.width : nil)
                }
                .fixedSize(horizontal: true, vertical: true)
                .background {
                    GeometryReader { tipGeo in
                        Color.clear.onAppear { tooltipSize = tipGeo.size }
                            .onChange(of: tipGeo.size) { _, s in tooltipSize = s }
                    }
                }
                .offset(
                    x: clampedX,
                    y: state.anchor.y - tooltipSize.height - tune.offsetDistance
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.1), value: state.day?.date)
            }
        }
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    let icon: String
    let gradientColors: [Color]
    let title: String
    let subtitle: String
    let buttonTitle: String
    let buttonAction: () -> Void

    @State private var isHovered = false
    @State private var isButtonHovered = false

    var body: some View {
        VStack(spacing: Spacing.md) {
            // Animated icon with gradient
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [gradientColors[0].opacity(0.2), gradientColors[1].opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 64, height: 64)
                    .scaleEffect(isHovered ? 1.1 : 1.0)

                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(isHovered ? 1.05 : 1.0)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isHovered)

            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(Theme.current.fontBodyMedium)
                    .foregroundColor(Theme.current.foreground)

                Text(subtitle)
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            Button(action: buttonAction) {
                Text(buttonTitle)
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(.white)
                    .scaleEffect(isButtonHovered ? 1.05 : 1.0)
            }
            .buttonStyle(.adaptiveGlassProminent)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isButtonHovered)
            .onHover { hovering in
                isButtonHovered = hovering
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Activity Level

enum ActivityLevel: Int {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3
    case max = 4

    var color: Color {
        switch self {
        case .none: return Color.gray.opacity(0.15)
        case .low: return Color.green.opacity(0.3)
        case .medium: return Color.green.opacity(0.5)
        case .high: return Color.green.opacity(0.7)
        case .max: return Color.green
        }
    }

    static func from(count: Int, max: Int) -> ActivityLevel {
        if count <= 0 { return .none }
        if max <= 0 { return .none }
        let ratio = Double(count) / Double(max)
        switch ratio {
        case 0..<0.25: return .low
        case 0.25..<0.5: return .medium
        case 0.5..<0.75: return .high
        default: return .max
        }
    }
}

// MARK: - Day Activity

struct DayActivity: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
    let level: ActivityLevel
}

// MARK: - Search Trigger Pill

private struct SearchTriggerPill: View {
    @State private var isSearchHovered = false
    @State private var isPaletteHovered = false

    var body: some View {
        HStack(spacing: 6) {
            // Content search pill
            Button {
                NotificationCenter.default.post(name: .showContentSearch, object: nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.current.foregroundMuted)

                    Text("Search...")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.current.foregroundMuted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Theme.current.surface1)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Theme.current.border.opacity(isSearchHovered ? 0.25 : 0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .onHover { isSearchHovered = $0 }

            // Command palette chip
            Button {
                NotificationCenter.default.post(name: .showCommandPalette, object: nil)
            } label: {
                Text("\u{2325}\u{2318}K")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.current.surface1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Theme.current.border.opacity(isPaletteHovered ? 0.25 : 0.1), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .onHover { isPaletteHovered = $0 }
        }
    }
}

// MARK: - Preference Keys

/// Preference key to measure content width for responsive layouts
private struct ContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 800
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Preference key to capture widgetsRow3 frame for floating activity expansion
private struct WidgetsRow3FrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// MARK: - Preview

#Preview {
    HomeScreen()
        .frame(width: 800, height: 700)
}

// MARK: - Backwards Compatibility Alias
typealias UnifiedDashboard = HomeScreen
