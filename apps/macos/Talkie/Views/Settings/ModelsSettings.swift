//
//  ModelsSettings.swift
//  Talkie macOS
//
//  Consolidated AI Models settings: STT + TTS + LLM
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

// MARK: - Models Settings (Consolidated)

/// Combined settings for all AI models: Speech-to-Text, Text-to-Speech, and LLM
/// Replaces separate Transcription, Voices, and LLM pages
struct ModelsSettingsView: View {
    @State private var selectedCategory: ModelCategory = .speechToText

    enum ModelCategory: String, CaseIterable {
        case speechToText = "STT"
        case textToSpeech = "TTS"
        case llm = "LLM"

        var title: String {
            switch self {
            case .speechToText: return "Speech-to-Text"
            case .textToSpeech: return "Text-to-Speech"
            case .llm: return "Language Models"
            }
        }

        var icon: String {
            switch self {
            case .speechToText: return "waveform"
            case .textToSpeech: return "speaker.wave.2"
            case .llm: return "brain"
            }
        }

        var color: Color {
            switch self {
            case .speechToText: return .cyan
            case .textToSpeech: return .purple
            case .llm: return .orange
            }
        }

        var description: String {
            switch self {
            case .speechToText: return "Transcription models"
            case .textToSpeech: return "Voice synthesis"
            case .llm: return "AI assistants"
            }
        }
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "cpu",
                title: "MODELS",
                subtitle: "Configure AI models for transcription, voice synthesis, and language processing."
            )
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                // Tab bar
                HStack(spacing: 0) {
                    ForEach(ModelCategory.allCases, id: \.rawValue) { category in
                        tabItem(category)
                    }
                    Spacer()
                }
                .padding(.horizontal, Spacing.sm)

                // Tab indicator line
                Rectangle()
                    .fill(Theme.current.divider)
                    .frame(height: 1)

                // Content based on selected category
                ScrollView {
                    Group {
                        switch selectedCategory {
                        case .speechToText:
                            TranscriptionModelsContent()
                        case .textToSpeech:
                            TTSVoicesContent()
                        case .llm:
                            LLMModelsContent()
                        }
                    }
                    .padding(.top, Spacing.md)
                }
            }
        }
        .onAppear {
            log.debug("ModelsSettingsView appeared")
        }
    }

    @ViewBuilder
    private func tabItem(_ category: ModelCategory) -> some View {
        let isSelected = selectedCategory == category

        Button(action: { selectedCategory = category }) {
            VStack(spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: category.icon)
                        .font(.system(size: 11))

                    Text(category.rawValue)
                        .font(Theme.current.fontXSBold)
                }
                .foregroundColor(isSelected ? category.color : Theme.current.foregroundSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xs)

                // Active indicator
                Rectangle()
                    .fill(isSelected ? category.color : Color.clear)
                    .frame(height: 2)
                    .cornerRadius(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Transcription Models Content

/// Content for STT models tab
struct TranscriptionModelsContent: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(EngineClient.self) private var engineClient

    @State private var showingDeleteConfirmation: (Bool, String?) = (false, nil)

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // Parakeet Models Section (recommended, show first)
            parakeetSection

            // Whisper Models Section
            whisperSection
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
            sectionHeader(
                title: "PARAKEET",
                subtitle: "NVIDIA's real-time streaming ASR",
                color: .cyan,
                repoURL: ParakeetModelCatalog.repoURL,
                paperURL: ParakeetModelCatalog.paperURL
            )

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(ParakeetModelCatalog.metadata, id: \.model) { meta in
                    parakeetCard(for: meta)
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private func parakeetCard(for meta: ParakeetModelMetadata) -> some View {
        let modelId = "parakeet:\(meta.model.rawValue)"
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
        card.isLoaded = status.isLoaded
        card.onCancel = { Task { await engineClient.cancelDownload() } }
        return card
    }

    // MARK: - Whisper Section

    private var whisperSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader(
                title: "WHISPER",
                subtitle: "OpenAI's multilingual speech recognition",
                color: .orange,
                repoURL: WhisperModelCatalog.repoURL,
                paperURL: WhisperModelCatalog.paperURL
            )

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(WhisperModelCatalog.metadata, id: \.model) { meta in
                    whisperCard(for: meta)
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private func whisperCard(for meta: WhisperModelMetadata) -> some View {
        let modelId = "whisper:\(meta.model.rawValue)"
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
        card.isLoaded = status.isLoaded
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

    private func downloadModel(_ modelId: String) {
        log.info("Downloading model: \(modelId)")
        Task {
            do {
                try await engineClient.downloadModel(modelId)
                log.info("Successfully downloaded model: \(modelId)")
            } catch {
                log.error("Failed to download model \(modelId): \(error.localizedDescription)")
            }
        }
    }

    private func deleteModel(_ modelId: String) {
        log.info("Deleting model: \(modelId)")
        // TODO: Implement model deletion via EngineClient
    }
}

// MARK: - TTS Voices Content

/// Content for TTS models tab - placeholder that links to the full TTS view
struct TTSVoicesContent: View {
    var body: some View {
        TTSVoicesSettingsView()
    }
}

// MARK: - LLM Models Content

/// Content for LLM models tab - placeholder that links to the full LLM view
struct LLMModelsContent: View {
    var body: some View {
        ModelLibraryView()
    }
}

// MARK: - Previews

#Preview("Models") {
    ModelsSettingsView()
        .environment(SettingsManager.shared)
        .environment(EngineClient.shared)
        .frame(width: 600, height: 600)
}
