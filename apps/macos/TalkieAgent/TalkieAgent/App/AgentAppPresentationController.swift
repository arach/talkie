//
//  AgentAppPresentationController.swift
//  TalkieAgent
//

import AppKit

@MainActor
final class AgentAppPresentationController {
    static let shared = AgentAppPresentationController()

    private var regularPresentationClaims: Set<String> = []

    private init() {}

    func retainRegularPresentation(for claim: String) {
        regularPresentationClaims.insert(claim)
        NSApp.setActivationPolicy(.regular)
    }

    func releaseRegularPresentation(for claim: String) {
        regularPresentationClaims.remove(claim)

        if regularPresentationClaims.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
