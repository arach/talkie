//
//  TranscriptionModelsSettingsView.swift
//  Talkie
//
//  Transcription model settings - uses static catalog with Engine status overlay
//

import SwiftUI
import os
import TalkieKit

private let logger = Logger(subsystem: "jdi.talkie.core", category: "TranscriptionModelsSettings")

struct TranscriptionModelsSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(EngineClient.self) private var engineClient

    @State private var showingDeleteConfirmation: (Bool, String?) = (false, nil)

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "waveform",
                title: "TRANSCRIPTION MODELS",
                subtitle: "Select a model for speech-to-text"
            )
        } content: {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Parakeet Models Section (recommended, show first)
                parakeetSection

                // Whisper Models Section
                whisperSection
            }
        }
        .onAppear {
            engineClient.refreshStatus()
        }
        .alert("Delete Model?", isPresented: Binding(
            get: { showingDeleteConfirmation.0 },
            set: { if !$0 { showingDeleteConfirmation = (false, nil) } }
        )) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let modelId = showingDeleteConfirmation.1 {
                    deleteModel(modelId)
                }
            }
        } message: {
            Text("This will remove the model from your system. You can download it again later.")
        }
    }

    // MARK: - Parakeet Section

    private var parakeetSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Section header with links
            sectionHeader(
                title: "PARAKEET",
                subtitle: "NVIDIA's real-time streaming ASR",
                color: .cyan,
                repoURL: ParakeetModelCatalog.repoURL,
                paperURL: ParakeetModelCatalog.paperURL
            )

            // Model cards grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(ParakeetModelCatalog.metadata, id: \.model) { meta in
                    parakeetCard(for: meta)
                }
            }
        }
    }

    private func parakeetCard(for meta: ParakeetModelMetadata) -> some View {
        let modelId = "parakeet:\(meta.model.rawValue)"
        let isSelected = settingsManager.liveTranscriptionModelId == modelId
        let status = engineClient.modelStatus(for: modelId)

        var card = STTModelCard(
            name: "Parakeet \(meta.displayName)",
            family: .parakeet,
            size: formatSize(meta.sizeMB),
            speedTier: .realtime,
            languageInfo: meta.languagesBadge,
            isDownloaded: status.isDownloaded,
            isDownloading: status.isDownloading,
            downloadProgress: status.downloadProgress,
            onDownload: { downloadModel(modelId) },
            onDelete: { showingDeleteConfirmation = (true, modelId) }
        )
        card.isSelected = isSelected
        card.isLoaded = status.isLoaded
        card.onSelect = { selectModel(modelId) }
        card.onCancel = { Task { await engineClient.cancelDownload() } }
        return card
    }

    // MARK: - Whisper Section

    private var whisperSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Section header with links
            sectionHeader(
                title: "WHISPER",
                subtitle: "OpenAI's multilingual speech recognition",
                color: .orange,
                repoURL: WhisperModelCatalog.repoURL,
                paperURL: WhisperModelCatalog.paperURL
            )

            // Model cards grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(WhisperModelCatalog.metadata, id: \.model) { meta in
                    whisperCard(for: meta)
                }
            }
        }
    }

    private func whisperCard(for meta: WhisperModelMetadata) -> some View {
        let modelId = "whisper:\(meta.model.rawValue)"
        let isSelected = settingsManager.liveTranscriptionModelId == modelId
        let status = engineClient.modelStatus(for: modelId)

        let speedTier: STTModelCard.SpeedTier = {
            switch meta.model {
            case .tiny: return .realtime
            case .base: return .fast
            case .small: return .balanced
            case .distilLargeV3: return .accurate
            }
        }()

        var card = STTModelCard(
            name: "Whisper \(meta.displayName)",
            family: .whisper,
            size: formatSize(meta.sizeMB),
            speedTier: speedTier,
            languageInfo: "99+",
            isDownloaded: status.isDownloaded,
            isDownloading: status.isDownloading,
            downloadProgress: status.downloadProgress,
            onDownload: { downloadModel(modelId) },
            onDelete: { showingDeleteConfirmation = (true, modelId) }
        )
        card.isSelected = isSelected
        card.isLoaded = status.isLoaded
        card.onSelect = { selectModel(modelId) }
        card.onCancel = { Task { await engineClient.cancelDownload() } }
        return card
    }

    // MARK: - Section Header

    private func sectionHeader(
        title: String,
        subtitle: String,
        color: Color,
        repoURL: URL?,
        paperURL: URL?
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Rectangle()
                .fill(color)
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

            // Links
            if let repoURL {
                Link(destination: repoURL) {
                    HStack(spacing: 3) {
                        Image(systemName: "link")
                            .font(.system(size: 9))
                        Text("Repo")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(Theme.current.foregroundMuted)
                }
                .buttonStyle(.plain)
            }

            if let paperURL {
                Link(destination: paperURL) {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9))
                        Text("Paper")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(Theme.current.foregroundMuted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private func formatSize(_ mb: Int) -> String {
        if mb >= 1000 {
            return String(format: "%.1f GB", Double(mb) / 1000.0)
        }
        return "\(mb) MB"
    }

    // MARK: - Actions

    private func selectModel(_ modelId: String) {
        settingsManager.liveTranscriptionModelId = modelId

        Task {
            do {
                try await engineClient.preloadModel(modelId)
                logger.info("Successfully preloaded model: \(modelId)")
            } catch {
                logger.error("Failed to preload model \(modelId): \(error.localizedDescription)")
            }
        }
    }

    private func downloadModel(_ modelId: String) {
        logger.info("Downloading model: \(modelId)")
        Task {
            do {
                try await engineClient.downloadModel(modelId)
                logger.info("Successfully downloaded model: \(modelId)")
            } catch {
                logger.error("Failed to download model \(modelId): \(error.localizedDescription)")
            }
        }
    }

    private func deleteModel(_ modelId: String) {
        logger.info("Deleting model: \(modelId)")
        // TODO: Implement model deletion via EngineClient
    }
}

#Preview {
    TranscriptionModelsSettingsView()
        .frame(width: 600, height: 500)
}
