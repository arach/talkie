//
//  JSONExportService.swift
//  Talkie macOS
//
//  Exports all memos to JSON files for power users.
//  Lives in Application Support/Talkie/export/
//
//  Export strategy:
//  - recordings.json: Full export (all memos) - weekly deep run
//  - recordings-recent.json: Shallow export (modified in last 2 days) - daily
//
//  Users rsync this to their preferred location.
//

import Foundation
import CoreData
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "JSONExport")

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
    let workflowRuns: [ExportedWorkflowRun]
}

struct ExportedWorkflowRun: Codable {
    let id: String
    let workflowName: String
    let workflowIcon: String?
    let runDate: String
    let status: String
    let output: String?
    let modelId: String?
    let providerName: String?
}

struct RecordingsExport: Codable {
    let version: Int
    let exportedAt: String
    let exportType: String  // "full" or "recent"
    let memoCount: Int
    let memos: [ExportedMemo]
}

// MARK: - JSON Export Service

class JSONExportService {
    static let shared = JSONExportService()

    private let fileManager = FileManager.default
    private var dailyTimer: Timer?
    private var weeklyTimer: Timer?
    private var scheduleObserver: NSObjectProtocol?
    private weak var context: NSManagedObjectContext?

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

    private init() {}

    deinit {
        stopScheduledExports()
        if let observer = scheduleObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Configuration

    /// Configure the service with Core Data context and start scheduled exports
    func configure(with context: NSManagedObjectContext) {
        self.context = context

        // Ensure export directory exists
        ensureExportDirectoryExists()

        // Listen for schedule changes
        scheduleObserver = NotificationCenter.default.addObserver(
            forName: .jsonExportScheduleDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.startScheduledExports()
        }

        // Start scheduled exports based on settings
        startScheduledExports()

        // Run initial export if no JSON exists
        if !fileManager.fileExists(atPath: fullExportURL.path) {
            exportFull()
        }

        logger.info("JSONExportService configured (schedule: \(SettingsManager.shared.jsonExportSchedule.rawValue))")
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
        let interval: TimeInterval = 24 * 60 * 60  // 24 hours

        dailyTimer = Timer(fire: nextRun, interval: interval, repeats: true) { [weak self] _ in
            self?.exportRecent()
        }
        if let timer = dailyTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        logger.info("Daily export scheduled for \(nextRun)")
    }

    private func scheduleWeeklyExport() {
        // Run weekly on Sunday at 4 AM
        let nextRun = nextWeeklySunday(hour: 4, minute: 0)
        let interval: TimeInterval = 7 * 24 * 60 * 60  // 7 days

        weeklyTimer = Timer(fire: nextRun, interval: interval, repeats: true) { [weak self] _ in
            self?.exportFull()
        }
        if let timer = weeklyTimer {
            RunLoop.main.add(timer, forMode: .common)
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
        dailyTimer?.invalidate()
        dailyTimer = nil
        weeklyTimer?.invalidate()
        weeklyTimer = nil
    }

    // MARK: - Export Methods

    /// Export recent memos (modified in last 2 days) - shallow daily run
    func exportRecent() {
        guard let context = context else {
            logger.warning("Cannot export - no Core Data context")
            return
        }

        let cutoffDate = Date().addingTimeInterval(-recentWindow)

        context.perform { [weak self] in
            guard let self = self else { return }

            let fetchRequest: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "lastModified >= %@ OR createdAt >= %@", cutoffDate as NSDate, cutoffDate as NSDate)
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \VoiceMemo.lastModified, ascending: false)]

            do {
                let memos = try context.fetch(fetchRequest)

                if memos.isEmpty {
                    logger.info("No recent memos to export (last 2 days)")
                    return
                }

                let exportedMemos = memos.compactMap { self.exportMemo($0) }

                let export = RecordingsExport(
                    version: 1,
                    exportedAt: self.isoFormatter.string(from: Date()),
                    exportType: "recent",
                    memoCount: exportedMemos.count,
                    memos: exportedMemos
                )

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(export)

                try data.write(to: self.recentExportURL)

                logger.info("Exported \(exportedMemos.count) recent memos to recordings-recent.json")
            } catch {
                logger.error("Failed to export recent memos: \(error.localizedDescription)")
            }
        }
    }

    /// Export all memos - deep weekly run
    func exportFull() {
        guard let context = context else {
            logger.warning("Cannot export - no Core Data context")
            return
        }

        context.perform { [weak self] in
            guard let self = self else { return }

            let fetchRequest: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)]

            do {
                let memos = try context.fetch(fetchRequest)
                let exportedMemos = memos.compactMap { self.exportMemo($0) }

                let export = RecordingsExport(
                    version: 1,
                    exportedAt: self.isoFormatter.string(from: Date()),
                    exportType: "full",
                    memoCount: exportedMemos.count,
                    memos: exportedMemos
                )

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(export)

                try data.write(to: self.fullExportURL)

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

    /// Convert a VoiceMemo to an exportable struct
    private func exportMemo(_ memo: VoiceMemo) -> ExportedMemo? {
        guard let id = memo.id else { return nil }

        // Export workflow runs
        var workflowRuns: [ExportedWorkflowRun] = []
        if let runs = memo.workflowRuns as? Set<WorkflowRun> {
            workflowRuns = runs.compactMap { run -> ExportedWorkflowRun? in
                guard let runId = run.id else { return nil }
                return ExportedWorkflowRun(
                    id: runId.uuidString,
                    workflowName: run.workflowName ?? "Unknown",
                    workflowIcon: run.workflowIcon,
                    runDate: run.runDate.map { isoFormatter.string(from: $0) } ?? "",
                    status: run.status ?? "unknown",
                    output: run.output,
                    modelId: run.modelId,
                    providerName: run.providerName
                )
            }.sorted { $0.runDate > $1.runDate }
        }

        // Build audio file reference if available
        var audioFile: String? = nil
        if let fileURL = memo.fileURL {
            audioFile = URL(fileURLWithPath: fileURL).lastPathComponent
        }

        return ExportedMemo(
            id: id.uuidString,
            title: memo.title ?? "Untitled",
            createdAt: memo.createdAt.map { isoFormatter.string(from: $0) } ?? "",
            duration: memo.duration,
            transcription: memo.currentTranscript,
            summary: memo.summary,
            tasks: memo.tasks,
            notes: memo.notes,
            reminders: memo.reminders,
            originDevice: memo.originDeviceId,
            lastModified: memo.lastModified.map { isoFormatter.string(from: $0) },
            audioFile: audioFile,
            workflowRuns: workflowRuns
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
