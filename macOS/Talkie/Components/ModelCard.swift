//
//  ModelCard.swift
//  Talkie
//
//  Generic card component for AI models (STT and TTS).
//  Provides consistent UI for download, load, select, and unload actions.
//

import SwiftUI
import TalkieKit

// MARK: - Model Card

/// Generic card for displaying AI model information and actions
struct ModelCard<DetailContent: View>: View {
    // MARK: - Properties

    let name: String
    let provider: ModelProvider
    let state: ModelState
    let isSelected: Bool
    let downloadProgress: Double?

    // Actions
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void
    let onUnload: (() -> Void)?

    // Custom detail content (size, speed, language, etc.)
    @ViewBuilder let detailContent: () -> DetailContent

    private let settings = SettingsManager.shared
    @State private var isHovered = false

    // MARK: - Initializer

    init(
        name: String,
        provider: ModelProvider,
        state: ModelState,
        isSelected: Bool = false,
        downloadProgress: Double? = nil,
        onSelect: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onUnload: (() -> Void)? = nil,
        @ViewBuilder detailContent: @escaping () -> DetailContent
    ) {
        self.name = name
        self.provider = provider
        self.state = state
        self.isSelected = isSelected
        self.downloadProgress = downloadProgress
        self.onSelect = onSelect
        self.onDownload = onDownload
        self.onDelete = onDelete
        self.onCancel = onCancel
        self.onUnload = onUnload
        self.detailContent = detailContent
    }

    // MARK: - Computed Properties

    private var accentColor: Color {
        ModelAccentColor.color(for: provider)
    }

    private var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    private var effectiveProgress: Double {
        if case .downloading(let progress) = state {
            return progress
        }
        return downloadProgress ?? 0
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top accent bar
            Rectangle()
                .fill(accentColor.opacity(state.isOnDisk ? 1.0 : 0.3))
                .frame(height: 3)

            VStack(alignment: .leading, spacing: 8) {
                // Header: Provider badge + Status
                HStack {
                    ProviderBadge(provider: provider)

                    Spacer()

                    ModelStatusBadge(state: state, isActive: isSelected && state.isInMemory)
                }

                // Model name
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(settings.midnightTextPrimary)
                    .lineLimit(1)

                // Custom detail content (specs, language, etc.)
                detailContent()

                Spacer(minLength: 4)

                // Action button
                actionButton
            }
            .padding(10)
        }
        .frame(height: 130)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Card Styling

    private var cardBackground: Color {
        isHovered ? settings.midnightSurfaceHover : settings.midnightSurface
    }

    private var borderColor: Color {
        if isSelected {
            return accentColor.opacity(0.6)
        }
        if state.isInMemory {
            return settings.midnightStatusActive.opacity(0.4)
        }
        if state.isOnDisk {
            return settings.midnightStatusReady.opacity(0.3)
        }
        if isHovered {
            return settings.midnightBorderActive
        }
        return settings.midnightBorder
    }

    // MARK: - Action Button

    @ViewBuilder
    private var actionButton: some View {
        if isDownloading {
            // Download progress
            DownloadProgressView(
                progress: effectiveProgress,
                accentColor: accentColor,
                onCancel: onCancel
            )
        } else if case .loading = state {
            // Loading indicator
            ModelLoadingIndicator(label: "Loading...")
        } else if state.isOnDisk {
            // Downloaded: Select, Unload, or Delete
            downloadedActions
        } else {
            // Not downloaded: Download button
            downloadButton
        }
    }

    @ViewBuilder
    private var downloadedActions: some View {
        HStack(spacing: 8) {
            // Select button (if not already loaded/active)
            if !state.isInMemory {
                Button(action: onSelect) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 9))
                        Text("Select")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }

            // Unload button (if loaded and not selected, and handler provided)
            if state.isInMemory && !isSelected, let onUnload {
                Button(action: onUnload) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 9))
                        Text("Unload")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Delete button
            Button(action: onDelete) {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                    Text("Remove")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(settings.midnightTextTertiary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.5)
        }
        .padding(.vertical, 2)
    }

    private var downloadButton: some View {
        Button(action: onDownload) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 10))
                Text("Download")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(settings.midnightTextSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(settings.midnightSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(settings.midnightBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Convenience Init (No Detail Content)

extension ModelCard where DetailContent == EmptyView {
    init(
        name: String,
        provider: ModelProvider,
        state: ModelState,
        isSelected: Bool = false,
        downloadProgress: Double? = nil,
        onSelect: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onUnload: (() -> Void)? = nil
    ) {
        self.name = name
        self.provider = provider
        self.state = state
        self.isSelected = isSelected
        self.downloadProgress = downloadProgress
        self.onSelect = onSelect
        self.onDownload = onDownload
        self.onDelete = onDelete
        self.onCancel = onCancel
        self.onUnload = onUnload
        self.detailContent = { EmptyView() }
    }
}

// MARK: - STT Model Card Detail

/// Detail content for STT models showing size, speed, and language support
struct STTModelCardDetail: View {
    let sizeDescription: String
    let speedTier: STTSpeedTier
    let languageInfo: String

    private let settings = SettingsManager.shared

    var body: some View {
        HStack(spacing: 12) {
            // Size
            VStack(alignment: .leading, spacing: 1) {
                Text("SIZE")
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundColor(settings.midnightTextTertiary)
                Text(sizeDescription)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(settings.midnightTextSecondary)
            }

            // Speed tier
            VStack(alignment: .leading, spacing: 1) {
                Text("SPEED")
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundColor(settings.midnightTextTertiary)
                SpeedTierBadge(tier: speedTier)
            }

            Spacer()

            // Languages
            VStack(alignment: .trailing, spacing: 1) {
                Text("LANG")
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundColor(settings.midnightTextTertiary)
                Text(languageInfo)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(settings.midnightTextSecondary)
            }
        }
    }
}

// MARK: - TTS Voice Card Detail

/// Detail content for TTS voices showing language and memory usage
struct TTSVoiceCardDetail: View {
    let language: String
    let memoryMB: Int?
    let isLocal: Bool

    private let settings = SettingsManager.shared

    var body: some View {
        HStack(spacing: 12) {
            // Language
            VStack(alignment: .leading, spacing: 1) {
                Text("LANGUAGE")
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundColor(settings.midnightTextTertiary)
                Text(language)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(settings.midnightTextSecondary)
            }

            Spacer()

            // Memory (if available)
            if let memoryMB {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("MEMORY")
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundColor(settings.midnightTextTertiary)
                    MemoryBadge(memoryMB: memoryMB)
                }
            }

            // Local/Cloud badge
            LocalCloudBadge(isLocal: isLocal)
        }
    }
}

// MARK: - Preview

#Preview("Model Cards") {
    let settings = SettingsManager.shared

    LazyVGrid(columns: [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ], spacing: 12) {
        // STT Model - Downloaded and loaded
        ModelCard(
            name: "Parakeet V3",
            provider: .parakeet,
            state: .loaded,
            isSelected: true,
            onSelect: {},
            onDownload: {},
            onDelete: {},
            onCancel: {}
        ) {
            STTModelCardDetail(
                sizeDescription: "~250 MB",
                speedTier: .realtime,
                languageInfo: "25"
            )
        }

        // STT Model - Downloaded, not loaded
        ModelCard(
            name: "Whisper Small",
            provider: .whisper,
            state: .downloaded,
            onSelect: {},
            onDownload: {},
            onDelete: {},
            onCancel: {}
        ) {
            STTModelCardDetail(
                sizeDescription: "~500 MB",
                speedTier: .balanced,
                languageInfo: "99+"
            )
        }

        // STT Model - Not downloaded
        ModelCard(
            name: "Whisper Large V3",
            provider: .whisper,
            state: .notDownloaded,
            onSelect: {},
            onDownload: {},
            onDelete: {},
            onCancel: {}
        ) {
            STTModelCardDetail(
                sizeDescription: "~1.5 GB",
                speedTier: .accurate,
                languageInfo: "99+"
            )
        }

        // STT Model - Downloading
        ModelCard(
            name: "Whisper Tiny",
            provider: .whisper,
            state: .downloading(progress: 0.45),
            onSelect: {},
            onDownload: {},
            onDelete: {},
            onCancel: {}
        ) {
            STTModelCardDetail(
                sizeDescription: "~75 MB",
                speedTier: .realtime,
                languageInfo: "99+"
            )
        }

        // TTS Voice - Loaded
        ModelCard(
            name: "Kokoro",
            provider: .kokoro,
            state: .loaded,
            isSelected: true,
            onSelect: {},
            onDownload: {},
            onDelete: {},
            onCancel: {},
            onUnload: {}
        ) {
            TTSVoiceCardDetail(
                language: "en-US",
                memoryMB: 800,
                isLocal: true
            )
        }

        // TTS Voice - Not loaded
        ModelCard(
            name: "ElevenLabs",
            provider: .elevenLabs,
            state: .downloaded,
            onSelect: {},
            onDownload: {},
            onDelete: {},
            onCancel: {}
        ) {
            TTSVoiceCardDetail(
                language: "en-US",
                memoryMB: nil,
                isLocal: false
            )
        }
    }
    .padding(24)
    .background(settings.midnightBase)
    .frame(width: 500, height: 500)
}
