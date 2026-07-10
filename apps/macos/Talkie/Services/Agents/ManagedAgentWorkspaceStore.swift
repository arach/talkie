//
//  ManagedAgentWorkspaceStore.swift
//  Talkie
//
//  Creates file-backed starter workspaces for managed agent sessions.
//

import Foundation
import TalkieKit

struct ManagedAgentWorkspace: Identifiable, Sendable {
    let id: String
    let rootURL: URL
    let createdAt: Date
    let profile: AgentHarnessProfile
    let contextFileURL: URL
    let agentsFileURL: URL
}

struct ManagedAgentWorkspaceStore: Sendable {
    let rootDirectoryURL: URL
    let rulePackStore: TalkieRulePackFileStore

    init(
        rootDirectoryURL: URL = URL.documentsDirectory.appending(path: "Talkie/Agent Sessions", directoryHint: .isDirectory),
        rulePackStore: TalkieRulePackFileStore = .init()
    ) {
        self.rootDirectoryURL = rootDirectoryURL
        self.rulePackStore = rulePackStore
    }

    func prepareWorkspace(
        profile: AgentHarnessProfile,
        prompt: String,
        notes: String
    ) throws -> ManagedAgentWorkspace {
        try prepareWorkspace(
            profile: profile,
            prompt: prompt,
            notes: notes,
            systemPrompt: "",
            examples: "",
            preferredModel: nil
        )
    }

    func prepareWorkspace(
        profile: AgentHarnessProfile,
        prompt: String,
        notes: String,
        systemPrompt: String,
        examples: String,
        preferredModel: String?
    ) throws -> ManagedAgentWorkspace {
        let createdAt = Date()
        let directoryName = makeDirectoryName(createdAt: createdAt, profile: profile)
        let workspaceURL = rootDirectoryURL.appending(path: directoryName, directoryHint: .isDirectory)
        return try prepareWorkspace(
            id: directoryName,
            workspaceURL: workspaceURL,
            createdAt: createdAt,
            profile: profile,
            prompt: prompt,
            notes: notes,
            systemPrompt: systemPrompt,
            examples: examples,
            preferredModel: preferredModel
        )
    }

    func prepareConsoleWorkspace(
        profileID: String,
        harness: AgentHarnessProfile,
        prompt: String,
        notes: String,
        systemPrompt: String,
        examples: String,
        preferredModel: String?
    ) throws -> ManagedAgentWorkspace {
        let createdAt = Date()
        let workspaceURL = consoleWorkspaceURL(for: profileID)
        return try prepareWorkspace(
            id: profileID,
            workspaceURL: workspaceURL,
            createdAt: createdAt,
            profile: harness,
            prompt: prompt,
            notes: notes,
            systemPrompt: systemPrompt,
            examples: examples,
            preferredModel: preferredModel
        )
    }

    func consoleWorkspaceURL(for profileID: String) -> URL {
        rootDirectoryURL.appending(path: profileID, directoryHint: .isDirectory)
    }

    /// Stable, shared home for the interactive Talkie agent console
    /// (`Application Support/Talkie/Agent`). Unlike the per-session console
    /// workspaces, this directory persists across launches, so the user-owned
    /// `CLAUDE.md` / `SYSTEM_PROMPT.md` the agent boots with survive hand edits.
    func agentHomeURL() -> URL {
        rootDirectoryURL
            .deletingLastPathComponent()
            .appending(path: "Agent", directoryHint: .isDirectory)
    }

    /// Prepare (or refresh) the durable agent home. The prompt files are seeded
    /// once and then left alone; the operational scaffolding (guides,
    /// `Live Config/`, optional utilities, rule packs) is rewritten each call so
    /// it tracks the app.
    @discardableResult
    func prepareAgentHome(
        harness: AgentHarnessProfile,
        systemPrompt: String,
        preferredModel: String?
    ) throws -> ManagedAgentWorkspace {
        try prepareWorkspace(
            id: "agent-home",
            workspaceURL: agentHomeURL(),
            createdAt: Date(),
            profile: harness,
            prompt: "",
            notes: "",
            systemPrompt: systemPrompt,
            examples: "",
            preferredModel: preferredModel,
            seedPromptsOnly: true
        )
    }

    /// Restore the user-owned prompt files in the durable agent home to their
    /// bundled defaults, overwriting any local edits.
    func resetAgentHomePrompts(harness: AgentHarnessProfile, systemPrompt: String) throws {
        let homeURL = agentHomeURL()
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        try writeText(claudeMemoryMarkdown(profile: harness), to: homeURL.appending(path: "CLAUDE.md"))
        try writeText(systemPromptMarkdown(systemPrompt), to: homeURL.appending(path: "SYSTEM_PROMPT.md"))
    }

    private func prepareWorkspace(
        id: String,
        workspaceURL: URL,
        createdAt: Date,
        profile: AgentHarnessProfile,
        prompt: String,
        notes: String,
        systemPrompt: String,
        examples: String,
        preferredModel: String?,
        seedPromptsOnly: Bool = false
    ) throws -> ManagedAgentWorkspace {
        let fileManager = FileManager.default

        try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let rulePackDirectoryURL = workspaceURL.appending(path: "Rule Packs", directoryHint: .isDirectory)
        let liveConfigDirectoryURL = workspaceURL.appending(path: "Live Config", directoryHint: .isDirectory)
        let toolsDirectoryURL = workspaceURL.appending(path: "Tools", directoryHint: .isDirectory)
        let workflowTemplatesDirectoryURL = workspaceURL.appending(path: "Workflow Templates", directoryHint: .isDirectory)

        try resetDirectory(at: rulePackDirectoryURL)
        try resetDirectory(at: liveConfigDirectoryURL)
        try resetDirectory(at: toolsDirectoryURL)
        try resetDirectory(at: workflowTemplatesDirectoryURL)

        let contextFileURL = workspaceURL.appending(path: "CONTEXT.md")
        let agentsFileURL = workspaceURL.appending(path: "AGENTS.md")
        let claudeMemoryFileURL = workspaceURL.appending(path: "CLAUDE.md")
        let systemPromptFileURL = workspaceURL.appending(path: "SYSTEM_PROMPT.md")
        let promptFileURL = workspaceURL.appending(path: "PROMPT.md")
        let examplesFileURL = workspaceURL.appending(path: "EXAMPLES.md")
        let configurationGuideFileURL = workspaceURL.appending(path: "CONFIGURATION_GUIDE.md")
        let memoGuideFileURL = workspaceURL.appending(path: "MEMO_GUIDE.md")
        let workflowGuideFileURL = workspaceURL.appending(path: "WORKFLOW_GUIDE.md")
        let cliGuideFileURL = workspaceURL.appending(path: "CLI_GUIDE.md")
        let workflowAuthoringGuideFileURL = workspaceURL.appending(path: "WORKFLOW_AUTHORING.md")
        let workflowCapabilitiesGuideFileURL = workspaceURL.appending(path: "WORKFLOW_CAPABILITIES.md")
        let workflowStepCatalogFileURL = workspaceURL.appending(path: "WORKFLOW_STEP_CATALOG.json")
        let openCodeConfigFileURL = workspaceURL.appending(path: "opencode.json")
        let readmeFileURL = workspaceURL.appending(path: "README.md")
        let liveConfigReadmeURL = liveConfigDirectoryURL.appending(path: "README.md")
        let toolsReadmeURL = toolsDirectoryURL.appending(path: "README.md")
        let workflowTemplatesReadmeURL = workflowTemplatesDirectoryURL.appending(path: "README.md")

        try writeText(contextMarkdown(notes: notes), to: contextFileURL)
        try writeText(agentsMarkdown(profile: profile), to: agentsFileURL)
        // CLAUDE.md and SYSTEM_PROMPT.md are the user-owned prompt surface. In a
        // durable agent home (`seedPromptsOnly`) we write them only when absent so
        // hand edits survive; everything else here is refreshed each launch.
        if seedPromptsOnly {
            try writeTextIfAbsent(claudeMemoryMarkdown(profile: profile), to: claudeMemoryFileURL)
            try writeTextIfAbsent(systemPromptMarkdown(systemPrompt), to: systemPromptFileURL)
        } else {
            try writeText(claudeMemoryMarkdown(profile: profile), to: claudeMemoryFileURL)
            try writeText(systemPromptMarkdown(systemPrompt), to: systemPromptFileURL)
        }
        try writeText(prompt.trimmingCharacters(in: .whitespacesAndNewlines) + "\n", to: promptFileURL)
        try writeText(examplesMarkdown(examples), to: examplesFileURL)
        try writeText(configurationGuideMarkdown(), to: configurationGuideFileURL)
        try writeText(memoGuideMarkdown(), to: memoGuideFileURL)
        try writeText(workflowGuideMarkdown(), to: workflowGuideFileURL)
        try writeText(cliGuideMarkdown(), to: cliGuideFileURL)
        try writeText(workflowAuthoringMarkdown(), to: workflowAuthoringGuideFileURL)
        try writeText(workflowCapabilitiesMarkdown(), to: workflowCapabilitiesGuideFileURL)
        try workflowStepCatalogData().write(to: workflowStepCatalogFileURL, options: .atomic)
        try writeText(
            openCodeConfigJSON(preferredModel: preferredModel),
            to: openCodeConfigFileURL
        )
        try writeText(readmeMarkdown(profile: profile, createdAt: createdAt, prompt: prompt), to: readmeFileURL)
        try writeText(liveConfigReadmeMarkdown(), to: liveConfigReadmeURL)
        try writeText(toolsReadmeMarkdown(), to: toolsReadmeURL)
        try writeText(workflowTemplatesReadmeMarkdown(), to: workflowTemplatesReadmeURL)

        try copyRulePacks(into: rulePackDirectoryURL)
        try mountLiveConfig(into: liveConfigDirectoryURL)
        try writeTools(into: toolsDirectoryURL)
        try copyWorkflowTemplates(into: workflowTemplatesDirectoryURL)

        return ManagedAgentWorkspace(
            id: id,
            rootURL: workspaceURL,
            createdAt: createdAt,
            profile: profile,
            contextFileURL: contextFileURL,
            agentsFileURL: agentsFileURL
        )
    }

    func prepareTerminalWorkspace() throws -> ManagedAgentWorkspace {
        try prepareConsoleWorkspace(
            profileID: "local-shell",
            harness: .helloWorld,
            prompt: "",
            notes: "",
            systemPrompt: "",
            examples: "",
            preferredModel: nil
        )
    }

    private func copyRulePacks(into directoryURL: URL) throws {
        let documents = rulePackStore.loadDocuments()

        for document in documents {
            let destinationURL = directoryURL.appending(path: document.url.lastPathComponent)
            try writeText(document.source, to: destinationURL)
        }
    }

    private func mountLiveConfig(into directoryURL: URL) throws {
        let workflowDefinitionsDirectoryURL = workflowDefinitionsBaseURL
        try FileManager.default.createDirectory(
            at: workflowDefinitionsDirectoryURL.appending(path: "system", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: workflowDefinitionsDirectoryURL.appending(path: "user", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: workflowDefinitionsDirectoryURL.appending(path: "imported", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        try createSymbolicLink(
            at: directoryURL.appending(path: "macos-settings.config.json"),
            pointingTo: macOSSettingsConfigURL
        )
        try createSymbolicLink(
            at: directoryURL.appending(path: "macos-workflows.config.json"),
            pointingTo: macOSWorkflowConfigURL
        )
        try createSymbolicLink(
            at: directoryURL.appending(path: "macos-context-rules.json"),
            pointingTo: macOSContextRulesURL
        )
        try createSymbolicLink(
            at: directoryURL.appending(path: "workflow-system", directoryHint: .isDirectory),
            pointingTo: workflowDefinitionsDirectoryURL.appending(path: "system", directoryHint: .isDirectory)
        )
        try createSymbolicLink(
            at: directoryURL.appending(path: "workflow-user", directoryHint: .isDirectory),
            pointingTo: workflowDefinitionsDirectoryURL.appending(path: "user", directoryHint: .isDirectory)
        )
        try createSymbolicLink(
            at: directoryURL.appending(path: "workflow-imported", directoryHint: .isDirectory),
            pointingTo: workflowDefinitionsDirectoryURL.appending(path: "imported", directoryHint: .isDirectory)
        )
    }

    private func writeTools(into directoryURL: URL) throws {
        let commonURL = directoryURL.appending(path: "_common.sh")
        let captureMarkupDescribeURL = directoryURL.appending(path: "capture-markup-describe.sh")
        let captureMarkupPlanURL = directoryURL.appending(path: "capture-markup-plan.sh")
        let captureMarkupApplyURL = directoryURL.appending(path: "capture-markup-apply.sh")
        let captureMarkupRenderURL = directoryURL.appending(path: "capture-markup-render.sh")

        try writeExecutableText(commonScript(), to: commonURL)
        try writeExecutableText(captureMarkupDescribeScript(), to: captureMarkupDescribeURL)
        try writeExecutableText(captureMarkupPlanScript(), to: captureMarkupPlanURL)
        try writeExecutableText(captureMarkupApplyScript(), to: captureMarkupApplyURL)
        try writeExecutableText(captureMarkupRenderScript(), to: captureMarkupRenderURL)
    }

    private func resetDirectory(at directoryURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let childURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )

        for childURL in childURLs {
            try fileManager.removeItem(at: childURL)
        }
    }

    private func createSymbolicLink(at linkURL: URL, pointingTo targetURL: URL) throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: linkURL)
        try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)
    }

    private func makeDirectoryName(createdAt: Date, profile: AgentHarnessProfile) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(formatter.string(from: createdAt))-\(profile.rawValue)"
    }

    private func writeText(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeTextIfAbsent(_ text: String, to url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try writeText(text, to: url)
    }

    private func writeExecutableText(_ text: String, to url: URL) throws {
        try writeText(text, to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: url.path
        )
    }

    private func agentsMarkdown(profile: AgentHarnessProfile) -> String {
        if let markdown = renderedAgentKitMarkdown(
            relativePath: "docs/agents.md",
            replacements: [
                "{{HARNESS_DISPLAY_NAME}}": profile.displayName,
            ]
        ) {
            return markdown
        }

        return """
        # AGENTS.md

        This workspace was generated by Talkie for a managed agent session.

        Your job:
        - work from the files in this directory first
        - inspect `Rule Packs/*.trf.toml` before changing command interpretation behavior
        - if the task touches settings, quick actions, workflow pinning, SSH, or iPhone preferences, read `CONFIGURATION_GUIDE.md`
        - if the task touches memos, transcripts, recordings, dictations, workflow runs, captures, or pinned actions, read `MEMO_GUIDE.md`, `WORKFLOW_GUIDE.md`, and `CLI_GUIDE.md`
        - use supported `talkie` CLI commands or Talkie bridge/API surfaces for app-data inspection
        - if the CLI/API lacks the needed view or recovery action, explain the gap or implement the missing supported surface instead of querying the database directly
        - if the task is to create or edit a workflow, read `WORKFLOW_AUTHORING.md`, inspect `Workflow Templates/`, read `WORKFLOW_CAPABILITIES.md`, and write the result into `Live Config/workflow-user/`
        - treat `Live Config/` as the canonical mounted file-backed surface when links are present
        - never edit `talkie.sqlite` directly unless the task is explicitly a database repair or migration
        - never use `sqlite3`, `bun:sqlite`, raw SQL, or generated shell database helpers for normal app-data inspection
        - explain what you inspected, what matched, what failed, and the smallest useful fix

        Harness:
        - \(profile.displayName)

        Important files:
        - `SYSTEM_PROMPT.md`: the governing instruction for this run
        - `PROMPT.md`: the current user request
        - `CONTEXT.md`: extra notes from Talkie
        - `EXAMPLES.md`: examples and few-shot guidance for the run
        - `CONFIGURATION_GUIDE.md`: map of Talkie's file-backed config surfaces and update rules
        - `MEMO_GUIDE.md`: map of memo storage, repositories, and safe inspection rules
        - `WORKFLOW_GUIDE.md`: map of workflow definitions, preferences, and run history
        - `CLI_GUIDE.md`: supported CLI commands for memos, dictations, captures, workflows, and search
        - `WORKFLOW_AUTHORING.md`: the flat JSON workflow format and authoring quick-start
        - `WORKFLOW_CAPABILITIES.md`: the supported step vocabulary and common patterns
        - `WORKFLOW_STEP_CATALOG.json`: machine-readable workflow step catalog
        - `Live Config/`: mounted config files and workflow directories when available
        - `Workflow Templates/`: working starter examples to copy or adapt
        - `Tools/`: optional non-database utilities, when present
        - `Rule Packs/`: copied user-authored rule packs
        """
    }

    /// Native Claude Code context file (`CLAUDE.md`) for the workspace. Claude
    /// auto-loads this from the working directory, so it doubles as the agent's
    /// orientation map — it points at the curated files Talkie mounts here and
    /// is portable to any user, since everything lives under Application Support
    /// rather than a source checkout.
    private func claudeMemoryMarkdown(profile: AgentHarnessProfile) -> String {
        return """
        # Talkie Agent — Session Workspace

        You are the **Talkie agent**, running inside the Talkie macOS app's console
        on a prepared session workspace (this directory, under Application Support).
        Everything you need for this run is mounted here — work from these files
        first, not from a source checkout.

        ## Read first
        1. `SYSTEM_PROMPT.md` — the governing instruction for this run. It wins on conflicts.
        2. `AGENTS.md` — your job description and a map of every file in this workspace.
        3. `PROMPT.md` and `CONTEXT.md` — the current request and any extra notes from Talkie.

        ## Then, by task
        - Settings, quick actions, workflow pinning, SSH, or iPhone prefs → `CONFIGURATION_GUIDE.md`
        - Memos, recordings, dictations, transcripts, captures, or workflow runs → `MEMO_GUIDE.md`, `WORKFLOW_GUIDE.md`, `CLI_GUIDE.md`
        - Creating or editing a workflow → `WORKFLOW_AUTHORING.md`, `Workflow Templates/`,
          `WORKFLOW_CAPABILITIES.md`; write the result into `Live Config/workflow-user/`

        ## Ground rules
        - `Live Config/` is the canonical, file-backed source of truth — edit it, not the mirrors.
        - Prefer supported `talkie` CLI commands or Talkie bridge/API surfaces for inspecting real app data.
        - Never edit `talkie.sqlite` directly unless the task is explicitly a repair or migration.
        - Never use `sqlite3`, `bun:sqlite`, raw SQL, or generated shell database helpers for normal app-data inspection.
        - Keep edits minimal and testable; explain what matched, what failed, and the smallest fix.

        Harness: \(profile.displayName)
        """
    }

    private func systemPromptMarkdown(_ systemPrompt: String) -> String {
        let trimmed = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return """
            # System Prompt

            No explicit system prompt was provided for this run.
            """
        }

        return """
        # System Prompt

        \(trimmed)
        """
    }

    private func contextMarkdown(notes: String) -> String {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return """
            # Context

            No extra context was provided for this run yet.
            """
        }

        return """
        # Context

        \(trimmed)
        """
    }

    private func examplesMarkdown(_ examples: String) -> String {
        let trimmed = examples.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return """
            # Examples

            No examples were provided for this run yet.
            """
        }

        return """
        # Examples

        \(trimmed)
        """
    }

    private func readmeMarkdown(profile: AgentHarnessProfile, createdAt: Date, prompt: String) -> String {
        if let markdown = renderedAgentKitMarkdown(
            relativePath: "docs/workspace-readme.md",
            replacements: [
                "{{CREATED_AT}}": createdAt.formatted(date: .abbreviated, time: .standard),
                "{{HARNESS_DISPLAY_NAME}}": profile.displayName,
                "{{PROMPT}}": prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            ]
        ) {
            return markdown
        }

        return """
        # Talkie Agent Session

        Created: \(createdAt.formatted(date: .abbreviated, time: .standard))
        Harness: \(profile.displayName)

        ## Prompt

        \(prompt.trimmingCharacters(in: .whitespacesAndNewlines))

        ## Notes

        This workspace is intentionally small but operational. It includes prompt files, copied rule packs, mounted file-backed config, memo/workflow guides, CLI guidance, and workflow-authoring examples.
        """
    }

    private func configurationGuideMarkdown() -> String {
        return """
        # Configuration Guide

        Use this file as a map. The real source of truth is the code and the live configuration files.

        ## Mounted live config

        The workspace mounts the main macOS file-backed surfaces under `Live Config/`:

        - `Live Config/macos-settings.config.json` -> `\(displayPath(macOSSettingsConfigURL))`
        - `Live Config/macos-workflows.config.json` -> `\(displayPath(macOSWorkflowConfigURL))`
        - `Live Config/macos-context-rules.json` -> `\(displayPath(macOSContextRulesURL))`
        - `Live Config/workflow-system` -> `\(displayPath(workflowDefinitionsBaseURL.appending(path: "system", directoryHint: .isDirectory)))`
        - `Live Config/workflow-user` -> `\(displayPath(workflowDefinitionsBaseURL.appending(path: "user", directoryHint: .isDirectory)))`
        - `Live Config/workflow-imported` -> `\(displayPath(workflowDefinitionsBaseURL.appending(path: "imported", directoryHint: .isDirectory)))`

        ## Canonical config files

        - macOS settings: `\(displayPath(macOSSettingsConfigURL))`
        - macOS workflow preferences/runtime: `\(displayPath(macOSWorkflowConfigURL))`
        - macOS context rules: `\(displayPath(macOSContextRulesURL))`
        - workflow definitions: `\(displayPath(workflowDefinitionsBaseURL))/{system,user,imported}`
        - iPhone app-group settings: `App Group/Library/Application Support/Talkie/settings/config.json`

        ## Owning code

        - macOS settings: `apps/macos/Talkie/Services/TalkieSettingsConfiguration.swift` + `apps/macos/Talkie/Services/TalkieSettingsConfigurationStore.swift`
        - macOS workflow preferences/runtime: `apps/macos/Talkie/Workflow/WorkflowConfiguration.swift` + `apps/macos/Talkie/Workflow/WorkflowConfigurationStore.swift`
        - workflow definition files: `apps/macos/Talkie/Workflow/WorkflowFileRepository.swift`
        - context rules: `ContextRuleStore` in `apps/macos/TalkieKit/Sources/TalkieKit/ContextRule.swift`
        - iPhone settings: `apps/ios/Talkie iOS/Services/TalkieAppConfiguration.swift` + `apps/ios/Talkie iOS/Services/TalkieAppConfigurationStore.swift`

        ## Important rules

        - Edit the file-backed source of truth, not the compatibility mirrors.
        - `UserDefaults`, shared defaults, GRDB workflow preference rows, iCloud `pinnedWorkflows`, and notch live-suite defaults are mirrors or transports.
        - Pinned workflows are authored in `macos-workflows.config.json` and the workflow definition directories. The iPhone keeps a cached file-backed copy, and iCloud is only the transport path.
        - If you change a config surface, also update `docs/specs/file-based-settings-inventory.md` and `docs/specs/agent-manageable-configuration.md`.
        """
    }

    private func memoGuideMarkdown() -> String {
        return """
        # Memo Guide

        Use this file as a map for memo and recording work. Memo data is operational app data, not declarative config.

        ## Live data surfaces

        - memo database: `\(displayPath(memoDatabaseURL))`
        - audio files: `\(displayPath(audioDirectoryURL))`
        - attachments: `\(displayPath(AttachmentStorage.attachmentsDirectory))`
        - workflow run history: `workflow_runs` table in `\(displayPath(memoDatabaseURL))`
        - memo source of truth: `voice_memos` rows in `\(displayPath(memoDatabaseURL))`
        - recording compatibility mirror: `recordings` rows in `\(displayPath(memoDatabaseURL))`

        ## Owning code

        - database path and migration: `apps/macos/TalkieKit/Sources/TalkieKit/DatabasePaths.swift`
        - schema and migrations: `apps/macos/Talkie/Data/Database/DatabaseManager.swift`
        - memo repository contract: `apps/macos/Talkie/Data/Database/MemoRepository.swift`
        - memo repository implementation: `apps/macos/Talkie/Data/Database/LocalRepository.swift`
        - memo app model: `apps/macos/Talkie/Data/Models/MemoModel.swift`
        - canonical shared memo schema: `apps/macos/TalkieKit/Sources/TalkieKit/Models/MemoRecord.swift`
        - memo view/query layer: `apps/macos/Talkie/Data/ViewModels/MemosViewModel.swift`
        - workflow runs on memos: `apps/macos/Talkie/Data/Models/WorkflowRunModel.swift`
        - iPhone memo surface: `apps/ios/Talkie iOS/Views/VoiceMemoDetailView.swift` + `apps/ios/Talkie iOS/Models/VoiceMemo+Transcripts.swift`

        ## Safe interaction rules

        - Prefer supported `talkie` CLI commands or Talkie bridge/API surfaces for app-data inspection.
        - Do not edit `talkie.sqlite` directly unless the task is explicitly a repair, migration, or forensic fix.
        - Do not use `sqlite3`, `bun:sqlite`, raw SQL, or generated shell database helpers for normal app-data inspection.
        - Treat `voice_memos` as the source of truth for memo transcript recovery; `recordings` is only a mirror for unified browsing.
        - If the task is about workflow pinning or action surfaces, update the file-backed workflow config instead of mutating memo rows.
        - If the task is about transcript display, summary, tasks, or reminders, inspect supported CLI/API output plus transcript/workflow owning code before proposing a fix.

        ## Memo and dictation inspection workflow

        1. Read `CLI_GUIDE.md`.
        2. Use `talkie memos`, `talkie dictations`, or `talkie search` to inspect user-facing data.
        3. Use `talkie workflows` when workflow history is relevant.
        4. Confirm what the supported output shows before inspecting owning code.
        5. If recovery or a deeper query is not exposed, explain the missing supported surface or implement it in the CLI/API.

        ## Useful commands

        - `talkie memos --limit 20 --pretty`
        - `talkie memos 8f42c1b0 --pretty`
        - `talkie dictations --since 24h --pretty`
        - `talkie search "ssh" --type memo --pretty`
        - `talkie workflows --pretty`

        ## Near-term evolution

        TalkieAgent already has a placeholder data bridge surface at `apps/macos/TalkieAgent/TalkieAgent/Services/TalkieRoutes.swift`.
        A good next step is turning TalkieRoutes into a first-class memo/query API so agents can inspect and act on memos through Talkie's own bridge instead of CLI-only workflows.
        """
    }

    private func workflowGuideMarkdown() -> String {
        if let markdown = renderedAgentKitMarkdown(
            relativePath: "docs/workflow-guide.md",
            replacements: workflowTemplateValues()
        ) {
            return markdown
        }

        return """
        # Workflow Guide

        Talkie workflows have three different surfaces:

        1. definition files on disk
        2. preference/runtime config in `config.json`
        3. run history in `workflow_runs`

        ## Definition files

        - system workflows: `\(displayPath(workflowDefinitionsBaseURL.appending(path: "system", directoryHint: .isDirectory)))`
        - user workflows: `\(displayPath(workflowDefinitionsBaseURL.appending(path: "user", directoryHint: .isDirectory)))`
        - imported workflows: `\(displayPath(workflowDefinitionsBaseURL.appending(path: "imported", directoryHint: .isDirectory)))`
        - owning code: `apps/macos/Talkie/Workflow/WorkflowFileRepository.swift`

        These JSON files are the editable source for workflow structure and steps.

        ## Preferences and runtime config

        - live config file: `\(displayPath(macOSWorkflowConfigURL))`
        - owning code: `apps/macos/Talkie/Workflow/WorkflowConfiguration.swift` + `apps/macos/Talkie/Workflow/WorkflowConfigurationStore.swift`
        - merged service view: `apps/macos/Talkie/Workflow/WorkflowService.swift`

        This file owns pinned state, auto-run, sort order, action-surface placement, control-plane settings, shell allowlists, path aliases, and automation timestamps.

        ## Run history

        - live table: `workflow_runs` in `\(displayPath(memoDatabaseURL))`
        - owning code: `apps/macos/Talkie/Data/Models/WorkflowRunModel.swift`
        - execution engine: `apps/macos/Talkie/Workflow/WorkflowExecutor.swift`

        ## Safe interaction rules

        - Edit workflow JSON files or `macos-workflows.config.json` for durable behavior changes.
        - For brand-new workflows, prefer the simplified flat JSON format described in `WORKFLOW_AUTHORING.md`.
        - Write user-authored workflows into `Live Config/workflow-user/<slug>.json`.
        - Do not backfill `workflow_runs` by hand unless the task is a one-off repair or migration.
        - When a pinned action looks wrong on iPhone, check both the workflow definition and `workflowPreferences.<workflow-id>` in `macos-workflows.config.json`.

        ## Useful commands

        - open `Live Config/macos-workflows.config.json`
        - inspect `Live Config/workflow-user/`
        - inspect `Workflow Templates/`
        - run `talkie workflows --pretty`
        - run `talkie workflows <run-id-prefix> --pretty`
        - run `talkie search <query> --type memo --pretty` when you need to connect a memo to workflow output
        """
    }

    private func cliGuideMarkdown() -> String {
        if let markdown = renderedAgentKitMarkdown(
            relativePath: "docs/cli-guide.md",
            replacements: [:]
        ) {
            return markdown
        }

        return """
        # Talkie CLI Guide

        Use the Talkie CLI as the supported agent-facing interface for local app data.

        ## First choice

        - `talkie memos --limit 20 --pretty`
        - `talkie memos <id-prefix> --pretty`
        - `talkie dictations --since 24h --pretty`
        - `talkie dictations <id-prefix> --pretty`
        - `talkie search "<query>" --type memo --pretty`
        - `talkie search "<query>" --type dictation --pretty`
        - `talkie captures --kind screenshot --source all --paths`
        - `talkie captures --kind clip --source all --paths`
        - `talkie workflows --pretty`
        - `talkie workflows <run-id-prefix> --pretty`
        - `talkie stats --pretty`
        - `talkie data path`

        Use `--json` when another command or script needs structured output.

        ## If `talkie` is unavailable

        Do not fall back to `sqlite3`, `bun:sqlite`, or raw SQL. Explain that the supported CLI is not available in the current environment. In a source checkout, inspect `packages/npm/cli` and either run the CLI through its documented development path or implement the missing command there.

        ## Database boundary

        `talkie.sqlite` schema details are useful for understanding owning code, migrations, and data model behavior. They are not the normal runtime interface for agents.

        Only inspect or modify the database directly when the user explicitly asks for a database repair, migration, or forensic recovery task. For ordinary product questions, debugging, memo lookup, dictation lookup, capture lookup, workflow history, and search, use the CLI or a first-class Talkie bridge/API surface.
        """
    }

    private func workflowAuthoringMarkdown() -> String {
        if let markdown = renderedAgentKitMarkdown(
            relativePath: "docs/workflow-authoring.md",
            replacements: [:]
        ) {
            return markdown
        }

        return """
        # Workflow Authoring

        Use this guide when the user describes a workflow in plain language and wants Talkie to set it up.

        ## Fast path

        1. Pick a kebab-case filename like `daily-standup-summary.json`.
        2. Create or update the file in `Live Config/workflow-user/`.
        3. Use the simplified flat JSON format, not the full encoded `WorkflowDefinition` shape with nested wrappers and UUIDs.
        4. Start from the closest example in `Workflow Templates/` whenever possible.
        5. Tell the user what the workflow now does and which file was created.

        Talkie hot-reloads workflow definition files, so saving the JSON file is usually enough to make the workflow appear.

        ## Root shape

        ```json
        {
          "name": "Workflow Name",
          "description": "What it does",
          "icon": "wand.and.stars",
          "color": "blue",
          "steps": [
            {
              "type": "llm",
              "outputKey": "summary",
              "prompt": "Summarize: {{TRANSCRIPT}}"
            }
          ]
        }
        ```

        Root fields:
        - `name`: required
        - `description`: required
        - `icon`: optional SF Symbol
        - `color`: optional Talkie workflow color like `blue`, `green`, `purple`, `orange`, `teal`
        - `maintainer`: optional, usually omit for user-authored workflows
        - `steps`: required array

        ## Variables

        Use template strings inside step config:
        - `{{TRANSCRIPT}}`: the memo transcript
        - `{{PREVIOUS_OUTPUT}}`: the previous step's output
        - `{{OUTPUT}}`: same as previous output for compatibility
        - `{{some_output_key}}`: the output of a named earlier step

        Keep `outputKey` values short and stable, like `summary`, `tasks`, `spoken`, or `saved_file`.

        ## Common step types

        Prefer the simplest working step types first.

        - `llm`
          - required: `prompt`
          - common fields: `provider`, `modelId`, `costTier`, `systemPrompt`, `temperature`, `maxTokens`
        - `shell`
          - required: `executable`
          - common fields: `arguments`, `stdin`, `workingDirectory`, `environment`, `timeout`, `captureStderr`
        - `speak`
          - common fields: `text`, `provider`, `voice`, `rate`, `pitch`, `playImmediately`
        - `saveFile`
          - common fields: `filename`, `directory`, `content`, `appendIfExists`
        - `notification`
          - common fields: `title`, `body`, `sound`, `actionLabel`
        - `transcribe`
          - common fields: `qualityTier`, `fallbackStrategy`, `overwriteExisting`, `saveAsVersion`
        - `transform`
          - common fields: `operation`, `parameters`
        - `conditional`
          - required: `condition`
          - branching uses step indexes via `thenSteps` and `elseSteps`

        Other supported type names:
        - `trigger`
        - `clipboard`
        - `iOSPush`
        - `appleReminders`
        - `intentExtract`
        - `executeWorkflows`
        - `webhook`
        - `email`
        - `cloudUpload`

        ## Good authoring habits

        - Prefer flat JSON over the compiled Swift shape.
        - Keep the workflow small on the first pass.
        - Use one step per real action.
        - Reuse a template when the user asks for something close to summarizing, speaking, extracting tasks, or saving text.
        - If the user only asked for the workflow behavior, stop after creating the definition file. Do not also pin or auto-run it unless requested.

        ## Example patterns

        Last sentence to TTS:
        - copy `Workflow Templates/last-word.json`
        - adapt the shell extraction if needed
        - keep the second step as `speak`

        Summary to file:
        - start from `Workflow Templates/quick-summary.json`
        - add a second `saveFile` step with `content: "{{summary}}"`

        Transcript to notification:
        - use an `llm` summary step
        - follow with `notification` using `body: "{{summary}}"`
        """
    }

    private func workflowCapabilitiesMarkdown() -> String {
        if let markdown = renderedAgentKitMarkdown(
            relativePath: "docs/workflow-capabilities.md",
            replacements: [:]
        ) {
            return markdown
        }

        return """
        # Workflow Capabilities

        Read WORKFLOW_AUTHORING.md for the authoring format and inspect Workflow Templates for concrete working examples.
        """
    }

    private func liveConfigReadmeMarkdown() -> String {
        return """
        # Live Config

        These links point at Talkie's real file-backed sources of truth on this Mac when they exist.

        Safe to edit:
        - `macos-settings.config.json`
        - `macos-workflows.config.json`
        - `macos-context-rules.json`
        - workflow definition directories

        Not mounted here:
        - iPhone app-group settings on a physical device
        - memo database files

        Use `CONFIGURATION_GUIDE.md`, `MEMO_GUIDE.md`, and `WORKFLOW_GUIDE.md` for the rules around what should and should not be edited directly.
        """
    }

    private func workflowTemplatesReadmeMarkdown() -> String {
        if let markdown = renderedAgentKitMarkdown(
            relativePath: "docs/workflow-templates-readme.md",
            replacements: [:]
        ) {
            return markdown
        }

        return """
        # Workflow Templates

        These copied examples come from Talkie's bundled starter workflows. They are here to make workflow authoring easier inside the agent harness.

        Recommended usage:
        - inspect the closest example
        - copy its structure into `Live Config/workflow-user/<slug>.json`
        - adapt the name, description, icon, color, and steps

        If the user wants a brand-new workflow from scratch, `WORKFLOW_AUTHORING.md` is the quickest reference for the flat JSON format.
        """
    }

    private func toolsReadmeMarkdown() -> String {
        return """
        # Tools

        These optional commands are thin wrappers over supported Talkie debug entrypoints.

        Capture markup (screenshot annotation):
        - `capture-markup-describe.sh <image-path>`
        - `capture-markup-plan.sh <image-path> <instruction>`
        - `capture-markup-apply.sh <image-path> <plan-json-path>`
        - `capture-markup-render.sh <image-path> [output-path]`

        There are intentionally no memo, dictation, workflow, or database inspection helpers here. Use `talkie` CLI commands from `CLI_GUIDE.md` for app data. If a supported command is missing, extend the CLI/API instead of adding a shell script that queries `talkie.sqlite`.
        """
    }

    private func openCodeConfigJSON(preferredModel: String?) -> String {
        var payload: [String: Any] = [
            "$schema": "https://opencode.ai/config.json",
            "instructions": [
                "AGENTS.md",
                "SYSTEM_PROMPT.md",
                "CONTEXT.md",
                "EXAMPLES.md",
                "CONFIGURATION_GUIDE.md",
                "MEMO_GUIDE.md",
                "WORKFLOW_GUIDE.md",
                "CLI_GUIDE.md",
                "WORKFLOW_AUTHORING.md",
                "WORKFLOW_CAPABILITIES.md",
            ],
        ]

        if let preferredModel,
           !preferredModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["model"] = preferredModel
            payload["small_model"] = preferredModel
        }

        let data = (try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )) ?? Data()

        return String(decoding: data, as: UTF8.self) + "\n"
    }

    private var macOSSettingsConfigURL: URL {
        TalkieEnvironment.current.appSupportDirectory
            .appendingPathComponent("settings", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    private var macOSWorkflowConfigURL: URL {
        TalkieEnvironment.current.appSupportDirectory
            .appendingPathComponent("workflows", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    private var macOSContextRulesURL: URL {
        TalkieEnvironment.current.appSupportDirectory
            .appendingPathComponent("context", isDirectory: true)
            .appendingPathComponent("rules.json")
    }

    private var workflowDefinitionsBaseURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Talkie", isDirectory: true)
            .appendingPathComponent("workflows", isDirectory: true)
    }

    private var memoDatabaseURL: URL {
        TalkieDatabase.databaseURL
    }

    private var audioDirectoryURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Talkie", isDirectory: true)
            .appendingPathComponent("Audio", isDirectory: true)
    }

    private var talkieExecutablePath: String {
        Bundle.main.executableURL?.path ?? ""
    }

    private var agentKitToolsRuntimePath: String {
        agentKitURL(relativePath: "runtime/agent-tools.ts")?.path ?? ""
    }

    private func displayPath(_ url: URL) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.replacingOccurrences(of: homePath, with: "~")
    }

    private func workflowTemplateValues() -> [String: String] {
        [
            "{{WORKFLOW_SYSTEM_DIR}}": displayPath(workflowDefinitionsBaseURL.appending(path: "system", directoryHint: .isDirectory)),
            "{{WORKFLOW_USER_DIR}}": displayPath(workflowDefinitionsBaseURL.appending(path: "user", directoryHint: .isDirectory)),
            "{{WORKFLOW_IMPORTED_DIR}}": displayPath(workflowDefinitionsBaseURL.appending(path: "imported", directoryHint: .isDirectory)),
            "{{WORKFLOW_CONFIG_PATH}}": displayPath(macOSWorkflowConfigURL),
            "{{MEMO_DATABASE_PATH}}": displayPath(memoDatabaseURL),
        ]
    }

    private func renderedAgentKitMarkdown(
        relativePath: String,
        replacements: [String: String]
    ) -> String? {
        guard let template = agentKitText(relativePath: relativePath) else {
            return nil
        }

        var rendered = template
        for (token, value) in replacements {
            rendered = rendered.replacingOccurrences(of: token, with: value)
        }
        return rendered.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func workflowStepCatalogData() -> Data {
        agentKitData(relativePath: "catalogs/workflow-step-catalog.json")
            ?? Data("""
            {
              "version": 1,
              "description": "Workflow step catalog unavailable.",
              "stepTypes": []
            }
            """.utf8)
    }

    private func agentKitText(relativePath: String) -> String? {
        guard let data = agentKitData(relativePath: relativePath) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func agentKitData(relativePath: String) -> Data? {
        guard let url = agentKitURL(relativePath: relativePath) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private func agentKitURL(relativePath: String) -> URL? {
        for baseURL in agentKitBaseURLs() {
            let url = baseURL.appending(path: relativePath)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private func agentKitBaseURLs() -> [URL] {
        guard let resourcePath = Bundle.main.resourcePath else { return [] }
        return [
            URL(fileURLWithPath: resourcePath).appending(path: "AgentKit", directoryHint: .isDirectory),
            URL(fileURLWithPath: resourcePath)
                .appending(path: "Resources", directoryHint: .isDirectory)
                .appending(path: "AgentKit", directoryHint: .isDirectory),
        ]
    }

    private func copyWorkflowTemplates(into directoryURL: URL) throws {
        guard let resourcePath = Bundle.main.resourcePath else { return }

        let directPath = resourcePath
        let nestedPath = (resourcePath as NSString).appendingPathComponent("Resources")
        let candidatePaths = [
            (directPath as NSString).appendingPathComponent("WorkflowTemplates"),
            (nestedPath as NSString).appendingPathComponent("WorkflowTemplates"),
        ]

        let fileManager = FileManager.default

        for path in candidatePaths where fileManager.fileExists(atPath: path) {
            let files = try fileManager.contentsOfDirectory(atPath: path)
                .filter { $0.hasSuffix(".json") }
                .sorted()

            for filename in files {
                let sourceURL = URL(fileURLWithPath: path).appendingPathComponent(filename)
                let destinationURL = directoryURL.appending(path: filename)
                try? fileManager.removeItem(at: destinationURL)
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }

            return
        }
    }

    private func commonScript() -> String {
        """
        #!/bin/zsh
        set -euo pipefail

        readonly TALKIE_EXECUTABLE_PATH=\(shellQuoted(talkieExecutablePath))
        readonly TALKIE_AGENTKIT_RUNTIME_PATH=\(shellQuoted(agentKitToolsRuntimePath))

        function resolved_bun_path() {
          if command -v bun >/dev/null 2>&1; then
            command -v bun
            return 0
          fi

          local candidates=(
            "$HOME/.bun/bin/bun"
            "/opt/homebrew/bin/bun"
            "/usr/local/bin/bun"
          )

          local candidate
          for candidate in "${candidates[@]}"; do
            if [[ -x "$candidate" ]]; then
              print -- "$candidate"
              return 0
            fi
          done

          print -u2 "bun is required but was not found on PATH."
          exit 1
        }

        function require_agentkit_runtime() {
          if [[ -z "$TALKIE_AGENTKIT_RUNTIME_PATH" || ! -f "$TALKIE_AGENTKIT_RUNTIME_PATH" ]]; then
            print -u2 "AgentKit runtime not available at '$TALKIE_AGENTKIT_RUNTIME_PATH'"
            exit 1
          fi
        }

        function exec_agentkit_tool() {
          local bun_path
          bun_path="$(resolved_bun_path)"
          require_agentkit_runtime

          TALKIE_EXECUTABLE_PATH="$TALKIE_EXECUTABLE_PATH" \
          "$bun_path" "$TALKIE_AGENTKIT_RUNTIME_PATH" "$@"
        }
        """
    }

    private func captureMarkupDescribeScript() -> String {
        """
        #!/bin/zsh
        set -euo pipefail

        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
        source "$SCRIPT_DIR/_common.sh"

        exec_agentkit_tool capture-markup-describe "$@"
        """
    }

    private func captureMarkupPlanScript() -> String {
        """
        #!/bin/zsh
        set -euo pipefail

        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
        source "$SCRIPT_DIR/_common.sh"

        exec_agentkit_tool capture-markup-plan "$@"
        """
    }

    private func captureMarkupApplyScript() -> String {
        """
        #!/bin/zsh
        set -euo pipefail

        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
        source "$SCRIPT_DIR/_common.sh"

        exec_agentkit_tool capture-markup-apply "$@"
        """
    }

    private func captureMarkupRenderScript() -> String {
        """
        #!/bin/zsh
        set -euo pipefail

        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
        source "$SCRIPT_DIR/_common.sh"

        exec_agentkit_tool capture-markup-render "$@"
        """
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
