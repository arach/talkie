import Foundation

public struct TalkieContextRoot: Equatable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case workspace
        case global
        case builtIn

        var precedence: Int {
            switch self {
            case .workspace: 3
            case .global: 2
            case .builtIn: 1
            }
        }
    }

    public var kind: Kind
    public var url: URL

    public init(kind: Kind, url: URL) {
        self.kind = kind
        self.url = url.standardizedFileURL
    }
}
