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

    private var requiredPermissionsGranted: Bool {
        manager.hasMicrophonePermission
            && manager.hasAccessibilityPermission
            && (!manager.enableLiveMode || (manager.hasAgentMicrophonePermission && manager.hasAgentAccessibilityPermission))
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
                    if manager.enableLiveMode {
                        HStack(alignment: .top, spacing: Spacing.md) {
                            PermissionGroup(colors: colors, title: "Talkie") {
                                PermissionRow(
                                    colors: colors,
                                    icon: "mic.fill",
                                    title: "Microphone Access",
                                    description: "Capture audio for transcriptions",
                                    isGranted: manager.hasMicrophonePermission,
                                    actionTitle: "Grant",
                                    isRequired: true,
                                    action: {
                                        Task {
                                            await manager.requestMicrophonePermission()
                                        }
                                    }
                                )

                                PermissionRow(
                                    colors: colors,
                                    icon: "app",
                                    title: "Accessibility Access",
                                    description: "Read app context for workflows",
                                    isGranted: manager.hasAccessibilityPermission,
                                    actionTitle: "Open",
                                    isRequired: true,
                                    action: {
                                        manager.requestAccessibilityPermission()
                                    }
                                )
                            }

                            PermissionGroup(colors: colors, title: "Agent") {
                                PermissionRow(
                                    colors: colors,
                                    icon: "waveform",
                                    title: "Microphone Access",
                                    description: "Listen for live dictation",
                                    isGranted: manager.hasAgentMicrophonePermission,
                                    actionTitle: manager.isRequestingAgentMicrophonePermission ? "Requesting..." : "Grant",
                                    isRequired: true,
                                    action: {
                                        Task {
                                            await manager.requestAgentMicrophonePermission()
                                        }
                                    }
                                )

                                PermissionRow(
                                    colors: colors,
                                    icon: "command",
                                    title: "Accessibility Access",
                                    description: "Auto-paste dictated text",
                                    isGranted: manager.hasAgentAccessibilityPermission,
                                    actionTitle: manager.isRequestingAgentAccessibilityPermission ? "Requesting..." : "Open",
                                    isRequired: true,
                                    action: {
                                        Task {
                                            await manager.requestAgentAccessibilityPermission()
                                        }
                                    }
                                )
                            }
                        }
                        .frame(width: 584)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        VStack(spacing: Spacing.md) {
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

                            PermissionRow(
                                colors: colors,
                                icon: "app",
                                title: "Accessibility Access",
                                description: "Read app context for workflows",
                                isGranted: manager.hasAccessibilityPermission,
                                actionTitle: "Open Settings",
                                isRequired: true,
                                action: {
                                    manager.requestAccessibilityPermission()
                                }
                            )
                        }
                        .frame(width: 380)
                    }

                    // Helper text
                    Text(manager.enableLiveMode
                         ? "Grant Talkie and Agent permissions before continuing so setup can verify dictation and auto-paste."
                         : "Microphone access is needed to record and transcribe audio.")
                        .font(.system(size: 11))
                        .foregroundColor(colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, Spacing.xs)
                }
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
            Task {
                await manager.refreshAgentMicrophonePermission()
                await manager.refreshAgentAccessibilityPermission()
                manager.startPermissionPolling()
            }
        }
    }
}

private struct PermissionGroup<Content: View>: View {
    let colors: OnboardingColors
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(colors.textSecondary)

            VStack(spacing: Spacing.sm) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
        .frame(minHeight: 48)
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
