//
//  ModelLibrarySettings.swift
//  Talkie macOS
//
//  Cloud AI provider configuration - uses same design as Models sidebar
//

import SwiftUI
import os

private let logger = Logger(subsystem: "to.talkie.app.mac", category: "Views")

// MARK: - Model Library View

struct ModelLibraryView: View {
    @Environment(SettingsManager.self) private var settingsManager

    @State private var expandedProvider: String?
    @State private var enabledMarkupAgentModelKeys: Set<String> = []
    @State private var isRefreshingAgentModels = false

    private let settings = SettingsManager.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Header
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("SETTINGS / AI & LLM")
                        .font(Theme.current.fontXSMedium)
                        .foregroundColor(Theme.current.foregroundMuted)

                    Text("LANGUAGE MODELS")
                        .font(Theme.current.fontHeadlineBold)
                        .foregroundColor(Theme.current.foreground)

                    Text("Configure cloud AI providers and speech models for workflows and smart features.")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .lineLimit(2)
                }

                // Cloud Providers Grid Section
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.blue)
                            .frame(width: 3, height: 14)

                        Text("CLOUD PROVIDERS")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Spacer()

                        let configuredCount = [
                            settingsManager.openaiApiKey != nil,
                            settingsManager.anthropicApiKey != nil,
                            settingsManager.hasValidApiKey,
                            settingsManager.groqApiKey != nil
                        ].filter { $0 }.count
                        Text("\(configuredCount)/4 CONFIGURED")
                            .font(.techLabelSmall)
                            .foregroundColor(configuredCount > 0 ? .green : .orange)
                    }

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: Spacing.sm),
                        GridItem(.flexible(), spacing: Spacing.sm)
                    ], spacing: Spacing.sm) {
                        ExpandableCloudProviderCard(
                            providerId: "openai",
                            name: "OpenAI",
                            tagline: "Industry standard for reasoning and vision",
                            isConfigured: settingsManager.openaiApiKey != nil,
                            isExpanded: expandedProvider == "openai",
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedProvider = expandedProvider == "openai" ? nil : "openai"
                                }
                            },
                            onConfigure: {
                                // Navigate to API Keys section in this same settings view
                                NavigationState.shared.navigateToSettings(.aiProviders)
                            }
                        )

                        ExpandableCloudProviderCard(
                            providerId: "anthropic",
                            name: "Anthropic",
                            tagline: "Extended thinking and nuanced understanding",
                            isConfigured: settingsManager.anthropicApiKey != nil,
                            isExpanded: expandedProvider == "anthropic",
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedProvider = expandedProvider == "anthropic" ? nil : "anthropic"
                                }
                            },
                            onConfigure: {
                                NavigationState.shared.navigateToSettings(.aiProviders)
                            }
                        )

                        ExpandableCloudProviderCard(
                            providerId: "gemini",
                            name: "Gemini",
                            tagline: "Multimodal powerhouse with massive context",
                            isConfigured: settingsManager.hasValidApiKey,
                            isExpanded: expandedProvider == "gemini",
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedProvider = expandedProvider == "gemini" ? nil : "gemini"
                                }
                            },
                            onConfigure: {
                                NavigationState.shared.navigateToSettings(.aiProviders)
                            }
                        )

                        ExpandableCloudProviderCard(
                            providerId: "groq",
                            name: "Groq",
                            tagline: "Ultra-fast inference at scale",
                            isConfigured: settingsManager.groqApiKey != nil,
                            isExpanded: expandedProvider == "groq",
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedProvider = expandedProvider == "groq" ? nil : "groq"
                                }
                            },
                            onConfigure: {
                                NavigationState.shared.navigateToSettings(.aiProviders)
                            }
                        )
                    }
                }
                .settingsSectionCard(padding: Spacing.md)

                markupAgentsSection

                // Quick configure hint
                if !hasAnyProviderConfigured {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack(spacing: Spacing.sm) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.orange)
                                .frame(width: 3, height: 14)

                            Text("GET STARTED")
                                .font(Theme.current.fontXSBold)
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }

                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "key.fill")
                                .font(Theme.current.fontBody)
                                .foregroundColor(Theme.current.foregroundMuted)

                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text("No API keys configured")
                                    .font(Theme.current.fontSMMedium)
                                    .foregroundColor(Theme.current.foregroundSecondary)
                                Text("Click 'Configure' on any provider to add your API key")
                                    .font(Theme.current.fontSM)
                                    .foregroundColor(Theme.current.foregroundMuted)
                            }

                            Spacer()

                            Button(action: {
                                NavigationState.shared.navigateToSettings(.aiProviders)
                            }) {
                                Text("Go to API Keys")
                                    .font(Theme.current.fontSMMedium)
                                    .foregroundColor(Theme.current.foregroundSecondary)
                                    .padding(.horizontal, Spacing.sm)
                                    .padding(.vertical, Spacing.xs)
                                    .background(Theme.current.surface2)
                                    .cornerRadius(CornerRadius.xs)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                                            .stroke(Theme.current.divider, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(Spacing.sm)
                        .background(Theme.current.surface1)
                        .cornerRadius(CornerRadius.sm)
                    }
                    .settingsSectionCard(padding: Spacing.md)
                }

                Spacer(minLength: Spacing.xxl)
            }
            .padding(Spacing.xl)
        }
        .background(Theme.current.background)
        .task {
            await refreshMarkupAgentModels(force: false)
        }
    }

    private var hasAnyProviderConfigured: Bool {
        settingsManager.openaiApiKey != nil ||
        settingsManager.anthropicApiKey != nil ||
        settingsManager.hasValidApiKey ||
        settingsManager.groqApiKey != nil
    }

    private var markupAgentsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.cyan)
                    .frame(width: 3, height: 14)

                Text("MARKUP AGENTS")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Text("\(enabledMarkupAgentModelKeys.count) ENABLED")
                    .font(.techLabelSmall)
                    .foregroundColor(enabledMarkupAgentModelKeys.isEmpty ? .orange : .green)

                Spacer()

                Button {
                    Task { await refreshMarkupAgentModels(force: true) }
                } label: {
                    Label(isRefreshingAgentModels ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
                        .font(Theme.current.fontXSMedium)
                }
                .buttonStyle(.plain)
                .disabled(isRefreshingAgentModels)

                Button {
                    LLMAgentModelPreferences.resetToRecommended()
                    reloadMarkupAgentSelection()
                } label: {
                    Text("Reset")
                        .font(Theme.current.fontXSMedium)
                }
                .buttonStyle(.plain)
            }

            if availableMarkupModels.isEmpty {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "sparkles")
                        .font(Theme.current.fontBody)
                        .foregroundColor(Theme.current.foregroundMuted)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("No markup agent catalog loaded")
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foregroundSecondary)
                        Text("Refresh models after adding a provider key.")
                            .font(Theme.current.fontSM)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }

                    Spacer()
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(markupProviderIds, id: \.self) { providerId in
                        let models = providerModels(for: providerId)
                        if !models.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                HStack(spacing: Spacing.xs) {
                                    Text(providerName(for: providerId).uppercased())
                                        .font(Theme.current.fontXSMedium)
                                        .foregroundColor(Theme.current.foregroundSecondary)

                                    Text(providerConfiguredLabel(for: providerId))
                                        .font(.techLabelSmall)
                                        .foregroundColor(isProviderConfigured(providerId) ? .green : Theme.current.foregroundMuted)

                                    Spacer()
                                }

                                VStack(spacing: 1) {
                                    ForEach(models) { model in
                                        MarkupAgentModelRow(
                                            model: model,
                                            isRecommended: LLMConfig.shared.recommendedModelIDs(for: providerId).contains(model.id),
                                            isEnabled: markupAgentBinding(for: model)
                                        )
                                    }
                                }
                                .clipShape(.rect(cornerRadius: CornerRadius.sm))
                            }
                        }
                    }
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private var availableMarkupModels: [LLMModel] {
        LLMAgentModelPreferences.sorted(
            LLMProviderRegistry.shared.allModels.filter { LLMAgentModelPreferences.isCuratableProvider($0.provider) }
        )
    }

    private var markupProviderIds: [String] {
        var ids: [String] = []
        var seen = Set<String>()
        for providerId in LLMConfig.shared.preferredProviderOrder + availableMarkupModels.map(\.provider) {
            guard LLMAgentModelPreferences.isCuratableProvider(providerId),
                  seen.insert(providerId).inserted else { continue }
            ids.append(providerId)
        }
        return ids
    }

    private func providerModels(for providerId: String) -> [LLMModel] {
        availableMarkupModels.filter { $0.provider == providerId }
    }

    private func providerName(for providerId: String) -> String {
        LLMProviderRegistry.shared.provider(for: providerId)?.name
            ?? LLMConfig.shared.config(for: providerId)?.name
            ?? providerId
    }

    private func isProviderConfigured(_ providerId: String) -> Bool {
        switch providerId {
        case "openai": return settingsManager.openaiApiKey != nil
        case "anthropic": return settingsManager.anthropicApiKey != nil
        case "gemini": return settingsManager.hasValidApiKey
        case "groq": return settingsManager.groqApiKey != nil
        default: return false
        }
    }

    private func providerConfiguredLabel(for providerId: String) -> String {
        isProviderConfigured(providerId) ? "CONFIGURED" : "NEEDS KEY"
    }

    private func markupAgentBinding(for model: LLMModel) -> Binding<Bool> {
        Binding(
            get: {
                enabledMarkupAgentModelKeys.contains(LLMAgentModelPreferences.modelKey(for: model))
            },
            set: { isEnabled in
                LLMAgentModelPreferences.setModel(
                    model,
                    enabled: isEnabled,
                    availableModels: LLMProviderRegistry.shared.allModels
                )
                reloadMarkupAgentSelection()
            }
        )
    }

    private func refreshMarkupAgentModels(force: Bool) async {
        isRefreshingAgentModels = true
        await LLMProviderRegistry.shared.refreshModels(force: force)
        reloadMarkupAgentSelection()
        isRefreshingAgentModels = false
    }

    private func reloadMarkupAgentSelection() {
        enabledMarkupAgentModelKeys = LLMAgentModelPreferences.enabledModelKeys(
            availableModels: LLMProviderRegistry.shared.allModels
        )
    }
}

private struct MarkupAgentModelRow: View {
    let model: LLMModel
    let isRecommended: Bool
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Spacing.xs) {
                    Text(model.displayName)
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    if isRecommended {
                        Text("RECOMMENDED")
                            .font(.techLabelSmall)
                            .foregroundColor(Color.blue)
                    }
                }

                Text(model.id)
                    .font(.techLabelSmall)
                    .foregroundColor(Theme.current.foregroundMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Theme.current.surface1)
    }
}

#Preview {
    ModelLibraryView()
        .environment(SettingsManager.shared)
        .frame(width: 800, height: 600)
}
