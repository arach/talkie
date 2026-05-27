//
//  ScopeSkillsLandingView.swift
//  Talkie
//
//  The Skills section landing — one tab, one surface, the whole loop.
//  Studio source of truth: design/studio/app/mac-skills/page.tsx.
//
//  Composition top-to-bottom:
//    1. Header           — "Skills" + state line
//    2. Editor bay       — chat (placeholder) + markup (placeholder)
//    3. Console strip    — last run output (static for Phase 1)
//    4. Starters row     — 3 Talkie-shipped templates
//    5. Your skills row  — driven by WorkflowService.workflows
//    6. Where it fires   — Compose / Voice / Library invocation previews
//    7. Footer           — italic byline
//
//  Phase 1 is visual + data-driven from WorkflowService for "your skills."
//  Editor bay + chat + run wiring are stubs that come in later phases.
//

import SwiftUI
import TalkieKit
import WFKit

// Typography routed through ScopeType — see TalkieKit/UI/ScopeDesign.swift.

private enum SkillsSpacing {
    static let sectionGap: CGFloat = 32
}

// MARK: - Agent choices (Phase 1 stub — wire to LLMConfig later)

private struct AgentChoice: Identifiable, Equatable {
    let id: String
    let label: String
    let provider: String
}

private let AGENT_CHOICES: [AgentChoice] = [
    .init(id: "claude-sonnet-4-6",  label: "claude sonnet 4.6", provider: "Anthropic"),
    .init(id: "claude-opus-4-7",    label: "claude opus 4.7",   provider: "Anthropic"),
    .init(id: "claude-haiku-4-5",   label: "claude haiku 4.5",  provider: "Anthropic"),
    .init(id: "gpt-5",              label: "gpt-5",             provider: "OpenAI"),
    .init(id: "gemini-2-0-flash",   label: "gemini 2.0 flash",  provider: "Google"),
]

// MARK: - Skill mode (temporary inline classification — replaced by SkillKind from codex)

private enum SkillMode {
    case atomic
    case composed
    case workflow
}

private func classifySkill(_ steps: [WorkflowStep]) -> SkillMode {
    let types = steps.map { $0.type }
    let hasExecuteWorkflows = types.contains(.executeWorkflows)
    let hasIntentExtract = types.contains(.intentExtract)
    let hasConditional = types.contains(.conditional)
    let actionStepCount = types.filter { type in
        switch type {
        case .llm, .shell, .webhook, .email, .notification, .iOSPush,
             .appleNotes, .appleReminders, .appleCalendar, .clipboard,
             .saveFile, .speak, .cloudUpload:
            return true
        default:
            return false
        }
    }.count

    if hasConditional || actionStepCount > 2 {
        return .workflow
    }
    if hasExecuteWorkflows || hasIntentExtract {
        return .composed
    }
    return .atomic
}

// MARK: - Static starter content (shipped templates)

private struct Starter: Identifiable {
    let id = UUID()
    let code: String
    let category: String
    let name: String
    let byline: String
    let pipeline: [(kw: String, tag: String)]
    let mode: SkillMode
    let status: String
    let markupBody: [SkillMarkupLine]
    let savePrompt: String
    let icon: String
    let color: WorkflowColor
    // If set, the loader will pull a parsed WorkflowDefinition from
    // Resources/Starters/<skillFileName>.skill.md. When present, SAVE uses
    // that real composition instead of the inline savePrompt stub.
    var skillFileName: String? = nil
}

private enum SkillMarkupLine {
    case keyword(kw: String, rest: String)
    case sub(text: String)
    case blank
}

private let SHIPPED_STARTERS: [Starter] = [
    Starter(
        code: "S-0031",
        category: "Knowledge",
        name: "Research",
        byline: "Speak a topic; the agent digs through your memos and the web, then files the brief as a note.",
        pipeline: [("WHEN", "voice"), ("WITH", "dictation"), ("DO", "research"), ("THEN", "note")],
        mode: .atomic,
        status: "DRAFT",
        markupBody: [
            .keyword(kw: "WHEN", rest: "voice \"research\""),
            .blank,
            .keyword(kw: "WITH", rest: "dictation"),
            .sub(text: "topic"),
            .blank,
            .keyword(kw: "DO",   rest: "llm.research"),
            .sub(text: "depth: deep"),
            .sub(text: "sources: memos + web"),
            .blank,
            .keyword(kw: "THEN", rest: "library.note"),
        ],
        savePrompt: """
        You are a research assistant. Take the user's spoken topic and write a focused research brief: what we know, open questions, key sources to read next. Pull from any prior memos or notes about this topic if available. Keep it scannable — a brief, not an essay.

        Topic:
        {{TRANSCRIPT}}
        """,
        icon: "magnifyingglass.circle.fill",
        color: .blue,
        skillFileName: "research"
    ),
    Starter(
        code: "S-0032",
        category: "Context",
        name: "Prepare",
        byline: "Pull every memo, note, and capture about a topic; synthesize a brief — for a meeting, a doc, anything.",
        pipeline: [("WHEN", "voice"), ("WITH", "dictation"), ("DO", "search"), ("THEN", "note")],
        mode: .composed,
        status: "DRAFT",
        markupBody: [
            .keyword(kw: "WHEN", rest: "voice \"prepare\""),
            .blank,
            .keyword(kw: "WITH", rest: "dictation"),
            .sub(text: "for what"),
            .blank,
            .keyword(kw: "DO",   rest: "search.local"),
            .sub(text: "scope: memos, notes, captures"),
            .sub(text: "window: 14d"),
            .blank,
            .keyword(kw: "DO",   rest: "llm.synthesize"),
            .blank,
            .keyword(kw: "THEN", rest: "library.note"),
        ],
        savePrompt: """
        You are a prep assistant. The user said what they're preparing for — pull together everything relevant from their recent activity (memos, notes, captures from the last two weeks) and synthesize a brief that's ready to scan five minutes before the thing.

        Preparing for:
        {{TRANSCRIPT}}
        """,
        icon: "doc.text.magnifyingglass",
        color: .green,
        skillFileName: "prepare"
    ),
    Starter(
        code: "S-0033",
        category: "Capture",
        name: "Screenshot",
        byline: "Say \"screenshot\" to capture without lifting a finger — voice-first version of the Hyper+S chord.",
        pipeline: [("WHEN", "voice"), ("WITH", "context"), ("DO", "capture"), ("THEN", "ack")],
        mode: .atomic,
        status: "DRAFT",
        markupBody: [
            .keyword(kw: "WHEN", rest: "voice \"screenshot\""),
            .blank,
            .keyword(kw: "WITH", rest: "context"),
            .sub(text: "active window"),
            .blank,
            .keyword(kw: "DO",   rest: "screenshot.capture"),
            .sub(text: "mode: window"),
            .blank,
            .keyword(kw: "THEN", rest: "voice ack"),
        ],
        savePrompt: """
        Capture the active window via the screenshot service and file it in the Tray. Speak a short ack confirming the capture landed.

        Context:
        {{TRANSCRIPT}}
        """,
        icon: "camera.viewfinder",
        color: .orange,
        skillFileName: "screenshot"
    ),
    Starter(
        code: "S-0034",
        category: "Awareness",
        name: "Monitor",
        byline: "A passive watcher that pings you when a topic moves — new memo, new mention, new context.",
        pipeline: [("WHEN", "schedule"), ("WITH", "context"), ("DO", "watch"), ("THEN", "notify")],
        mode: .workflow,
        status: "DRAFT",
        markupBody: [
            .keyword(kw: "WHEN", rest: "schedule"),
            .sub(text: "every 30m"),
            .blank,
            .keyword(kw: "WITH", rest: "context"),
            .sub(text: "inbox + recent memos"),
            .blank,
            .keyword(kw: "DO",   rest: "llm.watch"),
            .sub(text: "condition: meaningful change"),
            .blank,
            .keyword(kw: "THEN", rest: "notification"),
        ],
        savePrompt: """
        You are a watcher. Look at recent activity (last 30 minutes of memos, notes, captures, and inbox). Detect any meaningful change related to the tracked topic. If there's a meaningful shift, write a one-sentence summary suitable for a system notification. If nothing notable, return an empty string.

        Tracked topic:
        {{TRANSCRIPT}}
        """,
        icon: "antenna.radiowaves.left.and.right",
        color: .purple,
        skillFileName: "monitor"
    ),
]

// MARK: - Main view

struct ScopeSkillsLandingView: View {
    private let workflowService = WorkflowService.shared
    private let onUseWorkflow: (Workflow) -> Void

    // Editor bay state
    @State private var selectedStarterID: UUID? = nil
    @State private var isSaving: Bool = false
    @State private var consoleState: ConsoleState = .idle
    @State private var draftMessage: String = ""
    @State private var selectedAgentID: String = AGENT_CHOICES[0].id
    @State private var isHoveringMic: Bool = false
    @State private var isHoveringSubmit: Bool = false
    @State private var isRecording: Bool = false
    @State private var isTranscribing: Bool = false
    @State private var dictationError: String? = nil

    // Parsed .skill.md starters loaded from Resources/Starters on appear.
    // Keyed by file basename (e.g. "daily-standup"). When a Starter has a
    // matching entry, SAVE/RUN use the real composition; otherwise the
    // inline savePrompt stub is used.
    @State private var bundledStarters: [String: BundledStarter] = [:]
    @State private var isRunning: Bool = false

    init(onUseWorkflow: @escaping (Workflow) -> Void) {
        self.onUseWorkflow = onUseWorkflow
    }

    private enum ConsoleState: Equatable {
        case idle
        case savedSkill(name: String, at: Date)
        case saveError(message: String)
        case running(name: String, line: String, at: Date)
        case ranSkill(name: String, summary: String, at: Date)
        case runError(name: String, message: String)
    }

    private var selectedAgent: AgentChoice {
        AGENT_CHOICES.first { $0.id == selectedAgentID } ?? AGENT_CHOICES[0]
    }

    private var selectedStarter: Starter? {
        guard let id = selectedStarterID else { return nil }
        return SHIPPED_STARTERS.first { $0.id == id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                editorBay
                consoleStrip
                    .padding(.top, 14)
                sectionIntro(
                    label: "starters",
                    meta: "\(SHIPPED_STARTERS.count) shipped",
                    intro: "Four skills shipped with Talkie — each leans on something the app already has: dictation, local context, the screenshot chord, scheduled awareness. Click one to load it into the editor above, talk to the agent, save it as yours."
                )
                startersRow
                sectionLine(label: "your skills", hint: yourSkillsHint)
                yourSkillsRow
                sectionLine(label: "where it fires", hint: "saved skills show up in these surfaces")
                whereItFiresRow
                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, SkillsSpacing.sectionGap)
        }
        .background(ScopeCanvas.canvas)
        .onAppear {
            if bundledStarters.isEmpty {
                bundledStarters = SkillStarterLoader.loadBundledStarters()
            }
        }
    }

    private func bundledStarter(for starter: Starter) -> BundledStarter? {
        guard let fileName = starter.skillFileName else { return nil }
        return bundledStarters[fileName]
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("· SKILLS")
                    .font(ScopeType.mono(size: 9, weight: .semibold))
                    .tracking(2.6)
                    .foregroundStyle(ScopeInk.faint)
                Text("one surface · pick a starter, iterate, save")
                    .font(ScopeType.displayItalic(size: 13))
                    .foregroundStyle(ScopeInk.faint)
                Spacer()
                chip(label: editorStatusChipLabel, tone: .amber)
            }
            Text("Skills")
                .font(ScopeType.display(size: 30, weight: .medium))
                .tracking(-0.5)
                .foregroundStyle(ScopeInk.primary)
        }
        .padding(.horizontal, 32)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var editorStatusChipLabel: String {
        if let s = selectedStarter {
            return "\(s.name.uppercased()) · EDITING"
        }
        return "DRAFT · NEW SKILL"
    }

    // MARK: - Editor bay (placeholder)

    @ViewBuilder
    private var editorBay: some View {
        HStack(alignment: .top, spacing: 20) {
            chatPane
                .frame(maxWidth: .infinity)

            markupPane
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 32)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var chatPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            chatHeader
            VStack(spacing: 0) {
                // Message history — currently just the agent's initial greeting.
                // Becomes scrollable history once chat turns are wired.
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        agentMessageRow(text: chatGreeting)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)

                ScopeRule(.subtle)

                // Input row — mic, text field, paper plane. Bottom of the pane.
                HStack(spacing: 8) {
                    inlineMic
                    TextField("describe what to make · or tap the mic", text: $draftMessage)
                        .textFieldStyle(.plain)
                        .font(ScopeType.displayItalic(size: 12.5))
                        .foregroundStyle(ScopeInk.primary)
                        .onSubmit { submitDraftMessage() }
                    submitButton
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(ScopeCanvas.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(ScopeEdge.subtle, lineWidth: 1)
                    )
            )
            .frame(height: 280)
        }
    }

    @ViewBuilder
    private func agentMessageRow(text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("· AGENT")
                .font(ScopeType.mono(size: 9, weight: .semibold))
                .tracking(2.2)
                .foregroundStyle(ScopeInk.muted)
            Text(text)
                .font(ScopeType.displayItalic(size: 12.5))
                .foregroundStyle(ScopeInk.primary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var chatHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("· AGENT")
                .font(ScopeType.mono(size: 9, weight: .semibold))
                .tracking(2.0)
                .foregroundStyle(ScopeInk.faint)
            Spacer()
            Menu {
                Section("Anthropic") {
                    ForEach(AGENT_CHOICES.filter { $0.provider == "Anthropic" }) { a in
                        Button {
                            selectedAgentID = a.id
                        } label: {
                            Label(a.label, systemImage: selectedAgentID == a.id ? "checkmark" : "")
                        }
                    }
                }
                Section("OpenAI") {
                    ForEach(AGENT_CHOICES.filter { $0.provider == "OpenAI" }) { a in
                        Button {
                            selectedAgentID = a.id
                        } label: {
                            Label(a.label, systemImage: selectedAgentID == a.id ? "checkmark" : "")
                        }
                    }
                }
                Section("Google") {
                    ForEach(AGENT_CHOICES.filter { $0.provider == "Google" }) { a in
                        Button {
                            selectedAgentID = a.id
                        } label: {
                            Label(a.label, systemImage: selectedAgentID == a.id ? "checkmark" : "")
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedAgent.label.uppercased())
                        .font(ScopeType.mono(size: 9, weight: .regular))
                        .tracking(1.6)
                        .foregroundStyle(ScopeInk.subtle)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(ScopeInk.subtle)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func submitDraftMessage() {
        guard !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Phase 1: no-op stub — chat runtime arrives in a later phase.
        draftMessage = ""
    }

    @ViewBuilder
    private var inlineMic: some View {
        let recordingRed = Color(red: 0.72, green: 0.32, blue: 0.18)
        let micColor: Color = {
            if isRecording { return Color.white }
            if isTranscribing { return ScopeAmber.solid }
            if isHoveringMic { return ScopeAmber.solid }
            return ScopeInk.subtle
        }()
        let fillColor: Color = {
            if isRecording { return recordingRed }
            if isTranscribing { return ScopeAmber.tint }
            if isHoveringMic { return ScopeAmber.tint }
            return Color.clear
        }()
        let strokeColor: Color = {
            if isRecording { return recordingRed }
            if isTranscribing { return ScopeAmber.solid.opacity(0.6) }
            if isHoveringMic { return ScopeAmber.solid.opacity(0.55) }
            return ScopeEdge.faint
        }()
        let icon: String = {
            if isRecording { return "stop.fill" }
            if isTranscribing { return "waveform" }
            return "mic.fill"
        }()
        Button(action: toggleMic) {
            ZStack {
                Circle().fill(fillColor)
                Circle().stroke(strokeColor, lineWidth: 1)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(micColor)
            }
            .frame(width: 28, height: 28)
            .animation(.easeInOut(duration: 0.15), value: isHoveringMic)
            .animation(.easeInOut(duration: 0.15), value: isRecording)
            .animation(.easeInOut(duration: 0.15), value: isTranscribing)
        }
        .buttonStyle(.plain)
        .disabled(isTranscribing)
        .onHover { hovering in
            isHoveringMic = hovering
            if hovering && !isTranscribing {
                NSCursor.pointingHand.set()
            } else if !hovering {
                NSCursor.arrow.set()
            }
        }
        .help(micTooltip)
        .accessibilityLabel(micTooltip)
    }

    private var micTooltip: String {
        if isRecording { return "Stop & transcribe" }
        if isTranscribing { return "Transcribing…" }
        return "Tap to dictate"
    }

    private func toggleMic() {
        if isRecording {
            Task { await stopAndTranscribe() }
        } else if !isTranscribing {
            startDictation()
        }
    }

    private func startDictation() {
        // Optimistic: flip the visual immediately so the user gets feedback
        // before the AVAudioEngine spool-up completes. Revert on failure.
        isRecording = true
        dictationError = nil
        do {
            try EphemeralTranscriber.shared.startCapture(purpose: .skillsChatDictation)
        } catch {
            isRecording = false
            dictationError = error.localizedDescription
        }
    }

    private func stopAndTranscribe() async {
        guard isRecording else { return }
        isRecording = false
        isTranscribing = true
        do {
            let text = try await EphemeralTranscriber.shared.stopAndTranscribe()
            isTranscribing = false
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return }
            // Append to existing draft (if any) so dictation augments rather than overwrites.
            if draftMessage.isEmpty {
                draftMessage = cleaned
            } else {
                draftMessage = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines) + " " + cleaned
            }
        } catch {
            isTranscribing = false
            dictationError = error.localizedDescription
        }
    }

    @ViewBuilder
    private var submitButton: some View {
        let hasContent = !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let active = hasContent || isHoveringSubmit
        Button {
            submitDraftMessage()
        } label: {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(active ? ScopeAmber.solid : ScopeInk.faint)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(active ? ScopeAmber.tint : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(
                            active ? ScopeAmber.solid.opacity(0.55) : ScopeEdge.faint,
                            lineWidth: 1
                        )
                )
                .animation(.easeInOut(duration: 0.15), value: active)
        }
        .buttonStyle(.plain)
        .disabled(!hasContent)
        .onHover { hovering in
            isHoveringSubmit = hovering
            if hovering && hasContent {
                NSCursor.pointingHand.set()
            } else if !hovering {
                NSCursor.arrow.set()
            }
        }
        .help(hasContent ? "Send" : "Type a message first")
        .accessibilityLabel(hasContent ? "Send message" : "Send message disabled")
    }

    private var chatGreeting: String {
        if let s = selectedStarter {
            return "\(s.name) loaded. \(s.byline) Save to add it to your skills, or tell me to change something."
        }
        return "Ready when you are — pick a starter below, or tell me what to make."
    }

    @ViewBuilder
    private var markupPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("· MARKUP · \(markupFilename)")
                    .font(ScopeType.mono(size: 9, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(ScopeInk.faint)
                    .lineLimit(1)
                Spacer()
                Button(action: runSelectedStarter) {
                    chip(label: isRunning ? "RUNNING…" : "⌘↵ RUN",
                         tone: runChipTone)
                }
                .buttonStyle(.plain)
                .disabled(!canRunSelectedStarter)
                .help(runTooltip)
                Button(action: saveSelectedStarter) {
                    chip(label: isSaving ? "SAVING…" : "⌘S SAVE",
                         tone: (selectedStarter == nil || isSaving) ? .ink : .amber)
                }
                .buttonStyle(.plain)
                .disabled(selectedStarter == nil || isSaving)
            }
            markupBody
        }
    }

    private var canRunSelectedStarter: Bool {
        guard let starter = selectedStarter, !isRunning else { return false }
        // Only starters with a parsed .skill.md (real composition) are runnable.
        guard bundledStarter(for: starter) != nil else { return false }
        // Skills surface RUN runs against the chat input as the transcript.
        // Without text the .transcribe step would try to record against a
        // transient memo with no audio path — codex flagged that as unsafe.
        return !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var runChipTone: ChipTone {
        if !canRunSelectedStarter { return .ink }
        return .amber
    }

    private var runTooltip: String {
        guard let starter = selectedStarter else { return "Select a starter to run" }
        if bundledStarter(for: starter) == nil {
            return "This starter doesn't have a runnable composition yet"
        }
        if isRunning { return "Running…" }
        if draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Type or dictate input first, then run"
        }
        return "Run skill end-to-end on your input"
    }

    private var markupFilename: String {
        if let s = selectedStarter {
            return "\(s.name.lowercased().replacingOccurrences(of: " ", with: "-")).skill.md"
        }
        return "new-skill.skill.md"
    }

    @ViewBuilder
    private var markupBody: some View {
        if let starter = selectedStarter {
            // When a .skill.md ships with this starter, render the actual
            // file body — keeps the editor honest with what SAVE persists.
            // Falls back to the inline markup array for starters without
            // a bundled file.
            if let bundled = bundledStarter(for: starter) {
                markupEditor(lines: markupLines(fromRawBody: bundled.rawBody))
            } else {
                markupEditor(lines: starter.markupBody)
            }
        } else {
            markupPlaceholder
        }
    }

    private func markupLines(fromRawBody body: String) -> [SkillMarkupLine] {
        var lines: [SkillMarkupLine] = []
        let keywordsPrefix: Set<String> = ["WHEN", "WITH", "DO", "THEN"]
        for raw in body.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                lines.append(.blank)
                continue
            }
            if trimmed.hasPrefix("↳") {
                let rest = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                lines.append(.sub(text: rest))
                continue
            }
            let firstToken = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
            if keywordsPrefix.contains(firstToken) {
                let rest = trimmed.dropFirst(firstToken.count).trimmingCharacters(in: .whitespaces)
                lines.append(.keyword(kw: firstToken, rest: rest))
            } else {
                lines.append(.keyword(kw: "", rest: trimmed))
            }
        }
        return lines
    }

    @ViewBuilder
    private func markupEditor(lines: [SkillMarkupLine]) -> some View {
        ZStack(alignment: .topLeading) {
            ScopeCanvas.surface
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ScopeEdge.subtle, lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 0) {
                // Description header — the frontmatter rendered as a spec written by the agent.
                if let starter = selectedStarter {
                    descriptionHeader(name: starter.name, description: starter.byline)
                }
                // Body — WHEN/WITH/DO/THEN with gutter.
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { idx, _ in
                            Text("\(idx + 1)")
                                .font(ScopeType.mono(size: 10, weight: .regular))
                                .foregroundStyle(ScopeInk.subtle)
                                .frame(height: 20)
                                .padding(.trailing, 8)
                        }
                    }
                    .padding(.top, 12)
                    .frame(width: 32)
                    .background(
                        Color(red: 42/255, green: 38/255, blue: 32/255).opacity(0.02)
                            .overlay(
                                ScopeRule(.subtle, axis: .vertical)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            )
                    )

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            renderMarkupLine(line)
                        }
                        Spacer()
                    }
                    .padding(.top, 12)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(height: 280)
    }

    @ViewBuilder
    private func descriptionHeader(name: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(ScopeType.display(size: 17, weight: .medium))
                .tracking(-0.2)
                .foregroundStyle(ScopeInk.primary)
            Text(description)
                .font(ScopeType.displayItalic(size: 11.5))
                .foregroundStyle(ScopeInk.faint)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            ScopeRule(.subtle),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private func renderMarkupLine(_ line: SkillMarkupLine) -> some View {
        switch line {
        case .blank:
            Spacer().frame(height: 20)
        case .keyword(let kw, let rest):
            HStack(spacing: 0) {
                Text(kw.padding(toLength: 5, withPad: " ", startingAt: 0))
                    .font(ScopeType.mono(size: 12, weight: .semibold))
                    .foregroundStyle(ScopeAmber.solid)
                Text(rest)
                    .font(ScopeType.mono(size: 12, weight: .regular))
                    .foregroundStyle(ScopeInk.primary)
            }
            .frame(height: 20, alignment: .leading)
        case .sub(let text):
            HStack(spacing: 0) {
                Text("      \u{21B3} ")
                    .font(ScopeType.mono(size: 12, weight: .regular))
                    .foregroundStyle(ScopeInk.subtle)
                Text(text)
                    .font(ScopeType.mono(size: 12, weight: .regular))
                    .foregroundStyle(ScopeInk.primary)
            }
            .frame(height: 20, alignment: .leading)
        }
    }

    // MARK: - Save action

    private func saveSelectedStarter() {
        guard let starter = selectedStarter, !isSaving else { return }
        isSaving = true
        Task { @MainActor in
            do {
                let definition = definitionForSave(starter: starter)
                try await workflowService.save(definition)
                consoleState = .savedSkill(name: starter.name, at: Date())
                selectedStarterID = nil
            } catch {
                consoleState = .saveError(message: error.localizedDescription)
            }
            isSaving = false
        }
    }

    private func runSelectedStarter() {
        guard let starter = selectedStarter, !isRunning else { return }
        guard let bundled = bundledStarter(for: starter) else {
            consoleState = .runError(name: starter.name, message: "This starter doesn't have a runnable composition yet.")
            return
        }
        isRunning = true
        let runTime = Date()
        let definition = bundled.definition
        let dictation = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        consoleState = .running(name: definition.name, line: "preparing run…", at: runTime)

        Task { @MainActor in
            // Transient memo — not persisted. The Skills surface is a
            // standalone runner; saved runs against ad-hoc input are a
            // future phase. The synthetic memo lets the executor's step
            // functions resolve {{TRANSCRIPT}} etc. via WorkflowContext.
            let memo = MemoModel(
                id: UUID(),
                createdAt: runTime,
                title: "Skill run · \(definition.name)",
                transcription: dictation
            )
            var ctx = WorkflowContext(
                transcript: dictation,
                title: memo.title ?? "Skill run",
                date: memo.createdAt,
                memo: memo
            )

            // RUN-from-button bypasses voice trigger and uses the chat
            // input as the transcript. Always strip .trigger and
            // .transcribe — the transient memo has no audio path and the
            // .transcribe step's saveAsVersion would fail against a
            // non-persisted memo (codex Subtask F finding).
            let runnableSteps = definition.steps.filter { step in
                step.type != .trigger && step.type != .transcribe
            }

            guard !runnableSteps.isEmpty else {
                isRunning = false
                consoleState = .runError(name: definition.name, message: "No runnable steps after stripping trigger.")
                return
            }

            do {
                for (idx, step) in runnableSteps.enumerated() {
                    consoleState = .running(
                        name: definition.name,
                        line: "[\(idx + 1)/\(runnableSteps.count)] \(step.type.displayName)…",
                        at: runTime
                    )
                    let output = try await WorkflowExecutor.shared.executeHostedStep(step, context: &ctx)
                    if !step.outputKey.isEmpty {
                        ctx.outputs[step.outputKey] = output
                        ctx.outputOrder.append(step.outputKey)
                    }
                }
                let lastOutput = ctx.outputOrder.last.flatMap { ctx.outputs[$0] } ?? ""
                let trimmed = lastOutput.replacingOccurrences(of: "\n", with: " ")
                let truncated = trimmed.count > 120 ? String(trimmed.prefix(120)) + "…" : trimmed
                let summary = truncated.isEmpty ? "ran \(runnableSteps.count) steps" : truncated
                consoleState = .ranSkill(name: definition.name, summary: summary, at: Date())
            } catch {
                consoleState = .runError(name: definition.name, message: error.localizedDescription)
            }
            isRunning = false
        }
    }

    private func definitionForSave(starter: Starter) -> WorkflowDefinition {
        // Prefer the parsed .skill.md when one ships with this starter.
        // The parser keeps the real WHEN/WITH/DO/THEN composition; the
        // inline savePrompt is only a fallback for starters that don't
        // have a bundled file yet.
        if let bundled = bundledStarter(for: starter) {
            return WorkflowDefinition(
                id: UUID(),
                name: bundled.definition.name,
                description: bundled.definition.description,
                icon: bundled.definition.icon,
                color: bundled.definition.color,
                maintainer: bundled.definition.maintainer,
                inputs: bundled.definition.inputs,
                steps: bundled.definition.steps,
                isEnabled: bundled.definition.isEnabled,
                isPinned: bundled.definition.isPinned,
                autoRun: bundled.definition.autoRun,
                autoRunOrder: bundled.definition.autoRunOrder,
                source: .user,
                createdAt: Date(),
                modifiedAt: Date()
            )
        }
        let modelId = LLMConfig.shared.defaultModel(for: "gemini") ?? "gemini-2.0-flash"
        return WorkflowDefinition(
            name: starter.name,
            description: starter.byline,
            icon: starter.icon,
            color: starter.color,
            steps: [
                WorkflowStep(
                    type: .llm,
                    config: .llm(LLMStepConfig(
                        provider: .gemini,
                        modelId: modelId,
                        prompt: starter.savePrompt,
                        temperature: 0.7,
                        maxTokens: 1024
                    )),
                    outputKey: "output"
                )
            ]
        )
    }

    @ViewBuilder
    private var markupPlaceholder: some View {
        ZStack(alignment: .topLeading) {
            ScopeCanvas.surface
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ScopeEdge.subtle, lineWidth: 1)
                )
            HStack(alignment: .top, spacing: 0) {
                // Gutter
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(1...10, id: \.self) { i in
                        Text("\(i)")
                            .font(ScopeType.mono(size: 10, weight: .regular))
                            .foregroundStyle(ScopeInk.subtle)
                            .frame(height: 20)
                            .padding(.trailing, 8)
                    }
                }
                .padding(.top, 14)
                .frame(width: 32)
                .background(
                    Color(red: 42/255, green: 38/255, blue: 32/255).opacity(0.02)
                        .overlay(
                            ScopeRule(.subtle, axis: .vertical)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        )
                )

                VStack(alignment: .leading, spacing: 0) {
                    markupLine(kw: "WHEN", rest: "voice \"\u{2026}\"")
                    Spacer().frame(height: 20)
                    markupLine(kw: "WITH", rest: "\u{2026}")
                    Spacer().frame(height: 20)
                    markupLine(kw: "DO",   rest: "\u{2026}")
                    Spacer().frame(height: 20)
                    markupLine(kw: "THEN", rest: "\u{2026}")
                    Spacer()
                }
                .padding(.top, 14)
                .padding(.horizontal, 14)
            }
        }
        .frame(height: 280)
    }

    @ViewBuilder
    private func markupLine(kw: String, rest: String) -> some View {
        HStack(spacing: 0) {
            Text(kw.padding(toLength: 5, withPad: " ", startingAt: 0))
                .font(ScopeType.mono(size: 12, weight: .semibold))
                .foregroundStyle(ScopeAmber.solid)
            Text(rest)
                .font(ScopeType.mono(size: 12, weight: .regular))
                .foregroundStyle(ScopeInk.primary)
        }
        .frame(height: 20, alignment: .leading)
    }

    // MARK: - Console strip

    @ViewBuilder
    private var consoleStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("· CONSOLE · \(consoleHeaderLabel)")
                    .font(ScopeType.mono(size: 9, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(ScopeInk.faint)
                Spacer()
                Text(consoleHeaderRight)
                    .font(ScopeType.mono(size: 9, weight: .regular))
                    .tracking(1.6)
                    .foregroundStyle(ScopeInk.subtle)
            }
            consoleBody
            Spacer(minLength: 0)
        }
        .frame(minHeight: 96, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(ScopeCanvas.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ScopeEdge.subtle, lineWidth: 1)
                )
        )
        .padding(.horizontal, 32)
        .padding(.bottom, 12)
    }

    private var consoleHeaderLabel: String {
        switch consoleState {
        case .idle: return "awaiting first run"
        case .savedSkill: return "just saved"
        case .saveError: return "save failed"
        case .running(let name, _, _): return "running \(name.lowercased())"
        case .ranSkill: return "run complete"
        case .runError: return "run failed"
        }
    }

    private var consoleHeaderRight: String {
        switch consoleState {
        case .idle: return "ready"
        case .savedSkill(_, let at), .running(_, _, let at), .ranSkill(_, _, let at):
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f.string(from: at)
        case .saveError, .runError: return "error"
        }
    }

    @ViewBuilder
    private var consoleBody: some View {
        switch consoleState {
        case .idle:
            HStack(spacing: 8) {
                Text("›")
                    .font(ScopeType.mono(size: 11.5, weight: .regular))
                    .foregroundStyle(ScopeInk.muted)
                Text(selectedStarter == nil
                     ? "pick a starter below to load it into the editor"
                     : "press ⌘S to save \"\(selectedStarter!.name)\" as a skill")
                    .font(ScopeType.mono(size: 11.5, weight: .regular))
                    .foregroundStyle(ScopeInk.faint)
                Spacer()
            }
        case .savedSkill(let name, _):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("›")
                        .font(ScopeType.mono(size: 11.5, weight: .regular))
                        .foregroundStyle(ScopeInk.muted)
                    Text("save skill \"\(name.lowercased())\"")
                        .font(ScopeType.mono(size: 11.5, weight: .regular))
                        .foregroundStyle(ScopeBrass.solid)
                    Spacer()
                }
                HStack(spacing: 8) {
                    Text("✓")
                        .font(ScopeType.mono(size: 11.5, weight: .regular))
                        .foregroundStyle(ScopeBrass.solid)
                    Text("\(name) saved to your skills · scroll down to see the card")
                        .font(ScopeType.mono(size: 11.5, weight: .regular))
                        .foregroundStyle(ScopeInk.primary)
                    Spacer()
                }
            }
        case .saveError(let message):
            HStack(spacing: 8) {
                Text("✗")
                    .font(ScopeType.mono(size: 11.5, weight: .regular))
                    .foregroundStyle(Color.red.opacity(0.7))
                Text(message)
                    .font(ScopeType.mono(size: 11.5, weight: .regular))
                    .foregroundStyle(ScopeInk.primary)
                Spacer()
            }
        case .running(let name, let line, _):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("›")
                        .font(ScopeType.mono(size: 11.5, weight: .regular))
                        .foregroundStyle(ScopeInk.muted)
                    Text("run \(name.lowercased())")
                        .font(ScopeType.mono(size: 11.5, weight: .regular))
                        .foregroundStyle(ScopeBrass.solid)
                    Spacer()
                }
                HStack(spacing: 8) {
                    Text("·")
                        .font(ScopeType.mono(size: 11.5, weight: .regular))
                        .foregroundStyle(ScopeBrass.solid)
                    Text(line)
                        .font(ScopeType.mono(size: 11.5, weight: .regular))
                        .foregroundStyle(ScopeInk.primary)
                    Spacer()
                }
            }
        case .ranSkill(let name, let summary, _):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("›")
                        .font(ScopeType.mono(size: 11.5, weight: .regular))
                        .foregroundStyle(ScopeInk.muted)
                    Text("run \(name.lowercased())")
                        .font(ScopeType.mono(size: 11.5, weight: .regular))
                        .foregroundStyle(ScopeBrass.solid)
                    Spacer()
                }
                HStack(spacing: 8) {
                    Text("✓")
                        .font(ScopeType.mono(size: 11.5, weight: .regular))
                        .foregroundStyle(ScopeBrass.solid)
                    Text(summary)
                        .font(ScopeType.mono(size: 11.5, weight: .regular))
                        .foregroundStyle(ScopeInk.primary)
                    Spacer()
                }
            }
        case .runError(let name, let message):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("›")
                        .font(ScopeType.mono(size: 11.5, weight: .regular))
                        .foregroundStyle(ScopeInk.muted)
                    Text("run \(name.lowercased())")
                        .font(ScopeType.mono(size: 11.5, weight: .regular))
                        .foregroundStyle(ScopeBrass.solid)
                    Spacer()
                }
                HStack(spacing: 8) {
                    Text("✗")
                        .font(ScopeType.mono(size: 11.5, weight: .regular))
                        .foregroundStyle(Color.red.opacity(0.7))
                    Text(message)
                        .font(ScopeType.mono(size: 11.5, weight: .regular))
                        .foregroundStyle(ScopeInk.primary)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Section lines

    @ViewBuilder
    private func sectionLine(label: String, hint: String) -> some View {
        HStack(spacing: 12) {
            Text("· \(label.uppercased())")
                .font(ScopeType.mono(size: 9, weight: .semibold))
                .tracking(2.4)
                .foregroundStyle(ScopeInk.faint)
            Text(hint)
                .font(ScopeType.displayItalic(size: 12))
                .foregroundStyle(ScopeInk.faint)
            ScopeRule(.subtle)
        }
        .padding(.horizontal, 32)
        .padding(.top, SkillsSpacing.sectionGap)
        .padding(.bottom, 8)
    }

    // Richer section header: eyebrow + meta, then an italic prose intro
    // paragraph below. Editorial weight — used to mark a section as a
    // feature, not a list category. Bigger top breathing.
    @ViewBuilder
    private func sectionIntro(label: String, meta: String, intro: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("· \(label.uppercased())")
                    .font(ScopeType.mono(size: 9, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(ScopeInk.faint)
                Text(meta)
                    .font(ScopeType.mono(size: 9, weight: .regular))
                    .tracking(1.6)
                    .foregroundStyle(ScopeInk.subtle)
                ScopeRule(.subtle)
            }
            Text(intro)
                .font(ScopeType.displayItalic(size: 13))
                .foregroundStyle(ScopeInk.faint)
                .lineSpacing(2.5)
                .padding(.leading, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .padding(.top, SkillsSpacing.sectionGap)
        .padding(.bottom, 14)
    }

    // MARK: - Starters row

    @ViewBuilder
    private var startersRow: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(SHIPPED_STARTERS) { starter in
                Button {
                    toggleStarterSelection(starter)
                } label: {
                    starterCard(starter: starter, interactive: true)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 4)
    }

    private func toggleStarterSelection(_ starter: Starter) {
        if selectedStarterID == starter.id {
            selectedStarterID = nil
        } else {
            selectedStarterID = starter.id
        }
    }

    @ViewBuilder
    private func starterCard(starter: Starter, interactive: Bool = false) -> some View {
        let isWorkflow = starter.mode == .workflow
        let isActive = interactive && selectedStarterID == starter.id
        let resolvedStatus = isActive ? "EDITING" : starter.status
        let ctaLabel: String = {
            if isActive { return "OPEN ABOVE ↑" }
            if isWorkflow { return "OPEN IN EDITOR →" }
            return starter.status == "READY" ? "USE →" : "OPEN →"
        }()
        let ctaColor: Color = {
            if isActive { return ScopeAmber.solid }
            return isWorkflow ? ScopeBrass.solid : ScopeAmber.solid
        }()
        let chipTone: ChipTone = {
            if isActive { return .amber }
            if isWorkflow { return .brass }
            return starter.status == "READY" ? .amber : .ink
        }()
        let borderColor: Color = {
            if isActive { return ScopeAmber.solid.opacity(0.45) }
            return isWorkflow ? ScopeBrass.solid.opacity(0.30) : ScopeEdge.subtle
        }()
        let bgFill: Color = isActive ? ScopeAmber.tint.opacity(0.5) : ScopeCanvas.surface

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("· \(starter.category.uppercased())")
                    .font(ScopeType.mono(size: 9, weight: .semibold))
                    .tracking(2.0)
                    .foregroundStyle(isActive ? ScopeAmber.solid : (isWorkflow ? ScopeBrass.solid : ScopeInk.faint))
                Text(starter.code)
                    .font(ScopeType.mono(size: 9, weight: .regular))
                    .tracking(1.4)
                    .foregroundStyle(ScopeInk.subtle)
                Spacer()
            }
            .padding(.bottom, 4)

            Text(starter.name)
                .font(ScopeType.display(size: 19, weight: .medium))
                .tracking(-0.2)
                .foregroundStyle(ScopeInk.primary)
                .padding(.bottom, 4)

            Text(starter.byline)
                .font(ScopeType.displayItalic(size: 11.5))
                .foregroundStyle(ScopeInk.faint)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)

            ScopeRule(.subtle)
                .padding(.vertical, 10)

            pipelineRow(pipeline: starter.pipeline, isWorkflow: isWorkflow)

            Spacer(minLength: 12)

            HStack {
                chip(label: resolvedStatus, tone: chipTone)
                Spacer()
                Text(ctaLabel)
                    .font(ScopeType.mono(size: 9, weight: .semibold))
                    .tracking(2.0)
                    .foregroundStyle(ctaColor)
                    .padding(.bottom, 1)
                    .overlay(
                        Rectangle().fill(ctaColor).frame(height: 1),
                        alignment: .bottom
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 184, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 4).fill(bgFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4).stroke(borderColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func pipelineRow(pipeline: [(kw: String, tag: String)], isWorkflow: Bool) -> some View {
        let kwColor = isWorkflow ? ScopeBrass.solid : ScopeAmber.solid
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            ForEach(pipeline.indices, id: \.self) { i in
                HStack(spacing: 4) {
                    Text(pipeline[i].kw)
                        .font(ScopeType.mono(size: 10, weight: .semibold))
                        .foregroundStyle(kwColor)
                    Text(pipeline[i].tag)
                        .font(ScopeType.mono(size: 10, weight: .regular))
                        .foregroundStyle(ScopeInk.primary)
                }
                if i < pipeline.count - 1 {
                    Text("·")
                        .font(ScopeType.mono(size: 10, weight: .regular))
                        .foregroundStyle(ScopeInk.subtle)
                }
            }
        }
    }

    // MARK: - Your skills row (driven by WorkflowService)

    private var yourSkillsHint: String {
        let count = workflowService.workflows.count
        if count == 0 {
            return "empty for now — your first save will land here"
        }
        return "\(count) saved · pick one to open above"
    }

    @ViewBuilder
    private var yourSkillsRow: some View {
        let workflows = Array(workflowService.workflows.prefix(3))
        HStack(alignment: .top, spacing: 16) {
            ForEach(workflows, id: \.id) { wf in
                userSkillCard(workflow: wf)
            }
            // Fill empty slots so the grid stays 3-up
            ForEach(0..<(3 - workflows.count), id: \.self) { _ in
                placeholderCard
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func userSkillCard(workflow: Workflow) -> some View {
        let mode = classifySkill(workflow.steps)
        let isWorkflow = mode == .workflow
        let category = categoryLabel(for: mode)
        let pipeline = derivedPipeline(for: workflow)
        let status = isWorkflow ? "WORKFLOW" : "READY"

        Button {
            onUseWorkflow(workflow)
        } label: {
            starterCard(starter: Starter(
                code: String(workflow.slug.prefix(8)).uppercased(),
                category: category,
                name: workflow.name,
                byline: workflow.description.isEmpty ? "(no description)" : workflow.description,
                pipeline: pipeline,
                mode: mode,
                status: status,
                markupBody: [],
                savePrompt: "",
                icon: workflow.icon,
                color: workflow.color
            ))
        }
        .buttonStyle(.plain)
        .help("Open \(workflow.name)")
    }

    @ViewBuilder
    private var placeholderCard: some View {
        VStack(spacing: 6) {
            Text("+ NEW SKILL")
                .font(ScopeType.mono(size: 10, weight: .semibold))
                .tracking(2.2)
                .foregroundStyle(ScopeInk.faint)
            Text("⌘N")
                .font(ScopeType.mono(size: 9, weight: .regular))
                .tracking(1.6)
                .foregroundStyle(ScopeInk.subtle)
        }
        .frame(maxWidth: .infinity, minHeight: 184)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(ScopeEdge.subtle, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }

    private func categoryLabel(for mode: SkillMode) -> String {
        switch mode {
        case .atomic:   return "Yours · atomic"
        case .composed: return "Yours · composed"
        case .workflow: return "Yours · workflow"
        }
    }

    private func derivedPipeline(for workflow: Workflow) -> [(kw: String, tag: String)] {
        // Phase 1 quick derivation. Once SkillKind + the parser land,
        // this comes from the .skill.md frontmatter directly.
        let types = workflow.steps.map { $0.type }
        let whenTag: String = types.contains(.trigger) ? "voice" : "manual"
        let withTag: String
        if types.contains(.transcribe) { withTag = "dictation" }
        else if types.contains(.transform) { withTag = "transform" }
        else { withTag = "—" }
        let doTag: String
        if types.contains(.executeWorkflows) { doTag = "sequence" }
        else if types.contains(.intentExtract) { doTag = "route" }
        else if types.contains(.conditional) { doTag = "branch" }
        else if let action = workflow.steps.first(where: { isActionStep($0.type) }) {
            doTag = action.type.displayName.lowercased()
        } else {
            doTag = "—"
        }
        let thenTag: String
        if types.contains(.notification) || types.contains(.iOSPush) { thenTag = "notify" }
        else if types.contains(.speak) { thenTag = "speak" }
        else { thenTag = "—" }
        return [("WHEN", whenTag), ("WITH", withTag), ("DO", doTag), ("THEN", thenTag)]
    }

    private func isActionStep(_ type: WorkflowStep.StepType) -> Bool {
        switch type {
        case .llm, .shell, .webhook, .email, .appleNotes, .appleReminders,
             .appleCalendar, .clipboard, .saveFile, .cloudUpload:
            return true
        default:
            return false
        }
    }

    // MARK: - Where it fires row

    @ViewBuilder
    private var whereItFiresRow: some View {
        HStack(alignment: .top, spacing: 16) {
            previewShell(surface: "Compose · action chip",
                         caption: "Saved skills join the smart-action row. Tap, the skill fires on your selection.") {
                composePreview
            }
            previewShell(surface: "Voice · trigger anywhere",
                         caption: "The WHEN line registers. Say the phrase, the skill fires headless.") {
                voicePreview
            }
            previewShell(surface: "Library · apply to memo",
                         caption: "Recorded something? Apply a skill post-hoc — runs over the existing transcript.") {
                libraryPreview
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func previewShell<Content: View>(surface: String, caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("· \(surface.uppercased())")
                .font(ScopeType.mono(size: 9, weight: .semibold))
                .tracking(2.2)
                .foregroundStyle(ScopeInk.faint)
            content()
                .frame(maxWidth: .infinity)
            Text(caption)
                .font(ScopeType.displayItalic(size: 11.5))
                .foregroundStyle(ScopeInk.faint)
                .lineSpacing(1.4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 196, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 4).fill(ScopeCanvas.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4).stroke(ScopeEdge.subtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var composePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\u{201C}We made real progress on the worker layer today. The pool contention is gone — switching to a single-writer model cleared the last batch of stalls…\u{201D}")
                .font(ScopeType.displayItalic(size: 11))
                .foregroundStyle(ScopeInk.primary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            ScopeRule(.subtle)
            HStack(spacing: 6) {
                miniChip(label: "Refine", active: false)
                miniChip(label: "Simplify", active: false)
                miniChip(label: "Daily Standup →", active: true)
                miniChip(label: "…", active: false, muted: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 3).fill(ScopeCanvas.surface)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(ScopeEdge.subtle, lineWidth: 1))
        )
    }

    @ViewBuilder
    private func miniChip(label: String, active: Bool, muted: Bool = false) -> some View {
        Text(label)
            .font(ScopeType.mono(size: 9, weight: active ? .semibold : .medium))
            .tracking(1.6)
            .foregroundStyle(active ? ScopeBrass.solid : (muted ? ScopeInk.subtle : ScopeInk.faint))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(active ? ScopeBrass.solid.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(active ? ScopeBrass.solid : ScopeInk.muted.opacity(0.24), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var voicePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(ScopePanel.trace)
                    .frame(width: 6, height: 6)
                    .shadow(color: ScopePanel.trace, radius: 4)
                Text("· LISTENING")
                    .font(ScopeType.mono(size: 9, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(ScopePanel.inkMuted)
            }
            HStack(spacing: 4) {
                Text("say")
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(ScopePanel.ink)
                Text("\u{201C}standup\u{201D}")
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundStyle(ScopePanel.trace)
            }
            Text("then dictate · 3 bullets · auto-stops")
                .font(ScopeType.mono(size: 9, weight: .regular))
                .tracking(1.4)
                .foregroundStyle(ScopePanel.inkSubtle)
            Spacer().frame(height: 4)
            HStack(spacing: 1.5) {
                ForEach([3, 6, 4, 9, 5, 11, 7, 4, 8, 12, 6, 9, 5, 7, 3, 10, 6, 4], id: \.self) { h in
                    Rectangle()
                        .fill(ScopePanel.trace.opacity(0.5))
                        .frame(width: 2, height: CGFloat(h))
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(ScopePanel.bg)
        )
    }

    @ViewBuilder
    private var libraryPreview: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("08:42")
                    .font(ScopeType.mono(size: 9, weight: .regular))
                    .tracking(1.4)
                    .foregroundStyle(ScopeInk.subtle)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Worker layer notes")
                        .font(.system(size: 12.5, design: .serif))
                        .foregroundStyle(ScopeInk.primary)
                    Text("4:12 · today")
                        .font(ScopeType.displayItalic(size: 10.5))
                        .foregroundStyle(ScopeInk.faint)
                }
                Spacer()
                Text("▷ apply ↓")
                    .font(ScopeType.mono(size: 9, weight: .semibold))
                    .tracking(2.0)
                    .foregroundStyle(ScopeInk.subtle)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            ScopeRule(.subtle)
            VStack(alignment: .leading, spacing: 6) {
                Text("· YOUR SKILLS")
                    .font(ScopeType.mono(size: 9, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(ScopeInk.faint)
                HStack {
                    Text("Daily Standup")
                        .font(.system(size: 11.5, design: .serif))
                        .foregroundStyle(ScopeInk.primary)
                    Spacer()
                    Text("APPLY →")
                        .font(ScopeType.mono(size: 9, weight: .semibold))
                        .tracking(2.2)
                        .foregroundStyle(ScopeAmber.solid)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 2).fill(ScopeAmber.tint)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(ScopeAmber.solid.opacity(0.45), lineWidth: 1))
                )
                HStack {
                    Text("Log Bug")
                        .font(.system(size: 11.5, design: .serif))
                        .foregroundStyle(ScopeInk.faint)
                    Spacer()
                    Text("READY")
                        .font(ScopeType.mono(size: 9, weight: .regular))
                        .tracking(2.2)
                        .foregroundStyle(ScopeInk.subtle)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // Inner dropdown blends with the paper outer — hairline above does the separation.
        }
        .background(
            RoundedRectangle(cornerRadius: 3).fill(ScopeCanvas.surface)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(ScopeEdge.subtle, lineWidth: 1))
        )
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScopeRule(.subtle)
        }
        .padding(.horizontal, 32)
        .padding(.top, 26)
    }

    // MARK: - Pane header + chip primitives

    @ViewBuilder
    private func paneHeader(title: String, sub: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("· \(title.uppercased())")
                .font(ScopeType.mono(size: 9, weight: .semibold))
                .tracking(2.0)
                .foregroundStyle(ScopeInk.faint)
            Spacer()
            if let sub {
                Text(sub.uppercased())
                    .font(ScopeType.mono(size: 9, weight: .regular))
                    .tracking(1.6)
                    .foregroundStyle(ScopeInk.subtle)
            }
        }
    }

    private enum ChipTone { case amber, brass, ink }

    @ViewBuilder
    private func chip(label: String, tone: ChipTone) -> some View {
        let color: Color = {
            switch tone { case .amber: return ScopeAmber.solid
                          case .brass: return ScopeBrass.solid
                          case .ink:   return ScopeInk.faint }
        }()
        let border: Color = {
            switch tone { case .amber: return ScopeAmber.solid
                          case .brass: return ScopeBrass.solid
                          case .ink:   return ScopeEdge.faint }
        }()
        let bg: Color = {
            switch tone { case .amber: return ScopeAmber.tint
                          case .brass: return ScopeBrass.solid.opacity(0.08)
                          case .ink:   return Color.clear }
        }()
        Text(label)
            .font(ScopeType.mono(size: 9, weight: .semibold))
            .tracking(2.2)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 2).fill(bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2).stroke(border, lineWidth: 1)
            )
    }
}
