//
//  AudioStorage.swift
//  TalkieAgent
//
//  Manages persistent audio file storage for utterances
//

import Foundation
import os.log

private let logger = Logger(subsystem: "to.talkie.app.agent", category: "AudioStorage")

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

    /// Move or copy an external audio file to storage (optimized for speed).
    /// Tries moveItem first (atomic, near-instant) and falls back to copyItem if move fails.
    /// This is faster than always copying, especially for files in /var/folders temp.
    static func copyToStorage(_ sourceURL: URL) -> String? {
        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let filename = "\(UUID().uuidString).\(ext)"
        let destURL = audioDirectory.appendingPathComponent(filename)

        do {
            // Try move first - atomic and doesn't copy data (much faster)
            // This works when source and dest are on the same filesystem
            try FileManager.default.moveItem(at: sourceURL, to: destURL)
            let size = (try? destURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            logger.info("Moved audio file: \(filename) (\(size) bytes)")
            return filename
        } catch let moveError {
            // Move failed (likely cross-filesystem) - fall back to copy
            logger.debug("Move failed (likely cross-filesystem): \(moveError.localizedDescription), trying copy")
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
    }

    // MARK: - Async Copy (Background)

    /// Copy audio file to storage asynchronously (runs on background queue).
    /// Returns the filename immediately (optimistically) and copies in background.
    /// The callback is called when copy completes (success: true) or fails (success: false).
    ///
    /// This is designed for the critical recording path where we want to:
    /// 1. Return the filename immediately so transcription can start
    /// 2. Copy the file in the background
    /// 3. Notify when done so we can update the database record
    static func copyToStorageAsync(
        _ sourceURL: URL,
        completion: @escaping (_ filename: String?, _ success: Bool) -> Void
    ) {
        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let filename = "\(UUID().uuidString).\(ext)"
        let destURL = audioDirectory.appendingPathComponent(filename)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
                let size = (try? destURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                logger.info("Copied audio file (async): \(filename) (\(size) bytes)")
                DispatchQueue.main.async {
                    completion(filename, true)
                }
            } catch {
                logger.error("Failed to copy audio file (async): \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil, false)
                }
            }
        }
    }

    /// Async/await version of copyToStorageAsync
    static func copyToStorageAsync(_ sourceURL: URL) async -> String? {
        await withCheckedContinuation { continuation in
            copyToStorageAsync(sourceURL) { filename, success in
                continuation.resume(returning: success ? filename : nil)
            }
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

    /// Delete orphaned audio files (not referenced by any utterance)
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

        if deletedCount > 0 {
            logger.info("Pruned \(deletedCount) orphaned audio files")
        }
    }
}
