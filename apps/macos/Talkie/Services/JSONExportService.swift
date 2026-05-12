//
//  JSONExportService.swift
//  Talkie macOS
//
//  Exports all memos to JSON files for power users.
//  MIGRATED: Now uses GRDB via LocalRepository instead of Core Data.
//
//  Lives in Application Support/Talkie/export/
//
//  Export strategy:
//  - recordings.json: Full export (all memos) - weekly deep run
//  - recordings-recent.json: Shallow export (modified in last 2 days) - daily
//
//  Users rsync this to their preferred location.
//

import Foundation
import os
import TalkieKit

private let logger = Logger(subsystem: "to.talkie.app.mac", category: "JSONExport")

// MARK: - Export Models

struct ExportedMemo: Codable {
    let id: String
    let title: String
    let createdAt: String
    let duration: Double
    let transcription: String?
    let summary: String?
    let tasks: String?
    let notes: String?
    let reminders: String?
    let originDevice: String?
    let lastModified: String?
    let audioFile: String?
    // Note: workflowRuns removed - will be managed via API
}

struct RecordingsExport: Codable {
    let version: Int
    let exportedAt: String
    let exportType: String  // "full" or "recent"
    let memoCount: Int
    let memos: [ExportedMemo]
}

// MARK: - JSON Export Service

@MainActor
final class JSONExportService: NSObject {
    static let shared = JSONExportService()

    private let fileManager = FileManager.default
    private let repository = LocalRepository()
    private var dailyTask: Task<Void, Never>?
    private var weeklyTask: Task<Void, Never>?

    /// How far back "recent" looks (2 days)
    private let recentWindow: TimeInterval = 2 * 24 * 60 * 60

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Export directory: ~/Library/Application Support/Talkie/export/
    var exportDirectoryURL: URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: NSTemporaryDirectory())
        }
        return appSupport
            .appendingPathComponent("Talkie", isDirectory: true)
            .appendingPathComponent("export", isDirectory: true)
    }

    /// Full export: recordings.json
    var fullExportURL: URL {
        exportDirectoryURL.appendingPathComponent("recordings.json")
    }

    /// Recent export: recordings-recent.json
    var recentExportURL: URL {
        exportDirectoryURL.appendingPathComponent("recordings-recent.json")
    }

    private override init() {
        super.init()
    }

    // MARK: - Configuration

    /// Configure the service and start scheduled exports
    /// Note: context parameter is ignored - now uses GRDB
    func configure(with context: Any? = nil) {
        // Ensure export directory exists
        ensureExportDirectoryExists()

        // Listen for schedule changes
        NotificationCenter.default.removeObserver(self, name: .jsonExportScheduleDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScheduleDidChange),
            name: .jsonExportScheduleDidChange,
            object: nil
        )

        // Start scheduled exports based on settings
        startScheduledExports()

        // Run initial export if no JSON exists
        if !fileManager.fileExists(atPath: fullExportURL.path) {
            exportFull()
        }

        logger.info("JSONExportService configured (schedule: \(SettingsManager.shared.jsonExportSchedule.rawValue))")
    }

    @objc
    private func handleScheduleDidChange(_ notification: Notification) {
        startScheduledExports()
    }

    private func ensureExportDirectoryExists() {
        if !fileManager.fileExists(atPath: exportDirectoryURL.path) {
            do {
                try fileManager.createDirectory(at: exportDirectoryURL, withIntermediateDirectories: true)
                logger.info("Created export directory: \(self.exportDirectoryURL.path)")
            } catch {
                logger.error("Failed to create export directory: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Scheduled Exports

    func startScheduledExports() {
        stopScheduledExports()

        let schedule = SettingsManager.shared.jsonExportSchedule

        switch schedule {
        case .manual:
            logger.info("JSON export schedule: manual only")
            return

        case .dailyShallow:
            // Daily shallow export (every 24 hours)
            scheduleDailyExport()
            logger.info("JSON export: daily shallow")

        case .dailyShallowWeeklyDeep:
            // Daily shallow + weekly deep
            scheduleDailyExport()
            scheduleWeeklyExport()
            logger.info("JSON export: daily shallow + weekly deep")

        case .weeklyDeep:
            // Weekly deep export only
            scheduleWeeklyExport()
            logger.info("JSON export: weekly deep")
        }
    }

    private func scheduleDailyExport() {
        // Run daily at 3 AM (or now + 24h if past 3 AM)
        let nextRun = nextScheduledTime(hour: 3, minute: 0)
        dailyTask = Task {
            try? await Task.sleep(for: .seconds(max(0, nextRun.timeIntervalSinceNow)))
            while !Task.isCancelled {
                exportRecent()
                try? await Task.sleep(for: .seconds(24 * 60 * 60))
            }
        }
        logger.info("Daily export scheduled for \(nextRun)")
    }

    private func scheduleWeeklyExport() {
        // Run weekly on Sunday at 4 AM
        let nextRun = nextWeeklySunday(hour: 4, minute: 0)
        weeklyTask = Task {
            try? await Task.sleep(for: .seconds(max(0, nextRun.timeIntervalSinceNow)))
            while !Task.isCancelled {
                exportFull()
                try? await Task.sleep(for: .seconds(7 * 24 * 60 * 60))
            }
        }
        logger.info("Weekly export scheduled for \(nextRun)")
    }

    private func nextScheduledTime(hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let now = Date()

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0

        if let scheduledToday = calendar.date(from: components), scheduledToday > now {
            return scheduledToday
        }

        // Tomorrow at the specified time
        return calendar.date(byAdding: .day, value: 1, to: calendar.date(from: components)!) ?? now
    }

    private func nextWeeklySunday(hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let now = Date()

        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        components.weekday = 1  // Sunday
        components.hour = hour
        components.minute = minute
        components.second = 0

        if let nextSunday = calendar.date(from: components), nextSunday > now {
            return nextSunday
        }

        // Next week's Sunday
        return calendar.date(byAdding: .weekOfYear, value: 1, to: calendar.date(from: components)!) ?? now
    }

    func stopScheduledExports() {
        dailyTask?.cancel()
        dailyTask = nil
        weeklyTask?.cancel()
        weeklyTask = nil
    }

    // MARK: - Export Methods

    /// Export recent memos (modified in last 2 days) - shallow daily run
    func exportRecent() {
        let cutoffDate = Date().addingTimeInterval(-recentWindow)

        Task {
            do {
                // Fetch all memos sorted by date, no limit for export
                let allMemos = try await repository.fetchMemos(
                    sortBy: .timestamp,
                    ascending: false,
                    limit: 100000,  // Effectively no limit
                    offset: 0
                )
                let recentMemos = allMemos.filter { memo in
                    return memo.lastModified >= cutoffDate || memo.createdAt >= cutoffDate
                }

                if recentMemos.isEmpty {
                    logger.info("No recent memos to export (last 2 days)")
                    return
                }

                let exportedMemos = recentMemos.map { exportMemo($0) }

                let export = RecordingsExport(
                    version: 2,  // Version 2: GRDB-based, no workflow runs
                    exportedAt: isoFormatter.string(from: Date()),
                    exportType: "recent",
                    memoCount: exportedMemos.count,
                    memos: exportedMemos
                )

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(export)

                try data.write(to: recentExportURL)

                logger.info("Exported \(exportedMemos.count) recent memos to recordings-recent.json")
            } catch {
                logger.error("Failed to export recent memos: \(error.localizedDescription)")
            }
        }
    }

    /// Export all memos - deep weekly run
    func exportFull() {
        Task {
            do {
                // Fetch all memos sorted by date, no limit for export
                let allMemos = try await repository.fetchMemos(
                    sortBy: .timestamp,
                    ascending: false,
                    limit: 100000,  // Effectively no limit
                    offset: 0
                )
                let exportedMemos = allMemos.map { exportMemo($0) }

                let export = RecordingsExport(
                    version: 2,  // Version 2: GRDB-based, no workflow runs
                    exportedAt: isoFormatter.string(from: Date()),
                    exportType: "full",
                    memoCount: exportedMemos.count,
                    memos: exportedMemos
                )

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(export)

                try data.write(to: fullExportURL)

                logger.info("Exported \(exportedMemos.count) memos to recordings.json (full)")
            } catch {
                logger.error("Failed to export memos: \(error.localizedDescription)")
            }
        }
    }

    /// Export now (manual trigger) - runs both recent and full
    func exportNow() {
        exportRecent()
        exportFull()
    }

    /// Convert a MemoModel to an exportable struct
    private func exportMemo(_ memo: MemoModel) -> ExportedMemo {
        return ExportedMemo(
            id: memo.id.uuidString,
            title: memo.title ?? "Untitled",
            createdAt: isoFormatter.string(from: memo.createdAt),
            duration: memo.duration,
            transcription: memo.transcription,
            summary: memo.summary,
            tasks: memo.tasks,
            notes: memo.notes,
            reminders: memo.reminders,
            originDevice: memo.originDeviceId,
            lastModified: isoFormatter.string(from: memo.lastModified),
            audioFile: memo.audioFilePath
        )
    }

    // MARK: - Stats

    /// Get export file stats
    func getStats() -> (fullExists: Bool, recentExists: Bool, fullMemoCount: Int, recentMemoCount: Int, totalSize: Int64, lastFullExport: Date?, lastRecentExport: Date?) {
        var fullMemoCount = 0
        var recentMemoCount = 0
        var totalSize: Int64 = 0
        var lastFullExport: Date? = nil
        var lastRecentExport: Date? = nil

        // Check full export
        let fullExists = fileManager.fileExists(atPath: fullExportURL.path)
        if fullExists {
            if let attrs = try? fileManager.attributesOfItem(atPath: fullExportURL.path) {
                totalSize += attrs[.size] as? Int64 ?? 0
                lastFullExport = attrs[.modificationDate] as? Date
            }
            if let data = try? Data(contentsOf: fullExportURL),
               let export = try? JSONDecoder().decode(RecordingsExport.self, from: data) {
                fullMemoCount = export.memoCount
            }
        }

        // Check recent export
        let recentExists = fileManager.fileExists(atPath: recentExportURL.path)
        if recentExists {
            if let attrs = try? fileManager.attributesOfItem(atPath: recentExportURL.path) {
                totalSize += attrs[.size] as? Int64 ?? 0
                lastRecentExport = attrs[.modificationDate] as? Date
            }
            if let data = try? Data(contentsOf: recentExportURL),
               let export = try? JSONDecoder().decode(RecordingsExport.self, from: data) {
                recentMemoCount = export.memoCount
            }
        }

        return (fullExists, recentExists, fullMemoCount, recentMemoCount, totalSize, lastFullExport, lastRecentExport)
    }
}
