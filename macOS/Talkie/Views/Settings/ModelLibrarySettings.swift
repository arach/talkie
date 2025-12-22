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
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("SETTINGS / AI & LLM")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(settings.midnightTextTertiary)

                    Text("CLOUD AI PROVIDERS")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(settings.midnightTextPrimary)

                    Text("Configure API keys to enable cloud AI models for workflows and smart features.")
                        .font(.system(size: 12))
                        .foregroundColor(settings.midnightTextSecondary)
                        .lineLimit(2)
                }

                // Cloud Providers Grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 8) {
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
                    HStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 14))
                            .foregroundColor(settings.midnightTextTertiary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("No API keys configured")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(settings.midnightTextSecondary)
                            Text("Click 'Configure' on any provider to add your API key")
                                .font(.system(size: 11))
                                .foregroundColor(settings.midnightTextTertiary)
                        }

                        Spacer()

                        Button(action: {
                            NotificationCenter.default.post(name: .navigateToSettings, object: "apiKeys")
                        }) {
                            Text("Go to API Keys")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(settings.midnightTextSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(settings.midnightSurfaceElevated)
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(settings.midnightBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .background(settings.midnightSurface)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(settings.midnightBorder, lineWidth: 1)
                    )
                }

                Spacer(minLength: 40)
            }
            .padding(24)
        }
        .background(settings.midnightBase)
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
