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
        // Define layout zones for onboarding screens
        let screenHeight: CGFloat = 560
        let headerZoneHeight: CGFloat = 48
        let footerZoneHeight: CGFloat = 48
        let contentHeaderHeight: CGFloat = 48  // Icon/illustration area

        // Calculate content body height (fills remaining space)
        let contentBodyY = headerZoneHeight + contentHeaderHeight
        let contentBodyHeight = screenHeight - headerZoneHeight - contentHeaderHeight - footerZoneHeight

        let layoutZones: [LayoutZone] = [
            // Main zones (subtle shading)
            LayoutZone(
                label: "HEADER",
                frame: .top(height: headerZoneHeight),
                color: .blue,
                style: .subtle
            ),
            LayoutZone(
                label: "FOOTER",
                frame: .bottom(height: footerZoneHeight),
                color: .orange,
                style: .subtle
            ),

            // Content subdivisions (strong borders)
            LayoutZone(
                label: "CONTENT HEADER",
                frame: .custom(x: 0, y: headerZoneHeight, width: 0, height: contentHeaderHeight),
                color: .purple,
                style: .border
            ),
            LayoutZone(
                label: "CONTENT BODY",
                frame: .custom(
                    x: 0,
                    y: contentBodyY,
                    width: 0,
                    height: contentBodyHeight
                ),
                color: .cyan,
                style: .border
            )
        ]

        // Define scenarios
        let manager = OnboardingManager.shared
        let scenarios: [Scenario<OnboardingStep>] = [
            // Default flow
            Scenario<OnboardingStep>(
                name: "default",
                stepConfigurations: [:]
            ),

            // Live mode enabled
            Scenario<OnboardingStep>(
                name: "live-enabled",
                stepConfigurations: [
                    OnboardingStep.permissions: {
                        manager.enableLiveMode = true
                    },
                    OnboardingStep.liveModePitch: {
                        manager.enableLiveMode = true
                    },
                    OnboardingStep.statusCheck: {
                        manager.enableLiveMode = true
                    }
                ]
            ),

            // Status checks failing
            Scenario<OnboardingStep>(
                name: "checks-failing",
                stepConfigurations: [
                    OnboardingStep.statusCheck: {
                        manager.checkStatuses[.modelSelection] = .complete
                        manager.checkStatuses[.modelDownload] = .complete
                        manager.checkStatuses[.engineConnection] = .error("Connection failed")
                        manager.checkStatuses[.engineReady] = .pending
                    }
                ]
            ),

            // Model selection - different model
            Scenario<OnboardingStep>(
                name: "whisper-selected",
                stepConfigurations: [
                    OnboardingStep.modelInstall: {
                        manager.selectedModelType = "whisper"
                    }
                ]
            ),

            // Local AI model selected
            Scenario<OnboardingStep>(
                name: "llm-selected",
                stepConfigurations: [
                    OnboardingStep.llmConfig: {
                        manager.selectedLocalModel = "llama"
                    }
                ]
            )
        ]

        return StoryboardGenerator<OnboardingStep>(
            config: .init(
                screenSize: CGSize(width: 680, height: 560),
                showLayoutGrid: true,
                layoutZones: layoutZones,
                gridSpacing: 8,
                scenarios: scenarios
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
