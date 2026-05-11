//
//  MarkdownFileWriter.swift
//  Talkie
//
//  Persists every TalkieObject as a .md file on disk.
//  DB stays source of truth; the filesystem is a browsable shadow.
//
//  Directory: ~/Documents/Talkie/{type}/
//  Filename:  {date}_{slug}_{shortId}.md
//
//  Called from RecordingRepository on save/update/delete.
//

import Foundation
import TalkieKit

private let log = Log(.database)

enum MarkdownFileWriter {

    // MARK: - Root Directory

    static let rootDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Talkie", isDirectory: true)
    }()

    // MARK: - Write

    /// Write (or overwrite) the .md file for a TalkieObject.
    static func write(_ object: TalkieObject) {
        guard shouldWrite(object) else { return }

        let dir = typeDirectory(for: object.type)
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            log.error("[MarkdownFileWriter] Failed to create directory: \(error)")
            return
        }

        // Remove any previous file for this ID (slug may have changed)
        removeExisting(id: object.id, in: dir)

        let filename = self.filename(for: object)
        let fileURL = dir.appendingPathComponent(filename)
        let content = markdown(for: object)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            log.debug("[MarkdownFileWriter] Wrote \(fileURL.lastPathComponent)")
        } catch {
            log.error("[MarkdownFileWriter] Write failed: \(error)")
        }
    }

    // MARK: - Delete

    /// Remove the .md file for a TalkieObject.
    static func delete(id: UUID, type: TalkieObjectType) {
        let dir = typeDirectory(for: type)
        removeExisting(id: id, in: dir)
    }

    // MARK: - Bulk Export

    /// Export all objects (for initial backfill or recovery).
    static func exportAll(_ objects: [TalkieObject]) {
        var count = 0
        for object in objects {
            guard shouldWrite(object) else { continue }
            write(object)
            count += 1
        }
        log.info("[MarkdownFileWriter] Exported \(count) objects to ~/Documents/Talkie/")
    }

    /// One-time backfill: if ~/Documents/Talkie/memo/ doesn't exist yet, export everything.
    /// Call once at app startup.
    static func backfillIfNeeded() async {
        let fm = FileManager.default
        let memoDir = typeDirectory(for: .memo)

        // If memo directory already exists, we've already backfilled
        if fm.fileExists(atPath: memoDir.path) { return }

        // Clean up old plural directories from previous run
        for old in ["memos", "dictations", "notes"] {
            let oldDir = rootDirectory.appendingPathComponent(old)
            if fm.fileExists(atPath: oldDir.path) {
                try? fm.removeItem(at: oldDir)
            }
        }

        log.info("[MarkdownFileWriter] First run — backfilling .md files...")
        let repo = TalkieObjectRepository()
        do {
            let all = try await repo.fetchRecordings(limit: 10000, offset: 0)
            exportAll(all)
        } catch {
            log.error("[MarkdownFileWriter] Backfill failed: \(error)")
        }
    }

    // MARK: - Private

    private static func shouldWrite(_ object: TalkieObject) -> Bool {
        // Skip segments (internal children) and soft-deleted objects
        object.type != .segment && object.deletedAt == nil
    }

    private static func typeDirectory(for type: TalkieObjectType) -> URL {
        rootDirectory.appendingPathComponent(type.rawValue, isDirectory: true)
    }

    private static func filename(for object: TalkieObject) -> String {
        let dateStr = Self.dateFormatter.string(from: object.createdAt)
        let slug = Self.slug(from: object.title ?? object.text)
        let shortId = object.id.uuidString.prefix(8).lowercased()
        return "\(dateStr)_\(slug)_\(shortId).md"
    }

    /// Remove any existing .md file for this ID (matches the _shortId suffix).
    private static func removeExisting(id: UUID, in directory: URL) {
        let shortId = id.uuidString.prefix(8).lowercased()
        let suffix = "_\(shortId).md"
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        for file in files where file.hasSuffix(suffix) {
            try? fm.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    // MARK: - Markdown Generation

    private static func markdown(for object: TalkieObject) -> String {
        var lines: [String] = []

        // Frontmatter
        lines.append("---")
        lines.append("id: \(object.id.uuidString)")
        lines.append("type: \(object.type.rawValue)")
        if let title = object.title, !title.isEmpty {
            lines.append("title: \"\(title.replacingOccurrences(of: "\"", with: "\\\""))\"")
        }
        lines.append("created: \(iso8601(object.createdAt))")
        if let modified = object.lastModified {
            lines.append("modified: \(iso8601(modified))")
        }
        if object.duration > 0 {
            lines.append("duration: \(String(format: "%.1f", object.duration))")
        }
        lines.append("source: \(object.source.rawValue)")
        if object.hasAudio {
            lines.append("audio: \(object.id.uuidString).m4a")
        }
        if let model = object.transcriptionModel {
            lines.append("transcription_model: \(model)")
        }
        if object.wasPromoted {
            lines.append("promoted: true")
        }
        lines.append("---")
        lines.append("")

        // Title as heading
        if let title = object.title, !title.isEmpty {
            lines.append("# \(title)")
            lines.append("")
        }

        // Body
        if let text = object.text, !text.isEmpty {
            lines.append(text)
            lines.append("")
        }

        // Notes section
        if let notes = object.notes, !notes.isEmpty {
            lines.append("---")
            lines.append("")
            lines.append("## Notes")
            lines.append("")
            lines.append(notes)
            lines.append("")
        }

        // Summary section
        if let summary = object.summary, !summary.isEmpty {
            lines.append("## Summary")
            lines.append("")
            lines.append(summary)
            lines.append("")
        }

        // Tasks section
        if let tasks = object.tasks, !tasks.isEmpty {
            lines.append("## Tasks")
            lines.append("")
            lines.append(tasks)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func slug(from text: String?) -> String {
        guard let text = text, !text.isEmpty else { return "untitled" }

        let words = text
            .components(separatedBy: .newlines).first ?? text
        let slug = words
            .lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(6)
            .joined(separator: "-")

        if slug.isEmpty { return "untitled" }
        return String(slug.prefix(60))
    }
}
