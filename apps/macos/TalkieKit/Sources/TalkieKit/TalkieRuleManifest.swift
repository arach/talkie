import Foundation

public struct TalkieRuleManifest: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case normalize
        case expand
        case route
    }

    public struct When: Equatable, Sendable {
        public var event: String?
        public var apps: [String]
        public var bundleIDs: [String]
        public var sources: [String]
        public var workspacePaths: [String]
        public var projects: [String]
        public var modes: [String]
        public var minConfidence: Double?

        public init(
            event: String? = nil,
            apps: [String] = [],
            bundleIDs: [String] = [],
            sources: [String] = [],
            workspacePaths: [String] = [],
            projects: [String] = [],
            modes: [String] = [],
            minConfidence: Double? = nil
        ) {
            self.event = event
            self.apps = apps
            self.bundleIDs = bundleIDs
            self.sources = sources
            self.workspacePaths = workspacePaths
            self.projects = projects
            self.modes = modes
            self.minConfidence = minConfidence
        }
    }

    public struct Match: Equatable, Sendable {
        public enum MatchType: String, CaseIterable, Sendable {
            case exact
            case contains
            case regex
            case prefix
        }

        public var type: MatchType
        public var text: String?
        public var pattern: String?

        public init(type: MatchType, text: String? = nil, pattern: String? = nil) {
            self.type = type
            self.text = text
            self.pattern = pattern
        }
    }

    public struct Produce: Equatable, Sendable {
        public var replaceText: String?
        public var insertTemplate: String?
        public var runWorkflow: String?
        public var vars: [String: String]

        public init(
            replaceText: String? = nil,
            insertTemplate: String? = nil,
            runWorkflow: String? = nil,
            vars: [String: String] = [:]
        ) {
            self.replaceText = replaceText
            self.insertTemplate = insertTemplate
            self.runWorkflow = runWorkflow
            self.vars = vars
        }
    }

    public var id: String
    public var kind: Kind
    public var name: String?
    public var enabled: Bool
    public var priority: Int
    public var when: When
    public var match: Match
    public var produce: Produce

    public init(
        id: String,
        kind: Kind,
        name: String? = nil,
        enabled: Bool = true,
        priority: Int = 0,
        when: When = .init(),
        match: Match,
        produce: Produce
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.enabled = enabled
        self.priority = priority
        self.when = when
        self.match = match
        self.produce = produce
    }
}

public extension TalkieRuleManifest {
    static func load(from fileURL: URL) throws -> TalkieRuleManifest {
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let values = try TalkieYAML.parse(source)
        return try decode(values)
    }

    func validate(expectedID: String? = nil) throws {
        if let expectedID, id != expectedID {
            throw TalkieContextManifestError.idMismatch(expected: expectedID, actual: id)
        }

        if id.isEmpty {
            throw TalkieContextManifestError.missingField("id")
        }

        switch match.type {
        case .exact, .contains, .prefix:
            guard let text = match.text, !text.isEmpty else {
                throw TalkieContextManifestError.invalidField("Match type `\(match.type.rawValue)` requires `match.text`.")
            }
        case .regex:
            guard let pattern = match.pattern, !pattern.isEmpty else {
                throw TalkieContextManifestError.invalidField("Match type `regex` requires `match.pattern`.")
            }

            do {
                _ = try NSRegularExpression(pattern: pattern)
            } catch {
                throw TalkieContextManifestError.invalidField("Invalid regex pattern `\(pattern)`.")
            }
        }

        switch kind {
        case .normalize:
            guard let replaceText = produce.replaceText, !replaceText.isEmpty else {
                throw TalkieContextManifestError.invalidField("Normalize rules require `produce.replaceText`.")
            }
        case .expand:
            let hasOutput = !(produce.insertTemplate?.isEmpty ?? true) || !(produce.replaceText?.isEmpty ?? true)
            if !hasOutput {
                throw TalkieContextManifestError.invalidField("Expand rules require `produce.insertTemplate` or `produce.replaceText`.")
            }
        case .route:
            guard let workflow = produce.runWorkflow, !workflow.isEmpty else {
                throw TalkieContextManifestError.invalidField("Route rules require `produce.runWorkflow`.")
            }
        }

        if let minConfidence = when.minConfidence, !(0 ... 1).contains(minConfidence) {
            throw TalkieContextManifestError.invalidField("`when.minConfidence` must be between 0 and 1.")
        }
    }
}

private extension TalkieRuleManifest {
    static func decode(_ values: [String: TalkieYAML.Value]) throws -> TalkieRuleManifest {
        for key in values.keys {
            switch key {
            case "id", "kind", "name", "enabled", "priority", "when", "match", "produce":
                continue
            default:
                throw TalkieContextManifestError.unknownField(key)
            }
        }

        let id = try values.requiredString("id")
        let kindRaw = try values.requiredString("kind")
        guard let kind = Kind(rawValue: kindRaw) else {
            throw TalkieContextManifestError.invalidField("Unknown rule kind `\(kindRaw)`.")
        }

        let name = try values.optionalString("name")
        let enabled = try values.optionalBool("enabled") ?? true
        let priority = try values.optionalInt("priority") ?? 0
        let when = try decodeWhen(values.optionalObject("when") ?? [:])
        let match = try decodeMatch(values.optionalObject("match"))
        let produce = try decodeProduce(values.optionalObject("produce"))

        return TalkieRuleManifest(
            id: id,
            kind: kind,
            name: name,
            enabled: enabled,
            priority: priority,
            when: when,
            match: match,
            produce: produce
        )
    }

    static func decodeWhen(_ values: [String: TalkieYAML.Value]) throws -> When {
        for key in values.keys {
            switch key {
            case "event", "apps", "bundleIDs", "sources", "workspacePaths", "projects", "modes", "minConfidence":
                continue
            default:
                throw TalkieContextManifestError.unknownField("when.\(key)")
            }
        }

        return When(
            event: try values.optionalString("event"),
            apps: try values.optionalStringArray("apps") ?? [],
            bundleIDs: try values.optionalStringArray("bundleIDs") ?? [],
            sources: try values.optionalStringArray("sources") ?? [],
            workspacePaths: try values.optionalStringArray("workspacePaths") ?? [],
            projects: try values.optionalStringArray("projects") ?? [],
            modes: try values.optionalStringArray("modes") ?? [],
            minConfidence: try values.optionalDouble("minConfidence")
        )
    }

    static func decodeMatch(_ values: [String: TalkieYAML.Value]?) throws -> Match {
        guard let values else {
            throw TalkieContextManifestError.missingField("match")
        }

        for key in values.keys {
            switch key {
            case "type", "text", "pattern":
                continue
            default:
                throw TalkieContextManifestError.unknownField("match.\(key)")
            }
        }

        let typeRaw = try values.requiredString("type")
        guard let type = Match.MatchType(rawValue: typeRaw) else {
            throw TalkieContextManifestError.invalidField("Unknown match type `\(typeRaw)`.")
        }

        return Match(
            type: type,
            text: try values.optionalString("text"),
            pattern: try values.optionalString("pattern")
        )
    }

    static func decodeProduce(_ values: [String: TalkieYAML.Value]?) throws -> Produce {
        guard let values else {
            throw TalkieContextManifestError.missingField("produce")
        }

        for key in values.keys {
            switch key {
            case "replaceText", "insertTemplate", "runWorkflow", "vars":
                continue
            default:
                throw TalkieContextManifestError.unknownField("produce.\(key)")
            }
        }

        let varsObject = try values.optionalObject("vars") ?? [:]
        let vars = try varsObject.reduce(into: [String: String]()) { result, entry in
            guard case let .string(stringValue) = entry.value else {
                throw TalkieContextManifestError.invalidField("Expected `produce.vars.\(entry.key)` to be a string.")
            }

            result[entry.key] = stringValue
        }

        return Produce(
            replaceText: try values.optionalString("replaceText"),
            insertTemplate: try values.optionalString("insertTemplate"),
            runWorkflow: try values.optionalString("runWorkflow"),
            vars: vars
        )
    }
}
