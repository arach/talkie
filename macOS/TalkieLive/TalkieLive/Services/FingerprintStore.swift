//
//  FingerprintStore.swift
//  TalkieLive
//
//  Manages fingerprint → UUID mapping and dictation logging.
//  Each terminal context (bundleId + windowTitle) gets a UUID.
//  Dictations are appended to ~/.talkie-bridge/fingerprints/{uuid}.jsonl
//
//  A separate batch script (session-matcher) reads these files and
//  correlates with Claude's session files to establish mappings.
//

import Foundation
import TalkieKit

private let log = Log(.system)

/// A terminal fingerprint - identifies a unique context
struct Fingerprint: Codable, Hashable {
    let bundleId: String
    let windowTitle: String

    /// Stable key for hashing (excludes volatile parts of title if needed)
    var stableKey: String {
        "\(bundleId)|\(windowTitle)"
    }
}

/// Entry in a fingerprint's JSONL file
struct DictationEntry: Codable {
    let text: String
    let ts: String  // ISO8601 timestamp
}

/// Index entry mapping UUID to fingerprint details
struct FingerprintIndex: Codable {
    var entries: [String: FingerprintInfo]

    struct FingerprintInfo: Codable {
        let bundleId: String
        let windowTitle: String
        let createdAt: String
    }

    init() {
        self.entries = [:]
    }
}

/// Manages fingerprint files for session matching
final class FingerprintStore {
    static let shared = FingerprintStore()

    private let baseDir: URL
    private let indexFile: URL
    private var index: FingerprintIndex
    private var keyToUUID: [String: String] = [:]  // stableKey → UUID cache

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.baseDir = home
            .appendingPathComponent(".talkie-bridge", isDirectory: true)
            .appendingPathComponent("fingerprints", isDirectory: true)
        self.indexFile = baseDir.appendingPathComponent("index.json")
        self.index = FingerprintIndex()

        ensureDirectoryExists()
        loadIndex()
    }

    // MARK: - Public API

    /// Record a dictation for a fingerprint
    /// Call this after a dictation completes (in background, non-blocking)
    func recordDictation(bundleId: String, windowTitle: String, text: String) {
        // Skip if text too short
        guard text.count >= 10 else { return }

        let fingerprint = Fingerprint(bundleId: bundleId, windowTitle: windowTitle)
        let uuid = uuidFor(fingerprint)

        let entry = DictationEntry(
            text: String(text.prefix(500)),  // Truncate for storage
            ts: ISO8601DateFormatter().string(from: Date())
        )

        appendEntry(entry, to: uuid)
        log.debug("Recorded dictation for fingerprint \(uuid): \(text.prefix(30))...")
    }

    /// Get UUID for a fingerprint (creates if needed)
    func uuidFor(_ fingerprint: Fingerprint) -> String {
        let key = fingerprint.stableKey

        // Check cache
        if let existing = keyToUUID[key] {
            return existing
        }

        // Check index
        for (uuid, info) in index.entries {
            if info.bundleId == fingerprint.bundleId && info.windowTitle == fingerprint.windowTitle {
                keyToUUID[key] = uuid
                return uuid
            }
        }

        // Create new
        let uuid = UUID().uuidString.prefix(8).lowercased()
        let info = FingerprintIndex.FingerprintInfo(
            bundleId: fingerprint.bundleId,
            windowTitle: fingerprint.windowTitle,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        index.entries[String(uuid)] = info
        keyToUUID[key] = String(uuid)
        saveIndex()

        log.info("Created fingerprint \(uuid) for \(fingerprint.bundleId)|\(fingerprint.windowTitle)")
        return String(uuid)
    }

    // MARK: - Private

    private func ensureDirectoryExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: baseDir.path) {
            do {
                try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
                log.info("Created fingerprints directory: \(baseDir.path)")
            } catch {
                log.error("Failed to create fingerprints directory: \(error)")
            }
        }
    }

    private func loadIndex() {
        guard FileManager.default.fileExists(atPath: indexFile.path) else {
            log.debug("No existing fingerprint index")
            return
        }

        do {
            let data = try Data(contentsOf: indexFile)
            index = try JSONDecoder().decode(FingerprintIndex.self, from: data)

            // Build cache
            for (uuid, info) in index.entries {
                let key = "\(info.bundleId)|\(info.windowTitle)"
                keyToUUID[key] = uuid
            }

            log.info("Loaded \(index.entries.count) fingerprints from index")
        } catch {
            log.error("Failed to load fingerprint index: \(error)")
        }
    }

    private func saveIndex() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(index)
            try data.write(to: indexFile, options: .atomic)
        } catch {
            log.error("Failed to save fingerprint index: \(error)")
        }
    }

    private func appendEntry(_ entry: DictationEntry, to uuid: String) {
        let file = baseDir.appendingPathComponent("\(uuid).jsonl")

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(entry)
            guard var line = String(data: data, encoding: .utf8) else { return }
            line += "\n"

            if FileManager.default.fileExists(atPath: file.path) {
                // Append
                let handle = try FileHandle(forWritingTo: file)
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                handle.closeFile()
            } else {
                // Create
                try line.write(to: file, atomically: true, encoding: .utf8)
            }
        } catch {
            log.error("Failed to append to fingerprint file: \(error)")
        }
    }
}
