//
//  CompleteView.swift
//  Talkie macOS
//
//  Onboarding completion screen
//

import SwiftUI

struct CompleteView: View {
    let onComplete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var showTips = false

    private var colors: OnboardingColors {
        OnboardingColors.forScheme(colorScheme)
    }

    var body: some View {
        OnboardingStepLayout(
            colors: colors,
            title: "YOU'RE ALL SET!",
            subtitle: "Ready to start recording",
            illustration: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(colors.accent)
                    .symbolEffect(.bounce, value: true)
            },
            content: {
                VStack(spacing: Spacing.lg) {
                    // Quick tips
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("QUICK TIPS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(colors.textTertiary)

                        TipRow(
                            colors: colors,
                            icon: "command",
                            text: "Press ⌥⌘L to start/stop recording from anywhere"
                        )

                        TipRow(
                            colors: colors,
                            icon: "magnifyingglass",
                            text: "Use Search (⌘F) to find your memos quickly"
                        )

                        TipRow(
                            colors: colors,
                            icon: "gearshape.fill",
                            text: "Customize settings and workflows anytime"
                        )
                    }
                    .padding(Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(colors.surfaceCard)
                    )
                    .frame(width: 360)

                    Text("You can always re-run this setup from Settings")
                        .font(.system(size: 10))
                        .foregroundColor(colors.textTertiary)
                }
            },
            cta: {
                OnboardingCTAButton(
                    colors: colors,
                    title: "START USING TALKIE",
                    icon: "arrow.right",
                    action: onComplete
                )
            }
        )
    }
}

// MARK: - Tip Row

private struct TipRow: View {
    let colors: OnboardingColors
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(colors.accent)
                .frame(width: 20)

            Text(text)
                .font(.system(size: 11))
                .foregroundColor(colors.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Light") {
    CompleteView(onComplete: {})
        .frame(width: 680, height: 520)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    CompleteView(onComplete: {})
        .frame(width: 680, height: 520)
        .preferredColorScheme(.dark)
}
