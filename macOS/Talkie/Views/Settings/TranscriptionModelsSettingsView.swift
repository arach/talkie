//
//  TranscriptionModelsSettingsView.swift
//  Talkie
//
//  Transcription model settings - grouped by family with compact cards
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "TranscriptionModelsSettings")

struct TranscriptionModelsSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(EngineClient.self) private var engineClient
    @Environment(LiveSettings.self) private var liveSettings

    @State private var showingDeleteConfirmation: (Bool, ModelInfo?) = (false, nil)

    // Group models by family
    private var whisperModels: [ModelInfo] {
        engineClient.availableModels.filter { $0.family.lowercased() == "whisper" }
    }

    private var parakeetModels: [ModelInfo] {
        engineClient.availableModels.filter { $0.family.lowercased() == "parakeet" }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Header
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("LIVE / SETTINGS / TRANSCRIPTION")
                        .font(Theme.current.fontXSMedium)
                        .foregroundColor(Theme.current.foregroundMuted)

                    Text("TRANSCRIPTION MODELS")
                        .font(Theme.current.fontHeadlineBold)
                        .foregroundColor(Theme.current.foreground)

                    Text("Select a model for speech-to-text. Larger models are more accurate but slower.")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .lineLimit(2)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)

                // Whisper Models Section
                if !whisperModels.isEmpty {
                    modelFamilySection(
                        title: "WHISPER",
                        subtitle: "OpenAI's speech recognition models",
                        models: whisperModels
                    )
                }

                // Parakeet Models Section
                if !parakeetModels.isEmpty {
                    modelFamilySection(
                        title: "PARAKEET",
                        subtitle: "NVIDIA's multilingual models",
                        models: parakeetModels
                    )
                }

                Spacer(minLength: 40)
            }
        }
        .background(Theme.current.background)
        .onAppear {
            engineClient.refreshStatus()
        }
        .alert(isPresented: Binding(
            get: { showingDeleteConfirmation.0 },
            set: { if !$0 { showingDeleteConfirmation = (false, nil) } }
        )) {
            Alert(
                title: Text("Delete Model?"),
                message: Text("This will remove \(showingDeleteConfirmation.1?.displayName ?? "this model") from your system. You can download it again later."),
                primaryButton: .destructive(Text("Delete")) {
                    if let model = showingDeleteConfirmation.1 {
                        deleteModel(model)
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Model Family Section

    private func modelFamilySection(title: String, subtitle: String, models: [ModelInfo]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Section header with family-specific colors
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(title == "WHISPER" ? Color.orange : Color.cyan)
                    .frame(width: 3, height: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Theme.current.fontSMBold)
                        .foregroundColor(Theme.current.foreground)
                    Text(subtitle)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                Spacer()
            }
            .padding(.horizontal, Spacing.lg)

            // Model cards grid - 2 columns matching Models sidebar style
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: Spacing.sm),
                GridItem(.flexible(), spacing: Spacing.sm)
            ], spacing: Spacing.sm) {
                ForEach(models) { model in
                    STTModelCard(
                        modelInfo: model,
                        downloadProgress: engineClient.downloadProgress,
                        isSelected: settingsManager.liveTranscriptionModelId == model.id,
                        onSelect: { selectModel(model) },
                        onDownload: { downloadModel(model) },
                        onDelete: { showingDeleteConfirmation = (true, model) },
                        onCancel: { Task { await engineClient.cancelDownload() } }
                    )
                }
            }
            .padding(.horizontal, Spacing.lg)
        }
    }

    // MARK: - Actions

    private func selectModel(_ model: ModelInfo) {
        settingsManager.liveTranscriptionModelId = model.id

        Task {
            do {
                try await engineClient.preloadModel(model.id)
                logger.info("Successfully preloaded model: \(model.id)")
            } catch {
                logger.error("Failed to preload model \(model.id): \(error.localizedDescription)")
            }
        }
    }

    private func downloadModel(_ model: ModelInfo) {
        logger.info("Downloading model: \(model.id)")
        Task {
            do {
                try await engineClient.downloadModel(model.id)
                logger.info("Successfully downloaded model: \(model.id)")
            } catch {
                logger.error("Failed to download model \(model.id): \(error.localizedDescription)")
            }
        }
    }

    private func deleteModel(_ model: ModelInfo) {
        logger.info("Deleting model: \(model.id)")
        // TODO: Implement model deletion via EngineClient
    }
}

#Preview {
    TranscriptionModelsSettingsView()
        .frame(width: 900, height: 700)
}
