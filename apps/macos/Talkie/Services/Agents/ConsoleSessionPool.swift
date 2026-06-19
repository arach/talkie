//
//  ConsoleSessionPool.swift
//  Talkie
//
//  Manages N concurrent console sessions keyed by tab ID.
//  Sessions are created lazily on first activation and kept alive across tab switches.
//

import Foundation
import Observation
import TalkieKit

private let log = Log(.ui)

@MainActor
@Observable
final class ConsoleSessionPool {
    static let shared = ConsoleSessionPool()

    struct TabSessionState {
        var session: ManagedAgentConsoleSession?
        var launchError: String?
        var isStale: Bool = false
        var lastDefinition: TabDefinition?
    }

    private(set) var sessions: [String: TabSessionState] = [:]

    private let workspaceStore = ManagedAgentWorkspaceStore(
        rootDirectoryURL: URL.applicationSupportDirectory
            .appending(path: "Talkie/Agent Sessions", directoryHint: .isDirectory)
    )

    private init() {}

    /// Durable home the interactive Claude agent boots into
    /// (`Application Support/Talkie/Agent`). Shared across all Claude tabs.
    var agentHomeURL: URL {
        workspaceStore.agentHomeURL()
    }

    /// Restore the durable agent home's `CLAUDE.md` / `SYSTEM_PROMPT.md` to the
    /// bundled factory defaults, discarding local edits. Takes effect the next
    /// time the Claude tab is (re)launched.
    func resetAgentHomePrompts() {
        do {
            try workspaceStore.resetAgentHomePrompts(
                harness: .claude,
                systemPrompt: TabPresets.claude.systemPrompt
            )
            log.info("Reset agent home prompts to defaults")
        } catch {
            log.error("Failed to reset agent home prompts", error: error)
        }
    }

    func state(for tabId: String) -> TabSessionState {
        sessions[tabId] ?? TabSessionState()
    }

    func session(for tabId: String) -> ManagedAgentConsoleSession? {
        sessions[tabId]?.session
    }

    func isStale(_ tabId: String) -> Bool {
        sessions[tabId]?.isStale ?? false
    }

    func launchError(for tabId: String) -> String? {
        sessions[tabId]?.launchError
    }

    func hasSession(_ tabId: String) -> Bool {
        sessions[tabId]?.session != nil
    }

    func launch(tab: TabDefinition, registry: TabDefinitionRegistry) {
        let tabId = tab.id
        let existingSession = sessions[tabId]?.session
        existingSession?.stop()

        sessions[tabId] = TabSessionState(
            session: nil,
            launchError: nil,
            isStale: false,
            lastDefinition: tab
        )

        let profile = TabLaunchSpec.bridgeToProfile(tab)
        let envResult = registry.resolveEnv(for: tab)

        if !envResult.errors.isEmpty {
            let errorMsg = "Env needs attention: " + envResult.errors.joined(separator: ", ")
            sessions[tabId]?.launchError = errorMsg
            log.warning("Tab env resolution failed", detail: "\(tabId): \(errorMsg)")
            return
        }

        do {
            let workspace: ManagedAgentWorkspace
            if tab.harness == .claudeCode {
                // Interactive Claude console boots into one durable, user-owned
                // agent home (Application Support/Talkie/Agent) instead of a
                // per-session workspace, so the CLAUDE.md / SYSTEM_PROMPT.md it
                // instantiates with persist across launches and can be hand-tuned.
                workspace = try workspaceStore.prepareAgentHome(
                    harness: profile.harness,
                    systemPrompt: tab.systemPrompt,
                    preferredModel: tab.model
                )
            } else {
                workspace = try workspaceStore.prepareConsoleWorkspace(
                    profileID: tab.id,
                    harness: profile.harness,
                    prompt: tab.harness == .shell ? "" : profile.prompt,
                    notes: "",
                    systemPrompt: tab.harness == .shell ? "" : tab.systemPrompt,
                    examples: "",
                    preferredModel: tab.model
                )
            }

            let useTmux = tab.useTmux && AgentHarnessProfile.consoleTmuxAvailable

            let launchSpec = try TabLaunchSpec.makeLaunchSpec(
                for: tab,
                resolvedEnv: envResult.resolved,
                workspaceURL: workspace.rootURL,
                preferTmux: useTmux
            )

            let newSession = ManagedAgentConsoleSession(
                profile: profile,
                workspace: workspace,
                prompt: "",
                notes: "",
                prefersConsoleTmux: useTmux
            )

            sessions[tabId] = TabSessionState(
                session: newSession,
                launchError: nil,
                isStale: false,
                lastDefinition: tab
            )

            newSession.startWithLaunchSpec(
                launchSpec,
                reason: "Launched \(tab.label) tab (\(tab.harness.displayName))"
            )
            log.info("Launched tab session", detail: tabId)
        } catch {
            sessions[tabId]?.launchError = error.localizedDescription
            log.error("Failed to launch tab session", error: error)
        }
    }

    func restart(tab: TabDefinition, registry: TabDefinitionRegistry) {
        close(tabId: tab.id)
        launch(tab: tab, registry: registry)
    }

    func close(tabId: String) {
        let session = sessions[tabId]?.session
        session?.stop()
        sessions[tabId] = nil
    }

    func closeAll() {
        for (tabId, state) in sessions {
            state.session?.stop()
            sessions[tabId] = nil
        }
    }

    func detachAll() {
        for (tabId, state) in sessions {
            state.session?.handleConsoleClosed()
            sessions[tabId] = nil
        }
    }

    func markStaleIfStructuralChange(tabId: String, newDefinition: TabDefinition) {
        guard let state = sessions[tabId],
              let lastDef = state.lastDefinition,
              state.session != nil else { return }

        if !lastDef.structurallyEquals(newDefinition) {
            sessions[tabId]?.isStale = true
            log.info("Marked tab session as stale", detail: tabId)
        }
    }

    func applyCosmetic(tabId: String, definition: TabDefinition) {
        sessions[tabId]?.lastDefinition = definition
    }

    func checkForStaleDefinitions(registry: TabDefinitionRegistry) {
        for tab in registry.tabs {
            if let state = sessions[tab.id], state.session != nil {
                markStaleIfStructuralChange(tabId: tab.id, newDefinition: tab)
            }
        }

        for (tabId, _) in sessions {
            if registry.tab(for: tabId) == nil {
                close(tabId: tabId)
            }
        }
    }
}
