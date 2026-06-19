//
//  TabLaunchSpec.swift
//  Talkie
//
//  Bridges TabDefinition into the existing AgentHarnessProfile.LaunchSpec
//  so tab sessions can reuse ManagedAgentConsoleSession's PTY machinery.
//

import Foundation
import TalkieKit

private let log = Log(.system)

enum TabLaunchSpec {

    static func makeLaunchSpec(
        for tab: TabDefinition,
        resolvedEnv: [String: String],
        workspaceURL: URL,
        preferTmux: Bool
    ) throws -> AgentHarnessProfile.LaunchSpec {
        switch tab.harness {
        case .claudeCode:
            return try makeClaudeLaunchSpec(
                tab: tab,
                resolvedEnv: resolvedEnv,
                workspaceURL: workspaceURL,
                preferTmux: preferTmux
            )

        case .pi:
            return try makePiLaunchSpec(
                tab: tab,
                resolvedEnv: resolvedEnv,
                workspaceURL: workspaceURL,
                preferTmux: preferTmux
            )

        case .shell:
            return makeShellLaunchSpec(
                tab: tab,
                resolvedEnv: resolvedEnv,
                workspaceURL: workspaceURL,
                preferTmux: preferTmux
            )

        case .opencode:
            return try makeOpenCodeLaunchSpec(
                tab: tab,
                resolvedEnv: resolvedEnv,
                workspaceURL: workspaceURL,
                preferTmux: preferTmux
            )
        }
    }

    static func bridgeToProfile(_ tab: TabDefinition) -> ManagedAgentConsoleProfile {
        let harness: AgentHarnessProfile
        switch tab.harness {
        case .claudeCode: harness = .claude
        case .pi: harness = .helloWorld
        case .shell: harness = .helloWorld
        case .opencode: harness = .openCode
        }

        return ManagedAgentConsoleProfile(
            id: tab.id,
            title: tab.label,
            contextLabel: tab.harness == .shell ? "Shell" : "Workspace",
            symbolName: tab.symbolName,
            summary: "\(tab.label) tab — \(tab.harness.displayName) harness",
            systemPrompt: tab.systemPrompt,
            prompt: "",
            notes: "",
            examples: "",
            bootstrapPrompt: nil,
            preferredModel: tab.model,
            autoSendPrompt: false,
            harness: harness
        )
    }

    static func tmuxSessionName(for tab: TabDefinition) -> String {
        if let custom = tab.tmuxSessionName, !custom.isEmpty {
            return custom
        }
        let sanitized = tab.id
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9_-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return "talkie-\(sanitized.isEmpty ? "tab" : sanitized)"
    }

    // MARK: - Harness-specific launch specs

    private static func makeClaudeLaunchSpec(
        tab: TabDefinition,
        resolvedEnv: [String: String],
        workspaceURL: URL,
        preferTmux: Bool
    ) throws -> AgentHarnessProfile.LaunchSpec {
        guard let executableURL = AgentHarnessProfile.claude.executableURL else {
            throw AgentHarnessProfile.LaunchError.unavailable("Claude Code is not available on this Mac.")
        }

        let env = launchEnvironment(
            resolvedEnv: resolvedEnv,
            executableURL: executableURL
        )

        // The Talkie agent boots into its durable agent home
        // (Application Support/Talkie/Agent) — shared across sessions rather than
        // regenerated per launch — so the CLAUDE.md / SYSTEM_PROMPT.md it
        // instantiates with persist and can be hand-tuned. Talkie still refreshes
        // the operational scaffolding there each launch (AGENTS.md, the
        // config/memo/workflow guides, Tools/, Live Config/). Running here, not
        // against a source checkout, keeps the experience identical for every
        // user — developer or not.
        let workingDirectoryURL = workspaceURL

        var args = tab.launchArgs
        if let model = tab.model, !model.isEmpty, !args.contains("--model") {
            args = ["--model", model] + args
        }

        // Deliver the curated system prompt to Claude Code itself. Before this it
        // was only ever written to SYSTEM_PROMPT.md and never reached the CLI, so
        // the agent launched with no Talkie-specific instruction at all.
        if !tab.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !args.contains(where: { $0.hasPrefix("--system-prompt") || $0.hasPrefix("--append-system-prompt") }) {
            let systemPromptFileURL = workspaceURL.appending(path: "SYSTEM_PROMPT.md")
            if FileManager.default.fileExists(atPath: systemPromptFileURL.path) {
                args = ["--append-system-prompt-file", systemPromptFileURL.path] + args
            }
        }

        if let tmuxSpec = tryTmuxWrap(
            tab: tab,
            executableURL: executableURL,
            arguments: args,
            environment: env,
            preferTmux: preferTmux,
            harnessLabel: "Claude",
            workingDirectoryURL: workingDirectoryURL
        ) {
            return tmuxSpec
        }

        return AgentHarnessProfile.LaunchSpec(
            executableURL: executableURL,
            arguments: args,
            environment: env,
            workingDirectoryURL: workingDirectoryURL,
            sessionMode: .ephemeral,
            shouldSendInitialPrompt: false
        )
    }

    private static func makePiLaunchSpec(
        tab: TabDefinition,
        resolvedEnv: [String: String],
        workspaceURL: URL,
        preferTmux: Bool
    ) throws -> AgentHarnessProfile.LaunchSpec {
        guard let executableURL = TabHarness.locatePi() else {
            throw AgentHarnessProfile.LaunchError.unavailable("pi is not installed or not on PATH.")
        }

        let env = launchEnvironment(
            resolvedEnv: resolvedEnv,
            executableURL: executableURL
        )

        var args = tab.launchArgs
        if let provider = tab.provider, !provider.isEmpty, !args.contains("--provider") {
            args = ["--provider", provider] + args
        }
        if let model = tab.model, !model.isEmpty, !args.contains("--model") {
            args = ["--model", model] + args
        }

        if let tmuxSpec = tryTmuxWrap(
            tab: tab,
            executableURL: executableURL,
            arguments: args,
            environment: env,
            preferTmux: preferTmux,
            harnessLabel: "Pi"
        ) {
            return tmuxSpec
        }

        return AgentHarnessProfile.LaunchSpec(
            executableURL: executableURL,
            arguments: args,
            environment: env,
            workingDirectoryURL: tab.resolvedCwd,
            sessionMode: .ephemeral,
            shouldSendInitialPrompt: false
        )
    }

    private static func makeShellLaunchSpec(
        tab: TabDefinition,
        resolvedEnv: [String: String],
        workspaceURL: URL,
        preferTmux: Bool
    ) -> AgentHarnessProfile.LaunchSpec {
        let program = tab.shell?.program ?? "/bin/zsh"
        let env = launchEnvironment(
            resolvedEnv: resolvedEnv,
            executableURL: URL(fileURLWithPath: program)
        )

        var args: [String]
        if let initScript = tab.shell?.initScript {
            let expanded = (initScript as NSString).expandingTildeInPath
            args = ["-lc", "source '\(expanded)'"]
        } else {
            args = ["-i"]
        }

        if let tmuxSpec = tryTmuxWrap(
            tab: tab,
            executableURL: URL(fileURLWithPath: program),
            arguments: args,
            environment: env,
            preferTmux: preferTmux,
            harnessLabel: "Shell"
        ) {
            return tmuxSpec
        }

        return AgentHarnessProfile.LaunchSpec(
            executableURL: URL(fileURLWithPath: program),
            arguments: args,
            environment: env,
            workingDirectoryURL: tab.resolvedCwd,
            sessionMode: .ephemeral,
            shouldSendInitialPrompt: false
        )
    }

    private static func makeOpenCodeLaunchSpec(
        tab: TabDefinition,
        resolvedEnv: [String: String],
        workspaceURL: URL,
        preferTmux: Bool
    ) throws -> AgentHarnessProfile.LaunchSpec {
        guard let executableURL = AgentHarnessProfile.openCode.executableURL else {
            throw AgentHarnessProfile.LaunchError.unavailable("OpenCode is not available on this Mac.")
        }

        let env = launchEnvironment(
            resolvedEnv: resolvedEnv,
            executableURL: executableURL
        )

        var args = tab.launchArgs
        if let model = tab.model, !model.isEmpty, !args.contains("-m") {
            args = ["-m", model] + args
        }
        args.append(tab.resolvedCwd.path)

        if let tmuxSpec = tryTmuxWrap(
            tab: tab,
            executableURL: executableURL,
            arguments: args,
            environment: env,
            preferTmux: preferTmux,
            harnessLabel: "OpenCode"
        ) {
            return tmuxSpec
        }

        return AgentHarnessProfile.LaunchSpec(
            executableURL: executableURL,
            arguments: args,
            environment: env,
            workingDirectoryURL: tab.resolvedCwd,
            sessionMode: .ephemeral,
            shouldSendInitialPrompt: false
        )
    }

    // MARK: - Tmux wrapping

    private static func tryTmuxWrap(
        tab: TabDefinition,
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        preferTmux: Bool,
        harnessLabel: String,
        workingDirectoryURL: URL? = nil
    ) -> AgentHarnessProfile.LaunchSpec? {
        guard preferTmux,
              let tmuxURL = AgentHarnessProfile.tmuxExecutableURL(preferTmux: true) else {
            return nil
        }

        let cwdURL = workingDirectoryURL ?? tab.resolvedCwd

        let sessionName = tmuxSessionName(for: tab)
        let sessionExists = AgentHarnessProfile.tmuxSessionExists(
            named: sessionName,
            executableURL: tmuxURL
        )

        let envExports = environment
            .filter { isUserEnvKey($0.key) }
            .map { "export \(AgentHarnessProfile.shellQuote($0.key))=\(AgentHarnessProfile.shellQuote($0.value))" }
            .joined(separator: "\n")

        let innerCommand = AgentHarnessProfile.shellCommand(
            executablePath: executableURL.path,
            arguments: arguments
        )
        let paneCommand = AgentHarnessProfile.shellCommand(
            executablePath: "/bin/zsh",
            arguments: [
                "-lc",
                """
                export TERM=xterm-256color COLORTERM=truecolor TERM_PROGRAM=Talkie
                \(envExports)
                \(innerCommand)
                EXIT_CODE=$?
                printf '\\n[Talkie] \(harnessLabel) exited with status %s. Dropping into local shell.\\n' "$EXIT_CODE"
                exec /bin/zsh -i
                """
            ]
        )

        let script = """
        TMUX_BIN=\(AgentHarnessProfile.shellQuote(tmuxURL.path))
        SESSION_NAME=\(AgentHarnessProfile.shellQuote(sessionName))
        WORKSPACE=\(AgentHarnessProfile.shellQuote(cwdURL.path))
        if ! "$TMUX_BIN" has-session -t "$SESSION_NAME" 2>/dev/null; then
          "$TMUX_BIN" new-session -d -s "$SESSION_NAME" -c "$WORKSPACE" "exec \(paneCommand)"
        fi
        "$TMUX_BIN" set-option -t "$SESSION_NAME" status off >/dev/null 2>&1 || true
        exec "$TMUX_BIN" attach-session -t "$SESSION_NAME"
        """

        log.info("Tmux wrap for tab", detail: "\(tab.id) → session \(sessionName)")

        return AgentHarnessProfile.LaunchSpec(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", script],
            environment: environment,
            workingDirectoryURL: cwdURL,
            sessionMode: .tmux(
                sessionName: sessionName,
                executableURL: tmuxURL
            ),
            shouldSendInitialPrompt: !sessionExists
        )
    }

    // MARK: - Helpers

    private static let systemEnvKeys: Set<String> = [
        "PATH", "HOME", "USER", "SHELL", "LOGNAME", "TMPDIR",
        "TERM", "COLORTERM", "TERM_PROGRAM", "LANG", "LC_ALL",
        "CLICOLOR", "FORCE_COLOR", "NO_COLOR",
        "XPC_FLAGS", "XPC_SERVICE_NAME", "__CF_USER_TEXT_ENCODING",
    ]

    private static let passthroughSystemEnvKeys: [String] = [
        "HOME",
        "USER",
        "SHELL",
        "LOGNAME",
        "TMPDIR",
        "LANG",
        "LC_ALL",
        "__CF_USER_TEXT_ENCODING",
    ]

    private static func isUserEnvKey(_ key: String) -> Bool {
        !systemEnvKeys.contains(key)
    }

    private static func launchEnvironment(
        resolvedEnv: [String: String],
        executableURL: URL? = nil
    ) -> [String: String] {
        var env: [String: String] = [:]

        for key in passthroughSystemEnvKeys {
            if let value = resolvedEnv[key], !value.isEmpty {
                env[key] = value
            }
        }

        env["HOME"] = env["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        env["USER"] = env["USER"] ?? NSUserName()
        env["LOGNAME"] = env["LOGNAME"] ?? env["USER"]
        env["SHELL"] = env["SHELL"] ?? ExecutableResolver.preferredShellPath() ?? "/bin/zsh"
        env["TMPDIR"] = env["TMPDIR"] ?? NSTemporaryDirectory()
        env["PATH"] = launchPath(
            basePATH: resolvedEnv["PATH"],
            executableURL: executableURL
        )
        env["NO_COLOR"] = nil
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["CLICOLOR"] = "1"
        env["FORCE_COLOR"] = "1"
        env["TERM_PROGRAM"] = "Talkie"

        for (key, value) in resolvedEnv where isUserEnvKey(key) {
            env[key] = value
        }

        return env
    }

    private static func launchPath(basePATH: String?, executableURL: URL?) -> String {
        var directories: [String] = []

        if let executableURL {
            directories.append(executableURL.deletingLastPathComponent().path)
        }

        directories.append(contentsOf: ExecutableResolver.enrichedPATHDirectories())
        directories.append(contentsOf: (basePATH ?? "/usr/bin:/bin").components(separatedBy: ":"))

        var seen = Set<String>()
        let deduplicated = directories.filter { directory in
            guard !directory.isEmpty else { return false }
            return seen.insert(directory).inserted
        }

        return deduplicated.joined(separator: ":")
    }
}
