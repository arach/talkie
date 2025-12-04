//
//  TalkieWorkflowSchema.swift
//  Talkie macOS
//
//  Schema provider for WFKit integration
//  Defines all step types, fields, and metadata for the workflow visualizer
//

import Foundation
import SwiftUI
import WFKit

// MARK: - Talkie Schema Provider

/// Provides schema information about Talkie's workflow step types to WFKit
struct TalkieWorkflowSchema: WFSchemaProvider {
    static let shared = TalkieWorkflowSchema()

    // MARK: - WFSchemaProvider Conformance

    let nodeTypes: [WFNodeTypeSchema]

    init() {
        nodeTypes = Self.buildNodeTypes()
    }

    // MARK: - Category Colors

    private static let categoryColors: [String: String] = [
        "AI Processing": "#BF5AF2",      // Purple
        "Communication": "#64D2FF",       // Cyan
        "Apple Apps": "#FF375F",          // Pink
        "Integrations": "#FF9F0A",        // Orange
        "Output": "#30D158",              // Green
        "Logic": "#FFD60A",               // Yellow
        "Triggers": "#0A84FF",            // Blue
    ]

    // MARK: - Build All Node Types

    private static func buildNodeTypes() -> [WFNodeTypeSchema] {
        [
            // AI Processing
            llmNode(),
            transcribeNode(),

            // Communication
            notificationNode(),
            iOSPushNode(),
            emailNode(),

            // Apple Apps
            appleNotesNode(),
            appleRemindersNode(),
            appleCalendarNode(),

            // Integrations
            shellNode(),
            webhookNode(),

            // Output
            clipboardNode(),
            saveFileNode(),

            // Logic
            conditionalNode(),
            transformNode(),

            // Triggers
            triggerNode(),
            intentExtractNode(),
            executeWorkflowsNode(),
        ]
    }

    // MARK: - AI Processing Nodes

    private static func llmNode() -> WFNodeTypeSchema {
        WFNodeTypeSchema(
            id: "llm",
            displayName: "LLM Generation",
            category: "AI Processing",
            iconName: "brain",
            defaultColor: categoryColors["AI Processing"],
            fields: [
                WFFieldSchema(
                    id: "provider",
                    displayName: "Provider",
                    type: .picker([
                        .init(value: "gemini", label: "Gemini"),
                        .init(value: "openai", label: "OpenAI"),
                        .init(value: "anthropic", label: "Anthropic"),
                        .init(value: "groq", label: "Groq"),
                        .init(value: "mlx", label: "MLX (Local)"),
                    ]),
                    isRequired: true,
                    group: "Model Settings",
                    order: 0
                ),
                WFFieldSchema(
                    id: "modelId",
                    displayName: "Model",
                    type: .string,
                    placeholder: "e.g., gpt-4o, claude-3-opus",
                    isRequired: true,
                    group: "Model Settings",
                    order: 1
                ),
                WFFieldSchema(
                    id: "prompt",
                    displayName: "Prompt",
                    type: .text,
                    placeholder: "Use {{TRANSCRIPT}} for memo text",
                    isRequired: true,
                    group: "Prompt",
                    order: 2
                ),
                WFFieldSchema(
                    id: "systemPrompt",
                    displayName: "System Prompt",
                    type: .text,
                    placeholder: "Optional system instructions",
                    helpText: "Sets context and behavior for the model",
                    group: "Prompt",
                    order: 3
                ),
                WFFieldSchema(
                    id: "temperature",
                    displayName: "Temperature",
                    type: .slider(min: 0.0, max: 2.0, step: 0.1),
                    helpText: "Higher = more creative, lower = more focused",
                    group: "Parameters",
                    order: 4
                ),
                WFFieldSchema(
                    id: "maxTokens",
                    displayName: "Max Tokens",
                    type: .number,
                    placeholder: "1024",
                    group: "Parameters",
                    order: 5
                ),
                WFFieldSchema(
                    id: "topP",
                    displayName: "Top P",
                    type: .slider(min: 0.0, max: 1.0, step: 0.05),
                    helpText: "Nucleus sampling threshold",
                    group: "Parameters",
                    order: 6
                ),
            ]
        )
    }

    private static func transcribeNode() -> WFNodeTypeSchema {
        WFNodeTypeSchema(
            id: "transcribe",
            displayName: "Transcribe Audio",
            category: "AI Processing",
            iconName: "waveform.and.mic",
            defaultColor: categoryColors["AI Processing"],
            fields: [
                WFFieldSchema(
                    id: "model",
                    displayName: "Whisper Model",
                    type: .picker([
                        .init(value: "openai_whisper-tiny", label: "Tiny (fastest)"),
                        .init(value: "openai_whisper-base", label: "Base"),
                        .init(value: "openai_whisper-small", label: "Small (balanced)"),
                        .init(value: "distil-whisper_distil-large-v3", label: "Distil Large v3 (best)"),
                    ]),
                    isRequired: true,
                    order: 0
                ),
                WFFieldSchema(
                    id: "overwriteExisting",
                    displayName: "Overwrite Existing",
                    type: .boolean,
                    helpText: "Replace existing transcript if present",
                    order: 1
                ),
                WFFieldSchema(
                    id: "saveAsVersion",
                    displayName: "Save as Version",
                    type: .boolean,
                    helpText: "Create a transcript version for history",
                    order: 2
                ),
            ]
        )
    }

    // MARK: - Communication Nodes

    private static func notificationNode() -> WFNodeTypeSchema {
        WFNodeTypeSchema(
            id: "notification",
            displayName: "Notification",
            category: "Communication",
            iconName: "bell.badge",
            defaultColor: categoryColors["Communication"],
            fields: [
                WFFieldSchema(
                    id: "title",
                    displayName: "Title",
                    type: .string,
                    isRequired: true,
                    order: 0
                ),
                WFFieldSchema(
                    id: "body",
                    displayName: "Body",
                    type: .text,
                    isRequired: true,
                    order: 1
                ),
                WFFieldSchema(
                    id: "sound",
                    displayName: "Play Sound",
                    type: .boolean,
                    order: 2
                ),
                WFFieldSchema(
                    id: "actionLabel",
                    displayName: "Action Label",
                    type: .string,
                    placeholder: "View, Open, etc.",
                    order: 3
                ),
            ]
        )
    }

    private static func iOSPushNode() -> WFNodeTypeSchema {
        WFNodeTypeSchema(
            id: "iOSPush",
            displayName: "iOS Push",
            category: "Communication",
            iconName: "iphone.badge.play",
            defaultColor: categoryColors["Communication"],
            fields: [
                WFFieldSchema(
                    id: "title",
                    displayName: "Title",
                    type: .string,
                    placeholder: "{{WORKFLOW_NAME}} Complete",
                    isRequired: true,
                    order: 0
                ),
                WFFieldSchema(
                    id: "body",
                    displayName: "Body",
                    type: .text,
                    placeholder: "Finished processing {{TITLE}}",
                    isRequired: true,
                    order: 1
                ),
                WFFieldSchema(
                    id: "sound",
                    displayName: "Play Sound",
                    type: .boolean,
                    order: 2
                ),
                WFFieldSchema(
                    id: "includeOutput",
                    displayName: "Include Output",
                    type: .boolean,
                    helpText: "Attach workflow output to notification",
                    order: 3
                ),
            ]
        )
    }

    private static func emailNode() -> WFNodeTypeSchema {
        WFNodeTypeSchema(
            id: "email",
            displayName: "Email",
            category: "Communication",
            iconName: "envelope",
            defaultColor: categoryColors["Communication"],
            fields: [
                WFFieldSchema(
                    id: "to",
                    displayName: "To",
                    type: .string,
                    placeholder: "recipient@example.com",
                    isRequired: true,
                    order: 0
                ),
                WFFieldSchema(
                    id: "cc",
                    displayName: "CC",
                    type: .string,
                    order: 1
                ),
                WFFieldSchema(
                    id: "bcc",
                    displayName: "BCC",
                    type: .string,
                    order: 2
                ),
                WFFieldSchema(
                    id: "subject",
                    displayName: "Subject",
                    type: .string,
                    isRequired: true,
                    order: 3
                ),
                WFFieldSchema(
                    id: "body",
                    displayName: "Body",
                    type: .text,
                    isRequired: true,
                    order: 4
                ),
                WFFieldSchema(
                    id: "isHTML",
                    displayName: "HTML Format",
                    type: .boolean,
                    helpText: "Send as HTML email",
                    order: 5
                ),
            ]
        )
    }

    // MARK: - Apple Apps Nodes

    private static func appleNotesNode() -> WFNodeTypeSchema {
        WFNodeTypeSchema(
            id: "appleNotes",
            displayName: "Apple Notes",
            category: "Apple Apps",
            iconName: "note.text",
            defaultColor: categoryColors["Apple Apps"],
            fields: [
                WFFieldSchema(
                    id: "folderName",
                    displayName: "Folder",
                    type: .string,
                    placeholder: "Leave empty for default",
                    order: 0
                ),
                WFFieldSchema(
                    id: "title",
                    displayName: "Title",
                    type: .string,
                    isRequired: true,
                    order: 1
                ),
                WFFieldSchema(
                    id: "body",
                    displayName: "Body",
                    type: .text,
                    isRequired: true,
                    order: 2
                ),
                WFFieldSchema(
                    id: "attachTranscript",
                    displayName: "Attach Transcript",
                    type: .boolean,
                    order: 3
                ),
            ]
        )
    }

    private static func appleRemindersNode() -> WFNodeTypeSchema {
        WFNodeTypeSchema(
            id: "appleReminders",
            displayName: "Reminder",
            category: "Apple Apps",
            iconName: "checklist",
            defaultColor: categoryColors["Apple Apps"],
            fields: [
                WFFieldSchema(
                    id: "listName",
                    displayName: "List",
                    type: .string,
                    placeholder: "Leave empty for default",
                    order: 0
                ),
                WFFieldSchema(
                    id: "title",
                    displayName: "Title",
                    type: .string,
                    isRequired: true,
                    order: 1
                ),
                WFFieldSchema(
                    id: "notes",
                    displayName: "Notes",
                    type: .text,
                    order: 2
                ),
                WFFieldSchema(
                    id: "dueDate",
                    displayName: "Due Date",
                    type: .string,
                    placeholder: "{{NOW+1d}} or ISO date",
                    order: 3
                ),
                WFFieldSchema(
                    id: "priority",
                    displayName: "Priority",
                    type: .picker([
                        .init(value: "0", label: "None"),
                        .init(value: "9", label: "Low"),
                        .init(value: "5", label: "Medium"),
                        .init(value: "1", label: "High"),
                    ]),
                    order: 4
                ),
            ]
        )
    }

    private static func appleCalendarNode() -> WFNodeTypeSchema {
        WFNodeTypeSchema(
            id: "appleCalendar",
            displayName: "Calendar Event",
            category: "Apple Apps",
            iconName: "calendar.badge.plus",
            defaultColor: categoryColors["Apple Apps"],
            fields: [
                WFFieldSchema(
                    id: "calendarName",
                    displayName: "Calendar",
                    type: .string,
                    placeholder: "Leave empty for default",
                    order: 0
                ),
                WFFieldSchema(
                    id: "title",
                    displayName: "Title",
                    type: .string,
                    isRequired: true,
                    order: 1
                ),
                WFFieldSchema(
                    id: "notes",
                    displayName: "Notes",
                    type: .text,
                    order: 2
                ),
                WFFieldSchema(
                    id: "startDate",
                    displayName: "Start Date",
                    type: .string,
                    placeholder: "Template or ISO date",
                    order: 3
                ),
                WFFieldSchema(
                    id: "duration",
                    displayName: "Duration (seconds)",
                    type: .number,
                    placeholder: "3600",
                    order: 4
                ),
                WFFieldSchema(
                    id: "location",
                    displayName: "Location",
                    type: .string,
                    order: 5
                ),
                WFFieldSchema(
                    id: "isAllDay",
                    displayName: "All Day",
                    type: .boolean,
                    order: 6
                ),
            ]
        )
    }

    // MARK: - Integration Nodes

    private static func shellNode() -> WFNodeTypeSchema {
        WFNodeTypeSchema(
            id: "shell",
            displayName: "Shell Command",
            category: "Integrations",
            iconName: "terminal",
            defaultColor: categoryColors["Integrations"],
            fields: [
                WFFieldSchema(
                    id: "executable",
                    displayName: "Executable",
                    type: .string,
                    placeholder: "/bin/echo",
                    helpText: "Full path to command",
                    isRequired: true,
                    group: "Command",
                    order: 0
                ),
                WFFieldSchema(
                    id: "arguments",
                    displayName: "Arguments",
                    type: .stringArray(WFStringArrayOptions(
                        placeholder: "Argument value",
                        addLabel: "Add Argument",
                        itemIcon: "chevron.right"
                    )),
                    helpText: "Command line arguments",
                    group: "Command",
                    order: 1
                ),
                WFFieldSchema(
                    id: "workingDirectory",
                    displayName: "Working Directory",
                    type: .string,
                    group: "Command",
                    order: 2
                ),
                WFFieldSchema(
                    id: "environment",
                    displayName: "Environment",
                    type: .keyValueArray(WFKeyValueOptions(
                        keyPlaceholder: "VAR_NAME",
                        valuePlaceholder: "value",
                        addLabel: "Add Variable"
                    )),
                    helpText: "Environment variables for the command",
                    group: "Command",
                    order: 3
                ),
                WFFieldSchema(
                    id: "stdin",
                    displayName: "Stdin",
                    type: .text,
                    placeholder: "Input to pass via stdin",
                    group: "Input/Output",
                    order: 4
                ),
                WFFieldSchema(
                    id: "promptTemplate",
                    displayName: "Prompt Template",
                    type: .text,
                    helpText: "For claude CLI -p flag",
                    group: "Input/Output",
                    order: 5
                ),
                WFFieldSchema(
                    id: "timeout",
                    displayName: "Timeout (seconds)",
                    type: .slider(min: 1, max: 300, step: 1),
                    group: "Options",
                    order: 6
                ),
                WFFieldSchema(
                    id: "captureStderr",
                    displayName: "Capture Stderr",
                    type: .boolean,
                    group: "Options",
                    order: 7
                ),
            ]
        )
    }

    private static func webhookNode() -> WFNodeTypeSchema {
        WFNodeTypeSchema(
            id: "webhook",
            displayName: "Webhook",
            category: "Integrations",
            iconName: "arrow.up.forward.app",
            defaultColor: categoryColors["Integrations"],
            fields: [
                WFFieldSchema(
                    id: "url",
                    displayName: "URL",
                    type: .string,
                    placeholder: "https://example.com/webhook",
                    isRequired: true,
                    order: 0
                ),
                WFFieldSchema(
                    id: "method",
                    displayName: "Method",
                    type: .picker([
                        .init(value: "GET", label: "GET"),
                        .init(value: "POST", label: "POST"),
                        .init(value: "PUT", label: "PUT"),
                        .init(value: "PATCH", label: "PATCH"),
                        .init(value: "DELETE", label: "DELETE"),
                    ]),
                    isRequired: true,
                    order: 1
                ),
                WFFieldSchema(
                    id: "headers",
                    displayName: "Headers",
                    type: .keyValueArray(WFKeyValueOptions(
                        keyPlaceholder: "Header-Name",
                        valuePlaceholder: "Header value",
                        addLabel: "Add Header"
                    )),
                    helpText: "HTTP headers for the request",
                    order: 2
                ),
                WFFieldSchema(
                    id: "bodyTemplate",
                    displayName: "Body Template",
                    type: .text,
                    order: 3
                ),
                WFFieldSchema(
                    id: "includeTranscript",
                    displayName: "Include Transcript",
                    type: .boolean,
                    order: 4
                ),
                WFFieldSchema(
                    id: "includeMetadata",
                    displayName: "Include Metadata",
                    type: .boolean,
                    order: 5
                ),
            ]
        )
    }

    // MARK: - Output Nodes

    private static func clipboardNode() -> WFNodeTypeSchema {
        WFNodeTypeSchema(
            id: "clipboard",
            displayName: "Clipboard",
            category: "Output",
            iconName: "doc.on.clipboard",
            defaultColor: categoryColors["Output"],
            fields: [
                WFFieldSchema(
                    id: "content",
                    displayName: "Content",
                    type: .text,
                    placeholder: "{{OUTPUT}}",
                    isRequired: true,
                    order: 0
                ),
            ]
        )
    }

    private static func saveFileNode() -> WFNodeTypeSchema {
        WFNodeTypeSchema(
            id: "saveFile",
            displayName: "Save File",
            category: "Output",
            iconName: "doc.badge.plus",
            defaultColor: categoryColors["Output"],
            fields: [
                WFFieldSchema(
                    id: "filename",
                    displayName: "Filename",
                    type: .string,
                    placeholder: "{{TITLE}}.txt",
                    isRequired: true,
                    order: 0
                ),
                WFFieldSchema(
                    id: "directory",
                    displayName: "Directory",
                    type: .string,
                    placeholder: "@Alias or path",
                    order: 1
                ),
                WFFieldSchema(
                    id: "content",
                    displayName: "Content",
                    type: .text,
                    placeholder: "{{OUTPUT}}",
                    isRequired: true,
                    order: 2
                ),
                WFFieldSchema(
                    id: "appendIfExists",
                    displayName: "Append if Exists",
                    type: .boolean,
                    order: 3
                ),
            ]
        )
    }

    // MARK: - Logic Nodes

    private static func conditionalNode() -> WFNodeTypeSchema {
        WFNodeTypeSchema(
            id: "conditional",
            displayName: "Conditional",
            category: "Logic",
            iconName: "arrow.triangle.branch",
            defaultColor: categoryColors["Logic"],
            fields: [
                WFFieldSchema(
                    id: "condition",
                    displayName: "Condition",
                    type: .string,
                    placeholder: "{{OUTPUT}} contains 'urgent'",
                    isRequired: true,
                    order: 0
                ),
                WFFieldSchema(
                    id: "thenSteps",
                    displayName: "Then Steps",
                    type: .stringArray(WFStringArrayOptions(
                        placeholder: "Step ID (UUID)",
                        addLabel: "Add Step",
                        itemIcon: "arrow.right.circle"
                    )),
                    helpText: "Steps to execute when condition is true",
                    order: 1
                ),
                WFFieldSchema(
                    id: "elseSteps",
                    displayName: "Else Steps",
                    type: .stringArray(WFStringArrayOptions(
                        placeholder: "Step ID (UUID)",
                        addLabel: "Add Step",
                        itemIcon: "arrow.turn.down.right"
                    )),
                    helpText: "Steps to execute when condition is false",
                    order: 2
                ),
            ]
        )
    }

    private static func transformNode() -> WFNodeTypeSchema {
        WFNodeTypeSchema(
            id: "transform",
            displayName: "Transform",
            category: "Logic",
            iconName: "wand.and.rays",
            defaultColor: categoryColors["Logic"],
            fields: [
                WFFieldSchema(
                    id: "operation",
                    displayName: "Operation",
                    type: .picker([
                        .init(value: "extractJSON", label: "Extract JSON"),
                        .init(value: "extractList", label: "Extract List"),
                        .init(value: "formatMarkdown", label: "Format as Markdown"),
                        .init(value: "truncate", label: "Truncate/Summarize"),
                        .init(value: "regexExtract", label: "Regex Extract"),
                        .init(value: "applyTemplate", label: "Apply Template"),
                    ]),
                    isRequired: true,
                    order: 0
                ),
                WFFieldSchema(
                    id: "parameters",
                    displayName: "Parameters",
                    type: .keyValueArray(WFKeyValueOptions(
                        keyPlaceholder: "param",
                        valuePlaceholder: "value",
                        addLabel: "Add Parameter"
                    )),
                    helpText: "Operation-specific parameters",
                    order: 1
                ),
            ]
        )
    }

    // MARK: - Trigger Nodes

    private static func triggerNode() -> WFNodeTypeSchema {
        WFNodeTypeSchema(
            id: "trigger",
            displayName: "Trigger",
            category: "Triggers",
            iconName: "waveform.badge.mic",
            defaultColor: categoryColors["Triggers"],
            fields: [
                WFFieldSchema(
                    id: "phrases",
                    displayName: "Trigger Phrases",
                    type: .stringArray(WFStringArrayOptions(
                        placeholder: "e.g., hey talkie",
                        addLabel: "Add Phrase",
                        itemIcon: "text.bubble"
                    )),
                    isRequired: true,
                    order: 0
                ),
                WFFieldSchema(
                    id: "caseSensitive",
                    displayName: "Case Sensitive",
                    type: .boolean,
                    order: 1
                ),
                WFFieldSchema(
                    id: "searchLocation",
                    displayName: "Search Location",
                    type: .picker([
                        .init(value: "end", label: "End"),
                        .init(value: "anywhere", label: "Anywhere"),
                        .init(value: "start", label: "Start"),
                    ]),
                    order: 2
                ),
                WFFieldSchema(
                    id: "contextWindowSize",
                    displayName: "Context Window",
                    type: .number,
                    placeholder: "200",
                    helpText: "Words to extract around trigger",
                    order: 3
                ),
                WFFieldSchema(
                    id: "stopIfNoMatch",
                    displayName: "Stop if No Match",
                    type: .boolean,
                    helpText: "Gate workflow on trigger match",
                    order: 4
                ),
            ]
        )
    }

    private static func intentExtractNode() -> WFNodeTypeSchema {
        WFNodeTypeSchema(
            id: "intentExtract",
            displayName: "Extract Intents",
            category: "Triggers",
            iconName: "text.magnifyingglass",
            defaultColor: categoryColors["Triggers"],
            fields: [
                WFFieldSchema(
                    id: "inputKey",
                    displayName: "Input Key",
                    type: .string,
                    placeholder: "{{TRANSCRIPT}}",
                    isRequired: true,
                    order: 0
                ),
                WFFieldSchema(
                    id: "extractionMethod",
                    displayName: "Extraction Method",
                    type: .picker([
                        .init(value: "llm", label: "LLM"),
                        .init(value: "keywords", label: "Keywords"),
                        .init(value: "hybrid", label: "Hybrid"),
                    ]),
                    order: 1
                ),
                WFFieldSchema(
                    id: "confidenceThreshold",
                    displayName: "Confidence Threshold",
                    type: .slider(min: 0.0, max: 1.0, step: 0.1),
                    order: 2
                ),
                WFFieldSchema(
                    id: "llmPromptTemplate",
                    displayName: "LLM Prompt",
                    type: .text,
                    placeholder: "Custom extraction prompt",
                    order: 3
                ),
                WFFieldSchema(
                    id: "recognizedIntents",
                    displayName: "Recognized Intents",
                    type: .objectArray(WFObjectSchema(
                        fields: [
                            WFFieldSchema(
                                id: "name",
                                displayName: "Intent Name",
                                type: .string,
                                placeholder: "e.g., summarize",
                                isRequired: true,
                                order: 0
                            ),
                            WFFieldSchema(
                                id: "synonyms",
                                displayName: "Synonyms",
                                type: .text,
                                placeholder: "summary, sum up (one per line)",
                                helpText: "Alternative phrases that trigger this intent",
                                order: 1
                            ),
                            WFFieldSchema(
                                id: "targetWorkflowId",
                                displayName: "Target Workflow",
                                type: .string,
                                placeholder: "Leave empty for auto-matching by name",
                                helpText: "UUID of workflow to execute, or empty for name matching",
                                order: 2
                            ),
                            WFFieldSchema(
                                id: "isEnabled",
                                displayName: "Enabled",
                                type: .boolean,
                                order: 3
                            ),
                        ],
                        displayField: "name",
                        addLabel: "Add Intent",
                        itemIcon: "brain.head.profile"
                    )),
                    helpText: "Define intents to recognize from transcripts",
                    order: 4
                ),
            ]
        )
    }

    private static func executeWorkflowsNode() -> WFNodeTypeSchema {
        WFNodeTypeSchema(
            id: "executeWorkflows",
            displayName: "Execute Workflows",
            category: "Triggers",
            iconName: "arrow.triangle.2.circlepath",
            defaultColor: categoryColors["Triggers"],
            fields: [
                WFFieldSchema(
                    id: "intentsKey",
                    displayName: "Intents Key",
                    type: .string,
                    placeholder: "{{PREVIOUS_OUTPUT}}",
                    isRequired: true,
                    order: 0
                ),
                WFFieldSchema(
                    id: "stopOnError",
                    displayName: "Stop on Error",
                    type: .boolean,
                    order: 1
                ),
                WFFieldSchema(
                    id: "parallel",
                    displayName: "Run in Parallel",
                    type: .boolean,
                    order: 2
                ),
            ]
        )
    }
}
