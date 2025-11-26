//
//  WorkflowAction.swift
//  talkie
//
//  Workflow action system for processing voice memos
//

import Foundation

// MARK: - Action Types
enum WorkflowActionType: String, CaseIterable, Codable {
    case summarize = "Summarize"
    case extractTasks = "Extract Tasks"
    case keyInsights = "Key Insights"
    case reminders = "Remind"
    case share = "Share"

    var icon: String {
        switch self {
        case .summarize: return "list.bullet.clipboard"
        case .extractTasks: return "checkmark.square"
        case .keyInsights: return "lightbulb"
        case .reminders: return "bell"
        case .share: return "square.and.arrow.up"
        }
    }

    var systemPrompt: String {
        switch self {
        case .summarize:
            return """
            You are an expert executive assistant. Summarize the following voice memo transcript into a concise paragraph, highlighting the main purpose and outcome. Use a professional tone.

            Transcript:
            {{TRANSCRIPT}}
            """

        case .extractTasks:
            return """
            You are a task extraction specialist. Identify and list all action items from the following voice memo transcript. Format as a JSON array of task objects with "title" and "priority" (high/medium/low).

            Transcript:
            {{TRANSCRIPT}}

            Return ONLY valid JSON in this format:
            [{"title": "Task description", "priority": "medium"}]
            """

        case .keyInsights:
            return """
            You are an insight analyst. Extract 3-5 key takeaways from the following voice memo transcript. Format as a JSON array of strings.

            Transcript:
            {{TRANSCRIPT}}

            Return ONLY valid JSON in this format:
            ["Insight 1", "Insight 2", "Insight 3"]
            """

        case .reminders:
            return """
            You are a reminder extraction assistant. Identify any time-sensitive items, deadlines, or follow-ups mentioned in the transcript. Format as a JSON array with "title", "dueDate" (ISO8601 string or null), and "notes".

            Transcript:
            {{TRANSCRIPT}}

            Return ONLY valid JSON in this format:
            [{"title": "Follow up with client", "dueDate": "2025-11-25T10:00:00Z", "notes": "Discussed in meeting"}]
            """

        case .share:
            return ""
        }
    }
}

// MARK: - AI Models
enum AIModel: String, CaseIterable, Codable {
    case geminiFlash = "gemini-1.5-flash-latest"
    case geminiPro = "gemini-1.5-pro-latest"

    var displayName: String {
        switch self {
        case .geminiFlash: return "Gemini 2.5 Flash"
        case .geminiPro: return "Gemini 3.0 Pro"
        }
    }

    var description: String {
        switch self {
        case .geminiFlash: return "Best for general purpose summaries, emails, and daily tasks. Fast and capable."
        case .geminiPro: return "Top-tier reasoning for complex analysis, creative writing, and coding."
        }
    }

    var badge: String {
        switch self {
        case .geminiFlash: return "STANDARD"
        case .geminiPro: return "PRO"
        }
    }
}

// MARK: - Workflow Configuration
struct WorkflowConfig: Codable {
    let actionType: WorkflowActionType
    let model: AIModel
    let customPrompt: String?

    init(actionType: WorkflowActionType, model: AIModel = .geminiFlash, customPrompt: String? = nil) {
        self.actionType = actionType
        self.model = model
        self.customPrompt = customPrompt
    }

    func prompt(with transcript: String) -> String {
        let basePrompt = customPrompt ?? actionType.systemPrompt
        return basePrompt.replacingOccurrences(of: "{{TRANSCRIPT}}", with: transcript)
    }
}

// MARK: - Workflow Result
struct WorkflowResult: Codable {
    let actionType: WorkflowActionType
    let output: String
    let model: AIModel
    let timestamp: Date
    let tokensUsed: Int?

    init(actionType: WorkflowActionType, output: String, model: AIModel, tokensUsed: Int? = nil) {
        self.actionType = actionType
        self.output = output
        self.model = model
        self.timestamp = Date()
        self.tokensUsed = tokensUsed
    }
}

// MARK: - Task Model (for extractTasks result)
struct TaskItem: Codable, Identifiable {
    let id: UUID
    let title: String
    let priority: Priority

    enum Priority: String, Codable {
        case high, medium, low

        var color: String {
            switch self {
            case .high: return "red"
            case .medium: return "orange"
            case .low: return "gray"
            }
        }
    }

    init(id: UUID = UUID(), title: String, priority: Priority) {
        self.id = id
        self.title = title
        self.priority = priority
    }
}

// MARK: - Reminder Model (for reminders result)
struct ReminderItem: Codable, Identifiable {
    let id: UUID
    let title: String
    let dueDate: Date?
    let notes: String?

    init(id: UUID = UUID(), title: String, dueDate: Date? = nil, notes: String? = nil) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.notes = notes
    }
}
