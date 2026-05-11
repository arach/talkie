import Foundation

public struct TalkieSelectionRuleResolver {
    public struct Context: Equatable, Sendable {
        public var text: String
        public var event: String
        public var source: String
        public var appName: String?
        public var bundleID: String?
        public var workspacePath: String?
        public var mode: SelectionMode?

        public init(
            text: String,
            event: String = "selection.readout",
            source: String = "selection",
            appName: String? = nil,
            bundleID: String? = nil,
            workspacePath: String? = nil,
            mode: SelectionMode? = nil
        ) {
            self.text = text
            self.event = event
            self.source = source
            self.appName = appName
            self.bundleID = bundleID
            self.workspacePath = workspacePath
            self.mode = mode
        }
    }

    public struct Plan: Equatable, Sendable {
        public var ruleID: String
        public var ruleName: String?
        public var workflowID: String
        public var mode: SelectionMode
        public var prompt: String?
        public var systemPrompt: String?
        public var profile: String?
        public var shouldPersist: Bool
        public var timeout: Duration

        public init(
            ruleID: String,
            ruleName: String? = nil,
            workflowID: String,
            mode: SelectionMode,
            prompt: String?,
            systemPrompt: String?,
            profile: String? = nil,
            shouldPersist: Bool = false,
            timeout: Duration = .seconds(6)
        ) {
            self.ruleID = ruleID
            self.ruleName = ruleName
            self.workflowID = workflowID
            self.mode = mode
            self.prompt = prompt
            self.systemPrompt = systemPrompt
            self.profile = profile
            self.shouldPersist = shouldPersist
            self.timeout = timeout
        }
    }

    public enum Error: LocalizedError, Equatable, Sendable {
        case missingWorkflow(String)
        case invalidWorkflow(String)
        case missingPromptFile(workflowID: String, filename: String)
        case missingProfile(workflowID: String, profile: String)

        public var errorDescription: String? {
            switch self {
            case .missingWorkflow(let workflowID):
                return "Workflow `\(workflowID)` was not found in context roots."
            case .invalidWorkflow(let workflowID):
                return "Workflow `\(workflowID)` is invalid."
            case .missingPromptFile(let workflowID, let filename):
                return "Workflow `\(workflowID)` is missing prompt file `\(filename)`."
            case .missingProfile(let workflowID, let profile):
                return "Workflow `\(workflowID)` is missing profile `\(profile)`."
            }
        }
    }

    private let catalog: TalkieContextCatalog
    private let discovery: TalkieContextDiscovery

    public init(
        catalog: TalkieContextCatalog = .init(),
        discovery: TalkieContextDiscovery = .init()
    ) {
        self.catalog = catalog
        self.discovery = discovery
    }

    public func resolve(
        context: Context,
        roots: [TalkieContextRoot]? = nil
    ) throws -> Plan? {
        let roots = roots ?? TalkieContextRoots.defaultRoots(workspacePath: context.workspacePath)
        let catalogSnapshot = catalog.load(in: roots)
        let discoverySnapshot = discovery.discover(in: roots)

        let candidates = catalogSnapshot.items.compactMap { item -> Candidate? in
            guard item.validationStatus == .valid,
                  case .rule(let manifest) = item.manifest,
                  manifest.enabled,
                  manifest.kind == .route,
                  matches(manifest.when, context: context),
                  let captures = match(manifest.match, input: context.text) else {
                return nil
            }

            return Candidate(
                discovery: item.discovery,
                manifest: manifest,
                captures: captures
            )
        }
        .sorted { lhs, rhs in
            if lhs.manifest.priority == rhs.manifest.priority {
                return lhs.discovery.root.kind.precedence > rhs.discovery.root.kind.precedence
            }
            return lhs.manifest.priority > rhs.manifest.priority
        }

        guard let candidate = candidates.first,
              let workflowID = candidate.manifest.produce.runWorkflow,
              !workflowID.isEmpty else {
            return nil
        }

        guard let workflowItem = discoverySnapshot.item(id: workflowID, kind: .workflow) else {
            throw Error.missingWorkflow(workflowID)
        }

        let workflow = try loadWorkflow(from: workflowItem.entryURL)
        guard workflow.id == workflowID else {
            throw Error.invalidWorkflow(workflowID)
        }

        let resolvedVars = resolveVars(candidate.manifest.produce.vars, captures: candidate.captures)
        let profile = resolvedVars["profile"] ?? workflow.defaultProfile
        let systemPrompt = try buildSystemPrompt(
            workflow: workflow,
            workflowDirectoryURL: workflowItem.directoryURL,
            profile: profile
        )
        let prompt = buildPrompt(systemPrompt: systemPrompt, text: context.text, mode: workflow.mode)
        let shouldPersist = parseBoolean(resolvedVars["persist"]) ?? false
        let timeout = Duration.milliseconds(workflow.timeoutMs)

        return Plan(
            ruleID: candidate.manifest.id,
            ruleName: candidate.manifest.name,
            workflowID: workflow.id,
            mode: workflow.mode,
            prompt: prompt,
            systemPrompt: systemPrompt,
            profile: profile,
            shouldPersist: shouldPersist,
            timeout: timeout
        )
    }
}

private extension TalkieSelectionRuleResolver {
    struct Candidate {
        var discovery: TalkieContextDiscovery.Item
        var manifest: TalkieRuleManifest
        var captures: [String]
    }

    struct WorkflowManifest: Decodable {
        var id: String
        var mode: SelectionMode
        var systemPromptFile: String
        var defaultProfile: String?
        var timeoutMs: Int
    }

    func matches(_ when: TalkieRuleManifest.When, context: Context) -> Bool {
        if let event = when.event, event != context.event {
            return false
        }

        if !when.apps.isEmpty {
            guard let appName = context.appName,
                  when.apps.contains(where: { $0.localizedCaseInsensitiveCompare(appName) == .orderedSame }) else {
                return false
            }
        }

        if !when.bundleIDs.isEmpty {
            guard let bundleID = context.bundleID, when.bundleIDs.contains(bundleID) else {
                return false
            }
        }

        if !when.sources.isEmpty {
            guard when.sources.contains(where: { $0.localizedCaseInsensitiveCompare(context.source) == .orderedSame }) else {
                return false
            }
        }

        if !when.workspacePaths.isEmpty {
            guard let workspacePath = context.workspacePath else {
                return false
            }

            let normalizedWorkspace = URL(fileURLWithPath: workspacePath).standardizedFileURL.path(percentEncoded: false)
            let matchesWorkspace = when.workspacePaths.contains { rawPath in
                URL(fileURLWithPath: rawPath).standardizedFileURL.path(percentEncoded: false) == normalizedWorkspace
            }

            if !matchesWorkspace {
                return false
            }
        }

        if !when.projects.isEmpty {
            guard let workspacePath = context.workspacePath else {
                return false
            }

            let projectName = URL(fileURLWithPath: workspacePath).lastPathComponent
            guard when.projects.contains(where: { $0.localizedCaseInsensitiveCompare(projectName) == .orderedSame }) else {
                return false
            }
        }

        if !when.modes.isEmpty {
            guard let mode = context.mode?.rawValue,
                  when.modes.contains(where: { $0.localizedCaseInsensitiveCompare(mode) == .orderedSame }) else {
                return false
            }
        }

        return true
    }

    func match(_ match: TalkieRuleManifest.Match, input: String) -> [String]? {
        switch match.type {
        case .exact:
            guard match.text == input else { return nil }
            return []
        case .contains:
            guard let text = match.text, input.localizedStandardContains(text) else { return nil }
            return []
        case .prefix:
            guard let text = match.text, input.hasPrefix(text) else { return nil }
            return []
        case .regex:
            guard let pattern = match.pattern else { return nil }
            let regex = try? NSRegularExpression(pattern: pattern)
            guard let regex,
                  let result = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) else {
                return nil
            }

            guard result.range.location != NSNotFound else { return nil }

            var captures: [String] = []
            if result.numberOfRanges > 1 {
                for rangeIndex in 1..<result.numberOfRanges {
                    let range = result.range(at: rangeIndex)
                    guard let stringRange = Range(range, in: input) else {
                        captures.append("")
                        continue
                    }
                    captures.append(String(input[stringRange]))
                }
            }
            return captures
        }
    }

    func resolveVars(_ vars: [String: String], captures: [String]) -> [String: String] {
        vars.mapValues { value in
            captures.enumerated().reduce(value) { partial, capture in
                partial.replacing("$\(capture.offset + 1)", with: capture.element)
            }
        }
    }

    func parseBoolean(_ rawValue: String?) -> Bool? {
        guard let rawValue else { return nil }
        switch rawValue.lowercased() {
        case "true", "1", "yes", "on":
            return true
        case "false", "0", "no", "off":
            return false
        default:
            return nil
        }
    }

    func loadWorkflow(from fileURL: URL) throws -> WorkflowManifest {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(WorkflowManifest.self, from: data)
    }

    func buildSystemPrompt(
        workflow: WorkflowManifest,
        workflowDirectoryURL: URL,
        profile: String?
    ) throws -> String? {
        let systemPromptURL = workflowDirectoryURL.appending(path: workflow.systemPromptFile)
        guard FileManager.default.fileExists(atPath: systemPromptURL.path(percentEncoded: false)) else {
            throw Error.missingPromptFile(workflowID: workflow.id, filename: workflow.systemPromptFile)
        }

        var promptComponents: [String] = [
            try String(contentsOf: systemPromptURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        ]

        if let profile, !profile.isEmpty {
            let profileURL = workflowDirectoryURL
                .appending(path: "profiles", directoryHint: .isDirectory)
                .appending(path: "\(profile).md")
            guard FileManager.default.fileExists(atPath: profileURL.path(percentEncoded: false)) else {
                throw Error.missingProfile(workflowID: workflow.id, profile: profile)
            }

            let profilePrompt = try String(contentsOf: profileURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !profilePrompt.isEmpty {
                promptComponents.append(profilePrompt)
            }
        }

        let mergedPrompt = promptComponents
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return mergedPrompt.isEmpty ? nil : mergedPrompt
    }

    func buildPrompt(systemPrompt: String?, text: String, mode: SelectionMode) -> String? {
        guard mode != .verbatim else { return nil }
        guard let systemPrompt, !systemPrompt.isEmpty else { return nil }

        return """
        \(systemPrompt)

        Selected text:
        \(text)
        """
    }
}
