//
//  AgentHarnessProfile.swift
//  Talkie
//
//  Supported managed agent harnesses for the in-app agent lab.
//

import Foundation
import TalkieKit

enum AgentHarnessProfile: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case openCode
    case claude
    case helloWorld

    static let openCodeDefaultModel = ProcessInfo.processInfo.environment["TALKIE_OPENCODE_MODEL"] ?? "opencode/minimax-m2.5-free"

    struct LaunchSpec: Sendable {
        enum SessionMode: Sendable, Equatable {
            case ephemeral
            case tmux(sessionName: String, executableURL: URL)

            var keepsSessionAliveOnDetach: Bool {
                switch self {
                case .ephemeral:
                    false
                case .tmux:
                    true
                }
            }
        }

        let executableURL: URL
        let arguments: [String]
        let environment: [String: String]
        let workingDirectoryURL: URL
        let sessionMode: SessionMode
        let shouldSendInitialPrompt: Bool
    }

    enum LaunchError: LocalizedError {
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let message):
                message
            }
        }
    }

    var id: String { rawValue }

    static var defaultProfile: AgentHarnessProfile {
        .helloWorld
    }

    static var consoleTmuxAvailable: Bool {
        tmuxExecutableURL(preferTmux: true) != nil
    }

    static func tmuxExecutableURL(preferTmux: Bool) -> URL? {
        guard preferTmux else { return nil }
        return ExecutableResolver.resolve("tmux")
    }

    var displayName: String {
        switch self {
        case .openCode:
            "OpenCode"
        case .claude:
            "Claude"
        case .helloWorld:
            "Local Shell"
        }
    }

    var summary: String {
        switch self {
        case .openCode:
            "Runs OpenCode inside a prepared Talkie workspace."
        case .claude:
            "Runs Claude Code inside a prepared Talkie workspace."
        case .helloWorld:
            "Interactive zsh session inside the prepared Talkie workspace."
        }
    }

    var isAvailable: Bool {
        switch self {
        case .openCode:
            executableURL != nil
        case .claude:
            executableURL != nil
        case .helloWorld:
            true
        }
    }

    var availabilityNote: String? {
        switch self {
        case .openCode:
            if isAvailable {
                nil
            } else {
                "OpenCode is not installed or not on PATH. The Local Shell harness will still work."
            }
        case .claude:
            if isAvailable {
                nil
            } else {
                "Claude Code is not installed or not on PATH. The Local Shell harness will still work."
            }
        case .helloWorld:
            nil
        }
    }

    var executableURL: URL? {
        switch self {
        case .openCode:
            ExecutableResolver.resolve("opencode")
        case .claude:
            ExecutableResolver.resolve("claude")
        case .helloWorld:
            URL(fileURLWithPath: "/bin/zsh")
        }
    }

    func makeLaunchSpec(prompt: String, workspaceURL: URL) throws -> LaunchSpec {
        switch self {
        case .openCode:
            guard let executableURL else {
                throw LaunchError.unavailable("OpenCode is not available on this Mac.")
            }

            return LaunchSpec(
                executableURL: executableURL,
                arguments: ["run", prompt],
                environment: [
                    "TERM": "dumb",
                    "NO_COLOR": "1",
                    "CI": "1",
                ],
                workingDirectoryURL: workspaceURL,
                sessionMode: .ephemeral,
                shouldSendInitialPrompt: false
            )

        case .claude:
            guard let executableURL else {
                throw LaunchError.unavailable("Claude Code is not available on this Mac.")
            }

            return LaunchSpec(
                executableURL: executableURL,
                arguments: ["-p", prompt],
                environment: [
                    "TERM": "dumb",
                    "NO_COLOR": "1",
                    "CI": "1",
                ],
                workingDirectoryURL: workspaceURL,
                sessionMode: .ephemeral,
                shouldSendInitialPrompt: false
            )

        case .helloWorld:
            return LaunchSpec(
                executableURL: URL(fileURLWithPath: "/bin/zsh"),
                arguments: [
                    "-lc",
                    """
                    printf 'Talkie Local Shell\\n\\n'; \
                    printf 'Workspace: %s\\n\\n' "$PWD"; \
                    printf 'Workspace files:\\n'; \
                    /bin/ls -1; \
                    printf '\\nRule Packs:\\n'; \
                    /bin/ls -1 'Rule Packs' 2>/dev/null || true; \
                    printf '\\nLive Config:\\n'; \
                    /bin/ls -1 'Live Config' 2>/dev/null || true; \
                    printf '\\nTools:\\n'; \
                    /bin/ls -1 'Tools' 2>/dev/null || true; \
                    printf '\\nNext step:\\nUse this shell to verify the terminal relay before enabling OpenCode again.\\n'
                    """
                ],
                environment: [
                    "TERM": "dumb",
                    "NO_COLOR": "1",
                    "CI": "1",
                ],
                workingDirectoryURL: workspaceURL,
                sessionMode: .ephemeral,
                shouldSendInitialPrompt: false
            )
        }
    }

    func makeConsoleLaunchSpec(workspaceURL: URL) throws -> LaunchSpec {
        try makeConsoleLaunchSpec(
            workspaceURL: workspaceURL,
            preferredModel: nil,
            preferTmux: false
        )
    }

    func makeConsoleLaunchSpec(
        workspaceURL: URL,
        preferredModel: String?,
        preferTmux: Bool
    ) throws -> LaunchSpec {
        switch self {
        case .openCode:
            guard let openCodeExecutableURL = executableURL else {
                throw LaunchError.unavailable("OpenCode is not available on this Mac.")
            }

            let model = preferredModel ?? Self.openCodeDefaultModel
            let environment = [
                "TERM": "xterm-256color",
                "COLORTERM": "truecolor",
                "TERM_PROGRAM": "Talkie",
            ]

            if let tmuxExecutableURL = Self.tmuxExecutableURL(preferTmux: preferTmux) {
                let sessionName = Self.tmuxSessionName(for: workspaceURL)
                let sessionExists = Self.tmuxSessionExists(
                    named: sessionName,
                    executableURL: tmuxExecutableURL
                )
                let openCodeCommand = Self.shellCommand(
                    executablePath: openCodeExecutableURL.path,
                    arguments: openCodeArguments(
                        model: model,
                        workspacePath: workspaceURL.path
                    )
                )
                let paneCommand = Self.shellCommand(
                    executablePath: "/bin/zsh",
                    arguments: [
                        "-lc",
                        """
                        export TERM=xterm-256color COLORTERM=truecolor TERM_PROGRAM=Talkie
                        \(openCodeCommand)
                        EXIT_CODE=$?
                        printf '\\n[Talkie] OpenCode exited with status %s. Dropping into local shell.\\n' "$EXIT_CODE"
                        exec /bin/zsh -i
                        """
                    ]
                )
                let script = """
                TMUX_BIN=\(Self.shellQuote(tmuxExecutableURL.path))
                SESSION_NAME=\(Self.shellQuote(sessionName))
                WORKSPACE=\(Self.shellQuote(workspaceURL.path))
                if ! "$TMUX_BIN" has-session -t "$SESSION_NAME" 2>/dev/null; then
                  "$TMUX_BIN" new-session -d -s "$SESSION_NAME" -c "$WORKSPACE" "exec \(paneCommand)"
                fi
                "$TMUX_BIN" set-option -t "$SESSION_NAME" status off >/dev/null 2>&1 || true
                exec "$TMUX_BIN" attach-session -t "$SESSION_NAME"
                """

                return LaunchSpec(
                    executableURL: URL(fileURLWithPath: "/bin/zsh"),
                    arguments: ["-lc", script],
                    environment: environment,
                    workingDirectoryURL: workspaceURL,
                    sessionMode: .tmux(
                        sessionName: sessionName,
                        executableURL: tmuxExecutableURL
                    ),
                    shouldSendInitialPrompt: !sessionExists
                )
            }

            return LaunchSpec(
                executableURL: openCodeExecutableURL,
                arguments: openCodeArguments(
                    model: model,
                    workspacePath: workspaceURL.path
                ),
                environment: environment,
                workingDirectoryURL: workspaceURL,
                sessionMode: .ephemeral,
                shouldSendInitialPrompt: true
            )

        case .claude:
            guard let claudeExecutableURL = executableURL else {
                throw LaunchError.unavailable("Claude Code is not available on this Mac.")
            }

            let environment = [
                "TERM": "xterm-256color",
                "COLORTERM": "truecolor",
                "TERM_PROGRAM": "Talkie",
            ]

            if let tmuxExecutableURL = Self.tmuxExecutableURL(preferTmux: preferTmux) {
                let sessionName = Self.tmuxSessionName(for: workspaceURL)
                let launchCommand = Self.shellCommand(
                    executablePath: claudeExecutableURL.path,
                    arguments: []
                )
                let paneCommand = Self.shellCommand(
                    executablePath: "/bin/zsh",
                    arguments: [
                        "-lc",
                        """
                        export TERM=xterm-256color COLORTERM=truecolor TERM_PROGRAM=Talkie
                        \(launchCommand)
                        EXIT_CODE=$?
                        printf '\\n[Talkie] Claude exited with status %s. Dropping into local shell.\\n' "$EXIT_CODE"
                        exec /bin/zsh -i
                        """
                    ]
                )
                let script = """
                TMUX_BIN=\(Self.shellQuote(tmuxExecutableURL.path))
                SESSION_NAME=\(Self.shellQuote(sessionName))
                WORKSPACE=\(Self.shellQuote(workspaceURL.path))
                if ! "$TMUX_BIN" has-session -t "$SESSION_NAME" 2>/dev/null; then
                  "$TMUX_BIN" new-session -d -s "$SESSION_NAME" -c "$WORKSPACE" "exec \(paneCommand)"
                fi
                "$TMUX_BIN" set-option -t "$SESSION_NAME" status off >/dev/null 2>&1 || true
                exec "$TMUX_BIN" attach-session -t "$SESSION_NAME"
                """

                return LaunchSpec(
                    executableURL: URL(fileURLWithPath: "/bin/zsh"),
                    arguments: ["-lc", script],
                    environment: environment,
                    workingDirectoryURL: workspaceURL,
                    sessionMode: .tmux(
                        sessionName: sessionName,
                        executableURL: tmuxExecutableURL
                    ),
                    shouldSendInitialPrompt: false
                )
            }

            return LaunchSpec(
                executableURL: claudeExecutableURL,
                arguments: [],
                environment: environment,
                workingDirectoryURL: workspaceURL,
                sessionMode: .ephemeral,
                shouldSendInitialPrompt: false
            )

        case .helloWorld:
            let environment = [
                "TERM": "xterm-256color",
                "COLORTERM": "truecolor",
                "TERM_PROGRAM": "Talkie",
            ]

            if let tmuxExecutableURL = Self.tmuxExecutableURL(preferTmux: preferTmux) {
                let sessionName = Self.tmuxSessionName(for: workspaceURL)
                let launchCommand = Self.shellCommand(
                    executablePath: "/bin/zsh",
                    arguments: ["-i"]
                )
                let script = """
                TMUX_BIN=\(Self.shellQuote(tmuxExecutableURL.path))
                SESSION_NAME=\(Self.shellQuote(sessionName))
                WORKSPACE=\(Self.shellQuote(workspaceURL.path))
                if ! "$TMUX_BIN" has-session -t "$SESSION_NAME" 2>/dev/null; then
                  "$TMUX_BIN" new-session -d -s "$SESSION_NAME" -c "$WORKSPACE" "exec \(launchCommand)"
                fi
                "$TMUX_BIN" set-option -t "$SESSION_NAME" status off >/dev/null 2>&1 || true
                exec "$TMUX_BIN" attach-session -t "$SESSION_NAME"
                """

                return LaunchSpec(
                    executableURL: URL(fileURLWithPath: "/bin/zsh"),
                    arguments: ["-lc", script],
                    environment: environment,
                    workingDirectoryURL: workspaceURL,
                    sessionMode: .tmux(
                        sessionName: sessionName,
                        executableURL: tmuxExecutableURL
                    ),
                    shouldSendInitialPrompt: false
                )
            }

            return LaunchSpec(
                executableURL: URL(fileURLWithPath: "/bin/zsh"),
                arguments: ["-i"],
                environment: environment,
                workingDirectoryURL: workspaceURL,
                sessionMode: .ephemeral,
                shouldSendInitialPrompt: false
            )
        }
    }

    private func openCodeArguments(model: String, workspacePath: String) -> [String] {
        var arguments: [String] = []

        if !model.isEmpty {
            arguments.append(contentsOf: ["-m", model])
        }

        arguments.append(workspacePath)
        return arguments
    }

    static func tmuxSessionName(for workspaceURL: URL) -> String {
        let sanitized = workspaceURL.lastPathComponent
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9_-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))

        let suffix = sanitized.isEmpty ? "console" : sanitized
        return "talkie-\(suffix)"
    }

    static func tmuxSessionExists(named sessionName: String, executableURL: URL) -> Bool {
        let task = Process()
        task.executableURL = executableURL
        task.arguments = ["has-session", "-t", sessionName]

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func shellCommand(executablePath: String, arguments: [String]) -> String {
        ([shellQuote(executablePath)] + arguments.map(shellQuote))
            .joined(separator: " ")
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\"'\"'"#) + "'"
    }

    static func locateExecutable(named name: String, candidates: [String] = []) -> URL? {
        ExecutableResolver.resolve(name, extraCandidates: candidates)
    }

    private static var searchPathEntries: [String] {
        uniquePathEntries(
            fallbackSearchPaths
            + splitPathEntries(ProcessInfo.processInfo.environment["PATH"])
            + loginShellPathEntries
        )
    }

    private static var fallbackSearchPaths: [String] {
        [
            "\(NSHomeDirectory())/.local/bin",
            "\(NSHomeDirectory())/.opencode/bin",
            "\(NSHomeDirectory())/.bun/bin",
            "\(NSHomeDirectory())/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
    }

    private static let loginShellPathEntries: [String] = {
        guard let shellPath = userShellPath(),
              let shellOutput = runProcess(
                executablePath: shellPath,
                arguments: ["-lc", "printf %s \"$PATH\""]
              ) else {
            return []
        }

        return splitPathEntries(shellOutput)
    }()

    private static func userShellPath() -> String? {
        let fileManager = FileManager.default

        if let envShell = ProcessInfo.processInfo.environment["SHELL"],
           fileManager.isExecutableFile(atPath: envShell) {
            return envShell
        }

        guard let shellOutput = runProcess(
            executablePath: "/usr/bin/dscl",
            arguments: [".", "-read", "/Users/\(NSUserName())", "UserShell"]
        ) else {
            return "/bin/zsh"
        }

        guard let line = shellOutput
            .split(separator: "\n")
            .map(String.init)
            .first(where: { $0.hasPrefix("UserShell:") }) else {
            return "/bin/zsh"
        }

        let shellPath = line
            .replacingOccurrences(of: "UserShell:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if fileManager.isExecutableFile(atPath: shellPath) {
            return shellPath
        }

        return "/bin/zsh"
    }

    private static func splitPathEntries(_ pathValue: String?) -> [String] {
        guard let pathValue else { return [] }

        return pathValue
            .split(separator: ":")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func uniquePathEntries(_ entries: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []

        for entry in entries where seen.insert(entry).inserted {
            unique.append(entry)
        }

        return unique
    }

    private static func runProcess(executablePath: String, arguments: [String]) -> String? {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: stdout, encoding: .utf8)
    }
}
