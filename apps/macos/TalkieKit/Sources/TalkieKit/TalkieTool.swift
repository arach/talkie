import Foundation

public enum TalkieTool {
    public static let schemaVersion = "talkie/v1"

    public struct Input: Codable, Equatable, Sendable {
        public var version: String
        public var event: String
        public var text: String
        public var vars: [String: String]
        public var context: Context

        public init(
            version: String = TalkieTool.schemaVersion,
            event: String,
            text: String,
            vars: [String: String] = [:],
            context: Context
        ) {
            self.version = version
            self.event = event
            self.text = text
            self.vars = vars
            self.context = context
        }
    }

    public struct Context: Codable, Equatable, Sendable {
        public var appName: String?
        public var bundleID: String?
        public var source: String?
        public var workspacePath: String?
        public var timestamp: String?

        public init(
            appName: String? = nil,
            bundleID: String? = nil,
            source: String? = nil,
            workspacePath: String? = nil,
            timestamp: String? = nil
        ) {
            self.appName = appName
            self.bundleID = bundleID
            self.source = source
            self.workspacePath = workspacePath
            self.timestamp = timestamp
        }
    }

    public struct Output: Codable, Equatable, Sendable {
        public var effects: [Effect]

        public init(effects: [Effect] = []) {
            self.effects = effects
        }
    }

    public struct Effect: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable, CaseIterable {
            case replaceText
            case insertText
            case runWorkflow
            case showSuggestion
            case notify
            case skip
        }

        public var type: Kind
        public var workflow: String?
        public var vars: [String: String]?
        public var text: String?
        public var title: String?
        public var message: String?

        public init(
            type: Kind,
            workflow: String? = nil,
            vars: [String: String]? = nil,
            text: String? = nil,
            title: String? = nil,
            message: String? = nil
        ) {
            self.type = type
            self.workflow = workflow
            self.vars = vars
            self.text = text
            self.title = title
            self.message = message
        }
    }
}
