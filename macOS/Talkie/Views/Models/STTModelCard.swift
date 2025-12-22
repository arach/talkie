//
//  STTModelCard.swift
//  Talkie
//
//  Unified compact card for Speech-to-Text models
//  Used in Models inventory AND Settings transcription selection
//

import SwiftUI

// MARK: - STT Model Card (Unified Style)

struct STTModelCard: View {
    let name: String
    let family: STTFamily
    let size: String
    let speedTier: SpeedTier
    let languageInfo: String
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let onDownload: () -> Void
    let onDelete: () -> Void

    // Optional selection support (for Settings transcription view)
    var isSelected: Bool = false
    var isLoaded: Bool = false
    var onSelect: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    private let settings = SettingsManager.shared
    @State private var isHovered = false

    // MARK: - Convenience init for ModelInfo (from EngineClient)

    init(
        modelInfo: ModelInfo,
        downloadProgress: DownloadProgress?,
        isSelected: Bool = false,
        onSelect: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.name = modelInfo.displayName
        self.family = modelInfo.family.lowercased() == "whisper" ? .whisper : .parakeet
        self.size = modelInfo.sizeDescription
        self.speedTier = Self.inferSpeedTier(from: modelInfo)
        self.languageInfo = Self.inferLanguageInfo(from: modelInfo)
        self.isDownloaded = modelInfo.isDownloaded
        self.isDownloading = downloadProgress?.modelId == modelInfo.id && downloadProgress?.isDownloading == true
        self.downloadProgress = downloadProgress?.modelId == modelInfo.id ? downloadProgress?.progress ?? 0 : 0
        self.isSelected = isSelected
        self.isLoaded = modelInfo.isLoaded
        self.onSelect = onSelect
        self.onDownload = onDownload
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    // Standard init for WhisperModel/ParakeetModel usage
    init(
        name: String,
        family: STTFamily,
        size: String,
        speedTier: SpeedTier,
        languageInfo: String,
        isDownloaded: Bool,
        isDownloading: Bool,
        downloadProgress: Double,
        onDownload: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.name = name
        self.family = family
        self.size = size
        self.speedTier = speedTier
        self.languageInfo = languageInfo
        self.isDownloaded = isDownloaded
        self.isDownloading = isDownloading
        self.downloadProgress = downloadProgress
        self.onDownload = onDownload
        self.onDelete = onDelete
    }

    // MARK: - ModelInfo Helpers

    private static func inferSpeedTier(from modelInfo: ModelInfo) -> SpeedTier {
        let id = modelInfo.modelId.lowercased()

        if modelInfo.family.lowercased() == "parakeet" {
            return .realtime  // All Parakeet models are real-time
        }

        // Whisper tiers based on model size
        if id.contains("tiny") { return .realtime }
        if id.contains("base") { return .fast }
        if id.contains("small") { return .balanced }
        if id.contains("large") || id.contains("distil") { return .accurate }

        return .balanced  // Default
    }

    private static func inferLanguageInfo(from modelInfo: ModelInfo) -> String {
        if modelInfo.family.lowercased() == "parakeet" {
            let id = modelInfo.modelId.lowercased()
            if id.contains("v2") { return "EN" }
            if id.contains("v3") { return "25" }
            return "EN"
        }
        return "99+"  // Whisper supports 99+ languages
    }

    enum STTFamily {
        case whisper
        case parakeet

        var color: Color {
            switch self {
            case .whisper: return .orange
            case .parakeet: return .cyan
            }
        }

        var badge: String {
            switch self {
            case .whisper: return "WSP"
            case .parakeet: return "PKT"
            }
        }

        var icon: String {
            "waveform"
        }
    }

    enum SpeedTier: String {
        case realtime = "Real-time"
        case fast = "Fast"
        case balanced = "Balanced"
        case accurate = "Accurate"

        var color: Color {
            switch self {
            case .realtime: return .green
            case .fast: return .blue
            case .balanced: return .orange
            case .accurate: return .purple
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top accent bar (family color)
            Rectangle()
                .fill(family.color.opacity(isDownloaded ? 1.0 : 0.3))
                .frame(height: 3)

            VStack(alignment: .leading, spacing: 8) {
                // Header: Badge + Status
                HStack {
                    // Family badge
                    Text(family.badge)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(family.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(family.color.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Spacer()

                    // Status badge
                    if isLoaded {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(settings.midnightStatusActive)
                                .frame(width: 5, height: 5)
                                .shadow(color: settings.midnightStatusActive.opacity(0.5), radius: 3)
                            Text("LOADED")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(settings.midnightStatusActive)
                        }
                    } else if isDownloaded {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(settings.midnightStatusReady)
                                .frame(width: 5, height: 5)
                            Text("READY")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(settings.midnightStatusReady)
                        }
                    }
                }

                // Model name
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(settings.midnightTextPrimary)
                    .lineLimit(1)

                // Specs row
                HStack(spacing: 12) {
                    // Size
                    VStack(alignment: .leading, spacing: 1) {
                        Text("SIZE")
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundColor(settings.midnightTextTertiary)
                        Text(size)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(settings.midnightTextSecondary)
                    }

                    // Speed tier
                    VStack(alignment: .leading, spacing: 1) {
                        Text("SPEED")
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundColor(settings.midnightTextTertiary)
                        Text(speedTier.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(speedTier.color)
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

    private var cardBackground: Color {
        if isHovered {
            return settings.midnightSurfaceHover
        }
        return settings.midnightSurface
    }

    private var borderColor: Color {
        if isSelected {
            return family.color.opacity(0.6)
        }
        if isLoaded {
            return settings.midnightStatusActive.opacity(0.4)
        }
        if isDownloaded {
            return settings.midnightStatusReady.opacity(0.3)
        }
        if isHovered {
            return settings.midnightBorderActive
        }
        return settings.midnightBorder
    }

    @ViewBuilder
    private var actionButton: some View {
        if isDownloading {
            // Download progress with cancel option
            VStack(spacing: 3) {
                ProgressView(value: downloadProgress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(family.color)
                HStack {
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(settings.midnightTextTertiary)
                    Spacer()
                    if let onCancel = onCancel {
                        Button("Cancel", action: onCancel)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.red.opacity(0.8))
                            .buttonStyle(.plain)
                    }
                }
            }
        } else if isDownloaded {
            // Select (if selectable) and Delete options
            HStack(spacing: 8) {
                if let onSelect = onSelect, !isLoaded {
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

                Spacer()

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
        } else {
            // Download button
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
}

// MARK: - Whisper Model Extension

extension WhisperModel {
    var sttCardName: String {
        switch self {
        case .tiny: return "Whisper Tiny"
        case .base: return "Whisper Base"
        case .small: return "Whisper Small"
        case .distilLargeV3: return "Whisper Large V3"
        }
    }

    var sttCardSize: String {
        switch self {
        case .tiny: return "~75 MB"
        case .base: return "~150 MB"
        case .small: return "~500 MB"
        case .distilLargeV3: return "~1.5 GB"
        }
    }

    var sttSpeedTier: STTModelCard.SpeedTier {
        switch self {
        case .tiny: return .realtime
        case .base: return .fast
        case .small: return .balanced
        case .distilLargeV3: return .accurate
        }
    }

    var sttLanguages: String {
        "99+"  // Whisper supports 99 languages
    }
}

// MARK: - Parakeet Model Extension

extension ParakeetModel {
    var sttCardName: String {
        switch self {
        case .v2: return "Parakeet V2"
        case .v3: return "Parakeet V3"
        }
    }

    var sttCardSize: String {
        switch self {
        case .v2: return "~200 MB"
        case .v3: return "~250 MB"
        }
    }

    var sttSpeedTier: STTModelCard.SpeedTier {
        .realtime  // Parakeet is optimized for real-time
    }

    var sttLanguages: String {
        switch self {
        case .v2: return "EN"
        case .v3: return "25"
        }
    }
}

// MARK: - Preview

#Preview("STT Model Cards") {
    let settings = SettingsManager.shared

    LazyVGrid(columns: [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ], spacing: 12) {
        STTModelCard(
            name: "Parakeet V3",
            family: .parakeet,
            size: "~250 MB",
            speedTier: .realtime,
            languageInfo: "25",
            isDownloaded: true,
            isDownloading: false,
            downloadProgress: 0,
            onDownload: {},
            onDelete: {}
        )

        STTModelCard(
            name: "Whisper Small",
            family: .whisper,
            size: "~500 MB",
            speedTier: .balanced,
            languageInfo: "99+",
            isDownloaded: true,
            isDownloading: false,
            downloadProgress: 0,
            onDownload: {},
            onDelete: {}
        )

        STTModelCard(
            name: "Whisper Large V3",
            family: .whisper,
            size: "~1.5 GB",
            speedTier: .accurate,
            languageInfo: "99+",
            isDownloaded: false,
            isDownloading: false,
            downloadProgress: 0,
            onDownload: {},
            onDelete: {}
        )

        STTModelCard(
            name: "Whisper Tiny",
            family: .whisper,
            size: "~75 MB",
            speedTier: .realtime,
            languageInfo: "99+",
            isDownloaded: false,
            isDownloading: true,
            downloadProgress: 0.45,
            onDownload: {},
            onDelete: {}
        )
    }
    .padding(24)
    .background(settings.midnightBase)
    .frame(width: 700, height: 350)
}
