//
//  ReportSheet.swift
//  Talkie macOS
//
//  Report submission sheet triggered from command palette
//

import SwiftUI
import TalkieKit

struct ReportSheet: View {
    @Binding var isPresented: Bool
    @State private var description: String = ""
    @State private var isSubmitting = false
    @State private var submitResult: SubmitResult?
    @FocusState private var isDescriptionFocused: Bool

    private enum SubmitResult {
        case success(reportId: String, key: String)
        case error(message: String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Submit Report")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.current.foreground)

                    Text("Help us improve Talkie by reporting issues")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                Spacer()

                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Theme.current.foregroundMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.md)
            .background(Theme.current.backgroundSecondary)

            Divider()

            if let result = submitResult {
                // Result view
                resultView(result)
            } else {
                // Form view
                formView
            }
        }
        .frame(width: 480, height: 360)
        .background(Theme.current.background)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onAppear {
            isDescriptionFocused = true
        }
    }

    private var formView: some View {
        VStack(spacing: Spacing.md) {
            // Description field
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("What's happening?")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.current.foreground)

                TextEditor(text: $description)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .focused($isDescriptionFocused)
                    .frame(minHeight: 120)
                    .padding(Spacing.sm)
                    .background(Theme.current.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(Theme.current.border, lineWidth: 1)
                    )

                Text("Describe the issue or share feedback. System info and recent logs will be included automatically.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            Spacer()

            // Included info hint
            HStack(spacing: Spacing.sm) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.current.foregroundMuted)

                Text("Includes: macOS version, app version, recent logs (anonymized)")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.current.foregroundMuted)

                Spacer()
            }

            Divider()

            // Actions
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: submitReport) {
                    if isSubmitting {
                        BrailleSpinner(size: 12)
                    } else {
                        Text("Submit Report")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, Spacing.sm)
        }
        .padding(Spacing.md)
    }

    @ViewBuilder
    private func resultView(_ result: SubmitResult) -> some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            switch result {
            case .success(let reportId, let key):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)

                VStack(spacing: Spacing.xs) {
                    Text("Report Submitted")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.current.foreground)

                    Text("Thank you for your feedback!")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                // Report ID for reference
                VStack(spacing: 4) {
                    Text("Report ID")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.current.foregroundMuted)

                    HStack(spacing: Spacing.xs) {
                        Text(reportId)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.current.foreground)

                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(reportId, forType: .string)
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Theme.current.foregroundMuted)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Theme.current.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                }

            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)

                VStack(spacing: Spacing.xs) {
                    Text("Submission Failed")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.current.foreground)

                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, Spacing.sm)
        }
        .padding(Spacing.md)
    }

    private func submitReport() {
        isSubmitting = true

        Task { @MainActor in
            do {
                let response = try await TalkieReporter.shared.submit(
                    source: .talkie,
                    userDescription: description
                )

                if response.success, let id = response.id, let key = response.key {
                    submitResult = .success(reportId: id, key: key)
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

// MARK: - Report Sheet Overlay

struct ReportSheetOverlay: View {
    @Binding var isPresented: Bool

    var body: some View {
        if isPresented {
            ZStack {
                // Backdrop
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isPresented = false
                    }

                // Sheet
                ReportSheet(isPresented: $isPresented)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            .animation(.easeOut(duration: 0.15), value: isPresented)
        }
    }
}
