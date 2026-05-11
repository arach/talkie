//
//  TextPostProcessor.swift
//  TalkieEngine
//
//  Text post-processor for dictionary replacements and symbolic mapping.
//  Uses an optimized trie-based pattern matching for efficient text processing.
//  Engine is a runtime - it owns its dictionary file and persisted state.
//  Talkie configures what's active, but Engine runs independently.
//

import Foundation
import CryptoKit
import TalkieKit

// MARK: - Symbolic Mapper (Spoken Syntax Restoration)

/// Maps spoken technical terms to their symbolic equivalents.
/// E.g., "slash" → "/", "dash" → "-", "open paren" → "("
/// Designed for technical dictation contexts (terminals, code editors).
final class SymbolicMapper {

    /// Single mapping rule - Codable for JSON export/import
    struct Rule: Codable, Equatable {
        let spoken: String           // Lowercase spoken form
        let symbol: String           // Symbol to replace with
        let requiresWordBoundary: Bool  // Must be standalone word
        var isEnabled: Bool          // Can be toggled off

        init(_ spoken: String, _ symbol: String, wordBoundary: Bool = true, enabled: Bool = true) {
            self.spoken = spoken.lowercased()
            self.symbol = symbol
            self.requiresWordBoundary = wordBoundary
            self.isEnabled = enabled
        }

        // Coding keys for cleaner JSON
        enum CodingKeys: String, CodingKey {
            case spoken, symbol, requiresWordBoundary = "wordBoundary", isEnabled = "enabled"
        }
    }

    // MARK: - Singleton & File Storage

    static let shared = SymbolicMapper()

    /// Current active rules (loaded from file or defaults)
    private(set) var rules: [Rule]

    /// Path to the JSON file users can edit
    static var rulesFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let engineDir = appSupport.appendingPathComponent("TalkieEngine", isDirectory: true)
        try? FileManager.default.createDirectory(at: engineDir, withIntermediateDirectories: true)
        return engineDir.appendingPathComponent("symbolic-mapping.json")
    }

    /// Whether a custom file exists
    var hasCustomRulesFile: Bool {
        FileManager.default.fileExists(atPath: Self.rulesFileURL.path)
    }

    private init() {
        // Try to load from file, fall back to defaults
        if let data = try? Data(contentsOf: Self.rulesFileURL),
           var loadedRules = try? JSONDecoder().decode([Rule].self, from: data) {
            // Merge in any new default rules that aren't in the file yet
            // This ensures users get new rules we add without losing their customizations
            let loadedSpoken = Set(loadedRules.map { $0.spoken })
            var newRulesAdded = 0
            for defaultRule in Self.defaultRules {
                if !loadedSpoken.contains(defaultRule.spoken) {
                    loadedRules.append(defaultRule)
                    newRulesAdded += 1
                }
            }

            // If we added new rules, save the merged result back to file
            if newRulesAdded > 0 {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let mergedData = try? encoder.encode(loadedRules) {
                    try? mergedData.write(to: Self.rulesFileURL)
                }
                AppLogger.shared.info(.system, "Merged \(newRulesAdded) new rules into symbolic-mapping.json")
            }

            self.rules = loadedRules.filter { $0.isEnabled }.sorted { $0.spoken.count > $1.spoken.count }
            AppLogger.shared.info(.system, "Loaded symbolic mapping from file", detail: "\(loadedRules.count) rules, \(self.rules.count) enabled")
        } else {
            self.rules = Self.defaultRules
            // Write defaults to file so users can see/edit them
            writeDefaultsToFileIfNeeded()
        }
    }

    /// Write default rules to file (creates the file for users to discover)
    private func writeDefaultsToFileIfNeeded() {
        guard !hasCustomRulesFile else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(Self.defaultRules) {
            try? data.write(to: Self.rulesFileURL)
            AppLogger.shared.info(.system, "Created symbolic-mapping.json", detail: Self.rulesFileURL.path)
        }
    }

    /// Reload rules from file (call after user edits)
    func reloadFromFile() {
        if let data = try? Data(contentsOf: Self.rulesFileURL),
           var loadedRules = try? JSONDecoder().decode([Rule].self, from: data) {
            // Merge in any new default rules (same as init)
            let loadedSpoken = Set(loadedRules.map { $0.spoken })
            var newRulesAdded = 0
            for defaultRule in Self.defaultRules {
                if !loadedSpoken.contains(defaultRule.spoken) {
                    loadedRules.append(defaultRule)
                    newRulesAdded += 1
                }
            }

            if newRulesAdded > 0 {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let mergedData = try? encoder.encode(loadedRules) {
                    try? mergedData.write(to: Self.rulesFileURL)
                }
                AppLogger.shared.info(.system, "Merged \(newRulesAdded) new rules during reload")
            }

            self.rules = loadedRules.filter { $0.isEnabled }.sorted { $0.spoken.count > $1.spoken.count }
            AppLogger.shared.info(.system, "Reloaded symbolic mapping", detail: "\(self.rules.count) enabled rules")
        }
    }

    /// Reset to defaults (deletes custom file)
    func resetToDefaults() {
        try? FileManager.default.removeItem(at: Self.rulesFileURL)
        self.rules = Self.defaultRules
        writeDefaultsToFileIfNeeded()
        AppLogger.shared.info(.system, "Reset symbolic mapping to defaults")
    }

    /// Default symbolic mapping rules, ordered by spoken length (longest first for greedy matching)
    static let defaultRules: [Rule] = [
        // Multi-word patterns (must come first - longer matches win)
        Rule("open paren", "("),
        Rule("close paren", ")"),
        Rule("open parenthesis", "("),
        Rule("close parenthesis", ")"),
        Rule("open bracket", "["),
        Rule("close bracket", "]"),
        Rule("open square bracket", "["),
        Rule("close square bracket", "]"),
        Rule("open brace", "{"),
        Rule("close brace", "}"),
        Rule("open curly", "{"),
        Rule("close curly", "}"),
        Rule("open curly brace", "{"),
        Rule("close curly brace", "}"),
        Rule("open angle", "<"),
        Rule("close angle", ">"),
        Rule("less than", "<"),
        Rule("greater than", ">"),
        Rule("double quote", "\""),
        Rule("single quote", "'"),
        Rule("back tick", "`"),
        Rule("backtick", "`"),
        Rule("at sign", "@"),
        Rule("dollar sign", "$"),
        Rule("percent sign", "%"),
        Rule("and sign", "&"),
        Rule("double equals", "=="),
        Rule("triple equals", "==="),
        Rule("not equals", "!="),
        Rule("double colon", "::"),
        Rule("arrow", "->"),
        Rule("fat arrow", "=>"),
        Rule("double slash", "//"),
        Rule("new line", "\n"),
        Rule("newline", "\n"),

        // Single-word patterns
        Rule("slash", "/"),
        Rule("backslash", "\\"),
        Rule("dash", "-"),
        Rule("tack", "-"),
        Rule("hyphen", "-"),
        Rule("underscore", "_"),
        Rule("tilde", "~"),
        Rule("tilda", "~"),
        Rule("squiggly", "~"),
        Rule("squiggle", "~"),
        Rule("dot", "."),
        Rule("period", "."),
        Rule("comma", ","),
        Rule("colon", ":"),
        Rule("semicolon", ";"),
        Rule("equals", "="),
        Rule("plus", "+"),
        Rule("minus", "-"),
        Rule("asterisk", "*"),
        Rule("star", "*"),
        Rule("ampersand", "&"),
        Rule("pipe", "|"),
        Rule("caret", "^"),
        Rule("hash", "#"),
        Rule("pound", "#"),
        Rule("dollar", "$"),
        Rule("percent", "%"),
        Rule("at", "@", enabled: false),  // Disabled: use "at sign" or email pattern instead
        Rule("bang", "!"),
        Rule("exclamation", "!", enabled: false),  // Disabled: PunctuationProcessor handles "exclamation point/mark"
        Rule("question", "?", enabled: false),     // Disabled: PunctuationProcessor handles "question mark"
        Rule("quote", "\"", enabled: false),       // Disabled: PunctuationProcessor handles quote pairs
        Rule("apostrophe", "'"),
        Rule("tick", "`"),
    ].sorted { $0.spoken.count > $1.spoken.count }  // Longest first

    /// Apply symbolic mapping to text
    /// - Parameter text: Input text with spoken symbols
    /// - Returns: Text with symbols replaced and list of replacements made
    func apply(to text: String) -> (result: String, replacements: [(spoken: String, symbol: String, count: Int)]) {
        var result = text
        var replacementCounts: [String: (symbol: String, count: Int)] = [:]

        // Step 1: Context-aware email pattern (only if "at" candidate exists)
        // Converts "john at gmail dot com" → "john@gmail.com"
        // Cheap guard: skip regex if no " at " in text
        if result.range(of: " at ", options: .caseInsensitive) != nil {
            let (emailResult, emailCount) = Self.applyEmailPattern(result)
            if emailCount > 0 {
                result = emailResult
                replacementCounts["[email pattern]"] = ("user@domain.tld", emailCount)
            }
        }

        // Step 2: Standard symbolic mapping rules
        for rule in rules {
            let (newResult, count) = Self.replaceSpoken(rule, in: result)
            if count > 0 {
                result = newResult
                if let existing = replacementCounts[rule.spoken] {
                    replacementCounts[rule.spoken] = (rule.symbol, existing.count + count)
                } else {
                    replacementCounts[rule.spoken] = (rule.symbol, count)
                }
            }
        }

        let replacements = replacementCounts.map { (spoken: $0.key, symbol: $0.value.symbol, count: $0.value.count) }
        return (result, replacements)
    }

    // MARK: - Context-Aware Patterns

    /// Compiled email pattern regex (reused across calls)
    private static let emailRegex: NSRegularExpression? = {
        // Matches: word + " at " + word + " dot " + tld (2-6 chars)
        // Example: "john at gmail dot com" → "john@gmail.com"
        // Also handles subdomains: "john at mail dot company dot com"
        let pattern = #"(\w+)\s+at\s+(\w+(?:\s+dot\s+\w+)*)\s+dot\s+(\w{2,6})\b"#
        return try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }()

    /// Apply email pattern contextually
    /// - Returns: (result text, number of emails converted)
    private static func applyEmailPattern(_ text: String) -> (String, Int) {
        guard let regex = emailRegex else { return (text, 0) }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        guard !matches.isEmpty else { return (text, 0) }

        var result = text
        // Process matches in reverse to preserve indices
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let userRange = Range(match.range(at: 1), in: result),
                  let domainRange = Range(match.range(at: 2), in: result),
                  let tldRange = Range(match.range(at: 3), in: result) else { continue }

            let user = String(result[userRange])
            let domainPart = String(result[domainRange])
            let tld = String(result[tldRange])

            // Convert "mail dot company" → "mail.company"
            let domain = domainPart.replacingOccurrences(of: " dot ", with: ".", options: .caseInsensitive)

            let email = "\(user)@\(domain).\(tld)"
            result.replaceSubrange(fullRange, with: email)
        }

        return (result, matches.count)
    }

    /// Replace spoken form with symbol, respecting word boundaries
    private static func replaceSpoken(_ rule: Rule, in text: String) -> (String, Int) {
        guard rule.requiresWordBoundary else {
            // Simple replacement (rare case)
            let count = text.lowercased().components(separatedBy: rule.spoken).count - 1
            if count > 0 {
                return (text.replacingOccurrences(of: rule.spoken, with: rule.symbol, options: .caseInsensitive), count)
            }
            return (text, 0)
        }

        // Word boundary replacement using regex
        // \b doesn't work well with all Unicode, so we use a custom approach
        let pattern = "(?i)(?<=^|[\\s.,!?;:()\\[\\]{}])\\Q\(rule.spoken)\\E(?=[\\s.,!?;:()\\[\\]{}]|$)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (text, 0)
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        guard !matches.isEmpty else {
            return (text, 0)
        }

        // Apply replacements from end to preserve indices
        var result = text
        for match in matches.reversed() {
            guard let swiftRange = Range(match.range, in: result) else { continue }
            result.replaceSubrange(swiftRange, with: rule.symbol)
        }

        return (result, matches.count)
    }
}

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
/// Engine keeps a local cache, but Talkie's dictionary files are the source of truth.
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

    /// Talkie's environment-scoped dictionary directory.
    private static var talkieDictionariesDirectory: URL {
        TalkieEnvironment.current.appSupportDirectory
            .appending(path: "Dictionaries", directoryHint: .isDirectory)
    }

    // MARK: - Persisted State Keys

    private enum Defaults {
        static let dictionaryEnabled = "dictionaryEnabled"
        static let symbolicMappingEnabled = "symbolicMappingEnabled"
        static let fillerRemovalEnabled = "fillerRemovalEnabled"
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

    /// Whether symbolic mapping is enabled (persisted)
    /// Converts spoken symbols like "slash" → "/", "dash" → "-", etc.
    var isSymbolicMappingEnabled: Bool {
        get {
            // Default to true if not set (matches previous always-on behavior)
            if UserDefaults.standard.object(forKey: Defaults.symbolicMappingEnabled) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Defaults.symbolicMappingEnabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Defaults.symbolicMappingEnabled)
            AppLogger.shared.info(.system, "Symbolic mapping \(newValue ? "enabled" : "disabled")")
        }
    }

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

    /// Whether filler-word removal is enabled (persisted)
    /// Removes standalone filler words like "um", "uh", and "uhm".
    var isFillerRemovalEnabled: Bool {
        get {
            // Default to true if not set.
            if UserDefaults.standard.object(forKey: Defaults.fillerRemovalEnabled) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Defaults.fillerRemovalEnabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Defaults.fillerRemovalEnabled)
            AppLogger.shared.info(.system, "Filler removal \(newValue ? "enabled" : "disabled")")
        }
    }

    /// Whether dictionary has entries loaded
    var isLoaded: Bool { !entries.isEmpty }

    /// Last update timestamp
    private(set) var lastUpdated: Date?

    /// Content hash of the Talkie dictionary files last loaded into the engine.
    private var talkieDictionaryHash: String?

    private struct DictionarySnapshot {
        let hash: String
        let entries: [DictionaryEntry]
        let fileCount: Int
    }

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

    /// Set filler removal enabled state (called via XPC from Talkie)
    func setFillerRemovalEnabled(_ enabled: Bool) {
        isFillerRemovalEnabled = enabled
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

    /// Process text with symbolic mapping and dictionary replacements
    /// - Parameter text: Raw transcription text
    /// - Returns: Processed text with replacements applied
    func process(_ text: String) -> DictionaryProcessingResult {
        var result = text
        var allReplacementInfos: [DictionaryProcessingResult.ReplacementInfo] = []

        // Step 0: Apply symbolic mapping (spoken → symbols)
        // Converts "slash" → "/", "dash" → "-", etc. (if enabled)
        if isSymbolicMappingEnabled {
            let (symbolicResult, symbolicReplacements) = SymbolicMapper.shared.apply(to: result)
            if !symbolicReplacements.isEmpty {
                result = symbolicResult
                for (spoken, symbol, count) in symbolicReplacements {
                    allReplacementInfos.append(DictionaryProcessingResult.ReplacementInfo(
                        trigger: spoken,
                        replacement: symbol,
                        count: count
                    ))
                }
                AppLogger.shared.debug(.transcription, "Symbolic mapping applied",
                                      detail: symbolicReplacements.map { "\($0.spoken) → \($0.symbol) (×\($0.count))" }.joined(separator: ", "))
            }
        }

        // Step 0.5: Remove frequent filler words (if enabled)
        if isFillerRemovalEnabled {
            let (fillerResult, fillerReplacements) = applyFillerRemoval(to: result)
            if !fillerReplacements.isEmpty {
                result = fillerResult
                allReplacementInfos.append(contentsOf: fillerReplacements)
                let removedCount = fillerReplacements.reduce(0) { $0 + $1.count }
                AppLogger.shared.debug(.transcription, "Filler removal applied",
                                      detail: "removed \(removedCount) filler word(s)")
            }
        }

        reloadDictionaryIfStale()

        if isEnabled, !entries.isEmpty {
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
        }

        let (commandResult, commandRewrites) = ShellCommandPostProcessor.shared.process(result)
        if !commandRewrites.isEmpty {
            result = commandResult
            for rewrite in commandRewrites {
                allReplacementInfos.append(DictionaryProcessingResult.ReplacementInfo(
                    trigger: rewrite.trigger,
                    replacement: rewrite.replacement,
                    count: rewrite.count
                ))
            }
            AppLogger.shared.debug(.transcription, "Shell command post-processing applied",
                                  detail: commandRewrites.map { "\($0.trigger) -> \($0.replacement)" }.joined(separator: ", "))
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

    // MARK: - Talkie Dictionary Reload

    /// Refresh from Talkie's dictionary store when the files change.
    private func reloadDictionaryIfStale() {
        guard isEnabled else { return }

        let snapshot = loadTalkieDictionarySnapshot()
        guard snapshot.fileCount > 0 || talkieDictionaryHash != nil else { return }
        guard snapshot.hash != talkieDictionaryHash else { return }

        let previousCount = entries.count

        entries = snapshot.entries
        talkieDictionaryHash = snapshot.hash
        saveToFile()
        rebuildPatternMatcher()

        AppLogger.shared.info(
            .system,
            "Reloaded Talkie dictionaries",
            detail: "\(previousCount) -> \(snapshot.entries.count) entries"
        )
    }

    private func talkieDictionaryFileURLs() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.talkieDictionariesDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { $0.lastPathComponent.hasSuffix(".dict.json") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func loadTalkieDictionarySnapshot() -> DictionarySnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let fileURLs = talkieDictionaryFileURLs()
        var hasher = SHA256()
        var entries: [DictionaryEntry] = []

        for fileURL in fileURLs {
            do {
                let data = try Data(contentsOf: fileURL)
                if let nameData = fileURL.lastPathComponent.data(using: .utf8) {
                    hasher.update(data: nameData)
                }
                hasher.update(data: data)

                let dictionary = try decoder.decode(TalkieDictionary.self, from: data)
                if dictionary.isEnabled {
                    entries.append(contentsOf: dictionary.enabledEntries)
                }
            } catch {
                AppLogger.shared.warning(
                    .system,
                    "Failed to load Talkie dictionary",
                    detail: "\(fileURL.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }

        return DictionarySnapshot(
            hash: Self.hexString(from: hasher.finalize()),
            entries: entries,
            fileCount: fileURLs.count
        )
    }

    private static func hexString(from digest: SHA256.Digest) -> String {
        digest.map { byte in
            let value = String(byte, radix: 16)
            return value.count == 1 ? "0\(value)" : value
        }
        .joined()
    }

    // MARK: - Filler Removal

    /// Regex matching standalone filler words.
    /// Focuses on common conversational variants: um, umm..., uh, uhh..., uhm...
    private static let fillerWordRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"(?i)\b(?:um+|uh+|uhm+)\b"#)
    }()

    /// Collapse duplicate commas created by filler removals.
    private static let fillerDuplicateCommaRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #",\s*,+"#)
    }()

    /// Remove spaces before punctuation.
    private static let fillerSpaceBeforePunctuationRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"[ \t]+([,.;:!?])"#)
    }()

    /// Collapse repeated horizontal whitespace.
    private static let fillerDoubleSpaceRegex: NSRegularExpression? = {
        // Preserve intentional indentation at line starts.
        try? NSRegularExpression(pattern: #"(?m)(?<!^)[ \t]{2,}"#)
    }()

    /// Remove line-leading punctuation fragments left by removed fillers.
    private static let fillerLeadingPunctuationRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"(?m)^[ \t]*[,;:]+[ \t]*"#)
    }()

    /// Remove common filler words and normalize punctuation/spacing after removal.
    private func applyFillerRemoval(
        to text: String
    ) -> (String, [DictionaryProcessingResult.ReplacementInfo]) {
        guard let fillerRegex = Self.fillerWordRegex else { return (text, []) }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = fillerRegex.matches(in: text, options: [], range: nsRange)
        guard !matches.isEmpty else { return (text, []) }

        var result = fillerRegex.stringByReplacingMatches(in: text, options: [], range: nsRange, withTemplate: "")

        if let regex = Self.fillerDuplicateCommaRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: ", ")
        }
        if let regex = Self.fillerSpaceBeforePunctuationRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }
        if let regex = Self.fillerLeadingPunctuationRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        if let regex = Self.fillerDoubleSpaceRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: " ")
        }

        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        let info = DictionaryProcessingResult.ReplacementInfo(
            trigger: "filler: um/uh",
            replacement: "removed",
            count: matches.count
        )

        return (result, [info])
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
