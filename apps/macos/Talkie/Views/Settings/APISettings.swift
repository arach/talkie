//
//  APISettings.swift
//  Talkie macOS
//
//  Extracted from SettingsView.swift
//

import SwiftUI
import TalkieKit

private let logger = Log(.ui)

// MARK: - API Settings View
struct APISettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager
    @State private var editingProvider: String?
    @State private var editingProviderIdInput = ""
    @State private var editingKeyInput = ""
    @State private var revealedKeys: Set<String> = []
    @State private var fetchedKeys: [String: String] = [:]
    @State private var additionalProviderIDs: [String] = []
    @State private var isRefreshingModels = false
    @State private var modelCounts: [String: Int] = [:]

    private var slots: [APIKeyStore.ProviderSlot] {
        settingsManager.apiKeySlots(additionalProviderIDs: additionalProviderIDs)
    }

    private var configuredCount: Int {
        slots.filter { settingsManager.hasAPIKey(forProviderId: $0.id) }.count
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "key",
                title: "API KEYS",
                subtitle: "Manage reusable provider key slots"
            )
        } content: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.blue)
                        .frame(width: 3, height: 14)

                    Text("PROVIDER KEY SLOTS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    HStack(spacing: Spacing.xxs) {
                        Circle()
                            .fill(configuredCount > 0 ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text("\(configuredCount) CONFIGURED")
                            .font(.techLabelSmall)
                            .foregroundColor(configuredCount > 0 ? .green : .orange)
                    }

                    Menu {
                        ForEach(APIKeyStore.Provider.allCases, id: \.rawValue) { provider in
                            Button(provider.displayName, systemImage: provider.icon) {
                                startEditing(provider.slot)
                            }
                        }

                        Divider()

                        Button("Custom Provider", systemImage: "plus") {
                            addCustomSlot()
                        }
                    } label: {
                        Label("Add Slot", systemImage: "plus")
                            .font(.techLabelSmall)
                    }
                    .menuStyle(.button)

                    Button {
                        Task { await refreshAllModels() }
                    } label: {
                        HStack(spacing: Spacing.xxs) {
                            if isRefreshingModels {
                                BrailleSpinner(size: 12)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(Theme.current.fontXS)
                            }
                            Text("Refresh Models")
                                .font(.techLabelSmall)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRefreshingModels)
                    .help("Fetch latest models from all configured providers")
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(APIKeyStore.Provider.allCases, id: \.rawValue) { provider in
                            APIKeyPresetButton(provider: provider) {
                                startEditing(provider.slot)
                            }
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                }

                VStack(spacing: Spacing.sm) {
                    ForEach(slots) { slot in
                        APIKeyRow(
                            slot: slot,
                            isConfigured: settingsManager.hasAPIKey(forProviderId: slot.id),
                            currentKey: fetchedKeys[slot.id] ?? settingsManager.fetchAPIKey(forProviderId: slot.id),
                            isEditing: editingProvider == slot.id,
                            isRevealed: revealedKeys.contains(slot.id),
                            editingProviderId: $editingProviderIdInput,
                            editingKey: $editingKeyInput,
                            onEdit: { startEditing(slot) },
                            onSave: { saveSlot(previousProviderId: slot.id) },
                            onCancel: { stopEditing() },
                            onReveal: { toggleReveal(slot.id) },
                            onDelete: { deleteSlot(slot.id) }
                        )
                    }
                }
            }
            .settingsSectionCard(padding: Spacing.md)

            HStack(spacing: Spacing.sm) {
                Image(systemName: "lock.shield")
                    .font(Theme.current.fontXS)
                    .foregroundColor(.green)

                Text("API keys are encrypted using AES-GCM and mirrored into shared local settings for server-side workflows.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
            .padding(Spacing.sm)
            .background(Color.green.opacity(Opacity.light))
            .cornerRadius(CornerRadius.sm)
        }
        .onAppear {
            prefetchConfiguredKeys()
        }
    }

    private func startEditing(_ slot: APIKeyStore.ProviderSlot) {
        let providerId = APIKeyStore.normalizeProviderId(slot.id)
        editingProvider = providerId
        editingProviderIdInput = providerId
        editingKeyInput = settingsManager.fetchAPIKey(forProviderId: providerId) ?? ""
        fetchedKeys[providerId] = editingKeyInput.isEmpty ? nil : editingKeyInput

        if !additionalProviderIDs.contains(providerId), !slots.contains(where: { $0.id == providerId }) {
            additionalProviderIDs.append(providerId)
        }
    }

    private func addCustomSlot() {
        let base = "custom_provider"
        var candidate = base
        var index = 2
        let existingIDs = Set(slots.map(\.id) + additionalProviderIDs)

        while existingIDs.contains(candidate) {
            candidate = "\(base)_\(index)"
            index += 1
        }

        additionalProviderIDs.append(candidate)
        startEditing(APIKeyStore.providerSlot(forProviderId: candidate))
    }

    private func saveSlot(previousProviderId: String) {
        let providerId = APIKeyStore.normalizeProviderId(editingProviderIdInput)
        guard !providerId.isEmpty else { return }

        settingsManager.setAPIKey(editingKeyInput, forProviderId: providerId)
        fetchedKeys[providerId] = editingKeyInput.isEmpty ? nil : editingKeyInput

        if previousProviderId != providerId {
            settingsManager.setAPIKey(nil, forProviderId: previousProviderId)
            fetchedKeys[previousProviderId] = nil
            revealedKeys.remove(previousProviderId)
        }

        if !additionalProviderIDs.contains(providerId), !slots.contains(where: { $0.id == providerId }) {
            additionalProviderIDs.append(providerId)
        }

        stopEditing()
        Task { await refreshAllModels() }
    }

    private func stopEditing() {
        editingProvider = nil
        editingProviderIdInput = ""
        editingKeyInput = ""
    }

    private func toggleReveal(_ providerId: String) {
        if revealedKeys.contains(providerId) {
            revealedKeys.remove(providerId)
        } else {
            fetchedKeys[providerId] = settingsManager.fetchAPIKey(forProviderId: providerId)
            revealedKeys.insert(providerId)
        }
    }

    private func deleteSlot(_ providerId: String) {
        settingsManager.setAPIKey(nil, forProviderId: providerId)
        fetchedKeys[providerId] = nil
        revealedKeys.remove(providerId)
        additionalProviderIDs.removeAll { $0 == providerId }
    }

    private func prefetchConfiguredKeys() {
        for slot in slots where settingsManager.hasAPIKey(forProviderId: slot.id) {
            fetchedKeys[slot.id] = settingsManager.fetchAPIKey(forProviderId: slot.id)
        }
    }

    // MARK: - Model Refresh

    private func refreshAllModels() async {
        isRefreshingModels = true
        defer { isRefreshingModels = false }

        await LLMProviderRegistry.shared.refreshModels(force: true)

        let models = LLMProviderRegistry.shared.allModels
        modelCounts = Dictionary(grouping: models, by: { $0.provider })
            .mapValues { $0.count }

        logger.info("Refreshed models: \(models.count) total")
    }
}

// MARK: - API Key Preset Button
private struct APIKeyPresetButton: View {
    let provider: APIKeyStore.Provider
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Label(provider.displayName, systemImage: provider.icon)
                .font(Theme.current.fontXSMedium)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

// MARK: - API Key Row Component
private struct APIKeyRow: View {
    let slot: APIKeyStore.ProviderSlot
    let isConfigured: Bool
    let currentKey: String?
    let isEditing: Bool
    let isRevealed: Bool
    @Binding var editingProviderId: String
    @Binding var editingKey: String
    let onEdit: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void
    private let settings = SettingsManager.shared

    private var maskedKey: String {
        guard let key = currentKey, !key.isEmpty else { return "Not configured" }
        if key.count <= 8 { return String(repeating: "•", count: key.count) }
        let prefix = String(key.prefix(4))
        let suffix = String(key.suffix(4))
        return "\(prefix)••••••••\(suffix)"
    }

    private var shouldShowCollapsed: Bool {
        !isConfigured && !isEditing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: slot.icon)
                    .font(Theme.current.fontTitle)
                    .foregroundColor(isConfigured ? settings.resolvedAccentColor : Theme.current.foregroundSecondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.displayName.uppercased())
                        .font(Theme.current.fontSMBold)
                    Text(slot.id)
                        .font(.techLabelSmall)
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                Spacer()

                if shouldShowCollapsed {
                    Button(action: onEdit) {
                        Label("Add Key", systemImage: "plus.circle.fill")
                            .font(Theme.current.fontXSMedium)
                    }
                    .buttonStyle(.bordered)

                    if let helpURL = slot.helpURL {
                        Link(destination: helpURL) {
                            Image(systemName: "arrow.up.right.square")
                                .font(Theme.current.fontXS)
                                .foregroundColor(.blue)
                        }
                        .help("Get API key")
                    }
                } else {
                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(isConfigured ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(isConfigured ? "CONFIGURED" : "NOT SET")
                            .font(.techLabelSmall)
                            .foregroundColor(isConfigured ? .green : .orange)
                    }
                }
            }

            if !shouldShowCollapsed {
                if isEditing {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(spacing: Spacing.sm) {
                            TextField("provider_id", text: $editingProviderId)
                                .font(Theme.current.fontSM)
                                .textFieldStyle(.plain)
                                .padding(Spacing.sm)
                                .background(Theme.current.surface1)
                                .cornerRadius(CornerRadius.xs)
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                                        .stroke(Theme.current.divider, lineWidth: 1)
                                )

                            SecureField(slot.placeholder, text: $editingKey)
                                .font(Theme.current.fontSM)
                                .textFieldStyle(.plain)
                                .padding(Spacing.sm)
                                .background(Theme.current.surface1)
                                .cornerRadius(CornerRadius.xs)
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                                        .stroke(settings.resolvedAccentColor.opacity(Opacity.half), lineWidth: 1)
                                )
                        }

                        HStack(spacing: Spacing.sm) {
                            Spacer()

                            Button(action: onCancel) {
                                Text("Cancel")
                                    .font(Theme.current.fontXSMedium)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                onSave()
                            } label: {
                                Text("Save")
                                    .font(Theme.current.fontXSMedium)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(APIKeyStore.normalizeProviderId(editingProviderId).isEmpty)
                        }
                    }
                } else if isConfigured {
                    HStack(spacing: Spacing.sm) {
                        HStack(spacing: Spacing.sm) {
                            Text(isRevealed ? (currentKey ?? "") : maskedKey)
                                .font(Theme.current.fontSM)
                                .foregroundColor(Theme.current.foregroundMuted)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Button(action: onReveal) {
                                Image(systemName: isRevealed ? "eye.slash" : "eye")
                                    .font(Theme.current.fontXS)
                                    .foregroundColor(Theme.current.foregroundMuted)
                            }
                            .buttonStyle(.plain)
                            .help(isRevealed ? "Hide API key" : "Reveal API key")
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.sm)
                        .background(Theme.current.surface1)
                        .cornerRadius(CornerRadius.xs)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                .stroke(Theme.current.divider, lineWidth: 1)
                        )

                        Button(action: onEdit) {
                            Text("Edit")
                                .font(Theme.current.fontXSMedium)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .font(Theme.current.fontXS)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
            }
        }
        .settingsSectionCard(padding: shouldShowCollapsed ? Spacing.sm : Spacing.md)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(Theme.current.foreground.opacity(Opacity.light), lineWidth: 1)
        )
    }
}
