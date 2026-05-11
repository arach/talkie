import Foundation

public struct TalkieRulePackTOMLError: LocalizedError, Equatable, Sendable {
    public let line: Int?
    public let reason: String

    public init(line: Int? = nil, reason: String) {
        self.line = line
        self.reason = reason
    }

    public var errorDescription: String? {
        if let line {
            return "Line \(line): \(reason)"
        }

        return reason
    }
}

/// Constrained TOML codec for rule packs.
///
/// This intentionally supports only the schema Talkie emits:
/// top-level pack metadata, `[[rules]]`, `[rules.transforms]`, and `[[tests]]`.
public enum TalkieRulePackTOML {
    public static func decode(_ source: String) throws -> TalkieRulePack {
        try Parser(source: source).parse()
    }

    public static func encode(_ pack: TalkieRulePack) -> String {
        var lines: [String] = [
            "version = \(pack.version)",
            "id = \(quoted(pack.id))",
            "name = \(quoted(pack.name))",
        ]

        if let description = pack.description, !description.isEmpty {
            lines.append("description = \(quoted(description))")
        }

        for rule in pack.rules {
            lines.append("")
            lines.append("[[rules]]")
            lines.append("id = \(quoted(rule.id))")
            lines.append("kind = \(quoted(rule.kind.rawValue))")
            lines.append("scope = \(quotedArray(rule.scope.map(\.rawValue)))")
            lines.append("priority = \(rule.priority)")
            lines.append("match = \(quoted(rule.match))")
            lines.append("emit = \(quoted(rule.emit))")

            if !rule.transforms.isEmpty {
                lines.append("")
                lines.append("[rules.transforms]")

                for captureName in rule.transforms.keys.sorted() {
                    let transforms = rule.transforms[captureName] ?? []
                    let encodedTransforms = transforms
                        .map(encodeTransform)
                        .joined(separator: ", ")
                    lines.append("\(captureName) = [\(encodedTransforms)]")
                }
            }
        }

        for test in pack.tests {
            lines.append("")
            lines.append("[[tests]]")
            lines.append("rule = \(quoted(test.rule))")
            lines.append("scope = \(quoted(test.scope.rawValue))")
            lines.append("input = \(quoted(test.input))")
            lines.append("output = \(quoted(test.output))")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func encodeTransform(_ transform: TalkieRulePack.Transform) -> String {
        var parts = ["op = \(quoted(transform.op.rawValue))"]

        if let mode = transform.mode {
            parts.append("mode = \(quoted(mode.rawValue))")
        }

        if let separator = transform.separator {
            parts.append("separator = \(quoted(separator))")
        }

        return "{ \(parts.joined(separator: ", ")) }"
    }

    private static func quotedArray(_ values: [String]) -> String {
        "[\(values.map(quoted).joined(separator: ", "))]"
    }

    private static func quoted(_ value: String) -> String {
        let encoder = JSONEncoder()
        let data = (try? encoder.encode(value)) ?? Data(#"\"\""#.utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

private extension TalkieRulePackTOML {
    struct Parser {
        let source: String

        func parse() throws -> TalkieRulePack {
            enum Section {
                case topLevel
                case rule(Int)
                case ruleTransforms(Int)
                case test(Int)
            }

            var section: Section = .topLevel

            var version: Int?
            var id: String?
            var name: String?
            var description: String?
            var rules: [RuleBuilder] = []
            var tests: [TestBuilder] = []

            let lines = source.split(separator: "\n", omittingEmptySubsequences: false)

            for (index, rawLine) in lines.enumerated() {
                let lineNumber = index + 1
                let line = stripComments(from: String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)

                guard !line.isEmpty else { continue }

                switch line {
                case "[[rules]]":
                    rules.append(RuleBuilder())
                    section = .rule(rules.count - 1)
                    continue
                case "[rules.transforms]":
                    guard !rules.isEmpty else {
                        throw TalkieRulePackTOMLError(line: lineNumber, reason: "`[rules.transforms]` must appear after `[[rules]]`.")
                    }
                    section = .ruleTransforms(rules.count - 1)
                    continue
                case "[[tests]]":
                    tests.append(TestBuilder())
                    section = .test(tests.count - 1)
                    continue
                default:
                    break
                }

                if line.hasPrefix("[") {
                    throw TalkieRulePackTOMLError(line: lineNumber, reason: "Unsupported TOML section `\(line)`.")
                }

                guard let (key, value) = splitAssignment(in: line) else {
                    throw TalkieRulePackTOMLError(line: lineNumber, reason: "Expected `key = value`.")
                }

                switch section {
                case .topLevel:
                    switch key {
                    case "version":
                        version = try parseInt(value, line: lineNumber)
                    case "id":
                        id = try parseString(value, line: lineNumber)
                    case "name":
                        name = try parseString(value, line: lineNumber)
                    case "description":
                        description = try parseString(value, line: lineNumber)
                    default:
                        throw TalkieRulePackTOMLError(line: lineNumber, reason: "Unknown pack field `\(key)`.")
                    }

                case .rule(let ruleIndex):
                    switch key {
                    case "id":
                        rules[ruleIndex].id = try parseString(value, line: lineNumber)
                    case "kind":
                        let rawKind = try parseString(value, line: lineNumber)
                        guard let kind = TalkieRulePack.Kind(rawValue: rawKind) else {
                            throw TalkieRulePackTOMLError(line: lineNumber, reason: "Unknown rule kind `\(rawKind)`.")
                        }
                        rules[ruleIndex].kind = kind
                    case "scope":
                        let rawScopes = try parseStringArray(value, line: lineNumber)
                        rules[ruleIndex].scope = try rawScopes.map {
                            guard let scope = TalkieRulePack.Scope(rawValue: $0) else {
                                throw TalkieRulePackTOMLError(line: lineNumber, reason: "Unknown rule scope `\($0)`.")
                            }
                            return scope
                        }
                    case "priority":
                        rules[ruleIndex].priority = try parseInt(value, line: lineNumber)
                    case "match":
                        rules[ruleIndex].match = try parseString(value, line: lineNumber)
                    case "emit":
                        rules[ruleIndex].emit = try parseString(value, line: lineNumber)
                    default:
                        throw TalkieRulePackTOMLError(line: lineNumber, reason: "Unknown rule field `\(key)`.")
                    }

                case .ruleTransforms(let ruleIndex):
                    let transformDictionaries = try parseInlineTableArray(value, line: lineNumber)
                    rules[ruleIndex].transforms[key] = try transformDictionaries.map {
                        try parseTransform($0, line: lineNumber)
                    }

                case .test(let testIndex):
                    switch key {
                    case "rule":
                        tests[testIndex].rule = try parseString(value, line: lineNumber)
                    case "scope":
                        let rawScope = try parseString(value, line: lineNumber)
                        guard let scope = TalkieRulePack.Scope(rawValue: rawScope) else {
                            throw TalkieRulePackTOMLError(line: lineNumber, reason: "Unknown test scope `\(rawScope)`.")
                        }
                        tests[testIndex].scope = scope
                    case "input":
                        tests[testIndex].input = try parseString(value, line: lineNumber)
                    case "output":
                        tests[testIndex].output = try parseString(value, line: lineNumber)
                    default:
                        throw TalkieRulePackTOMLError(line: lineNumber, reason: "Unknown test field `\(key)`.")
                    }
                }
            }

            guard let version else {
                throw TalkieRulePackTOMLError(reason: "Missing `version`.")
            }

            guard let id, !id.isEmpty else {
                throw TalkieRulePackTOMLError(reason: "Missing `id`.")
            }

            guard let name, !name.isEmpty else {
                throw TalkieRulePackTOMLError(reason: "Missing `name`.")
            }

            return TalkieRulePack(
                version: version,
                id: id,
                name: name,
                description: description,
                rules: try rules.enumerated().map { offset, builder in
                    try builder.build(ruleNumber: offset + 1)
                },
                tests: try tests.enumerated().map { offset, builder in
                    try builder.build(testNumber: offset + 1)
                }
            )
        }

        private func parseTransform(
            _ values: [String: String],
            line: Int
        ) throws -> TalkieRulePack.Transform {
            guard let opRaw = values["op"], let op = TalkieRulePack.Operation(rawValue: opRaw) else {
                throw TalkieRulePackTOMLError(line: line, reason: "Transform is missing a valid `op`.")
            }

            let mode: TalkieRulePack.SplitMode?
            if let modeRaw = values["mode"] {
                guard let parsedMode = TalkieRulePack.SplitMode(rawValue: modeRaw) else {
                    throw TalkieRulePackTOMLError(line: line, reason: "Unknown split mode `\(modeRaw)`.")
                }
                mode = parsedMode
            } else {
                mode = nil
            }

            return TalkieRulePack.Transform(
                op: op,
                mode: mode,
                separator: values["separator"]
            )
        }

        private func parseInt(_ value: String, line: Int) throws -> Int {
            guard let parsed = Int(value.trimmingCharacters(in: .whitespaces)) else {
                throw TalkieRulePackTOMLError(line: line, reason: "Expected integer value.")
            }
            return parsed
        }

        private func parseString(_ value: String, line: Int) throws -> String {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") else {
                throw TalkieRulePackTOMLError(line: line, reason: "Expected quoted string value.")
            }

            let decoder = JSONDecoder()
            guard let data = trimmed.data(using: .utf8),
                  let parsed = try? decoder.decode(String.self, from: data) else {
                throw TalkieRulePackTOMLError(line: line, reason: "Invalid string literal.")
            }

            return parsed
        }

        private func parseStringArray(_ value: String, line: Int) throws -> [String] {
            let body = try arrayBody(value, line: line)
            let items = try splitTopLevel(body, separator: ",", line: line)
            return try items.map { try parseString($0, line: line) }
        }

        private func parseInlineTableArray(_ value: String, line: Int) throws -> [[String: String]] {
            let body = try arrayBody(value, line: line)
            let items = try splitTopLevel(body, separator: ",", line: line)
            return try items.map { try parseInlineTable($0, line: line) }
        }

        private func parseInlineTable(_ value: String, line: Int) throws -> [String: String] {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else {
                throw TalkieRulePackTOMLError(line: line, reason: "Expected inline table value.")
            }

            let start = trimmed.index(after: trimmed.startIndex)
            let end = trimmed.index(before: trimmed.endIndex)
            let body = String(trimmed[start..<end]).trimmingCharacters(in: .whitespaces)

            guard !body.isEmpty else { return [:] }

            var result: [String: String] = [:]
            for field in try splitTopLevel(body, separator: ",", line: line) {
                guard let (key, rawValue) = splitAssignment(in: field) else {
                    throw TalkieRulePackTOMLError(line: line, reason: "Invalid inline table field.")
                }

                result[key] = try parseString(rawValue, line: line)
            }

            return result
        }

        private func arrayBody(_ value: String, line: Int) throws -> String {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else {
                throw TalkieRulePackTOMLError(line: line, reason: "Expected array value.")
            }

            let start = trimmed.index(after: trimmed.startIndex)
            let end = trimmed.index(before: trimmed.endIndex)
            let body = String(trimmed[start..<end]).trimmingCharacters(in: .whitespaces)
            return body
        }

        private func stripComments(from line: String) -> String {
            var result = ""
            var inQuotes = false
            var isEscaping = false

            for character in line {
                if isEscaping {
                    result.append(character)
                    isEscaping = false
                    continue
                }

                if character == "\\" {
                    result.append(character)
                    isEscaping = true
                    continue
                }

                if character == "\"" {
                    inQuotes.toggle()
                    result.append(character)
                    continue
                }

                if character == "#", !inQuotes {
                    break
                }

                result.append(character)
            }

            return result
        }

        private func splitAssignment(in text: String) -> (String, String)? {
            var inQuotes = false
            var isEscaping = false
            var bracketDepth = 0
            var braceDepth = 0

            for (offset, character) in text.enumerated() {
                if isEscaping {
                    isEscaping = false
                    continue
                }

                switch character {
                case "\\" where inQuotes:
                    isEscaping = true
                case "\"":
                    inQuotes.toggle()
                case "[" where !inQuotes:
                    bracketDepth += 1
                case "]" where !inQuotes:
                    bracketDepth -= 1
                case "{" where !inQuotes:
                    braceDepth += 1
                case "}" where !inQuotes:
                    braceDepth -= 1
                case "=" where !inQuotes && bracketDepth == 0 && braceDepth == 0:
                    let index = text.index(text.startIndex, offsetBy: offset)
                    let key = String(text[..<index]).trimmingCharacters(in: .whitespaces)
                    let valueStart = text.index(after: index)
                    let value = String(text[valueStart...]).trimmingCharacters(in: .whitespaces)
                    return (key, value)
                default:
                    break
                }
            }

            return nil
        }

        private func splitTopLevel(
            _ text: String,
            separator: Character,
            line: Int
        ) throws -> [String] {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return [] }

            var parts: [String] = []
            var inQuotes = false
            var isEscaping = false
            var bracketDepth = 0
            var braceDepth = 0
            var start = trimmed.startIndex
            var index = trimmed.startIndex

            while index < trimmed.endIndex {
                let character = trimmed[index]

                if isEscaping {
                    isEscaping = false
                } else {
                    switch character {
                    case "\\" where inQuotes:
                        isEscaping = true
                    case "\"":
                        inQuotes.toggle()
                    case "[" where !inQuotes:
                        bracketDepth += 1
                    case "]" where !inQuotes:
                        bracketDepth -= 1
                    case "{" where !inQuotes:
                        braceDepth += 1
                    case "}" where !inQuotes:
                        braceDepth -= 1
                    case separator where !inQuotes && bracketDepth == 0 && braceDepth == 0:
                        let part = String(trimmed[start..<index]).trimmingCharacters(in: .whitespaces)
                        if !part.isEmpty {
                            parts.append(part)
                        }
                        start = trimmed.index(after: index)
                    default:
                        break
                    }
                }

                index = trimmed.index(after: index)
            }

            if inQuotes || bracketDepth != 0 || braceDepth != 0 {
                throw TalkieRulePackTOMLError(line: line, reason: "Unbalanced TOML value.")
            }

            let tail = String(trimmed[start...]).trimmingCharacters(in: .whitespaces)
            if !tail.isEmpty {
                parts.append(tail)
            }

            return parts
        }
    }

    struct RuleBuilder {
        var id: String?
        var kind: TalkieRulePack.Kind = .rewrite
        var scope: [TalkieRulePack.Scope] = []
        var priority: Int = 0
        var match: String?
        var emit: String?
        var transforms: [String: [TalkieRulePack.Transform]] = [:]

        func build(ruleNumber: Int) throws -> TalkieRulePack.Rule {
            guard let id, !id.isEmpty else {
                throw TalkieRulePackTOMLError(reason: "Rule \(ruleNumber) is missing `id`.")
            }

            guard !scope.isEmpty else {
                throw TalkieRulePackTOMLError(reason: "Rule `\(id)` is missing `scope`.")
            }

            guard let match, !match.isEmpty else {
                throw TalkieRulePackTOMLError(reason: "Rule `\(id)` is missing `match`.")
            }

            guard let emit, !emit.isEmpty else {
                throw TalkieRulePackTOMLError(reason: "Rule `\(id)` is missing `emit`.")
            }

            return TalkieRulePack.Rule(
                id: id,
                kind: kind,
                scope: scope,
                priority: priority,
                match: match,
                emit: emit,
                transforms: transforms
            )
        }
    }

    struct TestBuilder {
        var rule: String?
        var scope: TalkieRulePack.Scope?
        var input: String?
        var output: String?

        func build(testNumber: Int) throws -> TalkieRulePack.Test {
            guard let rule, !rule.isEmpty else {
                throw TalkieRulePackTOMLError(reason: "Test \(testNumber) is missing `rule`.")
            }

            guard let scope else {
                throw TalkieRulePackTOMLError(reason: "Test for rule `\(rule)` is missing `scope`.")
            }

            guard let input else {
                throw TalkieRulePackTOMLError(reason: "Test for rule `\(rule)` is missing `input`.")
            }

            guard let output else {
                throw TalkieRulePackTOMLError(reason: "Test for rule `\(rule)` is missing `output`.")
            }

            return TalkieRulePack.Test(
                rule: rule,
                scope: scope,
                input: input,
                output: output
            )
        }
    }
}
