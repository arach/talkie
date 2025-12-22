//
//  TranscriptionModelsSettingsView.swift
//  Talkie
//
//  Transcription model settings for Live Mode
//  Workflows select their models per-step in the workflow editor
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "TranscriptionModelsSettings")

struct TranscriptionModelsSettingsView: View {
    @State private var settingsManager = SettingsManager.shared
    @State private var engineClient = EngineClient.shared
    @State private var liveSettings = LiveSettings.shared

    @State private var showingDeleteConfirmation: (Bool, ModelInfo?) = (false, nil)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Header
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Transcription Models")
                        .font(Theme.current.fontTitle)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.current.foreground)

                    Text("Manage speech-to-text models. Download models to use them in Live Mode or workflows.")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                // Live Mode model picker
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("LIVE MODE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .textCase(.uppercase)

                    liveModePicker
                }

                Divider()

                // Available models grid
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("AVAILABLE MODELS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .textCase(.uppercase)

                    modelGrid
                }
            }
            .padding(Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.current.background)
        .onAppear {
            // Refresh model status when view appears
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

    // MARK: - Live Mode Picker

    private var liveModePicker: some View {
        let downloadedModels = engineClient.availableModels.filter { $0.isDownloaded }

        return VStack(alignment: .leading, spacing: Spacing.xs) {
            if downloadedModels.isEmpty {
                Text("No models downloaded. Download a model below to use in Live Mode.")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .padding(.vertical, Spacing.sm)
            } else {
                Picker("Live Mode Model", selection: $settingsManager.liveTranscriptionModelId) {
                    ForEach(downloadedModels) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 300, alignment: .leading)
                .onChange(of: settingsManager.liveTranscriptionModelId) { oldValue, newValue in
                    guard oldValue != newValue else { return }
                    logger.info("Live transcription model changed: \(oldValue) -> \(newValue)")

                    // Preload the new model in the engine
                    Task {
                        do {
                            try await engineClient.preloadModel(newValue)
                            logger.info("Successfully preloaded model: \(newValue)")
                        } catch {
                            logger.error("Failed to preload model \(newValue): \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Model Grid

    private var modelGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            ForEach(engineClient.availableModels) { model in
                TranscriptionModelCard(
                    model: model,
                    isSelected: false,  // Selection happens via Live Mode picker above
                    downloadProgress: engineClient.downloadProgress,
                    onSelect: {
                        // No-op: Selection handled by Live Mode picker
                    },
                    onDownload: {
                        downloadModel(model)
                    },
                    onDelete: {
                        showingDeleteConfirmation = (true, model)
                    },
                    onCancel: {
                        Task {
                            await engineClient.cancelDownload()
                        }
                    }
                )
            }
        }
    }

    // MARK: - Actions

    private func downloadModel(_ model: ModelInfo) {
        logger.info("Downloading model: \(model.id) - Functionality to be implemented")
        // TODO: Implement model download via EngineClient
    }

    private func deleteModel(_ model: ModelInfo) {
        logger.info("Deleting model: \(model.id) - Functionality to be implemented")
        // TODO: Implement model deletion via EngineClient
    }
}

#Preview {
    TranscriptionModelsSettingsView()
        .frame(width: 700, height: 600)
}
