//
//  WorkflowActionSheet.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI

enum WorkflowActionType {
    case summarize
    case taskify
    case reminders

    var systemPrompt: String {
        switch self {
        case .summarize:
            return """
            Provide a concise summary of the following voice memo transcript.
            Focus on key points, main ideas, and important details.
            Keep it brief but comprehensive.
            """
        case .taskify:
            return """
            Extract all action items and tasks from the following voice memo transcript.
            Format each task as a clear, actionable item.
            Use bullet points with checkboxes (- [ ]).
            If no clear tasks are found, respond with "No actionable tasks identified."
            """
        case .reminders:
            return """
            Identify any time-sensitive items, deadlines, or things to remember from this voice memo transcript.
            Format as:
            - [Item description] - [When/Deadline if mentioned]
            If no reminders are found, respond with "No time-sensitive items identified."
            """
        }
    }
}

struct WorkflowActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var memo: VoiceMemo

    let title: String
    let icon: String
    let actionType: WorkflowActionType

    @State private var isProcessing: Bool = false

    private var result: String {
        switch actionType {
        case .summarize:
            return memo.summary ?? ""
        case .taskify:
            return memo.tasks ?? ""
        case .reminders:
            return memo.reminders ?? ""
        }
    }

    private var isCurrentlyProcessing: Bool {
        switch actionType {
        case .summarize:
            return memo.isProcessingSummary
        case .taskify:
            return memo.isProcessingTasks
        case .reminders:
            return memo.isProcessingReminders
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.surfacePrimary
                    .ignoresSafeArea()

                if isCurrentlyProcessing {
                    // Processing state (synced across devices)
                    VStack(spacing: Spacing.lg) {
                        Spacer()

                        ProgressView()
                            .scaleEffect(1.5)

                        Text("PROCESSING...")
                            .font(.techLabel)
                            .tracking(2)
                            .foregroundColor(.textSecondary)

                        Spacer()
                    }
                } else if result.isEmpty {
                    // Initial state
                    VStack(spacing: Spacing.xl) {
                        Spacer()

                        VStack(spacing: Spacing.lg) {
                            ZStack {
                                RoundedRectangle(cornerRadius: CornerRadius.md)
                                    .strokeBorder(Color.borderPrimary, lineWidth: 1)
                                    .frame(width: 80, height: 80)
                                    .background(Color.surfaceSecondary)
                                    .cornerRadius(CornerRadius.md)

                                Image(systemName: icon)
                                    .font(.system(size: 32, weight: .regular))
                                    .foregroundColor(.textTertiary)
                            }

                            VStack(spacing: Spacing.xxs) {
                                Text("READY")
                                    .font(.techLabel)
                                    .tracking(2)
                                    .foregroundColor(.textSecondary)

                                Text("Tap below to process")
                                    .font(.labelSmall)
                                    .foregroundColor(.textTertiary)
                            }
                        }

                        Spacer()

                        Button(action: processAction) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 12, weight: .medium))

                                Text("RUN \(title)")
                                    .font(.techLabel)
                                    .tracking(1.5)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: 240)
                            .padding(.vertical, Spacing.md)
                            .background(
                                LinearGradient(
                                    colors: [Color.active, Color.activeGlow],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(CornerRadius.sm)
                            .shadow(color: Color.active.opacity(0.3), radius: 12, x: 0, y: 6)
                        }
                        .padding(.bottom, Spacing.xxl)
                    }
                } else {
                    // Result state
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Text(result)
                                .font(.bodySmall)
                                .foregroundColor(.textPrimary)
                                .textSelection(.enabled)
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(Spacing.md)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.surfacePrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.techLabel)
                        .tracking(2)
                        .foregroundColor(.textPrimary)
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Text("CLOSE")
                            .font(.techLabel)
                            .tracking(1)
                            .foregroundColor(.textSecondary)
                    }
                }

                if !result.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: copyResult) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.active)
                        }
                    }
                }
            }
        }
    }

    private func processAction() {
        guard let context = memo.managedObjectContext else { return }

        // Set processing flag (syncs to iCloud and other devices)
        context.perform {
            switch actionType {
            case .summarize:
                memo.isProcessingSummary = true
            case .taskify:
                memo.isProcessingTasks = true
            case .reminders:
                memo.isProcessingReminders = true
            }
            try? context.save()
        }

        // Simulate async AI processing
        // In production: this would be a background task that could complete on ANY device
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            context.perform {
                // Store result in Core Data (syncs to all devices)
                switch actionType {
                case .summarize:
                    memo.summary = generateMockSummary()
                    memo.isProcessingSummary = false
                case .taskify:
                    memo.tasks = generateMockTasks()
                    memo.isProcessingTasks = false
                case .reminders:
                    memo.reminders = generateMockReminders()
                    memo.isProcessingReminders = false
                }
                try? context.save()
            }
        }
    }

    private func generateMockSummary() -> String {
        """
        SUMMARY:

        The transcript discusses a project planning meeting where the team reviewed quarterly objectives and assigned action items.

        Key Points:
        • Q4 targets were established with a 15% growth goal
        • Budget allocation for new tooling approved
        • Timeline moved up by 2 weeks due to client request
        • Team capacity concerns raised for November

        Next meeting scheduled for next Thursday to review initial progress.
        """
    }

    private func generateMockTasks() -> String {
        """
        EXTRACTED TASKS:

        - [ ] Finalize Q4 roadmap by end of week
        - [ ] Submit budget proposal to finance team
        - [ ] Update project timeline in tracking system
        - [ ] Schedule follow-up meeting for next Thursday
        - [ ] Review team capacity and allocate resources
        - [ ] Prepare client presentation for deadline change
        """
    }

    private func generateMockReminders() -> String {
        """
        TIME-SENSITIVE ITEMS:

        • Finalize Q4 roadmap - Due: End of this week
        • Budget proposal deadline - Submit ASAP
        • Timeline update - Client expects confirmation by Monday
        • Follow-up meeting - Next Thursday at 2pm
        • Resource allocation review - Before month end
        """
    }

    private func copyResult() {
        UIPasteboard.general.string = result
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
