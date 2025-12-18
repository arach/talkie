//
//  WorkflowDefinition.swift
//  Talkie macOS
//
//  Workflow definition and management system
//

import Foundation
import os
import SwiftUI

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Workflow")
// MARK: - Workflow Definition

struct WorkflowDefinition: Identifiable, Codable, Hashable {
    static func == (lhs: WorkflowDefinition, rhs: WorkflowDefinition) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    let id: UUID
    var name: String
    var description: String
    var icon: String
    var color: WorkflowColor
    var steps: [WorkflowStep]
    var isEnabled: Bool
    var isPinned: Bool  // Pinned workflows appear in iOS MAC ACTIONS section
    var autoRun: Bool   // Run automatically on sync (for trigger workflows)
    var autoRunOrder: Int // Execution order for multiple auto-run workflows
    var createdAt: Date
    var modifiedAt: Date

    /// Returns true if this is a system workflow (Transcribe, Hey Talkie)
    var isSystem: Bool {
        id == WorkflowDefinition.heyTalkieWorkflowId ||
        id == WorkflowDefinition.systemTranscribeWorkflowId
    }

    /// Returns true if this workflow starts with a transcription step
    /// Used to determine whether to show untranscribed or transcribed memos in the picker
    var startsWithTranscribe: Bool {
        guard let firstStep = steps.first else { return false }
        return firstStep.type == .transcribe
    }

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        icon: String = "wand.and.stars",
        color: WorkflowColor = .blue,
        steps: [WorkflowStep] = [],
        isEnabled: Bool = true,
        isPinned: Bool = false,
        autoRun: Bool = false,
        autoRunOrder: Int = 0,
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
        self.isPinned = isPinned
        self.autoRun = autoRun
        self.autoRunOrder = autoRunOrder
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    // Custom decoder to handle migration from workflows saved without newer fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        icon = try container.decode(String.self, forKey: .icon)
        color = try container.decode(WorkflowColor.self, forKey: .color)
        steps = try container.decode([WorkflowStep].self, forKey: .steps)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        autoRun = try container.decodeIfPresent(Bool.self, forKey: .autoRun) ?? false
        autoRunOrder = try container.decodeIfPresent(Int.self, forKey: .autoRunOrder) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, icon, color, steps, isEnabled, isPinned, autoRun, autoRunOrder, createdAt, modifiedAt
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

    // MARK: - Hey Talkie Auto-Run Workflow

    /// Fixed UUID for Hey Talkie workflow (stable across updates)
    static let heyTalkieWorkflowId = UUID(uuidString: "00000000-7A1C-1E00-0000-000000000001")!

    /// Default "Hey Talkie" workflow - detects voice commands and routes to workflows
    static let heyTalkie = WorkflowDefinition(
        id: heyTalkieWorkflowId,
        name: "Hey Talkie",
        description: "Detects voice commands and routes to appropriate workflows",
        icon: "waveform.badge.mic",
        color: .purple,
        steps: [
            // Step 1: Trigger detection - looks for "hey talkie" at end of transcript
            WorkflowStep(
                type: .trigger,
                config: .trigger(TriggerStepConfig(
                    phrases: ["hey talkie"],
                    caseSensitive: false,
                    searchLocation: .end,
                    contextWindowSize: 200,
                    stopIfNoMatch: true
                )),
                outputKey: "trigger"
            ),
            // Step 2: Intent extraction - parse what the user wants to do
            WorkflowStep(
                type: .intentExtract,
                config: .intentExtract(IntentExtractStepConfig(
                    inputKey: "{{trigger}}",
                    extractionMethod: .hybrid,
                    recognizedIntents: IntentDefinition.defaults
                )),
                outputKey: "intents"
            ),
            // Step 3: Execute mapped workflows for each detected intent
            WorkflowStep(
                type: .executeWorkflows,
                config: .executeWorkflows(ExecuteWorkflowsStepConfig(
                    intentsKey: "{{intents}}",
                    stopOnError: false,
                    parallel: false
                )),
                outputKey: "results"
            )
        ],
        isEnabled: true,
        isPinned: false,
        autoRun: true,
        autoRunOrder: 1  // Runs after system transcription
    )

    // MARK: - System Transcribe Workflow

    /// Fixed UUID for system Transcribe workflow (stable across updates)
    static let systemTranscribeWorkflowId = UUID(uuidString: "00000000-7A1C-1E00-0000-000000000002")!

    /// System "Transcribe" workflow - uses Apple Speech (no download required)
    /// Runs first on every new memo to ensure transcription exists
    static let systemTranscribe = WorkflowDefinition(
        id: systemTranscribeWorkflowId,
        name: "Transcribe",
        description: "On-device transcription using Apple Speech (no download required)",
        icon: "waveform.and.mic",
        color: .blue,
        steps: [
            WorkflowStep(
                type: .transcribe,
                config: .transcribe(TranscribeStepConfig(
                    qualityTier: .fast,  // Apple Speech - instant, no download
                    fallbackStrategy: .none,
                    overwriteExisting: false,  // Don't overwrite existing transcripts
                    saveAsVersion: true
                )),
                outputKey: "transcript"
            )
        ],
        isEnabled: true,
        isPinned: false,
        autoRun: true,
        autoRunOrder: 0  // Runs FIRST - before Hey Talkie and other workflows
    )

    // MARK: - Brain Dump Processor (Canonical Test Workflow)

    /// Comprehensive workflow for testing WFKit visualization
    /// Processes freeform brainstorms into structured ideas with actions
    static let brainDumpProcessor = WorkflowDefinition(
        id: UUID(uuidString: "00000000-7E57-F100-0000-000000000001")!,
        name: "Brain Dump Processor",
        description: "Capture freeform brainstorms, extract ideas, create next actions, and save to your idea garden",
        icon: "brain.head.profile",
        color: .purple,
        steps: [
            // Step 1: Transcribe the voice brainstorm locally
            WorkflowStep(
                id: UUID(uuidString: "57E90001-0000-0000-0000-000000000001")!,
                type: .transcribe,
                config: .transcribe(TranscribeStepConfig(
                    qualityTier: .balanced,  // Whisper Small via TalkieEngine
                    fallbackStrategy: .automatic,
                    overwriteExisting: false,
                    saveAsVersion: true
                )),
                outputKey: "transcript"
            ),
            // Step 2: Extract distinct ideas and categorize them
            WorkflowStep(
                id: UUID(uuidString: "57E90002-0000-0000-0000-000000000002")!,
                type: .llm,
                config: .llm(LLMStepConfig(
                    provider: .gemini,
                    modelId: "gemini-2.0-flash",
                    prompt: """
                    You are a personal thinking partner. Analyze this voice brainstorm and extract the distinct ideas.

                    Transcript:
                    {{transcript}}

                    For each idea found, categorize it as: project, someday, reference, or actionable.

                    Return as JSON:
                    {
                      "ideas": [{"title": "short title", "description": "1-2 sentences", "category": "project|someday|reference|actionable"}],
                      "nextActions": ["specific next step to take"],
                      "connections": "any interesting connections between ideas"
                    }
                    """,
                    systemPrompt: "You help people capture and organize their creative thinking. Be concise but insightful.",
                    temperature: 0.5,
                    maxTokens: 2048
                )),
                outputKey: "extracted"
            ),
            // Step 3: Parse the JSON output
            WorkflowStep(
                id: UUID(uuidString: "57E90003-0000-0000-0000-000000000003")!,
                type: .transform,
                config: .transform(TransformStepConfig(
                    operation: .extractJSON,
                    parameters: ["path": "$", "fallback": "{\"ideas\": [], \"nextActions\": []}"]
                )),
                outputKey: "parsed"
            ),
            // Step 4: Check if there are actionable next steps
            WorkflowStep(
                id: UUID(uuidString: "57E90004-0000-0000-0000-000000000004")!,
                type: .conditional,
                config: .conditional(ConditionalStepConfig(
                    condition: "{{parsed.nextActions.length}} > 0",
                    thenSteps: [UUID(uuidString: "57E90005-0000-0000-0000-000000000005")!],
                    elseSteps: []
                )),
                outputKey: "hasActions"
            ),
            // Step 5: Create reminder for first next action (runs if conditional true)
            WorkflowStep(
                id: UUID(uuidString: "57E90005-0000-0000-0000-000000000005")!,
                type: .appleReminders,
                config: .appleReminders(AppleRemindersStepConfig(
                    listName: "Inbox",
                    title: "{{parsed.nextActions[0]}}",
                    notes: "From brainstorm: {{TITLE}}\n\nRelated ideas: {{parsed.ideas[0].title}}",
                    dueDate: "{{NOW+1d}}",
                    priority: .medium
                )),
                outputKey: "reminder"
            ),
            // Step 6: Use jq to format ideas for display
            WorkflowStep(
                id: UUID(uuidString: "57E90006-0000-0000-0000-000000000006")!,
                type: .shell,
                config: .shell(ShellStepConfig(
                    executable: "/opt/homebrew/bin/jq",
                    arguments: ["-r", ".ideas | map(\"- **\" + .title + \"** (\" + .category + \"): \" + .description) | join(\"\\n\")"],
                    stdin: "{{extracted}}",
                    timeout: 10
                )),
                outputKey: "formattedIdeas"
            ),
            // Step 7: Polish into a nice note format
            WorkflowStep(
                id: UUID(uuidString: "57E90007-0000-0000-0000-000000000007")!,
                type: .llm,
                config: .llm(LLMStepConfig(
                    provider: .gemini,
                    modelId: "gemini-2.0-flash",
                    prompt: """
                    Format this into a clean markdown note for my idea garden:

                    Ideas:
                    {{formattedIdeas}}

                    Connections:
                    {{parsed.connections}}

                    Next Actions:
                    {{parsed.nextActions}}

                    Create a brief, scannable note with emoji headers. Keep it concise.
                    """,
                    temperature: 0.3,
                    maxTokens: 1024
                )),
                outputKey: "polished"
            ),
            // Step 8: Use OpenAI to research and expand on the ideas
            WorkflowStep(
                id: UUID(uuidString: "57E90008-0000-0000-0000-000000000008")!,
                type: .llm,
                config: .llm(LLMStepConfig(
                    provider: .openai,
                    modelId: "gpt-5.1",
                    prompt: """
                    Based on these brainstormed ideas, suggest:
                    1. Related concepts worth exploring
                    2. Potential connections to other fields
                    3. One actionable experiment to test the most promising idea

                    Ideas:
                    {{parsed.ideas}}

                    Be concise and practical. Focus on sparking further thinking.
                    """,
                    systemPrompt: "You are a creative thinking partner who helps expand ideas with cross-disciplinary insights.",
                    temperature: 0.7,
                    maxTokens: 1024
                )),
                outputKey: "research"
            ),
            // Step 9: Save markdown file to Obsidian/Notion vault
            WorkflowStep(
                id: UUID(uuidString: "57E90009-0000-0000-0000-000000000009")!,
                type: .saveFile,
                config: .saveFile(SaveFileStepConfig(
                    filename: "{{DATE}}-{{TITLE}}.md",
                    directory: "@Obsidian/Ideas",
                    content: """
                    ---
                    created: {{DATE}}
                    tags: [braindump, ideas]
                    ---

                    # {{TITLE}}

                    {{polished}}

                    ## 🔬 Research Notes
                    {{research}}

                    ---
                    *Captured via Talkie*
                    """,
                    appendIfExists: false
                )),
                outputKey: "savedFile"
            ),
            // Step 10: Notify iPhone that ideas were captured
            WorkflowStep(
                id: UUID(uuidString: "57E90010-0000-0000-0000-000000000010")!,
                type: .iOSPush,
                config: .iOSPush(iOSPushStepConfig(
                    title: "💡 Ideas Captured",
                    body: "{{parsed.ideas.length}} ideas saved to your garden",
                    sound: true,
                    includeOutput: false
                )),
                outputKey: "notified"
            )
        ],
        isEnabled: true,
        isPinned: false,
        autoRun: false
    )

    // MARK: - Default Workflows (Initial set)
    static let defaultWorkflows = [summarize, extractTasks, keyInsights, brainDumpProcessor]
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
        case iOSPush = "Notify iPhone"
        case appleNotes = "Add to Apple Notes"
        case appleReminders = "Create Reminder"
        case appleCalendar = "Create Calendar Event"
        case clipboard = "Copy to Clipboard"
        case saveFile = "Save to File"
        case conditional = "Conditional Branch"
        case transform = "Transform Data"
        case transcribe = "Transcribe Audio"  // Local speech-to-text
        case speak = "Speak Response"  // Text-to-speech reply (Walkie-Talkie mode!)
        // Trigger-related step types
        case trigger = "Trigger Detection"
        case intentExtract = "Extract Intents"
        case executeWorkflows = "Execute Workflows"

        var icon: String {
            switch self {
            case .llm: return "brain"
            case .shell: return "terminal"
            case .webhook: return "arrow.up.forward.app"
            case .email: return "envelope"
            case .notification: return "bell.badge"
            case .iOSPush: return "iphone.badge.play"
            case .appleNotes: return "note.text"
            case .appleReminders: return "checklist"
            case .appleCalendar: return "calendar.badge.plus"
            case .clipboard: return "doc.on.clipboard"
            case .saveFile: return "doc.badge.plus"
            case .conditional: return "arrow.triangle.branch"
            case .transform: return "wand.and.rays"
            case .transcribe: return "waveform.and.mic"
            case .speak: return "speaker.wave.2"
            case .trigger: return "waveform.badge.mic"
            case .intentExtract: return "text.magnifyingglass"
            case .executeWorkflows: return "arrow.triangle.2.circlepath"
            }
        }

        var description: String {
            switch self {
            case .llm: return "Process with AI model"
            case .shell: return "Execute CLI command"
            case .webhook: return "Send data to URL"
            case .email: return "Compose and send email"
            case .notification: return "Show system notification"
            case .iOSPush: return "Send push notification to iPhone"
            case .appleNotes: return "Save to Apple Notes"
            case .appleReminders: return "Add to Reminders app"
            case .appleCalendar: return "Add calendar event"
            case .clipboard: return "Copy result to clipboard"
            case .saveFile: return "Save to local file"
            case .conditional: return "Branch based on condition"
            case .transform: return "Transform or filter data"
            case .transcribe: return "Convert audio to text locally"
            case .speak: return "Speak text aloud (Walkie-Talkie reply)"
            case .trigger: return "Detect keywords to trigger workflow"
            case .intentExtract: return "Extract intents from text"
            case .executeWorkflows: return "Run workflows for each intent"
            }
        }

        var category: StepCategory {
            switch self {
            case .llm: return .ai
            case .shell: return .integration
            case .webhook: return .integration
            case .email: return .communication
            case .notification, .iOSPush: return .communication
            case .appleNotes, .appleReminders, .appleCalendar: return .apple
            case .clipboard, .saveFile: return .output
            case .conditional, .transform: return .logic
            case .transcribe: return .ai
            case .speak: return .communication
            case .trigger, .intentExtract, .executeWorkflows: return .trigger
            }
        }

        /// Display name for headers (shorter than rawValue for some)
        var displayName: String {
            switch self {
            case .llm: return "LLM Generation"
            case .shell: return "Shell Command"
            case .webhook: return "Webhook"
            case .email: return "Email"
            case .notification: return "Notification"
            case .iOSPush: return "iOS Push"
            case .appleNotes: return "Apple Notes"
            case .appleReminders: return "Reminder"
            case .appleCalendar: return "Calendar Event"
            case .clipboard: return "Clipboard"
            case .saveFile: return "Save File"
            case .conditional: return "Conditional"
            case .transform: return "Transform"
            case .transcribe: return "Transcribe"
            case .speak: return "Speak"
            case .trigger: return "Trigger"
            case .intentExtract: return "Extract Intents"
            case .executeWorkflows: return "Execute Workflows"
            }
        }

        /// Theme color for step type
        var themeColor: Color {
            switch self.category {
            case .ai: return .purple
            case .communication: return .blue
            case .apple: return .pink
            case .integration: return .orange
            case .output: return .green
            case .logic: return .yellow
            case .trigger: return .cyan
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
        case trigger = "Triggers"

        var icon: String {
            switch self {
            case .ai: return "cpu"
            case .communication: return "bubble.left.and.bubble.right"
            case .apple: return "apple.logo"
            case .integration: return "puzzlepiece.extension"
            case .output: return "square.and.arrow.down"
            case .logic: return "gearshape.2"
            case .trigger: return "waveform.badge.mic"
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
    case iOSPush(iOSPushStepConfig)
    case appleNotes(AppleNotesStepConfig)
    case appleReminders(AppleRemindersStepConfig)
    case appleCalendar(AppleCalendarStepConfig)
    case clipboard(ClipboardStepConfig)
    case saveFile(SaveFileStepConfig)
    case conditional(ConditionalStepConfig)
    case transform(TransformStepConfig)
    case transcribe(TranscribeStepConfig)
    case speak(SpeakStepConfig)
    // Trigger-related configs
    case trigger(TriggerStepConfig)
    case intentExtract(IntentExtractStepConfig)
    case executeWorkflows(ExecuteWorkflowsStepConfig)

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
        case .iOSPush:
            return .iOSPush(iOSPushStepConfig(title: "{{WORKFLOW_NAME}} Complete", body: "Finished processing {{TITLE}}"))
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
        case .transcribe:
            return .transcribe(TranscribeStepConfig())
        case .speak:
            return .speak(SpeakStepConfig())
        case .trigger:
            return .trigger(TriggerStepConfig())
        case .intentExtract:
            return .intentExtract(IntentExtractStepConfig())
        case .executeWorkflows:
            return .executeWorkflows(ExecuteWorkflowsStepConfig())
        }
    }
}

// MARK: - LLM Cost Tier

/// Cost tier for LLM calls - controls expense/capability tradeoff
enum LLMCostTier: String, Codable, CaseIterable {
    case budget     // Cheapest, fastest - simple extraction, formatting
    case balanced   // Good cost/capability ratio (DEFAULT)
    case capable    // Higher capability - complex reasoning, research

    var displayName: String {
        switch self {
        case .budget: return "Budget"
        case .balanced: return "Balanced"
        case .capable: return "Capable"
        }
    }

    var description: String {
        switch self {
        case .budget: return "Fast & cheap - simple tasks"
        case .balanced: return "Good balance - most workflows"
        case .capable: return "Higher capability - complex reasoning"
        }
    }

    var icon: String {
        switch self {
        case .budget: return "leaf"
        case .balanced: return "scale.3d"
        case .capable: return "brain"
        }
    }

    /// Approximate relative cost multiplier (budget = 1x)
    var costMultiplier: Double {
        switch self {
        case .budget: return 1.0
        case .balanced: return 5.0
        case .capable: return 20.0
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
                // Budget tier - Flash models are very cheap
                WorkflowModelOption(id: "gemini-1.5-flash-latest", name: "Gemini 1.5 Flash", contextWindow: 1000000,
                                   costTier: .budget, inputCostPer1M: 0.075, outputCostPer1M: 0.30),
                WorkflowModelOption(id: "gemini-2.0-flash", name: "Gemini 2.0 Flash", contextWindow: 1000000,
                                   costTier: .balanced, inputCostPer1M: 0.10, outputCostPer1M: 0.40),
                // Capable tier - Pro models for complex tasks
                WorkflowModelOption(id: "gemini-1.5-pro-latest", name: "Gemini 1.5 Pro", contextWindow: 2000000,
                                   costTier: .capable, inputCostPer1M: 1.25, outputCostPer1M: 5.00),
            ]
        case .openai:
            return [
                // Budget tier - Mini models
                WorkflowModelOption(id: "gpt-4.1-mini", name: "GPT-4.1 Mini", contextWindow: 1000000,
                                   costTier: .budget, inputCostPer1M: 0.15, outputCostPer1M: 0.60, maxOutputTokens: 32768),
                // Balanced tier - Standard models
                WorkflowModelOption(id: "gpt-4.1", name: "GPT-4.1", contextWindow: 1000000,
                                   costTier: .balanced, inputCostPer1M: 2.00, outputCostPer1M: 8.00, maxOutputTokens: 32768),
                WorkflowModelOption(id: "gpt-5-mini", name: "GPT-5 Mini", contextWindow: 400000,
                                   costTier: .balanced, inputCostPer1M: 1.50, outputCostPer1M: 6.00, maxOutputTokens: 32768),
                // Capable tier - Flagship models
                WorkflowModelOption(id: "gpt-5.1", name: "GPT-5.1", contextWindow: 128000,
                                   costTier: .capable, inputCostPer1M: 5.00, outputCostPer1M: 15.00, maxOutputTokens: 32768),
                WorkflowModelOption(id: "gpt-5", name: "GPT-5", contextWindow: 400000,
                                   costTier: .capable, inputCostPer1M: 5.00, outputCostPer1M: 15.00, maxOutputTokens: 32768),
                // Reasoning models (special tier)
                WorkflowModelOption(id: "o4-mini", name: "o4-mini (Reasoning)", contextWindow: 200000,
                                   costTier: .capable, inputCostPer1M: 1.10, outputCostPer1M: 4.40, maxOutputTokens: 100000),
            ]
        case .anthropic:
            return [
                // Budget tier - Haiku
                WorkflowModelOption(id: "claude-3-5-haiku-20241022", name: "Claude 3.5 Haiku", contextWindow: 200000,
                                   costTier: .budget, inputCostPer1M: 0.80, outputCostPer1M: 4.00, maxOutputTokens: 8192),
                // Balanced tier - Sonnet
                WorkflowModelOption(id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", contextWindow: 200000,
                                   costTier: .balanced, inputCostPer1M: 3.00, outputCostPer1M: 15.00, maxOutputTokens: 8192),
                WorkflowModelOption(id: "claude-sonnet-4-20250514", name: "Claude Sonnet 4", contextWindow: 200000,
                                   costTier: .balanced, inputCostPer1M: 3.00, outputCostPer1M: 15.00, maxOutputTokens: 8192),
                // Capable tier - Opus
                WorkflowModelOption(id: "claude-3-opus-20240229", name: "Claude 3 Opus", contextWindow: 200000,
                                   costTier: .capable, inputCostPer1M: 15.00, outputCostPer1M: 75.00, maxOutputTokens: 4096),
            ]
        case .groq:
            // Groq is free/very cheap - all budget tier
            return [
                WorkflowModelOption(id: "llama-3.1-8b-instant", name: "Llama 3.1 8B Instant", contextWindow: 128000,
                                   costTier: .budget, inputCostPer1M: 0.05, outputCostPer1M: 0.08),
                WorkflowModelOption(id: "gemma2-9b-it", name: "Gemma 2 9B", contextWindow: 8192,
                                   costTier: .budget, inputCostPer1M: 0.20, outputCostPer1M: 0.20),
                WorkflowModelOption(id: "mixtral-8x7b-32768", name: "Mixtral 8x7B", contextWindow: 32768,
                                   costTier: .balanced, inputCostPer1M: 0.24, outputCostPer1M: 0.24),
                WorkflowModelOption(id: "llama-3.3-70b-versatile", name: "Llama 3.3 70B", contextWindow: 128000,
                                   costTier: .capable, inputCostPer1M: 0.59, outputCostPer1M: 0.79),
            ]
        case .mlx:
            // Local models - no API cost, tier based on capability
            return [
                WorkflowModelOption(id: "mlx-community/Llama-3.2-1B-Instruct-4bit", name: "Llama 3.2 1B", contextWindow: 8192,
                                   costTier: .budget),
                WorkflowModelOption(id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit", name: "Qwen 2.5 1.5B", contextWindow: 8192,
                                   costTier: .budget),
                WorkflowModelOption(id: "mlx-community/Llama-3.2-3B-Instruct-4bit", name: "Llama 3.2 3B", contextWindow: 8192,
                                   costTier: .balanced),
                WorkflowModelOption(id: "mlx-community/Qwen2.5-3B-Instruct-4bit", name: "Qwen 2.5 3B", contextWindow: 8192,
                                   costTier: .balanced),
                WorkflowModelOption(id: "mlx-community/Mistral-7B-Instruct-v0.3-4bit", name: "Mistral 7B", contextWindow: 32768,
                                   costTier: .capable),
            ]
        }
    }

    var defaultModel: WorkflowModelOption {
        models.first ?? WorkflowModelOption(id: "unknown", name: "Unknown", contextWindow: 4096, costTier: .budget)
    }

    /// Get the recommended model for a given cost tier
    /// Uses the model's declared costTier to find the best match
    func model(for tier: LLMCostTier) -> WorkflowModelOption {
        // First try to find exact tier match
        if let match = models.first(where: { $0.costTier == tier }) {
            return match
        }
        // Fall back to closest available tier
        switch tier {
        case .budget:
            // If no budget, try balanced
            return models.first(where: { $0.costTier == .balanced }) ?? defaultModel
        case .balanced:
            // If no balanced, prefer budget over capable
            return models.first(where: { $0.costTier == .budget })
                ?? models.first(where: { $0.costTier == .capable })
                ?? defaultModel
        case .capable:
            // If no capable, try balanced
            return models.first(where: { $0.costTier == .balanced }) ?? defaultModel
        }
    }

    /// Model ID for a given cost tier
    func modelId(for tier: LLMCostTier) -> String {
        model(for: tier).id
    }

    /// Get all models for a given cost tier
    func models(for tier: LLMCostTier) -> [WorkflowModelOption] {
        models.filter { $0.costTier == tier }
    }
}

struct WorkflowModelOption: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let contextWindow: Int
    let costTier: LLMCostTier          // Which cost tier this model belongs to
    let inputCostPer1M: Double?        // Cost per 1M input tokens (USD), nil if free/unknown
    let outputCostPer1M: Double?       // Cost per 1M output tokens (USD), nil if free/unknown
    let maxOutputTokens: Int?          // Max output tokens, nil if same as context

    init(
        id: String,
        name: String,
        contextWindow: Int,
        costTier: LLMCostTier = .balanced,
        inputCostPer1M: Double? = nil,
        outputCostPer1M: Double? = nil,
        maxOutputTokens: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.contextWindow = contextWindow
        self.costTier = costTier
        self.inputCostPer1M = inputCostPer1M
        self.outputCostPer1M = outputCostPer1M
        self.maxOutputTokens = maxOutputTokens
    }

    var formattedContext: String {
        if contextWindow >= 1000000 {
            return "\(contextWindow / 1000000)M"
        } else if contextWindow >= 1000 {
            return "\(contextWindow / 1000)K"
        }
        return "\(contextWindow)"
    }

    /// Formatted cost string for display (e.g., "$0.15/$0.60")
    var formattedCost: String? {
        guard let input = inputCostPer1M, let output = outputCostPer1M else { return nil }
        return String(format: "$%.2f/$%.2f", input, output)
    }

    /// Estimated cost for a typical workflow step (1K input, 500 output tokens)
    var estimatedStepCost: Double? {
        guard let input = inputCostPer1M, let output = outputCostPer1M else { return nil }
        return (input * 0.001) + (output * 0.0005)  // 1K in, 500 out
    }
}

// MARK: - Step-Specific Configurations

struct LLMStepConfig: Codable {
    var provider: WorkflowLLMProvider?  // nil = auto-route based on available providers
    var modelId: String?                // Explicit model ID (used if costTier is nil and autoRoute is false)
    var costTier: LLMCostTier?          // If set, overrides modelId with tier-based selection
    var autoRoute: Bool                 // If true, picks best available provider at runtime
    var prompt: String
    var systemPrompt: String?
    var temperature: Double
    var maxTokens: Int
    var topP: Double

    init(
        provider: WorkflowLLMProvider? = nil,
        modelId: String? = nil,
        costTier: LLMCostTier? = nil,
        autoRoute: Bool = true,         // Default: auto-route for flexibility
        prompt: String,
        systemPrompt: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 1024,
        topP: Double = 0.9
    ) {
        self.autoRoute = autoRoute
        self.costTier = costTier
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP

        // If explicit provider given, use it
        if let provider = provider {
            self.provider = provider
            if let tier = costTier {
                self.modelId = provider.modelId(for: tier)
            } else {
                self.modelId = modelId ?? provider.defaultModel.id
            }
        } else {
            // Auto-route mode - provider/model resolved at runtime
            self.provider = nil
            self.modelId = modelId
        }
    }

    /// Resolve the effective provider and model for execution
    /// - Parameters:
    ///   - availableProviders: Providers that have API keys configured
    ///   - globalTier: The global cost tier setting (from SettingsManager)
    /// - Returns: Tuple of (provider, modelId) to use, or nil if no provider available
    func resolveProviderAndModel(
        availableProviders: Set<WorkflowLLMProvider>,
        globalTier: LLMCostTier
    ) -> (provider: WorkflowLLMProvider, modelId: String)? {
        let tier = costTier ?? globalTier

        // If explicit provider specified, use it (even if not in available list - will fail at runtime)
        if let explicitProvider = provider {
            // Use explicitly selected model if set, otherwise fall back to tier default
            let resolvedModelId = modelId ?? explicitProvider.modelId(for: tier)
            return (explicitProvider, resolvedModelId)
        }

        // Auto-route: pick best available provider for this tier
        // Priority: Groq (free) > Gemini (cheap) > OpenAI > Anthropic
        let priorityOrder: [WorkflowLLMProvider] = [.groq, .gemini, .openai, .anthropic, .mlx]

        for candidate in priorityOrder {
            if availableProviders.contains(candidate) {
                return (candidate, candidate.modelId(for: tier))
            }
        }

        // No provider available
        return nil
    }

    /// Get the effective model option for a specific provider/tier
    func effectiveModel(provider: WorkflowLLMProvider, globalTier: LLMCostTier) -> WorkflowModelOption {
        let tier = costTier ?? globalTier
        return provider.model(for: tier)
    }

    var selectedModel: WorkflowModelOption? {
        guard let provider = provider, let modelId = modelId else { return nil }
        return provider.models.first { $0.id == modelId }
    }

    /// Get the display name for the current configuration
    var displayName: String {
        if autoRoute {
            if let tier = costTier {
                return "Auto (\(tier.displayName))"
            }
            return "Auto (uses global tier)"
        }
        if let tier = costTier {
            return tier.displayName
        }
        return selectedModel?.name ?? modelId ?? "Unknown"
    }

    /// Estimated cost for this step (nil if auto-routing or no explicit model)
    var estimatedCost: Double? {
        selectedModel?.estimatedStepCost
    }

    /// Whether this step uses auto-routing (provider-agnostic)
    var isAutoRouted: Bool {
        autoRoute && provider == nil
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
        "/opt/homebrew/Cellar/node/24.1.0/bin/node",  // Direct Cellar path for sandbox
        "/usr/local/bin/node",
        "/Users/arach/.bun/bin/bun",  // Bun runtime (faster than Node)

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

/// Configuration for sending push notifications to the iOS app via CloudKit
/// When this step executes, it saves a PushNotification record to CloudKit
/// which triggers a CKQuerySubscription on iOS to display the notification
struct iOSPushStepConfig: Codable {
    var title: String           // Notification title (supports {{WORKFLOW_NAME}}, {{TITLE}}, etc.)
    var body: String            // Notification body (supports template variables)
    var sound: Bool             // Play notification sound on iOS
    var includeOutput: Bool     // Include the workflow output in the notification data

    init(
        title: String = "Workflow Complete",
        body: String = "{{WORKFLOW_NAME}} finished processing",
        sound: Bool = true,
        includeOutput: Bool = false
    ) {
        self.title = title
        self.body = body
        self.sound = sound
        self.includeOutput = includeOutput
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
            guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return NSTemporaryDirectory() + "Talkie"
            }
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

// MARK: - Transcribe Step Configuration

/// Quality tier for transcription - user-facing preference, not architectural choice
enum TranscriptionQualityTier: String, Codable, CaseIterable {
    case fast = "fast"           // Prioritize speed
    case balanced = "balanced"   // Balance speed and accuracy
    case high = "high"           // Prioritize accuracy

    var displayName: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .high: return "Best"
        }
    }

    var description: String {
        switch self {
        case .fast: return "Prioritize speed"
        case .balanced: return "Balance speed & accuracy"
        case .high: return "Prioritize accuracy"
        }
    }

    var icon: String {
        switch self {
        case .fast: return "hare"
        case .balanced: return "scale.3d"
        case .high: return "sparkles"
        }
    }

    /// Primary model for this tier (implementation detail, not exposed to user)
    var primaryModel: String {
        switch self {
        case .fast: return "apple_speech"
        case .balanced: return "openai_whisper-small"
        case .high: return "distil-whisper_distil-large-v3"
        }
    }

    /// Default fallback model (nil for fast tier)
    var defaultFallbackModel: String? {
        switch self {
        case .fast: return nil
        case .balanced: return "openai_whisper-base"
        case .high: return "openai_whisper-small"
        }
    }
}

/// Fallback strategy when primary transcription fails or times out
enum TranscriptionFallbackStrategy: String, Codable, CaseIterable {
    case automatic = "automatic"   // Fallback on any error
    case onTimeout = "on_timeout"  // Only fallback on timeout
    case none = "none"             // No fallback

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .onTimeout: return "On Timeout"
        case .none: return "None"
        }
    }

    var description: String {
        switch self {
        case .automatic: return "Use fallback if primary fails for any reason"
        case .onTimeout: return "Only use fallback if primary times out"
        case .none: return "No fallback - fail if primary fails"
        }
    }
}

/// Configuration for local speech-to-text transcription
struct TranscribeStepConfig: Codable {
    // New quality-based configuration
    var qualityTier: TranscriptionQualityTier
    var fallbackStrategy: TranscriptionFallbackStrategy
    var fallbackModel: String?      // Explicit fallback (uses tier default if nil)

    // Options
    var overwriteExisting: Bool     // Overwrite if transcript already exists
    var saveAsVersion: Bool         // Save as new transcript version

    // Legacy field for migration
    private var model: String?

    init(
        qualityTier: TranscriptionQualityTier = .balanced,
        fallbackStrategy: TranscriptionFallbackStrategy = .automatic,
        fallbackModel: String? = nil,
        overwriteExisting: Bool = false,
        saveAsVersion: Bool = true
    ) {
        self.qualityTier = qualityTier
        self.fallbackStrategy = fallbackStrategy
        self.fallbackModel = fallbackModel
        self.overwriteExisting = overwriteExisting
        self.saveAsVersion = saveAsVersion
    }

    /// Primary model to use (derived from quality tier)
    var primaryModel: String {
        qualityTier.primaryModel
    }

    /// Effective fallback model (explicit or tier default)
    var effectiveFallbackModel: String? {
        guard fallbackStrategy != .none else { return nil }
        return fallbackModel ?? qualityTier.defaultFallbackModel
    }

    // MARK: - Migration from legacy format

    private enum CodingKeys: String, CodingKey {
        case qualityTier, fallbackStrategy, fallbackModel
        case overwriteExisting, saveAsVersion
        case model // Legacy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try new format first
        if let tier = try? container.decode(TranscriptionQualityTier.self, forKey: .qualityTier) {
            self.qualityTier = tier
            self.fallbackStrategy = try container.decodeIfPresent(TranscriptionFallbackStrategy.self, forKey: .fallbackStrategy) ?? .automatic
            self.fallbackModel = try container.decodeIfPresent(String.self, forKey: .fallbackModel)
        } else if let legacyModel = try? container.decode(String.self, forKey: .model) {
            // Migrate from legacy model field
            self.qualityTier = Self.inferTier(from: legacyModel)
            self.fallbackStrategy = .automatic
            self.fallbackModel = nil
        } else {
            // Default
            self.qualityTier = .balanced
            self.fallbackStrategy = .automatic
            self.fallbackModel = nil
        }

        self.overwriteExisting = try container.decodeIfPresent(Bool.self, forKey: .overwriteExisting) ?? false
        self.saveAsVersion = try container.decodeIfPresent(Bool.self, forKey: .saveAsVersion) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(qualityTier, forKey: .qualityTier)
        try container.encode(fallbackStrategy, forKey: .fallbackStrategy)
        try container.encodeIfPresent(fallbackModel, forKey: .fallbackModel)
        try container.encode(overwriteExisting, forKey: .overwriteExisting)
        try container.encode(saveAsVersion, forKey: .saveAsVersion)
    }

    /// Infer quality tier from legacy model ID
    private static func inferTier(from modelId: String) -> TranscriptionQualityTier {
        switch modelId {
        case "apple_speech":
            return .fast
        case "distil-whisper_distil-large-v3":
            return .high
        case "openai_whisper-small", "openai_whisper-base", "openai_whisper-tiny":
            return .balanced
        default:
            return .balanced
        }
    }

    /// All available models for advanced configuration
    static let availableModels: [(id: String, name: String, description: String, engine: String)] = [
        ("apple_speech", "Apple Speech", "Built-in, instant", "Apple"),
        ("openai_whisper-tiny", "Whisper Tiny", "~40MB, fastest Whisper", "TalkieEngine"),
        ("openai_whisper-base", "Whisper Base", "~75MB, good quality", "TalkieEngine"),
        ("openai_whisper-small", "Whisper Small", "~250MB, balanced", "TalkieEngine"),
        ("distil-whisper_distil-large-v3", "Whisper Large V3", "~750MB, best quality", "TalkieEngine")
    ]
}

// MARK: - Speech Synthesis (TTS) Configuration

/// TTS provider for Walkie speech synthesis
enum TTSProvider: String, Codable, CaseIterable {
    case system = "system"          // macOS built-in AVSpeechSynthesizer
    case speakeasy = "speakeasy"    // SpeakEasy CLI (supports openai, elevenlabs, etc.)
    case openai = "openai"          // OpenAI TTS via SpeakEasy
    case elevenlabs = "elevenlabs"  // ElevenLabs via SpeakEasy

    var displayName: String {
        switch self {
        case .system: return "System (macOS)"
        case .speakeasy: return "SpeakEasy (Default)"
        case .openai: return "OpenAI"
        case .elevenlabs: return "ElevenLabs"
        }
    }
}

/// Configuration for text-to-speech output (Walkie-Talkie mode!)
struct SpeakStepConfig: Codable {
    var text: String                    // Text to speak (supports variables like {{OUTPUT}})
    var provider: TTSProvider           // TTS provider to use
    var voice: String?                  // Voice name/ID (depends on provider)
    var rate: Float                     // Speech rate (0.0 - 1.0, default ~0.5)
    var pitch: Float                    // Voice pitch (0.5 - 2.0, default 1.0)
    var playImmediately: Bool           // Play now vs just generate audio
    var saveToFile: Bool                // Also save as audio file
    var useCache: Bool                  // Use SpeakEasy's caching

    init(
        text: String = "{{OUTPUT}}",
        provider: TTSProvider = .speakeasy,
        voice: String? = nil,
        rate: Float = 0.5,
        pitch: Float = 1.0,
        playImmediately: Bool = true,
        saveToFile: Bool = false,
        useCache: Bool = true           // Cache for repeated phrases
    ) {
        self.text = text
        self.provider = provider
        self.voice = voice
        self.rate = rate
        self.pitch = pitch
        self.playImmediately = playImmediately
        self.saveToFile = saveToFile
        self.useCache = useCache
    }

    // Legacy support - map old voiceIdentifier to new voice
    var voiceIdentifier: String? {
        get { voice }
        set { voice = newValue }
    }

    /// Available voices by provider
    static func availableVoices(for provider: TTSProvider) -> [(id: String, name: String)] {
        switch provider {
        case .system:
            return [
                ("com.apple.voice.compact.en-US.Samantha", "Samantha (Default)"),
                ("com.apple.voice.enhanced.en-US.Samantha", "Samantha (Enhanced)"),
                ("com.apple.voice.compact.en-US.Alex", "Alex"),
                ("com.apple.voice.enhanced.en-US.Alex", "Alex (Enhanced)")
            ]
        case .speakeasy, .openai:
            return [
                ("alloy", "Alloy"),
                ("echo", "Echo"),
                ("fable", "Fable"),
                ("onyx", "Onyx"),
                ("nova", "Nova"),
                ("shimmer", "Shimmer")
            ]
        case .elevenlabs:
            return [
                ("EXAVITQu4vr4xnSDxMaL", "Sarah"),
                ("21m00Tcm4TlvDq8ikWAM", "Rachel"),
                ("AZnzlk1XvdvUeBnXmlld", "Domi"),
                ("MF3mGyEYCl7XYWbV9V6O", "Elli")
            ]
        }
    }
}

// MARK: - Trigger Step Configurations

/// Configuration for keyword trigger detection
struct TriggerStepConfig: Codable {
    var phrases: [String]              // Trigger phrases to detect (e.g., ["hey talkie"])
    var caseSensitive: Bool            // Case-sensitive matching
    var searchLocation: SearchLocation // Where to search in transcript
    var contextWindowSize: Int         // Words to extract around trigger
    var stopIfNoMatch: Bool            // Gate workflow - stop if no match

    init(
        phrases: [String] = ["hey talkie"],
        caseSensitive: Bool = false,
        searchLocation: SearchLocation = .end,
        contextWindowSize: Int = 200,
        stopIfNoMatch: Bool = true
    ) {
        self.phrases = phrases
        self.caseSensitive = caseSensitive
        self.searchLocation = searchLocation
        self.contextWindowSize = contextWindowSize
        self.stopIfNoMatch = stopIfNoMatch
    }

    enum SearchLocation: String, Codable, CaseIterable {
        case end = "End"
        case anywhere = "Anywhere"
        case start = "Start"

        var displayName: String {
            switch self {
            case .end: return "End of transcript"
            case .anywhere: return "Anywhere"
            case .start: return "Beginning"
            }
        }
    }
}

/// Configuration for intent extraction
struct IntentExtractStepConfig: Codable {
    var inputKey: String               // Which previous output to use
    var extractionMethod: ExtractionMethod
    var recognizedIntents: [IntentDefinition]
    var llmPromptTemplate: String      // Customizable prompt for LLM extraction
    var confidenceThreshold: Double    // Minimum confidence to accept (0.0-1.0)

    init(
        inputKey: String = "{{PREVIOUS_OUTPUT}}",
        extractionMethod: ExtractionMethod = .hybrid,
        recognizedIntents: [IntentDefinition] = IntentDefinition.defaults,
        llmPromptTemplate: String = Self.defaultPromptTemplate,
        confidenceThreshold: Double = 0.5
    ) {
        self.inputKey = inputKey
        self.extractionMethod = extractionMethod
        self.recognizedIntents = recognizedIntents
        self.llmPromptTemplate = llmPromptTemplate
        self.confidenceThreshold = confidenceThreshold
    }

    // Custom decoder for migration from configs saved without newer fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputKey = try container.decode(String.self, forKey: .inputKey)
        extractionMethod = try container.decode(ExtractionMethod.self, forKey: .extractionMethod)
        recognizedIntents = try container.decode([IntentDefinition].self, forKey: .recognizedIntents)
        llmPromptTemplate = try container.decodeIfPresent(String.self, forKey: .llmPromptTemplate) ?? Self.defaultPromptTemplate
        confidenceThreshold = try container.decodeIfPresent(Double.self, forKey: .confidenceThreshold) ?? 0.5
        // notifyOnExtraction removed - use explicit notification step instead
    }

    private enum CodingKeys: String, CodingKey {
        case inputKey, extractionMethod, recognizedIntents, llmPromptTemplate, confidenceThreshold
    }

    /// Default prompt template with placeholders
    static let defaultPromptTemplate = """
        Analyze this voice transcript and extract any requested actions.

        Transcript:
        {{INPUT}}

        Recognized actions: {{INTENT_NAMES}}

        List each action found, one per line, in this format:
        ACTION: [action name] | PARAM: [optional parameter like time/date] | CONFIDENCE: [0.0-1.0]

        Only list actions explicitly requested. Be concise.
        """

    enum ExtractionMethod: String, Codable, CaseIterable {
        case llm = "LLM"
        case keywords = "Keywords"
        case hybrid = "Hybrid"

        var displayName: String {
            switch self {
            case .llm: return "LLM (AI-powered)"
            case .keywords: return "Keywords (fast, offline)"
            case .hybrid: return "Hybrid (LLM with keyword fallback)"
            }
        }
    }
}

/// Defines a recognized intent with synonyms and optional target workflow
struct IntentDefinition: Identifiable, Codable {
    let id: UUID
    var name: String                   // Canonical name (e.g., "summarize")
    var synonyms: [String]             // Alternative words (e.g., ["summary", "sum up"])
    var targetWorkflowId: UUID?        // Workflow to execute for this intent (nil = name matching, doNothingId = detect only)
    var isEnabled: Bool

    /// Special UUID for "detect only" mode - log the intent but don't execute any workflow
    static let doNothingId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// Returns true if this intent is in "detect only" mode (no execution)
    var shouldSkipExecution: Bool {
        targetWorkflowId == Self.doNothingId
    }

    init(
        id: UUID = UUID(),
        name: String,
        synonyms: [String] = [],
        targetWorkflowId: UUID? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.synonyms = synonyms
        self.targetWorkflowId = targetWorkflowId
        self.isEnabled = isEnabled
    }

    /// Default recognized intents
    static let defaults: [IntentDefinition] = [
        IntentDefinition(name: "summarize", synonyms: ["summary", "sum up", "brief", "tldr"]),
        IntentDefinition(name: "remind", synonyms: ["reminder", "remind me", "set reminder"]),
        IntentDefinition(name: "note", synonyms: ["notes", "take note", "make note"]),
        IntentDefinition(name: "email", synonyms: ["mail", "send email", "draft email"]),
        IntentDefinition(name: "todo", synonyms: ["task", "tasks", "to do", "action item"]),
        IntentDefinition(name: "calendar", synonyms: ["schedule", "event", "meeting", "appointment"]),
        IntentDefinition(name: "save", synonyms: ["store", "keep", "archive"]),
    ]
}

/// Result of intent extraction (for passing between steps)
struct ExtractedIntent: Codable {
    let action: String
    let parameter: String?
    let confidence: Double?
    let workflowId: UUID?

    var description: String {
        if let param = parameter {
            return "\(action): \(param)"
        }
        return action
    }
}

/// Configuration for executing workflows based on extracted intents
struct ExecuteWorkflowsStepConfig: Codable {
    var intentsKey: String             // Key containing intents array
    var stopOnError: Bool              // Stop loop if a workflow fails
    var parallel: Bool                 // Run workflows in parallel

    init(
        intentsKey: String = "{{PREVIOUS_OUTPUT}}",
        stopOnError: Bool = false,
        parallel: Bool = false
    ) {
        self.intentsKey = intentsKey
        self.stopOnError = stopOnError
        self.parallel = parallel
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
    private let iCloudPinnedKey = "pinnedWorkflows"
    private let twfMigrationKey = "twf_starter_migration_v1"

    private init() {
        loadWorkflows()

        // Only load starter workflows ONCE (migration-style)
        if !UserDefaults.standard.bool(forKey: twfMigrationKey) {
            loadStarterWorkflowsFromTWF()
            UserDefaults.standard.set(true, forKey: twfMigrationKey)
        }
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
            isPinned: false, // Duplicates start unpinned
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
        // Sync pinned workflows to iCloud KVS for iOS
        syncPinnedToiCloud()
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

        // Ensure system workflows are always in the list
        ensureSystemWorkflowsExist()
    }

    /// Ensure system workflows (Transcribe, Hey Talkie) are always present
    private func ensureSystemWorkflowsExist() {
        var needsSave = false

        // Ensure System Transcribe exists (runs first)
        if !workflows.contains(where: { $0.id == WorkflowDefinition.systemTranscribeWorkflowId }) {
            workflows.insert(WorkflowDefinition.systemTranscribe, at: 0)
            needsSave = true
        }

        // Ensure Hey Talkie exists (runs after transcription)
        if !workflows.contains(where: { $0.id == WorkflowDefinition.heyTalkieWorkflowId }) {
            // Insert after System Transcribe if it exists, otherwise at 0
            let insertIndex = workflows.firstIndex(where: { $0.id == WorkflowDefinition.systemTranscribeWorkflowId }).map { $0 + 1 } ?? 0
            workflows.insert(WorkflowDefinition.heyTalkie, at: insertIndex)
            needsSave = true
        }

        if needsSave {
            saveWorkflows()
        }
    }

    /// Sync pinned workflow info to iCloud Key-Value Store
    /// iOS reads this to show pinned workflows in MAC ACTIONS section
    private func syncPinnedToiCloud() {
        let pinnedWorkflows = workflows.filter { $0.isPinned }
        let pinnedInfo: [[String: String]] = pinnedWorkflows.map { workflow in
            [
                "id": workflow.id.uuidString,
                "name": workflow.name,
                "icon": workflow.icon
            ]
        }

        if let data = try? JSONEncoder().encode(pinnedInfo) {
            NSUbiquitousKeyValueStore.default.set(data, forKey: iCloudPinnedKey)
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    // MARK: - TWF Starter Workflows

    /// Load starter workflows from bundled TWF files
    /// Only adds workflows that don't already exist (by ID)
    private func loadStarterWorkflowsFromTWF() {
        let starterWorkflows = TWFLoader.loadStarterWorkflows()
        var added = 0

        for starter in starterWorkflows {
            // Check if workflow with this ID already exists
            if !workflows.contains(where: { $0.id == starter.id }) {
                workflows.append(starter)
                added += 1
            }
        }

        if added > 0 {
            logger.debug("[WorkflowManager] Added \(added) starter workflows from TWF")
            saveWorkflows()
        }
    }

    /// Force reload all starter workflows from TWF files (replaces existing ones with same slug)
    func reloadStarterWorkflowsFromTWF() {
        let starterWorkflows = TWFLoader.loadStarterWorkflows()

        for starter in starterWorkflows {
            if let index = workflows.firstIndex(where: { $0.id == starter.id }) {
                // Preserve user customizations like isPinned and autoRun
                var updated = starter
                updated = WorkflowDefinition(
                    id: starter.id,
                    name: starter.name,
                    description: starter.description,
                    icon: starter.icon,
                    color: starter.color,
                    steps: starter.steps,
                    isEnabled: workflows[index].isEnabled,  // Preserve
                    isPinned: workflows[index].isPinned,    // Preserve
                    autoRun: workflows[index].autoRun,      // Preserve
                    autoRunOrder: workflows[index].autoRunOrder,  // Preserve
                    createdAt: workflows[index].createdAt,  // Preserve
                    modifiedAt: Date()
                )
                workflows[index] = updated
            } else {
                workflows.append(starter)
            }
        }

        logger.debug("[WorkflowManager] Reloaded \(starterWorkflows.count) starter workflows from TWF")
        saveWorkflows()
    }
}
