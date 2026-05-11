//
//  ManagedAgentConsoleStore.swift
//  Talkie
//
//  Shared console context state so any screen can open the console with
//  the right prompt, notes, and harness configuration.
//

import Foundation
import Observation

@MainActor
@Observable
final class ManagedAgentConsoleStore {
    static let shared = ManagedAgentConsoleStore()

    var activeProfile: ManagedAgentConsoleProfile
    var systemPrompt: String
    var prompt: String
    var notes: String
    var examples: String
    var launchRequestID = UUID()
    var handledLaunchRequestID: UUID?
    var currentSession: ManagedAgentConsoleSession?
    var launchError: String?

    init(initialProfile: ManagedAgentConsoleProfile = .defaultProfile()) {
        self.activeProfile = initialProfile
        self.systemPrompt = initialProfile.systemPrompt
        self.prompt = initialProfile.prompt
        self.notes = initialProfile.notes
        self.examples = initialProfile.examples
    }

    var fallbackProfile: ManagedAgentConsoleProfile {
        ManagedAgentConsoleProfile.fallbackProfile()
    }

    var launchProfile: ManagedAgentConsoleProfile {
        activeProfile
    }

    func setActiveProfile(
        _ profile: ManagedAgentConsoleProfile,
        resetDrafts: Bool = false
    ) {
        activeProfile = profile

        if resetDrafts {
            applyDefaults(from: profile)
        }
    }

    func open(
        profile: ManagedAgentConsoleProfile = .defaultProfile(),
        systemPrompt: String? = nil,
        prompt: String? = nil,
        notes: String? = nil,
        examples: String? = nil,
        navigate: Bool = true
    ) {
        activeProfile = profile
        self.systemPrompt = resolveOverride(systemPrompt, fallback: profile.systemPrompt)
        self.prompt = resolveOverride(prompt, fallback: profile.prompt)
        self.notes = resolveOverride(notes, fallback: profile.notes)
        self.examples = resolveOverride(examples, fallback: profile.examples)
        launchRequestID = UUID()

        if navigate {
            NavigationState.shared.navigate(to: .systemConsole)
        }
    }

    func needsLaunch(for requestID: UUID) -> Bool {
        handledLaunchRequestID != requestID
    }

    func recordLaunchedSession(
        _ session: ManagedAgentConsoleSession,
        for requestID: UUID
    ) {
        currentSession = session
        launchError = nil
        handledLaunchRequestID = requestID
    }

    func recordLaunchFailure(
        _ message: String,
        for requestID: UUID
    ) {
        currentSession = nil
        launchError = message
        handledLaunchRequestID = requestID
    }

    func closeCurrentSession() {
        let session = currentSession
        currentSession = nil
        launchError = nil
        handledLaunchRequestID = launchRequestID
        session?.stop()
    }

    func resolvedSystemPrompt(for profile: ManagedAgentConsoleProfile? = nil) -> String {
        resolvedText(systemPrompt, fallback: (profile ?? activeProfile).systemPrompt)
    }

    func resolvedPrompt(for profile: ManagedAgentConsoleProfile? = nil) -> String {
        resolvedText(prompt, fallback: (profile ?? activeProfile).prompt)
    }

    func resolvedNotes(for profile: ManagedAgentConsoleProfile? = nil) -> String {
        resolvedText(notes, fallback: (profile ?? activeProfile).notes)
    }

    func resolvedExamples(for profile: ManagedAgentConsoleProfile? = nil) -> String {
        resolvedText(examples, fallback: (profile ?? activeProfile).examples)
    }

    private func applyDefaults(from profile: ManagedAgentConsoleProfile) {
        systemPrompt = profile.systemPrompt
        prompt = profile.prompt
        notes = profile.notes
        examples = profile.examples
    }

    private func resolveOverride(_ override: String?, fallback: String) -> String {
        guard let override else { return fallback }
        return resolvedText(override, fallback: fallback)
    }

    private func resolvedText(_ candidate: String, fallback: String) -> String {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
