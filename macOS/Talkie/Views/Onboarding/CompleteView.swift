//
//  CompleteView.swift
//  Talkie macOS
//
//  Onboarding completion screen with conditional content
//  Core mode: Tips and shortcuts
//  Live mode: Interactive demo with first recording celebration
//

import SwiftUI

struct CompleteView: View {
    let onComplete: () -> Void
    private let manager = OnboardingManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var scale: CGFloat = 0.5
    @State private var rotation: Double = 0
    @State private var showCelebration = false

    private var colors: OnboardingColors {
        OnboardingColors.forScheme(colorScheme)
    }

    var body: some View {
        OnboardingStepLayout(
            colors: colors,
            title: "YOU'RE ALL SET!",
            subtitle: "Talkie is ready to use",
            illustration: {
                successIcon
            },
            content: {
                VStack(spacing: Spacing.lg) {
                    if manager.enableLiveMode {
                        liveModeContent
                    } else {
                        coreModeContent
                    }

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
                    action: handleComplete
                )
            }
        )
    }

    // MARK: - Success Icon

    private var successIcon: some View {
        ZStack {
            // Pulsing rings
            ForEach(0..<3) { index in
                Circle()
                    .stroke(colors.accent.opacity(0.3), lineWidth: 2)
                    .frame(width: 100 + CGFloat(index * 30))
                    .scaleEffect(scale)
                    .opacity(2 - scale)
            }

            // Checkmark
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 100))
                .foregroundColor(colors.accent)
                .rotationEffect(.degrees(rotation))
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                scale = 1.5
                rotation = 360
            }
        }
    }

    // MARK: - Core Mode Content

    private var coreModeContent: some View {
        VStack(spacing: Spacing.lg) {
            // Keyboard shortcut reminder
            ShortcutCard(
                colors: colors,
                icon: "command.circle.fill",
                title: "Press ⌘N to start recording",
                subtitle: "Or use the menu bar icon"
            )

            // Quick tips
            HStack(spacing: Spacing.lg) {
                TipCard(
                    colors: colors,
                    icon: "folder.fill",
                    title: "Smart Organization",
                    description: "Your memos are automatically organized by date and content"
                )

                TipCard(
                    colors: colors,
                    icon: "magnifyingglass",
                    title: "Search Everything",
                    description: "Use ⌘F to search across all your transcriptions"
                )

                TipCard(
                    colors: colors,
                    icon: "icloud.fill",
                    title: "Sync Across Devices",
                    description: "Your memos sync automatically via iCloud"
                )
            }

            // Optional: Live mode promo
            if !manager.enableLiveMode {
                LiveModePromoCard(colors: colors)
            }
        }
    }

    // MARK: - Live Mode Content

    private var liveModeContent: some View {
        VStack(spacing: Spacing.lg) {
            // Interactive demo placeholder
            // Note: Full interactive demo would be ported from TalkieLive
            VStack(spacing: Spacing.md) {
                Text("INTERACTIVE DEMO")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(colors.textTertiary)

                Text("Try using ⌥⌘L to start your first recording")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                    .multilineTextAlignment(.center)

                // Simplified pill demo
                SimplePillDemo(colors: colors)
                    .frame(height: 100)
            }
            .padding(Spacing.lg)
            .frame(width: 440)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(colors.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(colors.border, lineWidth: 1)
                    )
            )

            // Celebration (if triggered)
            if showCelebration {
                CelebrationView(colors: colors)
                    .transition(.scale.combined(with: .opacity))
            }

            // Quick tips for Live mode
            VStack(spacing: Spacing.sm) {
                LiveTipRow(
                    colors: colors,
                    icon: "command.circle.fill",
                    title: "Press ⌥⌘L anywhere to start recording",
                    subtitle: "Works in any app, even full-screen"
                )

                LiveTipRow(
                    colors: colors,
                    icon: "text.cursor",
                    title: "Text appears at your cursor automatically",
                    subtitle: "No need to copy/paste manually"
                )

                LiveTipRow(
                    colors: colors,
                    icon: "display",
                    title: "Talkie can see your screen for smarter transcriptions",
                    subtitle: "Enable in Settings if you granted permission"
                )
            }
            .frame(width: 440)
        }
    }

    private func handleComplete() {
        manager.completeOnboarding()
        onComplete()
    }
}

// MARK: - Shortcut Card

private struct ShortcutCard: View {
    let colors: OnboardingColors
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(colors.accent)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(colors.textPrimary)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(colors.textSecondary)
        }
        .padding(Spacing.md)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(colors.surfaceCard)
        )
    }
}

// MARK: - Tip Card

private struct TipCard: View {
    let colors: OnboardingColors
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(colors.accent)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(colors.textPrimary)

            Text(description)
                .font(.system(size: 10))
                .foregroundColor(colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.sm)
        .frame(width: 130, height: 140)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(colors.surfaceCard)
        )
    }
}

// MARK: - Live Tip Row

private struct LiveTipRow: View {
    let colors: OnboardingColors
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.purple)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(colors.textPrimary)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(colors.textSecondary)
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(colors.surfaceCard)
        )
    }
}

// MARK: - Live Mode Promo Card

private struct LiveModePromoCard: View {
    let colors: OnboardingColors

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Want global hotkeys and auto-paste?")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(colors.textPrimary)

                    Text("POWER USERS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.2))
                        .foregroundColor(.purple)
                        .cornerRadius(4)
                }

                Button(action: {
                    // Open Settings to Live mode section
                    // TODO: Implement settings navigation
                }) {
                    Text("Enable Live Mode in Settings →")
                        .font(.system(size: 10))
                        .foregroundColor(colors.accent)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Image(systemName: "waveform.and.mic")
                .font(.system(size: 32))
                .foregroundColor(.purple.opacity(0.5))
        }
        .padding(Spacing.md)
        .frame(width: 440)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(Color.purple.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .strokeBorder(Color.purple.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Simplified Pill Demo

private struct SimplePillDemo: View {
    let colors: OnboardingColors
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Text("The floating pill appears at the bottom of your screen")
                .font(.system(size: 10))
                .foregroundColor(colors.textTertiary)
                .multilineTextAlignment(.center)

            // Simplified pill visualization
            ZStack {
                if isExpanded {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 6, height: 6)

                        Text("REC")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1)
                            .foregroundColor(Color.white.opacity(0.5))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.12))
                    )
                } else {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 24, height: 2)
                }
            }
            .animation(.spring(response: 0.3), value: isExpanded)
            .onTapGesture {
                withAnimation {
                    isExpanded.toggle()
                }
            }

            Text("Click to toggle • Hover to expand")
                .font(.system(size: 9))
                .foregroundColor(colors.textTertiary)
        }
    }
}

// MARK: - Celebration View

private struct CelebrationView: View {
    let colors: OnboardingColors

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 48))
                .foregroundColor(colors.accent)
                .symbolEffect(.bounce, value: true)

            Text("Perfect! You're a pro already")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(colors.accent)

            Text("Try using ⌥⌘L in any app now")
                .font(.system(size: 11))
                .foregroundColor(colors.textSecondary)
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(colors.accent.opacity(0.1))
        )
    }
}

#Preview("Core Mode") {
    CompleteView(onComplete: {})
        .frame(width: 680, height: 520)
        .preferredColorScheme(.dark)
}

#Preview("Live Mode") {
    let manager = OnboardingManager.shared
    manager.enableLiveMode = true
    return CompleteView(onComplete: {})
        .frame(width: 680, height: 520)
        .preferredColorScheme(.dark)
}
