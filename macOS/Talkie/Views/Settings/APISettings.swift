//
//  APISettings.swift
//  Talkie macOS
//
//  Extracted from SettingsView.swift
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

// MARK: - API Settings View
struct APISettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager
    @State private var editingProvider: String?
    @State private var editingKeyInput: String = ""
    @State private var revealedKeys: Set<String> = []
    @State private var fetchedKeys: [String: String] = [:]  // Cache fetched keys
    @State private var isRefreshingModels = false
    @State private var modelCounts: [String: Int] = [:]  // Provider -> model count

    var body: some View {
        @Bindable var settings = settingsManager

        SettingsPageContainer {
            SettingsPageHeader(
                icon: "key",
                title: "API KEYS",
                subtitle: "Manage API keys for cloud AI providers"
            )
        } content: {
            // MARK: - Provider API Keys
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.blue)
                        .frame(width: 3, height: 14)

                    Text("CLOUD PROVIDERS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    // Count configured keys
                    let configuredCount = [
                        settingsManager.hasOpenAIKey(),
                        settingsManager.hasAnthropicKey(),
                        settingsManager.hasValidApiKey,
                        settingsManager.hasGroqKey(),
                        settingsManager.hasElevenLabsKey()
                    ].filter { $0 }.count

                    HStack(spacing: Spacing.xxs) {
                        Circle()
                            .fill(configuredCount > 0 ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text("\(configuredCount)/5 CONFIGURED")
                            .font(.techLabelSmall)
                            .foregroundColor(configuredCount > 0 ? .green : .orange)
                    }

                    // Refresh models button
                    Button {
                        Task {
                            await refreshAllModels()
                        }
                    } label: {
                        HStack(spacing: Spacing.xxs) {
                            if isRefreshingModels {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 12, height: 12)
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

                VStack(spacing: Spacing.sm) {
                    APIKeyRow(
                        provider: "OpenAI",
                        icon: "brain.head.profile",
                        placeholder: "sk-...",
                        helpURL: "https://platform.openai.com/api-keys",
                        isConfigured: settingsManager.hasOpenAIKey(),
                        currentKey: fetchedKeys["openai"],
                        isEditing: editingProvider == "openai",
                        isRevealed: revealedKeys.contains("openai"),
                        editingKey: $editingKeyInput,
                        onEdit: {
                            // Fetch key only when editing
                            if let key = settingsManager.fetchOpenAIKey() {
                                fetchedKeys["openai"] = key
                                editingKeyInput = key
                            }
                            editingProvider = "openai"
                        },
                        onSave: {
                            settingsManager.openaiApiKey = editingKeyInput.isEmpty ? nil : editingKeyInput
                            settingsManager.saveSettings()
                            fetchedKeys["openai"] = editingKeyInput.isEmpty ? nil : editingKeyInput
                            editingProvider = nil
                            editingKeyInput = ""
                            // Refresh models after saving key
                            Task { await refreshAllModels() }
                        },
                        onCancel: {
                            editingProvider = nil
                            editingKeyInput = ""
                        },
                        onReveal: {
                            if revealedKeys.contains("openai") {
                                revealedKeys.remove("openai")
                                fetchedKeys["openai"] = nil
                            } else {
                                // Fetch key only when revealing
                                if let key = settingsManager.fetchOpenAIKey() {
                                    fetchedKeys["openai"] = key
                                }
                                revealedKeys.insert("openai")
                            }
                        },
                        onDelete: {
                            settingsManager.openaiApiKey = nil
                            settingsManager.saveSettings()
                            fetchedKeys["openai"] = nil
                        }
                    )

                    APIKeyRow(
                        provider: "Anthropic",
                        icon: "sparkles",
                        placeholder: "sk-ant-...",
                        helpURL: "https://console.anthropic.com/settings/keys",
                        isConfigured: settingsManager.hasAnthropicKey(),
                        currentKey: fetchedKeys["anthropic"],
                        isEditing: editingProvider == "anthropic",
                        isRevealed: revealedKeys.contains("anthropic"),
                        editingKey: $editingKeyInput,
                        onEdit: {
                            // Fetch key only when editing
                            if let key = settingsManager.fetchAnthropicKey() {
                                fetchedKeys["anthropic"] = key
                                editingKeyInput = key
                            }
                            editingProvider = "anthropic"
                        },
                        onSave: {
                            settingsManager.anthropicApiKey = editingKeyInput.isEmpty ? nil : editingKeyInput
                            settingsManager.saveSettings()
                            fetchedKeys["anthropic"] = editingKeyInput.isEmpty ? nil : editingKeyInput
                            editingProvider = nil
                            editingKeyInput = ""
                            Task { await refreshAllModels() }
                        },
                        onCancel: {
                            editingProvider = nil
                            editingKeyInput = ""
                        },
                        onReveal: {
                            if revealedKeys.contains("anthropic") {
                                revealedKeys.remove("anthropic")
                                fetchedKeys["anthropic"] = nil
                            } else {
                                // Fetch key only when revealing
                                if let key = settingsManager.fetchAnthropicKey() {
                                    fetchedKeys["anthropic"] = key
                                }
                                revealedKeys.insert("anthropic")
                            }
                        },
                        onDelete: {
                            settingsManager.anthropicApiKey = nil
                            settingsManager.saveSettings()
                            fetchedKeys["anthropic"] = nil
                        }
                    )

                    APIKeyRow(
                        provider: "Gemini",
                        icon: "cloud.fill",
                        placeholder: "AIzaSy...",
                        helpURL: "https://makersuite.google.com/app/apikey",
                        isConfigured: settingsManager.hasValidApiKey,
                        currentKey: settingsManager.geminiApiKey.isEmpty ? nil : settingsManager.geminiApiKey,
                        isEditing: editingProvider == "gemini",
                        isRevealed: revealedKeys.contains("gemini"),
                        editingKey: $editingKeyInput,
                        onEdit: {
                            editingProvider = "gemini"
                            editingKeyInput = settingsManager.geminiApiKey
                        },
                        onSave: {
                            settingsManager.geminiApiKey = editingKeyInput
                            settingsManager.saveSettings()
                            editingProvider = nil
                            editingKeyInput = ""
                            Task { await refreshAllModels() }
                        },
                        onCancel: {
                            editingProvider = nil
                            editingKeyInput = ""
                        },
                        onReveal: {
                            if revealedKeys.contains("gemini") {
                                revealedKeys.remove("gemini")
                            } else {
                                revealedKeys.insert("gemini")
                            }
                        },
                        onDelete: {
                            settingsManager.geminiApiKey = ""
                            settingsManager.saveSettings()
                        }
                    )

                    APIKeyRow(
                        provider: "Groq",
                        icon: "bolt.fill",
                        placeholder: "gsk_...",
                        helpURL: "https://console.groq.com/keys",
                        isConfigured: settingsManager.hasGroqKey(),
                        currentKey: fetchedKeys["groq"],
                        isEditing: editingProvider == "groq",
                        isRevealed: revealedKeys.contains("groq"),
                        editingKey: $editingKeyInput,
                        onEdit: {
                            // Fetch key only when editing
                            if let key = settingsManager.fetchGroqKey() {
                                fetchedKeys["groq"] = key
                                editingKeyInput = key
                            }
                            editingProvider = "groq"
                        },
                        onSave: {
                            settingsManager.groqApiKey = editingKeyInput.isEmpty ? nil : editingKeyInput
                            settingsManager.saveSettings()
                            fetchedKeys["groq"] = editingKeyInput.isEmpty ? nil : editingKeyInput
                            editingProvider = nil
                            editingKeyInput = ""
                            Task { await refreshAllModels() }
                        },
                        onCancel: {
                            editingProvider = nil
                            editingKeyInput = ""
                        },
                        onReveal: {
                            if revealedKeys.contains("groq") {
                                revealedKeys.remove("groq")
                                fetchedKeys["groq"] = nil
                            } else {
                                // Fetch key only when revealing
                                if let key = settingsManager.fetchGroqKey() {
                                    fetchedKeys["groq"] = key
                                }
                                revealedKeys.insert("groq")
                            }
                        },
                        onDelete: {
                            settingsManager.groqApiKey = nil
                            settingsManager.saveSettings()
                            fetchedKeys["groq"] = nil
                        }
                    )

                    APIKeyRow(
                        provider: "ElevenLabs",
                        icon: "speaker.wave.3",
                        placeholder: "sk_...",
                        helpURL: "https://elevenlabs.io/app/settings/api-keys",
                        isConfigured: settingsManager.hasElevenLabsKey(),
                        currentKey: fetchedKeys["elevenlabs"],
                        isEditing: editingProvider == "elevenlabs",
                        isRevealed: revealedKeys.contains("elevenlabs"),
                        editingKey: $editingKeyInput,
                        onEdit: {
                            if let key = settingsManager.fetchElevenLabsKey() {
                                fetchedKeys["elevenlabs"] = key
                                editingKeyInput = key
                            }
                            editingProvider = "elevenlabs"
                        },
                        onSave: {
                            settingsManager.elevenLabsApiKey = editingKeyInput.isEmpty ? nil : editingKeyInput
                            settingsManager.saveSettings()
                            fetchedKeys["elevenlabs"] = editingKeyInput.isEmpty ? nil : editingKeyInput
                            editingProvider = nil
                            editingKeyInput = ""
                        },
                        onCancel: {
                            editingProvider = nil
                            editingKeyInput = ""
                        },
                        onReveal: {
                            if revealedKeys.contains("elevenlabs") {
                                revealedKeys.remove("elevenlabs")
                                fetchedKeys["elevenlabs"] = nil
                            } else {
                                if let key = settingsManager.fetchElevenLabsKey() {
                                    fetchedKeys["elevenlabs"] = key
                                }
                                revealedKeys.insert("elevenlabs")
                            }
                        },
                        onDelete: {
                            settingsManager.elevenLabsApiKey = nil
                            settingsManager.saveSettings()
                            fetchedKeys["elevenlabs"] = nil
                        }
                    )
                }
            }
            .padding(Spacing.md)
            .background(Theme.current.surface2)
            .cornerRadius(CornerRadius.sm)

            // MARK: - Security Info
            HStack(spacing: Spacing.sm) {
                Image(systemName: "lock.shield")
                    .font(Theme.current.fontXS)
                    .foregroundColor(.green)

                Text("API keys are encrypted using AES-GCM and stored locally on this device.")
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

    /// Pre-fetch keys for configured providers so UI shows them immediately
    private func prefetchConfiguredKeys() {
        if settingsManager.hasOpenAIKey(), fetchedKeys["openai"] == nil {
            fetchedKeys["openai"] = settingsManager.fetchOpenAIKey()
        }
        if settingsManager.hasAnthropicKey(), fetchedKeys["anthropic"] == nil {
            fetchedKeys["anthropic"] = settingsManager.fetchAnthropicKey()
        }
        if settingsManager.hasValidApiKey, fetchedKeys["gemini"] == nil {
            fetchedKeys["gemini"] = settingsManager.geminiApiKey.isEmpty ? nil : settingsManager.geminiApiKey
        }
        if settingsManager.hasGroqKey(), fetchedKeys["groq"] == nil {
            fetchedKeys["groq"] = settingsManager.fetchGroqKey()
        }
        if settingsManager.hasElevenLabsKey(), fetchedKeys["elevenlabs"] == nil {
            fetchedKeys["elevenlabs"] = settingsManager.fetchElevenLabsKey()
        }
    }

    // MARK: - Model Refresh

    private func refreshAllModels() async {
        isRefreshingModels = true
        defer { isRefreshingModels = false }

        await LLMProviderRegistry.shared.refreshModels()

        // Update model counts for display
        let models = LLMProviderRegistry.shared.allModels
        modelCounts = Dictionary(grouping: models, by: { $0.provider ?? "unknown" })
            .mapValues { $0.count }

        logger.info("Refreshed models: \(models.count) total")
    }
}

// MARK: - API Key Row Component
struct APIKeyRow: View {
    let provider: String
    let icon: String
    let placeholder: String
    let helpURL: String
    let isConfigured: Bool
    let currentKey: String?
    let isEditing: Bool
    let isRevealed: Bool
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

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header row
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(Theme.current.fontTitle)
                    .foregroundColor(isConfigured ? settings.resolvedAccentColor : Theme.current.foregroundSecondary)
                    .frame(width: 20)

                Text(provider.uppercased())
                    .font(Theme.current.fontSMBold)

                Spacer()

                // Status indicator
                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(isConfigured ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(isConfigured ? "CONFIGURED" : "NOT SET")
                        .font(.techLabelSmall)
                        .foregroundColor(isConfigured ? .green : .orange)
                }
            }

            if isEditing {
                // Edit mode
                HStack(spacing: Spacing.sm) {
                    SecureField(placeholder, text: $editingKey)
                        .font(Theme.current.fontSM)
                        .textFieldStyle(.plain)
                        .padding(Spacing.sm)
                        .background(Theme.current.surface1)
                        .cornerRadius(CornerRadius.xs)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                .stroke(settings.resolvedAccentColor.opacity(Opacity.half), lineWidth: 1)
                        )

                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(Theme.current.fontXSMedium)
                    }
                    .buttonStyle(.bordered)

                    TalkieButtonSync("SaveAPIKey", section: "Settings") {
                        onSave()
                    } label: {
                        Text("Save")
                            .font(Theme.current.fontXSMedium)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if isConfigured {
                // Display mode with key - passive text field style
                HStack(spacing: Spacing.sm) {
                    // Key display styled as disabled text field
                    HStack(spacing: Spacing.sm) {
                        Text(isRevealed ? (currentKey ?? "") : maskedKey)
                            .font(Theme.current.fontSM)
                            .foregroundColor(Theme.current.foregroundMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        // Reveal button
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

                    TalkieButtonSync("DeleteAPIKey", section: "Settings") {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(Theme.current.fontXS)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            } else {
                // Not configured - show add button
                HStack(spacing: Spacing.sm) {
                    Button(action: onEdit) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "plus.circle.fill")
                                .font(Theme.current.fontXS)
                            Text("Add API Key")
                                .font(Theme.current.fontXSMedium)
                        }
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Link(destination: URL(string: helpURL)!) {
                        HStack(spacing: Spacing.xxs) {
                            Text("Get key")
                                .font(Theme.current.fontXS)
                            Image(systemName: "arrow.up.right.square")
                                .font(Theme.current.fontXS)
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(Theme.current.surface2)
        .cornerRadius(CornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(Theme.current.foreground.opacity(Opacity.light), lineWidth: 1)
        )
    }
}

