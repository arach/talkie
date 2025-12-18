//
//  PermissionsSetupView.swift
//  Talkie macOS
//
//  Permissions setup step for onboarding
//

import SwiftUI

struct PermissionsSetupView: View {
    let onNext: () -> Void
    @ObservedObject private var manager = OnboardingManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPulsing = false

    private var colors: OnboardingColors {
        OnboardingColors.forScheme(colorScheme)
    }

    private var allPermissionsGranted: Bool {
        manager.hasMicrophonePermission && manager.hasAccessibilityPermission
    }

    var body: some View {
        OnboardingStepLayout(
            colors: colors,
            title: "PERMISSIONS",
            subtitle: "Required for core features",
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
                    // Microphone permission row
                    PermissionRow(
                        colors: colors,
                        icon: "mic.fill",
                        title: "Microphone",
                        description: "Required for recording",
                        isGranted: manager.hasMicrophonePermission,
                        actionTitle: "Grant",
                        action: {
                            Task {
                                await manager.requestMicrophonePermission()
                            }
                        }
                    )

                    // Accessibility permission row
                    PermissionRow(
                        colors: colors,
                        icon: "hand.raised.fill",
                        title: "Accessibility",
                        description: "For global hotkeys",
                        isGranted: manager.hasAccessibilityPermission,
                        actionTitle: "Open Settings",
                        action: {
                            manager.openAccessibilitySettings()
                        }
                    )

                    // Screen Recording permission row (optional)
                    PermissionRow(
                        colors: colors,
                        icon: "rectangle.dashed.badge.record",
                        title: "Screen Recording",
                        description: "For context capture (optional)",
                        isGranted: manager.hasScreenRecordingPermission,
                        actionTitle: "Grant",
                        isOptional: true,
                        action: {
                            manager.requestScreenRecordingPermission()
                        }
                    )

                    if !allPermissionsGranted {
                        Text("Talkie needs these permissions to work properly. Screen Recording is optional but enables better context capture.")
                            .font(.system(size: 11))
                            .foregroundColor(colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, Spacing.xs)
                    }
                }
                .frame(width: 380)
            },
            cta: {
                if allPermissionsGranted {
                    OnboardingCTAButton(
                        colors: colors,
                        title: "CONTINUE",
                        action: onNext
                    )
                } else {
                    OnboardingCTAButton(
                        colors: colors,
                        title: "GRANT REQUIRED PERMISSIONS",
                        icon: "",
                        isEnabled: false,
                        action: {}
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
    var isOptional: Bool = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(isGranted ? .green : (isOptional ? .orange : colors.textTertiary))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(colors.textPrimary)

                    if isOptional {
                        Text("OPTIONAL")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.15))
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
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isOptional ? Color.orange : colors.accent)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.sm)
        .background(colors.surfaceCard)
        .cornerRadius(8)
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
