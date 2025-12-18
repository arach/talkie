//
//  OnboardingView.swift
//  Talkie macOS
//
//  Main onboarding flow coordinator view
//

import SwiftUI

struct OnboardingView: View {
    @ObservedObject private var manager = OnboardingManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var colors: OnboardingColors {
        OnboardingColors.forScheme(colorScheme)
    }

    var body: some View {
        ZStack {
            // Background
            colors.background
                .ignoresSafeArea()

            // Grid pattern
            GridPatternView(lineColor: colors.gridLine)
                .opacity(0.5)

            VStack(spacing: 0) {
                // Top bar - fixed height for consistent layout
                HStack {
                    Spacer()
                    Button(action: {
                        manager.completeOnboarding()
                        dismiss()
                    }) {
                        Text("SKIP ONBOARDING")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(colors.textTertiary)
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                }
                .frame(height: 44)
                .padding(.horizontal, Spacing.lg)

                // Step content - fixed frame for consistent positioning
                Group {
                    switch manager.currentStep {
                    case .welcome:
                        WelcomeView(onNext: {
                            manager.currentStep = .permissions
                        })
                    case .permissions:
                        PermissionsSetupView(onNext: {
                            manager.currentStep = .serviceSetup
                        })
                    case .serviceSetup:
                        ServiceSetupView(onNext: {
                            manager.currentStep = .modelInstall
                        })
                    case .modelInstall:
                        ModelInstallView(onNext: {
                            manager.currentStep = .llmConfig
                        })
                    case .llmConfig:
                        LLMConfigView(onNext: {
                            manager.currentStep = .complete
                        })
                    case .complete:
                        CompleteView(onComplete: {
                            manager.completeOnboarding()
                            dismiss()
                        })
                    }
                }
                .frame(maxHeight: .infinity)

                // Navigation - always present for consistent layout
                HStack(spacing: Spacing.lg) {
                    // Back button
                    Button(action: {
                        if let previous = OnboardingStep(rawValue: manager.currentStep.rawValue - 1) {
                            manager.currentStep = previous
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(colors.textTertiary)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .opacity(manager.currentStep != .welcome ? 1 : 0)
                    .disabled(manager.currentStep == .welcome)

                    Spacer()

                    // Page dots with pulsation on current step
                    HStack(spacing: Spacing.xs) {
                        ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                            Circle()
                                .fill(step.rawValue <= manager.currentStep.rawValue ? colors.accent : colors.border)
                                .frame(width: step == manager.currentStep ? 8 : 6, height: step == manager.currentStep ? 8 : 6)
                                .scaleEffect(step == manager.currentStep ? 1.0 : 1.0)
                                .animation(.spring(response: 0.3), value: manager.currentStep)
                        }
                    }
                    .opacity(manager.currentStep != .welcome ? 1 : 0)

                    Spacer()

                    // Forward button (visual placeholder for alignment)
                    Color.clear
                        .frame(width: 40, height: 40)
                }
                .frame(height: 40)
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.sm)
            }
        }
        .frame(width: 680, height: 520)
        .background(WindowAccessor())
    }
}

#Preview("Light") {
    OnboardingView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    OnboardingView()
        .preferredColorScheme(.dark)
}
