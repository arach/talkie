//
//  KeyboardDictation.swift
//  TalkieMobileKit
//
//  Simple model for keyboard dictation history.
//  Stored in App Group as JSON for simplicity.
//

import Foundation

/// A single keyboard dictation entry
public struct KeyboardDictation: Codable, Identifiable, Hashable {
    public let id: UUID
    public let text: String
    public let timestamp: Date
    public let durationSeconds: Double?
    public let wordCount: Int

    /// App context from HeadlessDictationService (optional)
    public let appContext: String?

    public init(
        id: UUID = UUID(),
        text: String,
        timestamp: Date = Date(),
        durationSeconds: Double? = nil,
        appContext: String? = nil
    ) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.wordCount = text.split(separator: " ").count
        self.appContext = appContext
    }
}

// MARK: - Keyboard Dictation Store

/// Simple file-based store for keyboard dictations in App Group
public final class KeyboardDictationStore {
    public static let shared = KeyboardDictationStore()

    private let log = Log(.keyboard)
    private let fileManager = FileManager.default
    private let maxEntries = 100  // Keep last 100 dictations

    /// Cache of dictations (loaded lazily)
    private var cache: [KeyboardDictation]?

    private init() {}

    // MARK: - File Storage

    private var storageURL: URL? {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: kTalkieAppGroup) else {
            log.error("Cannot access App Group container")
            return nil
        }
        return containerURL.appendingPathComponent("keyboard_dictations.json")
    }

    // MARK: - Public API

    /// Get all dictations (most recent first)
    public func all() -> [KeyboardDictation] {
        if let cache = cache {
            return cache
        }

        guard let url = storageURL else { return [] }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let dictations = try decoder.decode([KeyboardDictation].self, from: data)
            cache = dictations.sorted { $0.timestamp > $1.timestamp }
            return cache ?? []
        } catch {
            // File doesn't exist or is corrupted - start fresh
            log.debug("No existing dictations file or parse error: \(error.localizedDescription)")
            cache = []
            return []
        }
    }

    /// Add a new dictation
    public func add(_ dictation: KeyboardDictation) {
        var dictations = all()
        dictations.insert(dictation, at: 0)

        // Trim to max entries
        if dictations.count > maxEntries {
            dictations = Array(dictations.prefix(maxEntries))
        }

        save(dictations)
        log.info("Added dictation: \(dictation.text.prefix(30))... (\(dictation.wordCount) words)")
    }

    /// Add a dictation from transcription result
    public func add(text: String, durationSeconds: Double?, appContext: String? = nil) {
        let dictation = KeyboardDictation(
            text: text,
            durationSeconds: durationSeconds,
            appContext: appContext
        )
        add(dictation)
    }

    /// Delete a dictation by ID
    public func delete(_ id: UUID) {
        var dictations = all()
        dictations.removeAll { $0.id == id }
        save(dictations)
        log.info("Deleted dictation: \(id)")
    }

    /// Clear all dictations
    public func clear() {
        save([])
        log.info("Cleared all dictations")
    }

    /// Get count of dictations
    public var count: Int {
        all().count
    }

    /// Check if there are any dictations
    public var isEmpty: Bool {
        all().isEmpty
    }

    // MARK: - Private

    private func save(_ dictations: [KeyboardDictation]) {
        guard let url = storageURL else { return }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(dictations)
            try data.write(to: url, options: .atomic)
            cache = dictations
        } catch {
            log.error("Failed to save dictations: \(error.localizedDescription)")
        }
    }

    /// Force reload from disk (useful after keyboard extension writes)
    public func reload() {
        cache = nil
        _ = all()
    }
}
