//
//  ConversationModels.swift
//  Talkie
//
//  Versatile data models for conversational UI patterns
//  Supports multi-party messages with artifacts and decisions
//

import Foundation
import SwiftUI

// MARK: - Conversation

/// A conversation is a sequence of messages between parties
public struct Conversation: Identifiable, Sendable {
    public let id: UUID
    public let title: String?
    public let messages: [ConversationMessage]
    public let createdAt: Date
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        title: String? = nil,
        messages: [ConversationMessage] = [],
        createdAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

// MARK: - Message

/// A single message in a conversation
public struct ConversationMessage: Identifiable, Sendable {
    public let id: UUID
    public let role: MessageRole
    public let content: String
    public let timestamp: Date
    public let artifacts: [Artifact]

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        artifacts: [Artifact] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.artifacts = artifacts
    }
}

/// Who sent the message
public enum MessageRole: String, Sendable, Codable {
    case user       // Human input (voice instruction, typed message)
    case assistant  // LLM response
    case system     // System message (info, status)
}

// MARK: - Artifact

/// An artifact attached to a message (diff, text, code, image, etc.)
public struct Artifact: Identifiable, Sendable {
    public let id: UUID
    public let type: ArtifactType
    public let content: ArtifactContent
    public let decision: ArtifactDecision?
    public let timestamp: Date
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        type: ArtifactType,
        content: ArtifactContent,
        decision: ArtifactDecision? = nil,
        timestamp: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.decision = decision
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

/// Types of artifacts
public enum ArtifactType: String, Sendable, Codable {
    case diff       // Text diff (before/after)
    case text       // Plain text snippet
    case code       // Code block
    case image      // Image reference
    case file       // File reference
}

/// Content of an artifact (type-safe union)
public enum ArtifactContent: Sendable {
    case diff(DiffContent)
    case text(String)
    case code(language: String?, content: String)
    case image(url: URL)
    case file(url: URL, name: String)
}

/// Content for a diff artifact
public struct DiffContent: Sendable {
    public let before: String
    public let after: String
    public let changeCount: Int

    public init(before: String, after: String, changeCount: Int = 0) {
        self.before = before
        self.after = after
        self.changeCount = changeCount
    }
}

/// Decision made on an artifact
public enum ArtifactDecision: String, Sendable, Codable {
    case accepted
    case rejected
    case pending
}

// MARK: - Conversion from RevisionHistory

extension Conversation {
    /// Create a Conversation from a RevisionHistory (for interactive memos)
    public static func from(revisionHistory: RevisionHistory) -> Conversation {
        var messages: [ConversationMessage] = []

        // Opening message with original text
        let openingMessage = ConversationMessage(
            role: .system,
            content: "Original transcription",
            timestamp: revisionHistory.savedAt,
            artifacts: [
                Artifact(
                    type: .text,
                    content: .text(revisionHistory.originalText)
                )
            ]
        )
        messages.append(openingMessage)

        // Each revision becomes a user message (instruction) + assistant message (result)
        for revision in revisionHistory.revisions {
            // User's instruction
            let userMessage = ConversationMessage(
                id: revision.id,
                role: .user,
                content: revision.instruction,
                timestamp: revision.timestamp
            )
            messages.append(userMessage)

            // Assistant's response with diff artifact
            let diffContent = DiffContent(
                before: revision.textBefore,
                after: revision.textAfter,
                changeCount: revision.changeCount
            )

            let artifact = Artifact(
                type: .diff,
                content: .diff(diffContent),
                decision: revision.wasAccepted ? .accepted : .rejected,
                timestamp: revision.timestamp,
                metadata: ["changeCount": "\(revision.changeCount)"]
            )

            let resultText = revision.wasAccepted
                ? "Applied \(revision.changeCount) changes"
                : "Proposed \(revision.changeCount) changes (rejected)"

            let assistantMessage = ConversationMessage(
                role: .assistant,
                content: resultText,
                timestamp: revision.timestamp,
                artifacts: [artifact]
            )
            messages.append(assistantMessage)
        }

        return Conversation(
            title: "Editing Session",
            messages: messages,
            createdAt: revisionHistory.savedAt
        )
    }
}
