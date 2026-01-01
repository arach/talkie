//
//  TranscriptionModelsSettingsView.swift
//  Talkie
//
//  Transcription model settings - grouped by family with unified ModelCard
//

import SwiftUI
import os
import TalkieKit

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
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "waveform",
                title: "TRANSCRIPTION MODELS",
                subtitle: "Select a model for speech-to-text"
            )
        } content: {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Whisper Models Section
                if !whisperModels.isEmpty {
                    modelFamilySection(
                        title: "WHISPER",
                        subtitle: "OpenAI's speech recognition models",
                        provider: .whisper,
                        models: whisperModels
                    )
                }

                // Parakeet Models Section
                if !parakeetModels.isEmpty {
                    modelFamilySection(
                        title: "PARAKEET",
                        subtitle: "NVIDIA's real-time models",
                        provider: .parakeet,
                        models: parakeetModels
                    )
                }

                // Empty state
                if engineClient.availableModels.isEmpty {
                    emptyState
                }
            }
        }
        .onAppear {
            engineClient.refreshStatus()
            Task { await engineClient.fetchAvailableModels() }
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.badge.exclamationmark")
                .font(.system(size: 32))
                .foregroundColor(Theme.current.foregroundMuted)
            Text("No models available")
                .font(Theme.current.fontBodyMedium)
                .foregroundColor(Theme.current.foregroundSecondary)
            Text("Connect to TalkieEngine to see available models")
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Model Family Section

    private func modelFamilySection(
        title: String,
        subtitle: String,
        provider: ModelProvider,
        models: [ModelInfo]
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Section header
            HStack(spacing: Spacing.sm) {
                Rectangle()
                    .fill(ModelAccentColor.color(for: provider))
                    .frame(width: 3, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 1))

                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.current.foreground)

                Text("•")
                    .foregroundColor(Theme.current.foregroundMuted)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundMuted)

                Spacer()
            }

            // Model cards grid - 2 columns
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(models) { model in
                    modelCard(for: model, provider: provider)
                }
            }
        }
    }

    // MARK: - Model Card

    private func modelCard(for model: ModelInfo, provider: ModelProvider) -> some View {
        let isSelected = settingsManager.liveTranscriptionModelId == model.id
        let state = computeState(for: model)
        let speedTier = inferSpeedTier(from: model)
        let languageInfo = inferLanguageInfo(from: model)

        return ModelCard(
            name: model.displayName,
            provider: provider,
            state: state,
            isSelected: isSelected,
            downloadProgress: engineClient.downloadProgress?.modelId == model.id
                ? engineClient.downloadProgress?.progress
                : nil,
            onSelect: { selectModel(model) },
            onDownload: { downloadModel(model) },
            onDelete: { showingDeleteConfirmation = (true, model) },
            onCancel: { Task { await engineClient.cancelDownload() } }
        ) {
            STTModelCardDetail(
                sizeDescription: model.sizeDescription,
                speedTier: speedTier,
                languageInfo: languageInfo
            )
        }
    }

    // MARK: - State Computation

    private func computeState(for model: ModelInfo) -> ModelState {
        // Check if currently downloading
        if let progress = engineClient.downloadProgress,
           progress.modelId == model.id,
           progress.isDownloading {
            return .downloading(progress: progress.progress)
        }

        if model.isLoaded {
            return .loaded
        } else if model.isDownloaded {
            return .downloaded
        } else {
            return .notDownloaded
        }
    }

    private func inferSpeedTier(from model: ModelInfo) -> STTSpeedTier {
        let id = model.modelId.lowercased()

        if model.family.lowercased() == "parakeet" {
            return .realtime  // All Parakeet models are real-time
        }

        // Whisper tiers based on model size
        if id.contains("tiny") { return .realtime }
        if id.contains("base") { return .fast }
        if id.contains("small") { return .balanced }
        if id.contains("large") || id.contains("distil") { return .accurate }

        return .balanced  // Default
    }

    private func inferLanguageInfo(from model: ModelInfo) -> String {
        if model.family.lowercased() == "parakeet" {
            let id = model.modelId.lowercased()
            if id.contains("v2") { return "EN" }
            if id.contains("v3") { return "25" }
            return "EN"
        }
        return "99+"  // Whisper supports 99+ languages
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
        .frame(width: 600, height: 500)
}
