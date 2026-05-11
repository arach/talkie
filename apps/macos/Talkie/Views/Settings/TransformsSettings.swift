//
//  TransformsSettings.swift
//  Talkie macOS
//
//  Rules settings: engine picker + symbolic mapping
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

// MARK: - Rules Settings

/// Engine selection and transform rules applied to transcriptions
struct RulesSettingsView: View {
    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "arrow.right.arrow.left",
                title: "RULES",
                subtitle: "Engine selection and post-processing rules for transcriptions."
            )
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Engine picker (simple toggle)
                    EnginePickerSection()

                    // Symbolic mapping rules
                    TransformRulesContent()
                }
                .padding(Spacing.lg)
            }
        }
        .onAppear {
            log.debug("RulesSettingsView appeared")
        }
    }
}

// MARK: - Engine Picker Section

/// Simple picker for selecting the active STT model from downloaded models
struct EnginePickerSection: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(EngineClient.self) private var engineClient

    private var downloadedModels: [(id: String, name: String)] {
        var models: [(id: String, name: String)] = []

        for meta in ParakeetModelCatalog.metadata {
            let modelId = "parakeet:\(meta.model.rawValue)"
            if engineClient.modelStatus(for: modelId).isDownloaded {
                models.append((id: modelId, name: "Parakeet \(meta.displayName)"))
            }
        }

        for meta in WhisperModelCatalog.metadata {
            let modelId = "whisper:\(meta.model.rawValue)"
            if engineClient.modelStatus(for: modelId).isDownloaded {
                models.append((id: modelId, name: "Whisper \(meta.displayName)"))
            }
        }

        return models
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "waveform")
                    .font(.system(size: 10))
                    .foregroundColor(.cyan)
                Text("ENGINE")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            if downloadedModels.isEmpty {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text("No models downloaded. Install models in AI → Models → STT.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }
                .padding(Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.current.backgroundSecondary)
                .cornerRadius(CornerRadius.md)
            } else {
                VStack(spacing: 0) {
                    ForEach(downloadedModels, id: \.id) { model in
                        let isSelected = settingsManager.liveTranscriptionModelId == model.id
                        let isLoaded = engineClient.modelStatus(for: model.id).isLoaded

                        Button {
                            settingsManager.liveTranscriptionModelId = model.id
                            Task {
                                try? await engineClient.preloadModel(model.id)
                            }
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 12))
                                    .foregroundColor(isSelected ? .cyan : Theme.current.foregroundMuted)

                                Text(model.name)
                                    .font(Theme.current.fontSM)
                                    .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)

                                if isLoaded {
                                    Text("LOADED")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.green.opacity(0.15))
                                        .cornerRadius(3)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.sm)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Theme.current.backgroundSecondary)
                .cornerRadius(CornerRadius.md)
            }
        }
    }
}

// MARK: - Previews

#Preview("Rules") {
    RulesSettingsView()
        .environment(SettingsManager.shared)
        .environment(EngineClient.shared)
        .frame(width: 600, height: 600)
}
