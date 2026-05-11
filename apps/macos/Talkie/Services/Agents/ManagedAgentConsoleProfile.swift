//
//  ManagedAgentConsoleProfile.swift
//  Talkie
//
//  Reusable console presets for the in-app agent playground.
//

import Foundation

struct ManagedAgentConsoleProfile: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let contextLabel: String
    let symbolName: String
    let summary: String
    let systemPrompt: String
    let prompt: String
    let notes: String
    let examples: String
    let bootstrapPrompt: String?
    let preferredModel: String?
    let autoSendPrompt: Bool
    let harness: AgentHarnessProfile

    static let talkieAgent = ManagedAgentConsoleProfile(
        id: "talkie-agent",
        title: "Talkie Agent",
        contextLabel: "Workspace",
        symbolName: "terminal",
        summary: "Use Talkie Agent to inspect and configure Talkie, work with file-backed settings, and create or run workflows from the mounted workspace.",
        systemPrompt: AgentConsoleAssetLoader.text(
            relativePath: "prompts/talkie-agent/system.md",
            fallback: "Read WORKFLOW_AUTHORING.md and WORKFLOW_CAPABILITIES.md before creating a workflow."
        ),
        prompt: AgentConsoleAssetLoader.text(
            relativePath: "prompts/talkie-agent/prompt.md",
            fallback: "Turn workflow requests into real workflow files in Live Config/workflow-user."
        ),
        notes: AgentConsoleAssetLoader.text(
            relativePath: "prompts/talkie-agent/notes.md",
            fallback: "Prefer the flat JSON format and adapt the closest workflow template."
        ),
        examples: AgentConsoleAssetLoader.text(
            relativePath: "prompts/talkie-agent/examples.md",
            fallback: "Read WORKFLOW_AUTHORING.md, adapt a template, and write Live Config/workflow-user/<slug>.json."
        ),
        bootstrapPrompt: AgentConsoleAssetLoader.optionalText(
            relativePath: "prompts/talkie-agent/bootstrap.md"
        ),
        preferredModel: AgentHarnessProfile.openCodeDefaultModel,
        autoSendPrompt: false,
        harness: .openCode
    )

    static let localShell = ManagedAgentConsoleProfile(
        id: "local-shell",
        title: "Local Shell",
        contextLabel: "Shell",
        symbolName: "chevron.left.forwardslash.chevron.right",
        summary: "Open a plain interactive zsh session in Talkie's console playground.",
        systemPrompt: "",
        prompt: "",
        notes: "",
        examples: "",
        bootstrapPrompt: nil,
        preferredModel: nil,
        autoSendPrompt: false,
        harness: .helloWorld
    )

    static let claudeAgent = ManagedAgentConsoleProfile(
        id: "claude-agent",
        title: "Claude Agent",
        contextLabel: "Workspace",
        symbolName: "sparkles",
        summary: "Claude-first Talkie agent console for inspecting Talkie config and creating or running workflows with the mounted workspace loaded.",
        systemPrompt: talkieAgent.systemPrompt,
        prompt: talkieAgent.prompt,
        notes: talkieAgent.notes,
        examples: talkieAgent.examples,
        bootstrapPrompt: talkieAgent.bootstrapPrompt,
        preferredModel: nil,
        autoSendPrompt: false,
        harness: .claude
    )

    static let all: [ManagedAgentConsoleProfile] = [
        talkieAgent,
        claudeAgent,
        localShell,
    ]

    static func defaultProfile() -> ManagedAgentConsoleProfile {
        talkieAgent
    }

    static func fallbackProfile() -> ManagedAgentConsoleProfile {
        localShell
    }
}

private enum AgentConsoleAssetLoader {
    static func text(relativePath: String, fallback: String) -> String {
        optionalText(relativePath: relativePath) ?? fallback
    }

    static func optionalText(relativePath: String) -> String? {
        guard let url = resourceURL(relativePath: relativePath),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func resourceURL(relativePath: String) -> URL? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }

        let directURL = URL(fileURLWithPath: resourcePath)
            .appending(path: "AgentKit", directoryHint: .isDirectory)
            .appending(path: relativePath)
        if FileManager.default.fileExists(atPath: directURL.path) {
            return directURL
        }

        let nestedURL = URL(fileURLWithPath: resourcePath)
            .appending(path: "Resources", directoryHint: .isDirectory)
            .appending(path: "AgentKit", directoryHint: .isDirectory)
            .appending(path: relativePath)
        if FileManager.default.fileExists(atPath: nestedURL.path) {
            return nestedURL
        }

        return nil
    }
}
