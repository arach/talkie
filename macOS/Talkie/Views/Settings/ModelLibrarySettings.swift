//
//  ModelLibrarySettings.swift
//  Talkie macOS
//
//  Cloud AI provider configuration - uses same design as Models sidebar
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

// MARK: - Model Library View

struct ModelLibraryView: View {
    @Environment(SettingsManager.self) private var settingsManager

    @State private var expandedProvider: String?

    private let settings = SettingsManager.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Header
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("SETTINGS / AI & LLM")
                        .font(Theme.current.fontXSMedium)
                        .foregroundColor(Theme.current.foregroundMuted)

                    Text("CLOUD AI PROVIDERS")
                        .font(Theme.current.fontHeadlineBold)
                        .foregroundColor(Theme.current.foreground)

                    Text("Configure API keys to enable cloud AI models for workflows and smart features.")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .lineLimit(2)
                }

                // Cloud Providers Grid
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
                            NotificationCenter.default.post(name: .navigateToSettings, object: "apiKeys")
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
                            NotificationCenter.default.post(name: .navigateToSettings, object: "apiKeys")
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
                            NotificationCenter.default.post(name: .navigateToSettings, object: "apiKeys")
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
                            NotificationCenter.default.post(name: .navigateToSettings, object: "apiKeys")
                        }
                    )
                }

                // Quick configure hint
                if !hasAnyProviderConfigured {
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
                            NotificationCenter.default.post(name: .navigateToSettings, object: "apiKeys")
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
                    .padding(Spacing.md)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .stroke(Theme.current.divider, lineWidth: 1)
                    )
                }

                Spacer(minLength: Spacing.xxl)
            }
            .padding(Spacing.xl)
        }
        .background(Theme.current.background)
    }

    private var hasAnyProviderConfigured: Bool {
        settingsManager.openaiApiKey != nil ||
        settingsManager.anthropicApiKey != nil ||
        settingsManager.hasValidApiKey ||
        settingsManager.groqApiKey != nil
    }
}

#Preview {
    ModelLibraryView()
        .environment(SettingsManager.shared)
        .frame(width: 800, height: 600)
}
