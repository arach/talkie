//
//  LiveSidecar.swift
//  TalkieKit
//
//  Shared models and prompt construction for lightweight background
//  sidecar tasks that react to moments in a live recording.
//

import Foundation

public enum LiveSidecarKind: String, Codable, CaseIterable, Sendable {
    case feedback
    case research

    public var displayName: String {
        switch self {
        case .feedback:
            return "Feedback"
        case .research:
            return "Research"
        }
    }

    public var detailLabel: String {
        switch self {
        case .feedback:
            return "Live feedback"
        case .research:
            return "Live research"
        }
    }

    public var iconName: String {
        switch self {
        case .feedback:
            return "bubble.left.and.sparkles"
        case .research:
            return "magnifyingglass"
        }
    }

    public var queuedToastText: String {
        switch self {
        case .feedback:
            return "Feedback queued"
        case .research:
            return "Research queued"
        }
    }

    public var readyToastText: String {
        switch self {
        case .feedback:
            return "Feedback ready"
        case .research:
            return "Research ready"
        }
    }
}

public struct LiveSidecarPrompt: Equatable, Sendable {
    public let system: String
    public let user: String

    public init(system: String, user: String) {
        self.system = system
        self.user = user
    }
}

public enum LiveSidecarPromptBuilder {
    public static func build(
        kind: LiveSidecarKind,
        transcript: String,
        appName: String? = nil,
        windowTitle: String? = nil
    ) -> LiveSidecarPrompt {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextLines = buildContextLines(appName: appName, windowTitle: windowTitle)

        switch kind {
        case .feedback:
            return LiveSidecarPrompt(
                system: feedbackSystemPrompt,
                user: [
                    "Task: Give concise feedback on the most recent spoken idea.",
                    contextLines,
                    "Transcript excerpt:",
                    trimmedTranscript,
                    "",
                    "Return only the feedback. Prefer 3 to 5 short bullets."
                ].joined(separator: "\n")
            )

        case .research:
            return LiveSidecarPrompt(
                system: researchSystemPrompt,
                user: [
                    "Task: Identify the best next research directions based on the most recent spoken idea.",
                    contextLines,
                    "Transcript excerpt:",
                    trimmedTranscript,
                    "",
                    "Return only the research output. Prefer 3 to 5 short bullets."
                ].joined(separator: "\n")
            )
        }
    }

    public static func provenanceDetail(
        kind: LiveSidecarKind,
        providerName: String,
        modelId: String
    ) -> String {
        "\(kind.detailLabel) · \(providerName) · \(modelId)"
    }

    private static func buildContextLines(appName: String?, windowTitle: String?) -> String {
        var lines: [String] = []

        if let appName, !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("App: \(appName)")
        }

        if let windowTitle, !windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Window: \(windowTitle)")
        }

        if lines.isEmpty {
            lines.append("App: Unknown")
        }

        return lines.joined(separator: "\n")
    }

    private static let feedbackSystemPrompt = """
    You are a quiet sidecar assistant for a live brainstorming session.
    Give grounded, constructive feedback on the user's most recent idea.
    Focus on blind spots, unclear assumptions, stronger framing, tradeoffs, and good next moves.
    Do not restate the transcript at length.
    Do not invent outside facts.
    Keep the response concise and directly useful.
    """

    private static let researchSystemPrompt = """
    You are a quiet sidecar assistant for a live research workflow.
    Based only on the transcript, identify the best next research directions.
    Call out open questions, terms or entities worth checking, and why each thread matters.
    If the transcript is underspecified, say what is missing instead of inventing facts.
    Keep the response concise and directly useful.
    """
}
