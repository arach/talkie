import Foundation

public enum TalkieContextManifestError: LocalizedError, Equatable, Sendable {
    case missingField(String)
    case unknownField(String)
    case invalidField(String)
    case unsupportedSchemaVersion(String)
    case idMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .missingField(let field):
            return "Missing required field `\(field)`."
        case .unknownField(let field):
            return "Unknown field `\(field)`."
        case .invalidField(let detail):
            return detail
        case .unsupportedSchemaVersion(let version):
            return "Unsupported schema version `\(version)`. Expected `\(TalkieTool.schemaVersion)`."
        case .idMismatch(let expected, let actual):
            return "Manifest id `\(actual)` does not match folder id `\(expected)`."
        }
    }
}
