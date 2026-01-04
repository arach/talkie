//
//  PermissionsSetupView.swift
//  Talkie macOS
//
//  Permissions setup step for onboarding
//

import SwiftUI

struct PermissionsSetupView: View {
    let onNext: () -> Void
    @Bindable private var manager = OnboardingManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPulsing = false

    private var colors: OnboardingColors {
        OnboardingColors.forScheme(colorScheme)
    }

    // Required permissions depend on Live mode
    private var requiredPermissionsGranted: Bool {
        if manager.enableLiveMode {
            // Live mode: require mic + accessibility
            return manager.hasMicrophonePermission && manager.hasAccessibilityPermission
        } else {
            // Core mode: require mic only
            return manager.hasMicrophonePermission
        }
    }

    var body: some View {
        OnboardingStepLayout(
            colors: colors,
            title: "GRANT PERMISSIONS",
            subtitle: "Let's enable the features you need",
            illustration: {
                ZStack {
                    // Subtle pulse ring
                    Circle()
                        .fill(colors.accent.opacity(0.08))
                        .frame(width: 96, height: 96)
                        .scaleEffect(isPulsing ? 1.15 : 1.0)
                        .opacity(isPulsing ? 0.3 : 0.6)

                    // Main circle with light fill
                    Circle()
                        .fill(colors.accent.opacity(0.12))
                        .frame(width: 80, height: 80)

                    // Lock icon
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 32, weight: .medium))
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
                    // Live mode toggle (checkbox at top)
                    HStack {
                        Toggle(isOn: $manager.enableLiveMode) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable Live Mode")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(colors.textPrimary)
                                Text("Advanced features: auto-paste, screen recording")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(colors.textTertiary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                    .padding(Spacing.sm)
                    .background(colors.surfaceCard)
                    .cornerRadius(CornerRadius.sm)

                    // Microphone permission row (always shown)
                    PermissionRow(
                        colors: colors,
                        icon: "mic.fill",
                        title: "Microphone Access",
                        description: "Capture audio for transcriptions",
                        isGranted: manager.hasMicrophonePermission,
                        actionTitle: "Grant Access",
                        isRequired: true,
                        action: {
                            Task {
                                await manager.requestMicrophonePermission()
                            }
                        }
                    )

                    // Accessibility permission row (shown only if Live mode enabled)
                    if manager.enableLiveMode {
                        PermissionRow(
                            colors: colors,
                            icon: "command",
                            title: "Accessibility Access",
                            description: "Paste in place to accelerate your actions",
                            isGranted: manager.hasAccessibilityPermission,
                            actionTitle: "Open Settings",
                            isRequired: true,
                            action: {
                                manager.openAccessibilitySettings()
                            }
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Screen Recording permission row (shown only if Live mode enabled)
                    if manager.enableLiveMode {
                        PermissionRow(
                            colors: colors,
                            icon: "display",
                            title: "Screen Recording",
                            description: "Record screen to capture context",
                            isGranted: manager.hasScreenRecordingPermission,
                            actionTitle: "Grant Access",
                            isRequired: false,
                            action: {
                                manager.requestScreenRecordingPermission()
                            }
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Helper text
                    Text("All processing happens on your Mac - your data never leaves your device")
                        .font(.system(size: 11))
                        .foregroundColor(colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, Spacing.xs)
                }
                .frame(width: 380)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: manager.enableLiveMode)
            },
            cta: {
                HStack {
                    Spacer()
                    OnboardingCTAButton(
                        colors: colors,
                        title: "CONTINUE",
                        icon: "arrow.right",
                        isEnabled: requiredPermissionsGranted,
                        action: onNext
                    )
                }
            }
        )
        .onAppear {
            manager.checkMicrophonePermission()
            manager.checkAccessibilityPermission()
            manager.checkScreenRecordingPermission()
        }
    }
}

// MARK: - Permission Row

private struct PermissionRow: View {
    let colors: OnboardingColors
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let actionTitle: String
    var isRequired: Bool = true
    let action: () -> Void

    @State private var isHovered = false

    // Neutral pending color - not alarming
    private var pendingColor: Color {
        colors.textSecondary
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Icon with color coding - green when granted, neutral when pending
            ZStack {
                Circle()
                    .fill(isGranted ? Color.green.opacity(0.15) : pendingColor.opacity(0.1))
                    .frame(width: 32, height: 32)

                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isGranted ? .green : pendingColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(colors.textPrimary)

                    // Badge - neutral styling for pending, don't use alarming red
                    if !isGranted {
                        Text(isRequired ? "REQUIRED" : "OPTIONAL")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(isRequired ? colors.textSecondary : colors.textTertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .strokeBorder(isRequired ? colors.textSecondary.opacity(0.3) : colors.textTertiary.opacity(0.3), lineWidth: 1)
                            )
                    }
                }

                Text(description)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(colors.textTertiary)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.green)
            } else {
                // Outlined button style - looks more like an actionable button
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isHovered ? .white : colors.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                .fill(isHovered ? colors.accent : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                .strokeBorder(colors.accent, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .onHover { isHovered = $0 }
            }
        }
        .padding(Spacing.sm)
        .background(colors.surfaceCard)
        .cornerRadius(CornerRadius.sm)
    }
}

#Preview("Light") {
    PermissionsSetupView(onNext: {})
        .frame(width: 680, height: 520)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    PermissionsSetupView(onNext: {})
        .frame(width: 680, height: 520)
        .preferredColorScheme(.dark)
}
