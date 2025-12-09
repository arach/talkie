//
//  TranscriptFileManager.swift
//  Talkie macOS
//
//  Manages local file storage for transcripts (Markdown) and audio files (M4A).
//  Your data, your files - stored in a user-configurable folder.
//  Transcripts use Markdown with YAML frontmatter for maximum portability.
//

import Foundation
import CoreData
import AppKit
import os

private let logger = Logger(subsystem: "live.talkie.core", category: "LocalFiles")

class TranscriptFileManager {
    static let shared = TranscriptFileManager()

    private let fileManager = FileManager.default
    private var remoteChangeObserver: NSObjectProtocol?

    /// Cache of memo IDs to hash of last-written content
    /// Persisted to disk so it survives app restarts
    private var lastWrittenHashes: [UUID: Int] = [:] {
        didSet { saveHashCache() }
    }

    private let hashCacheURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Talkie", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("transcript_hashes.json")
    }()

    private init() {
        loadHashCache()
    }

    private func loadHashCache() {
        guard let data = try? Data(contentsOf: hashCacheURL),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return
        }
        // Convert string keys back to UUIDs
        lastWrittenHashes = dict.reduce(into: [:]) { result, pair in
            if let uuid = UUID(uuidString: pair.key) {
                result[uuid] = pair.value
            }
        }
        logger.debug("Loaded \(self.lastWrittenHashes.count) transcript hashes from cache")
    }

    private func saveHashCache() {
        // Convert UUID keys to strings for JSON
        let dict = lastWrittenHashes.reduce(into: [String: Int]()) { result, pair in
            result[pair.key.uuidString] = pair.value
        }
        if let data = try? JSONEncoder().encode(dict) {
            try? data.write(to: hashCacheURL)
        }
    }

    // MARK: - Setup

    /// Start watching for memo changes and sync files
    func configure(with context: NSManagedObjectContext) {
        guard SettingsManager.shared.localFilesEnabled else {
            logger.info("Local file storage disabled - skipping configuration")
            return
        }

        // Ensure folders exist
        ensureFoldersExist()

        // Listen for sync completed notifications to update files
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .talkieSyncCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncAllMemos(context: context)
        }

        // Initial sync
        syncAllMemos(context: context)

        logger.info("TranscriptFileManager configured (transcripts: \(SettingsManager.shared.saveTranscriptsLocally), audio: \(SettingsManager.shared.saveAudioLocally))")
    }

    // MARK: - Folder Management

    private var transcriptsFolderURL: URL {
        URL(fileURLWithPath: SettingsManager.shared.transcriptsFolderPath)
    }

    private var audioFolderURL: URL {
        URL(fileURLWithPath: SettingsManager.shared.audioFolderPath)
    }

    /// Ensure all local file folders exist
    func ensureFoldersExist() {
        // Create transcripts folder if transcript saving is enabled
        if SettingsManager.shared.saveTranscriptsLocally {
            if !fileManager.fileExists(atPath: transcriptsFolderURL.path) {
                do {
                    try fileManager.createDirectory(at: transcriptsFolderURL, withIntermediateDirectories: true)
                    logger.info("Created transcripts folder: \(self.transcriptsFolderURL.path)")
                } catch {
                    logger.error("Failed to create transcripts folder: \(error.localizedDescription)")
                }
            }
        }

        // Create audio folder if audio saving is enabled
        if SettingsManager.shared.saveAudioLocally {
            if !fileManager.fileExists(atPath: audioFolderURL.path) {
                do {
                    try fileManager.createDirectory(at: audioFolderURL, withIntermediateDirectories: true)
                    logger.info("Created audio folder: \(self.audioFolderURL.path)")
                } catch {
                    logger.error("Failed to create audio folder: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Sync All Memos

    /// Sync all memos - writes transcripts and/or audio files based on settings
    func syncAllMemos(context: NSManagedObjectContext) {
        guard SettingsManager.shared.localFilesEnabled else {
            logger.info("Local file storage disabled, skipping sync")
            return
        }

        ensureFoldersExist()

        context.perform {
            let fetchRequest: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()

            do {
                let memos = try context.fetch(fetchRequest)
                var transcriptsCreated = 0
                var transcriptsUpdated = 0
                var audioCreated = 0

                for memo in memos {
                    // Write transcript file (if enabled and memo has transcription)
                    if SettingsManager.shared.saveTranscriptsLocally,
                       let transcription = memo.currentTranscript, !transcription.isEmpty {
                        let result = self.writeTranscriptFile(for: memo)
                        switch result {
                        case .created: transcriptsCreated += 1
                        case .updated: transcriptsUpdated += 1
                        case .unchanged, .skipped: break
                        }
                    }

                    // Write audio file (if enabled and memo has audio)
                    if SettingsManager.shared.saveAudioLocally {
                        let audioResult = self.writeAudioFile(for: memo)
                        if audioResult == .created {
                            audioCreated += 1
                        }
                    }
                }

                // Only log if something actually changed
                if transcriptsCreated > 0 || transcriptsUpdated > 0 || audioCreated > 0 {
                    var parts: [String] = []
                    if transcriptsCreated > 0 { parts.append("\(transcriptsCreated) new") }
                    if transcriptsUpdated > 0 { parts.append("\(transcriptsUpdated) updated") }
                    if audioCreated > 0 { parts.append("\(audioCreated) audio") }
                    logger.info("Local files: \(parts.joined(separator: ", "))")
                }
            } catch {
                logger.error("Failed to fetch memos for local file sync: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Write Transcript File

    /// Write a single transcript as Markdown with YAML frontmatter
    func writeTranscriptFile(for memo: VoiceMemo) -> WriteResult {
        guard SettingsManager.shared.saveTranscriptsLocally else { return .skipped }
        guard let transcript = memo.currentTranscript, !transcript.isEmpty else { return .skipped }
        guard let memoId = memo.id else { return .skipped }

        let content = generateMarkdownContent(for: memo)
        let contentHash = content.hashValue
        let fileURL = transcriptFileURL(for: memo)

        // Check if content has changed since last write
        if let lastHash = lastWrittenHashes[memoId], lastHash == contentHash {
            // Content unchanged - skip unless file was deleted
            if fileManager.fileExists(atPath: fileURL.path) {
                return .unchanged
            }
        }

        let isUpdate = fileManager.fileExists(atPath: fileURL.path)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            lastWrittenHashes[memoId] = contentHash

            if isUpdate {
                logger.info("Updated transcript: \(fileURL.lastPathComponent)")
                return .updated
            } else {
                logger.info("Created transcript: \(fileURL.lastPathComponent)")
                return .created
            }
        } catch {
            logger.error("Failed to write transcript: \(error.localizedDescription)")
            return .skipped
        }
    }

    // MARK: - Write Audio File

    /// Copy the M4A audio file to local storage
    /// For synced memos from iOS, uses audioData binary; for local recordings, copies the file
    func writeAudioFile(for memo: VoiceMemo) -> WriteResult {
        guard SettingsManager.shared.saveAudioLocally else { return .skipped }

        let destURL = audioFileURL(for: memo)

        // Skip if already exists
        if fileManager.fileExists(atPath: destURL.path) {
            return .unchanged
        }

        // Try 1: Use audioData (synced from iOS via CloudKit)
        if let audioData = memo.audioData, !audioData.isEmpty {
            do {
                try audioData.write(to: destURL)
                logger.debug("Wrote audio file from synced data: \(destURL.lastPathComponent)")
                return .created
            } catch {
                logger.error("Failed to write audio from data: \(error.localizedDescription)")
                return .skipped
            }
        }

        // Try 2: Copy from local file path (local recordings)
        if let sourceURLString = memo.fileURL {
            let sourceURL = URL(fileURLWithPath: sourceURLString)
            if fileManager.fileExists(atPath: sourceURL.path) {
                do {
                    try fileManager.copyItem(at: sourceURL, to: destURL)
                    logger.debug("Copied audio file: \(destURL.lastPathComponent)")
                    return .created
                } catch {
                    logger.error("Failed to copy audio file: \(error.localizedDescription)")
                    return .skipped
                }
            }
        }

        // No audio source available
        return .skipped
    }

    enum WriteResult {
        case created
        case updated
        case unchanged
        case skipped
    }

    // MARK: - File Naming

    /// Generate transcript filename: YYYY-MM-DD_HHmm_Title.md
    private func transcriptFileURL(for memo: VoiceMemo) -> URL {
        let filename = baseFilename(for: memo) + ".md"
        return transcriptsFolderURL.appendingPathComponent(filename)
    }

    /// Generate audio filename: YYYY-MM-DD_HHmm_Title.m4a
    private func audioFileURL(for memo: VoiceMemo) -> URL {
        let filename = baseFilename(for: memo) + ".m4a"
        return audioFolderURL.appendingPathComponent(filename)
    }

    /// Generate base filename (without extension): YYYY-MM-DD_HHmm_Title
    private func baseFilename(for memo: VoiceMemo) -> String {
        let date = memo.createdAt ?? Date()
        let title = sanitizeFilename(memo.title ?? "Untitled")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HHmm"
        let timeString = timeFormatter.string(from: date)

        return "\(dateString)_\(timeString)_\(title)"
    }

    /// Sanitize a string for use as filename
    private func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        var sanitized = name.components(separatedBy: invalidChars).joined(separator: "-")
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)

        // Limit length
        if sanitized.count > 50 {
            sanitized = String(sanitized.prefix(50))
        }

        return sanitized.isEmpty ? "Untitled" : sanitized
    }

    // MARK: - Markdown Generation

    /// Generate Obsidian-compatible Markdown with YAML frontmatter
    private func generateMarkdownContent(for memo: VoiceMemo) -> String {
        var content = "---\n"

        // Frontmatter
        content += "title: \"\(escapeYAML(memo.title ?? "Untitled"))\"\n"

        if let date = memo.createdAt {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]
            content += "date: \(isoFormatter.string(from: date))\n"
        }

        content += "duration: \(Int(memo.duration))\n"

        if let id = memo.id {
            content += "id: \(id.uuidString)\n"
        }

        content += "tags: []\n"
        content += "---\n\n"

        // Transcript
        if let transcript = memo.currentTranscript {
            content += transcript
            content += "\n"
        }

        // Summary section (if available)
        if let summary = memo.summary, !summary.isEmpty {
            content += "\n---\n\n"
            content += "## Summary\n\n"
            content += summary
            content += "\n"
        }

        // Tasks section (if available)
        if let tasks = memo.tasks, !tasks.isEmpty {
            content += "\n## Tasks\n\n"
            content += tasks
            content += "\n"
        }

        // Notes section (if available)
        if let notes = memo.notes, !notes.isEmpty {
            content += "\n## Notes\n\n"
            content += notes
            content += "\n"
        }

        return content
    }

    /// Escape special characters for YAML strings
    private func escapeYAML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }

    // MARK: - Open Folder

    /// Open the transcripts folder in Finder
    func openTranscriptsFolderInFinder() {
        if SettingsManager.shared.saveTranscriptsLocally {
            ensureFoldersExist()
            NSWorkspace.shared.open(transcriptsFolderURL)
        }
    }

    /// Open the audio folder in Finder
    func openAudioFolderInFinder() {
        if SettingsManager.shared.saveAudioLocally {
            ensureFoldersExist()
            NSWorkspace.shared.open(audioFolderURL)
        }
    }

    // MARK: - Statistics

    /// Get stats about local files for display
    func getStats() -> (transcripts: Int, audioFiles: Int, totalSize: Int64) {
        var transcriptCount = 0
        var audioCount = 0
        var totalSize: Int64 = 0

        // Count transcripts
        if let files = try? fileManager.contentsOfDirectory(atPath: transcriptsFolderURL.path) {
            transcriptCount = files.filter { $0.hasSuffix(".md") }.count
            for file in files {
                let filePath = transcriptsFolderURL.appendingPathComponent(file).path
                if let attrs = try? fileManager.attributesOfItem(atPath: filePath),
                   let size = attrs[.size] as? Int64 {
                    totalSize += size
                }
            }
        }

        // Count audio files
        if let files = try? fileManager.contentsOfDirectory(atPath: audioFolderURL.path) {
            audioCount = files.filter { $0.hasSuffix(".m4a") }.count
            for file in files {
                let filePath = audioFolderURL.appendingPathComponent(file).path
                if let attrs = try? fileManager.attributesOfItem(atPath: filePath),
                   let size = attrs[.size] as? Int64 {
                    totalSize += size
                }
            }
        }

        return (transcriptCount, audioCount, totalSize)
    }
}
