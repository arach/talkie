import Foundation

public struct TalkieContextCatalog {
    public struct Snapshot: Equatable, Sendable {
        public var items: [Item]
        public var problems: [Problem]

        public init(items: [Item] = [], problems: [Problem] = []) {
            self.items = items
            self.problems = problems
        }

        public var summary: Summary {
            Summary(items: items, problems: problems)
        }
    }

    public struct Item: Equatable, Sendable, Identifiable {
        public enum Manifest: Equatable, Sendable {
            case rule(TalkieRuleManifest)
            case tool(TalkieToolManifest)
        }

        public enum ValidationStatus: String, Equatable, Sendable {
            case valid
            case invalid
            case unvalidated
        }

        public var discovery: TalkieContextDiscovery.Item
        public var manifest: Manifest?
        public var validationStatus: ValidationStatus

        public var id: String {
            "\(discovery.kind.rawValue)::\(discovery.id)"
        }

        public var displayName: String {
            switch manifest {
            case .rule(let rule):
                return rule.name ?? rule.id
            case .tool(let tool):
                return tool.name
            case nil:
                return discovery.id
            }
        }

        public init(
            discovery: TalkieContextDiscovery.Item,
            manifest: Manifest? = nil,
            validationStatus: ValidationStatus
        ) {
            self.discovery = discovery
            self.manifest = manifest
            self.validationStatus = validationStatus
        }
    }

    public struct Problem: Equatable, Sendable {
        public var severity: TalkieContextDiscovery.Problem.Severity
        public var kind: TalkieContextDiscovery.Item.Kind
        public var id: String
        public var entryURL: URL
        public var message: String

        public init(
            severity: TalkieContextDiscovery.Problem.Severity,
            kind: TalkieContextDiscovery.Item.Kind,
            id: String,
            entryURL: URL,
            message: String
        ) {
            self.severity = severity
            self.kind = kind
            self.id = id
            self.entryURL = entryURL.standardizedFileURL
            self.message = message
        }
    }

    public struct Summary: Equatable, Sendable {
        public var totalItems: Int
        public var validItems: Int
        public var invalidItems: Int
        public var unvalidatedItems: Int
        public var warningCount: Int
        public var errorCount: Int

        init(items: [Item], problems: [Problem]) {
            totalItems = items.count
            validItems = items.filter { $0.validationStatus == .valid }.count
            invalidItems = items.filter { $0.validationStatus == .invalid }.count
            unvalidatedItems = items.filter { $0.validationStatus == .unvalidated }.count
            warningCount = problems.filter { $0.severity == .warning }.count
            errorCount = problems.filter { $0.severity == .error }.count
        }
    }

    private let discovery: TalkieContextDiscovery

    public init(discovery: TalkieContextDiscovery = .init()) {
        self.discovery = discovery
    }

    public func load(in roots: [TalkieContextRoot]) -> Snapshot {
        let discoverySnapshot = discovery.discover(in: roots)
        var items: [Item] = []
        var problems = discoverySnapshot.problems.map { problem in
            Problem(
                severity: problem.severity,
                kind: problem.kind,
                id: problem.id,
                entryURL: problem.directoryURL,
                message: message(for: problem.reason)
            )
        }

        for discoveredItem in discoverySnapshot.items {
            switch discoveredItem.kind {
            case .rule:
                do {
                    let manifest = try TalkieRuleManifest.load(from: discoveredItem.entryURL)
                    try manifest.validate(expectedID: discoveredItem.id)
                    items.append(
                        Item(
                            discovery: discoveredItem,
                            manifest: .rule(manifest),
                            validationStatus: .valid
                        )
                    )
                } catch {
                    items.append(
                        Item(
                            discovery: discoveredItem,
                            validationStatus: .invalid
                        )
                    )
                    problems.append(
                        Problem(
                            severity: .error,
                            kind: discoveredItem.kind,
                            id: discoveredItem.id,
                            entryURL: discoveredItem.entryURL,
                            message: error.localizedDescription
                        )
                    )
                }
            case .tool:
                do {
                    let manifest = try TalkieToolManifest.load(from: discoveredItem.entryURL)
                    try manifest.validate(expectedID: discoveredItem.id)
                    items.append(
                        Item(
                            discovery: discoveredItem,
                            manifest: .tool(manifest),
                            validationStatus: .valid
                        )
                    )
                } catch {
                    items.append(
                        Item(
                            discovery: discoveredItem,
                            validationStatus: .invalid
                        )
                    )
                    problems.append(
                        Problem(
                            severity: .error,
                            kind: discoveredItem.kind,
                            id: discoveredItem.id,
                            entryURL: discoveredItem.entryURL,
                            message: error.localizedDescription
                        )
                    )
                }
            case .workflow, .automation:
                items.append(
                    Item(
                        discovery: discoveredItem,
                        validationStatus: .unvalidated
                    )
                )
            }
        }

        return Snapshot(items: items, problems: problems)
    }

    private func message(for reason: TalkieContextDiscovery.Problem.Reason) -> String {
        switch reason {
        case .missingEntry(let expected):
            return "Missing required entry file `\(expected)`."
        case .duplicateItem(let shadowedByRoot):
            return "Shadowed by higher-priority root at `\(shadowedByRoot.path(percentEncoded: false))`."
        }
    }
}
