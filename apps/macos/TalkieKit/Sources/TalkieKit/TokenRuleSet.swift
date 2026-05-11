import Foundation

// MARK: - Token Processing Protocol

/// Shared mutable context passed through all rule sets during a token scan.
public struct TokenContext {
    public var inQuote: Bool = false
    public var lastWasWord: Bool = false
    public var needsSpaceBeforeNextWord: Bool = false

    public init() {}
}

/// Result of a rule set consuming one or more tokens.
public struct TokenRuleResult {
    /// Output fragments to append.
    public let fragments: [String]
    /// Next token index to process.
    public let nextIndex: Int

    public init(fragments: [String], nextIndex: Int) {
        self.fragments = fragments
        self.nextIndex = nextIndex
    }

    public init(_ fragment: String, nextIndex: Int) {
        self.fragments = [fragment]
        self.nextIndex = nextIndex
    }
}

/// A rule set that processes tokens in a sequential scan.
/// Rule sets may consume multiple tokens (lookahead) and update shared context.
public protocol TokenRuleSet: AnyObject {
    func consume(words: [String], at i: Int, context: inout TokenContext) -> TokenRuleResult?
}

// MARK: - Composed Token Processor

/// How words are spaced in the output.
public enum TokenSpacingMode {
    /// Protocol mode: no spaces between tokens unless "space" token is used.
    /// Words inside quotes get auto-spaced.
    case explicit

    /// Natural mode: spaces between all words by default.
    /// Rule set outputs (symbols, numbers) attach without extra space.
    case natural
}

/// Composes multiple rule sets into a single processor.
/// Tries each rule set in priority order; first match wins.
public final class ComposedTokenProcessor {
    private let ruleSets: [TokenRuleSet]
    private let preNormalize: Bool
    private let spacing: TokenSpacingMode

    /// - Parameters:
    ///   - ruleSets: Rule sets in priority order (first match wins)
    ///   - preNormalize: Whether to normalize compound forms like "camelCase" → "camel case" before tokenizing
    ///   - spacing: How to handle spaces between tokens
    public init(ruleSets: [TokenRuleSet], preNormalize: Bool = false, spacing: TokenSpacingMode = .explicit) {
        self.ruleSets = ruleSets
        self.preNormalize = preNormalize
        self.spacing = spacing
    }

    public func process(_ text: String) -> String {
        let input = preNormalize ? Self.normalizeCompoundForms(text) : text
        let words = input.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var output: [String] = []
        var i = 0
        var context = TokenContext()

        while i < words.count {
            var handled = false
            for ruleSet in ruleSets {
                if let result = ruleSet.consume(words: words, at: i, context: &context) {
                    if spacing == .natural,
                       let firstFragment = result.fragments.first,
                       Self.fragmentNeedsLeadingSpace(firstFragment),
                       (context.lastWasWord || context.needsSpaceBeforeNextWord) {
                        output.append(" ")
                    }
                    output.append(contentsOf: result.fragments)
                    switch spacing {
                    case .explicit:
                        context.lastWasWord = false
                        context.needsSpaceBeforeNextWord = false
                    case .natural:
                        let lastFragment = result.fragments.last ?? ""
                        context.lastWasWord = Self.fragmentBehavesLikeWord(lastFragment)
                        context.needsSpaceBeforeNextWord = Self.fragmentNeedsTrailingSpace(lastFragment)
                    }
                    i = result.nextIndex
                    handled = true
                    break
                }
            }
            if !handled {
                // Pass-through: regular word
                switch spacing {
                case .explicit:
                    if context.inQuote && context.lastWasWord {
                        output.append(" ")
                    }
                case .natural:
                    if context.lastWasWord || context.needsSpaceBeforeNextWord {
                        output.append(" ")
                    }
                }
                output.append(words[i])
                context.lastWasWord = true
                context.needsSpaceBeforeNextWord = false
                i += 1
            }
        }
        return output.joined()
    }

    private static func fragmentBehavesLikeWord(_ fragment: String) -> Bool {
        guard let lastScalar = fragment.unicodeScalars.last else { return false }
        return CharacterSet.alphanumerics.contains(lastScalar)
    }

    private static func fragmentNeedsLeadingSpace(_ fragment: String) -> Bool {
        guard let firstScalar = fragment.unicodeScalars.first else { return false }
        return CharacterSet.alphanumerics.contains(firstScalar)
    }

    private static func fragmentNeedsTrailingSpace(_ fragment: String) -> Bool {
        switch fragment {
        case ".", ",", "!", "?", ";", ":", ")", "]", "}", ">":
            return true
        default:
            return false
        }
    }

    // MARK: - Pre-normalization

    private static let compoundPatterns: [(NSRegularExpression, String)] = {
        let pairs: [(String, String)] = [
            (#"(?i)\bcamel[-_]?case\b"#, "camel case"),
            (#"(?i)\bpascal[-_]?case\b"#, "pascal case"),
            (#"(?i)\bsnake[-_]?case\b"#, "snake case"),
            (#"(?i)\bkebab[-_]?case\b"#, "kebab case"),
            (#"(?i)\bscreaming[-_]?case\b"#, "screaming case"),
            (#"(?i)\ball[-_]caps\b"#, "all caps"),
        ]
        return pairs.compactMap { (pattern, replacement) in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (regex, replacement)
        }
    }()

    static func normalizeCompoundForms(_ text: String) -> String {
        var result = text
        for (regex, replacement) in compoundPatterns {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: replacement
            )
        }
        return result
    }
}
