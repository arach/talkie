import Foundation

/// Deterministic executor for user-authored rewrite rules.
public struct TalkieRuleExecutor {
    public struct Match: Equatable, Sendable {
        public let output: String
        public let packID: String
        public let ruleID: String

        public init(output: String, packID: String, ruleID: String) {
            self.output = output
            self.packID = packID
            self.ruleID = ruleID
        }
    }

    public static let shared = TalkieRuleExecutor()

    public init() {}

    public func rewrite(
        _ input: String,
        scope: TalkieRulePack.Scope,
        packs: [TalkieRulePack]
    ) -> Match? {
        let words = tokenize(input)
        guard !words.isEmpty else { return nil }

        let compiledRules = packs.enumerated().flatMap { packOffset, pack in
            pack.rules.enumerated().compactMap { ruleOffset, rule in
                compile(rule, packID: pack.id, packOffset: packOffset, ruleOffset: ruleOffset)
            }
        }
        .sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                if lhs.packOffset == rhs.packOffset {
                    return lhs.ruleOffset < rhs.ruleOffset
                }
                return lhs.packOffset < rhs.packOffset
            }
            return lhs.priority > rhs.priority
        }

        for compiled in compiledRules {
            guard compiled.scope.contains(scope),
                  let captures = match(
                    compiled.pattern,
                    words: words,
                    patternIndex: 0,
                    wordIndex: 0,
                    captures: [:]
                  ) else {
                continue
            }

            let transformedCaptures = applyTransforms(captures, using: compiled.transforms)
            let output = render(compiled.emit, captures: transformedCaptures)
            return Match(output: output, packID: compiled.packID, ruleID: compiled.ruleID)
        }

        return nil
    }

    private enum PatternPart {
        case literal(String)
        case capture(name: String, mode: CaptureMode)
    }

    private enum CaptureMode {
        case single
        case oneOrMore
        case rest
    }

    private struct CompiledRule {
        let packID: String
        let ruleID: String
        let packOffset: Int
        let ruleOffset: Int
        let priority: Int
        let scope: [TalkieRulePack.Scope]
        let pattern: [PatternPart]
        let emit: String
        let transforms: [String: [TalkieRulePack.Transform]]
    }

    private func compile(
        _ rule: TalkieRulePack.Rule,
        packID: String,
        packOffset: Int,
        ruleOffset: Int
    ) -> CompiledRule? {
        guard rule.kind == .rewrite else { return nil }
        let pattern = compilePattern(rule.match)
        guard !pattern.isEmpty else { return nil }

        return CompiledRule(
            packID: packID,
            ruleID: rule.id,
            packOffset: packOffset,
            ruleOffset: ruleOffset,
            priority: rule.priority,
            scope: rule.scope,
            pattern: pattern,
            emit: rule.emit,
            transforms: rule.transforms
        )
    }

    private func compilePattern(_ pattern: String) -> [PatternPart] {
        tokenize(pattern).compactMap { token in
            if token.hasPrefix("{"), token.hasSuffix("}") {
                let inner = String(token.dropFirst().dropLast())
                if inner.hasSuffix("...") {
                    let name = String(inner.dropLast(3))
                    guard !name.isEmpty else { return nil }
                    return .capture(name: name, mode: .rest)
                }
                if inner.hasSuffix("+") {
                    let name = String(inner.dropLast())
                    guard !name.isEmpty else { return nil }
                    return .capture(name: name, mode: .oneOrMore)
                }
                guard !inner.isEmpty else { return nil }
                return .capture(name: inner, mode: .single)
            }

            return .literal(token.lowercased())
        }
    }

    private func match(
        _ pattern: [PatternPart],
        words: [String],
        patternIndex: Int,
        wordIndex: Int,
        captures: [String: String]
    ) -> [String: String]? {
        if patternIndex == pattern.count {
            return wordIndex == words.count ? captures : nil
        }

        guard wordIndex <= words.count else { return nil }

        switch pattern[patternIndex] {
        case .literal(let literal):
            guard wordIndex < words.count,
                  words[wordIndex].lowercased() == literal else {
                return nil
            }
            return match(
                pattern,
                words: words,
                patternIndex: patternIndex + 1,
                wordIndex: wordIndex + 1,
                captures: captures
            )

        case .capture(let name, let mode):
            switch mode {
            case .single:
                guard wordIndex < words.count else { return nil }
                var updated = captures
                updated[name] = words[wordIndex]
                return match(
                    pattern,
                    words: words,
                    patternIndex: patternIndex + 1,
                    wordIndex: wordIndex + 1,
                    captures: updated
                )

            case .oneOrMore, .rest:
                let minimumCount = 1
                for end in stride(from: words.count, through: wordIndex + minimumCount, by: -1) {
                    var updated = captures
                    updated[name] = words[wordIndex..<end].joined(separator: " ")
                    if let result = match(
                        pattern,
                        words: words,
                        patternIndex: patternIndex + 1,
                        wordIndex: end,
                        captures: updated
                    ) {
                        return result
                    }
                }
                return nil
            }
        }
    }

    private func applyTransforms(
        _ captures: [String: String],
        using transforms: [String: [TalkieRulePack.Transform]]
    ) -> [String: String] {
        var result = captures

        for (captureName, captureTransforms) in transforms {
            guard var value = result[captureName] else { continue }
            for transform in captureTransforms {
                value = apply(transform, to: value)
            }
            result[captureName] = value
        }

        return result
    }

    private func apply(_ transform: TalkieRulePack.Transform, to value: String) -> String {
        switch transform.op {
        case .lowercase:
            return value.lowercased()
        case .uppercase:
            return value.uppercased()
        case .trim:
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .split:
            switch transform.mode ?? .words {
            case .words:
                return tokenize(value).joined(separator: " ")
            }
        case .join:
            let separator = transform.separator ?? ""
            return tokenize(value).joined(separator: separator)
        }
    }

    private func render(_ template: String, captures: [String: String]) -> String {
        var rendered = template
        for (name, value) in captures {
            rendered = rendered.replacingOccurrences(of: "{{\(name)}}", with: value)
        }
        return rendered
    }

    private func tokenize(_ text: String) -> [String] {
        text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }
}
