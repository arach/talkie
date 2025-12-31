//
//  TextPostProcessor.swift
//  TalkieEngine
//
//  Text post-processor for dictionary replacements.
//  Engine is a runtime - it owns its dictionary file and persisted state.
//  Talkie configures what's active, but Engine runs independently.
//

import Foundation
import TalkieKit

/// Singleton that manages dictionary and applies text replacements.
/// Engine owns its dictionary file - Talkie pushes updates, Engine persists and loads independently.
@MainActor
final class TextPostProcessor {
    static let shared = TextPostProcessor()

    // MARK: - Paths

    /// Engine's own application support directory
    private static var engineSupportDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TalkieEngine", isDirectory: true)
    }

    /// Dictionary file path (Engine's own copy)
    private static var dictionaryFileURL: URL {
        engineSupportDir.appendingPathComponent("dictionary.json")
    }

    // MARK: - Persisted State Keys

    private enum Defaults {
        static let dictionaryEnabled = "dictionaryEnabled"
    }

    // MARK: - State

    /// In-memory dictionary entries (loaded from Engine's file)
    private(set) var entries: [DictionaryEntry] = []

    /// Whether dictionary processing is enabled (persisted)
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Defaults.dictionaryEnabled) }
        set {
            UserDefaults.standard.set(newValue, forKey: Defaults.dictionaryEnabled)
            AppLogger.shared.info(.system, "Dictionary \(newValue ? "enabled" : "disabled")")

            if newValue && entries.isEmpty {
                // Enabling - load from file if not already loaded
                loadFromFile()
            } else if !newValue {
                // Disabling - keep file but clear memory
                entries.removeAll()
            }
        }
    }

    /// Whether dictionary has entries loaded
    var isLoaded: Bool { !entries.isEmpty }

    /// Last update timestamp
    private(set) var lastUpdated: Date?

    // MARK: - Init

    private init() {
        ensureDirectoryExists()

        // On startup: if enabled, load from file
        if UserDefaults.standard.bool(forKey: Defaults.dictionaryEnabled) {
            loadFromFile()
        }

        AppLogger.shared.info(.system, "TextPostProcessor initialized",
                             detail: "enabled=\(isEnabled), entries=\(entries.count)")
    }

    // MARK: - File Operations

    /// Ensure Engine's support directory exists
    private func ensureDirectoryExists() {
        let dir = Self.engineSupportDir
        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                AppLogger.shared.debug(.system, "Created TalkieEngine support directory")
            } catch {
                AppLogger.shared.error(.system, "Failed to create support directory", detail: error.localizedDescription)
            }
        }
    }

    /// Load dictionary from Engine's file
    func loadFromFile() {
        let fileURL = Self.dictionaryFileURL

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            AppLogger.shared.debug(.system, "No dictionary file found")
            entries = []
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([DictionaryEntry].self, from: data)
            lastUpdated = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
            AppLogger.shared.info(.system, "Loaded dictionary from file", detail: "\(entries.count) entries")
        } catch {
            AppLogger.shared.error(.system, "Failed to load dictionary", detail: error.localizedDescription)
            entries = []
        }
    }

    /// Save dictionary to Engine's file
    private func saveToFile() {
        let fileURL = Self.dictionaryFileURL

        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
            lastUpdated = Date()
            AppLogger.shared.debug(.system, "Saved dictionary to file", detail: "\(entries.count) entries")
        } catch {
            AppLogger.shared.error(.system, "Failed to save dictionary", detail: error.localizedDescription)
        }
    }

    // MARK: - Dictionary Management (called via XPC from Talkie)

    /// Update dictionary with entries from Talkie
    /// Talkie pushes content, Engine persists to its own file
    func updateDictionary(_ newEntries: [DictionaryEntry]) {
        let previousCount = entries.count
        entries = newEntries
        saveToFile()

        AppLogger.shared.info(.system, "Dictionary updated",
                             detail: "\(previousCount) -> \(newEntries.count) entries")
    }

    /// Set enabled state (called via XPC from Talkie)
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    /// Clear the dictionary (file and memory)
    func clearDictionary() {
        entries.removeAll()
        lastUpdated = nil

        // Remove file
        let fileURL = Self.dictionaryFileURL
        try? FileManager.default.removeItem(at: fileURL)

        AppLogger.shared.info(.system, "Dictionary cleared")
    }

    // MARK: - Text Processing

    /// Process text with dictionary replacements
    /// - Parameter text: Raw transcription text
    /// - Returns: Processed text with replacements applied
    func process(_ text: String) -> DictionaryProcessingResult {
        // Only process if enabled and has entries
        guard isEnabled, !entries.isEmpty else {
            return DictionaryProcessingResult(
                original: text,
                processed: text,
                replacements: []
            )
        }

        var result = text
        var allReplacements: [DictionaryProcessingResult.ReplacementInfo] = []

        // Sort by trigger length (longest first) to avoid partial replacements
        let sorted = entries.filter { $0.isEnabled }.sorted { $0.trigger.count > $1.trigger.count }

        for entry in sorted {
            let (replaced, count) = applyReplacement(
                to: result,
                trigger: entry.trigger,
                replacement: entry.replacement,
                matchType: entry.matchType
            )

            if count > 0 {
                result = replaced
                allReplacements.append(DictionaryProcessingResult.ReplacementInfo(
                    trigger: entry.trigger,
                    replacement: entry.replacement,
                    count: count
                ))
            }
        }

        if !allReplacements.isEmpty {
            AppLogger.shared.debug(.transcription, "Applied replacements",
                                  detail: allReplacements.map { "\($0.trigger) -> \($0.replacement)" }.joined(separator: ", "))
        }

        return DictionaryProcessingResult(
            original: text,
            processed: result,
            replacements: allReplacements
        )
    }

    // MARK: - Replacement Logic

    private func applyReplacement(
        to text: String,
        trigger: String,
        replacement: String,
        matchType: DictionaryMatchType
    ) -> (String, Int) {
        switch matchType {
        case .exact:
            return replaceExactWord(in: text, trigger: trigger, replacement: replacement)
        case .caseInsensitive:
            return replaceCaseInsensitive(in: text, trigger: trigger, replacement: replacement)
        }
    }

    /// Replace exact word matches using word boundary regex
    private func replaceExactWord(in text: String, trigger: String, replacement: String) -> (String, Int) {
        // Escape special regex characters in trigger
        let escaped = NSRegularExpression.escapedPattern(for: trigger)

        // Word boundary pattern
        let pattern = "\\b\(escaped)\\b"

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let range = NSRange(text.startIndex..., in: text)

            let matchCount = regex.numberOfMatches(in: text, range: range)

            if matchCount > 0 {
                let replaced = regex.stringByReplacingMatches(
                    in: text,
                    range: range,
                    withTemplate: replacement
                )
                return (replaced, matchCount)
            }
        } catch {
            AppLogger.shared.error(.system, "Regex error for trigger '\(trigger)'")
        }

        return (text, 0)
    }

    /// Replace case-insensitive matches anywhere in text
    private func replaceCaseInsensitive(in text: String, trigger: String, replacement: String) -> (String, Int) {
        var result = text
        var count = 0
        var searchRange = result.startIndex..<result.endIndex

        while let range = result.range(of: trigger, options: .caseInsensitive, range: searchRange) {
            result.replaceSubrange(range, with: replacement)
            count += 1

            let newStart = result.index(range.lowerBound, offsetBy: replacement.count, limitedBy: result.endIndex) ?? result.endIndex
            searchRange = newStart..<result.endIndex
        }

        return (result, count)
    }
}
