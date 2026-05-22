//
//  SkillFileFormat.swift
//  Talkie macOS
//
//  Parser/serializer for Talkie .skill.md files.
//

import Foundation

// MARK: - Public entry points used by wiring/tests

func parseSkillFile(_ markdown: String) throws -> WorkflowDefinition {
    try SkillFileFormat.parseSkillFile(markdown)
}

func serializeSkill(_ definition: WorkflowDefinition) -> String {
    SkillFileFormat.serializeSkill(definition)
}

// MARK: - Errors

enum SkillFileFormatError: LocalizedError, Equatable {
    case missingFrontmatter
    case unterminatedFrontmatter
    case invalidBodyLine(String)

    var errorDescription: String? {
        switch self {
        case .missingFrontmatter:
            return ".skill.md files must start with YAML frontmatter delimited by --- lines."
        case .unterminatedFrontmatter:
            return ".skill.md frontmatter must close with a second --- line."
        case .invalidBodyLine(let line):
            return "Could not parse skill body line: \(line)"
        }
    }
}

// MARK: - Format

enum SkillFileFormat {
    static let slackWebhookUserDefaultsKey = "SkillsSlackWebhookURL"
    static let slackWebhookURLPlaceholder = "{{USERDEFAULTS:\(slackWebhookUserDefaultsKey)}}"

    static func parseSkillFile(_ markdown: String) throws -> WorkflowDefinition {
        let parsed = try splitFrontmatter(markdown)
        let metadata = parseFrontmatter(parsed.frontmatter)
        let steps = try parseBody(parsed.body)
        let now = Date()

        return WorkflowDefinition(
            id: metadata.id,
            name: metadata.name,
            description: metadata.description,
            icon: metadata.icon,
            color: metadata.color,
            maintainer: metadata.maintainer,
            steps: steps,
            isEnabled: metadata.isEnabled,
            isPinned: metadata.isPinned,
            autoRun: metadata.autoRun,
            autoRunOrder: metadata.autoRunOrder,
            source: .user,
            createdAt: now,
            modifiedAt: now
        )
    }

    static func serializeSkill(_ definition: WorkflowDefinition) -> String {
        var lines: [String] = [
            "---",
            "id: \(definition.id.uuidString)",
            "name: \(definition.name)",
            "description: \(definition.description)",
            "icon: \(definition.icon)",
            "color: \(definition.color.rawValue)",
            "isEnabled: \(definition.isEnabled ? "true" : "false")"
        ]

        if definition.isPinned {
            lines.append("isPinned: true")
        }
        if definition.autoRun {
            lines.append("autoRun: true")
            lines.append("autoRunOrder: \(definition.autoRunOrder)")
        }
        if let maintainer = definition.maintainer, !maintainer.isEmpty {
            lines.append("maintainer: \(maintainer)")
        }

        lines.append("---")

        let body = serializeBody(definition.steps)
        if !body.isEmpty {
            lines.append("")
            lines.append(contentsOf: body)
        }

        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - Frontmatter

private extension SkillFileFormat {
    struct SkillMetadata {
        var id: UUID
        var name: String
        var description: String
        var icon: String
        var color: WorkflowColor
        var maintainer: String?
        var isEnabled: Bool
        var isPinned: Bool
        var autoRun: Bool
        var autoRunOrder: Int
    }

    static func splitFrontmatter(_ markdown: String) throws -> (frontmatter: String, body: String) {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            throw SkillFileFormatError.missingFrontmatter
        }

        guard let endIndex = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            throw SkillFileFormatError.unterminatedFrontmatter
        }

        let frontmatter = lines[1..<endIndex].joined(separator: "\n")
        let bodyStart = lines.index(after: endIndex)
        let body = bodyStart < lines.endIndex
            ? lines[bodyStart..<lines.endIndex].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        return (frontmatter, body)
    }

    static func parseFrontmatter(_ frontmatter: String) -> SkillMetadata {
        let values = frontmatter
            .components(separatedBy: .newlines)
            .reduce(into: [String: String]()) { result, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let colon = trimmed.firstIndex(of: ":") else { return }
                let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                result[key] = unquote(value)
            }

        let idValue = values["id"] ?? values["slug"] ?? values["name"] ?? "skill"
        let id = UUID(uuidString: idValue) ?? stableUUID(from: idValue)

        return SkillMetadata(
            id: id,
            name: values["name"] ?? "Untitled Skill",
            description: values["description"] ?? "",
            icon: values["icon"] ?? "wand.and.stars",
            color: values["color"].flatMap(WorkflowColor.init(rawValue:)) ?? .blue,
            maintainer: values["maintainer"],
            isEnabled: bool(values["isEnabled"], default: true),
            isPinned: bool(values["isPinned"], default: false),
            autoRun: bool(values["autoRun"], default: false),
            autoRunOrder: values["autoRunOrder"].flatMap(Int.init) ?? 0
        )
    }

    static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    static func bool(_ value: String?, default defaultValue: Bool) -> Bool {
        guard let value = value?.lowercased() else { return defaultValue }
        switch value {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return defaultValue
        }
    }

    static func stableUUID(from value: String) -> UUID {
        let hash = fnv1a64(value)
        return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012llX", hash & 0x0000_FFFF_FFFF_FFFF)) ?? UUID()
    }

    static func fnv1a64(_ value: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }
}

// MARK: - Body parser

private extension SkillFileFormat {
    struct BodySection {
        enum Keyword: String {
            case when = "WHEN"
            case with = "WITH"
            case `do` = "DO"
            case then = "THEN"
        }

        var keyword: Keyword
        var tail: String
        var fields: [BodyField] = []
    }

    struct BodyField: Equatable {
        var key: String?
        var value: String
    }

    static func parseBody(_ body: String) throws -> [WorkflowStep] {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let sections = try parseSections(body)
        var steps: [WorkflowStep] = []

        for section in sections {
            switch section.keyword {
            case .when:
                steps.append(contentsOf: makeTriggerSteps(from: section))
            case .with:
                steps.append(contentsOf: makeInputSteps(from: section))
            case .do:
                steps.append(contentsOf: makeActionSteps(from: section))
            case .then:
                steps.append(contentsOf: makeConfirmationSteps(from: section))
            }
        }

        return steps
    }

    static func parseSections(_ body: String) throws -> [BodySection] {
        var sections: [BodySection] = []
        var current: BodySection?

        for rawLine in body.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if let parsed = parseHeaderLine(trimmed) {
                if let current {
                    sections.append(current)
                }
                current = parsed
            } else if trimmed.hasPrefix("↳") {
                guard var open = current else {
                    throw SkillFileFormatError.invalidBodyLine(rawLine)
                }
                open.fields.append(parseField(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
                current = open
            } else {
                throw SkillFileFormatError.invalidBodyLine(rawLine)
            }
        }

        if let current {
            sections.append(current)
        }

        return sections
    }

    static func parseHeaderLine(_ line: String) -> BodySection? {
        for keyword in [BodySection.Keyword.when, .with, .do, .then] {
            if line == keyword.rawValue {
                return BodySection(keyword: keyword, tail: "")
            }
            if line.hasPrefix(keyword.rawValue + " ") || line.hasPrefix(keyword.rawValue + "\t") {
                return BodySection(
                    keyword: keyword,
                    tail: String(line.dropFirst(keyword.rawValue.count)).trimmingCharacters(in: .whitespaces)
                )
            }
        }
        return nil
    }

    static func parseField(_ value: String) -> BodyField {
        guard let colon = value.firstIndex(of: ":") else {
            return BodyField(key: nil, value: value)
        }
        let key = String(value[..<colon]).trimmingCharacters(in: .whitespaces)
        let fieldValue = String(value[value.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        return BodyField(key: key, value: fieldValue)
    }

    static func makeTriggerSteps(from section: BodySection) -> [WorkflowStep] {
        let tail = section.tail.lowercased()
        if tail.hasPrefix("manual") || tail.isEmpty {
            return []
        }

        if tail.hasPrefix("voice") {
            let phrase = quotedValue(in: section.tail) ?? section.tail.dropPrefix("voice").trimmingCharacters(in: .whitespaces)
            return [
                WorkflowStep(
                    type: .trigger,
                    config: .trigger(TriggerStepConfig(
                        phrases: phrase.isEmpty ? [] : [phrase],
                        caseSensitive: false,
                        searchLocation: .anywhere,
                        contextWindowSize: 200,
                        stopIfNoMatch: true
                    )),
                    outputKey: "trigger"
                )
            ]
        }

        // Phase 1 has only keyword-style triggers in WorkflowDefinition.
        // Schedule-specific semantics can be layered onto Automation later.
        return [
            WorkflowStep(
                type: .trigger,
                config: .trigger(TriggerStepConfig(
                    phrases: [section.tail],
                    caseSensitive: false,
                    searchLocation: .anywhere,
                    contextWindowSize: 200,
                    stopIfNoMatch: true
                )),
                outputKey: "trigger"
            )
        ]
    }

    static func makeInputSteps(from section: BodySection) -> [WorkflowStep] {
        let tags = commaSeparatedTags(section.tail)
        return tags.enumerated().map { index, tag in
            let lowered = tag.lowercased()
            if lowered.contains("dictation") || lowered.contains("transcript") || lowered.contains("audio") {
                return WorkflowStep(
                    type: .transcribe,
                    config: .transcribe(TranscribeStepConfig(overwriteExisting: false, saveAsVersion: true)),
                    outputKey: index == 0 ? "dictation" : "dictation_\(index + 1)"
                )
            }

            // Capture/selection inputs do not have a dedicated step type yet.
            // Represent them as a pass-through transform so the definition stays executable.
            return WorkflowStep(
                type: .transform,
                config: .transform(TransformStepConfig(
                    operation: .template,
                    parameters: [
                        "template": "{{PREVIOUS_OUTPUT}}",
                        "todo": "Input capture not wired yet: \(tag)"
                    ]
                )),
                outputKey: sanitizedOutputKey(tag, fallback: "input_\(index + 1)")
            )
        }
    }

    static func makeActionSteps(from section: BodySection) -> [WorkflowStep] {
        let action = section.tail.trimmingCharacters(in: .whitespaces)
        guard !action.isEmpty else { return [] }

        if action == "sequence" {
            return [WorkflowStep(type: .executeWorkflows, config: .executeWorkflows(ExecuteWorkflowsStepConfig()), outputKey: "sequence")]
        }

        if action.hasPrefix("route") {
            return [
                WorkflowStep(type: .intentExtract, config: .intentExtract(IntentExtractStepConfig(inputKey: "{{PREVIOUS_OUTPUT}}")), outputKey: "intents"),
                WorkflowStep(type: .executeWorkflows, config: .executeWorkflows(ExecuteWorkflowsStepConfig(intentsKey: "{{intents}}")), outputKey: "route")
            ]
        }

        var steps: [WorkflowStep] = []
        let fieldMap = dictionary(from: section.fields)
        if hasClaudeTighten(section.fields) && action != "claude.tighten" {
            steps.append(claudeTightenStep())
        }

        switch action {
        case "github.issue":
            steps.append(gitHubIssueStep(fieldMap: fieldMap))
        case "slack.post":
            steps.append(slackPostStep(fieldMap: fieldMap))
        case "library.note":
            steps.append(libraryNoteStep(fieldMap: fieldMap))
        case "claude.tighten":
            steps.append(claudeTightenStep())
        default:
            steps.append(fallbackLLMStep(action: action, fields: section.fields))
        }

        return steps
    }

    static func makeConfirmationSteps(from section: BodySection) -> [WorkflowStep] {
        let tail = section.tail.lowercased()
        let fieldMap = dictionary(from: section.fields)
        if tail.contains("voice") || tail.contains("speak") || tail.contains("ack") {
            let text = fieldMap["text"] ?? fieldMap["message"] ?? "Done."
            return [WorkflowStep(type: .speak, config: .speak(SpeakStepConfig(text: text, provider: .system)), outputKey: "ack")]
        }

        if tail.contains("clipboard") {
            return [WorkflowStep(type: .clipboard, config: .clipboard(ClipboardStepConfig(content: "{{PREVIOUS_OUTPUT}}")), outputKey: "clipboard")]
        }

        return [
            WorkflowStep(
                type: .notification,
                config: .notification(NotificationStepConfig(
                    title: fieldMap["title"] ?? "Skill complete",
                    body: fieldMap["body"] ?? "{{PREVIOUS_OUTPUT}}"
                )),
                outputKey: "notification"
            )
        ]
    }

    static func commaSeparatedTags(_ tail: String) -> [String] {
        tail.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func dictionary(from fields: [BodyField]) -> [String: String] {
        fields.reduce(into: [:]) { result, field in
            if let key = field.key?.lowercased() {
                result[key] = field.value
            }
        }
    }

    static func hasClaudeTighten(_ fields: [BodyField]) -> Bool {
        fields.contains { field in
            let key = field.key?.lowercased()
            let value = field.value.lowercased()
            return (key == "polish" && value == "claude.tighten") || value == "claude.tighten"
        }
    }

    static func quotedValue(in value: String) -> String? {
        guard let start = value.firstIndex(of: "\"") else { return nil }
        let afterStart = value.index(after: start)
        guard let end = value[afterStart...].firstIndex(of: "\"") else { return nil }
        return String(value[afterStart..<end])
    }

    static func sanitizedOutputKey(_ value: String, fallback: String) -> String {
        let allowed = value.lowercased().map { char -> Character in
            if char.isLetter || char.isNumber { return char }
            return "_"
        }
        let key = String(allowed)
            .split(separator: "_")
            .joined(separator: "_")
        return key.isEmpty ? fallback : key
    }
}

// MARK: - Step builders

private extension SkillFileFormat {
    static func claudeTightenStep() -> WorkflowStep {
        WorkflowStep(
            type: .llm,
            config: .llm(LLMStepConfig(
                provider: .anthropic,
                costTier: .balanced,
                prompt: """
                Tighten this standup update into three crisp bullets. Preserve concrete details, remove filler, and keep the tone direct.

                Input:
                {{PREVIOUS_OUTPUT}}
                """,
                systemPrompt: "You polish short team updates for clarity.",
                temperature: 0.3,
                maxTokens: 600
            )),
            outputKey: "polished"
        )
    }

    static func slackPostStep(fieldMap: [String: String]) -> WorkflowStep {
        let channel = fieldMap["channel"] ?? "#standup"
        return WorkflowStep(
            type: .webhook,
            config: .webhook(WebhookStepConfig(
                url: slackWebhookURLPlaceholder,
                method: .post,
                bodyTemplate: "{\"channel\":\"\(jsonEscaped(channel))\",\"text\":{{PREVIOUS_OUTPUT_JSON}}}",
                includeTranscript: false,
                includeMetadata: false
            )),
            outputKey: "slack_response"
        )
    }

    static func gitHubIssueStep(fieldMap: [String: String]) -> WorkflowStep {
        // TODO: Replace placeholder URL/auth with real GitHub credential wiring.
        let title = fieldMap["title"] ?? "Talkie skill issue"
        return WorkflowStep(
            type: .webhook,
            config: .webhook(WebhookStepConfig(
                url: "https://api.github.com/repos/OWNER/REPO/issues",
                method: .post,
                bodyTemplate: "{\"title\":\"\(jsonEscaped(title))\",\"body\":{{PREVIOUS_OUTPUT_JSON}}}",
                includeTranscript: false,
                includeMetadata: false
            )),
            outputKey: "github_issue"
        )
    }

    static func libraryNoteStep(fieldMap: [String: String]) -> WorkflowStep {
        // TODO: SaveFile is a placeholder until Library notes get first-class filing.
        WorkflowStep(
            type: .saveFile,
            config: .saveFile(SaveFileStepConfig(
                filename: fieldMap["filename"] ?? "{{DATE}}-{{TITLE}}.md",
                directory: fieldMap["directory"] ?? defaultLibraryNotesDirectory,
                content: "{{PREVIOUS_OUTPUT}}"
            )),
            outputKey: "library_note"
        )
    }

    static var defaultLibraryNotesDirectory: String {
        URL.applicationSupportDirectory
            .appending(path: "Talkie", directoryHint: .isDirectory)
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "notes", directoryHint: .isDirectory)
            .path
    }

    static func fallbackLLMStep(action: String, fields: [BodyField]) -> WorkflowStep {
        let fieldText = fields.map { field in
            if let key = field.key {
                return "- \(key): \(field.value)"
            }
            return "- \(field.value)"
        }.joined(separator: "\n")

        return WorkflowStep(
            type: .llm,
            config: .llm(LLMStepConfig(
                prompt: """
                Perform the requested skill action: \(action)

                Fields:
                \(fieldText.isEmpty ? "- none" : fieldText)

                Input:
                {{PREVIOUS_OUTPUT}}
                """,
                temperature: 0.4,
                maxTokens: 1024
            )),
            outputKey: sanitizedOutputKey(action, fallback: "action_output")
        )
    }

    static func jsonEscaped(_ value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        guard let encoded = data.flatMap({ String(data: $0, encoding: .utf8) }) else { return value }
        return String(encoded.dropFirst().dropLast())
    }
}

// MARK: - Serializer body

private extension SkillFileFormat {
    static func serializeBody(_ steps: [WorkflowStep]) -> [String] {
        guard !steps.isEmpty else { return [] }

        var lines: [String] = []
        var index = 0

        if let first = steps.first, case .trigger(let config) = first.config {
            let phrase = config.phrases.first ?? ""
            lines.append("WHEN voice \"\(phrase)\"")
            index = 1
        } else {
            lines.append("WHEN manual")
        }

        while index < steps.count {
            let step = steps[index]
            switch step.config {
            case .transcribe:
                appendBlankIfNeeded(&lines)
                lines.append("WITH dictation")
                index += 1
            case .transform:
                appendBlankIfNeeded(&lines)
                lines.append("WITH transform")
                index += 1
            default:
                break
            }

            if index < steps.count, !isInputStep(steps[index]) {
                break
            }
        }

        if index < steps.count {
            appendBlankIfNeeded(&lines)
            let consumed = appendActionLines(from: steps, startIndex: index, to: &lines)
            index += consumed
        }

        if let finalStep = steps.last, isConfirmationStep(finalStep) {
            appendBlankIfNeeded(&lines)
            appendConfirmationLine(finalStep, to: &lines)
        }

        return lines
    }

    static func appendActionLines(from steps: [WorkflowStep], startIndex: Int, to lines: inout [String]) -> Int {
        let step = steps[startIndex]
        let next = steps.indices.contains(startIndex + 1) ? steps[startIndex + 1] : nil

        if isClaudeTightenStep(step), let next, case .webhook(let config) = next.config, isSlackWebhook(config) {
            lines.append("DO slack.post")
            lines.append("      ↳ channel: \(slackChannel(from: config) ?? "#standup")")
            lines.append("      ↳ polish: claude.tighten")
            return 2
        }

        switch step.config {
        case .webhook(let config) where isSlackWebhook(config):
            lines.append("DO slack.post")
            lines.append("      ↳ channel: \(slackChannel(from: config) ?? "#standup")")
            return 1
        case .webhook(let config) where config.url.contains("api.github.com"):
            lines.append("DO github.issue")
            return 1
        case .saveFile:
            lines.append("DO library.note")
            return 1
        case .llm where isClaudeTightenStep(step):
            lines.append("DO claude.tighten")
            return 1
        case .executeWorkflows:
            lines.append("DO sequence")
            return 1
        default:
            lines.append("DO \(step.type.rawValue)")
            return 1
        }
    }

    static func appendConfirmationLine(_ step: WorkflowStep, to lines: inout [String]) {
        switch step.config {
        case .speak:
            lines.append("THEN voice ack")
        case .clipboard:
            lines.append("THEN clipboard")
        case .notification:
            lines.append("THEN notification")
        default:
            break
        }
    }

    static func appendBlankIfNeeded(_ lines: inout [String]) {
        if lines.last?.isEmpty == false {
            lines.append("")
        }
    }

    static func isInputStep(_ step: WorkflowStep) -> Bool {
        switch step.config {
        case .transcribe, .transform:
            return true
        default:
            return false
        }
    }

    static func isConfirmationStep(_ step: WorkflowStep) -> Bool {
        switch step.config {
        case .speak, .clipboard, .notification:
            return true
        default:
            return false
        }
    }

    static func isClaudeTightenStep(_ step: WorkflowStep) -> Bool {
        guard case .llm(let config) = step.config else { return false }
        return config.provider == .anthropic && config.prompt.localizedCaseInsensitiveContains("tighten")
    }

    static func isSlackWebhook(_ config: WebhookStepConfig) -> Bool {
        config.url.contains(slackWebhookUserDefaultsKey) || config.bodyTemplate?.localizedCaseInsensitiveContains("channel") == true
    }

    static func slackChannel(from config: WebhookStepConfig) -> String? {
        guard let template = config.bodyTemplate,
              let range = template.range(of: #"\"channel\"\s*:\s*\"([^\"]+)\""#, options: .regularExpression) else {
            return nil
        }
        let match = String(template[range])
        guard let colon = match.firstIndex(of: ":") else { return nil }
        return match[match.index(after: colon)...]
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\""))
    }
}

private extension String {
    func dropPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
