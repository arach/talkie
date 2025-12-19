//
//  OnboardingStoryboardGenerator.swift
//  Talkie macOS
//
//  Storyboard generator for onboarding flow using DebugKit
//

import SwiftUI
import DebugKit

@MainActor
class OnboardingStoryboardGenerator {
    static let shared = OnboardingStoryboardGenerator()

    private init() {}

    private lazy var generator: StoryboardGenerator<OnboardingStep> = {
        StoryboardGenerator<OnboardingStep>(
            config: .init(
                screenSize: CGSize(width: 680, height: 560),
                showLayoutGrid: true,
                layoutZones: [
                    .header(height: 48),
                    .content(topOffset: 48, bottomOffset: 48),
                    .footer(height: 48)
                ],
                gridSpacing: 8
            ),
            viewBuilder: { [weak self] step in
                self?.createView(for: step) ?? AnyView(EmptyView())
            }
        )
    }()

    /// Generate storyboard headlessly (for CLI)
    func generateAndExit(outputPath: String? = nil) async {
        await generator.generate(outputPath: outputPath)
    }

    /// Generate storyboard in-app
    func generateImage() async -> NSImage? {
        await generator.generateImage()
    }

    private func createView(for step: OnboardingStep) -> AnyView {
        let manager = OnboardingManager.shared
        manager.currentStep = step

        let colors = OnboardingColors.forScheme(.dark)

        let view = ZStack {
            // Background
            colors.background
                .ignoresSafeArea()

            // Grid pattern
            GridPatternView(lineColor: colors.gridLine)
                .opacity(0.5)

            VStack(spacing: 0) {
                // Top bar (header zone - 48px)
                HStack {
                    Color.clear
                        .frame(height: 48)
                }
                .padding(.horizontal, Spacing.lg)

                // Step content
                Group {
                    switch step {
                    case .welcome:
                        WelcomeView(onNext: {})
                    case .permissions:
                        PermissionsSetupView(onNext: {})
                    case .modelInstall:
                        ModelInstallView(onNext: {})
                    case .llmConfig:
                        LLMConfigView(onNext: {})
                    case .liveModePitch:
                        LiveModePitchView(onNext: {})
                    case .statusCheck:
                        StatusCheckView(onNext: {})
                    case .complete:
                        CompleteView(onComplete: {})
                    }
                }
                .frame(maxHeight: .infinity)

                // Navigation area (footer zone - 48px)
                Color.clear
                    .frame(height: 48)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.bottom, Spacing.sm)
            }
        }

        return AnyView(view)
    }
}
