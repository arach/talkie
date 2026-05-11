//
//  FeedbackSheet.swift
//  Talkie iOS
//
//  Shake-triggered feedback form — collects description, optional contact,
//  auto-attaches logs and system info, submits to api.usetalkie.com.
//

import SwiftUI

struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var description = ""
    @State private var contactInfo = ""
    @State private var isSubmitting = false
    @State private var result: SubmitResult?
    @FocusState private var isDescriptionFocused: Bool

    private enum SubmitResult {
        case success(reportId: String)
        case error(message: String)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    resultView(result)
                } else {
                    formView
                }
            }
            .navigationTitle("Send Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Form

    private var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("What's happening?")
                        .font(.subheadline.weight(.medium))

                    TextEditor(text: $description)
                        .focused($isDescriptionFocused)
                        .frame(minHeight: 120)
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Text("Describe the issue or share your feedback.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Contact
                VStack(alignment: .leading, spacing: 8) {
                    Text("How can we reach you?")
                        .font(.subheadline.weight(.medium))

                    TextField("Email or phone (optional)", text: $contactInfo)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Auto-included info
                VStack(alignment: .leading, spacing: 6) {
                    Label("Automatically included", systemImage: "info.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    let logCount = LogStore.shared.entries.count

                    VStack(alignment: .leading, spacing: 4) {
                        includedItem("App version & build")
                        includedItem("iOS version & device model")
                        includedItem("Recent logs (\(logCount) entries, anonymized)")
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Submit
                Button(action: submitFeedback) {
                    HStack(spacing: 6) {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text("Submit Feedback")
                    }
                    .font(.body.weight(.medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canSubmit ? Color.accentColor : Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canSubmit)
            }
            .padding()
        }
        .onAppear { isDescriptionFocused = true }
    }

    // MARK: - Result

    @ViewBuilder
    private func resultView(_ result: SubmitResult) -> some View {
        VStack(spacing: 24) {
            Spacer()

            switch result {
            case .success(let reportId):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.green)

                Text("Feedback Submitted")
                    .font(.title2.weight(.semibold))

                Text("Thank you for helping improve Talkie!")
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text("Reference:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(reportId)
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Button {
                        UIPasteboard.general.string = reportId
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.orange)

                Text("Submission Failed")
                    .font(.title2.weight(.semibold))

                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.body.weight(.medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    // MARK: - Helpers

    private var canSubmit: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    private func includedItem(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.green)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 4)
    }

    private func submitFeedback() {
        isSubmitting = true

        Task { @MainActor in
            do {
                let trimmedContact = contactInfo.trimmingCharacters(in: .whitespacesAndNewlines)
                let response = try await FeedbackReporter.shared.submit(
                    description: description,
                    contactInfo: trimmedContact.isEmpty ? nil : trimmedContact
                )

                if response.success, let id = response.id {
                    result = .success(reportId: id)
                } else {
                    result = .error(message: response.error ?? "Unknown error")
                }
            } catch {
                result = .error(message: error.localizedDescription)
            }

            isSubmitting = false
        }
    }
}

#Preview {
    FeedbackSheet()
}
