//
//  AgentVoiceTool.swift
//  TalkieAgent
//
//  Tool-calling layer for the agent voice surface. v1 exposes a single tool —
//  `talkie_cli` — restricted to a read-only allowlist of subcommands.
//  Output is forced to JSON so the LLM can structure-pattern-match on
//  it rather than parse prose.
//
//  Future tools land here (shell, AppleScript, window control) each
//  behind their own setting + allowlist. The session reads each
//  AgentVoiceToolInvocation it produces and surfaces them live in the
//  scope panel.
//

import Foundation
import AppKit
import TalkieKit

private let log = Log(.workflow)

/// Read-only allowlist. The LLM may *request* anything; the executor
/// rejects the call unless `args.first` is in this set.
private let allowedTalkieCliSubcommands: Set<String> = [
    "memos",
    "dictations",
    "captures",
    "search",
    "workflows",
    "stats",
]

private let cliTimeoutSeconds: TimeInterval = 10
private let outputTruncationChars = 12_000

// MARK: - Public types

struct AgentVoiceToolInvocation: Identifiable, Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case running
        case done
        case failed(String)
    }

    let id: UUID
    let toolName: String
    let displayCommand: String     // human-readable, e.g. "talkie memos --limit 5"
    let args: [String]
    var status: Status
    var output: String?            // truncated stdout for LLM + UI
    var durationMs: Int?
    let startedAt: Date

    init(toolName: String, displayCommand: String, args: [String]) {
        self.id = UUID()
        self.toolName = toolName
        self.displayCommand = displayCommand
        self.args = args
        self.status = .running
        self.output = nil
        self.durationMs = nil
        self.startedAt = Date()
    }
}

enum AgentVoiceToolError: LocalizedError, Sendable {
    case unknownTool(String)
    case missingArgs
    case subcommandNotAllowed(String)
    case execFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .unknownTool(let n): return "Unknown tool: \(n)"
        case .missingArgs: return "Tool called without args."
        case .subcommandNotAllowed(let s): return "Subcommand '\(s)' is not on the read-only allowlist."
        case .execFailed(let detail): return "CLI exec failed: \(detail)"
        case .timeout: return "CLI call timed out (\(Int(cliTimeoutSeconds))s)."
        }
    }
}

// MARK: - JSON-Schema definitions sent to the LLM

enum AgentVoiceToolCatalog {
    /// OpenAI tool definitions (Chat Completions tools API).
    static func toolDefinitions() -> [[String: Any]] {
        return [
            talkieCliTool(),
            captureMarkupTool(),
        ]
    }

    private static func talkieCliTool() -> [String: Any] {
        [
                "type": "function",
                "function": [
                    "name": "talkie_cli",
                    "description": """
                    Run a read-only Talkie CLI command and return the JSON output. Use this to query the \
                    user's voice memos, dictations, captures, search results, workflow runs, and usage stats. Only \
                    these subcommands are allowed: memos, dictations, captures, search, workflows, stats. Output is \
                    automatically requested in JSON; you don't need to add --json.
                    """,
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "args": [
                                "type": "array",
                                "items": ["type": "string"],
                                "description": """
                                Full argument list to pass after `talkie`. First element MUST be one of: \
                                memos, dictations, captures, search, workflows, stats. Examples: ['memos'], \
                                ['search', 'bridge protocol'], ['memos', '--limit', '3'], ['stats'].
                                """,
                            ],
                        ],
                        "required": ["args"],
                        "additionalProperties": false,
                    ],
                ],
        ]
    }

    private static func captureMarkupTool() -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "capture_markup_open",
                "description": """
                Open Talkie's agentic screenshot markup bay for an image file on disk. \
                Optionally pass a natural-language instruction for the agent to apply markup.
                """,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description": "Absolute path to a PNG/JPEG screenshot file.",
                        ],
                        "instruction": [
                            "type": "string",
                            "description": "Optional markup instruction, e.g. highlight the error line.",
                        ],
                    ],
                    "required": ["path"],
                    "additionalProperties": false,
                ],
            ],
        ]
    }
}

// MARK: - Executor

enum AgentVoiceToolExecutor {
    /// Execute one tool call. Returns the completed invocation (with
    /// output + status). Throws if the tool is unknown or rejected.
    static func execute(name: String, arguments: [String: Any]) async throws -> AgentVoiceToolInvocation {
        switch name {
        case "talkie_cli":
            return try await runTalkieCLI(arguments: arguments)
        case "capture_markup_open":
            return try await runCaptureMarkupOpen(arguments: arguments)
        default:
            throw AgentVoiceToolError.unknownTool(name)
        }
    }

    // MARK: - capture_markup_open

    private static func runCaptureMarkupOpen(arguments: [String: Any]) async throws -> AgentVoiceToolInvocation {
        guard let path = arguments["path"] as? String, !path.isEmpty else {
            throw AgentVoiceToolError.missingArgs
        }
        let instruction = arguments["instruction"] as? String
        var components = URLComponents()
        components.scheme = TalkieEnvironment.current.talkieURLScheme
        components.host = "capture"
        components.path = "/markup"
        var query: [URLQueryItem] = [
            URLQueryItem(name: "path", value: path),
        ]
        if let instruction, !instruction.isEmpty {
            query.append(URLQueryItem(name: "instruction", value: instruction))
        }
        components.queryItems = query
        guard let url = components.url else {
            throw AgentVoiceToolError.execFailed("Invalid capture markup URL")
        }

        let display = "\(TalkieEnvironment.current.talkieURLScheme)://capture/markup path=\(path)"
        var invocation = AgentVoiceToolInvocation(
            toolName: "capture_markup_open",
            displayCommand: display,
            args: [path]
        )

        let started = Date()
        let opened = await MainActor.run {
            TalkieAppOpener.open(url)
        }
        invocation.durationMs = Int(Date().timeIntervalSince(started) * 1000)
        if opened {
            invocation.status = .done
            invocation.output = "{\"ok\":true,\"url\":\"\(url.absoluteString)\"}"
        } else {
            invocation.status = .failed("Talkie did not open the markup URL")
        }
        return invocation
    }

    // MARK: - talkie_cli

    private static func runTalkieCLI(arguments: [String: Any]) async throws -> AgentVoiceToolInvocation {
        guard let args = arguments["args"] as? [String], !args.isEmpty else {
            throw AgentVoiceToolError.missingArgs
        }
        let subcommand = args[0]
        guard allowedTalkieCliSubcommands.contains(subcommand) else {
            throw AgentVoiceToolError.subcommandNotAllowed(subcommand)
        }

        // Force JSON output (idempotent — the LLM may include it too).
        var resolvedArgs = args
        if !resolvedArgs.contains("--json") {
            resolvedArgs.append("--json")
        }
        let displayCommand = "talkie " + resolvedArgs.joined(separator: " ")
        var invocation = AgentVoiceToolInvocation(
            toolName: "talkie_cli",
            displayCommand: displayCommand,
            args: resolvedArgs
        )

        let started = Date()
        do {
            let stdout = try await runShell("talkie " + shellQuote(resolvedArgs))
            invocation.output = truncate(stdout)
            invocation.durationMs = Int(Date().timeIntervalSince(started) * 1000)
            invocation.status = .done
            log.info(
                "Tool talkie_cli succeeded",
                detail: "\(displayCommand) duration=\(invocation.durationMs ?? -1)ms"
            )
            return invocation
        } catch {
            invocation.durationMs = Int(Date().timeIntervalSince(started) * 1000)
            invocation.status = .failed(error.localizedDescription)
            invocation.output = (error as? AgentVoiceToolError)?.errorDescription
            log.error("Tool talkie_cli failed", detail: error.localizedDescription)
            return invocation
        }
    }

    // MARK: - Shell

    /// Run a command through a login bash so PATH (including fnm /
    /// homebrew) resolves the same way it does in the user's terminal.
    /// Captures stdout; merges stderr into stdout so the LLM sees CLI
    /// usage errors too.
    private static func runShell(_ command: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-lc", command]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            // Timeout watchdog — kills the process if it overruns.
            let timeoutItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + cliTimeoutSeconds,
                execute: timeoutItem
            )

            process.terminationHandler = { proc in
                timeoutItem.cancel()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if proc.terminationReason == .uncaughtSignal && proc.terminationStatus == 15 {
                    continuation.resume(throwing: AgentVoiceToolError.timeout)
                } else if proc.terminationStatus != 0 {
                    let detail = output.isEmpty ? "exit \(proc.terminationStatus)" : output
                    continuation.resume(throwing: AgentVoiceToolError.execFailed(detail))
                } else {
                    continuation.resume(returning: output)
                }
            }

            do {
                try process.run()
            } catch {
                timeoutItem.cancel()
                continuation.resume(throwing: error)
            }
        }
    }

    /// Quote args for safe shell interpolation. Single-quote each, and
    /// escape any single-quote inside.
    private static func shellQuote(_ args: [String]) -> String {
        args.map { a in
            "'" + a.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }.joined(separator: " ")
    }

    private static func truncate(_ s: String) -> String {
        if s.count <= outputTruncationChars { return s }
        let head = s.prefix(outputTruncationChars)
        return head + "\n\n[…truncated, \(s.count - outputTruncationChars) more chars]"
    }
}
