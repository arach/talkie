//
//  PhraseDetector.swift
//  TalkieLive
//
//  Utility for detecting wake, end, and cancel phrases in transcribed text.
//  Uses fuzzy matching with phonetic substitutions and Levenshtein distance.
//

import Foundation
import TalkieKit

private let log = Log(.system)

// MARK: - Phrase Match Result

/// Result of a phrase detection
struct PhraseMatchResult: Equatable {
    /// The range of the matched phrase in the original text
    let range: Range<String.Index>

    /// Text before the matched phrase
    let textBefore: String

    /// Text after the matched phrase
    let textAfter: String

    /// The variation that matched (for debugging)
    let matchedVariation: String
}

// MARK: - Phrase Detector

/// Detects wake, end, and cancel phrases in text using fuzzy matching
final class PhraseDetector: Sendable {
    // MARK: - Configuration

    let wakePhrase: String
    let endPhrase: String
    let cancelPhrase: String

    /// Maximum Levenshtein distance for fuzzy matching
    let maxDistance: Int

    // MARK: - Phonetic Substitutions

    /// Common phonetic substitutions for transcription errors
    private static let phoneticSubstitutions: [String: [String]] = [
        // Wake word variations - expanded for more tolerance
        "hey": ["hay", "a", "eh", "ey", "hey,", "hey.", "hi", "hate", "heh", "he", "pay", "say", "way", "they"],
        "talkie": ["talky", "taki", "talki", "talkey", "talk he", "talkie,", "talkie.", "tacky", "talkee",
                   "talky,", "talking", "talkin", "talkin'", "taco", "talky.", "talcky", "tocky", "talka",
                   "turkey", "taffy", "tauky"],
        // End phrase variations
        "that's": ["thats", "that is", "that's,", "that's.", "dats", "that", "that", "this is", "this"],
        "it": ["it.", "it,", "eat", "at", "in", "is"],
        // Cancel variations
        "never": ["neva", "never,", "never.", "neber", "ever"],
        "mind": ["mind.", "mind,", "mine", "mined", "my"]
    ]

    // MARK: - Cached Variations

    private let wakePhraseVariations: [String]
    private let endPhraseVariations: [String]
    private let cancelPhraseVariations: [String]

    // MARK: - Init

    init(
        wakePhrase: String = "hey talkie",
        endPhrase: String = "that's it",
        cancelPhrase: String = "never mind",
        maxDistance: Int = 3  // Increased from 2 for more permissive matching
    ) {
        self.wakePhrase = wakePhrase.lowercased()
        self.endPhrase = endPhrase.lowercased()
        self.cancelPhrase = cancelPhrase.lowercased()
        self.maxDistance = maxDistance

        // Pre-compute variations
        self.wakePhraseVariations = Self.generateVariations(for: wakePhrase)
        self.endPhraseVariations = Self.generateVariations(for: endPhrase)
        self.cancelPhraseVariations = Self.generateVariations(for: cancelPhrase)

        // Log generated variations for debugging
        log.info("[PhraseDetector] Init with maxDistance=\(maxDistance)")
        log.debug("[PhraseDetector] Wake variations (\(wakePhraseVariations.count))", detail: wakePhraseVariations.prefix(10).joined(separator: ", "))
    }

    /// Create from AmbientTranscriptionConfig
    convenience init(config: AmbientTranscriptionConfig) {
        self.init(
            wakePhrase: config.wakePhrase,
            endPhrase: config.endPhrase,
            cancelPhrase: config.cancelPhrase
        )
    }

    // MARK: - Phrase Detection

    /// Check if text contains the wake phrase
    /// - Returns: Match result with range and surrounding text, or nil if not found
    func containsWakePhrase(in text: String) -> PhraseMatchResult? {
        let result = findPhrase(
            in: text,
            phrase: wakePhrase,
            variations: wakePhraseVariations
        )
        if result != nil {
            log.info("[PhraseDetector] ✅ Wake phrase MATCHED", detail: "via '\(result!.matchedVariation)'")
        }
        return result
    }

    /// Check if text contains the end phrase
    /// - Returns: Match result with range and surrounding text, or nil if not found
    func containsEndPhrase(in text: String) -> PhraseMatchResult? {
        return findPhrase(
            in: text,
            phrase: endPhrase,
            variations: endPhraseVariations
        )
    }

    /// Check if text contains the cancel phrase
    /// - Returns: Match result with range and surrounding text, or nil if not found
    func containsCancelPhrase(in text: String) -> PhraseMatchResult? {
        return findPhrase(
            in: text,
            phrase: cancelPhrase,
            variations: cancelPhraseVariations
        )
    }

    // MARK: - Private Methods

    /// Find a phrase in text using variations and fuzzy matching
    private func findPhrase(
        in text: String,
        phrase: String,
        variations: [String]
    ) -> PhraseMatchResult? {
        let lowercased = text.lowercased()

        // Try exact/variation match first (faster)
        for variation in variations {
            if let range = lowercased.range(of: variation) {
                // Verify word boundaries to avoid mid-word matches
                if hasWordBoundaries(in: lowercased, range: range) {
                    return makeResult(text: text, range: range, matchedVariation: variation)
                }
            }
        }

        // Fallback: Levenshtein distance for typos/mishearings
        if let range = fuzzyMatch(lowercased, phrase: phrase, maxDistance: maxDistance) {
            if hasWordBoundaries(in: lowercased, range: range) {
                return makeResult(text: text, range: range, matchedVariation: "fuzzy:\(phrase)")
            }
        }

        return nil
    }

    /// Create a match result from a range
    private func makeResult(
        text: String,
        range: Range<String.Index>,
        matchedVariation: String
    ) -> PhraseMatchResult {
        let textBefore = String(text[text.startIndex..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let textAfter = String(text[range.upperBound..<text.endIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return PhraseMatchResult(
            range: range,
            textBefore: textBefore,
            textAfter: textAfter,
            matchedVariation: matchedVariation
        )
    }

    // MARK: - Variation Generation

    /// Generate all variations of a phrase using phonetic substitutions
    private static func generateVariations(for phrase: String) -> [String] {
        var variations = Set<String>()
        let base = phrase.lowercased().trimmingCharacters(in: .whitespaces)
        variations.insert(base)

        // Add punctuation variants
        variations.insert(base + ".")
        variations.insert(base + ",")
        variations.insert(base.replacingOccurrences(of: " ", with: ", "))

        // Apply phonetic substitutions
        for (word, subs) in phoneticSubstitutions {
            if base.contains(word) {
                for sub in subs {
                    variations.insert(base.replacingOccurrences(of: word, with: sub))
                }
            }
        }

        // Generate combinations (apply multiple substitutions)
        let words = base.components(separatedBy: " ")
        if words.count >= 2 {
            // Try substituting each word independently
            for (i, word) in words.enumerated() {
                if let subs = phoneticSubstitutions[word] {
                    for sub in subs {
                        var newWords = words
                        newWords[i] = sub
                        variations.insert(newWords.joined(separator: " "))
                    }
                }
            }
        }

        return Array(variations)
    }

    // MARK: - Levenshtein Distance

    /// Calculate edit distance between two strings
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let m = s1.count
        let n = s2.count

        if m == 0 { return n }
        if n == 0 { return m }

        let s1Array = Array(s1)
        let s2Array = Array(s2)

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }

        return matrix[m][n]
    }

    /// Fuzzy match using Levenshtein distance with sliding window
    private func fuzzyMatch(_ text: String, phrase: String, maxDistance: Int) -> Range<String.Index>? {
        let lowercased = text.lowercased()
        let phraseLen = phrase.count

        // Sliding window approach
        guard lowercased.count >= phraseLen else { return nil }

        var startIndex = lowercased.startIndex
        while startIndex <= lowercased.index(lowercased.endIndex, offsetBy: -phraseLen, limitedBy: lowercased.startIndex) ?? lowercased.startIndex {
            let endIndex = lowercased.index(startIndex, offsetBy: phraseLen)
            let window = String(lowercased[startIndex..<endIndex])

            if levenshteinDistance(window, phrase) <= maxDistance {
                return startIndex..<endIndex
            }

            startIndex = lowercased.index(after: startIndex)
        }

        return nil
    }

    // MARK: - Word Boundaries

    /// Check word boundaries around a match
    private func hasWordBoundaries(in text: String, range: Range<String.Index>) -> Bool {
        let lowercased = text.lowercased()

        // Check before
        let beforeOK: Bool
        if range.lowerBound == lowercased.startIndex {
            beforeOK = true
        } else {
            let charBefore = lowercased[lowercased.index(before: range.lowerBound)]
            beforeOK = charBefore.isWhitespace || charBefore.isPunctuation
        }

        // Check after
        let afterOK: Bool
        if range.upperBound == lowercased.endIndex {
            afterOK = true
        } else {
            let charAfter = lowercased[range.upperBound]
            afterOK = charAfter.isWhitespace || charAfter.isPunctuation
        }

        return beforeOK && afterOK
    }
}
