import Foundation

/// Per-word logistic regression classifier that detects protocol segments
/// in mixed dictations (e.g., "I want to check the directory ls dash la").
///
/// Identifies protocol anchor words (dash, dot, slash, space, etc.), then
/// expands ±2 words to capture adjacent command tokens (ls, git, etc.).
/// Natural speech passes through untouched.
///
/// Trained from `datasets/train-segment-classifier.py`. To retrain:
/// 1. Update training data in that script
/// 2. Run it to get new weights
/// 3. Update the constants below
public struct ProtocolSegmentClassifier {
    public static let shared = ProtocolSegmentClassifier()

    // MARK: - Model Parameters (from datasets/segment-classifier-model.json)

    private static let weights: [Double] = [
        +0.33411720958159185635,  // is_strong_protocol
        -0.01883618036579912114,  // is_weak_protocol
        +0.00000000000000000000,  // is_expanded_symbol
        +0.00000000000000000000,  // has_syntax_chars
        -0.09512784613770698672,  // word_length_norm
        -0.27082908357760426821,  // is_short_word
        +0.25826009349206091592,  // context_strong_density
        +0.24189819020570574315,  // context_any_density
        +0.35690881474192120981,  // left_is_strong
        +0.33751703709094504902,  // right_is_strong
        +0.09194955109384082836,  // is_number_like
        +1.05151196243534239549,  // strong_neighbor_count
        -0.17715608130670168485,  // is_all_lower
        -0.11667765899752853553,  // position_ratio
    ]

    private static let bias: Double = -1.12642523649575898581

    private static let threshold: Double = 0.5

    // MARK: - Vocabulary Sets

    /// Strong protocol words — almost never appear in natural speech
    private static let strongProtocol: Set<String> = [
        "dash", "dot", "slash", "pipe", "tilde", "hash", "dollar",
        "caret", "ampersand", "equals", "underscore", "backslash",
        "backtick", "semicolon", "colon",
        "minus", "hyphen", "asterisk", "hashtag",
        "paren", "brace", "bracket", "parenthesis", "curly",
        "capital", "caps", "camel", "snake", "pascal", "kebab", "screaming",
        "space",
        "redirect", "append",
    ]

    /// Weak protocol words — frequently appear in natural speech
    private static let weakProtocol: Set<String> = [
        "at", "star", "bang", "exclamation", "question", "comma", "quote",
        "period", "plus", "percent",
        "single", "open", "close", "angle", "forward", "back", "sign",
        "double", "mark", "than", "less", "new", "line", "all", "case",
    ]

    /// Expanded symbols (after symbolic mapping)
    private static let expandedSymbols: Set<String> = [
        "-", ".", "/", "\\", "_", "|", "~", "@", "#", "*",
        "+", "=", ":", ";", "&", "%", "^", "!", "?", "`",
        "$", "<", ">", "--", "&&", "||",
    ]

    private static let syntaxChars: Set<Character> = [
        "-", ".", "/", "\\", "_", "|", "~", "@", "#", ":", "=",
    ]

    private static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six",
        "seven", "eight", "nine", "ten",
    ]

    // MARK: - Segment Types

    public struct TextSegment {
        public enum Kind { case passthrough, protocolSegment }
        public let kind: Kind
        public let text: String
    }

    // MARK: - Public API

    /// Extract protocol segments from mixed dictation text.
    /// Returns segments split into passthrough (natural speech) and protocol (needs model).
    public func extractSegments(_ text: String) -> [TextSegment] {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return [] }

        // Step 1: Classify each word as protocol anchor
        var isAnchor = [Bool](repeating: false, count: words.count)
        for i in 0..<words.count {
            let prob = classifyWord(words[i], at: i, in: words)
            isAnchor[i] = prob >= Self.threshold
        }

        // No anchors → entire text is passthrough
        guard isAnchor.contains(true) else {
            return [TextSegment(kind: .passthrough, text: text)]
        }

        // Step 2: Expand ±2 around anchors to capture command tokens
        var inProtocol = [Bool](repeating: false, count: words.count)
        for i in 0..<words.count {
            if isAnchor[i] {
                let start = max(0, i - 2)
                let end = min(words.count - 1, i + 2)
                for j in start...end {
                    inProtocol[j] = true
                }
            }
        }

        // Step 3: Build contiguous segments
        var segments: [TextSegment] = []
        var currentKind: TextSegment.Kind = inProtocol[0] ? .protocolSegment : .passthrough
        var currentWords: [String] = [words[0]]

        for i in 1..<words.count {
            let kind: TextSegment.Kind = inProtocol[i] ? .protocolSegment : .passthrough
            if kind == currentKind {
                currentWords.append(words[i])
            } else {
                segments.append(TextSegment(kind: currentKind, text: currentWords.joined(separator: " ")))
                currentKind = kind
                currentWords = [words[i]]
            }
        }
        segments.append(TextSegment(kind: currentKind, text: currentWords.joined(separator: " ")))

        return segments
    }

    /// Returns true if the text contains any protocol segments.
    public func hasProtocolSegments(_ text: String) -> Bool {
        let segments = extractSegments(text)
        return segments.contains { $0.kind == .protocolSegment }
    }

    // MARK: - Per-Word Classification

    /// Classify a single word in context. Returns probability of being a protocol word.
    public func classifyWord(_ word: String, at position: Int, in words: [String]) -> Double {
        let features = extractFeatures(word: word, position: position, words: words)
        let logit = dot(features, Self.weights) + Self.bias
        return sigmoid(logit)
    }

    // MARK: - Feature Extraction

    private func extractFeatures(word: String, position: Int, words: [String]) -> [Double] {
        let lower = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        let stripped = word.trimmingCharacters(in: .whitespaces)
        let total = words.count

        // Build context window ±2
        let ctxStart = max(0, position - 2)
        let ctxEnd = min(total, position + 3)
        let context = Array(words[ctxStart..<ctxEnd])

        // Feature 0: is_strong_protocol
        let fStrong: Double = Self.strongProtocol.contains(lower) ? 1.0 : 0.0

        // Feature 1: is_weak_protocol
        let fWeak: Double = Self.weakProtocol.contains(lower) ? 1.0 : 0.0

        // Feature 2: is_expanded_symbol
        let fSymbol: Double = Self.expandedSymbols.contains(stripped) ? 1.0 : 0.0

        // Feature 3: has_syntax_chars
        var fSyntax = 0.0
        if lower.contains(where: { Self.syntaxChars.contains($0) }) {
            let isContraction = word.contains("'") || word.contains("\u{2019}")
            let isTrailingPeriod = word.hasSuffix(".") && !word.dropLast().contains(".")
            if !isContraction && !isTrailingPeriod {
                fSyntax = 1.0
            }
        }

        // Feature 4: word_length_norm
        let fLen = Double(word.count) / 10.0

        // Feature 5: is_short_word
        let fShort: Double = lower.count <= 3 ? 1.0 : 0.0

        // Feature 6: context_strong_density
        let ctxStrongCount = context.filter { isStrongProtocol($0) }.count
        let fCtxStrong = Double(ctxStrongCount) / Double(max(context.count, 1))

        // Feature 7: context_any_density
        let ctxAnyCount = context.filter { isAnyProtocol($0) }.count
        let fCtxAny = Double(ctxAnyCount) / Double(max(context.count, 1))

        // Feature 8: left_is_strong
        let fLeft: Double = position > 0 && isStrongProtocol(words[position - 1]) ? 1.0 : 0.0

        // Feature 9: right_is_strong
        let fRight: Double = position < total - 1 && isStrongProtocol(words[position + 1]) ? 1.0 : 0.0

        // Feature 10: is_number_like
        let fNumber: Double = (Self.numberWords.contains(lower) || CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: lower))) ? 1.0 : 0.0

        // Feature 11: strong_neighbor_count
        let fStrongNeighbors = Double(ctxStrongCount)

        // Feature 12: is_all_lower
        let fLower: Double = (word.allSatisfy({ $0.isLetter }) && word == word.lowercased()) ? 1.0 : 0.0

        // Feature 13: position_ratio
        let fPos = Double(position) / Double(max(total - 1, 1))

        return [
            fStrong, fWeak, fSymbol, fSyntax,
            fLen, fShort,
            fCtxStrong, fCtxAny,
            fLeft, fRight,
            fNumber, fStrongNeighbors,
            fLower, fPos,
        ]
    }

    // MARK: - Helpers

    private func isStrongProtocol(_ word: String) -> Bool {
        let lower = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        if Self.strongProtocol.contains(lower) { return true }
        let stripped = word.trimmingCharacters(in: .whitespaces)
        return Self.expandedSymbols.contains(stripped)
    }

    private func isAnyProtocol(_ word: String) -> Bool {
        let lower = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        if Self.strongProtocol.contains(lower) || Self.weakProtocol.contains(lower) { return true }
        let stripped = word.trimmingCharacters(in: .whitespaces)
        return Self.expandedSymbols.contains(stripped)
    }

    private func dot(_ a: [Double], _ b: [Double]) -> Double {
        var sum = 0.0
        for i in 0..<a.count {
            sum += a[i] * b[i]
        }
        return sum
    }

    private func sigmoid(_ x: Double) -> Double {
        1.0 / (1.0 + exp(-x))
    }
}
