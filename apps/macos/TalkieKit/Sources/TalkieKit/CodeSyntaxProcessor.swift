import Foundation

/// Converts spoken code/terminal vocabulary to syntax.
///
/// Code-specific symbols and directives that only apply in protocol dictation mode.
///
/// Handles:
/// - "space" token → literal space (the defining feature of protocol mode)
/// - Three-word symbols: "two redirect ampersand" → "2>&"
/// - Casing directives: camelCase, snake_case, PascalCase, kebab-case, SCREAMING_CASE
/// - Two-word code symbols: "dash dash" → "--", "and and" → "&&", "pipe pipe" → "||"
/// - Case modifiers: "all caps WORD" → "WORD", "capital x" → "X"
/// - Single-word code symbols: "dash" → "-", "slash" → "/", "pipe" → "|", etc.
/// - Quote tracking for auto-spacing inside quoted regions
public final class CodeSyntaxProcessor: TokenRuleSet {

    // MARK: - Symbol Vocabulary

    struct TwoWordKey: Hashable {
        let first: String
        let second: String
    }

    struct ThreeWordKey: Hashable {
        let first: String
        let second: String
        let third: String
    }

    /// Single-word code symbols. `nil` means the word needs lookahead.
    static let symbols: [String: String?] = [
        "dash": "-",
        "dot": ".",
        "slash": "/",
        "pipe": "|",
        "redirect": ">",
        "append": ">>",
        "less": nil,       // needs "less than" (handled by PunctuationProcessor)
        "star": "*",
        "bang": "!",
        "hash": "#",
        "tilde": "~",
        "at": "@",
        "dollar": "$",
        "percent": "%",
        "caret": "^",
        "ampersand": "&",
        "equals": "=",
        "plus": "+",
        "colon": ":",
        "semicolon": ";",
        "underscore": "_",
        "comma": ",",
        "backslash": "\\",
        "quote": "\"",
        "backtick": "`",
        "question": nil,   // needs "question mark" (handled by PunctuationProcessor)
        // Synonyms
        "minus": "-",
        "hyphen": "-",
        "period": ".",
        "asterisk": "*",
        "hashtag": "#",
    ]

    static let twoWordSymbols: [TwoWordKey: String] = [
        TwoWordKey(first: "dash", second: "dash"): "--",
        TwoWordKey(first: "double", second: "dash"): "--",
        TwoWordKey(first: "minus", second: "minus"): "--",
        TwoWordKey(first: "and", second: "and"): "&&",
        TwoWordKey(first: "pipe", second: "pipe"): "||",
        TwoWordKey(first: "dot", second: "dot"): "..",
        TwoWordKey(first: "two", second: "redirect"): "2>",
        TwoWordKey(first: "forward", second: "slash"): "/",
        TwoWordKey(first: "back", second: "slash"): "\\",
        TwoWordKey(first: "equals", second: "sign"): "=",
        TwoWordKey(first: "at", second: "sign"): "@",
        TwoWordKey(first: "dollar", second: "sign"): "$",
    ]

    static let threeWordSymbols: [ThreeWordKey: String] = [
        ThreeWordKey(first: "two", second: "redirect", third: "ampersand"): "2>&",
    ]

    // MARK: - Casing Directives

    static let casingDirectives: Set<String> = [
        "camel", "snake", "pascal", "kebab", "screaming",
    ]

    public init() {}

    // MARK: - TokenRuleSet

    public func consume(words: [String], at i: Int, context: inout TokenContext) -> TokenRuleResult? {
        let w = words[i].lowercased()

        // "space" → literal space
        if w == "space" {
            return TokenRuleResult(" ", nextIndex: i + 1)
        }

        // Three-word symbols
        if i + 2 < words.count {
            let key = ThreeWordKey(first: w, second: words[i + 1].lowercased(), third: words[i + 2].lowercased())
            if let sym = Self.threeWordSymbols[key] {
                return TokenRuleResult(sym, nextIndex: i + 3)
            }
        }

        // Casing directives
        if let (result, nextI) = consumeCasing(words: words, i: i) {
            return TokenRuleResult(result, nextIndex: nextI)
        }

        // Two-word code symbols
        if i + 1 < words.count {
            let key = TwoWordKey(first: w, second: words[i + 1].lowercased())
            if let sym = Self.twoWordSymbols[key] {
                if sym == "\"" || sym == "'" {
                    context.inQuote = !context.inQuote
                }
                return TokenRuleResult(sym, nextIndex: i + 2)
            }
        }

        // "all caps <word>"
        if w == "all" && i + 2 < words.count && words[i + 1].lowercased() == "caps" {
            return TokenRuleResult(words[i + 2].uppercased(), nextIndex: i + 3)
        }

        // "capital <letter or word>"
        if w == "capital" && i + 1 < words.count {
            let next = words[i + 1]
            let capitalized = next.count == 1 ? next.uppercased() : next.prefix(1).uppercased() + next.dropFirst()
            return TokenRuleResult(capitalized, nextIndex: i + 2)
        }

        // Single-word code symbols
        if let symOpt = Self.symbols[w], let sym = symOpt {
            if sym == "\"" || sym == "'" {
                context.inQuote = !context.inQuote
            }
            return TokenRuleResult(sym, nextIndex: i + 1)
        }

        return nil
    }

    // MARK: - Casing Consumption

    private func consumeCasing(words: [String], i: Int) -> (String, Int)? {
        let w = words[i].lowercased()
        guard Self.casingDirectives.contains(w) else { return nil }
        guard i + 1 < words.count, words[i + 1].lowercased() == "case" else { return nil }

        let style = w
        var j = i + 2
        var parts: [String] = []

        while j < words.count {
            let next = words[j]
            if next == "space" { break }
            if Self.symbols[next] != nil { break }
            if Self.casingDirectives.contains(next.lowercased())
                && j + 1 < words.count && words[j + 1].lowercased() == "case" { break }
            if next == "all" || next == "capital" { break }
            if j + 1 < words.count {
                let twoKey = TwoWordKey(first: next, second: words[j + 1])
                if Self.twoWordSymbols[twoKey] != nil { break }
            }
            parts.append(next.lowercased())
            j += 1
        }

        guard !parts.isEmpty else { return nil }

        let result: String
        switch style {
        case "camel":
            result = parts[0] + parts.dropFirst().map { $0.capitalized }.joined()
        case "pascal":
            result = parts.map { $0.capitalized }.joined()
        case "snake":
            result = parts.joined(separator: "_")
        case "kebab":
            result = parts.joined(separator: "-")
        case "screaming":
            result = parts.map { $0.uppercased() }.joined(separator: "_")
        default:
            return nil
        }

        return (result, j)
    }
}
