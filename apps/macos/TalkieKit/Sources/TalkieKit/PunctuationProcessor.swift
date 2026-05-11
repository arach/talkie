import Foundation

/// Converts spoken punctuation to symbols.
///
/// General-purpose punctuation that applies in both natural dictation and code contexts.
/// These are symbols a normal person would say in everyday speech.
///
/// Handles:
/// - Multi-word: "question mark" → "?", "open paren" → "(", "exclamation point" → "!"
/// - Single-word: "comma" → ",", "colon" → ":", "period" → "."
/// - Quote tracking: updates `context.inQuote` for "quote" and "single quote"
public final class PunctuationProcessor: TokenRuleSet {

    struct TwoWordKey: Hashable {
        let first: String
        let second: String
    }

    static let twoWordSymbols: [TwoWordKey: String] = [
        TwoWordKey(first: "question", second: "mark"): "?",
        TwoWordKey(first: "exclamation", second: "point"): "!",
        TwoWordKey(first: "exclamation", second: "mark"): "!",
        TwoWordKey(first: "single", second: "quote"): "'",
        TwoWordKey(first: "open", second: "paren"): "(",
        TwoWordKey(first: "close", second: "paren"): ")",
        TwoWordKey(first: "open", second: "parenthesis"): "(",
        TwoWordKey(first: "close", second: "parenthesis"): ")",
        TwoWordKey(first: "open", second: "bracket"): "[",
        TwoWordKey(first: "close", second: "bracket"): "]",
        TwoWordKey(first: "open", second: "brace"): "{",
        TwoWordKey(first: "close", second: "brace"): "}",
        TwoWordKey(first: "open", second: "angle"): "<",
        TwoWordKey(first: "close", second: "angle"): ">",
        TwoWordKey(first: "open", second: "curly"): "{",
        TwoWordKey(first: "close", second: "curly"): "}",
        TwoWordKey(first: "less", second: "than"): "<",
        TwoWordKey(first: "new", second: "line"): "\n",
    ]

    /// Single-word punctuation. `nil` means the word needs lookahead (part of a two-word pair).
    static let singleWordSymbols: [String: String?] = [
        "comma": ",",
        "colon": ":",
        "semicolon": ";",
        "period": ".",
        "quote": "\"",
        "question": nil,     // needs "question mark"
        "exclamation": nil,  // needs "exclamation point/mark"
    ]

    public init() {}

    public func consume(words: [String], at i: Int, context: inout TokenContext) -> TokenRuleResult? {
        let w = words[i].lowercased()

        // Two-word punctuation first
        if i + 1 < words.count {
            let key = TwoWordKey(first: w, second: words[i + 1].lowercased())
            if let sym = Self.twoWordSymbols[key] {
                if sym == "\"" || sym == "'" {
                    context.inQuote = !context.inQuote
                }
                return TokenRuleResult(sym, nextIndex: i + 2)
            }
        }

        // Single-word punctuation
        if let symOpt = Self.singleWordSymbols[w], let sym = symOpt {
            if sym == "\"" || sym == "'" {
                context.inQuote = !context.inQuote
            }
            return TokenRuleResult(sym, nextIndex: i + 1)
        }

        return nil
    }
}
