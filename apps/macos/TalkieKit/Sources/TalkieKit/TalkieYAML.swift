import Foundation

enum TalkieYAML {
    indirect enum Value: Equatable, Sendable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
        case array([Value])
        case object([String: Value])
    }

    struct Error: LocalizedError, Equatable, Sendable {
        let line: Int?
        let reason: String

        var errorDescription: String? {
            if let line {
                return "Line \(line): \(reason)"
            }

            return reason
        }
    }

    static func parse(_ source: String) throws -> [String: Value] {
        var parser = Parser(lines: source.components(separatedBy: .newlines))
        return try parser.parseRoot()
    }
}

private extension TalkieYAML {
    struct Parser {
        let lines: [String]
        var index = 0

        mutating func parseRoot() throws -> [String: Value] {
            try parseObject(expectedIndent: 0)
        }

        mutating func parseObject(expectedIndent: Int) throws -> [String: Value] {
            var object: [String: Value] = [:]

            while index < lines.count {
                let rawLine = lines[index]

                if rawLine.trimmingCharacters(in: .whitespaces).isEmpty {
                    index += 1
                    continue
                }

                let indent = rawLine.prefix { $0 == " " }.count
                let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)

                if trimmedLine.hasPrefix("#") {
                    index += 1
                    continue
                }

                if indent < expectedIndent {
                    break
                }

                if indent > expectedIndent {
                    throw Error(line: index + 1, reason: "Unexpected indentation.")
                }

                let content = stripComment(from: String(rawLine.dropFirst(indent)))
                guard let colonIndex = topLevelColon(in: content) else {
                    throw Error(line: index + 1, reason: "Expected `key: value`.")
                }

                let key = content[..<colonIndex].trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else {
                    throw Error(line: index + 1, reason: "Missing key before `:`.")
                }

                let remainderStart = content.index(after: colonIndex)
                let remainder = content[remainderStart...].trimmingCharacters(in: .whitespaces)
                index += 1

                if remainder.isEmpty {
                    object[key] = .object(try parseObject(expectedIndent: expectedIndent + 2))
                    continue
                }

                if remainder == "|" {
                    object[key] = .string(try parseBlockString(baseIndent: expectedIndent + 2))
                    continue
                }

                object[key] = try parseInlineValue(remainder, line: index)
            }

            return object
        }

        mutating func parseBlockString(baseIndent: Int) throws -> String {
            var lines: [String] = []

            while index < self.lines.count {
                let rawLine = self.lines[index]

                if rawLine.trimmingCharacters(in: .whitespaces).isEmpty {
                    lines.append("")
                    index += 1
                    continue
                }

                let indent = rawLine.prefix { $0 == " " }.count
                if indent < baseIndent {
                    break
                }

                lines.append(String(rawLine.dropFirst(baseIndent)))
                index += 1
            }

            return lines.joined(separator: "\n")
        }

        private func parseInlineValue(_ rawValue: String, line: Int) throws -> Value {
            let value = rawValue.trimmingCharacters(in: .whitespaces)

            if value == "true" {
                return .bool(true)
            }

            if value == "false" {
                return .bool(false)
            }

            if let intValue = Int(value) {
                return .int(intValue)
            }

            if let doubleValue = Double(value), value.contains(".") {
                return .double(doubleValue)
            }

            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                return .string(unescape(String(value.dropFirst().dropLast())))
            }

            if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
                return .string(String(value.dropFirst().dropLast()))
            }

            if value.hasPrefix("[") {
                return .array(try parseArray(value, line: line))
            }

            return .string(value)
        }

        private func parseArray(_ rawValue: String, line: Int) throws -> [Value] {
            guard rawValue.hasSuffix("]") else {
                throw Error(line: line, reason: "Expected closing `]` for array.")
            }

            let content = String(rawValue.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if content.isEmpty {
                return []
            }

            let parts = splitTopLevel(content, separator: ",")
            return try parts.map { try parseInlineValue($0, line: line) }
        }

        private func splitTopLevel(_ value: String, separator: Character) -> [String] {
            var parts: [String] = []
            var current = ""
            var bracketDepth = 0
            var activeQuote: Character?
            var previous: Character?

            for character in value {
                if let quote = activeQuote {
                    current.append(character)
                    if character == quote, previous != "\\" {
                        activeQuote = nil
                    }
                    previous = character
                    continue
                }

                switch character {
                case "\"", "'":
                    activeQuote = character
                    current.append(character)
                case "[":
                    bracketDepth += 1
                    current.append(character)
                case "]":
                    bracketDepth -= 1
                    current.append(character)
                default:
                    if character == separator, bracketDepth == 0 {
                        parts.append(current.trimmingCharacters(in: .whitespaces))
                        current = ""
                    } else {
                        current.append(character)
                    }
                }

                previous = character
            }

            if !current.isEmpty {
                parts.append(current.trimmingCharacters(in: .whitespaces))
            }

            return parts
        }

        private func topLevelColon(in line: String) -> String.Index? {
            var bracketDepth = 0
            var activeQuote: Character?
            var previous: Character?

            for index in line.indices {
                let character = line[index]

                if let quote = activeQuote {
                    if character == quote, previous != "\\" {
                        activeQuote = nil
                    }
                    previous = character
                    continue
                }

                switch character {
                case "\"", "'":
                    activeQuote = character
                case "[":
                    bracketDepth += 1
                case "]":
                    bracketDepth -= 1
                case ":" where bracketDepth == 0:
                    return index
                default:
                    break
                }

                previous = character
            }

            return nil
        }

        private func stripComment(from line: String) -> String {
            var result = ""
            var bracketDepth = 0
            var activeQuote: Character?
            var previous: Character?

            for character in line {
                if let quote = activeQuote {
                    result.append(character)
                    if character == quote, previous != "\\" {
                        activeQuote = nil
                    }
                    previous = character
                    continue
                }

                switch character {
                case "\"", "'":
                    activeQuote = character
                    result.append(character)
                case "[":
                    bracketDepth += 1
                    result.append(character)
                case "]":
                    bracketDepth -= 1
                    result.append(character)
                case "#" where bracketDepth == 0:
                    return result.trimmingCharacters(in: .whitespaces)
                default:
                    result.append(character)
                }

                previous = character
            }

            return result.trimmingCharacters(in: .whitespaces)
        }

        private func unescape(_ value: String) -> String {
            value
                .replacing("\\n", with: "\n")
                .replacing("\\\"", with: "\"")
                .replacing("\\\\", with: "\\")
        }
    }
}

extension Dictionary where Key == String, Value == TalkieYAML.Value {
    func requiredString(_ key: String) throws -> String {
        guard let value = self[key] else {
            throw TalkieYAML.Error(line: nil, reason: "Missing required field `\(key)`.")
        }

        guard case let .string(stringValue) = value else {
            throw TalkieYAML.Error(line: nil, reason: "Expected `\(key)` to be a string.")
        }

        return stringValue
    }

    func optionalString(_ key: String) throws -> String? {
        guard let value = self[key] else { return nil }
        guard case let .string(stringValue) = value else {
            throw TalkieYAML.Error(line: nil, reason: "Expected `\(key)` to be a string.")
        }

        return stringValue
    }

    func optionalBool(_ key: String) throws -> Bool? {
        guard let value = self[key] else { return nil }
        guard case let .bool(boolValue) = value else {
            throw TalkieYAML.Error(line: nil, reason: "Expected `\(key)` to be a boolean.")
        }

        return boolValue
    }

    func optionalInt(_ key: String) throws -> Int? {
        guard let value = self[key] else { return nil }
        guard case let .int(intValue) = value else {
            throw TalkieYAML.Error(line: nil, reason: "Expected `\(key)` to be an integer.")
        }

        return intValue
    }

    func optionalDouble(_ key: String) throws -> Double? {
        guard let value = self[key] else { return nil }

        switch value {
        case let .double(doubleValue):
            return doubleValue
        case let .int(intValue):
            return Double(intValue)
        default:
            throw TalkieYAML.Error(line: nil, reason: "Expected `\(key)` to be numeric.")
        }
    }

    func optionalStringArray(_ key: String) throws -> [String]? {
        guard let value = self[key] else { return nil }
        guard case let .array(values) = value else {
            throw TalkieYAML.Error(line: nil, reason: "Expected `\(key)` to be an array.")
        }

        return try values.map { value in
            guard case let .string(stringValue) = value else {
                throw TalkieYAML.Error(line: nil, reason: "Expected all `\(key)` values to be strings.")
            }

            return stringValue
        }
    }

    func optionalObject(_ key: String) throws -> [String: TalkieYAML.Value]? {
        guard let value = self[key] else { return nil }
        guard case let .object(objectValue) = value else {
            throw TalkieYAML.Error(line: nil, reason: "Expected `\(key)` to be an object.")
        }

        return objectValue
    }
}
