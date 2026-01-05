//
//  AmbientSettings.swift
//  TalkieLive
//
//  Settings for Ambient Mode - always-on audio with wake word activation
//

import Foundation
import SwiftUI
import TalkieKit

// MARK: - Ambient State

/// Current state of ambient mode
enum AmbientState: String, Equatable {
    case disabled       // Ambient mode is off
    case listening      // Always-on, scanning for wake word
    case command        // Wake word detected, accumulating command
    case processing     // End phrase detected, routing command
    case cancelled      // Command was cancelled

    var isActive: Bool {
        self == .listening || self == .command || self == .processing
    }

    var displayName: String {
        switch self {
        case .disabled: return "Off"
        case .listening: return "Listening"
        case .command: return "Recording Command"
        case .processing: return "Processing"
        case .cancelled: return "Cancelled"
        }
    }
}

// MARK: - Ambient Settings

@MainActor
final class AmbientSettings: ObservableObject {
    static let shared = AmbientSettings()

    // MARK: - Storage

    private var storage: UserDefaults { TalkieSharedSettings }

    // MARK: - Published Settings

    /// Whether ambient mode is enabled (user toggle)
    @Published var isEnabled: Bool {
        didSet { save() }
    }

    /// Wake phrase to activate command mode (default: "hey talkie")
    @Published var wakePhrase: String {
        didSet { save() }
    }

    /// End phrase to complete command capture (default: "that's it")
    @Published var endPhrase: String {
        didSet { save() }
    }

    /// Cancel phrase to abort command (default: "never mind")
    @Published var cancelPhrase: String {
        didSet { save() }
    }

    /// Rolling buffer duration in seconds (default: 300 = 5 minutes)
    @Published var bufferDuration: TimeInterval {
        didSet { save() }
    }

    /// Whether to play audio chimes on activation/completion
    @Published var enableChimes: Bool {
        didSet { save() }
    }

    /// Whether to use streaming ASR for faster wake detection (vs batch)
    /// DEV-ONLY: Not exposed in UI. Toggle via defaults:
    /// `defaults write com.arach.talkie.shared ambientUseStreamingASR -bool true`
    @Published var useStreamingASR: Bool {
        didSet { save() }
    }

    /// Whether to enable batch channel (context buffer, 10s chunks)
    /// DEV-ONLY: Toggle for testing - disable to isolate streaming channel
    /// `defaults write com.arach.talkie.shared ambientUseBatchASR -bool false`
    @Published var useBatchASR: Bool {
        didSet { save() }
    }

    // MARK: - Fuzzy Matching

    /// Common phonetic substitutions for transcription errors
    private static let phoneticSubstitutions: [String: [String]] = [
        // Wake word variations
        "hey": ["hay", "a", "eh", "ey", "hey,", "hey."],
        "talkie": ["talky", "taki", "talki", "talkey", "talk he", "talkie,", "talkie.", "tacky", "talkee"],
        // End phrase variations
        "that's": ["thats", "that is", "that's,", "that's.", "dats", "that"],
        "it": ["it.", "it,", "eat"],
        // Cancel variations
        "never": ["neva", "never,", "never.", "neber"],
        "mind": ["mind.", "mind,", "mine", "mined"]
    ]

    /// Generate all variations of a phrase using phonetic substitutions
    private func generateVariations(for phrase: String) -> [String] {
        var variations = Set<String>()
        let base = phrase.lowercased().trimmingCharacters(in: .whitespaces)
        variations.insert(base)

        // Add punctuation variants
        variations.insert(base + ".")
        variations.insert(base + ",")
        variations.insert(base.replacingOccurrences(of: " ", with: ", "))

        // Apply phonetic substitutions
        for (word, subs) in Self.phoneticSubstitutions {
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
                if let subs = Self.phoneticSubstitutions[word] {
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

    /// Wake phrase variations for fuzzy matching
    var wakePhraseVariations: [String] {
        generateVariations(for: wakePhrase)
    }

    /// End phrase variations for fuzzy matching
    var endPhraseVariations: [String] {
        generateVariations(for: endPhrase)
    }

    /// Cancel phrase variations for fuzzy matching
    var cancelPhraseVariations: [String] {
        generateVariations(for: cancelPhrase)
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
    private func fuzzyMatch(_ text: String, phrase: String, maxDistance: Int = 2) -> Range<String.Index>? {
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

    // MARK: - Defaults

    static let defaultWakePhrase = "hey talkie"
    static let defaultEndPhrase = "that's it"
    static let defaultCancelPhrase = "never mind"
    static let defaultBufferDuration: TimeInterval = 300  // 5 minutes

    // MARK: - Init

    private init() {
        let store = TalkieSharedSettings

        // Load enabled state (default: false)
        self.isEnabled = store.bool(forKey: LiveSettingsKey.ambientEnabled)

        // Load wake phrase
        if let phrase = store.string(forKey: LiveSettingsKey.ambientWakePhrase), !phrase.isEmpty {
            self.wakePhrase = phrase
        } else {
            self.wakePhrase = Self.defaultWakePhrase
        }

        // Load end phrase
        if let phrase = store.string(forKey: LiveSettingsKey.ambientEndPhrase), !phrase.isEmpty {
            self.endPhrase = phrase
        } else {
            self.endPhrase = Self.defaultEndPhrase
        }

        // Load cancel phrase
        if let phrase = store.string(forKey: LiveSettingsKey.ambientCancelPhrase), !phrase.isEmpty {
            self.cancelPhrase = phrase
        } else {
            self.cancelPhrase = Self.defaultCancelPhrase
        }

        // Load buffer duration
        let duration = store.double(forKey: LiveSettingsKey.ambientBufferDuration)
        self.bufferDuration = duration > 0 ? duration : Self.defaultBufferDuration

        // Load chimes enabled (default: true)
        if store.object(forKey: LiveSettingsKey.ambientEnableChimes) != nil {
            self.enableChimes = store.bool(forKey: LiveSettingsKey.ambientEnableChimes)
        } else {
            self.enableChimes = true
        }

        // Load streaming ASR enabled (default: true - streaming is faster for wake detection)
        if store.object(forKey: LiveSettingsKey.ambientUseStreamingASR) != nil {
            self.useStreamingASR = store.bool(forKey: LiveSettingsKey.ambientUseStreamingASR)
        } else {
            self.useStreamingASR = true  // Default to streaming for fast wake detection
        }

        // Load batch ASR enabled (default: true - context buffer always on)
        if store.object(forKey: LiveSettingsKey.ambientUseBatchASR) != nil {
            self.useBatchASR = store.bool(forKey: LiveSettingsKey.ambientUseBatchASR)
        } else {
            self.useBatchASR = true  // Default to batch for context buffer
        }
    }

    // MARK: - Persistence

    private func save() {
        let store = storage

        store.set(isEnabled, forKey: LiveSettingsKey.ambientEnabled)
        store.set(wakePhrase, forKey: LiveSettingsKey.ambientWakePhrase)
        store.set(endPhrase, forKey: LiveSettingsKey.ambientEndPhrase)
        store.set(cancelPhrase, forKey: LiveSettingsKey.ambientCancelPhrase)
        store.set(bufferDuration, forKey: LiveSettingsKey.ambientBufferDuration)
        store.set(enableChimes, forKey: LiveSettingsKey.ambientEnableChimes)
        store.set(useStreamingASR, forKey: LiveSettingsKey.ambientUseStreamingASR)
        store.set(useBatchASR, forKey: LiveSettingsKey.ambientUseBatchASR)
    }

    // MARK: - Phrase Matching

    /// Check if text contains the wake phrase (case-insensitive, fuzzy with fallback)
    func containsWakePhrase(in text: String) -> Range<String.Index>? {
        let lowercased = text.lowercased()

        // Try exact/variation match first (faster)
        for variation in wakePhraseVariations {
            if let range = lowercased.range(of: variation) {
                // Verify word boundaries to avoid mid-word matches
                if hasWordBoundaries(in: lowercased, range: range) {
                    return range
                }
            }
        }

        // Fallback: Levenshtein distance for typos/mishearings
        if let range = fuzzyMatch(lowercased, phrase: wakePhrase.lowercased(), maxDistance: 2) {
            if hasWordBoundaries(in: lowercased, range: range) {
                return range
            }
        }

        return nil
    }

    /// Check if text contains the end phrase (case-insensitive, fuzzy with fallback)
    func containsEndPhrase(in text: String) -> Range<String.Index>? {
        let lowercased = text.lowercased()

        // Try exact/variation match first
        for variation in endPhraseVariations {
            if let range = lowercased.range(of: variation) {
                if hasWordBoundaries(in: lowercased, range: range) {
                    return range
                }
            }
        }

        // Fallback: Levenshtein distance
        if let range = fuzzyMatch(lowercased, phrase: endPhrase.lowercased(), maxDistance: 2) {
            if hasWordBoundaries(in: lowercased, range: range) {
                return range
            }
        }

        return nil
    }

    /// Check if text contains the cancel phrase (case-insensitive, fuzzy with fallback)
    func containsCancelPhrase(in text: String) -> Range<String.Index>? {
        let lowercased = text.lowercased()

        // Try exact/variation match first
        for variation in cancelPhraseVariations {
            if let range = lowercased.range(of: variation) {
                if hasWordBoundaries(in: lowercased, range: range) {
                    return range
                }
            }
        }

        // Fallback: Levenshtein distance
        if let range = fuzzyMatch(lowercased, phrase: cancelPhrase.lowercased(), maxDistance: 2) {
            if hasWordBoundaries(in: lowercased, range: range) {
                return range
            }
        }

        return nil
    }

    // MARK: - Reset

    /// Reset all settings to defaults
    func resetToDefaults() {
        wakePhrase = Self.defaultWakePhrase
        endPhrase = Self.defaultEndPhrase
        cancelPhrase = Self.defaultCancelPhrase
        bufferDuration = Self.defaultBufferDuration
        enableChimes = true
    }
}
