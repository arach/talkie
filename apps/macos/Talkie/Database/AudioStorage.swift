//
//  AudioStorage.swift
//  TalkieAgent
//
//  Manages persistent audio file storage for dictations
//

import Foundation
import os.log

private let logger = Logger(subsystem: "jdi.talkie.agent", category: "AudioStorage")

enum AudioStorage {
    /// Directory where audio files are stored (shared across all Talkie apps)
    /// Since all apps are unsandboxed, they can all access Application Support
    static let audioDirectory: URL = {
        let fm = FileManager.default

        // Use a shared Application Support directory for all Talkie apps
        // ~/Library/Application Support/Talkie/Audio
        do {
            let appSupport = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let audioDir = appSupport
                .appendingPathComponent("Talkie", isDirectory: true)
                .appendingPathComponent("Audio", isDirectory: true)
            try fm.createDirectory(at: audioDir, withIntermediateDirectories: true)
            logger.info("Using shared audio directory: \(audioDir.path)")
            return audioDir
        } catch {
            logger.error("Failed to create audio directory: \(error.localizedDescription)")
            // Ultimate fallback to temp directory
            return fm.temporaryDirectory.appendingPathComponent("TalkieAudio")
        }
    }()

    /// Save audio data for a specific recording ID
    /// Audio will be saved as {id}.m4a
    @discardableResult
    static func save(_ data: Data, forRecordingID id: UUID) -> Bool {
        let filename = "\(id.uuidString).m4a"
        let fileURL = audioDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
            logger.info("Saved audio file: \(filename) (\(data.count) bytes)")
            return true
        } catch {
            logger.error("Failed to save audio: \(error.localizedDescription)")
            return false
        }
    }

    /// Legacy: Save audio data and return the filename (deprecated)
    @available(*, deprecated, message: "Use save(_:forRecordingID:) instead")
    static func save(_ data: Data, withExtension ext: String = "m4a") -> String? {
        let filename = "\(UUID().uuidString).\(ext)"
        let fileURL = audioDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
            logger.info("Saved audio file: \(filename) (\(data.count) bytes)")
            return filename
        } catch {
            logger.error("Failed to save audio: \(error.localizedDescription)")
            return nil
        }
    }

    /// Delete audio file for a specific recording ID
    static func delete(forRecordingID id: UUID) {
        let filename = "\(id.uuidString).m4a"
        let fileURL = audioDirectory.appendingPathComponent(filename)
        do {
            try FileManager.default.removeItem(at: fileURL)
            logger.info("Deleted audio file: \(filename)")
        } catch {
            logger.warning("Failed to delete audio file \(filename): \(error.localizedDescription)")
        }
    }

    /// Delete an audio file by filename (legacy)
    static func delete(filename: String) {
        let fileURL = audioDirectory.appendingPathComponent(filename)
        do {
            try FileManager.default.removeItem(at: fileURL)
            logger.info("Deleted audio file: \(filename)")
        } catch {
            logger.warning("Failed to delete audio file \(filename): \(error.localizedDescription)")
        }
    }

    /// Get the URL for a recording's audio file
    static func url(forRecordingID id: UUID) -> URL {
        audioDirectory.appendingPathComponent("\(id.uuidString).m4a")
    }

    /// Get the URL for an audio file by filename (legacy)
    static func url(for filename: String) -> URL {
        audioDirectory.appendingPathComponent(filename)
    }

    /// Check if audio exists for a recording ID
    static func exists(forRecordingID id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(forRecordingID: id).path)
    }

    /// Check if an audio file exists by filename (legacy)
    static func exists(filename: String) -> Bool {
        FileManager.default.fileExists(atPath: audioDirectory.appendingPathComponent(filename).path)
    }

    // MARK: - Storage Size (Async with Caching)

    /// Cached storage size to avoid blocking UI
    private static var cachedStorageBytes: Int64?
    private static var cacheTimestamp: Date?
    private static let cacheDuration: TimeInterval = 30 // Cache for 30 seconds

    /// Calculate total storage used by audio files (async, off main thread)
    static func totalStorageBytesAsync() async -> Int64 {
        // Return cached value if fresh
        if let cached = cachedStorageBytes,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheDuration {
            return cached
        }

        // Calculate on background thread
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let bytes = calculateStorageBytes()
                cachedStorageBytes = bytes
                cacheTimestamp = Date()
                continuation.resume(returning: bytes)
            }
        }
    }

    /// Calculate storage bytes synchronously (internal use only)
    private static func calculateStorageBytes() -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: audioDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Human-readable storage size (async)
    static func formattedStorageSizeAsync() async -> String {
        let bytes = await totalStorageBytesAsync()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Get cached storage size immediately (returns "Calculating..." if not cached)
    static func cachedFormattedStorageSize() -> String {
        guard let bytes = cachedStorageBytes else {
            return "Calculating..."
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Invalidate cache (call after deleting files)
    static func invalidateCache() {
        cachedStorageBytes = nil
        cacheTimestamp = nil
    }

    /// Legacy sync method - deprecated, use async version
    @available(*, deprecated, message: "Use totalStorageBytesAsync() to avoid blocking UI")
    static func totalStorageBytes() -> Int64 {
        calculateStorageBytes()
    }

    /// Legacy sync method - deprecated, use async version
    @available(*, deprecated, message: "Use formattedStorageSizeAsync() to avoid blocking UI")
    static func formattedStorageSize() -> String {
        let bytes = calculateStorageBytes()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Copy an external audio file to storage for a specific recording ID
    /// Audio will be saved as {id}.m4a
    @discardableResult
    static func copyToStorage(_ sourceURL: URL, forRecordingID id: UUID) -> Bool {
        let filename = "\(id.uuidString).m4a"
        let destURL = audioDirectory.appendingPathComponent(filename)

        do {
            // Remove existing file if present (for re-recording)
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            let size = (try? destURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            logger.info("Copied audio file: \(filename) (\(size) bytes)")
            return true
        } catch {
            logger.error("Failed to copy audio file: \(error.localizedDescription)")
            return false
        }
    }

    /// Legacy: Copy an external audio file to storage (deprecated)
    @available(*, deprecated, message: "Use copyToStorage(_:forRecordingID:) instead")
    static func copyToStorage(_ sourceURL: URL) -> String? {
        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let filename = "\(UUID().uuidString).\(ext)"
        let destURL = audioDirectory.appendingPathComponent(filename)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            let size = (try? destURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            logger.info("Copied audio file: \(filename) (\(size) bytes)")
            return filename
        } catch {
            logger.error("Failed to copy audio file: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Migration Helpers

    /// Rename a legacy audio file to the standard {id}.m4a format
    /// Used during migration from old audioFilename-based storage
    @discardableResult
    static func renameToStandardFormat(from oldFilename: String, toRecordingID id: UUID) -> Bool {
        let oldURL = audioDirectory.appendingPathComponent(oldFilename)
        let newFilename = "\(id.uuidString).m4a"
        let newURL = audioDirectory.appendingPathComponent(newFilename)

        // Skip if old file doesn't exist
        guard FileManager.default.fileExists(atPath: oldURL.path) else {
            logger.warning("Migration: old file doesn't exist: \(oldFilename)")
            return false
        }

        // Skip if already in correct format
        if oldFilename == newFilename {
            logger.info("Migration: file already in correct format: \(newFilename)")
            return true
        }

        // Skip if new file already exists (avoid overwriting)
        if FileManager.default.fileExists(atPath: newURL.path) {
            logger.warning("Migration: target file already exists: \(newFilename)")
            return false
        }

        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            logger.info("Migration: renamed \(oldFilename) → \(newFilename)")
            return true
        } catch {
            logger.error("Migration: failed to rename \(oldFilename): \(error.localizedDescription)")
            return false
        }
    }

    /// Delete all audio files
    static func deleteAll() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        for fileURL in contents {
            try? fm.removeItem(at: fileURL)
        }
        invalidateCache()
        logger.info("Deleted all audio files")
    }

    /// Delete orphaned audio files (not referenced by any dictation)
    static func pruneOrphanedFiles(referencedFilenames: Set<String>) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        var deletedCount = 0
        for fileURL in contents {
            let filename = fileURL.lastPathComponent
            if !referencedFilenames.contains(filename) {
                try? fm.removeItem(at: fileURL)
                deletedCount += 1
            }
        }

        invalidateCache()
        if deletedCount > 0 {
            logger.info("Pruned \(deletedCount) orphaned audio files")
        }
    }

    /// Preview orphaned files (count and total size)
    static func orphanedFilesPreview(referencedFilenames: Set<String>) -> (count: Int, totalBytes: Int64) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: audioDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return (0, 0)
        }

        var count = 0
        var totalBytes: Int64 = 0

        for fileURL in contents {
            let filename = fileURL.lastPathComponent
            if !referencedFilenames.contains(filename) {
                count += 1
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalBytes += Int64(size)
                }
            }
        }

        return (count, totalBytes)
    }

    /// Get total file count in audio directory
    static func fileCount() -> Int {
        let fm = FileManager.default
        return (try? fm.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: nil).count) ?? 0
    }

    /// Get all audio filenames in the storage directory
    static func allFilenames() -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return contents.map { $0.lastPathComponent }
    }
}
