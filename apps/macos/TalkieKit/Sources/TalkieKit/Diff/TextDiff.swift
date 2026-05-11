//
//  TextDiff.swift
//  TalkieKit
//
//  Word-based diff using Longest Common Subsequence algorithm
//  Optimized for typical voice memo lengths (~10k words or less)
//

import Foundation
import SwiftUI

// MARK: - Diff Types

public enum DiffOperation: Equatable, Sendable {
    case equal(String)      // Word unchanged
    case delete(String)     // Word removed from original
    case insert(String)     // Word added in proposed
}

public struct TextDiff: Sendable {
    public let operations: [DiffOperation]

    public init(operations: [DiffOperation]) {
        self.operations = operations
    }

    /// Original text reconstructed (equal + delete)
    public var originalText: String {
        var result = ""
        var isFirst = true
        var lastWasNewline = false

        for op in operations {
            switch op {
            case .equal(let word), .delete(let word):
                if DiffEngine.isNewline(word) {
                    result += "\n"
                    isFirst = true
                    lastWasNewline = true
                } else {
                    if !isFirst && !lastWasNewline { result += " " }
                    result += word
                    isFirst = false
                    lastWasNewline = false
                }
            case .insert:
                break
            }
        }
        return result
    }

    /// Proposed text reconstructed (equal + insert)
    public var proposedText: String {
        var result = ""
        var isFirst = true
        var lastWasNewline = false

        for op in operations {
            switch op {
            case .equal(let word), .insert(let word):
                if DiffEngine.isNewline(word) {
                    result += "\n"
                    isFirst = true
                    lastWasNewline = true
                } else {
                    if !isFirst && !lastWasNewline { result += " " }
                    result += word
                    isFirst = false
                    lastWasNewline = false
                }
            case .delete:
                break
            }
        }
        return result
    }

    /// Count of changes
    public var changeCount: Int {
        operations.filter { op in
            if case .equal = op { return false }
            return true
        }.count
    }

    /// Check if there are any changes
    public var hasChanges: Bool {
        changeCount > 0
    }
}

// MARK: - Diff Algorithm

public struct DiffEngine {

    /// Compute word-based diff between original and proposed text
    public static func diff(original: String, proposed: String) -> TextDiff {
        let originalWords = tokenize(original)
        let proposedWords = tokenize(proposed)

        // Edge cases
        if originalWords.isEmpty && proposedWords.isEmpty {
            return TextDiff(operations: [])
        }
        if originalWords.isEmpty {
            return TextDiff(operations: proposedWords.map { .insert($0) })
        }
        if proposedWords.isEmpty {
            return TextDiff(operations: originalWords.map { .delete($0) })
        }

        // Compute LCS and generate diff operations
        let lcs = computeLCS(originalWords, proposedWords)
        let operations = generateOperations(original: originalWords, proposed: proposedWords, lcs: lcs)

        return TextDiff(operations: operations)
    }

    // MARK: - Tokenization

    /// Special token representing a newline (paragraph break)
    public static let newlineToken = "\u{2028}" // Unicode line separator

    /// Split text into words, preserving newlines as tokens
    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []

        // Split by newlines first, then by spaces within each line
        let lines = text.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            // Add words from this line
            let words = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            tokens.append(contentsOf: words)

            // Add newline token after each line except the last
            if index < lines.count - 1 {
                tokens.append(newlineToken)
            }
        }

        return tokens
    }

    /// Check if a token is a newline marker
    public static func isNewline(_ token: String) -> Bool {
        token == newlineToken
    }

    // MARK: - LCS Algorithm

    /// Compute Longest Common Subsequence using dynamic programming
    private static func computeLCS(_ a: [String], _ b: [String]) -> Set<Int> {
        let m = a.count
        let n = b.count

        // DP table
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...m {
            for j in 1...n {
                if a[i - 1].lowercased() == b[j - 1].lowercased() {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to find indices in 'a' that are part of LCS
        var lcsIndices = Set<Int>()
        var i = m, j = n

        while i > 0 && j > 0 {
            if a[i - 1].lowercased() == b[j - 1].lowercased() {
                lcsIndices.insert(i - 1)
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        return lcsIndices
    }

    // MARK: - Operation Generation

    private static func generateOperations(original: [String], proposed: [String], lcs: Set<Int>) -> [DiffOperation] {
        var operations: [DiffOperation] = []

        var origIdx = 0
        var propIdx = 0

        while origIdx < original.count || propIdx < proposed.count {
            let origInLCS = origIdx < original.count && lcs.contains(origIdx)

            if origInLCS {
                let origWord = original[origIdx]

                // Emit insertions before this match
                while propIdx < proposed.count &&
                      proposed[propIdx].lowercased() != origWord.lowercased() {
                    operations.append(.insert(proposed[propIdx]))
                    propIdx += 1
                }

                // Emit equal operation
                if propIdx < proposed.count {
                    operations.append(.equal(proposed[propIdx]))
                    propIdx += 1
                }
                origIdx += 1

            } else if origIdx < original.count {
                operations.append(.delete(original[origIdx]))
                origIdx += 1

            } else {
                operations.append(.insert(proposed[propIdx]))
                propIdx += 1
            }
        }

        return operations
    }
}

// MARK: - Attributed String Helpers

extension TextDiff {

    /// Generate attributed text for original side (deletions in red strikethrough)
    public func attributedOriginal(
        baseColor: Color,
        deleteColor: Color = .red
    ) -> AttributedString {
        var result = AttributedString()
        var isFirst = true
        var lastWasNewline = false

        for op in operations {
            switch op {
            case .equal(let word):
                if DiffEngine.isNewline(word) {
                    result.append(AttributedString("\n"))
                    isFirst = true
                    lastWasNewline = true
                } else {
                    if !isFirst && !lastWasNewline { result.append(AttributedString(" ")) }
                    var attr = AttributedString(word)
                    attr.foregroundColor = baseColor
                    result.append(attr)
                    isFirst = false
                    lastWasNewline = false
                }

            case .delete(let word):
                if DiffEngine.isNewline(word) {
                    var attr = AttributedString("↵\n")
                    attr.foregroundColor = deleteColor
                    attr.strikethroughStyle = .single
                    result.append(attr)
                    isFirst = true
                    lastWasNewline = true
                } else {
                    if !isFirst && !lastWasNewline { result.append(AttributedString(" ")) }
                    var attr = AttributedString(word)
                    attr.foregroundColor = deleteColor
                    attr.strikethroughStyle = .single
                    attr.backgroundColor = deleteColor.opacity(0.15)
                    result.append(attr)
                    isFirst = false
                    lastWasNewline = false
                }

            case .insert:
                break
            }
        }

        return result
    }

    /// Generate attributed text for proposed side (insertions in green highlight)
    public func attributedProposed(
        baseColor: Color,
        insertColor: Color = .green
    ) -> AttributedString {
        var result = AttributedString()
        var isFirst = true
        var lastWasNewline = false

        for op in operations {
            switch op {
            case .equal(let word):
                if DiffEngine.isNewline(word) {
                    result.append(AttributedString("\n"))
                    isFirst = true
                    lastWasNewline = true
                } else {
                    if !isFirst && !lastWasNewline { result.append(AttributedString(" ")) }
                    var attr = AttributedString(word)
                    attr.foregroundColor = baseColor
                    result.append(attr)
                    isFirst = false
                    lastWasNewline = false
                }

            case .insert(let word):
                if DiffEngine.isNewline(word) {
                    var attr = AttributedString("↵\n")
                    attr.foregroundColor = insertColor
                    attr.backgroundColor = insertColor.opacity(0.15)
                    result.append(attr)
                    isFirst = true
                    lastWasNewline = true
                } else {
                    if !isFirst && !lastWasNewline { result.append(AttributedString(" ")) }
                    var attr = AttributedString(word)
                    attr.foregroundColor = insertColor
                    attr.backgroundColor = insertColor.opacity(0.15)
                    result.append(attr)
                    isFirst = false
                    lastWasNewline = false
                }

            case .delete:
                break
            }
        }

        return result
    }
}
