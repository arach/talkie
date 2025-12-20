//
//  TranscriptionModelCard.swift
//  Talkie
//
//  Model cards for Live transcription engine selection
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "TranscriptionModelCard")

// MARK: - Transcription Model Card

struct TranscriptionModelCard: View {
    let model: ModelInfo
    let isSelected: Bool
    let downloadProgress: DownloadProgress?
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    private let settings = SettingsManager.shared
    @State private var isHovered = false

    private var isDownloading: Bool {
        downloadProgress?.modelId == model.id && downloadProgress?.isDownloading == true
    }

    private var accentColor: Color {
        if model.isLoaded { return .green }
        if model.isDownloaded { return .blue }
        return .secondary
    }

    private var familyBadge: String {
        switch model.family.lowercased() {
        case "whisper": return "WSP"
        case "parakeet": return "PKT"
        default: return String(model.family.prefix(3).uppercased())
        }
    }

    var body: some View {
        Button(action: {
            if model.isDownloaded {
                onSelect()
            }
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    // Family badge
                    Text(familyBadge)
                        .font(settings.monoXS)
                        .foregroundColor(settings.specLabelColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(accentColor.opacity(0.1))
                        .cornerRadius(2)

                    Spacer()

                    // Status indicator
                    if model.isLoaded {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(settings.statusActive)
                                .frame(width: 6, height: 6)
                                .shadow(color: settings.statusActive.opacity(0.5), radius: 3)
                            Text("LOADED")
                                .font(settings.monoXS)
                                .foregroundColor(settings.statusActive)
                        }
                    } else if model.isDownloaded {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.blue)
                                .frame(width: 6, height: 6)
                            Text("READY")
                                .font(settings.monoXS)
                                .foregroundColor(.blue)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 8))
                            Text("AVAILABLE")
                                .font(settings.monoXS)
                        }
                        .foregroundColor(.secondary.opacity(0.8))
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 8)

                // Model name
                Text(model.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(settings.specValueColor)
                    .padding(.bottom, 6)

                // Description
                Text(model.description)
                    .font(settings.fontXS)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)

                // Size info
                HStack {
                    Text("SIZE")
                        .font(settings.monoXS)
                        .foregroundColor(settings.specLabelColor)
                    Spacer()
                    Text(model.sizeDescription)
                        .font(settings.fontSM)
                        .foregroundColor(settings.specValueColor)
                }
                .padding(.bottom, 4)

                // Action buttons or progress
                if isDownloading {
                    // Download progress
                    VStack(spacing: 4) {
                        if let progress = downloadProgress {
                            HStack {
                                Text(progress.progressFormatted)
                                    .font(settings.monoXS)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(progress.sizeFormatted)
                                    .font(settings.monoXS)
                                    .foregroundColor(.secondary)
                            }

                            ProgressView(value: progress.progress)
                                .progressViewStyle(.linear)
                                .tint(.blue)

                            Button("Cancel") {
                                onCancel()
                            }
                            .font(settings.fontXS)
                            .foregroundColor(.red)
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.top, 4)
                } else if model.isDownloaded {
                    // Select or Delete
                    HStack(spacing: 8) {
                        if !model.isLoaded {
                            Button(action: onSelect) {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle")
                                        .font(.system(size: 10))
                                    Text("Select")
                                        .font(settings.fontXS)
                                }
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(.borderless)
                        }

                        Spacer()

                        Button(action: onDelete) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                Text("Delete")
                                    .font(settings.fontXS)
                            }
                            .foregroundColor(.red.opacity(isHovered ? 1.0 : 0.7))
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.top, 4)
                } else {
                    // Download button
                    Button(action: onDownload) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 10))
                            Text("Download")
                                .font(settings.fontXS)
                        }
                        .foregroundColor(.blue)
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 4)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? accentColor.opacity(0.1) : Color.primary.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isSelected ? accentColor.opacity(0.4) : (isHovered ? Color.primary.opacity(0.1) : Color.clear),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview("Downloaded Whisper") {
    TranscriptionModelCard(
        model: ModelInfo(
            id: "whisper:openai_whisper-small",
            family: "whisper",
            modelId: "openai_whisper-small",
            displayName: "Whisper Small",
            sizeDescription: "244 MB",
            description: "Balanced accuracy and speed",
            isDownloaded: true,
            isLoaded: false
        ),
        isSelected: false,
        downloadProgress: nil as DownloadProgress?,
        onSelect: {},
        onDownload: {},
        onDelete: {},
        onCancel: {}
    )
    .frame(width: 300)
    .padding()
}

#Preview("Downloading") {
    TranscriptionModelCard(
        model: ModelInfo(
            id: "whisper:openai_whisper-base",
            family: "whisper",
            modelId: "openai_whisper-base",
            displayName: "Whisper Base",
            sizeDescription: "74 MB",
            description: "Fast and lightweight",
            isDownloaded: false,
            isLoaded: false
        ),
        isSelected: false,
        downloadProgress: DownloadProgress(
            modelId: "whisper:openai_whisper-base",
            progress: 0.45,
            downloadedBytes: 33_000_000,
            totalBytes: 74_000_000,
            isDownloading: true
        ),
        onSelect: {},
        onDownload: {},
        onDelete: {},
        onCancel: {}
    )
    .frame(width: 300)
    .padding()
}

#Preview("Loaded Parakeet") {
    TranscriptionModelCard(
        model: ModelInfo(
            id: "parakeet:v3",
            family: "parakeet",
            modelId: "v3",
            displayName: "Parakeet V3",
            sizeDescription: "120 MB",
            description: "High accuracy streaming model",
            isDownloaded: true,
            isLoaded: true
        ),
        isSelected: true,
        downloadProgress: nil as DownloadProgress?,
        onSelect: {},
        onDownload: {},
        onDelete: {},
        onCancel: {}
    )
    .frame(width: 300)
    .padding()
}
