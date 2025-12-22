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
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(EngineClient.self) private var engineClient
    @Environment(LiveSettings.self) private var liveSettings

    @State private var showingDeleteConfirmation: (Bool, ModelInfo?) = (false, nil)
    @State private var expandedModel: String? = nil

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Header with breadcrumb
                VStack(alignment: .leading, spacing: 6) {
                    Text("LIVE / SETTINGS / TRANSCRIPTION")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(settingsManager.midnightTextTertiary)

                    Text("TRANSCRIPTION")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(settingsManager.midnightTextPrimary)

                    Text("Configure the speech-to-text engine. Models are downloaded and managed by the engine.")
                        .font(.system(size: 12))
                        .foregroundColor(settingsManager.midnightTextSecondary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Engine Status Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(settingsManager.midnightAccentCloud)
                            .frame(width: 3, height: 14)

                        Text("ENGINE SERVICE")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(settingsManager.midnightTextSecondary)

                        Spacer()

                        Text("SERVICE STATUS")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(settingsManager.midnightTextTertiary)
                    }

                    engineStatusCard
                }
                .padding(.horizontal, 24)

                Divider()
                    .padding(.horizontal, 24)

                // Transcription Models Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(settingsManager.midnightAccentSTT)
                            .frame(width: 3, height: 14)

                        Text("TRANSCRIPTION MODELS")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(settingsManager.midnightTextSecondary)

                        Spacer()

                        Text("SELECT & DOWNLOAD")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(settingsManager.midnightTextTertiary)
                    }

                    modelsSection
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 40)
            }
        }
        .background(settingsManager.midnightBase)
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

    // MARK: - Engine Status Card

    private var engineStatusCard: some View {
        HStack(spacing: 12) {
            // Status icon
            RoundedRectangle(cornerRadius: 6)
                .fill(settingsManager.midnightSurfaceElevated)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "cpu")
                        .font(.system(size: 14))
                        .foregroundColor(settingsManager.midnightTextSecondary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("TalkieEngine".uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(settingsManager.midnightTextPrimary)
                Text(engineClient.status?.loadedModelId ?? "No model loaded")
                    .font(.system(size: 10))
                    .foregroundColor(settingsManager.midnightTextTertiary)
            }

            Spacer()

            // Connection status - shows if service is running
            Group {
                if engineClient.connectionState == .connected {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(settingsManager.midnightStatusReady)
                            .frame(width: 6, height: 6)
                        Text("RUNNING")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(settingsManager.midnightStatusReady)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(settingsManager.midnightStatusReady.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(settingsManager.midnightStatusReady.opacity(0.25), lineWidth: 1))
                } else {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                        Text("STOPPED")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.orange.opacity(0.25), lineWidth: 1))
                }
            }
        }
        .padding(16)
        .background(settingsManager.midnightSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(settingsManager.midnightBorder, lineWidth: 1)
        )
        .cornerRadius(8)
    }

    // MARK: - Models Section

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(engineClient.availableModels) { model in
                ExpandableTranscriptionModelCard(
                    model: model,
                    isExpanded: expandedModel == model.id,
                    isSelected: settingsManager.liveTranscriptionModelId == model.id,
                    downloadProgress: engineClient.downloadProgress?.progress,
                    onToggle: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedModel = expandedModel == model.id ? nil : model.id
                        }
                    },
                    onSelect: {
                        selectModel(model)
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

    private func selectModel(_ model: ModelInfo) {
        settingsManager.liveTranscriptionModelId = model.id

        // Preload the model in the engine
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
        // Download via EngineClient
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
        // The EngineClient doesn't currently have a deleteModel method
    }
}

// MARK: - Expandable Transcription Model Card

struct ExpandableTranscriptionModelCard: View {
    let model: ModelInfo
    let isExpanded: Bool
    let isSelected: Bool
    let downloadProgress: Double?
    let onToggle: () -> Void
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    private let settings = SettingsManager.shared
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row (always visible)
            Button(action: onToggle) {
                modelHeaderRow
            }
            .buttonStyle(.expandableRow)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                        .background(settings.midnightBorder)
                        .padding(.horizontal, 16)

                    // Model details
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.description.isEmpty ? "High-quality speech recognition" : model.description)
                            .font(.system(size: 11))
                            .foregroundColor(settings.midnightTextSecondary)

                        // Actions
                        HStack(spacing: 8) {
                            if model.isDownloaded {
                                if !isSelected {
                                    Button(action: onSelect) {
                                        Text("Select")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(settings.resolvedAccentColor)
                                            .cornerRadius(4)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Button(action: onDelete) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 10))
                                        Text("Delete")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            } else if let progress = downloadProgress, progress > 0 {
                                HStack(spacing: 8) {
                                    ProgressView(value: progress, total: 1.0)
                                        .frame(width: 100)
                                    Text("\(Int(progress * 100))%")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(settings.midnightTextSecondary)
                                    Button(action: onCancel) {
                                        Text("Cancel")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else {
                                Button(action: onDownload) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .font(.system(size: 10))
                                        Text("Download")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .foregroundColor(settings.resolvedAccentColor)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(settings.resolvedAccentColor.opacity(0.1))
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? settings.midnightSurfaceHover : settings.midnightSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isExpanded || isSelected ? settings.midnightBorderActive : (isHovered ? settings.midnightBorderActive : settings.midnightBorder),
                    lineWidth: 1
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var modelHeaderRow: some View {
        HStack(spacing: 12) {
            // Model icon
            RoundedRectangle(cornerRadius: 6)
                .fill(settings.midnightSurfaceElevated)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 14))
                        .foregroundColor(settings.midnightTextSecondary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName.uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(settings.midnightTextPrimary)
                Text(model.family.capitalized)
                    .font(.system(size: 10))
                    .foregroundColor(settings.midnightTextTertiary)
            }
            .frame(minWidth: 100, alignment: .leading)

            // Description
            Text(modelDescription)
                .font(.system(size: 11))
                .foregroundColor(settings.midnightTextSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            modelSizeView

            statusBadge

            // Expand chevron
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(settings.midnightTextTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var modelSizeView: some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text("SIZE")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(settings.midnightTextTertiary)
                Text(model.sizeDescription)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(settings.midnightTextPrimary)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        Group {
            if isSelected {
                // Model is loaded in memory and active
                statusBadgeContent(
                    color: settings.midnightStatusActive,
                    text: "ACTIVE"
                )
            } else if model.isDownloaded {
                // Model is downloaded but not loaded
                statusBadgeContent(
                    color: settings.midnightStatusReady,
                    text: "DOWNLOADED"
                )
            } else {
                // Not downloaded - show subtle indicator
                Text("—")
                    .font(.system(size: 11))
                    .foregroundColor(settings.midnightTextTertiary)
            }
        }
        .frame(width: 100, alignment: .trailing)
    }

    private func statusBadgeContent(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
    }

    private var modelDescription: String {
        switch model.id {
        case let id where id.contains("tiny"):
            return "Fastest, basic quality"
        case let id where id.contains("base"):
            return "Fast, good quality"
        case let id where id.contains("small"):
            return "Balanced speed/quality"
        case let id where id.contains("medium"):
            return "High quality, slower"
        case let id where id.contains("large"):
            return "Best quality, slowest"
        case let id where id.contains("distil"):
            return "Best quality, slower"
        case let id where id.contains("parakeet"):
            return "25 languages, fast"
        default:
            return "High-quality speech recognition"
        }
    }
}
#Preview {
    TranscriptionModelsSettingsView()
        .frame(width: 900, height: 700)
}
