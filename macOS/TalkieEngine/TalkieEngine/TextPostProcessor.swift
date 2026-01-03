//
//  TextPostProcessor.swift
//  TalkieEngine
//
//  Text post-processor for dictionary replacements.
//  Uses an optimized trie-based pattern matching for efficient text processing.
//  Engine is a runtime - it owns its dictionary file and persisted state.
//  Talkie configures what's active, but Engine runs independently.
//

import Foundation
import TalkieKit

// MARK: - Pattern Matching Trie

/// Trie node for efficient multi-pattern matching
private class TrieNode {
    var children: [Character: TrieNode] = [:]
    var entry: DictionaryEntry?  // Non-nil if this node marks end of a pattern
}

/// Trie-based pattern matcher optimized for dictionary replacements
private final class PatternMatcher {
    private let root = TrieNode()
    private var patterns: [DictionaryEntry] = []

    init(entries: [DictionaryEntry]) {
        patterns = entries
        for entry in entries {
            insert(entry)
        }
    }

    private func insert(_ entry: DictionaryEntry) {
        var node = root
        // Use lowercase for case-insensitive matching
        for char in entry.trigger.lowercased() {
            if node.children[char] == nil {
                node.children[char] = TrieNode()
            }
            node = node.children[char]!
        }
        // Store the entry at the terminal node
        // If multiple entries have same trigger (different case), keep first
        if node.entry == nil {
            node.entry = entry
        }
    }

    /// Find all matches in text
    func findMatches(in text: String) -> [Match] {
        var matches: [Match] = []
        let lowercasedText = text.lowercased()
        let chars = Array(lowercasedText)
        let originalChars = Array(text)

        for i in 0..<chars.count {
            var node = root
            var j = i

            while j < chars.count, let child = node.children[chars[j]] {
                node = child
                j += 1

                if let entry = node.entry {
                    // Found a match from i to j
                    let startIndex = text.index(text.startIndex, offsetBy: i)
                    let endIndex = text.index(text.startIndex, offsetBy: j)
                    let matchedText = String(originalChars[i..<j])

                    matches.append(Match(
                        entry: entry,
                        range: startIndex..<endIndex,
                        matchedText: matchedText,
                        startOffset: i,
                        endOffset: j
                    ))
                }
            }
        }

        return matches
    }

    struct Match {
        let entry: DictionaryEntry
        let range: Range<String.Index>
        let matchedText: String
        let startOffset: Int
        let endOffset: Int
    }
}

// MARK: - Text Post Processor

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

    /// Pattern matcher for efficient multi-pattern matching
    private var patternMatcher: PatternMatcher?

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
                patternMatcher = nil
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

    // MARK: - Pattern Matcher Building

    /// Rebuild the pattern matcher from current entries
    private func rebuildPatternMatcher() {
        let enabledEntries = entries.filter { $0.isEnabled }
        guard !enabledEntries.isEmpty else {
            patternMatcher = nil
            return
        }

        patternMatcher = PatternMatcher(entries: enabledEntries)
        AppLogger.shared.debug(.system, "Pattern matcher rebuilt", detail: "\(enabledEntries.count) patterns")
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
            patternMatcher = nil
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([DictionaryEntry].self, from: data)
            lastUpdated = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
            rebuildPatternMatcher()
            AppLogger.shared.info(.system, "Loaded dictionary from file", detail: "\(entries.count) entries")
        } catch {
            AppLogger.shared.error(.system, "Failed to load dictionary", detail: error.localizedDescription)
            entries = []
            patternMatcher = nil
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
        rebuildPatternMatcher()

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
        patternMatcher = nil
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
        guard isEnabled, !entries.isEmpty, let matcher = patternMatcher else {
            return DictionaryProcessingResult(
                original: text,
                processed: text,
                replacements: []
            )
        }

        // Find all matches using trie
        let allMatches = matcher.findMatches(in: text)

        guard !allMatches.isEmpty else {
            return DictionaryProcessingResult(
                original: text,
                processed: text,
                replacements: []
            )
        }

        // Filter matches based on match type and resolve overlaps
        let validMatches = filterAndResolveMatches(allMatches, in: text)

        guard !validMatches.isEmpty else {
            return DictionaryProcessingResult(
                original: text,
                processed: text,
                replacements: []
            )
        }

        // Apply replacements (from end to start to preserve indices)
        let (result, replacementInfos) = applyReplacements(validMatches, to: text)

        if !replacementInfos.isEmpty {
            AppLogger.shared.debug(.transcription, "Applied replacements",
                                  detail: replacementInfos.map { "\($0.trigger) -> \($0.replacement)" }.joined(separator: ", "))
        }

        return DictionaryProcessingResult(
            original: text,
            processed: result,
            replacements: replacementInfos
        )
    }

    // MARK: - Match Processing

    /// Filter matches based on match type and resolve overlapping matches
    private func filterAndResolveMatches(
        _ matches: [PatternMatcher.Match],
        in text: String
    ) -> [PatternMatcher.Match] {
        var validMatches: [PatternMatcher.Match] = []

        for match in matches {
            let entry = match.entry

            // Validate based on match type
            switch entry.matchType {
            case .exact:
                // Check word boundaries
                if isWordBoundary(at: match.startOffset, isStart: true, in: text) &&
                   isWordBoundary(at: match.endOffset, isStart: false, in: text) {
                    validMatches.append(match)
                }
            case .caseInsensitive:
                // Case-insensitive matches anywhere
                validMatches.append(match)
            }
        }

        // Resolve overlaps: first match wins, longer patterns preferred
        return resolveOverlaps(validMatches)
    }

    /// Check if position is at a word boundary
    private func isWordBoundary(at offset: Int, isStart: Bool, in text: String) -> Bool {
        let chars = Array(text)

        if isStart {
            // Start of string is a word boundary
            if offset == 0 { return true }
            // Check if previous character is not a word character
            let prevChar = chars[offset - 1]
            return !isWordCharacter(prevChar)
        } else {
            // End of string is a word boundary
            if offset >= chars.count { return true }
            // Check if current character is not a word character
            let currentChar = chars[offset]
            return !isWordCharacter(currentChar)
        }
    }

    private func isWordCharacter(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || char == "_"
    }

    /// Resolve overlapping matches - first match wins, prefer longer patterns
    private func resolveOverlaps(_ matches: [PatternMatcher.Match]) -> [PatternMatcher.Match] {
        guard matches.count > 1 else { return matches }

        // Sort by start position, then by length (longer first)
        let sorted = matches.sorted { a, b in
            if a.startOffset == b.startOffset {
                return a.entry.trigger.count > b.entry.trigger.count
            }
            return a.startOffset < b.startOffset
        }

        var result: [PatternMatcher.Match] = []
        var lastEndOffset = -1

        for match in sorted {
            // Skip if overlapping with previous match
            if match.startOffset < lastEndOffset {
                continue
            }
            result.append(match)
            lastEndOffset = match.endOffset
        }

        return result
    }

    /// Apply replacements to text, returning modified text and replacement info
    private func applyReplacements(
        _ matches: [PatternMatcher.Match],
        to text: String
    ) -> (String, [DictionaryProcessingResult.ReplacementInfo]) {
        var result = text
        var replacementCounts: [UUID: (entry: DictionaryEntry, count: Int)] = [:]

        // Apply from end to start to preserve indices
        for match in matches.reversed() {
            result.replaceSubrange(match.range, with: match.entry.replacement)

            // Track counts
            if let existing = replacementCounts[match.entry.id] {
                replacementCounts[match.entry.id] = (existing.entry, existing.count + 1)
            } else {
                replacementCounts[match.entry.id] = (match.entry, 1)
            }
        }

        // Build replacement info
        let infos = replacementCounts.values.map { entry, count in
            DictionaryProcessingResult.ReplacementInfo(
                trigger: entry.trigger,
                replacement: entry.replacement,
                count: count
            )
        }

        return (result, infos)
    }
}
