import Foundation

/// Logistic regression classifier that determines whether dictated input
/// needs LLM normalization or can be processed procedurally.
///
/// Ported from `datasets/needs-llm-classifier.py`. The model is 10 weights + a bias
/// trained on hand-crafted features. Retrain in Python and update constants here.
public struct NeedsLLMClassifier {
    public static let shared = NeedsLLMClassifier()

    // MARK: - Model Parameters (from datasets/needs-llm-model.json)

    private static let weights: [Double] = [
        -1.7262899181892912,  // space_ratio
        -4.262508378155058,   // space_present
        -0.9437095996085207,  // protocol_ratio
         2.1420661962764926,  // filler_count
         3.324701471305833,   // intent_count
         0.14425229651354413, // correction_count
        -3.2102164965682594,  // starts_casing
         0.30804019879345856, // word_count
         0.9174257808985996,  // non_protocol_ratio
        -0.09508729183500425, // avg_word_len
    ]

    private static let bias: Double = 2.6924004765246026

    private static let threshold: Double = 0.5

    // MARK: - Vocabulary Sets

    private static let protocolVocab: Set<String> = [
        // Symbol words
        "dash", "dot", "slash", "pipe", "redirect", "append", "less", "star",
        "bang", "hash", "tilde", "at", "dollar", "percent", "caret", "ampersand",
        "equals", "plus", "colon", "semicolon", "underscore", "comma", "backslash",
        "quote", "backtick", "question",
        // Synonyms
        "minus", "hyphen", "period", "asterisk", "hashtag",
        // Two-word symbol components
        "single", "open", "close", "paren", "brace", "bracket", "angle", "curly",
        "than", "mark", "double", "and", "forward", "back", "sign", "new", "line",
        "parenthesis",
        // Casing
        "capital", "all", "caps", "camel", "snake", "pascal", "kebab", "screaming",
        "case",
        // Space
        "space",
        // Number words
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
        "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen",
        "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty",
        "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "thousand",
    ]

    private static let fillerWords: Set<String> = [
        "okay", "ok", "so", "um", "uh", "umm", "like", "basically",
        "actually", "right", "alright", "yeah", "well", "hmm",
    ]

    private static let intentPhrases: [String] = [
        "i want", "i wanna", "can you", "let's", "let me", "we need",
        "type out", "should be", "go ahead", "i need", "i think",
        "we want", "the command", "just do", "run it", "make it",
        "change", "set the", "for the", "use the", "add the",
    ]

    private static let correctionPhrases: [String] = [
        "no wait", "wait no", "scratch", "not that", "go back",
        "actually no", "never mind", "hold on", "start over",
    ]

    private static let casingStarters: Set<String> = [
        "camel", "snake", "pascal", "kebab", "screaming",
    ]

    // MARK: - Public API

    /// Returns `true` if the text likely needs LLM normalization.
    public func classify(_ text: String) -> Bool {
        let features = extractFeatures(from: text)
        let logit = dot(features, Self.weights) + Self.bias
        return sigmoid(logit) >= Self.threshold
    }

    /// Returns the classification and the raw probability.
    public func classifyWithProbability(_ text: String) -> (needsLLM: Bool, probability: Double) {
        let features = extractFeatures(from: text)
        let logit = dot(features, Self.weights) + Self.bias
        let prob = sigmoid(logit)
        return (prob >= Self.threshold, prob)
    }

    // MARK: - Feature Extraction

    /// Extract 10 numeric features, mirroring the Python `extract_features` exactly.
    private func extractFeatures(from text: String) -> [Double] {
        let words = text.lowercased().split(separator: " ").map(String.init)
        let n = words.count
        guard n > 0 else { return [Double](repeating: 0.0, count: 10) }

        let nd = Double(n)

        // 1. space_ratio
        let spaceCount = words.filter { $0 == "space" }.count
        let spaceRatio = Double(spaceCount) / nd

        // 2. space_present
        let spacePresent: Double = spaceCount > 0 ? 1.0 : 0.0

        // 3. protocol_ratio
        let protocolCount = words.filter { Self.protocolVocab.contains($0) }.count
        let protocolRatio = Double(protocolCount) / nd

        // 4. filler_count
        let fillerCount = Double(words.filter { Self.fillerWords.contains($0) }.count)

        // 5. intent_count
        let textLower = text.lowercased()
        let intentCount = Double(Self.intentPhrases.filter { textLower.contains($0) }.count)

        // 6. correction_count
        let correctionCount = Double(Self.correctionPhrases.filter { textLower.contains($0) }.count)

        // 7. starts_casing
        let startsCasing: Double = Self.casingStarters.contains(words[0]) ? 1.0 : 0.0

        // 8. word_count (normalized)
        let wordCount = nd / 20.0

        // 9. non_protocol_ratio
        let nonProtocolRatio = 1.0 - protocolRatio

        // 10. avg_word_len
        let totalChars = words.reduce(0) { $0 + $1.count }
        let avgWordLen = Double(totalChars) / nd

        return [
            spaceRatio,
            spacePresent,
            protocolRatio,
            fillerCount,
            intentCount,
            correctionCount,
            startsCasing,
            wordCount,
            nonProtocolRatio,
            avgWordLen,
        ]
    }

    // MARK: - Math

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
