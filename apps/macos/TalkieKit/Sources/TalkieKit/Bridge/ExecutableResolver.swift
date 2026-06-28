//
//  ExecutableResolver.swift
//  TalkieKit
//
//  Unified executable resolution and PATH enrichment.
//  Replaces scattered locate/resolve patterns across the codebase.
//

import Foundation

public enum ExecutableResolver {

    // MARK: - Resolution

    /// Resolve an executable by name.
    /// Checks known candidate paths first, then searches the enriched PATH.
    public static func resolve(_ name: String) -> URL? {
        resolve(name, extraCandidates: [])
    }

    /// Resolve an executable with additional candidate paths beyond the built-in ones.
    public static func resolve(_ name: String, extraCandidates: [String]) -> URL? {
        let fm = FileManager.default
        let allCandidates = (knownCandidates[name] ?? []) + extraCandidates

        for candidate in allCandidates {
            let expanded = expandPath(candidate)
            if fm.isExecutableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }

        // Fall back to enriched PATH search
        for dir in enrichedPATHDirectories() {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        if let shellResolved = resolveInUserShell(name) {
            return URL(fileURLWithPath: shellResolved)
        }

        return nil
    }

    /// Resolve and return the path string, or nil.
    public static func resolvePath(_ name: String) -> String? {
        resolve(name)?.path
    }

    /// Resolve a command using the user's preferred shell startup environment.
    /// This is helpful for tools installed through npm/fnm/nvm where launchd does
    /// not inherit the same PATH entries as a normal terminal session.
    public static func resolveInUserShell(_ name: String) -> String? {
        let fm = FileManager.default
        guard let shellPath = preferredShellPath() else { return nil }

        let command = "command -v -- \(shellQuote(name)) 2>/dev/null || true"
        guard let output = runProcess(
            executablePath: shellPath,
            arguments: ["-ilc", command]
        ) else {
            return nil
        }

        let lines = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines.reversed() {
            if line.hasPrefix("/"), fm.isExecutableFile(atPath: line) {
                return line
            }
        }

        return nil
    }

    /// Returns the user's preferred shell when possible, falling back to zsh.
    public static func preferredShellPath() -> String? {
        let fm = FileManager.default

        if let envShell = ProcessInfo.processInfo.environment["SHELL"],
           fm.isExecutableFile(atPath: envShell) {
            return envShell
        }

        guard let output = runProcess(
            executablePath: "/usr/bin/dscl",
            arguments: [".", "-read", "/Users/\(NSUserName())", "UserShell"]
        ) else {
            return fm.isExecutableFile(atPath: "/bin/zsh") ? "/bin/zsh" : nil
        }

        let shellPath = output
            .split(separator: "\n")
            .map(String.init)
            .first(where: { $0.hasPrefix("UserShell:") })?
            .replacingOccurrences(of: "UserShell:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let shellPath, fm.isExecutableFile(atPath: shellPath) {
            return shellPath
        }

        return fm.isExecutableFile(atPath: "/bin/zsh") ? "/bin/zsh" : nil
    }

    // MARK: - PATH Enrichment

    /// Directories to prepend to PATH for subprocess environments.
    /// Includes user-local tool locations that launchd/XPC agents typically lack.
    public static func enrichedPATHDirectories() -> [String] {
        enrichedPATHDirectories(
            environment: ProcessInfo.processInfo.environment,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
    }

    static func enrichedPATHDirectories(
        environment: [String: String],
        homeDirectory: String
    ) -> [String] {
        var patterns = [
            "\(homeDirectory)/.bun/bin",
            "\(homeDirectory)/.local/bin",
            "\(homeDirectory)/Library/pnpm",
            "\(homeDirectory)/.local/share/pnpm",
        ]

        // FNM can leave behind thousands of multishell symlinks. Expanding all of
        // them makes PATH large enough to trip execve(E2BIG), so keep only the
        // active multishell path plus stable install locations.
        if let activeFNMMultishell = environment["FNM_MULTISHELL_PATH"],
           !activeFNMMultishell.isEmpty {
            patterns.append("\(expandPath(activeFNMMultishell))/bin")
        }

        patterns.append(contentsOf: [
            "\(homeDirectory)/.local/share/fnm/aliases/default/bin",
            "\(homeDirectory)/.local/share/fnm/node-versions/*/installation/bin",
            "\(homeDirectory)/.nvm/versions/node/*/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
        ])

        return patterns
            .flatMap(expandPatternDirectories)
            .removingDuplicates()
    }

    /// Build a PATH string that prepends enriched directories to the current PATH.
    public static func enrichedPATH(from currentPATH: String? = nil) -> String {
        let base = currentPATH
            ?? ProcessInfo.processInfo.environment["PATH"]
            ?? "/usr/bin:/bin"
        let existing = Set(base.components(separatedBy: ":"))
        let additions = enrichedPATHDirectories().filter { !existing.contains($0) }

        if additions.isEmpty { return base }
        return (additions + [base]).joined(separator: ":")
    }

    /// Returns a copy of the given environment with an enriched PATH.
    public static func enrichedEnvironment(from env: [String: String]? = nil) -> [String: String] {
        var result = env ?? ProcessInfo.processInfo.environment
        result["PATH"] = enrichedPATH(from: result["PATH"])
        return result
    }

    // MARK: - Known Tools

    /// Built-in candidate paths for commonly used executables.
    /// Ordered by likelihood — user-local installs first, then system locations.
    public static let knownCandidates: [String: [String]] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "bun": [
                "\(home)/.bun/bin/bun",
                "/opt/homebrew/bin/bun",
                "/usr/local/bin/bun",
            ],
            "claude": [
                "\(home)/.local/bin/claude",
                "\(home)/.claude/local/claude",
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude",
            ],
            "pi": [
                "\(home)/.local/bin/pi",
                "\(home)/.bun/bin/pi",
                "/opt/homebrew/bin/pi",
                "/usr/local/bin/pi",
            ],
            "opencode": [
                "\(home)/.opencode/bin/opencode",
                "/opt/homebrew/bin/opencode",
                "/usr/local/bin/opencode",
            ],
            "codex": [
                "/Applications/Codex.app/Contents/Resources/codex",
                "\(home)/Applications/Codex.app/Contents/Resources/codex",
                "\(home)/.local/bin/codex",
                "\(home)/.bun/bin/codex",
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex",
            ],
            "tmux": [
                "/opt/homebrew/bin/tmux",
                "/usr/local/bin/tmux",
                "/usr/bin/tmux",
            ],
            "node": [
                "/opt/homebrew/bin/node",
                "/usr/local/bin/node",
            ],
            "npm": [
                "/opt/homebrew/bin/npm",
                "/usr/local/bin/npm",
                "/usr/bin/npm",
            ],
            "brew": [
                "/opt/homebrew/bin/brew",
                "/usr/local/bin/brew",
            ],
            "tailscale": [
                "/opt/homebrew/bin/tailscale",
                "/usr/local/bin/tailscale",
            ],
            "gh": [
                "/opt/homebrew/bin/gh",
                "/usr/local/bin/gh",
            ],
            "python3": [
                "/usr/bin/python3",
                "/opt/homebrew/bin/python3",
            ],
            "npx": [
                "/opt/homebrew/bin/npx",
                "/usr/local/bin/npx",
            ],
            "ffmpeg": [
                "/opt/homebrew/bin/ffmpeg",
                "/usr/local/bin/ffmpeg",
            ],
            "ffprobe": [
                "/opt/homebrew/bin/ffprobe",
                "/usr/local/bin/ffprobe",
            ],
        ]
    }()

    // MARK: - Helpers

    private static func expandPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    private static func expandPatternDirectories(_ pattern: String) -> [String] {
        let fm = FileManager.default

        guard let wildcardIndex = pattern.firstIndex(of: "*") else {
            return fm.fileExists(atPath: pattern) ? [pattern] : []
        }

        let prefix = String(pattern[..<wildcardIndex])
        let suffix = String(pattern[pattern.index(after: wildcardIndex)...])
        let parent = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix

        guard !parent.isEmpty,
              let children = try? fm.contentsOfDirectory(atPath: parent) else {
            return []
        }

        return children
            .map { parent + "/\($0)" + suffix }
            .filter { fm.fileExists(atPath: $0) }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\"'\"'"#) + "'"
    }

    private static func runProcess(executablePath: String, arguments: [String]) -> String? {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

private extension Array where Element == String {
    func removingDuplicates() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
