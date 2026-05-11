//
//  RevisionHistoryView.swift
//  Talkie
//
//  Displays the revision history of an interactive memo
//  Shows the journey from original transcription through LLM-assisted edits
//

import SwiftUI

struct RevisionHistoryView: View {
    let memo: MemoModel

    @State private var isExpanded = false

    private var revisionHistory: RevisionHistory? {
        memo.revisionHistory
    }

    private var conversation: Conversation? {
        guard let history = revisionHistory else { return nil }
        return Conversation.from(revisionHistory: history)
    }

    var body: some View {
        if let history = revisionHistory, let conv = conversation {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                            .foregroundColor(.purple)

                        Text("Interactive Editing Session")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)

                        Spacer()

                        // Stats
                        HStack(spacing: 12) {
                            StatBadge(
                                icon: "checkmark.circle.fill",
                                count: acceptedCount(history),
                                color: .green
                            )

                            if rejectedCount(history) > 0 {
                                StatBadge(
                                    icon: "xmark.circle.fill",
                                    count: rejectedCount(history),
                                    color: .red
                                )
                            }
                        }

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color.purple.opacity(0.08))
                }
                .buttonStyle(.plain)

                // Expanded content
                if isExpanded {
                    Divider()

                    ConversationView(conversation: conv)
                        .frame(maxHeight: 400)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.purple.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private func acceptedCount(_ history: RevisionHistory) -> Int {
        history.revisions.filter { $0.wasAccepted }.count
    }

    private func rejectedCount(_ history: RevisionHistory) -> Int {
        history.revisions.filter { !$0.wasAccepted }.count
    }
}

struct StatBadge: View {
    let icon: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text("\(count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .foregroundColor(color)
    }
}

// MARK: - Preview

#Preview {
    let sampleHistory = RevisionHistory(
        originalText: "So I was thinking that maybe we should consider looking into this further.",
        revisions: [
            RevisionRecord(
                instruction: "Make it more direct",
                textBefore: "So I was thinking that maybe we should consider looking into this further.",
                textAfter: "We should look into this further.",
                changeCount: 3,
                wasAccepted: true
            ),
            RevisionRecord(
                instruction: "Add urgency",
                textBefore: "We should look into this further.",
                textAfter: "We need to look into this immediately!",
                changeCount: 2,
                wasAccepted: false
            ),
            RevisionRecord(
                instruction: "Make it professional",
                textBefore: "We should look into this further.",
                textAfter: "I recommend we investigate this matter further.",
                changeCount: 2,
                wasAccepted: true
            )
        ]
    )

    let sampleMemo = MemoModel(
        transcription: "I recommend we investigate this matter further.",
        revisionHistoryJSON: sampleHistory.toJSON()
    )

    return RevisionHistoryView(memo: sampleMemo)
        .padding()
        .frame(width: 500)
}
