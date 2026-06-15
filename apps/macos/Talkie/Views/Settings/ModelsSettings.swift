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
                .foregroundStyle(isSelected ? category.color : Theme.current.foregroundSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xs)

                // Active indicator
                Rectangle()
                    .fill(isSelected ? category.color : Color.clear)
                    .frame(height: 2)
                    .clipShape(.rect(cornerRadius: 1))
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

    private let modelId = TalkieDefaults.dictationModelId

    var body: some View {
        #if arch(arm64)
        voiceModelSection
        .onAppear {
            normalizeVoiceModel()
            engineClient.refreshStatus()
        }
        #else
        localSpeechUnavailable
        #endif
    }

    private var voiceModelSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SettingsSectionHeader(
                title: "VOICE MODEL",
                subtitle: "Local speech recognition uses one supported model."
            )

            HStack(spacing: Spacing.md) {
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.current.accent)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Parakeet")
                        .font(Theme.current.fontBodyMedium)
                        .foregroundStyle(Theme.current.foreground)
                    Text(modelId)
                        .font(Theme.current.fontXS)
                        .foregroundStyle(Theme.current.foregroundSecondary)
                }

                Spacer()

                modelStatusBadge
                modelAction
            }
            .padding(Spacing.md)
            .background(Theme.current.surface1)
            .clipShape(.rect(cornerRadius: CornerRadius.sm))
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private var modelStatusBadge: some View {
        let status = engineClient.modelStatus(for: modelId)
        let label = status.isDownloading
            ? "Downloading"
            : status.isLoaded
                ? "Loaded"
                : status.isDownloaded ? "Ready" : "Not installed"

        return HStack(spacing: 5) {
            Circle()
                .fill(status.isDownloaded || status.isLoaded ? Theme.current.accent : Theme.current.foregroundMuted)
                .frame(width: 6, height: 6)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(status.isDownloaded || status.isLoaded ? Theme.current.accent : Theme.current.foregroundMuted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.current.surface2)
        .clipShape(.capsule)
    }

    @ViewBuilder
    private var modelAction: some View {
        let status = engineClient.modelStatus(for: modelId)

        if status.isDownloading {
            HStack(spacing: Spacing.sm) {
                ProgressView(value: status.downloadProgress)
                    .frame(width: 90)
                Button("Cancel") {
                    Task { await engineClient.cancelDownload() }
                }
                .buttonStyle(.borderless)
            }
        } else if !status.isDownloaded {
            Button("Download", systemImage: "arrow.down.circle") {
                downloadModel(modelId)
            }
            .buttonStyle(.bordered)
        }
    }

    private var localSpeechUnavailable: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("Local speech recognition requires Apple Silicon.")
                .font(Theme.current.fontSM)
                .foregroundStyle(Theme.current.foregroundSecondary)
            Spacer()
        }
        .padding(Spacing.md)
        .settingsSectionCard(padding: Spacing.md)
    }

    private func normalizeVoiceModel() {
        if settingsManager.liveTranscriptionModelId != modelId {
            settingsManager.liveTranscriptionModelId = modelId
        }
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
}

private struct SettingsSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Rectangle()
                .fill(Theme.current.accent)
                .frame(width: 3, height: 16)
                .clipShape(.rect(cornerRadius: 1))

            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.current.foreground)

            Text("·")
                .foregroundStyle(Theme.current.foregroundMuted)

            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(Theme.current.foregroundMuted)

            Spacer()
        }
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
