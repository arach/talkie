import Foundation

/// User-authored rewrite rules loaded from disk.
///
/// Rule packs are persisted as TOML so the files stay user-owned, portable, and
/// easy to inspect in git. The runtime schema stays intentionally small:
/// match, transforms, and emit.
public struct TalkieRulePack: Codable, Equatable, Sendable {
    public var version: Int
    public var id: String
    public var name: String
    public var description: String?
    public var rules: [Rule]
    public var tests: [Test]

    public init(
        version: Int = 1,
        id: String,
        name: String,
        description: String? = nil,
        rules: [Rule],
        tests: [Test] = []
    ) {
        self.version = version
        self.id = id
        self.name = name
        self.description = description
        self.rules = rules
        self.tests = tests
    }

    public struct Rule: Codable, Equatable, Sendable {
        public var id: String
        public var kind: Kind
        public var scope: [Scope]
        public var priority: Int
        public var match: String
        public var emit: String
        public var transforms: [String: [Transform]]

        public init(
            id: String,
            kind: Kind = .rewrite,
            scope: [Scope],
            priority: Int = 0,
            match: String,
            emit: String,
            transforms: [String: [Transform]] = [:]
        ) {
            self.id = id
            self.kind = kind
            self.scope = scope
            self.priority = priority
            self.match = match
            self.emit = emit
            self.transforms = transforms
        }
    }

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case rewrite
    }

    public enum Scope: String, Codable, Sendable, CaseIterable {
        case natural
        case terminal
    }

    public struct Transform: Codable, Equatable, Sendable {
        public var op: Operation
        public var mode: SplitMode?
        public var separator: String?

        public init(
            op: Operation,
            mode: SplitMode? = nil,
            separator: String? = nil
        ) {
            self.op = op
            self.mode = mode
            self.separator = separator
        }
    }

    public enum Operation: String, Codable, Sendable, CaseIterable {
        case lowercase
        case uppercase
        case trim
        case split
        case join
    }

    public enum SplitMode: String, Codable, Sendable, CaseIterable {
        case words
    }

    public struct Test: Codable, Equatable, Sendable {
        public var rule: String
        public var scope: Scope
        public var input: String
        public var output: String

        public init(
            rule: String,
            scope: Scope,
            input: String,
            output: String
        ) {
            self.rule = rule
            self.scope = scope
            self.input = input
            self.output = output
        }
    }
}

public extension TalkieRulePack {
    static func starterPack(
        id: String = "terminal-rules",
        name: String = "Terminal Rules",
        description: String? = "Sample user-authored shell command rules."
    ) -> TalkieRulePack {
        TalkieRulePack(
            id: id,
            name: name,
            description: description,
            rules: [
                .init(
                    id: "bun-run-script",
                    scope: [.natural, .terminal],
                    priority: 100,
                    match: "bun run {script...}",
                    emit: "bun run {{script}}",
                    transforms: [
                        "script": [
                            .init(op: .lowercase),
                            .init(op: .split, mode: .words),
                            .init(op: .join, separator: ":"),
                        ]
                    ]
                )
            ],
            tests: [
                .init(
                    rule: "bun-run-script",
                    scope: .terminal,
                    input: "Bun run Native App Build",
                    output: "bun run native:app:build"
                )
            ]
        )
    }
}
