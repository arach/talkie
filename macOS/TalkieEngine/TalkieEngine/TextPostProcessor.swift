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

// MARK: - Fuzzy Matching (SymSpell-style)

/// Configuration for fuzzy matching
private enum FuzzyConfig {
    static let minWordLength = 4          // Skip words with 3 or fewer chars
    static let maxDeleteDistance = 2      // SymSpell delete depth (1-2 edits)
    static let scoreThreshold = 0.7       // Min similarity for replacement (0.0-1.0)
    static let marginDelta = 0.1          // Min margin over second-best candidate
}

/// Token representing a word in the transcript
private struct WordToken {
    let text: String
    let startOffset: Int
    let endOffset: Int
    var range: Range<Int> { startOffset..<endOffset }
}

/// SymSpell-style delete index for O(1) fuzzy candidate lookup
private final class FuzzyDeleteIndex {
    /// Maps delete variants -> source entries that could match
    private var deleteMap: [String: [DictionaryEntry]] = [:]

    /// Set of normalized triggers for "known word" detection
    private var knownTriggers: Set<String> = []

    /// Maximum edit distance for delete generation
    let maxDeleteDistance: Int

    init(entries: [DictionaryEntry], maxDeleteDistance: Int = FuzzyConfig.maxDeleteDistance) {
        self.maxDeleteDistance = maxDeleteDistance
        buildIndex(from: entries)
    }

    /// Build the delete index from dictionary entries
    private func buildIndex(from entries: [DictionaryEntry]) {
        for entry in entries {
            let normalized = entry.trigger.lowercased()
            knownTriggers.insert(normalized)

            // Generate all delete variants and map them to this entry
            let deletes = generateDeletes(word: normalized, maxDistance: maxDeleteDistance)
            for variant in deletes {
                deleteMap[variant, default: []].append(entry)
            }
        }
    }

    /// Generate all delete variants within maxDistance edits
    /// Uses index-based queue processing for O(1) dequeue operations
    private func generateDeletes(word: String, maxDistance: Int) -> Set<String> {
        var results = Set<String>([word])
        var queue = [(word, 0)] // (variant, currentDepth)
        var queueIndex = 0

        while queueIndex < queue.count {
            let (current, depth) = queue[queueIndex]
            queueIndex += 1

            guard depth < maxDistance else { continue }

            // Generate all single-character deletions
            let chars = Array(current)
            for i in 0..<chars.count {
                var variant = chars
                variant.remove(at: i)
                let variantStr = String(variant)

                if !variantStr.isEmpty && !results.contains(variantStr) {
                    results.insert(variantStr)
                    queue.append((variantStr, depth + 1))
                }
            }
        }

        return results
    }

    /// Find candidate entries for a word
    func findCandidates(for word: String) -> [DictionaryEntry] {
        let normalized = word.lowercased()
        var candidates: [DictionaryEntry] = []
        var seen = Set<UUID>()

        // Generate deletes of the input word and look up each
        let wordDeletes = generateDeletes(word: normalized, maxDistance: maxDeleteDistance)
        for variant in wordDeletes {
            if let entries = deleteMap[variant] {
                for entry in entries {
                    if !seen.contains(entry.id) {
                        seen.insert(entry.id)
                        candidates.append(entry)
                    }
                }
            }
        }

        return candidates
    }

    /// Check if a word is a known trigger (exact match)
    func isKnownTrigger(_ word: String) -> Bool {
        knownTriggers.contains(word.lowercased())
    }
}

// MARK: - String Distance Algorithms

/// Compute Damerau-Levenshtein distance between two strings
/// Handles insertions, deletions, substitutions, and transpositions
private func damerauLevenshtein(_ s1: String, _ s2: String) -> Int {
    let a = Array(s1.lowercased())
    let b = Array(s2.lowercased())
    let m = a.count
    let n = b.count

    // Handle empty string cases
    if m == 0 { return n }
    if n == 0 { return m }

    // DP matrix
    var d = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

    for i in 0...m { d[i][0] = i }
    for j in 0...n { d[0][j] = j }

    for i in 1...m {
        for j in 1...n {
            let cost = a[i-1] == b[j-1] ? 0 : 1

            d[i][j] = min(
                d[i-1][j] + 1,      // deletion
                d[i][j-1] + 1,      // insertion
                d[i-1][j-1] + cost  // substitution
            )

            // Transposition (adjacent character swap) - always costs 1
            if i > 1 && j > 1 && a[i-1] == b[j-2] && a[i-2] == b[j-1] {
                d[i][j] = min(d[i][j], d[i-2][j-2] + 1)
            }
        }
    }

    return d[m][n]
}

/// Convert edit distance to similarity score (0.0-1.0)
private func similarityScore(_ s1: String, _ s2: String) -> Double {
    let distance = damerauLevenshtein(s1, s2)
    let maxLen = max(s1.count, s2.count)
    guard maxLen > 0 else { return 1.0 }
    return 1.0 - (Double(distance) / Double(maxLen))
}

/// Simple word tokenizer - splits on non-alphanumeric characters
private func tokenize(_ text: String) -> [WordToken] {
    var tokens: [WordToken] = []
    var currentWord = ""
    var wordStart = 0

    for (offset, char) in text.enumerated() {
        if char.isLetter || char.isNumber {
            if currentWord.isEmpty {
                wordStart = offset
            }
            currentWord.append(char)
        } else {
            if !currentWord.isEmpty {
                tokens.append(WordToken(
                    text: currentWord,
                    startOffset: wordStart,
                    endOffset: offset
                ))
                currentWord = ""
            }
        }
    }

    // Handle trailing word
    if !currentWord.isEmpty {
        tokens.append(WordToken(
            text: currentWord,
            startOffset: wordStart,
            endOffset: text.count
        ))
    }

    return tokens
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

    /// Pattern matcher for efficient multi-pattern matching (word/phrase types)
    private var patternMatcher: PatternMatcher?

    /// Cached compiled regex patterns (regex type entries)
    private var regexCache: [(entry: DictionaryEntry, regex: NSRegularExpression)] = []

    /// Fuzzy delete index for approximate matching (fuzzy type entries)
    private var fuzzyIndex: FuzzyDeleteIndex?

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
                regexCache.removeAll()
                fuzzyIndex = nil
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

    /// Rebuild the pattern matcher, regex cache, and fuzzy index from current entries
    private func rebuildPatternMatcher() {
        let enabledEntries = entries.filter { $0.isEnabled }

        // Separate entries by match type
        let trieEntries = enabledEntries.filter { $0.matchType == .word || $0.matchType == .phrase }
        let regexEntries = enabledEntries.filter { $0.matchType == .regex }
        let fuzzyEntries = enabledEntries.filter { $0.matchType == .fuzzy }

        // Build trie for word/phrase entries
        if trieEntries.isEmpty {
            patternMatcher = nil
        } else {
            patternMatcher = PatternMatcher(entries: trieEntries)
        }

        // Compile regex entries
        regexCache = regexEntries.compactMap { entry in
            do {
                // No lookahead/lookbehind for performance
                let regex = try NSRegularExpression(pattern: entry.trigger, options: [.caseInsensitive])
                return (entry, regex)
            } catch {
                AppLogger.shared.warning(.system, "Invalid regex pattern", detail: "'\(entry.trigger)': \(error.localizedDescription)")
                return nil
            }
        }

        // Build fuzzy delete index
        if fuzzyEntries.isEmpty {
            fuzzyIndex = nil
        } else {
            fuzzyIndex = FuzzyDeleteIndex(entries: fuzzyEntries)
        }

        let total = trieEntries.count + regexCache.count + fuzzyEntries.count
        if total > 0 {
            AppLogger.shared.debug(.system, "Pattern matcher rebuilt",
                                  detail: "\(trieEntries.count) trie + \(regexCache.count) regex + \(fuzzyEntries.count) fuzzy patterns")
        }
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
            regexCache.removeAll()
            fuzzyIndex = nil
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
            regexCache.removeAll()
            fuzzyIndex = nil
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
        regexCache.removeAll()
        fuzzyIndex = nil
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
        var allReplacementInfos: [DictionaryProcessingResult.ReplacementInfo] = []

        // Step 1: Apply trie matches (word/phrase types)
        if let matcher = patternMatcher {
            let allMatches = matcher.findMatches(in: result)
            if !allMatches.isEmpty {
                let validMatches = filterAndResolveMatches(allMatches, in: result)
                if !validMatches.isEmpty {
                    let (newResult, infos) = applyReplacements(validMatches, to: result)
                    result = newResult
                    allReplacementInfos.append(contentsOf: infos)
                }
            }
        }

        // Step 2: Apply regex patterns with capture group substitution
        if !regexCache.isEmpty {
            let (newResult, infos) = applyRegexReplacements(to: result)
            result = newResult
            allReplacementInfos.append(contentsOf: infos)
        }

        // Step 3: Apply fuzzy matching to remaining unmatched words
        // Note: isKnownTrigger check prevents double-processing of exact matches
        if let index = fuzzyIndex {
            let (newResult, infos) = applyFuzzyMatching(to: result, index: index)
            result = newResult
            allReplacementInfos.append(contentsOf: infos)
        }

        if !allReplacementInfos.isEmpty {
            AppLogger.shared.debug(.transcription, "Applied replacements",
                                  detail: allReplacementInfos.map { "\($0.trigger) -> \($0.replacement)" }.joined(separator: ", "))
        }

        return DictionaryProcessingResult(
            original: text,
            processed: result,
            replacements: allReplacementInfos
        )
    }

    /// Apply regex patterns with capture group substitution
    private func applyRegexReplacements(to text: String) -> (String, [DictionaryProcessingResult.ReplacementInfo]) {
        var result = text
        var replacementInfos: [DictionaryProcessingResult.ReplacementInfo] = []

        for (entry, regex) in regexCache {
            let nsRange = NSRange(result.startIndex..., in: result)
            var matches: [(NSTextCheckingResult, Range<String.Index>)] = []

            // Collect all matches first
            regex.enumerateMatches(in: result, options: [], range: nsRange) { match, _, _ in
                guard let match = match, let range = Range(match.range, in: result) else { return }
                matches.append((match, range))
            }

            guard !matches.isEmpty else { continue }

            // Apply from end to start to preserve indices
            var count = 0
            for (match, range) in matches.reversed() {
                let replacement = buildRegexReplacement(
                    template: entry.replacement,
                    match: match,
                    in: result
                )
                result.replaceSubrange(range, with: replacement)
                count += 1
            }

            if count > 0 {
                replacementInfos.append(DictionaryProcessingResult.ReplacementInfo(
                    trigger: entry.trigger,
                    replacement: entry.replacement,
                    count: count
                ))
            }
        }

        return (result, replacementInfos)
    }

    /// Build replacement string by substituting capture groups ($1, $2, $3)
    private func buildRegexReplacement(
        template: String,
        match: NSTextCheckingResult,
        in text: String
    ) -> String {
        var result = template

        // Replace $1, $2, $3 with captured groups (up to 9)
        for i in 1...min(9, match.numberOfRanges - 1) {
            let groupRange = match.range(at: i)
            guard groupRange.location != NSNotFound,
                  let range = Range(groupRange, in: text) else { continue }

            let captured = String(text[range])
            result = result.replacingOccurrences(of: "$\(i)", with: captured)
        }

        return result
    }

    // MARK: - Fuzzy Matching

    /// Apply fuzzy matching to words not matched by exact methods
    /// - Parameters:
    ///   - text: Current text after exact replacements
    ///   - index: The fuzzy delete index
    /// - Returns: Processed text and replacement info
    private func applyFuzzyMatching(
        to text: String,
        index: FuzzyDeleteIndex
    ) -> (String, [DictionaryProcessingResult.ReplacementInfo]) {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return (text, []) }

        var replacements: [(token: WordToken, entry: DictionaryEntry, score: Double)] = []

        for token in tokens {
            // Skip short words
            guard token.text.count >= FuzzyConfig.minWordLength else { continue }

            // Skip if word is a known trigger (exact match - already handled by trie)
            if index.isKnownTrigger(token.text) { continue }

            // Find fuzzy candidates
            let candidates = index.findCandidates(for: token.text)
            guard !candidates.isEmpty else { continue }

            // Score candidates
            var scored: [(entry: DictionaryEntry, score: Double)] = []
            for entry in candidates {
                let score = similarityScore(token.text, entry.trigger)
                if score >= FuzzyConfig.scoreThreshold {
                    scored.append((entry, score))
                }
            }

            guard !scored.isEmpty else { continue }

            // Sort by score descending
            scored.sort { $0.score > $1.score }

            // Check margin - best must be clearly better than second-best
            let best = scored[0]
            if scored.count > 1 {
                let second = scored[1]
                if best.score - second.score < FuzzyConfig.marginDelta {
                    continue // Ambiguous match - skip
                }
            }

            replacements.append((token, best.entry, best.score))
        }

        guard !replacements.isEmpty else { return (text, []) }

        // Apply replacements from end to start to preserve indices
        var result = text
        var replacementCounts: [UUID: (entry: DictionaryEntry, count: Int)] = [:]

        for (token, entry, _) in replacements.reversed() {
            let startIdx = result.index(result.startIndex, offsetBy: token.startOffset)
            let endIdx = result.index(result.startIndex, offsetBy: token.endOffset)
            result.replaceSubrange(startIdx..<endIdx, with: entry.replacement)

            // Track counts
            if let existing = replacementCounts[entry.id] {
                replacementCounts[entry.id] = (existing.entry, existing.count + 1)
            } else {
                replacementCounts[entry.id] = (entry, 1)
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
            case .word:
                // Check word boundaries
                if isWordBoundary(at: match.startOffset, isStart: true, in: text) &&
                   isWordBoundary(at: match.endOffset, isStart: false, in: text) {
                    validMatches.append(match)
                }
            case .phrase:
                // Case-insensitive phrase matches anywhere
                validMatches.append(match)
            case .regex, .fuzzy:
                // Regex and fuzzy entries are processed separately (not via trie)
                // These cases shouldn't be reached as they skip the trie
                break
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
