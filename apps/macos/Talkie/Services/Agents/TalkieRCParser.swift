//
//  TalkieRCParser.swift
//  Talkie
//
//  Lightweight TOML-subset parser for .talkierc tab config files.
//  Supports: string values, multiline strings ("""), arrays, [section] tables,
//  comments (#), and the subset of TOML that .talkierc files use.
//

import Foundation

enum TalkieRCParser {

    enum ParseError: LocalizedError {
        case invalidSyntax(line: Int, detail: String)
        case missingRequiredField(String)
        case invalidHarness(String)

        var errorDescription: String? {
            switch self {
            case .invalidSyntax(let line, let detail):
                "Line \(line): \(detail)"
            case .missingRequiredField(let field):
                "Missing required field: \(field)"
            case .invalidHarness(let value):
                "Unknown harness: \(value)"
            }
        }
    }

    struct ParsedRC: Sendable {
        var values: [String: String] = [:]
        var sections: [String: [String: String]] = [:]
        var arrays: [String: [String]] = [:]
    }

    static func parse(_ content: String) throws -> ParsedRC {
        var result = ParsedRC()
        var currentSection: String?
        let lines = content.components(separatedBy: .newlines)
        var i = 0

        while i < lines.count {
            let rawLine = lines[i]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                i += 1
                continue
            }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                i += 1
                continue
            }

            guard let equalsIndex = trimmed.firstIndex(of: "=") else {
                i += 1
                continue
            }

            let key = trimmed[trimmed.startIndex..<equalsIndex].trimmingCharacters(in: .whitespaces)
            var rawValue = trimmed[trimmed.index(after: equalsIndex)...].trimmingCharacters(in: .whitespaces)

            let value: String
            if rawValue.hasPrefix("\"\"\"") {
                // Multiline string
                var multiline = String(rawValue.dropFirst(3))
                i += 1
                while i < lines.count {
                    let ml = lines[i]
                    if ml.trimmingCharacters(in: .whitespaces).hasSuffix("\"\"\"") {
                        let lastPart = ml.trimmingCharacters(in: .whitespaces)
                        multiline += "\n" + String(lastPart.dropLast(3))
                        break
                    }
                    multiline += "\n" + ml
                    i += 1
                }
                value = multiline.trimmingCharacters(in: .newlines)
            } else if rawValue.hasPrefix("\"") {
                value = unquote(rawValue)
            } else if rawValue.hasPrefix("[") {
                // Inline array
                let arrayContent = parseInlineArray(rawValue)
                if let section = currentSection {
                    let fullKey = "\(section).\(key)"
                    result.arrays[fullKey] = arrayContent
                } else {
                    result.arrays[key] = arrayContent
                }
                i += 1
                continue
            } else if rawValue == "true" {
                value = "true"
            } else if rawValue == "false" {
                value = "false"
            } else {
                value = rawValue.components(separatedBy: "#").first?
                    .trimmingCharacters(in: .whitespaces) ?? rawValue
            }

            if let section = currentSection {
                result.sections[section, default: [:]][key] = value
            } else {
                result.values[key] = value
            }

            i += 1
        }

        return result
    }

    static func parseTabDefinition(from content: String, sourceURL: URL? = nil) throws -> TabDefinition {
        let rc = try parse(content)

        guard let id = rc.values["id"] else {
            throw ParseError.missingRequiredField("id")
        }
        guard let label = rc.values["label"] else {
            throw ParseError.missingRequiredField("label")
        }
        guard let harnessRaw = rc.values["harness"] else {
            throw ParseError.missingRequiredField("harness")
        }
        guard let harness = TabHarness(rawValue: harnessRaw) else {
            throw ParseError.invalidHarness(harnessRaw)
        }

        let icon = rc.values["icon"] ?? TabHarnessIcon.symbolName(for: harness)
        let order = Int(rc.values["order"] ?? "50") ?? 50
        let model = rc.values["model"]
        let provider = rc.values["provider"]
        let systemPrompt = rc.values["system_prompt"] ?? ""
        let cwd = rc.values["cwd"] ?? "~/dev/talkie"
        let launchArgs = rc.arrays["launch_args"] ?? []
        let readOnly = rc.values["read_only"] == "true"
        let useTmux = rc.values["use_tmux"] == "true"

        var env: [String: String] = [:]
        if let envSection = rc.sections["env"] {
            env = envSection
        }

        var shellConfig: TabDefinition.ShellConfig?
        if let shellSection = rc.sections["shell"] {
            shellConfig = TabDefinition.ShellConfig(
                program: shellSection["program"] ?? "/bin/zsh",
                initScript: shellSection["init_script"]
            )
        }

        return TabDefinition(
            id: id,
            label: label,
            icon: icon,
            order: order,
            harness: harness,
            model: model,
            provider: provider,
            systemPrompt: systemPrompt,
            cwd: cwd,
            launchArgs: launchArgs,
            readOnly: readOnly,
            useTmux: useTmux,
            tmuxSessionName: rc.values["tmux_session_name"],
            env: env,
            shell: shellConfig,
            sourceURL: sourceURL
        )
    }

    static func parseGlobalRC(_ content: String) throws -> GlobalRCConfig {
        let rc = try parse(content)

        let tabsDir = rc.values["tabs_dir"]
        let secretsFiles = rc.arrays["secrets_files"] ?? []
        let globalEnv = rc.sections["env"] ?? [:]

        var defaultsByHarness: [String: [String: String]] = [:]
        for (key, section) in rc.sections where key.hasPrefix("defaults.") {
            let harness = String(key.dropFirst("defaults.".count))
            defaultsByHarness[harness] = section
        }

        return GlobalRCConfig(
            tabsDir: tabsDir,
            secretsFiles: secretsFiles,
            env: globalEnv,
            defaults: defaultsByHarness
        )
    }

    static func serialize(_ tab: TabDefinition) -> String {
        var lines: [String] = []
        lines.append("id = \"\(escape(tab.id))\"")
        lines.append("label = \"\(escape(tab.label))\"")
        lines.append("icon = \"\(escape(tab.icon))\"")
        lines.append("order = \(tab.order)")
        lines.append("")
        lines.append("harness = \"\(tab.harness.rawValue)\"")
        if let model = tab.model {
            lines.append("model = \"\(escape(model))\"")
        }
        if let provider = tab.provider {
            lines.append("provider = \"\(escape(provider))\"")
        }
        if !tab.systemPrompt.isEmpty {
            if tab.systemPrompt.contains("\n") {
                lines.append("system_prompt = \"\"\"")
                lines.append(tab.systemPrompt)
                lines.append("\"\"\"")
            } else {
                lines.append("system_prompt = \"\(escape(tab.systemPrompt))\"")
            }
        }
        lines.append("cwd = \"\(escape(tab.cwd))\"")
        if !tab.launchArgs.isEmpty {
            let argsStr = tab.launchArgs.map { "\"\(escape($0))\"" }.joined(separator: ", ")
            lines.append("launch_args = [\(argsStr)]")
        }
        if tab.readOnly {
            lines.append("read_only = true")
        }
        if tab.useTmux {
            lines.append("use_tmux = true")
        }
        if let tmuxName = tab.tmuxSessionName {
            lines.append("tmux_session_name = \"\(escape(tmuxName))\"")
        }

        if !tab.env.isEmpty {
            lines.append("")
            lines.append("[env]")
            for (key, value) in tab.env.sorted(by: { $0.key < $1.key }) {
                lines.append("\(key) = \"\(escape(value))\"")
            }
        }

        if let shell = tab.shell {
            lines.append("")
            lines.append("[shell]")
            lines.append("program = \"\(escape(shell.program))\"")
            if let initScript = shell.initScript {
                lines.append("init_script = \"\(escape(initScript))\"")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func unquote(_ raw: String) -> String {
        var s = raw
        if s.hasPrefix("\"") { s.removeFirst() }
        if s.hasSuffix("\"") { s.removeLast() }
        return s
    }

    private static func parseInlineArray(_ raw: String) -> [String] {
        var s = raw
        if s.hasPrefix("[") { s.removeFirst() }
        if s.hasSuffix("]") { s.removeLast() }
        return s.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { unquote($0) }
            .filter { !$0.isEmpty }
    }
}

struct GlobalRCConfig: Sendable {
    var tabsDir: String?
    var secretsFiles: [String]
    var env: [String: String]
    var defaults: [String: [String: String]]
}
