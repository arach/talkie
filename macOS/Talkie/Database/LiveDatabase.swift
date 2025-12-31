//
//  LiveDatabase.swift
//  Talkie (READ-ONLY COPY)
//
//  Read-only access to live.sqlite for the Talkie app.
//  TalkieLive owns all writes - Talkie only reads.
//  See CLAUDE.md "Data Ownership" for architecture details.
//

import Foundation
import GRDB
import TalkieKit

private let log = Log(.database)

enum LiveDatabase {
    /// Database filename
    static let dbFilename = "live.sqlite"

    /// Shared folder for all Talkie apps (unsandboxed)
    static let folderName = "Talkie"

    /// The resolved database URL (Application Support, shared by all apps)
    /// ~/Library/Application Support/Talkie/live.sqlite
    /// Falls back to temp directory if Application Support unavailable (should never happen)
    static let databaseURL: URL = {
        let fm = FileManager.default

        // Use shared Application Support directory - all apps are unsandboxed
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let folderURL = appSupport.appendingPathComponent(folderName, isDirectory: true)
            try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let dbURL = folderURL.appendingPathComponent(dbFilename)
            log.info("[LiveDatabase] Using shared database path: \(dbURL.path)")
            return dbURL
        }

        // Fallback to temp directory (should never happen on macOS)
        log.error("[LiveDatabase] Application Support unavailable, using temp directory")
        let tempURL = fm.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
        try? fm.createDirectory(at: tempURL, withIntermediateDirectories: true)
        return tempURL.appendingPathComponent(dbFilename)
    }()

    static let shared: DatabaseQueue = {
        // IMPORTANT: Talkie opens READ-ONLY - TalkieLive owns all writes and migrations
        // If DB doesn't exist yet, TalkieLive hasn't run - return empty in-memory DB
        let fm = FileManager.default
        guard fm.fileExists(atPath: databaseURL.path) else {
            log.info("[LiveDatabase] Database not found - TalkieLive hasn't created it yet")
            return try! DatabaseQueue() // Empty in-memory until TalkieLive runs
        }

        do {
            var config = Configuration()
            config.readonly = true
            let dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: config)
            log.info("[LiveDatabase] Opened READ-ONLY: \(databaseURL.path)")
            return dbQueue
        } catch {
            log.error("[LiveDatabase] Failed to open read-only: \(error.localizedDescription)")
            return try! DatabaseQueue() // Fallback to empty in-memory
        }
    }()
}

// MARK: - Read Operations (Talkie is read-only - TalkieLive owns writes)

extension LiveDatabase {
    static func fetch(id: Int64) -> LiveDictation? {
        try? shared.read { db in
            try LiveDictation.fetchOne(db, id: id)
        }
    }

    static func all() -> [LiveDictation] {
        (try? shared.read { db in
            try LiveDictation
                .order(LiveDictation.Columns.createdAt.desc)
                .fetchAll(db)
        }) ?? []
    }

    static func recent(limit: Int = 100) -> [LiveDictation] {
        (try? shared.read { db in
            try LiveDictation
                .order(LiveDictation.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []
    }

    /// Fetch dictations with ID greater than specified (for incremental updates)
    /// Uses INTEGER PRIMARY KEY for optimal performance - O(log n) seek + O(k) scan
    static func since(id: Int64) -> [LiveDictation] {
        (try? shared.read { db in
            try LiveDictation
                .filter(LiveDictation.Columns.id > id)
                .order(LiveDictation.Columns.id.asc)  // Sequential order for processing
                .fetchAll(db)
        }) ?? []
    }

    static func search(_ query: String) -> [LiveDictation] {
        guard !query.isEmpty else { return all() }
        return (try? shared.read { db in
            try LiveDictation
                .filter(LiveDictation.Columns.text.like("%\(query)%"))
                .order(LiveDictation.Columns.createdAt.desc)
                .fetchAll(db)
        }) ?? []
    }

    static func byApp(_ bundleID: String) -> [LiveDictation] {
        (try? shared.read { db in
            try LiveDictation
                .filter(LiveDictation.Columns.appBundleID == bundleID)
                .order(LiveDictation.Columns.createdAt.desc)
                .fetchAll(db)
        }) ?? []
    }

    static func count() -> Int {
        (try? shared.read { db in
            try LiveDictation.fetchCount(db)
        }) ?? 0
    }

    // MARK: - Stats Queries (for app_stats table)

    /// Count dictations from today
    static func countToday() -> Int {
        let todayStart = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        return (try? shared.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM dictations WHERE createdAt >= ?",
                arguments: [todayStart]
            )
        }) ?? 0
    }

    /// Count dictations from last 7 days
    static func countWeek() -> Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())?.timeIntervalSince1970 ?? 0
        return (try? shared.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM dictations WHERE createdAt >= ?",
                arguments: [weekAgo]
            )
        }) ?? 0
    }

    /// Sum of all word counts
    static func totalWords() -> Int {
        (try? shared.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(wordCount), 0) FROM dictations"
            )
        }) ?? 0
    }

    /// Top apps by dictation count
    static func topApps(limit: Int = 5) -> [(name: String, bundleID: String?, count: Int)] {
        (try? shared.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT appName, appBundleID, COUNT(*) as cnt
                    FROM dictations
                    WHERE appName IS NOT NULL AND appName != ''
                    GROUP BY appName
                    ORDER BY cnt DESC
                    LIMIT ?
                    """,
                arguments: [limit]
            )
            return rows.map { row in
                (
                    name: row["appName"] as String? ?? "",
                    bundleID: row["appBundleID"] as String?,
                    count: row["cnt"] as Int? ?? 0
                )
            }
        }) ?? []
    }

    /// Activity data for contribution graph (fast GROUP BY, no record loading)
    /// Returns counts per day for the last N days
    static func activityByDay(days: Int = 91) -> [String: Int] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())?.timeIntervalSince1970 ?? 0
        log.debug("activityByDay: cutoff=\(cutoff), days=\(days)")

        return (try? shared.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT date(createdAt, 'unixepoch', 'localtime') as day, COUNT(*) as cnt
                    FROM dictations
                    WHERE createdAt >= ?
                    GROUP BY day
                    """,
                arguments: [cutoff]
            )
            log.debug("activityByDay: got \(rows.count) rows")
            var result: [String: Int] = [:]
            for row in rows {
                // SQLite returns Int64 for COUNT(*), need explicit conversion
                if let day = row["day"] as? String {
                    let count: Int
                    if let int64 = row["cnt"] as? Int64 {
                        count = Int(int64)
                    } else if let int = row["cnt"] as? Int {
                        count = int
                    } else {
                        continue
                    }
                    result[day] = count
                }
            }
            return result
        }) ?? [:]
    }

    /// Calculate current streak (consecutive days with dictations)
    static func calculateStreak() -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Get distinct days with dictations (last 365 days max)
        let yearAgo = calendar.date(byAdding: .day, value: -365, to: today)?.timeIntervalSince1970 ?? 0
        let daysWithDictations: Set<Date> = (try? shared.read { db in
            let timestamps = try Double.fetchAll(
                db,
                sql: "SELECT DISTINCT date(createdAt, 'unixepoch', 'localtime') as d FROM dictations WHERE createdAt >= ? ORDER BY d DESC",
                arguments: [yearAgo]
            )
            // Actually we need the dates, let me query differently
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT date(createdAt, 'unixepoch', 'localtime') as day
                    FROM dictations
                    WHERE createdAt >= ?
                    """,
                arguments: [yearAgo]
            )
            var dates: Set<Date> = []
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            for row in rows {
                if let dayStr = row["day"] as? String,
                   let date = formatter.date(from: dayStr) {
                    dates.insert(calendar.startOfDay(for: date))
                }
            }
            return dates
        }) ?? []

        // Count consecutive days from today (or yesterday if no activity today)
        var checkDate = today
        if !daysWithDictations.contains(today) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
            checkDate = yesterday
        }

        var streak = 0
        while daysWithDictations.contains(checkDate) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
            if streak > 365 { break }
        }
        return streak
    }

    // prune() removed - TalkieLive owns writes

    /// Preview what would be pruned (count and oldest date) - read-only
    static func prunePreview(olderThanHours hours: Int) -> (count: Int, oldestDate: Date?, newestDate: Date?) {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 60 * 60)
        let cutoffTS = cutoff.timeIntervalSince1970

        return (try? shared.read { db -> (Int, Date?, Date?) in
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM dictations WHERE createdAt < ?",
                arguments: [cutoffTS]
            ) ?? 0

            let oldest: Double? = try Double.fetchOne(
                db,
                sql: "SELECT MIN(createdAt) FROM dictations WHERE createdAt < ?",
                arguments: [cutoffTS]
            )

            let newest: Double? = try Double.fetchOne(
                db,
                sql: "SELECT MAX(createdAt) FROM dictations WHERE createdAt < ?",
                arguments: [cutoffTS]
            )

            return (
                count,
                oldest.map { Date(timeIntervalSince1970: $0) },
                newest.map { Date(timeIntervalSince1970: $0) }
            )
        }) ?? (0, nil, nil)
    }

    /// Get all audio filenames referenced in database
    static func allAudioFilenames() -> Set<String> {
        let filenames: [String] = (try? shared.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT audioFilename FROM dictations WHERE audioFilename IS NOT NULL"
            )
        }) ?? []
        return Set(filenames)
    }
}

// MARK: - Promotion Methods (removed - TalkieLive owns writes)
// markAsMemo, markAsCommand, markAsIgnored, resetPromotion moved to TalkieLive

// MARK: - Filtered Queries

extension LiveDatabase {
    static func needsAction(limit: Int = 100) -> [LiveDictation] {
        (try? shared.read { db in
            try LiveDictation
                .filter(LiveDictation.Columns.promotionStatus == PromotionStatus.none.rawValue)
                .order(LiveDictation.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []
    }

    static func byStatus(_ status: PromotionStatus, limit: Int = 100) -> [LiveDictation] {
        (try? shared.read { db in
            try LiveDictation
                .filter(LiveDictation.Columns.promotionStatus == status.rawValue)
                .order(LiveDictation.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []
    }

    static func countNeedsAction() -> Int {
        (try? shared.read { db in
            try LiveDictation
                .filter(LiveDictation.Columns.promotionStatus == PromotionStatus.none.rawValue)
                .fetchCount(db)
        }) ?? 0
    }
}

// MARK: - Queue Methods

extension LiveDatabase {
    static func fetchQueued() -> [LiveDictation] {
        (try? shared.read { db in
            try LiveDictation
                .filter(LiveDictation.Columns.createdInTalkieView == 1)
                .filter(LiveDictation.Columns.pasteTimestamp == nil)
                .filter(LiveDictation.Columns.promotionStatus == PromotionStatus.none.rawValue)
                .order(LiveDictation.Columns.createdAt.desc)
                .fetchAll(db)
        }) ?? []
    }

    static func countQueued() -> Int {
        (try? shared.read { db in
            try LiveDictation
                .filter(LiveDictation.Columns.createdInTalkieView == 1)
                .filter(LiveDictation.Columns.pasteTimestamp == nil)
                .filter(LiveDictation.Columns.promotionStatus == PromotionStatus.none.rawValue)
                .fetchCount(db)
        }) ?? 0
    }
    // markPasted removed - TalkieLive owns writes
}

// MARK: - Live State Methods (Real-time sync between apps)

extension LiveDatabase {
    /// Get current live state (read-only)
    static func getLiveState() -> (state: String, elapsedTime: TimeInterval, transcript: String)? {
        try? shared.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT state, elapsedTime, transcript FROM live_state WHERE id = 1") else {
                return nil
            }
            return (
                state: row["state"] as String? ?? "idle",
                elapsedTime: row["elapsedTime"] as TimeInterval? ?? 0,
                transcript: row["transcript"] as String? ?? ""
            )
        }
    }
    // updateLiveState and resetLiveState removed - TalkieLive owns writes
}

// MARK: - Transcription Retry Methods

extension LiveDatabase {
    static func fetchNeedsRetry() -> [LiveDictation] {
        (try? shared.read { db in
            try LiveDictation
                .filter(
                    LiveDictation.Columns.transcriptionStatus == TranscriptionStatus.failed.rawValue ||
                    LiveDictation.Columns.transcriptionStatus == TranscriptionStatus.pending.rawValue
                )
                .filter(LiveDictation.Columns.audioFilename != nil)
                .order(LiveDictation.Columns.createdAt.desc)
                .fetchAll(db)
        }) ?? []
    }

    static func countNeedsRetry() -> Int {
        (try? shared.read { db in
            try LiveDictation
                .filter(
                    LiveDictation.Columns.transcriptionStatus == TranscriptionStatus.failed.rawValue ||
                    LiveDictation.Columns.transcriptionStatus == TranscriptionStatus.pending.rawValue
                )
                .filter(LiveDictation.Columns.audioFilename != nil)
                .fetchCount(db)
        }) ?? 0
    }
    // markTranscriptionSuccess, markTranscriptionFailed removed - TalkieLive owns writes
}
