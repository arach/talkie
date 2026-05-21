//
//  FeedbackNext.swift
//  Talkie iOS
//
//  Next-styled feedback surface. Paint pass — submit pipeline is a
//  Codex contract via `FeedbackService.submit(...)`. The shell shows
//  three states: editing, submitting (spinner inline), and result
//  (success / error).
//
//  Donor: FeedbackSheet — kept the form shape (description + contact +
//  auto-include note + result view), dropped the donor's accent button
//  chrome and Image(systemName:) headers in favor of the Next idiom
//  (channel labels via talkieType, hairline rows, theme accent).
//

import SwiftUI

struct FeedbackNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var logStore = LogStore.shared

    @State private var description: String = ""
    @State private var contact: String = ""
    @State private var isSubmitting: Bool = false
    @State private var result: Result?
    @State private var includeLogs: Bool = true
    @State private var showingLogInspector: Bool = false
    @State private var reviewedLogText: String = ""
    @FocusState private var descriptionFocused: Bool

    enum Result: Equatable {
        case success(reportID: String)
        case error(message: String)
    }

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(theme.currentTheme.chrome.edgeFaint)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let result {
                            resultPanel(result)
                        } else {
                            formPanel
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 120)
                }
            }
        }
        .onAppear {
            descriptionFocused = true
            refreshReviewedLogs()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("TALKIE · FEEDBACK")
                .talkieType(.wordmark)
                .foregroundStyle(theme.colors.textPrimary.opacity(0.78))

            Spacer()

            Button(action: { AppShellRouter.shared.openSettings() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(theme.currentTheme.chrome.edgeFaint.opacity(0.5))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close feedback")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Form

    private var formPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            field(eyebrow: "WHAT'S HAPPENING") {
                ZStack(alignment: .topLeading) {
                    if description.isEmpty {
                        Text("Describe the issue or share feedback. Be as specific as you can — what you were doing, what you expected, what you saw.")
                            .talkieType(.preview)
                            .foregroundStyle(theme.colors.textTertiary.opacity(0.65))
                            .padding(.top, 6)
                            .padding(.horizontal, 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $description)
                        .focused($descriptionFocused)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 140)
                        .talkieType(.preview)
                        .foregroundStyle(theme.colors.textPrimary)
                        .tint(theme.currentTheme.chrome.accent)
                }
                .padding(8)
                .background(theme.currentTheme.chrome.edgeFaint.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
            }

            field(eyebrow: "REACH BACK (OPTIONAL)") {
                TextField("email or phone", text: $contact)
                    .talkieType(.fieldValue)
                    .foregroundStyle(theme.colors.textPrimary)
                    .tint(theme.currentTheme.chrome.accent)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                    .background(theme.currentTheme.chrome.edgeFaint.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )
            }

            autoIncludedPanel
            submitButton
        }
    }

    @ViewBuilder
    private func field<Content: View>(eyebrow: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .talkieType(.channelLabel)
                .foregroundStyle(theme.colors.textTertiary)
            content()
        }
    }

    private var autoIncludedPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("AUTO-INCLUDED")
                    .talkieType(.channelLabel)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer()
            }
            .frame(height: 28)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.currentTheme.chrome.edgeFaint)
                    .frame(height: 1)
            }

            includedRow(label: "App version", value: "\(Bundle.main.feedbackShortVersion) (\(Bundle.main.feedbackBuildNumber))")
            includedRow(label: "Device", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
            logReviewPanel
        }
    }

    private var logReviewPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent logs")
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.textPrimary.opacity(0.85))
                Spacer(minLength: 8)
                Text(includeLogs ? "\(reviewedLogLines.count) redacted" : "excluded")
                    .talkieType(.fieldValue)
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(spacing: 8) {
                Button(action: { includeLogs.toggle() }) {
                    Text(includeLogs ? "INCLUDED" : "EXCLUDED")
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(includeLogs ? theme.currentTheme.chrome.accent : theme.colors.textTertiary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(theme.currentTheme.chrome.edgeFaint.opacity(0.45))
                        )
                }
                .buttonStyle(.plain)

                Button(action: { showingLogInspector.toggle() }) {
                    Text(showingLogInspector ? "HIDE" : "REVIEW / REDACT")
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(theme.currentTheme.chrome.edgeFaint.opacity(0.45))
                        )
                }
                .buttonStyle(.plain)

                Button(action: refreshReviewedLogs) {
                    Text("RESET")
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.colors.textTertiary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(theme.currentTheme.chrome.edgeFaint.opacity(0.28))
                        )
                }
                .buttonStyle(.plain)
                .disabled(logStore.entries.isEmpty)
            }

            if showingLogInspector {
                Text("Logs are pre-redacted. Delete any line you don’t want attached; edits are redacted again on send.")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)

                TextEditor(text: $reviewedLogText)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 128)
                    .talkieType(.preview)
                    .foregroundStyle(includeLogs ? theme.colors.textPrimary : theme.colors.textTertiary)
                    .tint(theme.currentTheme.chrome.accent)
                    .disabled(!includeLogs)
                    .padding(8)
                    .background(theme.currentTheme.chrome.edgeFaint.opacity(0.28))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: 1)
        }
    }

    private func includedRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .talkieType(.fieldLabel)
                .foregroundStyle(theme.colors.textPrimary.opacity(0.85))
            Spacer(minLength: 8)
            Text(value)
                .talkieType(.fieldValue)
                .foregroundStyle(theme.colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(height: 40)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: 1)
        }
    }

    private var submitButton: some View {
        Button(action: submit) {
            HStack(spacing: 10) {
                if isSubmitting {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(theme.colors.textPrimary)
                }
                Text(isSubmitting ? "SENDING…" : "SEND FEEDBACK")
                    .talkieType(.chipLabel)
                    .foregroundStyle(canSubmit ? theme.colors.textPrimary : theme.colors.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(canSubmit ? theme.currentTheme.chrome.accent.opacity(0.18) : theme.currentTheme.chrome.edgeFaint.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        canSubmit ? theme.currentTheme.chrome.accent : theme.currentTheme.chrome.edgeFaint,
                        lineWidth: theme.currentTheme.chrome.hairlineWidth
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    // MARK: - Result panel

    @ViewBuilder
    private func resultPanel(_ result: Result) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            switch result {
            case .success(let reportID):
                Text("SUBMITTED")
                    .talkieType(.channelLabel)
                    .foregroundStyle(Color(red: 0.36, green: 0.74, blue: 0.50))

                Text("Thank you for helping improve Talkie.")
                    .talkieType(.headlineSecondary)
                    .foregroundStyle(theme.colors.textPrimary)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("REPORT ID")
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.colors.textTertiary)
                    Text(reportID)
                        .talkieType(.instrumentReadoutSmall)
                        .foregroundStyle(theme.colors.textPrimary)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = reportID
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(theme.currentTheme.chrome.edgeFaint.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )

            case .error(let message):
                Text("SEND FAILED")
                    .talkieType(.channelLabel)
                    .foregroundStyle(Color(red: 0.85, green: 0.46, blue: 0.34))

                Text(message)
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textPrimary)
            }

            Button(action: { AppShellRouter.shared.openSettings() }) {
                Text("DONE")
                    .talkieType(.chipLabel)
                    .foregroundStyle(theme.colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(theme.currentTheme.chrome.accent.opacity(0.18))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(theme.currentTheme.chrome.accent, lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    // MARK: - Submit

    private var canSubmit: Bool {
        !isSubmitting && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        Task { @MainActor in
            do {
                let reportID = try await FeedbackService.submit(
                    description: description,
                    contact: contact,
                    logs: includeLogs ? reviewedLogLines : []
                )
                isSubmitting = false
                result = .success(reportID: reportID)
            } catch {
                isSubmitting = false
                result = .error(message: error.localizedDescription)
            }
        }
    }

    private var reviewedLogLines: [String] {
        reviewedLogText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func refreshReviewedLogs() {
        reviewedLogText = FeedbackService.reviewableLogLines(limit: 50).joined(separator: "\n")
    }
}

private extension Bundle {
    var feedbackShortVersion: String {
        (object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
    }
    var feedbackBuildNumber: String {
        (object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "—"
    }
}
