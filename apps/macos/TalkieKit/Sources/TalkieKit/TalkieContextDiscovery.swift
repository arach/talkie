import Foundation

public struct TalkieContextDiscovery {
    public struct Snapshot: Equatable, Sendable {
        public var items: [Item]
        public var problems: [Problem]

        public init(items: [Item] = [], problems: [Problem] = []) {
            self.items = items
            self.problems = problems
        }

        public func item(id: String, kind: Item.Kind) -> Item? {
            items.first(where: { $0.id == id && $0.kind == kind })
        }
    }

    public struct Item: Equatable, Sendable, Identifiable {
        public enum Kind: String, Codable, Sendable, CaseIterable {
            case rule
            case tool
            case workflow
            case automation

            fileprivate var directoryName: String {
                switch self {
                case .rule: "rules"
                case .tool: "tools"
                case .workflow: "workflows"
                case .automation: "automations"
                }
            }

            fileprivate var entryFilename: String {
                switch self {
                case .rule: "rule.yaml"
                case .tool: "tool.yaml"
                case .workflow: "workflow.json"
                case .automation: "automation.yaml"
                }
            }
        }

        public var id: String
        public var kind: Kind
        public var root: TalkieContextRoot
        public var directoryURL: URL
        public var entryURL: URL

        public init(
            id: String,
            kind: Kind,
            root: TalkieContextRoot,
            directoryURL: URL,
            entryURL: URL
        ) {
            self.id = id
            self.kind = kind
            self.root = root
            self.directoryURL = directoryURL.standardizedFileURL
            self.entryURL = entryURL.standardizedFileURL
        }
    }

    public struct Problem: Equatable, Sendable {
        public enum Severity: String, Codable, Sendable {
            case warning
            case error
        }

        public enum Reason: Equatable, Sendable {
            case missingEntry(expected: String)
            case duplicateItem(shadowedByRoot: URL)
        }

        public var severity: Severity
        public var kind: Item.Kind
        public var id: String
        public var directoryURL: URL
        public var reason: Reason

        public init(
            severity: Severity,
            kind: Item.Kind,
            id: String,
            directoryURL: URL,
            reason: Reason
        ) {
            self.severity = severity
            self.kind = kind
            self.id = id
            self.directoryURL = directoryURL.standardizedFileURL
            self.reason = reason
        }
    }

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func discover(in roots: [TalkieContextRoot]) -> Snapshot {
        let orderedRoots = roots
            .enumerated()
            .sorted { lhs, rhs in
                let leftPrecedence = lhs.element.kind.precedence
                let rightPrecedence = rhs.element.kind.precedence

                if leftPrecedence != rightPrecedence {
                    return leftPrecedence > rightPrecedence
                }

                return lhs.offset < rhs.offset
            }
            .map(\.element)

        var items: [Item] = []
        var problems: [Problem] = []
        var winners: [String: TalkieContextRoot] = [:]

        for root in orderedRoots {
            for kind in Item.Kind.allCases {
                let directoryURL = root.url.appending(path: kind.directoryName)
                guard isDirectory(directoryURL) else { continue }

                let childDirectories = (try? fileManager.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )) ?? []

                let sortedDirectories = childDirectories
                    .filter(isDirectory)
                    .sorted {
                        $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
                    }

                for itemDirectoryURL in sortedDirectories {
                    let itemID = itemDirectoryURL.lastPathComponent
                    let key = "\(kind.rawValue)::\(itemID)"
                    let entryURL = itemDirectoryURL.appending(path: kind.entryFilename)

                    guard fileManager.fileExists(atPath: entryURL.path(percentEncoded: false)) else {
                        problems.append(
                            Problem(
                                severity: .error,
                                kind: kind,
                                id: itemID,
                                directoryURL: itemDirectoryURL,
                                reason: .missingEntry(expected: kind.entryFilename)
                            )
                        )
                        continue
                    }

                    if let winningRoot = winners[key] {
                        problems.append(
                            Problem(
                                severity: .warning,
                                kind: kind,
                                id: itemID,
                                directoryURL: itemDirectoryURL,
                                reason: .duplicateItem(shadowedByRoot: winningRoot.url)
                            )
                        )
                        continue
                    }

                    winners[key] = root
                    items.append(
                        Item(
                            id: itemID,
                            kind: kind,
                            root: root,
                            directoryURL: itemDirectoryURL,
                            entryURL: entryURL
                        )
                    )
                }
            }
        }

        return Snapshot(items: items, problems: problems)
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }
}
