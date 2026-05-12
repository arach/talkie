//
//  LegacyModelCards.swift
//  Talkie macOS
//
//  Extracted from ModelsContentView.swift
//

import SwiftUI
import os

private let logger = Logger(subsystem: "to.talkie.app.mac", category: "Views")

// MARK: - Whisper Family Card - Integrated Tabular Design

struct WhisperFamilyCard: View {
    let models: [WhisperModel]
    let whisperService: WhisperService
    let downloadingModel: WhisperModel?
    let onDownload: (WhisperModel) -> Void
    let onDelete: (WhisperModel) -> Void
    let onCancel: () -> Void

    private let settings = SettingsManager.shared
    @State private var selectedModelIndex: Int = 0
    @State private var hoveredModelIndex: Int? = nil
    @State private var isHovered = false

    private var displayedModelIndex: Int {
        hoveredModelIndex ?? selectedModelIndex
    }

    private var displayedModel: WhisperModel {
        guard displayedModelIndex < models.count else { return models[0] }
        return models[displayedModelIndex]
    }

    private var selectedModel: WhisperModel {
        guard selectedModelIndex < models.count else { return models[0] }
        return models[selectedModelIndex]
    }

    private var isDownloading: Bool {
        downloadingModel == selectedModel
    }

    private var hasInstalledModel: Bool {
        models.contains { whisperService.isModelDownloaded($0) }
    }

    private func variantLabel(for model: WhisperModel) -> String {
        WhisperModelCatalog.metadata(for: model)?.displayName ?? "—"
    }

    private func accuracy(for model: WhisperModel) -> String {
        guard let meta = WhisperModelCatalog.metadata(for: model) else { return "—" }
        return "\(meta.accuracy)%"
    }

    private func modelSize(for model: WhisperModel) -> String {
        guard let meta = WhisperModelCatalog.metadata(for: model) else { return "—" }
        return "\(meta.sizeMB)MB"
    }

    private func rtf(for model: WhisperModel) -> String {
        guard let meta = WhisperModelCatalog.metadata(for: model) else { return "—" }
        return String(format: "%.2fx", meta.rtf)
    }

    private var repoURL: URL { WhisperModelCatalog.repoURL }
    private var paperURL: URL { WhisperModelCatalog.paperURL }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(alignment: .center) {
                Text("WHISPER")
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(settings.specValueColor)

                Spacer()

                if hasInstalledModel {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(settings.statusActive)
                            .frame(width: 7, height: 7)
                        Text("READY")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(settings.statusActive)
                    }
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 10)

            // Integrated Tab Bar
            HStack(spacing: 0) {
                ForEach(Array(models.enumerated()), id: \.element.rawValue) { index, model in
                    STTModelTab(
                        label: variantLabel(for: model),
                        badge: accuracy(for: model),
                        isSelected: selectedModelIndex == index,
                        isHovered: hoveredModelIndex == index,
                        isInstalled: whisperService.isModelDownloaded(model),
                        isActive: whisperService.loadedModel == model,
                        onTap: { selectedModelIndex = index },
                        onHover: { isHovering in
                            hoveredModelIndex = isHovering ? index : nil
                        }
                    )
                }
                Spacer()
            }

            // Specs area (connected to tabs)
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)

                HStack(spacing: 16) {
                    specCell(label: "SIZE", value: modelSize(for: displayedModel))
                    specCell(label: "RTF", value: rtf(for: displayedModel))
                    specCell(label: "ACC", value: accuracy(for: displayedModel))
                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .animation(.easeInOut(duration: 0.15), value: displayedModelIndex)
            }
            .background(Color.primary.opacity(0.02))

            // Links row
            HStack(spacing: 16) {
                Button(action: { NSWorkspace.shared.open(repoURL) }) {
                    HStack(spacing: 4) {
                        Text("Repo")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)

                Button(action: { NSWorkspace.shared.open(paperURL) }) {
                    HStack(spacing: 4) {
                        Text("Paper")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
            .padding(.bottom, 10)

            Spacer()

            // Action button
            if isDownloading {
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                            Rectangle()
                                .fill(LinearGradient(colors: [.blue.opacity(0.6), .blue.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * CGFloat(whisperService.downloadProgress))
                        }
                    }
                    .frame(height: 4)
                    .cornerRadius(2)

                    HStack {
                        Text("DOWNLOADING \(Int(whisperService.downloadProgress * 100))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.blue.opacity(0.9))
                        Spacer()
                        Button(action: onCancel) {
                            Text("CANCEL")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(settings.statusError)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if whisperService.isModelDownloaded(selectedModel) {
                Button(action: { onDelete(selectedModel) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 11))
                        Text("REMOVE")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(isHovered ? 0.06 : 0.03))
                    .cornerRadius(CornerRadius.xs)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: { onDownload(selectedModel) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12))
                        Text("DOWNLOAD")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(isHovered ? .accentColor : settings.specValueColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        isHovered ? AnyView(Color.accentColor.opacity(0.1)) :
                        AnyView(LinearGradient(colors: [Color.primary.opacity(0.06), Color.primary.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                    )
                    .cornerRadius(CornerRadius.xs)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                            .stroke(isHovered ? Color.accentColor.opacity(0.3) : settings.cardBorderDefault, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(height: 210)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                settings.cardBackgroundDark
                settings.cardBackground
                LinearGradient(colors: [Color.primary.opacity(0.03), Color.clear], startPoint: .top, endPoint: .bottom)
            }
        )
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isHovered ? Theme.current.foreground.opacity(0.2) :
                    hasInstalledModel ? settings.cardBorderActive : settings.cardBorderDefault,
                    lineWidth: isHovered ? 1.5 : 1
                )
        )
        .shadow(color: Theme.current.foreground.opacity(isHovered ? 0.06 : 0), radius: 8, x: 0, y: 0)
        .shadow(color: .black.opacity(isHovered ? 0.15 : 0.08), radius: isHovered ? 8 : 6, y: 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onAppear {
            if let idx = models.firstIndex(where: { whisperService.isModelDownloaded($0) }) {
                selectedModelIndex = idx
            }
        }
    }

    private func specCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(settings.specLabelColor)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(settings.specValueColor)
        }
    }
}

// MARK: - Parakeet Family Card - Integrated Tabular Design

struct ParakeetFamilyCard: View {
    let models: [ParakeetModel]
    let parakeetService: ParakeetService
    let downloadingModel: ParakeetModel?
    let onDownload: (ParakeetModel) -> Void
    let onDelete: (ParakeetModel) -> Void
    let onCancel: () -> Void

    private let settings = SettingsManager.shared
    @State private var selectedModelIndex: Int = 0
    @State private var hoveredModelIndex: Int? = nil
    @State private var isHovered = false

    private var displayedModelIndex: Int {
        hoveredModelIndex ?? selectedModelIndex
    }

    private var displayedModel: ParakeetModel {
        guard displayedModelIndex < models.count else { return models[0] }
        return models[displayedModelIndex]
    }

    private var selectedModel: ParakeetModel {
        guard selectedModelIndex < models.count else { return models[0] }
        return models[selectedModelIndex]
    }

    private var isDownloading: Bool {
        downloadingModel == selectedModel
    }

    private var hasInstalledModel: Bool {
        models.contains { parakeetService.isModelDownloaded($0) }
    }

    private func variantLabel(for model: ParakeetModel) -> String {
        ParakeetModelCatalog.metadata(for: model)?.displayName ?? "—"
    }

    private func languagesBadge(for model: ParakeetModel) -> String {
        ParakeetModelCatalog.metadata(for: model)?.languagesBadge ?? "—"
    }

    private func languagesCount(for model: ParakeetModel) -> String {
        guard let meta = ParakeetModelCatalog.metadata(for: model) else { return "—" }
        return "\(meta.languages)"
    }

    private func modelSize(for model: ParakeetModel) -> String {
        guard let meta = ParakeetModelCatalog.metadata(for: model) else { return "—" }
        return "\(meta.sizeMB)MB"
    }

    private func rtf(for model: ParakeetModel) -> String {
        guard let meta = ParakeetModelCatalog.metadata(for: model) else { return "—" }
        return String(format: "%.2fx", meta.rtf)
    }

    private var repoURL: URL { ParakeetModelCatalog.repoURL }
    private var paperURL: URL { ParakeetModelCatalog.paperURL }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(alignment: .center) {
                Text("PARAKEET")
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(settings.specValueColor)

                Spacer()

                if hasInstalledModel {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(settings.statusActive)
                            .frame(width: 7, height: 7)
                        Text("READY")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(settings.statusActive)
                    }
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 10)

            // Integrated Tab Bar
            HStack(spacing: 0) {
                ForEach(Array(models.enumerated()), id: \.element.rawValue) { index, model in
                    STTModelTab(
                        label: variantLabel(for: model),
                        badge: languagesBadge(for: model),
                        isSelected: selectedModelIndex == index,
                        isHovered: hoveredModelIndex == index,
                        isInstalled: parakeetService.isModelDownloaded(model),
                        isActive: parakeetService.loadedModel == model,
                        onTap: { selectedModelIndex = index },
                        onHover: { isHovering in
                            hoveredModelIndex = isHovering ? index : nil
                        }
                    )
                }
                Spacer()
            }

            // Specs area (connected to tabs)
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)

                HStack(spacing: 16) {
                    specCell(label: "SIZE", value: "~600MB")
                    specCell(label: "RTF", value: "0.05x")
                    specCell(label: "LANG", value: languagesCount(for: displayedModel))
                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .animation(.easeInOut(duration: 0.15), value: displayedModelIndex)
            }
            .background(Color.primary.opacity(0.02))

            // Links row
            HStack(spacing: 16) {
                Button(action: { NSWorkspace.shared.open(repoURL) }) {
                    HStack(spacing: 4) {
                        Text("Repo")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)

                Button(action: { NSWorkspace.shared.open(paperURL) }) {
                    HStack(spacing: 4) {
                        Text("Paper")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
            .padding(.bottom, 10)

            Spacer()

            // Action button
            if isDownloading {
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                            Rectangle()
                                .fill(LinearGradient(colors: [.blue.opacity(0.6), .blue.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * CGFloat(parakeetService.downloadProgress))
                        }
                    }
                    .frame(height: 4)
                    .cornerRadius(2)

                    HStack {
                        Text("DOWNLOADING \(Int(parakeetService.downloadProgress * 100))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.blue.opacity(0.9))
                        Spacer()
                        Button(action: onCancel) {
                            Text("CANCEL")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(settings.statusError)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if parakeetService.isModelDownloaded(selectedModel) {
                Button(action: { onDelete(selectedModel) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 11))
                        Text("REMOVE")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(isHovered ? 0.06 : 0.03))
                    .cornerRadius(CornerRadius.xs)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: { onDownload(selectedModel) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12))
                        Text("DOWNLOAD")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(isHovered ? .accentColor : settings.specValueColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        isHovered ? AnyView(Color.accentColor.opacity(0.1)) :
                        AnyView(LinearGradient(colors: [Color.primary.opacity(0.06), Color.primary.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                    )
                    .cornerRadius(CornerRadius.xs)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                            .stroke(isHovered ? Color.accentColor.opacity(0.3) : settings.cardBorderDefault, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(height: 210)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                settings.cardBackgroundDark
                settings.cardBackground
                LinearGradient(colors: [Color.primary.opacity(0.03), Color.clear], startPoint: .top, endPoint: .bottom)
            }
        )
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isHovered ? Theme.current.foreground.opacity(0.2) :
                    hasInstalledModel ? settings.cardBorderActive : settings.cardBorderDefault,
                    lineWidth: isHovered ? 1.5 : 1
                )
        )
        .shadow(color: Theme.current.foreground.opacity(isHovered ? 0.06 : 0), radius: 8, x: 0, y: 0)
        .shadow(color: .black.opacity(isHovered ? 0.15 : 0.08), radius: isHovered ? 8 : 6, y: 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onAppear {
            if let idx = models.firstIndex(where: { parakeetService.isModelDownloaded($0) }) {
                selectedModelIndex = idx
            }
        }
    }

    private func specCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(settings.specLabelColor)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(settings.specValueColor)
        }
    }
}

// MARK: - STT Model Tab Component

struct STTModelTab: View {
    let label: String
    let badge: String
    let isSelected: Bool
    let isHovered: Bool
    let isInstalled: Bool
    let isActive: Bool
    let onTap: () -> Void
    let onHover: (Bool) -> Void

    private let settings = SettingsManager.shared

    private var isActiveState: Bool { isSelected || isHovered }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text(label)
                        .font(.system(size: 12, weight: isActiveState ? .semibold : .medium, design: .monospaced))

                    if isInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(isActive ? settings.statusActive : settings.statusActive.opacity(0.8))
                    }
                }

                Text(badge)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .foregroundColor(
                isActive ? settings.statusActive :
                isActiveState ? (isInstalled ? settings.statusActive : settings.specValueColor) :
                (isInstalled ? settings.statusActive.opacity(0.7) : .secondary.opacity(0.6))
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isActiveState ? Color.primary.opacity(0.06) : Color.clear
            )
            .overlay(
                Rectangle()
                    .fill(isSelected ? settings.statusActive : Color.clear)
                    .frame(height: 2),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            onHover(hovering)
        }
    }
}
