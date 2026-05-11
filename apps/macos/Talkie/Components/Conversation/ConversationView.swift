//
//  ConversationView.swift
//  Talkie
//
//  A conversational UI component for displaying messages with artifacts
//  First use case: Revision history for interactive memos
//

import SwiftUI

// MARK: - Conversation View

struct ConversationView: View {
    let conversation: Conversation

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(conversation.messages) { message in
                    MessageBubble(message: message)
                }
            }
            .padding()
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ConversationMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Role icon
            roleIcon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 8) {
                // Message content
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.system(size: 13))
                        .foregroundColor(message.role == .system ? .secondary : .primary)
                        .italic(message.role == .system)
                }

                // Artifacts
                ForEach(message.artifacts) { artifact in
                    ArtifactView(artifact: artifact)
                }
            }

            Spacer()

            // Timestamp (subtle)
            Text(message.timestamp, style: .time)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var roleIcon: some View {
        switch message.role {
        case .user:
            Image(systemName: "mic.fill")
                .font(.system(size: 14))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.blue)
                .clipShape(Circle())

        case .assistant:
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.purple)
                .clipShape(Circle())

        case .system:
            Image(systemName: "doc.text")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.secondary.opacity(0.2))
                .clipShape(Circle())
        }
    }
}

// MARK: - Artifact View

struct ArtifactView: View {
    let artifact: Artifact

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch artifact.content {
            case .diff(let diffContent):
                DiffArtifactView(diff: diffContent, decision: artifact.decision)

            case .text(let text):
                TextArtifactView(text: text)

            case .code(let language, let content):
                CodeArtifactView(language: language, content: content)

            case .image, .file:
                // Placeholder for future artifact types
                Text("[\(artifact.type.rawValue)]")
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Text Artifact

struct TextArtifactView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, design: .default))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
    }
}

// MARK: - Code Artifact

struct CodeArtifactView: View {
    let language: String?
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let lang = language {
                Text(lang.uppercased())
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Text(content)
                .font(.system(size: 11, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
        }
    }
}

// MARK: - Diff Artifact

struct DiffArtifactView: View {
    let diff: DiffContent
    let decision: ArtifactDecision?

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with decision badge
            HStack {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text("\(diff.changeCount) changes")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                // Decision badge
                if let decision = decision {
                    DecisionBadge(decision: decision)
                }

                // Expand/collapse
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            // Diff content
            if isExpanded {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    // Before
                    DiffSection(label: "Before", text: diff.before, color: .red.opacity(0.1))

                    // After
                    DiffSection(label: "After", text: diff.after, color: .green.opacity(0.1))
                }
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var borderColor: Color {
        switch decision {
        case .accepted: return .green.opacity(0.3)
        case .rejected: return .red.opacity(0.3)
        case .pending, .none: return Color(nsColor: .separatorColor)
        }
    }
}

struct DiffSection: View {
    let label: String
    let text: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)

            Text(text)
                .font(.system(size: 11))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color)
                .cornerRadius(4)
        }
    }
}

struct DecisionBadge: View {
    let decision: ArtifactDecision

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .cornerRadius(4)
    }

    private var icon: String {
        switch decision {
        case .accepted: return "checkmark"
        case .rejected: return "xmark"
        case .pending: return "clock"
        }
    }

    private var label: String {
        switch decision {
        case .accepted: return "Accepted"
        case .rejected: return "Rejected"
        case .pending: return "Pending"
        }
    }

    private var color: Color {
        switch decision {
        case .accepted: return .green
        case .rejected: return .red
        case .pending: return .orange
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleConversation = Conversation(
        title: "Sample Session",
        messages: [
            ConversationMessage(
                role: .system,
                content: "Original transcription",
                artifacts: [
                    Artifact(type: .text, content: .text("So I was thinking that maybe we should consider the possibility of perhaps looking into this further."))
                ]
            ),
            ConversationMessage(
                role: .user,
                content: "Make it more direct"
            ),
            ConversationMessage(
                role: .assistant,
                content: "Applied 3 changes",
                artifacts: [
                    Artifact(
                        type: .diff,
                        content: .diff(DiffContent(
                            before: "So I was thinking that maybe we should consider the possibility of perhaps looking into this further.",
                            after: "We should look into this further.",
                            changeCount: 3
                        )),
                        decision: .accepted
                    )
                ]
            )
        ]
    )

    return ConversationView(conversation: sampleConversation)
        .frame(width: 500, height: 400)
}
