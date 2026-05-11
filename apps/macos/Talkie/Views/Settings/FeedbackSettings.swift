//
//  FeedbackSettings.swift
//  Talkie macOS
//
//  Settings page for submitting feedback and reports
//

import SwiftUI
import TalkieKit

struct FeedbackSettingsView: View {
    @State private var description: String = ""
    @State private var contactInfo: String = ""
    @State private var isSubmitting = false
    @State private var submitResult: SubmitResult?
    @State private var logsExpanded = false
    @FocusState private var isDescriptionFocused: Bool

    private enum SubmitResult {
        case success(reportId: String)
        case error(message: String)
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "bubble.left.and.text.bubble.right",
                title: "FEEDBACK",
                subtitle: "Help us improve Talkie by sharing feedback or reporting issues."
            )
        } content: {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if let result = submitResult {
                    resultView(result)
                } else {
                    formView
                }
            }
        }
    }

    private var formView: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Description field
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("What's on your mind?")
                    .font(Theme.current.fontBodyMedium)
                    .foregroundColor(Theme.current.foreground)

                TextEditor(text: $description)
                    .font(Theme.current.fontBody)
                    .scrollContentBackground(.hidden)
                    .focused($isDescriptionFocused)
                    .frame(minHeight: 150)
                    .padding(Spacing.sm)
                    .background(Theme.current.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .strokeBorder(Theme.current.border, lineWidth: 1)
                    )

                Text("Describe your feedback, feature request, or issue. System info will be included automatically.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            // Contact info field
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("How can we reach you?")
                    .font(Theme.current.fontBodyMedium)
                    .foregroundColor(Theme.current.foreground)

                TextField("Email or phone (optional)", text: $contactInfo)
                    .font(Theme.current.fontBody)
                    .textFieldStyle(.plain)
                    .padding(Spacing.sm)
                    .background(Theme.current.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .strokeBorder(Theme.current.border, lineWidth: 1)
                    )

                Text("Optional — if you'd like us to follow up.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            // What gets included
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.current.foregroundMuted)
                    Text("Automatically included")
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    includedItem("App version & build number")
                    includedItem("macOS version")
                    includedItem("Helper app status")
                    includedItem("System health check (permissions, agent, engine)")
                    includedItem("Permission landscape (environment, bundle IDs, helper path)")
                }

                // Expandable log preview
                let logs = TalkieReporter.shared.getRecentLogs()
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { logsExpanded.toggle() } }) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.green)
                            Text("Recent logs (anonymized)")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)
                            Text("(\(logs.count) lines)")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)
                            Spacer()
                            Image(systemName: logsExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9))
                                .foregroundColor(Theme.current.foregroundMuted)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, Spacing.md)

                    if logsExpanded {
                        ScrollView {
                            Text(logs.isEmpty ? "No logs collected yet." : logs.joined(separator: "\n"))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Theme.current.foregroundSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 200)
                        .padding(Spacing.sm)
                        .background(Theme.current.surfaceBase)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                        .padding(.leading, Spacing.md)
                    }
                }
            }
            .padding(Spacing.md)
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.md)

            // Submit button
            HStack {
                Spacer()
                Button(action: submitFeedback) {
                    HStack(spacing: Spacing.xs) {
                        if isSubmitting {
                            BrailleSpinner(size: 12)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12))
                        }
                        Text("Submit Feedback")
                    }
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting
                        ? Color.gray
                        : Color.accentColor)
                    .cornerRadius(CornerRadius.md)
                }
                .buttonStyle(.plain)
                .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .onAppear {
            isDescriptionFocused = true
        }
    }

    private func includedItem(_ text: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.green)
            Text(text)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .padding(.leading, Spacing.md)
    }

    @ViewBuilder
    private func resultView(_ result: SubmitResult) -> some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            switch result {
            case .success(let reportId):
                VStack(spacing: Spacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.green)

                    Text("Feedback Submitted")
                        .font(Theme.current.fontTitleMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text("Thank you for helping improve Talkie!")
                        .font(Theme.current.fontBody)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    // Report ID
                    HStack(spacing: Spacing.sm) {
                        Text("Reference:")
                            .font(Theme.current.fontSM)
                            .foregroundColor(Theme.current.foregroundMuted)

                        Text(reportId)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.current.foreground)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xxs)
                            .background(Theme.current.surface1)
                            .cornerRadius(CornerRadius.sm)

                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(reportId, forType: .string)
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.current.foregroundMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }

            case .error(let message):
                VStack(spacing: Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.orange)

                    Text("Submission Failed")
                        .font(Theme.current.fontTitleMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text(message)
                        .font(Theme.current.fontBody)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()

            // Action button
            Button(action: {
                if case .success = result {
                    description = ""
                    contactInfo = ""
                }
                submitResult = nil
            }) {
                Text(submitResult != nil && isSuccessResult ? "Submit Another" : "Try Again")
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.accentColor)
                    .cornerRadius(CornerRadius.md)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private var isSuccessResult: Bool {
        if case .success = submitResult { return true }
        return false
    }

    private func submitFeedback() {
        isSubmitting = true

        Task { @MainActor in
            do {
                let trimmedContact = contactInfo.trimmingCharacters(in: .whitespacesAndNewlines)
                let response = try await TalkieReporter.shared.submit(
                    source: .talkie,
                    userDescription: description,
                    contactInfo: trimmedContact.isEmpty ? nil : trimmedContact
                )

                if response.success, let id = response.id {
                    submitResult = .success(reportId: id)
                } else {
                    submitResult = .error(message: response.error ?? "Unknown error")
                }
            } catch {
                submitResult = .error(message: error.localizedDescription)
            }

            isSubmitting = false
        }
    }
}
