//
//  TabPresets.swift
//  Talkie
//
//  Bundled starter tab definitions seeded on first launch.
//

import Foundation

enum TabPresets {
    static let legacyClaudeAuthBridgeEnv: [String: String] = [
        "ANTHROPIC_API_KEY": "${env:ANTHROPIC_API_KEY}",
    ]

    /// Tab presets are now created on demand from the starter picker —
    /// the registry no longer seeds Claude/Pi/Shell as bare tabs on
    /// first launch. The static templates below stay as the source of
    /// truth that the picker clones from (preserving harness/model/cwd
    /// defaults), but a fresh user starts with an empty tab list.
    static let bundled: [TabDefinition] = []

    /// Templates exposed to the picker. Each entry's id is treated as
    /// a *family* name; clones get a unique id with a numeric suffix.
    static let templates: [TabDefinition] = [claude, pi, talkieShell, bridgeLogs]

    static let claude = TabDefinition(
        id: "claude",
        label: "Claude",
        icon: "sparkles",
        order: 10,
        harness: .claudeCode,
        model: "claude-sonnet-4-6",
        systemPrompt: mergedClaudeSystemPrompt,
        cwd: "~/dev/talkie",
        launchArgs: [],
        readOnly: false,
        useTmux: false,
        tmuxSessionName: nil,
        // Claude should behave like a normal terminal session and reuse the
        // existing CLI auth state on disk instead of forcing API-key mode.
        env: [:],
        shell: nil,
        sourceURL: nil
    )

    static let pi = TabDefinition(
        id: "pi",
        label: "Pi",
        icon: "circle.grid.cross",
        order: 20,
        harness: .pi,
        model: nil,
        systemPrompt: "",
        cwd: "~/dev/talkie",
        launchArgs: [],
        readOnly: false,
        useTmux: false,
        tmuxSessionName: nil,
        env: [:],
        shell: nil,
        sourceURL: nil
    )

    static let talkieShell = TabDefinition(
        id: "talkie-shell",
        label: "Talkie Shell",
        icon: "apple.terminal",
        order: 30,
        harness: .shell,
        model: nil,
        systemPrompt: "",
        cwd: "~/dev/talkie",
        launchArgs: [],
        readOnly: false,
        useTmux: false,
        tmuxSessionName: nil,
        env: [
            "TALKIE_WORKSPACE": "~/dev/talkie",
        ],
        shell: TabDefinition.ShellConfig(
            program: "/bin/zsh",
            initScript: "~/.talkie/tabs/talkie-shell.init.zsh"
        ),
        sourceURL: nil
    )

    static let bridgeLogs = TabDefinition(
        id: "bridge-logs",
        label: "Bridge Logs",
        icon: "doc.text.magnifyingglass",
        order: 40,
        harness: .shell,
        model: nil,
        systemPrompt: "",
        cwd: "~",
        launchArgs: [],
        readOnly: false,
        useTmux: false,
        tmuxSessionName: nil,
        env: [:],
        shell: TabDefinition.ShellConfig(
            program: "/bin/zsh",
            initScript: bridgeLogsInitScriptPath
        ),
        sourceURL: nil
    )

    static let bridgeLogsInitScriptPath = "~/.talkie/tabs/bridge-logs.init.zsh"

    private static var mergedClaudeSystemPrompt: String {
        let bundled = TabPresetAssetLoader.text(
            relativePath: "prompts/talkie-agent/system.md",
            fallback: ""
        )
        if !bundled.isEmpty {
            return bundled
        }
        return """
        You are the Talkie assistant running inside the Talkie macOS app console.
        Help the user with Talkie configuration, workflow authoring, and codebase tasks.
        Read WORKFLOW_AUTHORING.md and WORKFLOW_CAPABILITIES.md before creating a workflow.
        """
    }
}

enum TabPresetAssetLoader {
    static func text(relativePath: String, fallback: String) -> String {
        optionalText(relativePath: relativePath) ?? fallback
    }

    static func optionalText(relativePath: String) -> String? {
        guard let url = resourceURL(relativePath: relativePath),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func resourceURL(relativePath: String) -> URL? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }

        let directURL = URL(fileURLWithPath: resourcePath)
            .appending(path: "AgentKit", directoryHint: .isDirectory)
            .appending(path: relativePath)
        if FileManager.default.fileExists(atPath: directURL.path) {
            return directURL
        }

        let nestedURL = URL(fileURLWithPath: resourcePath)
            .appending(path: "Resources", directoryHint: .isDirectory)
            .appending(path: "AgentKit", directoryHint: .isDirectory)
            .appending(path: relativePath)
        if FileManager.default.fileExists(atPath: nestedURL.path) {
            return nestedURL
        }

        return nil
    }
}
