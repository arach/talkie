//
//  AudioStorage.swift
//  TalkieLive
//
//  Manages persistent audio file storage for utterances
//

import Foundation
import os.log

private let logger = Logger(subsystem: "jdi.talkie.live", category: "AudioStorage")

enum AudioStorage {
    /// Directory where audio files are stored
    static let audioDirectory: URL = {
        let fm = FileManager.default
        do {
            let appSupport = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let audioDir = appSupport
                .appendingPathComponent("TalkieLive", isDirectory: true)
                .appendingPathComponent("Audio", isDirectory: true)
            try fm.createDirectory(at: audioDir, withIntermediateDirectories: true)
            return audioDir
        } catch {
            logger.error("Failed to create audio directory: \(error.localizedDescription)")
            return fm.temporaryDirectory.appendingPathComponent("TalkieLiveAudio")
        }
    }()

    /// Save audio data and return the filename
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

    /// Delete an audio file by filename
    static func delete(filename: String) {
        let fileURL = audioDirectory.appendingPathComponent(filename)
        do {
            try FileManager.default.removeItem(at: fileURL)
            logger.info("Deleted audio file: \(filename)")
        } catch {
            logger.warning("Failed to delete audio file \(filename): \(error.localizedDescription)")
        }
    }

    /// Get the URL for an audio file
    static func url(for filename: String) -> URL {
        audioDirectory.appendingPathComponent(filename)
    }

    /// Check if an audio file exists
    static func exists(filename: String) -> Bool {
        FileManager.default.fileExists(atPath: audioDirectory.appendingPathComponent(filename).path)
    }

    /// Calculate total storage used by audio files
    static func totalStorageBytes() -> Int64 {
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

    /// Human-readable storage size
    static func formattedStorageSize() -> String {
        let bytes = totalStorageBytes()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Copy an external audio file to storage
    /// Returns the new filename if successful
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

    /// Delete all audio files
    static func deleteAll() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        for fileURL in contents {
            try? fm.removeItem(at: fileURL)
        }
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
