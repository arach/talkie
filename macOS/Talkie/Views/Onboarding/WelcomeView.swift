//
//  WelcomeView.swift
//  Talkie macOS
//
//  Welcome screen for onboarding flow
//

import SwiftUI

struct WelcomeView: View {
    let onNext: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var colors: OnboardingColors {
        OnboardingColors.forScheme(colorScheme)
    }

    var body: some View {
        OnboardingStepLayout(
            colors: colors,
            title: "WELCOME TO TALKIE",
            subtitle: "Your personal voice memo system",
            illustration: {
                // App icon
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 88, height: 88)
                        .shadow(color: colors.accent.opacity(0.3), radius: 12, x: 0, y: 4)
                } else {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 88))
                        .foregroundColor(colors.accent)
                }
            },
            content: {
                // Features - 3 column layout
                HStack(spacing: Spacing.xl) {
                    FeatureColumn(
                        colors: colors,
                        icon: "mic.fill",
                        title: "Record",
                        description: "Capture voice\nmemos anywhere"
                    )
                    FeatureColumn(
                        colors: colors,
                        icon: "text.badge.checkmark",
                        title: "Transcribe",
                        description: "AI-powered\ntranscription"
                    )
                    FeatureColumn(
                        colors: colors,
                        icon: "folder.fill",
                        title: "Organize",
                        description: "Search and\nmanage memos"
                    )
                }
            },
            cta: {
                OnboardingCTAButton(
                    colors: colors,
                    title: "GET STARTED",
                    action: onNext
                )
            }
        )
    }
}

// MARK: - Feature Column

private struct FeatureColumn: View {
    let colors: OnboardingColors
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(colors.accent)
                .frame(width: 32, height: 32)

            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(colors.textPrimary)

                Text(description)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 100)
    }
}

#Preview("Light") {
    WelcomeView(onNext: {})
        .frame(width: 680, height: 520)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    WelcomeView(onNext: {})
        .frame(width: 680, height: 520)
        .preferredColorScheme(.dark)
}
