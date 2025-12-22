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

    var body: some View {
        @Bindable var settings = settingsManager

        SettingsPageContainer {
            SettingsPageHeader(
                icon: "key",
                title: "API KEYS",
                subtitle: "Manage API keys for cloud AI providers. Keys are stored securely in the macOS Keychain."
            )
        } content: {
            // MARK: - Provider API Keys
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.blue)
                        .frame(width: 3, height: 14)

                    Text("CLOUD PROVIDERS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Spacer()

                    // Count configured keys
                    let configuredCount = [
                        settingsManager.hasOpenAIKey(),
                        settingsManager.hasAnthropicKey(),
                        settingsManager.hasValidApiKey,
                        settingsManager.hasGroqKey()
                    ].filter { $0 }.count

                    HStack(spacing: 4) {
                        Circle()
                            .fill(configuredCount > 0 ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text("\(configuredCount)/4 CONFIGURED")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(configuredCount > 0 ? .green : .orange)
                    }
                }

                VStack(spacing: 12) {
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
                }
            }
            .padding(16)
            .background(Theme.current.surface2)
            .cornerRadius(8)

            // MARK: - LLM Cost Tier Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple)
                        .frame(width: 3, height: 14)

                    Text("LLM COST TIER")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Spacer()

                    // Current tier badge
                    Text(settingsManager.llmCostTier.displayName.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(tierColor(settingsManager.llmCostTier))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tierColor(settingsManager.llmCostTier).opacity(0.15))
                        .cornerRadius(3)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Controls the default model quality for workflow LLM steps.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(.secondary.opacity(0.8))

                    Picker("Cost Tier", selection: $settings.llmCostTier) {
                        ForEach(LLMCostTier.allCases, id: \.self) { tier in
                            Text(tier.displayName).tag(tier)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    // Tier description card
                    HStack(spacing: 12) {
                        Image(systemName: tierIcon(settingsManager.llmCostTier))
                            .font(.system(size: 18))
                            .foregroundColor(tierColor(settingsManager.llmCostTier))
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(settingsManager.llmCostTier.displayName)
                                .font(Theme.current.fontSMMedium)
                            Text(tierDescription(settingsManager.llmCostTier))
                                .font(Theme.current.fontXS)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.current.surface1)
                    .cornerRadius(8)
                }
            }
            .padding(16)
            .background(Theme.current.surface2)
            .cornerRadius(8)

            // MARK: - Keychain Info
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(Theme.current.fontXS)
                    .foregroundColor(.green)

                Text("API keys are encrypted and stored in the macOS Keychain for maximum security.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)
        }
    }

    private func tierIcon(_ tier: LLMCostTier) -> String {
        switch tier {
        case .budget: return "leaf"
        case .balanced: return "scale.3d"
        case .capable: return "sparkles"
        }
    }

    private func tierColor(_ tier: LLMCostTier) -> Color {
        switch tier {
        case .budget: return .green
        case .balanced: return .orange
        case .capable: return .purple
        }
    }

    private func tierDescription(_ tier: LLMCostTier) -> String {
        switch tier {
        case .budget:
            return "Uses Groq (free) or Gemini Flash. Fastest, lowest cost."
        case .balanced:
            return "Uses Gemini 2.0 Flash or GPT-4o-mini. Good balance of quality and cost."
        case .capable:
            return "Uses Claude Sonnet or GPT-4o. Best quality for complex reasoning."
        }
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
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(Theme.current.fontTitle)
                    .foregroundColor(isConfigured ? settings.resolvedAccentColor : .secondary)
                    .frame(width: 20)

                Text(provider.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))

                Spacer()

                // Status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(isConfigured ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(isConfigured ? "CONFIGURED" : "NOT SET")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(isConfigured ? .green : .orange)
                }
            }

            if isEditing {
                // Edit mode
                HStack(spacing: 8) {
                    SecureField(placeholder, text: $editingKey)
                        .font(.system(size: 11, design: .monospaced))
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Theme.current.surface1)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(settings.resolvedAccentColor.opacity(0.5), lineWidth: 1)
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
                HStack(spacing: 8) {
                    // Key display styled as disabled text field
                    HStack(spacing: 8) {
                        Text(isRevealed ? (currentKey ?? "") : maskedKey)
                            .font(.system(size: 11, design: .monospaced))
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
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
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(Theme.current.fontXS)
                            Text("Add API Key")
                                .font(Theme.current.fontXSMedium)
                        }
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Link(destination: URL(string: helpURL)!) {
                        HStack(spacing: 4) {
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
        .padding(16)
        .background(Theme.current.surface2)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

