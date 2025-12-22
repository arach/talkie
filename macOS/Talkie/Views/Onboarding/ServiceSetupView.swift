//
//  ServiceSetupView.swift
//  Talkie macOS
//
//  Service setup step - auto-launch TalkieLive and TalkieEngine
//

import SwiftUI

struct ServiceSetupView: View {
    let onNext: () -> Void
    @Bindable private var manager = OnboardingManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private var colors: OnboardingColors {
        OnboardingColors.forScheme(colorScheme)
    }

    private var allServicesRunning: Bool {
        manager.isTalkieLiveRunning && manager.isTalkieEngineRunning
    }

    var body: some View {
        OnboardingStepLayout(
            colors: colors,
            title: "SERVICE SETUP",
            subtitle: allServicesRunning ? "All services ready" : "Launching background services...",
            illustration: {
                ZStack {
                    // Animated gears or service icons
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 72))
                        .foregroundColor(colors.accent)
                        .symbolEffect(.pulse, value: manager.isLaunchingServices)
                }
            },
            content: {
                VStack(spacing: Spacing.md) {
                    // TalkieLive service status
                    ServiceStatusRow(
                        colors: colors,
                        icon: "waveform.circle.fill",
                        title: "TalkieLive",
                        description: "Recording service",
                        isRunning: manager.isTalkieLiveRunning,
                        isLaunching: manager.isLaunchingServices && !manager.isTalkieLiveRunning
                    )

                    // TalkieEngine service status
                    ServiceStatusRow(
                        colors: colors,
                        icon: "cpu.fill",
                        title: "TalkieEngine",
                        description: "Transcription engine",
                        isRunning: manager.isTalkieEngineRunning,
                        isLaunching: manager.isLaunchingServices && !manager.isTalkieEngineRunning
                    )

                    if let error = manager.errorMessage {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.top, Spacing.xs)
                    }
                }
                .frame(width: 320)
            },
            cta: {
                VStack(spacing: Spacing.xs) {
                    // Continue button - always bottom right
                    HStack {
                        Spacer()
                        OnboardingCTAButton(
                            colors: colors,
                            title: "CONTINUE",
                            icon: "arrow.right",
                            isEnabled: !manager.isLaunchingServices,
                            action: onNext
                        )
                    }

                    // Subtle skip option if services aren't running
                    if !allServicesRunning && !manager.isLaunchingServices {
                        Button(action: onNext) {
                            Text("Skip (start services later)")
                                .font(.system(size: 10))
                                .foregroundColor(colors.textTertiary)
                                .underline()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        )
        .task {
            await manager.checkServices()
            // Auto-launch if not running
            if !allServicesRunning {
                await manager.launchServices()
            }
        }
    }
}

// MARK: - Service Status Row

private struct ServiceStatusRow: View {
    let colors: OnboardingColors
    let icon: String
    let title: String
    let description: String
    let isRunning: Bool
    let isLaunching: Bool

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(isRunning ? .green : colors.textTertiary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colors.textPrimary)

                Text(description)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(colors.textTertiary)
            }

            Spacer()

            if isLaunching {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 18, height: 18)
            } else if isRunning {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.green)
            } else {
                Circle()
                    .strokeBorder(colors.textTertiary, lineWidth: 1)
                    .frame(width: 14, height: 14)
            }
        }
        .padding(Spacing.sm)
        .background(colors.surfaceCard)
        .cornerRadius(8)
    }
}

#Preview("Light") {
    ServiceSetupView(onNext: {})
        .frame(width: 680, height: 520)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ServiceSetupView(onNext: {})
        .frame(width: 680, height: 520)
        .preferredColorScheme(.dark)
}
