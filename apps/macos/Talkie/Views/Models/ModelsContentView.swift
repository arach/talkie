//
//  ModelsContentView.swift
//  Talkie macOS
//
//  Provider-first model selection for Talkie.
//

import SwiftUI
import TalkieKit

private let modelsLog = Log(.ui)

struct ModelsContentView: View {
    private let registry = LLMProviderRegistry.shared
    private let parakeetService = ParakeetService.shared

    @Environment(SettingsManager.self) private var settingsManager
    @State private var downloadingParakeet = false
    @State private var parakeetDownloadTask: Task<Void, Never>?

    var body: some View {
        TalkiePage("Models", title: "Models", style: .page) {
            VStack(alignment: .leading, spacing: 18) {
                ModelsInventorySummary(
                    voiceStatus: voiceStatus,
                    configuredProviderCount: configuredProviderCount,
                    providerCount: providerRows.count,
                    selectedProviderName: selectedProviderName,
                    selectedModelName: selectedModelName
                )

                VoiceModelSection(
                    status: voiceStatus,
                    isDownloading: downloadingParakeet,
                    downloadProgress: parakeetService.downloadProgress,
                    onDownload: downloadParakeet,
                    onDelete: deleteParakeet
                )

                ProviderModelsSection(
                    rows: providerRows,
                    activeProviderId: activeProviderId,
                    selectedModelId: selectedModelId(for:),
                    onSelectModel: selectModel,
                    onUseProvider: useProvider,
                    onConfigureProvider: configureProvider
                )
            }
            .frame(maxWidth: 980, alignment: .leading)
        }
        .task {
            normalizeVoiceModel()
            await registry.refreshModels()
        }
    }

    private var voiceStatus: VoiceModelStatus {
        #if arch(arm64)
        if downloadingParakeet {
            return .downloading
        }
        if parakeetService.isModelDownloaded(.v3) {
            return .ready
        }
        return .available
        #else
        return .unavailable
        #endif
    }

    private var providerRows: [ProviderModelRowState] {
        let configs = LLMConfig.shared.providers
        let orderedIds = LLMConfig.shared.preferredProviderOrder + configs.keys.sorted()
        var seen = Set<String>()

        return orderedIds.compactMap { providerId in
            guard seen.insert(providerId).inserted,
                  let config = configs[providerId],
                  registry.provider(for: providerId) != nil
            else {
                return nil
            }

            let options = modelOptions(for: config)
            return ProviderModelRowState(
                id: providerId,
                name: config.name,
                isConfigured: settingsManager.hasAPIKey(forProviderId: providerId),
                defaultModelId: config.defaultModel,
                modelOptions: options
            )
        }
    }

    private var configuredProviderCount: Int {
        providerRows.filter(\.isConfigured).count
    }

    private var activeProviderId: String? {
        if let selected = registry.selectedProviderId,
           providerRows.contains(where: { $0.id == selected }) {
            return selected
        }
        return providerRows.first(where: \.isConfigured)?.id
    }

    private var selectedProviderName: String {
        guard let activeProviderId,
              let row = providerRows.first(where: { $0.id == activeProviderId })
        else {
            return "None"
        }
        return row.name
    }

    private var selectedModelName: String {
        guard let activeProviderId,
              let row = providerRows.first(where: { $0.id == activeProviderId })
        else {
            return "No provider configured"
        }

        let id = selectedModelId(for: row)
        return row.modelOptions.first(where: { $0.id == id })?.name ?? id
    }

    private func modelOptions(for config: LLMConfig.ProviderConfig) -> [ProviderModelOption] {
        let options = config.models.map { model in
            ProviderModelOption(
                id: model.id,
                name: model.displayName,
                detail: model.description,
                isRecommended: model.recommended ?? false
            )
        }

        if options.isEmpty {
            return [
                ProviderModelOption(
                    id: config.defaultModel,
                    name: config.defaultModel,
                    detail: nil,
                    isRecommended: true
                ),
            ]
        }

        return options
    }

    private func selectedModelId(for row: ProviderModelRowState) -> String {
        let selectedModel = registry.selectedProviderId == row.id ? registry.selectedModelId : nil
        if let selectedModel,
           row.modelOptions.contains(where: { $0.id == selectedModel }) {
            return selectedModel
        }
        if row.modelOptions.contains(where: { $0.id == row.defaultModelId }) {
            return row.defaultModelId
        }
        return row.modelOptions.first?.id ?? row.defaultModelId
    }

    private func selectModel(providerId: String, modelId: String) {
        registry.selectedProviderId = providerId
        registry.selectedModelId = modelId
    }

    private func useProvider(_ row: ProviderModelRowState) {
        guard row.isConfigured else {
            configureProvider(row.id)
            return
        }
        selectModel(providerId: row.id, modelId: selectedModelId(for: row))
    }

    private func configureProvider(_ providerId: String) {
        NavigationState.shared.navigateToSettings(.aiProviders)
    }

    private func normalizeVoiceModel() {
        if settingsManager.liveTranscriptionModelId != TalkieDefaults.dictationModelId {
            settingsManager.liveTranscriptionModelId = TalkieDefaults.dictationModelId
        }
    }

    private func downloadParakeet() {
        #if arch(arm64)
        guard !parakeetService.isModelDownloaded(.v3), parakeetDownloadTask == nil else {
            return
        }

        downloadingParakeet = true
        parakeetDownloadTask = Task {
            do {
                try await parakeetService.downloadModel(.v3)
            } catch is CancellationError {
                modelsLog.debug("Parakeet download cancelled")
            } catch {
                modelsLog.error("Parakeet download failed: \(error.localizedDescription)")
            }

            await MainActor.run {
                downloadingParakeet = false
                parakeetDownloadTask = nil
            }
        }
        #endif
    }

    private func deleteParakeet() {
        #if arch(arm64)
        do {
            try parakeetService.deleteModel(.v3)
        } catch {
            modelsLog.error("Parakeet delete failed: \(error.localizedDescription)")
        }
        #endif
    }
}

private struct ProviderModelOption: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String?
    let isRecommended: Bool
}

private struct ProviderModelRowState: Identifiable, Equatable {
    let id: String
    let name: String
    let isConfigured: Bool
    let defaultModelId: String
    let modelOptions: [ProviderModelOption]
}

private enum VoiceModelStatus: Equatable {
    case ready
    case downloading
    case available
    case unavailable

    var label: String {
        switch self {
        case .ready: return "Ready"
        case .downloading: return "Downloading"
        case .available: return "Available"
        case .unavailable: return "Unavailable"
        }
    }

    var detail: String {
        switch self {
        case .ready: return "Installed locally"
        case .downloading: return "Installing local model"
        case .available: return "Not installed"
        case .unavailable: return "Requires Apple Silicon"
        }
    }
}

private struct ModelsInventorySummary: View {
    let voiceStatus: VoiceModelStatus
    let configuredProviderCount: Int
    let providerCount: Int
    let selectedProviderName: String
    let selectedModelName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Inventory")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.current.foreground)
                Spacer()
                Text("\(configuredProviderCount)/\(providerCount) providers")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.current.foregroundMuted)
            }

            HStack(spacing: 12) {
                InventoryPill(title: "Voice", value: "Parakeet", detail: voiceStatus.label)
                InventoryPill(title: "Provider", value: selectedProviderName, detail: selectedModelName)
            }
        }
    }
}

private struct InventoryPill: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.current.foregroundMuted)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.current.foreground)
            }

            Spacer(minLength: 8)

            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.current.foregroundSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.current.surface1)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.current.border, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 8))
    }
}

private struct VoiceModelSection: View {
    let status: VoiceModelStatus
    let isDownloading: Bool
    let downloadProgress: Float
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ModelsSection(title: "Voice", trailing: "1 model") {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.current.accent)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Parakeet")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.current.foreground)
                        Text(status.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.current.foregroundSecondary)
                    }

                    Spacer()

                    ModelsStatusBadge(label: status.label, isActive: status == .ready)

                    voiceAction
                }
                .padding(12)

                if isDownloading {
                    ProgressView(value: Double(downloadProgress))
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    @ViewBuilder
    private var voiceAction: some View {
        switch status {
        case .ready:
            Menu {
                Button("Remove", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
        case .downloading:
            ProgressView()
                .controlSize(.small)
                .frame(width: 28, height: 28)
        case .available:
            Button("Download", systemImage: "arrow.down.circle", action: onDownload)
                .buttonStyle(.bordered)
        case .unavailable:
            EmptyView()
        }
    }
}

private struct ProviderModelsSection: View {
    let rows: [ProviderModelRowState]
    let activeProviderId: String?
    let selectedModelId: (ProviderModelRowState) -> String
    let onSelectModel: (String, String) -> Void
    let onUseProvider: (ProviderModelRowState) -> Void
    let onConfigureProvider: (String) -> Void

    var body: some View {
        ModelsSection(title: "Providers", trailing: "\(rows.count) supported") {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    ProviderModelRow(
                        row: row,
                        isActive: activeProviderId == row.id,
                        selectedModelId: selectedModelId(row),
                        onSelectModel: { modelId in
                            onSelectModel(row.id, modelId)
                        },
                        onUseProvider: {
                            onUseProvider(row)
                        },
                        onConfigureProvider: {
                            onConfigureProvider(row.id)
                        }
                    )

                    if row.id != rows.last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct ProviderModelRow: View {
    let row: ProviderModelRowState
    let isActive: Bool
    let selectedModelId: String
    let onSelectModel: (String) -> Void
    let onUseProvider: () -> Void
    let onConfigureProvider: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProviderInitial(name: row.name, isActive: isActive)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(row.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.current.foreground)
                    ModelsStatusBadge(label: statusLabel, isActive: isActive)
                }

                Text(modelDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.current.foregroundSecondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 170, alignment: .leading)

            Spacer(minLength: 12)

            ProviderModelPicker(
                options: row.modelOptions,
                selection: selectedModelId,
                isEnabled: row.isConfigured,
                onChange: onSelectModel
            )
            .frame(width: 260)

            if row.isConfigured {
                Button(isActive ? "In Use" : "Use", systemImage: isActive ? "checkmark.circle.fill" : "arrow.right.circle") {
                    onUseProvider()
                }
                .buttonStyle(.bordered)
                .disabled(isActive)
            } else {
                Button("Configure", systemImage: "key", action: onConfigureProvider)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .contentShape(Rectangle())
    }

    private var statusLabel: String {
        if isActive { return "In use" }
        return row.isConfigured ? "Ready" : "Not set"
    }

    private var modelDetail: String {
        if let selected = row.modelOptions.first(where: { $0.id == selectedModelId }) {
            return selected.detail ?? selected.id
        }
        return selectedModelId
    }
}

private struct ProviderModelPicker: View {
    let options: [ProviderModelOption]
    let selection: String
    let isEnabled: Bool
    let onChange: (String) -> Void

    var body: some View {
        Picker("Model", selection: binding) {
            ForEach(options) { option in
                Text(optionLabel(option))
                    .tag(option.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .disabled(!isEnabled || options.isEmpty)
    }

    private var binding: Binding<String> {
        Binding(
            get: { selection },
            set: { onChange($0) }
        )
    }

    private func optionLabel(_ option: ProviderModelOption) -> String {
        option.isRecommended ? "\(option.name) recommended" : option.name
    }
}

private struct ProviderInitial: View {
    let name: String
    let isActive: Bool

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(isActive ? Theme.current.background : Theme.current.foregroundSecondary)
            .frame(width: 30, height: 30)
            .background(isActive ? Theme.current.accent : Theme.current.surface2)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Theme.current.border, lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: 7))
    }
}

private struct ModelsStatusBadge: View {
    let label: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isActive ? Theme.current.accent : Theme.current.foregroundMuted)
                .frame(width: 6, height: 6)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(isActive ? Theme.current.accent : Theme.current.foregroundMuted)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background((isActive ? Theme.current.accent : Theme.current.surface2).opacity(isActive ? 0.12 : 1))
        .clipShape(.capsule)
    }
}

private struct ModelsSection<Content: View>: View {
    let title: String
    let trailing: String
    let content: Content

    init(title: String, trailing: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.current.foreground)
                Spacer()
                Text(trailing.uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.current.foregroundMuted)
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.current.surface1)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.current.border, lineWidth: 1)
                )
                .clipShape(.rect(cornerRadius: 8))
        }
    }
}

#Preview {
    ModelsContentView()
        .environment(SettingsManager.shared)
        .frame(width: 900, height: 720)
}
