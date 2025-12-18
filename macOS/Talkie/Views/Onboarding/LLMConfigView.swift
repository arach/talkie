//
//  LLMConfigView.swift
//  Talkie macOS
//
//  Optional LLM configuration step for AI workflows
//

import SwiftUI

struct LLMConfigView: View {
    let onNext: () -> Void
    @ObservedObject private var manager = OnboardingManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedProvider: OnboardingLLMProvider? = nil
    @State private var apiKey: String = ""
    @State private var showingAPIKeyField = false

    private var colors: OnboardingColors {
        OnboardingColors.forScheme(colorScheme)
    }

    var body: some View {
        OnboardingStepLayout(
            colors: colors,
            title: "AI WORKFLOWS",
            subtitle: "Enhance with LLM capabilities (optional)",
            illustration: {
                ZStack {
                    // Sparkle/AI icon
                    Image(systemName: "sparkles")
                        .font(.system(size: 56))
                        .foregroundColor(colors.accent)
                        .symbolEffect(.pulse, value: selectedProvider != nil)
                }
            },
            content: {
                VStack(spacing: Spacing.lg) {
                    if !showingAPIKeyField {
                        // Provider selection
                        Text("Choose an LLM provider to enable AI-powered workflows")
                            .font(.system(size: 11))
                            .foregroundColor(colors.textSecondary)
                            .multilineTextAlignment(.center)

                        HStack(spacing: Spacing.md) {
                            OnboardingProviderCard(
                                colors: colors,
                                provider: .openai,
                                isSelected: selectedProvider == .openai,
                                onTap: {
                                    selectedProvider = .openai
                                    showingAPIKeyField = true
                                }
                            )

                            OnboardingProviderCard(
                                colors: colors,
                                provider: .anthropic,
                                isSelected: selectedProvider == .anthropic,
                                onTap: {
                                    selectedProvider = .anthropic
                                    showingAPIKeyField = true
                                }
                            )
                        }
                    } else {
                        // API key input
                        if let provider = selectedProvider {
                            VStack(spacing: Spacing.md) {
                                Text("Enter your \(provider.displayName) API key")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(colors.textPrimary)

                                SecureField("API Key", text: $apiKey)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, design: .monospaced))
                                    .padding(Spacing.sm)
                                    .background(colors.surfaceCard)
                                    .cornerRadius(CornerRadius.xs)
                                    .frame(width: 320)

                                Text("Get your API key from \(provider.website)")
                                    .font(.system(size: 10))
                                    .foregroundColor(colors.textTertiary)

                                Button("Back to provider selection") {
                                    showingAPIKeyField = false
                                    selectedProvider = nil
                                    apiKey = ""
                                }
                                .font(.system(size: 10))
                                .foregroundColor(colors.textSecondary)
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Text("You can configure this later in Settings")
                        .font(.system(size: 10))
                        .foregroundColor(colors.textTertiary)
                }
                .frame(width: 400)
            },
            cta: {
                HStack(spacing: Spacing.md) {
                    // Skip button
                    OnboardingCTAButton(
                        colors: colors,
                        title: "SKIP",
                        icon: "",
                        isEnabled: true,
                        action: {
                            manager.skipLLMConfiguration()
                            onNext()
                        }
                    )

                    // Continue/Configure button
                    if showingAPIKeyField && !apiKey.isEmpty {
                        OnboardingCTAButton(
                            colors: colors,
                            title: "CONFIGURE",
                            icon: "checkmark",
                            action: {
                                if let provider = selectedProvider {
                                    Task {
                                        await manager.configureLLM(provider: provider.rawValue, apiKey: apiKey)
                                        onNext()
                                    }
                                }
                            }
                        )
                    }
                }
            }
        )
    }
}

// MARK: - LLM Provider

private enum OnboardingLLMProvider: String {
    case openai = "openai"
    case anthropic = "anthropic"

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        }
    }

    var icon: String {
        switch self {
        case .openai: return "cpu"
        case .anthropic: return "sparkles"
        }
    }

    var website: String {
        switch self {
        case .openai: return "platform.openai.com"
        case .anthropic: return "console.anthropic.com"
        }
    }
}

// MARK: - Provider Card

private struct OnboardingProviderCard: View {
    let colors: OnboardingColors
    let provider: OnboardingLLMProvider
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: Spacing.sm) {
                Image(systemName: provider.icon)
                    .font(.system(size: 32))
                    .foregroundColor(colors.accent)

                Text(provider.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
            }
            .frame(width: 140, height: 100)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(colors.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(isSelected ? colors.accent : colors.border, lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

#Preview("Light") {
    LLMConfigView(onNext: {})
        .frame(width: 680, height: 520)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    LLMConfigView(onNext: {})
        .frame(width: 680, height: 520)
        .preferredColorScheme(.dark)
}
