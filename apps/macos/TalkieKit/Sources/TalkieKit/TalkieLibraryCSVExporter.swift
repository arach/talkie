//
//  TalkieLibraryCSVExporter.swift
//  TalkieKit
//
//  Export dictations, captures, and memos as CSV and open in Numbers.
//

import Foundation
import GRDB

#if canImport(AppKit)
import AppKit
#endif

public enum TalkieLibraryCSVExporter {
    public enum Kind: String, Sendable, CaseIterable {
        case dictations
        case captures
        case memos

        var objectType: TalkieObjectType {
            switch self {
            case .dictations: return .dictation
            case .captures: return .capture
            case .memos: return .memo
            }
        }

        var exportLabel: String {
            switch self {
            case .dictations: return "Dictations"
            case .captures: return "Captures"
            case .memos: return "Memos"
            }
        }
    }

    private static let log = Log(.database)
    private static let numbersBundleID = "com.apple.iWork.Numbers"

    @MainActor
    public static func exportAndOpenInNumbers(_ kind: Kind) {
        Task {
            do {
                let url = try await export(kind)
                openInNumbers(url)
            } catch {
                log.error("CSV export failed for \(kind.rawValue)", detail: error.localizedDescription)
            }
        }
    }

    public static func export(_ kind: Kind) async throws -> URL {
        let objects = try await fetchObjects(kind: kind)
        let csv = makeCSV(kind: kind, objects: objects)
        return try writeCSV(csv, kind: kind)
    }

    @concurrent
    private static func fetchObjects(kind: Kind) async throws -> [TalkieObject] {
        _ = TalkieDatabase.migrateFilenameIfNeeded()

        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA busy_timeout = 10000")
        }

        let dbQueue = try DatabaseQueue(path: TalkieDatabase.databaseURL.path, configuration: config)
        return try await dbQueue.read { db in
            try TalkieObject.fetchAll(
                db,
                sql: """
                SELECT * FROM recordings
                WHERE deletedAt IS NULL AND type = ?
                ORDER BY createdAt DESC
                """,
                arguments: [kind.objectType.rawValue]
            )
        }
    }

    static func makeCSV(kind: Kind, objects: [TalkieObject]) -> String {
        let headers = headers(for: kind)
        var lines = [headers.joined(separator: ",")]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        for object in objects {
            let values = rowValues(for: kind, object: object, dateFormatter: formatter)
            lines.append(values.map(csvField).joined(separator: ","))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func headers(for kind: Kind) -> [String] {
        switch kind {
        case .dictations:
            return [
                "id", "created_at", "text", "duration_seconds", "word_count",
                "app_name", "app_bundle_id", "window_title", "transcription_status", "source",
            ]
        case .captures:
            return [
                "id", "created_at", "title", "text", "duration_seconds",
                "app_name", "app_bundle_id", "capture_mode", "media_path", "source",
            ]
        case .memos:
            return [
                "id", "created_at", "title", "text", "duration_seconds", "word_count",
                "summary", "source",
            ]
        }
    }

    private static func rowValues(
        for kind: Kind,
        object: TalkieObject,
        dateFormatter: ISO8601DateFormatter
    ) -> [String] {
        let createdAt = dateFormatter.string(from: object.createdAt)
        switch kind {
        case .dictations:
            return [
                object.id.uuidString,
                createdAt,
                object.text ?? "",
                String(format: "%.2f", object.duration),
                String(object.wordCount),
                object.appContext?.name ?? "",
                object.appContext?.bundleId ?? "",
                object.appContext?.windowTitle ?? "",
                object.transcriptionStatus.rawValue,
                object.source.rawValue,
            ]
        case .captures:
            let screenshot = object.screenshots.first
            let captureMode = screenshot?.captureMode ?? object.clips.first?.captureMode ?? ""
            let mediaPath = CaptureMediaFileResolver.primaryMedia(for: object)?.url.path ?? ""
            return [
                object.id.uuidString,
                createdAt,
                object.title ?? object.displayTitle,
                object.text ?? "",
                String(format: "%.2f", object.duration),
                screenshot?.appName ?? object.appContext?.name ?? "",
                screenshot?.appBundleID ?? object.appContext?.bundleId ?? "",
                captureMode,
                mediaPath,
                object.source.rawValue,
            ]
        case .memos:
            return [
                object.id.uuidString,
                createdAt,
                object.title ?? "",
                object.text ?? "",
                String(format: "%.2f", object.duration),
                String(object.wordCount),
                object.summary ?? "",
                object.source.rawValue,
            ]
        }
    }

    static func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"\(value.replacing("\"", with: "\"\""))\""
        }
        return value
    }

    private static func writeCSV(_ csv: String, kind: Kind) throws -> URL {
        let exportsDirectory = TalkieDatabase.folderURL.appending(path: "Exports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)

        let stamp = exportTimestamp()
        let filename = "Talkie \(kind.exportLabel) - \(stamp).csv"
        let destination = uniqueURL(in: exportsDirectory, filename: filename)

        try Data(csv.utf8).write(to: destination, options: .atomic)
        return destination
    }

    private static func exportTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }

    private static func uniqueURL(in directory: URL, filename: String) -> URL {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = directory.appending(path: filename)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(base) (\(index)).\(ext)")
            index += 1
        }
        return candidate
    }

    @MainActor
    private static func openInNumbers(_ url: URL) {
        #if canImport(AppKit)
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: numbersBundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { _, error in
                if let error {
                    log.warning("Opening CSV in Numbers failed", detail: error.localizedDescription)
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }

        NSWorkspace.shared.open(url)
        #endif
    }
}