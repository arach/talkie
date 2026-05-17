//
//  StatsCache.swift
//  Talkie macOS
//
//  Session-level cache for the Stats screen.
//
//  Why this exists:
//    Stats screen used to load 8+ DB queries and a full Application
//    Support file-system enumeration on every visit, with the heavy
//    file work running on MainActor (FileManager.enumerator is sync,
//    and `Task {}` from a SwiftUI View inherits MainActor). Worst
//    observed: 27.5s freeze. The data also doesn't need to be fresh
//    on every visit — day-level granularity is plenty for stats.
//
//  Design:
//    Singleton, @MainActor for safe @State-style reads from views.
//    `refresh()` runs the heavy queries in detached tasks so the main
//    thread is never blocked. `refreshIfStale()` is the API for views:
//    no-ops if data was fetched recently; views read the published
//    properties either way, so the screen paints instantly even on
//    cold start (it just shows zeros until the first refresh lands).
//

import Foundation
import GRDB
import Observation

@MainActor
@Observable
final class StatsCache {
    static let shared = StatsCache()

    // Hero / panel stats
    var todayDictations: Int = 0
    var weekDictations: Int = 0
    var totalWords: Int = 0
    var streak: Int = 0
    var totalDictations: Int = 0

    // Top apps for "where dictation is used"
    var topApps: [TopApp] = []

    // Storage / workflow
    var deviceStorageBytes: Int64 = 0
    var workflowRunsCount: Int = 0

    // Activity heatmap (last ~13 weeks) + last-30 sparkline
    var activityData: [DayActivity] = []
    var maxDayCount: Int = 1
    var sparklineCounts: [Int] = []

    // Refresh state
    var lastRefreshed: Date?
    var isRefreshing: Bool = false

    /// Beyond this age, `refreshIfStale()` triggers a background load.
    /// One hour is the right zone for stats: rare enough that
    /// background refreshes are essentially free, fresh enough that a
    /// user returning later in the day sees up-to-date numbers.
    static let staleThreshold: TimeInterval = 60 * 60

    private init() {}

    var isStale: Bool {
        guard let last = lastRefreshed else { return true }
        return Date().timeIntervalSince(last) > Self.staleThreshold
    }

    /// Kicks off a background refresh only if the cache is stale.
    /// Views call this on appear; the screen paints with cached values
    /// immediately and updates when the refresh lands.
    func refreshIfStale() {
        guard isStale, !isRefreshing else { return }
        Task { await refresh() }
    }

    /// Force a refresh regardless of staleness (manual "refresh" button).
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Detach the heavy work so the main actor stays free for UI.
        // File enumeration in particular was running on MainActor and
        // could block for tens of seconds with large audio archives.
        let snapshot = await Task.detached(priority: .userInitiated) {
            await Self.fetchSnapshot()
        }.value

        apply(snapshot)
        lastRefreshed = Date()
    }

    private func apply(_ s: Snapshot) {
        todayDictations    = s.today
        weekDictations     = s.week
        totalWords         = s.totalWords
        streak             = s.streak
        totalDictations    = s.totalDictations
        topApps            = s.topApps
        deviceStorageBytes = s.storageBytes
        workflowRunsCount  = s.workflowRuns
        activityData       = s.activityData
        maxDayCount        = s.maxDayCount
        sparklineCounts    = s.sparklineCounts
    }

    // MARK: - Heavy lifting (off-main)

    /// Plain value type so we can hand a complete snapshot back to the
    /// MainActor in one hop instead of dozens of cross-actor calls.
    private struct Snapshot: Sendable {
        let today: Int
        let week: Int
        let totalWords: Int
        let streak: Int
        let totalDictations: Int
        let topApps: [TopApp]
        let storageBytes: Int64
        let workflowRuns: Int
        let activityData: [DayActivity]
        let maxDayCount: Int
        let sparklineCounts: [Int]
    }

    /// Runs entirely off MainActor (called from `Task.detached`).
    /// GRDB reads already dispatch to a background queue internally;
    /// what matters here is that the FileManager enumeration and the
    /// activity-day Date math don't run on main.
    private static func fetchSnapshot() async -> Snapshot {
        let repo = TalkieObjectRepository()

        async let todayQ        = repo.countRecordingsToday(type: .dictation)
        async let weekQ         = repo.countDictationsThisWeek()
        async let wordsQ        = repo.totalDictationWords()
        async let streakQ       = repo.calculateDictationStreak()
        async let appsQ         = repo.topDictationApps(limit: 6)
        async let totalQ        = repo.countDictations()
        async let activityQ     = repo.dictationActivityByDay(days: 365)

        // Storage scan + workflow count run concurrently with the DB work.
        async let storageBytes  = computeStorageBytes()
        async let workflowRuns  = computeWorkflowRunCount()

        let today  = (try? await todayQ) ?? 0
        let week   = (try? await weekQ) ?? 0
        let words  = (try? await wordsQ) ?? 0
        let strk   = (try? await streakQ) ?? 0
        let apps   = (try? await appsQ) ?? []
        let total  = (try? await totalQ) ?? 0
        let actMap = (try? await activityQ) ?? [:]

        let (days, maxCount, last30) = buildActivity(from: actMap)

        return Snapshot(
            today: today,
            week: week,
            totalWords: words,
            streak: strk,
            totalDictations: total,
            topApps: apps.map { TopApp(name: $0.name, bundleID: $0.bundleID, count: $0.count) },
            storageBytes: await storageBytes,
            workflowRuns: await workflowRuns,
            activityData: days,
            maxDayCount: maxCount,
            sparklineCounts: last30
        )
    }

    private static func computeStorageBytes() async -> Int64 {
        guard let audioDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Talkie")
            .appendingPathComponent("Audio") else {
            return 0
        }
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(
            at: audioDir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for case let fileURL as URL in enumerator {
                if let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) {
                    total += Int64(size)
                }
            }
        }
        return total
    }

    private static func computeWorkflowRunCount() async -> Int {
        do {
            let db = try await DatabaseManager.shared.databaseWhenReady()
            return try await db.read { db in
                try WorkflowRunModel.fetchCount(db)
            }
        } catch {
            return 0
        }
    }

    private static func buildActivity(
        from dayMap: [String: Int]
    ) -> (days: [DayActivity], maxCount: Int, last30: [Int]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weeksToShow = 13

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var dateMap: [Date: Int] = [:]
        for (dateString, count) in dayMap {
            if let date = dateFormatter.date(from: dateString) {
                dateMap[calendar.startOfDay(for: date), default: 0] += count
            }
        }

        let maxCount = max(dateMap.values.max() ?? 1, 1)

        let todayWeekday = calendar.component(.weekday, from: today)
        let daysBack = (weeksToShow - 1) * 7 + (todayWeekday - 1)
        guard let startDate = calendar.date(byAdding: .day, value: -daysBack, to: today) else {
            return ([], 1, [])
        }

        var days: [DayActivity] = []
        var cursor = startDate
        while cursor <= today {
            let count = dateMap[cursor] ?? 0
            let level = ActivityLevel.from(count: count, max: maxCount)
            days.append(DayActivity(date: cursor, count: count, level: level))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }

        var last30: [Int] = []
        for offset in stride(from: 29, through: 0, by: -1) {
            if let d = calendar.date(byAdding: .day, value: -offset, to: today) {
                last30.append(dateMap[calendar.startOfDay(for: d)] ?? 0)
            }
        }

        return (days, maxCount, last30)
    }
}

/// Sendable mirror of the `(name, bundleID, count)` tuple used by the
/// repo's top-apps query. Needed so the snapshot value type can cross
/// the actor boundary.
struct TopApp: Sendable, Hashable {
    let name: String
    let bundleID: String?
    let count: Int
}
