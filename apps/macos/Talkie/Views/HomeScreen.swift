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
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.orange.gradient)
                .clipShape(.rect(cornerRadius: 8))
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
                        .foregroundStyle(.orange)
                    Text("\(streak) day streak")
                        .foregroundStyle(.orange)
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
            let millions = (Double(n) / 1_000_000).formatted(.number.precision(.fractionLength(1)))
            return "\(millions)M"
        } else if n >= 1000 {
            let thousands = (Double(n) / 1_000).formatted(.number.precision(.fractionLength(1)))
            return "\(thousands)k"
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
