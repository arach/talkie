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
    @ObservedObject var settingsManager: SettingsManager
    @State private var editingProvider: String?
    @State private var editingKeyInput: String = ""
    @State private var revealedKeys: Set<String> = []
    @State private var fetchedKeys: [String: String] = [:]  // Cache fetched keys

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "key",
                title: "API KEYS",
                subtitle: "Manage API keys for cloud AI providers. Keys are stored securely in the macOS Keychain."
            )
        } content: {
            // Provider API Keys
            VStack(spacing: 16) {
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

            Divider()
                .background(Theme.current.divider)
                .padding(.vertical, 8)

            // LLM Cost Tier Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("LLM COST TIER")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                Text("Controls the default model quality for workflow LLM steps. Budget uses cheaper/faster models, Capable uses more powerful models.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)

                Picker("Cost Tier", selection: $settingsManager.llmCostTier) {
                    ForEach(LLMCostTier.allCases, id: \.self) { tier in
                        Text(tier.displayName).tag(tier)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                // Tier description
                HStack(spacing: 6) {
                    Circle()
                        .fill(tierColor(settingsManager.llmCostTier))
                        .frame(width: 6, height: 6)
                    Text(tierDescription(settingsManager.llmCostTier))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)

            Spacer()
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
                    .font(SettingsManager.shared.fontTitle)
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
                                .font(SettingsManager.shared.fontXS)
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
                            .font(SettingsManager.shared.fontXS)
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
                                .font(SettingsManager.shared.fontXS)
                            Text("Add API Key")
                                .font(Theme.current.fontXSMedium)
                        }
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Link(destination: URL(string: helpURL)!) {
                        HStack(spacing: 4) {
                            Text("Get key")
                                .font(SettingsManager.shared.fontXS)
                            Image(systemName: "arrow.up.right.square")
                                .font(SettingsManager.shared.fontXS)
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

