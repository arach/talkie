//
//  LiveModePitchView.swift
//  Talkie macOS
//
//  Introduces Live mode features with status bar preview and shortcut selection
//  Optional feature that can be enabled here or later in Settings
//

import SwiftUI

struct LiveModePitchView: View {
    let onNext: () -> Void
    @ObservedObject private var manager = OnboardingManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var animationPhase: Int = 0

    private var colors: OnboardingColors {
        OnboardingColors.forScheme(colorScheme)
    }

    var body: some View {
        OnboardingStepLayout(
            colors: colors,
            title: "UNLOCK LIVE MODE",
            subtitle: manager.enableLiveMode ? "Advanced features enabled" : "Optional power-user features",
            illustration: {
                // Pill animation demo + keyboard shortcut
                VStack(spacing: Spacing.lg) {
                    // Pill demo animation (shows Live workflow)
                    PillDemoAnimation(colors: colors, phase: $animationPhase)
                        .frame(width: 180, height: 110)
                        .onAppear {
                            animatePillDemo()
                        }

                    // Keyboard shortcut display
                    KeyboardShortcutView()
                        .padding(.top, Spacing.xs)
                }
            },
            content: {
                VStack(spacing: Spacing.lg) {
                    // Live mode toggle
                    LiveModeToggle(colors: colors, enabled: $manager.enableLiveMode)

                    // Feature highlights
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        LiveFeatureRow(
                            colors: colors,
                            icon: "text.insert",
                            title: "Auto-Paste Anywhere",
                            description: "Transcribed text appears instantly at your cursor",
                            isEnabled: manager.enableLiveMode
                        )

                        LiveFeatureRow(
                            colors: colors,
                            icon: "rectangle.on.rectangle",
                            title: "Screen Context",
                            description: "AI sees what's on screen for better responses",
                            isEnabled: manager.enableLiveMode
                        )

                        LiveFeatureRow(
                            colors: colors,
                            icon: "bolt.fill",
                            title: "Global Hotkey",
                            description: "Summon from any app with ⌥⌘L",
                            isEnabled: manager.enableLiveMode
                        )
                    }
                    .frame(width: 480)

                    // Note
                    Text(manager.enableLiveMode ?
                        "Live features can be disabled anytime in Settings" :
                        "You can enable Live mode later in Settings")
                        .font(.system(size: 10))
                        .foregroundColor(colors.textTertiary)
                        .padding(.top, Spacing.sm)
                }
            },
            cta: {
                OnboardingCTAButton(
                    colors: colors,
                    title: "CONTINUE",
                    icon: "arrow.right",
                    action: onNext
                )
            }
        )
    }

    private func animatePillDemo() {
        // Full recording lifecycle for Live demo:
        // Phase 0: Idle sliver, cursor approaches (2s)
        // Phase 1: Cursor arrives, pill expands to "REC" (1.5s)
        // Phase 2: Click - recording starts, cursor stays briefly (1.2s)
        // Phase 3: Cursor moves away, pill becomes red sliver with pulsing (4s)
        // Phase 4: Keys appear, processing (2s)
        // Phase 5: Success (checkmark) (1.5s)
        // Phase 6: Cursor leaves, back to idle (1s)

        Task {
            while true {
                // Phase 0: Idle sliver, cursor approaching
                withAnimation(.easeIn(duration: 0.4)) { animationPhase = 0 }
                try? await Task.sleep(nanoseconds: 2_000_000_000)

                // Phase 1: Cursor arrives, pill expands to "REC"
                withAnimation(.easeOut(duration: 0.4)) { animationPhase = 1 }
                try? await Task.sleep(nanoseconds: 1_500_000_000)

                // Phase 2: Click - recording starts, cursor still there
                withAnimation(.easeOut(duration: 0.15)) { animationPhase = 2 }
                try? await Task.sleep(nanoseconds: 1_200_000_000)

                // Phase 3: Cursor moves away, pill becomes red sliver with pulsing
                withAnimation(.easeInOut(duration: 0.5)) { animationPhase = 3 }
                try? await Task.sleep(nanoseconds: 4_000_000_000)

                // Phase 4: Keys appear, processing
                withAnimation(.easeOut(duration: 0.3)) { animationPhase = 4 }
                try? await Task.sleep(nanoseconds: 2_000_000_000)

                // Phase 5: Success (checkmark)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { animationPhase = 5 }
                try? await Task.sleep(nanoseconds: 1_500_000_000)

                // Phase 6: Cursor leaves, back to idle
                withAnimation(.easeIn(duration: 0.4)) { animationPhase = 6 }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}

// MARK: - Live Mode Toggle

private struct LiveModeToggle: View {
    let colors: OnboardingColors
    @Binding var enabled: Bool

    var body: some View {
        HStack(spacing: Spacing.md) {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Live Mode")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.textPrimary)

                    Text("Unlock advanced productivity features")
                        .font(.system(size: 11))
                        .foregroundColor(colors.textSecondary)
                }
            }
            .toggleStyle(.switch)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(enabled ? colors.accent.opacity(0.1) : colors.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(enabled ? colors.accent.opacity(0.3) : colors.border, lineWidth: enabled ? 2 : 1)
        )
        .animation(.easeInOut(duration: 0.2), value: enabled)
    }
}

// MARK: - Live Feature Row

private struct LiveFeatureRow: View {
    let colors: OnboardingColors
    let icon: String
    let title: String
    let description: String
    let isEnabled: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(isEnabled ? colors.accent : colors.textTertiary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colors.textPrimary)

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if isEnabled {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(colors.accent)
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(isEnabled ? colors.accent.opacity(0.05) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}

#Preview("Disabled") {
    LiveModePitchView(onNext: {})
        .frame(width: 680, height: 520)
        .onAppear {
            OnboardingManager.shared.enableLiveMode = false
        }
}

#Preview("Enabled") {
    LiveModePitchView(onNext: {})
        .frame(width: 680, height: 520)
        .onAppear {
            OnboardingManager.shared.enableLiveMode = true
        }
}
