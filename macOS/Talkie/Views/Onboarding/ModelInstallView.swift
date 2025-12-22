//
//  ModelInstallView.swift
//  Talkie macOS
//
//  Model installation step for transcription models
//

import SwiftUI

struct ModelInstallView: View {
    let onNext: () -> Void
    @State private var manager = OnboardingManager.shared
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
                            badgeColor: colors.accent,
                            modelURL: URL(string: "https://github.com/FluidInference/FluidAudio")!,
                            paperURL: URL(string: "https://arxiv.org/abs/2409.17143")
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
                            badgeColor: SemanticColor.info,
                            modelURL: URL(string: "https://huggingface.co/openai/whisper-large-v3")!,
                            paperURL: URL(string: "https://arxiv.org/abs/2212.04356")
                        ) {
                            selectedModel = .whisper
                            manager.selectedModelType = "whisper"
                        }
                    }

                    // Helper text moved here - right below model selection
                    if !manager.isModelDownloaded && !manager.isDownloadingModel {
                        Text("Click Continue to start download, you can change this at any time")
                            .font(.system(size: 10))
                            .foregroundColor(colors.textTertiary.opacity(0.8))
                            .padding(.top, Spacing.xs)
                    }
                }
            },
            cta: {
                VStack(spacing: Spacing.xs) {
                    // Show download status if downloading (non-blocking indicator)
                    if manager.isDownloadingModel {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .progressViewStyle(CircularProgressViewStyle(tint: colors.accent))
                            Text("Downloading... \(Int(manager.downloadProgress * 100))%")
                                .font(.system(size: 10))
                                .foregroundColor(colors.textSecondary)
                        }
                        .frame(height: 20)
                    }

                    // Continue button - always enabled (non-blocking)
                    HStack {
                        Spacer()
                        OnboardingCTAButton(
                            colors: colors,
                            title: "CONTINUE",
                            icon: "arrow.right",
                            action: {
                                // Start download in background if not already started
                                if !manager.isModelDownloaded && !manager.isDownloadingModel {
                                    Task {
                                        await manager.downloadModel()
                                    }
                                }
                                onNext()
                            }
                        )
                    }

                    // Helper text (status only)
                    if manager.isDownloadingModel {
                        Text("Download continues in background")
                            .font(.system(size: 9))
                            .foregroundColor(colors.textTertiary.opacity(0.7))
                    } else if manager.isModelDownloaded {
                        Text("Model ready!")
                            .font(.system(size: 9))
                            .foregroundColor(colors.accent.opacity(0.9))
                    }
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
    let modelURL: URL
    let paperURL: URL?
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                // Logo + Model name (version on hover)
                HStack(alignment: .center, spacing: 6) {
                    // Model logo placeholder
                    Circle()
                        .fill(colors.accent.opacity(0.2))
                        .frame(width: 16, height: 16)
                        .overlay(
                            Text(logoName.prefix(1).uppercased())
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(colors.accent)
                        )

                    Text(modelName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(colors.textPrimary)

                    if isHovered {
                        Text(version)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(colors.textTertiary)
                            .transition(.opacity)
                    }
                }

                Divider()
                    .background(colors.border)

                // Specs - more compact
                VStack(alignment: .leading, spacing: 2) {
                    // Size row
                    HStack {
                        Text("Size")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(colors.textTertiary)
                        Spacer()
                        Text(size)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(colors.textSecondary)
                    }
                    ForEach(specs, id: \.0) { spec in
                        HStack {
                            Text(spec.0)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(colors.textTertiary)
                            Spacer()
                            Text(spec.1)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(colors.textSecondary)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .padding(.top, 4)
            .frame(width: 160, height: 115)
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
                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(badgeColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(colors.surfaceCard)
                            .overlay(
                                Capsule()
                                    .strokeBorder(badgeColor.opacity(0.5), lineWidth: 1)
                            )
                    )
                    .offset(y: -6)
            }
            .overlay(alignment: .bottom) {
                // Links overlay - shown on hover (compact)
                if isHovered {
                    HStack(spacing: 8) {
                        Button(action: { NSWorkspace.shared.open(modelURL) }) {
                            HStack(spacing: 2) {
                                Text("Model")
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 6))
                            }
                            .foregroundColor(colors.textSecondary)
                        }
                        .buttonStyle(.plain)

                        if let paperURL = paperURL {
                            Button(action: { NSWorkspace.shared.open(paperURL) }) {
                                HStack(spacing: 2) {
                                    Text("Paper")
                                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 6))
                                }
                                .foregroundColor(colors.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(
                        Rectangle()
                            .fill(colors.background.opacity(0.95))
                            .blur(radius: 8)
                    )
                    .overlay(alignment: .top) {
                        Divider()
                            .background(colors.border)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .clipped()
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
