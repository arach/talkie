//
//  ProOnboardingManager.swift
//  Talkie macOS
//
//  Manages the Pro Tools onboarding flow — validates prerequisites,
//  installs dependencies, and activates Pro Tools features.
//

import Foundation
import SwiftUI
import Observation
import TalkieKit

enum ProOnboardingStep: Int, CaseIterable {
    case intro = 0
    case prerequisites = 1
    case complete = 2

    var label: String {
        switch self {
        case .intro: return "Overview"
        case .prerequisites: return "Tooling"
        case .complete: return "Ready"
        }
    }
}

enum PrerequisiteCheckStatus: Equatable {
    case pending
    case checking
    case passed
    case failed(String)
    case optional(String)

    var icon: String {
        switch self {
        case .pending: return "circle"
        case .checking: return "spinner"
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .optional: return "minus.circle"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .gray
        case .checking: return .blue
        case .passed: return .green
        case .failed: return .red
        case .optional: return .orange
        }
    }

    var isPassed: Bool {
        if case .passed = self { return true }
        return false
    }
}

enum PrerequisiteItem: String, CaseIterable {
    case bun = "Bun Runtime"
    case serverSource = "Local TalkieServer Source"
    case dependencies = "Local Server Dependencies"
    case tailscale = "Tailscale"

    var icon: String {
        switch self {
        case .bun: return "terminal"
        case .serverSource: return "doc.text"
        case .dependencies: return "shippingbox"
        case .tailscale: return "network"
        }
    }

    var description: String {
        switch self {
        case .bun: return "Runtime and package manager for local TalkieServer commands"
        case .serverSource: return "Repository checkout that contains src/server.ts and package.json"
        case .dependencies: return "Packages from TalkieServer plus linked local workspace modules"
        case .tailscale: return "Optional networking layer for remote bridge and device access"
        }
    }

    var badgeTitle: String {
        switch self {
        case .bun, .serverSource, .dependencies:
            return "LOCAL DEV"
        case .tailscale:
            return "OPTIONAL"
        }
    }
}

@MainActor
@Observable
final class ProOnboardingManager {
    static let shared = ProOnboardingManager()

    /// Global presentation flag for the Pro Tools onboarding sheet.
    /// Mutated by route handlers, CLI deep links, and in-app triggers; observed at the app root.
    var shouldShowProOnboarding: Bool = false

    var currentStep: ProOnboardingStep = .intro
    var prerequisiteStatuses: [PrerequisiteItem: PrerequisiteCheckStatus] = [:]
    var isValidating = false
    var isInstallingDependencies = false
    var errorMessage: String?

    var canGoBack: Bool {
        currentStep != .intro
    }

    var canActivateDeveloperMode: Bool {
        !isValidating
    }

    var localToolingReady: Bool {
        [.bun, .serverSource, .dependencies]
            .allSatisfy { prerequisiteStatuses[$0]?.isPassed == true }
    }

    var activationButtonTitle: String {
        localToolingReady ? "ENABLE" : "ENABLE NOW"
    }

    var toolingFootnote: String {
        if localToolingReady {
            return "Local TalkieServer tooling is ready if you want to work against this checkout."
        }

        return "Pro Tools still works now. Skipping these only affects repo-local TalkieServer work and remote networking extras."
    }

    init() {
        for item in PrerequisiteItem.allCases {
            prerequisiteStatuses[item] = .pending
        }
    }

    func validatePrerequisites() async {
        isValidating = true
        errorMessage = nil

        let status = await BridgeManager.shared.checkPrerequisites()

        // Bun
        if status.bunInstalled {
            prerequisiteStatuses[.bun] = .passed
        } else {
            prerequisiteStatuses[.bun] = .optional("Install Bun later if you want to run TalkieServer from the repo.")
        }

        // Server source
        if status.serverSourceExists {
            prerequisiteStatuses[.serverSource] = .passed
        } else {
            prerequisiteStatuses[.serverSource] = .optional("This build could not find a local apps/macos/TalkieServer checkout.")
        }

        // Dependencies
        if status.dependenciesInstalled {
            prerequisiteStatuses[.dependencies] = .passed
        } else if status.bunInstalled && status.serverSourceExists {
            prerequisiteStatuses[.dependencies] = .optional("Install packages when you need local TalkieServer scripts.")
        } else {
            prerequisiteStatuses[.dependencies] = .optional("Skipped until Bun and the local source checkout are available.")
        }

        // Tailscale
        if status.tailscaleInstalled {
            prerequisiteStatuses[.tailscale] = .passed
        } else {
            prerequisiteStatuses[.tailscale] = .optional("Only needed for remote networking and device access.")
        }

        isValidating = false
    }

    func installDependencies() async {
        isInstallingDependencies = true
        prerequisiteStatuses[.dependencies] = .checking

        let result = await BridgeManager.shared.installDependencies()

        switch result {
        case .success:
            prerequisiteStatuses[.dependencies] = .passed
        case .bunNotFound:
            prerequisiteStatuses[.dependencies] = .failed("Bun not found")
        case .sourceNotFound:
            prerequisiteStatuses[.dependencies] = .failed("Local TalkieServer source checkout not found")
        case .installFailed(let error):
            prerequisiteStatuses[.dependencies] = .failed(error)
        }

        isInstallingDependencies = false
    }

    func activate() {
        let settings = SettingsManager.shared
        settings.isProToolsActive = true
        settings.hasCompletedProOnboarding = true
    }

    func goBack() {
        guard let previous = ProOnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = previous
    }

    func reset() {
        currentStep = .intro
        for item in PrerequisiteItem.allCases {
            prerequisiteStatuses[item] = .pending
        }
        isValidating = false
        isInstallingDependencies = false
        errorMessage = nil
    }
}
