//
//  LLMConfigView.swift
//  Talkie macOS
//
//  Optional LLM configuration step for AI workflows
//  Implements secure API key storage using Apple Keychain
//

import SwiftUI

struct LLMConfigView: View {
    let onNext: () -> Void
    @Bindable private var manager = OnboardingManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPulsing = false

    private var colors: OnboardingColors {
        OnboardingColors.forScheme(colorScheme)
    }

    // Use computed property to sync with manager's state
    private var selectedModel: LocalAIModel? {
        get {
            guard let rawValue = manager.selectedLocalModel else { return nil }
            return LocalAIModel(rawValue: rawValue)
        }
    }

    private func selectModel(_ model: LocalAIModel) {
        manager.selectedLocalModel = model.rawValue
    }

    var body: some View {
        OnboardingStepLayout(
            colors: colors,
            title: "LOCAL AI MODELS",
            subtitle: "Private, fast, and free - runs entirely on your Mac",
            illustration: {
                ZStack {
                    // Pulsing rings
                    ForEach(0..<3) { index in
                        Circle()
                            .stroke(colors.accent.opacity(0.3), lineWidth: 2)
                            .frame(width: 80 + CGFloat(index * 30))
                            .scaleEffect(isPulsing ? 1.2 : 1.0)
                            .opacity(isPulsing ? 0.5 : 0.8)
                    }

                    // Brain/CPU icon
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 56))
                        .foregroundColor(colors.accent)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
            },
            content: {
                VStack(spacing: Spacing.md) {
                    // Local AI models
                    HStack(spacing: 10) {
                        ForEach(LocalAIModel.allCases) { model in
                            LocalAIModelCard(
                                colors: colors,
                                model: model,
                                isSelected: selectedModel == model,
                                onSelect: {
                                    withAnimation {
                                        selectModel(model)
                                    }
                                }
                            )
                        }
                    }

                    // Cloud provider note
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "cloud")
                                .font(.system(size: 14))
                                .foregroundColor(colors.textTertiary.opacity(0.6))

                            Text("Want to use OpenAI or Anthropic?")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(colors.textSecondary)
                        }

                        Text("You can add API keys later in Settings → AI Models")
                            .font(.system(size: 10))
                            .foregroundColor(colors.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                            .fill(colors.surfaceCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.xs)
                                    .strokeBorder(colors.border.opacity(0.5), lineWidth: 1)
                            )
                    )
                }
                .frame(width: 600)
            },
            cta: {
                OnboardingCTAButton(
                    colors: colors,
                    title: selectedModel != nil ? "CONTINUE" : "SKIP FOR NOW",
                    icon: "arrow.right",
                    action: handleContinue
                )
            }
        )
    }

    private func handleContinue() {
        // Save selected local model if any
        if let rawValue = manager.selectedLocalModel,
           let model = LocalAIModel(rawValue: rawValue) {
            manager.llmProvider = "local:\(model.rawValue)"
            manager.hasConfiguredLLM = true
        } else {
            manager.llmProvider = nil
            manager.hasConfiguredLLM = false
        }

        onNext()
    }
}

// MARK: - Local AI Model

enum LocalAIModel: String, CaseIterable, Identifiable {
    case llama = "llama"
    case qwen = "qwen"
    case gemma = "gemma"
    case mixtral = "mixtral"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .llama: return "Llama 3.2"
        case .qwen: return "Qwen 2.5"
        case .gemma: return "Gemma 2"
        case .mixtral: return "Mixtral"
        }
    }

    var provider: String {
        switch self {
        case .llama: return "Meta"
        case .qwen: return "Alibaba"
        case .gemma: return "Google"
        case .mixtral: return "Mistral AI"
        }
    }

    var size: String {
        switch self {
        case .llama: return "~2 GB"
        case .qwen: return "~1.5 GB"
        case .gemma: return "~1.8 GB"
        case .mixtral: return "~4 GB"
        }
    }

    var capabilities: [String] {
        switch self {
        case .llama:
            return ["Fast inference", "Strong reasoning", "Multi-language"]
        case .qwen:
            return ["Lightweight", "Code-focused", "Math & logic"]
        case .gemma:
            return ["Efficient", "Instruction tuned", "Balanced"]
        case .mixtral:
            return ["Expert routing", "High quality", "Versatile"]
        }
    }

    var badge: String? {
        switch self {
        case .llama: return "RECOMMENDED"
        case .qwen: return "LIGHTWEIGHT"
        case .gemma: return nil
        case .mixtral: return "ADVANCED"
        }
    }
}

// MARK: - Local AI Model Card

private struct LocalAIModelCard: View {
    let colors: OnboardingColors
    let model: LocalAIModel
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.displayName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(colors.textPrimary)

                        Text(model.provider)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(colors.textTertiary)
                    }

                    Spacer()
                }

                Divider()
                    .background(colors.border)

                // Capabilities
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.capabilities, id: \.self) { capability in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(colors.accent.opacity(0.6))
                                .frame(width: 4, height: 4)
                            Text(capability)
                                .font(.system(size: 9))
                                .foregroundColor(colors.textSecondary)
                        }
                    }
                }

                Spacer()

                // Size
                HStack {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 10))
                    Text(model.size)
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundColor(colors.textTertiary)
            }
            .padding(Spacing.sm)
            .padding(.top, 4)
            .frame(width: 135, height: 160)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(colors.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(isSelected ? colors.accent : colors.border, lineWidth: isSelected ? 2 : 1)
                    )
            )
            .overlay(alignment: .top) {
                // Badge
                if let badge = model.badge {
                    Text(badge)
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(model == .llama ? colors.accent : colors.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(colors.surfaceCard)
                                .overlay(
                                    Capsule()
                                        .strokeBorder((model == .llama ? colors.accent : colors.border).opacity(0.5), lineWidth: 1)
                                )
                        )
                        .offset(y: -6)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
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
