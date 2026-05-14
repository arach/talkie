//
//  AIProviderCredentialReviewSheet.swift
//  Talkie iOS
//
//  Review/edit step before validating and saving OCR-detected AI credentials.
//

import SwiftUI
import UIKit
import TalkieMobileKit

struct AIProviderCredentialScanPreview: Identifiable {
    let id = UUID()
    let image: UIImage
    let recognizedText: String
    let candidates: [TalkieAIProviderCredentialOCRCandidate]
}

struct AIProviderCredentialReviewSheet: View {
    let preview: AIProviderCredentialScanPreview

    @Environment(\.dismiss) private var dismiss

    @State private var providerId: String
    @State private var apiKey: String
    @State private var knownGoodAPIKey = TalkieAIProviderCredentialOCRService.localTestAPIKey
    @State private var recognizedText: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showsOCRText = false
    @State private var hasEditedAPIKey = false

    init(preview: AIProviderCredentialScanPreview) {
        self.preview = preview

        let firstCandidate = preview.candidates.first
        _providerId = State(initialValue: firstCandidate?.providerId ?? "openai")
        _apiKey = State(initialValue: firstCandidate?.apiKey ?? "")
        _recognizedText = State(initialValue: preview.recognizedText)
        _showsOCRText = State(initialValue: preview.candidates.isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Image(uiImage: preview.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 260)
                        .clipShape(.rect(cornerRadius: CornerRadius.md))
                        .overlay {
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .stroke(Color.borderPrimary.opacity(0.4), lineWidth: 0.5)
                                .allowsHitTesting(false)
                        }

                    credentialEditor

                    if !currentCandidates.isEmpty {
                        detectedCandidates
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showsOCRText.toggle()
                        }
                    } label: {
                        Label(showsOCRText ? "Hide OCR Text" : "Show OCR Text", systemImage: "text.viewfinder")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)

                    if showsOCRText {
                        TextEditor(text: $recognizedText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.textSecondary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(Spacing.md)
                            .frame(minHeight: 150)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.surfaceSecondary)
                            .clipShape(.rect(cornerRadius: CornerRadius.md))
                            .onChange(of: recognizedText) { _, newValue in
                                updateDraftFromOCRText(newValue)
                            }
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.recording)
                    }

                    if let successMessage {
                        Label(successMessage, systemImage: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.green)
                    }

                    Button {
                        Task {
                            await compareLocally()
                        }
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark.shield.fill")
                            }
                            Text(isSaving ? "Comparing..." : "Compare Locally")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(canValidate ? Color.cyan : Color.textTertiary.opacity(0.5))
                        .clipShape(.rect(cornerRadius: CornerRadius.md))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canValidate || isSaving)
                }
                .padding(Spacing.md)
            }
            .background(Color.surfacePrimary.ignoresSafeArea())
            .navigationTitle("Review API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var credentialEditor: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("DETECTED CREDENTIAL")
                .font(.system(size: 10, weight: .medium))
                .tracking(1)
                .foregroundStyle(Color.textTertiary)

            Picker("", selection: $providerId) {
                Text("OpenAI").tag("openai")
                Text("Groq").tag("groq")
            }
            .pickerStyle(.segmented)

            TextField("Paste or correct the full API key", text: apiKeyBinding, axis: .vertical)
                .font(.system(size: 13, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(2...4)
                .padding(12)
                .background(Color.surfacePrimary)
                .clipShape(.rect(cornerRadius: CornerRadius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(Color.borderPrimary.opacity(0.7), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }

            TextField("Paste a known-good throwaway key to compare", text: knownGoodAPIKeyBinding, axis: .vertical)
                .font(.system(size: 13, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(2...4)
                .padding(12)
                .background(Color.surfacePrimary)
                .clipShape(.rect(cornerRadius: CornerRadius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(Color.cyan.opacity(0.35), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }

            Text("Local comparison only. Nothing is sent or saved.")
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
        }
        .padding(Spacing.md)
        .background(Color.surfaceSecondary)
        .clipShape(.rect(cornerRadius: CornerRadius.md))
    }

    private var detectedCandidates: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("POSSIBLE MATCHES")
                .font(.system(size: 10, weight: .medium))
                .tracking(1)
                .foregroundStyle(Color.textTertiary)

            ForEach(currentCandidates) { candidate in
                Button {
                    providerId = candidate.providerId
                    apiKey = candidate.apiKey
                    hasEditedAPIKey = false
                    errorMessage = nil
                    successMessage = nil
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: candidate.providerId == providerId && candidate.apiKey == apiKey ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.providerName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.textPrimary)

                            Text(candidate.apiKey)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(2)
                        }

                        Spacer()
                    }
                    .padding(Spacing.sm)
                    .background(Color.surfacePrimary)
                    .clipShape(.rect(cornerRadius: CornerRadius.sm))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.md)
        .background(Color.surfaceSecondary)
        .clipShape(.rect(cornerRadius: CornerRadius.md))
    }

    private var canValidate: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !knownGoodAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { apiKey },
            set: { newValue in
                apiKey = newValue
                hasEditedAPIKey = true
                errorMessage = nil
                successMessage = nil
            }
        )
    }

    private var knownGoodAPIKeyBinding: Binding<String> {
        Binding(
            get: { knownGoodAPIKey },
            set: { newValue in
                knownGoodAPIKey = newValue
                errorMessage = nil
                successMessage = nil
            }
        )
    }

    private var currentCandidates: [TalkieAIProviderCredentialOCRCandidate] {
        let detected = TalkieAIProviderCredentialOCRService.candidates(in: recognizedText)
        if !detected.isEmpty {
            return detected
        }

        guard let draft = TalkieAIProviderCredentialOCRService.bestDraft(in: recognizedText) else {
            return []
        }

        return [draft]
    }

    private func updateDraftFromOCRText(_ text: String) {
        guard !hasEditedAPIKey || apiKey.isEmpty,
              let candidate = TalkieAIProviderCredentialOCRService.bestDraft(in: text) else {
            return
        }

        providerId = candidate.providerId
        apiKey = candidate.apiKey
    }

    @MainActor
    private func compareLocally() async {
        guard !isSaving else { return }

        isSaving = true
        errorMessage = nil
        successMessage = nil
        defer { isSaving = false }

        let comparison = TalkieAIProviderCredentialOCRService.localComparison(
            candidate: apiKey,
            expected: knownGoodAPIKey
        )

        if comparison.isMatch {
            successMessage = "Local match. Nothing was sent or saved."
        } else {
            errorMessage = "No local match yet: \(comparison.similarityPercent)% similar, \(comparison.editDistance) edit\(comparison.editDistance == 1 ? "" : "s")."
        }
    }
}
