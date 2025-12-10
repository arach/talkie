//
//  ExpandableModelCards.swift
//  Talkie macOS
//
//  Extracted from ModelsContentView.swift
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

// MARK: - Expandable Model Family Card (New Design)

struct ExpandableModelFamilyCard: View {
    let family: ModelsContentView.ModelFamilyInfo
    let models: [LLMModel]
    let isExpanded: Bool
    let downloadingModelId: String?
    let downloadProgress: Double
    let onToggle: () -> Void
    let onDownload: (LLMModel) -> Void
    let onDelete: (LLMModel) -> Void
    let onCancel: () -> Void

    @StateObject private var settings = SettingsManager.shared
    @State private var isHovered = false

    private var hasInstalledModel: Bool {
        models.contains { $0.isInstalled }
    }

    private var activeModel: LLMModel? {
        models.first { $0.isInstalled }
    }

    private func specValue(for prefix: String) -> (params: String, quant: String) {
        // Get from first model in family
        if let first = models.first, let def = MLXModelCatalog.model(byId: first.id) {
            return (def.size, def.quantization)
        }
        return ("—", "—")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row (always visible)
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    // Family icon placeholder
                    RoundedRectangle(cornerRadius: 6)
                        .fill(settings.midnightSurfaceElevated)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(String(family.name.prefix(1)))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(settings.midnightTextSecondary)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(family.name.uppercased())
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(settings.midnightTextPrimary)
                        Text(family.provider)
                            .font(.system(size: 10))
                            .foregroundColor(settings.midnightTextTertiary)
                    }
                    .frame(width: 70, alignment: .leading)

                    // Description (truncated)
                    Text(family.description)
                        .font(.system(size: 11))
                        .foregroundColor(settings.midnightTextSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: 200, alignment: .leading)

                    Spacer()

                    // Specs preview
                    HStack(spacing: 16) {
                        VStack(spacing: 1) {
                            Text("PARAMS")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(settings.midnightTextTertiary)
                            Text(specValue(for: family.prefix).params)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(settings.midnightTextPrimary)
                        }

                        VStack(spacing: 1) {
                            Text("QUANT")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(settings.midnightTextTertiary)
                            Text(specValue(for: family.prefix).quant)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(settings.midnightTextPrimary)
                        }
                    }

                    // Status - Fixed width to prevent layout shift
                    Group {
                        if hasInstalledModel {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(settings.midnightStatusReady)
                                    .frame(width: 6, height: 6)
                                Text("READY")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(settings.midnightStatusReady)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(settings.midnightStatusReady.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(settings.midnightStatusReady.opacity(0.25), lineWidth: 1))
                        } else {
                            // Empty space when not installed
                            Color.clear
                        }
                    }
                    .frame(width: 70, alignment: .trailing)

                    // Expand chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(settings.midnightTextTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.expandableRow)

            // Expanded content - variant list with table header
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                        .background(settings.midnightBorder)
                        .padding(.horizontal, 16)

                    // Table header
                    HStack(spacing: 0) {
                        Text("VARIANT")
                            .frame(width: 120, alignment: .leading)
                        Text("SIZE")
                            .frame(width: 60, alignment: .leading)
                        Text("SPECS")
                            .frame(width: 50, alignment: .leading)
                        Text("FEATURES")
                            .frame(width: 60, alignment: .leading)
                        Spacer()
                        Text("ACTION")
                            .frame(width: 100, alignment: .trailing)
                    }
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(settings.midnightTextTertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    // Variant rows
                    ForEach(models, id: \.id) { model in
                        ModelVariantRow(
                            model: model,
                            isDownloading: downloadingModelId == model.id,
                            downloadProgress: downloadProgress,
                            onDownload: { onDownload(model) },
                            onDelete: { onDelete(model) }
                        )
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? settings.midnightSurfaceHover : settings.midnightSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isExpanded ? settings.midnightBorderActive : (isHovered ? settings.midnightBorderActive : settings.midnightBorder),
                    lineWidth: 1
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Model Variant Row (Simplified)

struct ModelVariantRow: View {
    let model: LLMModel
    let isDownloading: Bool
    let downloadProgress: Double
    let onDownload: () -> Void
    let onDelete: () -> Void

    @StateObject private var settings = SettingsManager.shared
    @State private var isHovered = false

    private var catalogDef: MLXModelDefinition? {
        MLXModelCatalog.model(byId: model.id)
    }

    private var variantName: String {
        if model.id.contains("1B") && !model.id.contains("1.5B") { return "1B Instruct" }
        if model.id.contains("1.5B") { return "1.5B Instruct" }
        if model.id.contains("3B") { return "3B Instruct" }
        if model.id.contains("3.5") { return "3.5 Mini" }
        if model.id.contains("7B") { return "7B Instruct" }
        if model.id.contains("8B") { return "8B Instruct" }
        if model.id.contains("70B") { return "70B Instruct" }
        return model.displayName
    }

    private var variantSubtitle: String {
        if model.id.contains("1B") && !model.id.contains("1.5B") { return "Mobile friendly" }
        if model.id.contains("1.5B") { return "Compact" }
        if model.id.contains("3B") || model.id.contains("3.5") { return "Entry level" }
        if model.id.contains("7B") || model.id.contains("8B") { return "Standard" }
        if model.id.contains("70B") { return "High capabilities" }
        return ""
    }

    var body: some View {
        HStack(spacing: 0) {
            // VARIANT column - name with subtitle
            VStack(alignment: .leading, spacing: 1) {
                Text(variantName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(model.isInstalled ? settings.midnightStatusReady : settings.midnightTextPrimary)
                if !variantSubtitle.isEmpty {
                    Text(variantSubtitle)
                        .font(.system(size: 9))
                        .foregroundColor(settings.midnightTextTertiary)
                }
            }
            .frame(width: 120, alignment: .leading)

            // SIZE column - plain text, no icons
            Text(catalogDef?.diskSize ?? "—")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(settings.midnightTextSecondary)
                .frame(width: 60, alignment: .leading)

            // SPECS column
            Text("—")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(settings.midnightTextTertiary)
                .frame(width: 50, alignment: .leading)

            // FEATURES column
            Text(catalogDef?.quantization ?? "4-bit")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(settings.midnightTextSecondary)
                .frame(width: 60, alignment: .leading)

            Spacer()

            // ACTION column
            Group {
                if isDownloading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.5)
                        Text("\(Int(downloadProgress * 100))%")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(settings.midnightTextTertiary)
                    }
                } else if model.isInstalled {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                            Text("READY")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(settings.midnightStatusReady)

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundColor(settings.midnightTextTertiary)
                        }
                        .buttonStyle(.iconDestructive)
                    }
                } else {
                    Button(action: onDownload) {
                        HStack(spacing: 4) {
                            Text("DOWNLOAD")
                                .font(.system(size: 9, weight: .semibold))
                            Image(systemName: "arrow.down")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(settings.midnightTextSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(settings.midnightButtonPrimary)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(isHovered ? settings.midnightSurfaceElevated : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Expandable STT Card

struct ExpandableSTTCard<Content: View>: View {
    let name: String
    let provider: String
    let description: String
    let isRecommended: Bool
    let isExpanded: Bool
    let isActive: Bool
    let hasInstalledModel: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: () -> Content

    @StateObject private var settings = SettingsManager.shared
    @State private var isHovered = false

    private func specValues() -> (size: String, rtf: String) {
        if name == "Whisper" {
            return ("39MB", "0.07x")
        } else {
            return ("600MB", "0.05x")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    // Icon placeholder
                    RoundedRectangle(cornerRadius: 6)
                        .fill(settings.midnightSurfaceElevated)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: name == "Whisper" ? "waveform" : "bolt.fill")
                                .font(.system(size: 14))
                                .foregroundColor(settings.midnightTextSecondary)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(name.uppercased())
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(settings.midnightTextPrimary)
                        Text(provider)
                            .font(.system(size: 10))
                            .foregroundColor(settings.midnightTextTertiary)
                    }
                    .frame(width: 70, alignment: .leading)

                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(settings.midnightTextSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Specs
                    HStack(spacing: 12) {
                        VStack(spacing: 1) {
                            Text("SIZE")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(settings.midnightTextTertiary)
                            Text(specValues().size)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(settings.midnightTextPrimary)
                        }

                        VStack(spacing: 1) {
                            Text("RTF")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(settings.midnightTextTertiary)
                            Text(specValues().rtf)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(settings.midnightTextPrimary)
                        }
                    }

                    // Status - Fixed width with consistent pill treatment
                    Group {
                        if isActive {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(settings.midnightStatusActive)
                                    .frame(width: 6, height: 6)
                                    .shadow(color: settings.midnightStatusActive.opacity(0.5), radius: 3, x: 0, y: 0)
                                Text("ACTIVE")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(settings.midnightStatusActive)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(settings.midnightStatusActive.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(settings.midnightStatusActive.opacity(0.3), lineWidth: 1))
                        } else if hasInstalledModel {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(settings.midnightStatusReady)
                                    .frame(width: 6, height: 6)
                                Text("READY")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(settings.midnightStatusReady)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(settings.midnightStatusReady.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(settings.midnightStatusReady.opacity(0.25), lineWidth: 1))
                        } else {
                            // Empty space when not installed
                            Color.clear
                        }
                    }
                    .frame(width: 70, alignment: .trailing)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(settings.midnightTextTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.expandableRow)

            if isExpanded {
                Divider()
                    .background(settings.midnightBorder)
                    .padding(.horizontal, 16)
                content()
                    .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? settings.midnightSurfaceHover : settings.midnightSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isExpanded ? settings.midnightBorderActive : (isHovered ? settings.midnightBorderActive : settings.midnightBorder),
                    lineWidth: 1
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Whisper Variant Table

struct WhisperVariantTable: View {
    let whisperService: WhisperService
    let downloadingModel: WhisperModel?
    let onDownload: (WhisperModel) -> Void
    let onDelete: (WhisperModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(WhisperModel.allCases, id: \.rawValue) { model in
                let meta = WhisperModelCatalog.metadata(for: model)
                STTVariantRow(
                    name: meta?.displayName ?? model.rawValue,
                    size: "\(meta?.sizeMB ?? 0)MB",
                    accuracy: "\(meta?.accuracy ?? 0)%",
                    rtf: String(format: "%.2fx", meta?.rtf ?? 0),
                    isInstalled: whisperService.isModelDownloaded(model),
                    isActive: whisperService.loadedModel == model,
                    isDownloading: downloadingModel == model,
                    onDownload: { onDownload(model) },
                    onDelete: { onDelete(model) }
                )
            }
        }
    }
}

// MARK: - Parakeet Variant Table

struct ParakeetVariantTable: View {
    let parakeetService: ParakeetService
    let downloadingModel: ParakeetModel?
    let onDownload: (ParakeetModel) -> Void
    let onDelete: (ParakeetModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ParakeetModel.allCases, id: \.rawValue) { model in
                let meta = ParakeetModelCatalog.metadata(for: model)
                STTVariantRow(
                    name: meta?.displayName ?? model.rawValue,
                    size: "\(meta?.sizeMB ?? 0)MB",
                    accuracy: meta?.languagesBadge ?? "—",
                    rtf: String(format: "%.2fx", meta?.rtf ?? 0),
                    isInstalled: parakeetService.isModelDownloaded(model),
                    isActive: parakeetService.loadedModel == model,
                    isDownloading: downloadingModel == model,
                    onDownload: { onDownload(model) },
                    onDelete: { onDelete(model) }
                )
            }
        }
    }
}

// MARK: - STT Variant Row (Simplified)

struct STTVariantRow: View {
    let name: String
    let size: String
    let accuracy: String
    let rtf: String
    let isInstalled: Bool
    let isActive: Bool
    let isDownloading: Bool
    let onDownload: () -> Void
    let onDelete: () -> Void

    @StateObject private var settings = SettingsManager.shared
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Name column - fixed width for table alignment
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(settings.midnightTextPrimary)
                .frame(width: 50, alignment: .leading)

            // Specs column - fixed position after name
            HStack(spacing: 6) {
                Text("·")
                    .foregroundColor(settings.midnightTextTertiary)

                Text("\(size) · \(rtf)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(settings.midnightTextTertiary)
            }

            Spacer()

            // Status/Action - fixed width
            Group {
                if isDownloading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.5)
                        Text("...")
                            .font(.system(size: 10))
                            .foregroundColor(settings.midnightTextTertiary)
                    }
                } else if isInstalled {
                    if isActive {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(settings.midnightStatusActive)
                                .frame(width: 5, height: 5)
                                .shadow(color: settings.midnightStatusActive.opacity(0.5), radius: 2, x: 0, y: 0)
                            Text("ACTIVE")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(settings.midnightStatusActive)
                        }
                    } else {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(settings.midnightStatusReady)
                                .frame(width: 5, height: 5)
                            Text("READY")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(settings.midnightStatusReady)
                        }
                    }
                } else {
                    Button(action: onDownload) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 10))
                            Text("GET")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(settings.midnightTextSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(settings.midnightButtonPrimary)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isHovered ? settings.midnightSurfaceElevated : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

