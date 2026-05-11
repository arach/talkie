import Foundation

public struct TalkieToolManifest: Equatable, Sendable {
    public enum Runtime: String, CaseIterable, Sendable {
        case node
        case python
        case shell
        case binary
    }

    public var id: String
    public var name: String
    public var enabled: Bool
    public var runtime: Runtime
    public var entry: String
    public var input: String
    public var timeoutMs: Int

    public init(
        id: String,
        name: String,
        enabled: Bool = true,
        runtime: Runtime,
        entry: String,
        input: String = TalkieTool.schemaVersion,
        timeoutMs: Int = 10_000
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.runtime = runtime
        self.entry = entry
        self.input = input
        self.timeoutMs = timeoutMs
    }
}

public extension TalkieToolManifest {
    static func load(from fileURL: URL) throws -> TalkieToolManifest {
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

        if name.isEmpty {
            throw TalkieContextManifestError.missingField("name")
        }

        if entry.isEmpty {
            throw TalkieContextManifestError.missingField("entry")
        }

        if input != TalkieTool.schemaVersion {
            throw TalkieContextManifestError.unsupportedSchemaVersion(input)
        }

        if timeoutMs <= 0 {
            throw TalkieContextManifestError.invalidField("timeoutMs must be greater than zero")
        }
    }
}

private extension TalkieToolManifest {
    static func decode(_ values: [String: TalkieYAML.Value]) throws -> TalkieToolManifest {
        for key in values.keys {
            switch key {
            case "id", "name", "enabled", "runtime", "entry", "input", "timeoutMs":
                continue
            default:
                throw TalkieContextManifestError.unknownField(key)
            }
        }

        let id = try values.requiredString("id")
        let name = try values.requiredString("name")
        let enabled = try values.optionalBool("enabled") ?? true
        let runtimeRaw = try values.requiredString("runtime")
        guard let runtime = Runtime(rawValue: runtimeRaw) else {
            throw TalkieContextManifestError.invalidField("Unknown runtime `\(runtimeRaw)`.")
        }

        let entry = try values.requiredString("entry")
        let input = try values.optionalString("input") ?? TalkieTool.schemaVersion
        let timeoutMs = try values.optionalInt("timeoutMs") ?? 10_000

        return TalkieToolManifest(
            id: id,
            name: name,
            enabled: enabled,
            runtime: runtime,
            entry: entry,
            input: input,
            timeoutMs: timeoutMs
        )
    }
}
