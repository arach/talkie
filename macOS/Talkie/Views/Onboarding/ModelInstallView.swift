//
//  ModelInstallView.swift
//  Talkie macOS
//
//  Model installation step for transcription models
//

import SwiftUI

struct ModelInstallView: View {
    let onNext: () -> Void
    @ObservedObject private var manager = OnboardingManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedModel: ModelChoice = .parakeet

    private var colors: OnboardingColors {
        OnboardingColors.forScheme(colorScheme)
    }

    var body: some View {
        OnboardingStepLayout(
            colors: colors,
            title: "TRANSCRIPTION MODEL",
            subtitle: "Choose your AI model",
            illustration: {
                // CPU/chip icon - represents on-device AI
                Image(systemName: "cpu.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(colors.accent)
                    .frame(width: 72, height: 72)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colors.accent.opacity(0.15))
                    )
            },
            content: {
                VStack(spacing: Spacing.md) {
                    // Model cards
                    HStack(alignment: .top, spacing: Spacing.md) {
                        OnboardingModelCard(
                            colors: colors,
                            isSelected: selectedModel == .parakeet,
                            logoName: "nvidia",
                            modelName: "Parakeet",
                            version: "v3",
                            size: "~200 MB",
                            specs: [
                                ("Speed", "Ultra-fast"),
                                ("Languages", "English")
                            ],
                            badge: "RECOMMENDED",
                            badgeColor: colors.accent
                        ) {
                            selectedModel = .parakeet
                            manager.selectedModelType = "parakeet"
                        }

                        OnboardingModelCard(
                            colors: colors,
                            isSelected: selectedModel == .whisper,
                            logoName: "openai",
                            modelName: "Whisper",
                            version: "large-v3",
                            size: "~1.5 GB",
                            specs: [
                                ("Speed", "Fast"),
                                ("Languages", "99+")
                            ],
                            badge: "MULTILINGUAL",
                            badgeColor: SemanticColor.info
                        ) {
                            selectedModel = .whisper
                            manager.selectedModelType = "whisper"
                        }
                    }
                }
            },
            cta: {
                if manager.isDownloadingModel {
                    DownloadProgressButton(
                        colors: colors,
                        progress: manager.downloadProgress,
                        status: manager.downloadStatus
                    )
                } else if manager.isModelDownloaded {
                    OnboardingCTAButton(
                        colors: colors,
                        title: "CONTINUE",
                        action: onNext
                    )
                } else {
                    OnboardingCTAButton(
                        colors: colors,
                        title: "DOWNLOAD & CONTINUE",
                        icon: "arrow.down",
                        action: {
                            Task {
                                await manager.downloadModel()
                            }
                        }
                    )
                }
            }
        )
        .onAppear {
            // Sync local state with manager
            selectedModel = manager.selectedModelType == "parakeet" ? .parakeet : .whisper
        }
        .task {
            await manager.checkModelInstalled()
        }
    }
}

// MARK: - Model Choice

private enum ModelChoice {
    case parakeet
    case whisper
}

// MARK: - Download Progress Button

private struct DownloadProgressButton: View {
    let colors: OnboardingColors
    let progress: Double
    let status: String

    var body: some View {
        ZStack {
            // Background track
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(colors.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .strokeBorder(colors.border, lineWidth: 1)
                )

            // Progress fill from left
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(colors.accent.opacity(0.3))
                    .frame(width: geo.size.width * CGFloat(progress))
            }

            // Text overlay
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                    .progressViewStyle(CircularProgressViewStyle(tint: colors.accent))

                Text(status.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(colors.textPrimary)
            }
        }
        .frame(width: 200, height: 44)
    }
}

// MARK: - Model Card

private struct OnboardingModelCard: View {
    let colors: OnboardingColors
    let isSelected: Bool
    let logoName: String
    let modelName: String
    let version: String
    let size: String
    let specs: [(String, String)]
    let badge: String
    let badgeColor: Color
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Logo + Model name (version on hover)
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    // Model logo placeholder
                    Circle()
                        .fill(colors.accent.opacity(0.2))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Text(logoName.prefix(1).uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(colors.accent)
                        )

                    Text(modelName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(colors.textPrimary)

                    if isHovered {
                        Text(version)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(colors.textTertiary)
                            .transition(.opacity)
                    }
                }

                Divider()
                    .background(colors.border)

                // Specs
                VStack(alignment: .leading, spacing: 4) {
                    // Size row
                    HStack {
                        Text("Size")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(colors.textTertiary)
                        Spacer()
                        Text(size)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(colors.textSecondary)
                    }
                    ForEach(specs, id: \.0) { spec in
                        HStack {
                            Text(spec.0)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(colors.textTertiary)
                            Spacer()
                            Text(spec.1)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(colors.textSecondary)
                        }
                    }
                }
            }
            .padding(Spacing.md)
            .padding(.top, 6)
            .frame(width: 170)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(colors.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(isSelected ? colors.accent : colors.border, lineWidth: isSelected ? 2 : 1)
                    )
            )
            .overlay(alignment: .top) {
                // Badge floating on top edge
                Text(badge)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(badgeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(colors.surfaceCard)
                            .overlay(
                                Capsule()
                                    .strokeBorder(badgeColor.opacity(0.5), lineWidth: 1)
                            )
                    )
                    .offset(y: -8)
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
    ModelInstallView(onNext: {})
        .frame(width: 680, height: 520)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ModelInstallView(onNext: {})
        .frame(width: 680, height: 520)
        .preferredColorScheme(.dark)
}
