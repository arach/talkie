//
//  WorkflowDefinition.swift
//  Talkie macOS
//
//  Workflow definition and management system
//

import Foundation
import SwiftUI

// MARK: - Workflow Definition

struct WorkflowDefinition: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    var icon: String
    var color: WorkflowColor
    var steps: [WorkflowStep]
    var isEnabled: Bool
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        icon: String = "wand.and.stars",
        color: WorkflowColor = .blue,
        steps: [WorkflowStep] = [],
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.color = color
        self.steps = steps
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    // Built-in system workflows
    static let summarize = WorkflowDefinition(
        name: "Quick Summary",
        description: "Generate a concise executive summary",
        icon: "list.bullet.clipboard",
        color: .blue,
        steps: [
            WorkflowStep(
                type: .llm,
                config: .llm(LLMStepConfig(
                    provider: .gemini,
                    modelId: "gemini-2.0-flash",
                    prompt: """
                    You are an expert executive assistant. Summarize the following voice memo transcript into a concise paragraph, highlighting the main purpose and outcome. Use a professional tone.

                    Transcript:
                    {{TRANSCRIPT}}
                    """,
                    temperature: 0.7,
                    maxTokens: 1024
                )),
                outputKey: "summary"
            )
        ]
    )

    static let extractTasks = WorkflowDefinition(
        name: "Extract Action Items",
        description: "Identify and list all tasks from the memo",
        icon: "checkmark.square",
        color: .green,
        steps: [
            WorkflowStep(
                type: .llm,
                config: .llm(LLMStepConfig(
                    provider: .gemini,
                    modelId: "gemini-2.0-flash",
                    prompt: """
                    You are a task extraction specialist. Identify and list all action items from the following voice memo transcript. Format as a JSON array of task objects with "title" and "priority" (high/medium/low).

                    Transcript:
                    {{TRANSCRIPT}}

                    Return ONLY valid JSON in this format:
                    [{"title": "Task description", "priority": "medium"}]
                    """,
                    temperature: 0.3,
                    maxTokens: 2048
                )),
                outputKey: "tasks"
            )
        ]
    )

    static let keyInsights = WorkflowDefinition(
        name: "Key Insights",
        description: "Extract 3-5 key takeaways",
        icon: "lightbulb",
        color: .yellow,
        steps: [
            WorkflowStep(
                type: .llm,
                config: .llm(LLMStepConfig(
                    provider: .gemini,
                    modelId: "gemini-2.0-flash",
                    prompt: """
                    You are an insight analyst. Extract 3-5 key takeaways from the following voice memo transcript. Format as a JSON array of strings.

                    Transcript:
                    {{TRANSCRIPT}}

                    Return ONLY valid JSON in this format:
                    ["Insight 1", "Insight 2", "Insight 3"]
                    """,
                    temperature: 0.5,
                    maxTokens: 1024
                )),
                outputKey: "summary"
            )
        ]
    )

    // MARK: - Default Workflows (Initial set)
    static let defaultWorkflows = [summarize, extractTasks, keyInsights]
}

// MARK: - Workflow Step

struct WorkflowStep: Identifiable, Codable {
    let id: UUID
    var type: StepType
    var config: StepConfig
    var outputKey: String
    var isEnabled: Bool
    var condition: StepCondition?

    init(
        id: UUID = UUID(),
        type: StepType,
        config: StepConfig,
        outputKey: String,
        isEnabled: Bool = true,
        condition: StepCondition? = nil
    ) {
        self.id = id
        self.type = type
        self.config = config
        self.outputKey = outputKey
        self.isEnabled = isEnabled
        self.condition = condition
    }

    enum StepType: String, Codable, CaseIterable {
        case llm = "LLM Generation"
        case shell = "Run Shell Command"
        case webhook = "Webhook"
        case email = "Send Email"
        case notification = "Send Notification"
        case appleNotes = "Add to Apple Notes"
        case appleReminders = "Create Reminder"
        case appleCalendar = "Create Calendar Event"
        case clipboard = "Copy to Clipboard"
        case saveFile = "Save to File"
        case conditional = "Conditional Branch"
        case transform = "Transform Data"

        var icon: String {
            switch self {
            case .llm: return "brain"
            case .shell: return "terminal"
            case .webhook: return "arrow.up.forward.app"
            case .email: return "envelope"
            case .notification: return "bell.badge"
            case .appleNotes: return "note.text"
            case .appleReminders: return "checklist"
            case .appleCalendar: return "calendar.badge.plus"
            case .clipboard: return "doc.on.clipboard"
            case .saveFile: return "doc.badge.plus"
            case .conditional: return "arrow.triangle.branch"
            case .transform: return "wand.and.rays"
            }
        }

        var description: String {
            switch self {
            case .llm: return "Process with AI model"
            case .shell: return "Execute CLI command"
            case .webhook: return "Send data to URL"
            case .email: return "Compose and send email"
            case .notification: return "Show system notification"
            case .appleNotes: return "Save to Apple Notes"
            case .appleReminders: return "Add to Reminders app"
            case .appleCalendar: return "Add calendar event"
            case .clipboard: return "Copy result to clipboard"
            case .saveFile: return "Save to local file"
            case .conditional: return "Branch based on condition"
            case .transform: return "Transform or filter data"
            }
        }

        var category: StepCategory {
            switch self {
            case .llm: return .ai
            case .shell: return .integration
            case .webhook: return .integration
            case .email: return .communication
            case .notification: return .communication
            case .appleNotes, .appleReminders, .appleCalendar: return .apple
            case .clipboard, .saveFile: return .output
            case .conditional, .transform: return .logic
            }
        }
    }

    enum StepCategory: String, CaseIterable {
        case ai = "AI Processing"
        case communication = "Communication"
        case apple = "Apple Apps"
        case integration = "Integrations"
        case output = "Output"
        case logic = "Logic"

        var icon: String {
            switch self {
            case .ai: return "cpu"
            case .communication: return "bubble.left.and.bubble.right"
            case .apple: return "apple.logo"
            case .integration: return "puzzlepiece.extension"
            case .output: return "square.and.arrow.down"
            case .logic: return "gearshape.2"
            }
        }

        var steps: [StepType] {
            StepType.allCases.filter { $0.category == self }
        }
    }
}

// MARK: - Step Configuration (Union Type)

enum StepConfig: Codable {
    case llm(LLMStepConfig)
    case shell(ShellStepConfig)
    case webhook(WebhookStepConfig)
    case email(EmailStepConfig)
    case notification(NotificationStepConfig)
    case appleNotes(AppleNotesStepConfig)
    case appleReminders(AppleRemindersStepConfig)
    case appleCalendar(AppleCalendarStepConfig)
    case clipboard(ClipboardStepConfig)
    case saveFile(SaveFileStepConfig)
    case conditional(ConditionalStepConfig)
    case transform(TransformStepConfig)

    // Provide a default config for each step type
    static func defaultConfig(for type: WorkflowStep.StepType) -> StepConfig {
        switch type {
        case .llm:
            return .llm(LLMStepConfig(provider: .gemini, prompt: ""))
        case .shell:
            return .shell(ShellStepConfig(executable: "/bin/echo", arguments: ["{{TRANSCRIPT}}"]))
        case .webhook:
            return .webhook(WebhookStepConfig(url: "", method: .post))
        case .email:
            return .email(EmailStepConfig(to: "", subject: "", body: ""))
        case .notification:
            return .notification(NotificationStepConfig(title: "", body: ""))
        case .appleNotes:
            return .appleNotes(AppleNotesStepConfig(folderName: nil, title: "", body: ""))
        case .appleReminders:
            return .appleReminders(AppleRemindersStepConfig(listName: nil, title: "", notes: nil, dueDate: nil, priority: .none))
        case .appleCalendar:
            return .appleCalendar(AppleCalendarStepConfig(calendarName: nil, title: "", notes: nil, startDate: nil, duration: 3600))
        case .clipboard:
            return .clipboard(ClipboardStepConfig(content: "{{OUTPUT}}"))
        case .saveFile:
            return .saveFile(SaveFileStepConfig(filename: "output.txt", directory: nil, content: "{{OUTPUT}}"))
        case .conditional:
            return .conditional(ConditionalStepConfig(condition: "", thenSteps: [], elseSteps: []))
        case .transform:
            return .transform(TransformStepConfig(operation: .extractJSON, parameters: [:]))
        }
    }
}

// MARK: - LLM Provider and Model Definitions for Workflows

enum WorkflowLLMProvider: String, Codable, CaseIterable {
    case gemini
    case openai
    case anthropic
    case groq
    case mlx

    var displayName: String {
        switch self {
        case .gemini: return "Gemini"
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .groq: return "Groq"
        case .mlx: return "MLX"
        }
    }

    /// Provider ID used by the LLMProviderRegistry
    var registryId: String {
        rawValue
    }

    var models: [WorkflowModelOption] {
        switch self {
        case .gemini:
            return [
                WorkflowModelOption(id: "gemini-2.0-flash", name: "Gemini 2.0 Flash", contextWindow: 1000000),
                WorkflowModelOption(id: "gemini-1.5-flash-latest", name: "Gemini 1.5 Flash", contextWindow: 1000000),
                WorkflowModelOption(id: "gemini-1.5-pro-latest", name: "Gemini 1.5 Pro", contextWindow: 2000000),
            ]
        case .openai:
            return [
                WorkflowModelOption(id: "gpt-4o", name: "GPT-4o", contextWindow: 128000),
                WorkflowModelOption(id: "gpt-4o-mini", name: "GPT-4o Mini", contextWindow: 128000),
                WorkflowModelOption(id: "gpt-4-turbo", name: "GPT-4 Turbo", contextWindow: 128000),
                WorkflowModelOption(id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo", contextWindow: 16385),
            ]
        case .anthropic:
            return [
                WorkflowModelOption(id: "claude-sonnet-4-20250514", name: "Claude Sonnet 4", contextWindow: 200000),
                WorkflowModelOption(id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", contextWindow: 200000),
                WorkflowModelOption(id: "claude-3-5-haiku-20241022", name: "Claude 3.5 Haiku", contextWindow: 200000),
                WorkflowModelOption(id: "claude-3-opus-20240229", name: "Claude 3 Opus", contextWindow: 200000),
            ]
        case .groq:
            return [
                WorkflowModelOption(id: "llama-3.3-70b-versatile", name: "Llama 3.3 70B", contextWindow: 128000),
                WorkflowModelOption(id: "llama-3.1-8b-instant", name: "Llama 3.1 8B Instant", contextWindow: 128000),
                WorkflowModelOption(id: "mixtral-8x7b-32768", name: "Mixtral 8x7B", contextWindow: 32768),
                WorkflowModelOption(id: "gemma2-9b-it", name: "Gemma 2 9B", contextWindow: 8192),
            ]
        case .mlx:
            return [
                WorkflowModelOption(id: "mlx-community/Llama-3.2-1B-Instruct-4bit", name: "Llama 3.2 1B", contextWindow: 8192),
                WorkflowModelOption(id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit", name: "Qwen 2.5 1.5B", contextWindow: 8192),
                WorkflowModelOption(id: "mlx-community/Llama-3.2-3B-Instruct-4bit", name: "Llama 3.2 3B", contextWindow: 8192),
                WorkflowModelOption(id: "mlx-community/Qwen2.5-3B-Instruct-4bit", name: "Qwen 2.5 3B", contextWindow: 8192),
                WorkflowModelOption(id: "mlx-community/Mistral-7B-Instruct-v0.3-4bit", name: "Mistral 7B", contextWindow: 32768),
            ]
        }
    }

    var defaultModel: WorkflowModelOption {
        models.first!
    }
}

struct WorkflowModelOption: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let contextWindow: Int

    var formattedContext: String {
        if contextWindow >= 1000000 {
            return "\(contextWindow / 1000000)M"
        } else if contextWindow >= 1000 {
            return "\(contextWindow / 1000)K"
        }
        return "\(contextWindow)"
    }
}

// MARK: - Step-Specific Configurations

struct LLMStepConfig: Codable {
    var provider: WorkflowLLMProvider
    var modelId: String
    var prompt: String
    var systemPrompt: String?
    var temperature: Double
    var maxTokens: Int
    var topP: Double

    init(
        provider: WorkflowLLMProvider = .gemini,
        modelId: String? = nil,
        prompt: String,
        systemPrompt: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 1024,
        topP: Double = 0.9
    ) {
        self.provider = provider
        self.modelId = modelId ?? provider.defaultModel.id
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
    }

    var selectedModel: WorkflowModelOption? {
        provider.models.first { $0.id == modelId }
    }
}

struct ShellStepConfig: Codable {
    var executable: String              // Path to CLI tool (e.g., "/usr/local/bin/gh", "/opt/homebrew/bin/jq")
    var arguments: [String]             // Command arguments, supports template variables
    var workingDirectory: String?       // Optional working directory
    var environment: [String: String]   // Additional environment variables
    var stdin: String?                  // Optional input to pass via stdin (supports templates)
    var promptTemplate: String?         // Multi-line prompt template (passed via -p flag for claude)
    var timeout: Int                    // Timeout in seconds (default 30)
    var captureStderr: Bool             // Include stderr in output

    init(
        executable: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String] = [:],
        stdin: String? = nil,
        promptTemplate: String? = nil,
        timeout: Int = 30,
        captureStderr: Bool = true
    ) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.stdin = stdin
        self.promptTemplate = promptTemplate
        self.timeout = timeout
        self.captureStderr = captureStderr
    }

    // MARK: - Security
    //
    // Threat model:
    // - Users are trusted (controlled environment)
    // - Content is untrusted (LLM outputs could contain injection attempts)
    // - Tools should have full capability (claude with MCP, gh with auth, etc.)
    //
    // Strategy: Sanitize data flowing between steps, allow powerful tools
    //

    /// Default allowed executables (built-in)
    static let defaultAllowedExecutables: Set<String> = [
        // Text processing
        "/bin/echo",
        "/bin/cat",
        "/usr/bin/head",
        "/usr/bin/tail",
        "/usr/bin/wc",
        "/usr/bin/sort",
        "/usr/bin/uniq",
        "/usr/bin/grep",
        "/usr/bin/sed",
        "/usr/bin/awk",
        "/usr/bin/tr",
        "/usr/bin/cut",
        "/usr/bin/paste",

        // JSON/data processing
        "/opt/homebrew/bin/jq",
        "/usr/local/bin/jq",

        // HTTP clients
        "/usr/bin/curl",

        // Developer CLIs - full access to configured auth/MCP
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "/usr/local/bin/npx",
        "/opt/homebrew/bin/npx",

        // Scripting
        "/usr/bin/python3",
        "/opt/homebrew/bin/python3",
        "/opt/homebrew/bin/node",
        "/usr/local/bin/node",

        // macOS automation
        "/usr/bin/osascript",
        "/usr/bin/open",
        "/usr/bin/pbcopy",
        "/usr/bin/pbpaste",

        // Utilities
        "/bin/date",
        "/usr/bin/base64",
        "/usr/bin/uuidgen",
        "/usr/bin/shasum",
        "/usr/bin/md5",
        "/usr/bin/file",
        "/usr/bin/which",
    ]

    /// UserDefaults key for custom allowed executables
    private static let customAllowedKey = "ShellStepCustomAllowedExecutables"

    /// Get all allowed executables (defaults + user-added)
    static var allowedExecutables: Set<String> {
        var allowed = defaultAllowedExecutables
        if let custom = UserDefaults.standard.stringArray(forKey: customAllowedKey) {
            allowed.formUnion(custom)
        }
        return allowed
    }

    /// Add a custom executable to the allowlist
    static func addAllowedExecutable(_ path: String) {
        var custom = UserDefaults.standard.stringArray(forKey: customAllowedKey) ?? []
        if !custom.contains(path) {
            custom.append(path)
            UserDefaults.standard.set(custom, forKey: customAllowedKey)
        }
    }

    /// Remove a custom executable from the allowlist
    static func removeAllowedExecutable(_ path: String) {
        var custom = UserDefaults.standard.stringArray(forKey: customAllowedKey) ?? []
        custom.removeAll { $0 == path }
        UserDefaults.standard.set(custom, forKey: customAllowedKey)
    }

    /// Get just the custom (user-added) executables
    static var customAllowedExecutables: [String] {
        UserDefaults.standard.stringArray(forKey: customAllowedKey) ?? []
    }

    /// Blocked executables - destructive or privilege escalation
    static let blockedExecutables: Set<String> = [
        // Destructive file operations
        "/bin/rm", "/bin/rmdir", "/bin/mv",
        // Privilege escalation
        "/usr/bin/sudo", "/usr/bin/su", "/usr/bin/doas",
        // Permission changes
        "/bin/chmod", "/usr/sbin/chown",
        // Process control
        "/bin/kill", "/usr/bin/killall",
        // Raw shells (use specific tools instead)
        "/bin/sh", "/bin/bash", "/bin/zsh", "/usr/bin/fish",
        // Network tools that could exfiltrate
        "/usr/bin/ssh", "/usr/bin/scp", "/usr/bin/sftp", "/usr/bin/ftp",
        "/usr/bin/nc", "/usr/bin/netcat",
        // Disk operations
        "/usr/sbin/diskutil", "/sbin/mount", "/sbin/umount",
    ]

    /// Check if executable is allowed
    func isExecutableAllowed() -> Bool {
        if Self.blockedExecutables.contains(executable) {
            return false
        }
        return Self.allowedExecutables.contains(executable)
    }

    /// Sanitize dynamic content (from LLM outputs, transcripts, etc.)
    /// This is applied to template-resolved values, NOT to the static config
    static func sanitizeContent(_ input: String) -> String {
        var result = input

        // Remove null bytes (can break C-based tools)
        result = result.replacingOccurrences(of: "\0", with: "")

        // Limit length to prevent DoS via massive inputs
        let maxLength = 500_000 // 500KB reasonable for transcript + LLM output
        if result.count > maxLength {
            result = String(result.prefix(maxLength))
        }

        return result
    }

    /// Detect potential injection attempts in content
    /// Returns warnings but doesn't block - logs for audit
    static func detectInjectionAttempts(_ input: String) -> [String] {
        var warnings: [String] = []

        let suspiciousPatterns: [(pattern: String, description: String)] = [
            ("$(", "Command substitution"),
            ("`", "Backtick execution"),
            ("&&", "Command chaining"),
            ("||", "Conditional execution"),
            ("; ", "Command separator"),
            ("| ", "Pipe to command"),
            ("> ", "Output redirection"),
            ("< ", "Input redirection"),
            ("#!/", "Shebang (script injection)"),
            ("import os", "Python os import"),
            ("subprocess", "Python subprocess"),
            ("child_process", "Node child_process"),
            ("eval(", "Eval execution"),
            ("exec(", "Exec execution"),
            ("__import__", "Python dynamic import"),
            ("require('child", "Node require child_process"),
        ]

        for (pattern, description) in suspiciousPatterns {
            if input.contains(pattern) {
                warnings.append("Detected '\(pattern)': \(description)")
            }
        }

        return warnings
    }

    /// Validate config (static check at workflow design time)
    func validate() -> (valid: Bool, errors: [String]) {
        var errors: [String] = []

        if !isExecutableAllowed() {
            if Self.blockedExecutables.contains(executable) {
                errors.append("'\(executable)' is blocked for security reasons.")
            } else {
                errors.append("'\(executable)' is not in allowlist. Add it in Settings > Workflows > Allowed Commands.")
            }
        }

        if timeout < 1 || timeout > 300 {
            errors.append("Timeout must be between 1 and 300 seconds")
        }

        if executable.isEmpty {
            errors.append("Executable path is required")
        }

        return (errors.isEmpty, errors)
    }

    /// Common CLI presets for quick setup
    enum Preset: String, CaseIterable {
        case custom = "Custom Command"
        case jq = "jq (JSON processor)"
        case curl = "curl (HTTP client)"
        case gh = "gh (GitHub CLI)"
        case claude = "claude (Claude CLI)"
        case python = "python3"
        case node = "node"
        case osascript = "osascript (AppleScript)"

        var defaultExecutable: String {
            switch self {
            case .custom: return "/bin/echo"
            case .jq: return "/opt/homebrew/bin/jq"
            case .curl: return "/usr/bin/curl"
            case .gh: return "/opt/homebrew/bin/gh"
            case .claude: return "/usr/local/bin/claude"
            case .python: return "/usr/bin/python3"
            case .node: return "/opt/homebrew/bin/node"
            case .osascript: return "/usr/bin/osascript"
            }
        }

        var description: String {
            switch self {
            case .custom: return "Run any allowed command-line tool"
            case .jq: return "Process and transform JSON data"
            case .curl: return "Make HTTP requests"
            case .gh: return "Interact with GitHub (issues, PRs, etc.)"
            case .claude: return "Run Claude AI from command line"
            case .python: return "Execute Python scripts"
            case .node: return "Execute Node.js scripts"
            case .osascript: return "Run AppleScript commands"
            }
        }

        var exampleConfig: ShellStepConfig {
            switch self {
            case .custom:
                return ShellStepConfig(executable: "/bin/echo", arguments: ["{{TRANSCRIPT}}"])
            case .jq:
                return ShellStepConfig(executable: "/opt/homebrew/bin/jq", arguments: ["-r", "."], stdin: "{{OUTPUT}}")
            case .curl:
                return ShellStepConfig(executable: "/usr/bin/curl", arguments: ["-s", "https://api.example.com"])
            case .gh:
                return ShellStepConfig(executable: "/opt/homebrew/bin/gh", arguments: ["issue", "list", "--limit", "5"])
            case .claude:
                return ShellStepConfig(
                    executable: "/usr/local/bin/claude",
                    arguments: [],
                    promptTemplate: """
                    You are a helpful assistant processing voice memo content.

                    Here is the transcript:
                    {{TRANSCRIPT}}

                    Please provide a clear, concise summary.
                    """
                )
            case .python:
                return ShellStepConfig(executable: "/usr/bin/python3", arguments: ["-c", "import sys; print(sys.stdin.read().upper())"], stdin: "{{TRANSCRIPT}}")
            case .node:
                return ShellStepConfig(executable: "/opt/homebrew/bin/node", arguments: ["-e", "console.log(require('fs').readFileSync(0, 'utf-8').toUpperCase())"], stdin: "{{TRANSCRIPT}}")
            case .osascript:
                return ShellStepConfig(executable: "/usr/bin/osascript", arguments: ["-e", "display notification \"{{TITLE}}\" with title \"Talkie\""])
            }
        }
    }
}

struct WebhookStepConfig: Codable {
    var url: String
    var method: HTTPMethod
    var headers: [String: String]
    var bodyTemplate: String?
    var includeTranscript: Bool
    var includeMetadata: Bool

    init(
        url: String,
        method: HTTPMethod = .post,
        headers: [String: String] = [:],
        bodyTemplate: String? = nil,
        includeTranscript: Bool = true,
        includeMetadata: Bool = true
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.bodyTemplate = bodyTemplate
        self.includeTranscript = includeTranscript
        self.includeMetadata = includeMetadata
    }

    enum HTTPMethod: String, Codable, CaseIterable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case patch = "PATCH"
        case delete = "DELETE"
    }
}

struct EmailStepConfig: Codable {
    var to: String
    var cc: String?
    var bcc: String?
    var subject: String
    var body: String
    var isHTML: Bool

    init(
        to: String,
        cc: String? = nil,
        bcc: String? = nil,
        subject: String,
        body: String,
        isHTML: Bool = false
    ) {
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
        self.isHTML = isHTML
    }
}

struct NotificationStepConfig: Codable {
    var title: String
    var body: String
    var sound: Bool
    var actionLabel: String?

    init(title: String, body: String, sound: Bool = true, actionLabel: String? = nil) {
        self.title = title
        self.body = body
        self.sound = sound
        self.actionLabel = actionLabel
    }
}

struct AppleNotesStepConfig: Codable {
    var folderName: String?
    var title: String
    var body: String
    var attachTranscript: Bool

    init(folderName: String? = nil, title: String, body: String, attachTranscript: Bool = true) {
        self.folderName = folderName
        self.title = title
        self.body = body
        self.attachTranscript = attachTranscript
    }
}

struct AppleRemindersStepConfig: Codable {
    var listName: String?
    var title: String
    var notes: String?
    var dueDate: String? // Template string like "{{NOW+1d}}" or ISO date
    var priority: ReminderPriority

    init(listName: String? = nil, title: String, notes: String? = nil, dueDate: String? = nil, priority: ReminderPriority = .none) {
        self.listName = listName
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.priority = priority
    }

    enum ReminderPriority: Int, Codable, CaseIterable {
        case none = 0
        case low = 9
        case medium = 5
        case high = 1

        var displayName: String {
            switch self {
            case .none: return "None"
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            }
        }
    }
}

struct AppleCalendarStepConfig: Codable {
    var calendarName: String?
    var title: String
    var notes: String?
    var startDate: String? // Template string
    var duration: Int // seconds
    var location: String?
    var isAllDay: Bool

    init(
        calendarName: String? = nil,
        title: String,
        notes: String? = nil,
        startDate: String? = nil,
        duration: Int = 3600,
        location: String? = nil,
        isAllDay: Bool = false
    ) {
        self.calendarName = calendarName
        self.title = title
        self.notes = notes
        self.startDate = startDate
        self.duration = duration
        self.location = location
        self.isAllDay = isAllDay
    }
}

struct ClipboardStepConfig: Codable {
    var content: String // Template string with {{OUTPUT}}, {{TRANSCRIPT}}, etc.

    init(content: String = "{{OUTPUT}}") {
        self.content = content
    }
}

struct SaveFileStepConfig: Codable {
    var filename: String // Can contain template variables
    var directory: String? // nil = use default output directory from settings, supports @aliases
    var content: String // Template string
    var appendIfExists: Bool

    init(filename: String, directory: String? = nil, content: String, appendIfExists: Bool = false) {
        self.filename = filename
        self.directory = directory
        self.content = content
        self.appendIfExists = appendIfExists
    }

    // MARK: - Default Output Directory Setting

    private static let defaultOutputDirectoryKey = "TalkieDefaultOutputDirectory"

    /// Get the default output directory (user-configurable)
    static var defaultOutputDirectory: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: defaultOutputDirectoryKey), !saved.isEmpty {
                return saved
            }
            // Default to ~/Documents/Talkie
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            return documents.appendingPathComponent("Talkie").path
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultOutputDirectoryKey)
        }
    }

    /// Ensure the default output directory exists
    static func ensureDefaultDirectoryExists() throws {
        let path = defaultOutputDirectory
        if !FileManager.default.fileExists(atPath: path) {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
    }

    // MARK: - Path Aliases

    private static let pathAliasesKey = "TalkiePathAliases"

    /// Get all defined path aliases (e.g., ["Obsidian": "/Users/x/Obsidian/Vault", "Notes": "/Users/x/Notes"])
    static var pathAliases: [String: String] {
        get {
            UserDefaults.standard.dictionary(forKey: pathAliasesKey) as? [String: String] ?? [:]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: pathAliasesKey)
        }
    }

    /// Add or update a path alias
    static func setPathAlias(_ name: String, path: String) {
        var aliases = pathAliases
        aliases[name] = path
        pathAliases = aliases
    }

    /// Remove a path alias
    static func removePathAlias(_ name: String) {
        var aliases = pathAliases
        aliases.removeValue(forKey: name)
        pathAliases = aliases
    }

    /// Resolve a path that may contain an @alias (e.g., "@Obsidian/notes" -> "/Users/x/Vault/notes")
    static func resolvePathAlias(_ path: String) -> String {
        // Check if path starts with @
        guard path.hasPrefix("@") else { return path }

        // Extract alias name (everything after @ until / or end)
        let withoutAt = String(path.dropFirst())
        let components = withoutAt.split(separator: "/", maxSplits: 1)
        let aliasName = String(components.first ?? "")
        let remainder = components.count > 1 ? "/" + components[1] : ""

        // Look up alias
        if let resolvedBase = pathAliases[aliasName] {
            return resolvedBase + remainder
        }

        // Alias not found, return original
        return path
    }
}

struct ConditionalStepConfig: Codable {
    var condition: String // Expression like "{{OUTPUT}} contains 'urgent'"
    var thenSteps: [UUID] // Step IDs to run if true
    var elseSteps: [UUID] // Step IDs to run if false

    init(condition: String, thenSteps: [UUID] = [], elseSteps: [UUID] = []) {
        self.condition = condition
        self.thenSteps = thenSteps
        self.elseSteps = elseSteps
    }
}

struct TransformStepConfig: Codable {
    var operation: TransformOperation
    var parameters: [String: String]

    init(operation: TransformOperation, parameters: [String: String] = [:]) {
        self.operation = operation
        self.parameters = parameters
    }

    enum TransformOperation: String, Codable, CaseIterable {
        case extractJSON = "Extract JSON"
        case extractList = "Extract List"
        case formatMarkdown = "Format as Markdown"
        case summarize = "Truncate/Summarize"
        case regex = "Regex Extract"
        case template = "Apply Template"

        var description: String {
            switch self {
            case .extractJSON: return "Parse and extract JSON from text"
            case .extractList: return "Convert text to bullet list"
            case .formatMarkdown: return "Convert to Markdown format"
            case .summarize: return "Truncate to length"
            case .regex: return "Extract using regex pattern"
            case .template: return "Apply custom template"
            }
        }
    }
}

// MARK: - Step Condition

struct StepCondition: Codable {
    var expression: String // e.g., "{{PREVIOUS_OUTPUT}} != ''"
    var skipOnFail: Bool

    init(expression: String, skipOnFail: Bool = true) {
        self.expression = expression
        self.skipOnFail = skipOnFail
    }
}

// MARK: - Workflow Color

enum WorkflowColor: String, Codable, CaseIterable {
    case blue, green, orange, purple, yellow, red, pink, cyan, indigo, mint, teal

    var displayName: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .yellow: return .yellow
        case .red: return .red
        case .pink: return .pink
        case .cyan: return .cyan
        case .indigo: return .indigo
        case .mint: return .mint
        case .teal: return .teal
        }
    }
}

// MARK: - Workflow Manager

@MainActor
class WorkflowManager: ObservableObject {
    static let shared = WorkflowManager()

    @Published var workflows: [WorkflowDefinition] = []

    private let userDefaultsKey = "workflows_v2"

    private init() {
        loadWorkflows()
    }

    func addWorkflow(_ workflow: WorkflowDefinition) {
        workflows.append(workflow)
        saveWorkflows()
    }

    func updateWorkflow(_ workflow: WorkflowDefinition) {
        if let index = workflows.firstIndex(where: { $0.id == workflow.id }) {
            workflows[index] = workflow
            saveWorkflows()
        }
    }

    func deleteWorkflow(_ workflow: WorkflowDefinition) {
        workflows.removeAll { $0.id == workflow.id }
        saveWorkflows()
    }

    func duplicateWorkflow(_ workflow: WorkflowDefinition) -> WorkflowDefinition {
        var duplicate = workflow
        duplicate = WorkflowDefinition(
            id: UUID(),
            name: "\(workflow.name) Copy",
            description: workflow.description,
            icon: workflow.icon,
            color: workflow.color,
            steps: workflow.steps,
            isEnabled: workflow.isEnabled,
            createdAt: Date(),
            modifiedAt: Date()
        )
        workflows.append(duplicate)
        saveWorkflows()
        return duplicate
    }

    private func saveWorkflows() {
        if let data = try? JSONEncoder().encode(workflows) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    private func loadWorkflows() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let savedWorkflows = try? JSONDecoder().decode([WorkflowDefinition].self, from: data),
           !savedWorkflows.isEmpty {
            workflows = savedWorkflows
        } else {
            // Initialize with default workflows
            workflows = WorkflowDefinition.defaultWorkflows
            saveWorkflows()
        }
    }
}
