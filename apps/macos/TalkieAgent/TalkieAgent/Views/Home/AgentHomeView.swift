//
//  AgentHomeView.swift
//  TalkieAgent
//
//  Conversation surface. Mirrors the studio canon at
//  design/studio/components/studies/MacAgentHome.tsx — sidebar of
//  auto-named conversations on the left, a linear You ↔ Talkie
//  transcript on the right, every Talkie reply tucks extra context
//  (summary, action log, timing) behind a quiet "Details" link.
//
//  Palette: cool-gray Scope substrate (ScopeCanvas / ScopeInk),
//  amber as the sole accent (live state, Talkie avatar). One
//  display-serif moment for the conversation title; everything else
//  is the system sans on the 4 / 8 / 12 / 16 / 24 / 32 spacing scale.
//

import SwiftUI
import TalkieKit

struct AgentHomeView: View {
    let onDismiss: () -> Void
    let onOpenSettings: () -> Void

    @StateObject private var store = AgentHomeActivityStore()
    @StateObject private var voiceCapture = AgentHomeVoiceCapture()
    @State private var selectedTopicId: String?
    @State private var agentPrompt = ""
    @State private var continuation: AgentHomeContinuationContext?
    @State private var voicePromptTarget: AgentHomePromptTarget?
    @State private var openWorkTurnIds: Set<String> = []
    @FocusState private var agentPromptFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 240)

            Rectangle()
                .fill(ScopeEdge.subtle)
                .frame(width: 1)

            reader
        }
        .background(ScopeCanvas.canvas)
        .onAppear { store.startRefreshing() }
        .onDisappear {
            store.stopRefreshing()
            voiceCapture.cancel()
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                newConversationButton

                AgentHomeRuntimeBadge(ping: store.runtimePing)

                AgentHomeAgentRuntimexyx(agentRuntimexyx: store.agentRuntimexyx)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 8)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let topics = store.conversationTopics
                    ForEach(Array(topics.enumerated()), id: \.element.id) { index, topic in
                        let prevGroup = index == 0
                            ? nil
                            : AgentHomeActivityStore.groupLabel(for: topics[index - 1].lastActivityAt)
                        let group = AgentHomeActivityStore.groupLabel(for: topic.lastActivityAt)
                        if prevGroup != group {
                            AgentHomeGroupLabel(label: group, isFirst: index == 0)
                        }
                        AgentHomeConversationRow(
                            topic: topic,
                            selected: topic.id == selectedTopic.id
                        ) {
                            selectTopic(topic.id)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }

            Spacer(minLength: 0)

            Divider()
                .overlay(ScopeEdge.subtle)

            HStack(spacing: 6) {
                Button(action: onOpenSettings) {
                    Label("Settings", systemImage: "gearshape")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(ScopeInk.faint)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(ScopeCanvas.canvasAlt)
    }

    private var newConversationButton: some View {
        Button(action: startNewTopic) {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("+")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(ScopeInk.subtle)
                        .offset(y: -1)

                    Text("New conversation")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(ScopeInk.primary)
                }

                Spacer(minLength: 8)

                Text("⌘N")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(ScopeInk.subtle)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(ScopeEdge.subtle, lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.02), radius: 1, x: 0, y: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Reader

    private var reader: some View {
        VStack(spacing: 0) {
            readerHeader

            Rectangle()
                .fill(ScopeEdge.subtle)
                .frame(height: 1)

            if isIdle {
                // Idle mode: replace the transcript + pinned-composer with a
                // centered IdleHero that integrates the composer right under
                // the headline. One focal point, no chrome handoff.
                ScrollView(.vertical, showsIndicators: false) {
                    AgentHomeIdleHero(
                        text: $agentPrompt,
                        isSending: store.isInvokingAgent,
                        placeholder: composerPlaceholder,
                        continuation: continuation,
                        voiceCapture: voiceCapture,
                        error: store.invokeError,
                        isFocused: $agentPromptFocused,
                        onClearContinuation: { continuation = nil },
                        onSend: sendAgentPrompt,
                        onCancelTalkBack: cancelTalkBack,
                        onTalkBack: talkBack,
                        onStarter: useStarter
                    )
                    .padding(.leading, AgentHomeMetrics.gutter)
                    .padding(.trailing, AgentHomeMetrics.gutter)
                    .padding(.top, 56)
                    .padding(.bottom, 32)
                    .frame(maxWidth: AgentHomeMetrics.readerColumn + AgentHomeMetrics.gutter * 2,
                           alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    AgentHomeTranscriptView(
                        turns: selectedTurns,
                        openTurnIds: openWorkTurnIds,
                        onToggleWork: toggleWork,
                        onCopy: store.copy,
                        onContinue: continueConversation
                    )
                    .padding(.leading, AgentHomeMetrics.gutter)
                    .padding(.trailing, AgentHomeMetrics.gutter)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                    .frame(maxWidth: AgentHomeMetrics.readerColumn + AgentHomeMetrics.gutter * 2,
                           alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                composer
            }
        }
        .background(ScopeCanvas.canvas)
    }

    private var isIdle: Bool { selectedTurns.isEmpty }

    private var readerHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("· CONVERSATION")
                    .font(ScopeType.eyebrow)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)

                Text(selectedTopic.title)
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .foregroundStyle(ScopeInk.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(headerSubtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(ScopeInk.faint)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if !isIdle {
                AgentHomeTalkBackButton(
                    isRecording: voiceCapture.phase == .recording,
                    isProcessing: voiceCapture.phase == .processing,
                    action: talkBack
                )
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ScopeInk.faint)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(ScopeInk.primary.opacity(0.04))
                    )
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.leading, AgentHomeMetrics.gutter)
        .padding(.trailing, AgentHomeMetrics.gutter)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(maxWidth: AgentHomeMetrics.readerColumn + AgentHomeMetrics.gutter * 2,
               alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: ScopeCanvas.canvas.opacity(0), location: 0),
                    .init(color: ScopeCanvas.canvas, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 12)

            AgentHomeComposer(
                text: $agentPrompt,
                isSending: store.isInvokingAgent,
                placeholder: composerPlaceholder,
                continuation: continuation,
                voiceCapture: voiceCapture,
                error: store.invokeError,
                isFocused: $agentPromptFocused,
                onClearContinuation: { continuation = nil },
                onSend: sendAgentPrompt,
                onCancelTalkBack: cancelTalkBack,
                onTalkBack: talkBack
            )
            .padding(.leading, AgentHomeMetrics.gutter)
            .padding(.trailing, AgentHomeMetrics.gutter)
            .padding(.bottom, 18)
            .frame(maxWidth: AgentHomeMetrics.readerColumn + AgentHomeMetrics.gutter * 2,
                   alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ScopeCanvas.canvas)
    }

    // MARK: Derived

    private var selectedTopic: AgentHomeConversationTopic {
        if let selectedTopicId,
           let topic = store.conversationTopics.first(where: { $0.id == selectedTopicId }) {
            return topic
        }
        if let selectedTopicId {
            return AgentHomeConversationTopic(
                id: selectedTopicId,
                title: "New conversation",
                subtitle: "Draft",
                icon: "plus.bubble",
                activeCount: 0,
                turnCount: 0,
                lastActivityAt: nil
            )
        }
        return store.conversationTopics.first ?? .general
    }

    private var selectedTurns: [AgentHomeExecutorTurn] {
        store.executorTurns(in: selectedTopic.id)
    }

    private var headerSubtitle: String {
        let count = selectedTopic.turnCount
        let turnLabel = count == 1 ? "1 turn" : "\(count) turns"
        var parts: [String] = []
        if let last = selectedTopic.lastActivityAt {
            parts.append(AgentHomeActivityStore.groupLabel(for: last) + " " +
                         AgentHomeActivityStore.sidebarStamp(for: last))
        }
        if count > 0 { parts.append(turnLabel) }
        if selectedTopic.activeCount > 0 { parts.append("working now") }
        return parts.isEmpty ? "Say or type something — Talkie's listening" : parts.joined(separator: " · ")
    }

    private var composerPlaceholder: String {
        selectedTopic.turnCount == 0
            ? "Say something, or type here"
            : "Reply by voice or text"
    }

    // MARK: Actions

    private func startNewTopic() {
        selectedTopicId = "agent-home-\(UUID().uuidString.lowercased())"
        continuation = nil
        agentPromptFocused = true
    }

    private func selectTopic(_ topicId: String) {
        selectedTopicId = topicId
        continuation = nil
        if voiceCapture.phase == .idle {
            agentPromptFocused = true
        }
    }

    private func toggleWork(_ turnId: String) {
        if openWorkTurnIds.contains(turnId) {
            openWorkTurnIds.remove(turnId)
        } else {
            openWorkTurnIds.insert(turnId)
        }
    }

    /// Starter chip handler — drops the starter text into the composer
    /// and focuses it. Users can edit before sending; we don't auto-fire
    /// because starters are seeds, not commands.
    private func useStarter(_ text: String) {
        agentPrompt = text
        agentPromptFocused = true
    }

    private func sendAgentPrompt() {
        let prompt = agentPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !store.isInvokingAgent else { return }

        agentPrompt = ""
        let target = currentPromptTarget()
        continuation = nil
        submitAgentPrompt(prompt, target: target)
    }

    private func continueConversation(from turn: AgentHomeExecutorTurn) {
        continuation = AgentHomeContinuationContext(turn: turn)
        selectedTopicId = continuation?.conversationId
        agentPromptFocused = true
    }

    private func talkBack() {
        switch voiceCapture.phase {
        case .idle:
            voicePromptTarget = currentPromptTarget()
            agentPromptFocused = false
            voiceCapture.start()
        case .recording:
            let target = voicePromptTarget ?? currentPromptTarget()
            voiceCapture.stopAndTranscribe(
                onTranscript: { transcript in
                    continuation = nil
                    submitAgentPrompt(transcript, target: target)
                },
                onFinish: {
                    voicePromptTarget = nil
                }
            )
        case .processing:
            break
        }
    }

    private func cancelTalkBack() {
        voicePromptTarget = nil
        voiceCapture.cancel()
    }

    private func currentPromptTarget() -> AgentHomePromptTarget {
        AgentHomePromptTarget(
            conversationId: continuation?.conversationId ?? selectedTopic.id,
            parentSessionId: continuation?.parentSessionId
        )
    }

    private func submitAgentPrompt(_ prompt: String, target: AgentHomePromptTarget) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !store.isInvokingAgent else { return }

        Task {
            await store.invokeAgent(
                text: trimmed,
                conversationId: target.conversationId,
                parentSessionId: target.parentSessionId
            )
        }
    }
}

// MARK: - Metrics

private enum AgentHomeMetrics {
    /// Reader column width. Matches the studio's READER_COLUMN.
    static let readerColumn: CGFloat = 720
    /// Left/right gutter inside the reader. Matches studio READER_GUTTER.
    static let gutter: CGFloat = 32
}

private struct AgentHomePromptTarget: Equatable {
    let conversationId: String
    let parentSessionId: String?
}

// MARK: - Continuation context

private struct AgentHomeContinuationContext: Equatable {
    let conversationId: String
    let parentSessionId: String
    let label: String

    init(turn: AgentHomeExecutorTurn) {
        conversationId = turn.conversationId ?? "agent-home-main"
        parentSessionId = turn.id

        if let summary = turn.spokenSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            label = summary
        } else if let transcript = turn.transcript?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !transcript.isEmpty {
            label = transcript
        } else {
            label = turn.id
        }
    }
}

// MARK: - Agent status badge

private struct AgentHomeRuntimeBadge: View {
    let ping: WalkieRuntimePing?

    var body: some View {
        let healthy = ping?.scoutBridge == .configured
        let label = ping == nil ? "Offline" : "Ready"
        let dot: Color = ping == nil ? .red : (healthy ? .green : .orange)

        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(label.uppercased())
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.faint)
            Spacer(minLength: 0)
        }
        .help(ping == nil ? "Talkie is not answering yet." : "Talkie is ready to answer here.")
    }
}

private struct AgentHomeAgentRuntimexyx: View {
    let agentRuntimexyx: [WalkieRuntimeAgentSnapshot]

    private var availableCount: Int {
        agentRuntimexyx.filter(\.isAvailable).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("AGENTS")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(ScopeInk.subtle)

                Spacer(minLength: 4)

                Text(agentRuntimexyx.isEmpty ? "checking" : "\(availableCount)/\(agentRuntimexyx.count)")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(ScopeInk.subtle)
            }

            VStack(alignment: .leading, spacing: 3) {
                if agentRuntimexyx.isEmpty {
                    AgentHomeAgentRuntimexyxPlaceholder()
                } else {
                    ForEach(agentRuntimexyx) { agent in
                        AgentHomeAgentRow(agent: agent)
                    }
                }
            }
        }
        .padding(.top, 4)
    }
}

private struct AgentHomeAgentRuntimexyxPlaceholder: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ScopeInk.subtle.opacity(0.35))
                .frame(width: 6, height: 6)

            Text("Checking agent sessions")
                .font(.system(size: 11))
                .foregroundStyle(ScopeInk.subtle)
        }
        .frame(height: 20)
    }
}

private struct AgentHomeAgentRow: View {
    let agent: WalkieRuntimeAgentSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(agent.name)
                .font(.system(size: 11.5, weight: agent.isPreferred == true ? .semibold : .medium))
                .foregroundStyle(agent.isAvailable ? ScopeInk.primary : ScopeInk.subtle)
                .lineLimit(1)

            Spacer(minLength: 4)

            if agent.isPreferred == true {
                Text("default")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(ScopeInk.subtle)
            } else if let count = agent.activeSessions, count > 0 {
                Text("\(count) live")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(ScopeAmber.solid)
            } else {
                Text(statusLabel)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(ScopeInk.subtle)
            }
        }
        .frame(height: 20)
        .help(helpText)
    }

    private var statusColor: Color {
        if agent.isAvailable {
            return (agent.activeSessions ?? 0) > 0 ? ScopeAmber.solid : .green
        }

        switch agent.status {
        case "misconfigured":
            return .orange
        case "missing", "unavailable":
            return .red
        default:
            return ScopeInk.subtle.opacity(0.45)
        }
    }

    private var statusLabel: String {
        if agent.isAvailable { return "ready" }
        if agent.status == "misconfigured" { return "setup" }
        if agent.status == "unavailable" { return "offline" }
        return "missing"
    }

    private var helpText: String {
        let detail = agent.detail?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let path = agent.executablePath?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        return [detail, path].compactMap { $0 }.joined(separator: "\n")
    }
}

// MARK: - Sidebar atoms

private struct AgentHomeGroupLabel: View {
    let label: String
    let isFirst: Bool

    var body: some View {
        Text("· \(label.uppercased())")
            .font(ScopeType.chrome)
            .tracking(ScopeType.Tracking.wide)
            .foregroundStyle(ScopeInk.subtle)
            .padding(.horizontal, 12)
            .padding(.top, isFirst ? 8 : 16)
            .padding(.bottom, 6)
    }
}

private struct AgentHomeConversationRow: View {
    let topic: AgentHomeConversationTopic
    let selected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(topic.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(ScopeInk.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                trailing
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(rowFill)
                    .shadow(color: selected ? Color.black.opacity(0.03) : .clear,
                            radius: 0.5, x: 0, y: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(selected ? "Focus the reply field" : "Open this conversation")
        .accessibilityLabel("\(topic.title), \(selected ? "selected" : "conversation")")
    }

    private var rowFill: Color {
        if selected { return .white }
        if hovered  { return ScopeInk.primary.opacity(0.025) }
        return .clear
    }

    @ViewBuilder
    private var trailing: some View {
        if topic.activeCount > 0 {
            HStack(spacing: 6) {
                Text("working")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(ScopeBrass.solid)
                Circle()
                    .fill(ScopeAmber.solid)
                    .frame(width: 6, height: 6)
                    .shadow(color: ScopeAmber.glow, radius: 0, x: 0, y: 0)
                    .overlay(
                        Circle().stroke(ScopeAmber.tint, lineWidth: 3)
                    )
            }
        } else if hovered || selected {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hovered ? ScopeBrass.solid : ScopeInk.subtle)
                .frame(width: 20, alignment: .trailing)
        } else {
            Text(AgentHomeActivityStore.sidebarStamp(for: topic.lastActivityAt))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(ScopeInk.subtle)
        }
    }
}

// MARK: - Talk-back button (header)

private struct AgentHomeTalkBackButton: View {
    let isRecording: Bool
    let isProcessing: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(hovered ? .white : ScopeBrass.solid)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(hovered ? ScopeAmber.solid : ScopeAmber.tint)
            )
            .overlay(
                Capsule().stroke(ScopeAmber.solid.opacity(hovered ? 0 : 0.30), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .help(helpText)
    }

    private var iconName: String {
        if isProcessing { return "hourglass" }
        return isRecording ? "stop.fill" : "mic.fill"
    }

    private var label: String {
        if isProcessing { return "Sending" }
        return isRecording ? "Stop" : "Talk back"
    }

    private var helpText: String {
        if isProcessing { return "Transcribing voice reply" }
        return isRecording ? "Stop and send this voice reply" : "Record a voice reply in Agent Home"
    }
}

// MARK: - Transcript

struct AgentHomeTranscriptView: View {
    let turns: [AgentHomeExecutorTurn]
    let openTurnIds: Set<String>
    let onToggleWork: (String) -> Void
    let onCopy: (String) -> Void
    let onContinue: (AgentHomeExecutorTurn) -> Void

    var body: some View {
        if turns.isEmpty {
            AgentHomeEmptyRoom()
        } else {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(Array(turns.enumerated()), id: \.element.id) { index, turn in
                    let prev = index > 0 ? turns[index - 1] : nil
                    if let prev, AgentHomeTranscriptView.hoursBetween(prev.createdAt, turn.createdAt) >= 24 {
                        AgentHomeDateDivider(label: AgentHomeTranscriptView.dayLabel(for: turn.createdAt))
                    }
                    AgentHomeTurnBlock(
                        turn: turn,
                        showWork: openTurnIds.contains(turn.id),
                        onToggleWork: { onToggleWork(turn.id) },
                        onCopy: onCopy,
                        onContinue: { onContinue(turn) }
                    )
                }
            }
        }
    }

    private static func hoursBetween(_ a: Date, _ b: Date) -> Double {
        abs(b.timeIntervalSince(a)) / 3_600
    }

    private static func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

private struct AgentHomeDateDivider: View {
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(ScopeEdge.subtle).frame(height: 1)
            Text(label.uppercased())
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.subtle)
            Rectangle().fill(ScopeEdge.subtle).frame(height: 1)
        }
        .padding(.vertical, 2)
    }
}

private struct AgentHomeEmptyRoom: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("Say something to start.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ScopeInk.muted)
            Text("click the mic or type below")
                .font(.system(size: 11))
                .foregroundStyle(ScopeInk.subtle)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 48)
    }
}

// MARK: - Turn block (You + Talkie pair)

private struct AgentHomeTurnBlock: View {
    let turn: AgentHomeExecutorTurn
    let showWork: Bool
    let onToggleWork: () -> Void
    let onCopy: (String) -> Void
    let onContinue: () -> Void

    private var isLive: Bool {
        turn.status == .running || turn.status == .waiting
    }

    private var talkieBody: String {
        if isLive {
            return turn.response?.nonEmpty ?? turn.ack ?? "Working on it…"
        }
        return turn.spokenBody ?? turn.ack ?? "—"
    }

    private var talkieMeta: String? {
        if isLive { return "working" }
        return turn.latencyLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            AgentHomeSpeech(
                speaker: .you,
                bodyText: turn.askBody ?? "—",
                time: timeLabel(turn.createdAt),
                onCopy: { onCopy(turn.askBody ?? "") }
            )

            AgentHomeSpeech(
                speaker: .talkie,
                meta: talkieMeta,
                live: isLive,
                bodyText: talkieBody,
                italic: isLive,
                time: timeLabel(turn.updatedAt),
                onCopy: { onCopy(talkieBody) },
                onContinue: isLive ? nil : onContinue,
                footer: AnyView(showWorkFooter)
            )
        }
        .padding(.leading, isLive ? 14 : 16)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isLive ? ScopeAmber.solid : Color.clear)
                .frame(width: 2)
        }
        .animation(.easeOut(duration: 0.18), value: isLive)
    }

    @ViewBuilder
    private var showWorkFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggleWork) {
                Text(showWork ? "Hide details" : "Details")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ScopeInk.subtle)
            }
            .buttonStyle(.plain)
            .help(showWork ? "Hide reply details" : "Show reply details")

            if showWork {
                AgentHomeWorkBlock(turn: turn, onCopy: onCopy, onContinue: onContinue)
            }
        }
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date).lowercased()
    }
}

// MARK: - Speech

private enum AgentHomeSpeaker {
    case you
    case talkie

    var label: String {
        switch self {
        case .you:    return "You"
        case .talkie: return "Talkie"
        }
    }

    var initial: String {
        switch self {
        case .you:    return "Y"
        case .talkie: return "T"
        }
    }
}

private struct AgentHomeSpeech: View {
    let speaker: AgentHomeSpeaker
    var meta: String? = nil
    var live: Bool = false
    let bodyText: String
    var italic: Bool = false
    var time: String? = nil
    var onCopy: () -> Void = {}
    var onContinue: (() -> Void)? = nil
    var footer: AnyView = AnyView(EmptyView())

    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AgentHomeAvatar(speaker: speaker, live: live)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                speakerLine

                Text(displayedText)
                    .font(.system(size: 13))
                    .italic(italic)
                    .foregroundStyle(italic ? ScopeInk.muted : ScopeInk.primary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                footer
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    private var displayedText: String {
        italic ? "\u{201C}\(bodyText)\u{201D}" : bodyText
    }

    private var speakerLine: some View {
        HStack(spacing: 8) {
            Text(speaker.label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(ScopeInk.primary)

            if let meta {
                Text("· \(meta)")
                    .font(.system(size: 10, weight: live ? .semibold : .medium, design: .monospaced))
                    .foregroundStyle(live ? ScopeBrass.solid : ScopeInk.subtle)
            }

            if live {
                Circle()
                    .fill(ScopeAmber.solid)
                    .frame(width: 6, height: 6)
                    .overlay(
                        Circle().stroke(ScopeAmber.tint, lineWidth: 3)
                    )
            }

            Spacer(minLength: 0)

            if let onContinue, hovered {
                Button(action: onContinue) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Continue")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(ScopeBrass.solid)
                }
                .buttonStyle(.plain)
                .help("Continue from this turn")
                .transition(.opacity)
            }

            if let time {
                Text(time)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(ScopeInk.subtle)
                    .opacity(hovered ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: hovered)
                    .help("Sent at \(time)")
            }
        }
    }
}

private struct AgentHomeAvatar: View {
    let speaker: AgentHomeSpeaker
    let live: Bool

    var body: some View {
        let isTalkie = speaker == .talkie
        let bg: Color = isTalkie ? ScopeAmber.tint : ScopeInk.primary.opacity(0.05)
        let fg: Color = isTalkie ? ScopeBrass.solid : ScopeInk.muted

        RoundedRectangle(cornerRadius: 6)
            .fill(bg)
            .frame(width: 22, height: 22)
            .overlay(
                Text(speaker.initial)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(fg)
            )
    }
}

// MARK: - Details block

private struct AgentHomeWorkBlock: View {
    let turn: AgentHomeExecutorTurn
    let onCopy: (String) -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary = turn.spokenSummary?.nonEmpty, summary != turn.spokenBody {
                Text(summary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(ScopeInk.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if !turn.threads.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(turn.threads) { thread in
                        AgentHomeActionRow(thread: thread)
                    }
                }
            }

            if let response = turn.response?.nonEmpty,
               response != turn.spokenBody && response != turn.spokenSummary {
                Text(response)
                    .font(.system(size: 12.5))
                    .foregroundStyle(ScopeInk.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                Text(identityLine)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(ScopeInk.subtle)

                Spacer(minLength: 8)

                if turn.spokenSummary?.nonEmpty != nil {
                    Button(action: onContinue) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Continue")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(ScopeBrass.solid)
                    }
                    .buttonStyle(.plain)
                    .help("Continue this conversation")
                }
            }
        }
    }

    private var identityLine: String {
        switch turn.status {
        case .waiting:
            return "\(turn.agentDisplayName) · queued"
        case .running:
            return "\(turn.agentDisplayName) · working"
        case .failed:
            return "\(turn.agentDisplayName) · needs attention"
        case .done:
            return "\(turn.agentDisplayName) · \(turn.latencyLabel ?? "done")"
        }
    }
}

// String/Optional helpers used by this view. The store has its own
// `private extension String` with the same shape — duplicated here on
// purpose so we don't widen its visibility.
fileprivate extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private struct AgentHomeActionRow: View {
    let thread: AgentHomeExecutorThread

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: glyphName)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(thread.status == .failed ? .red : ScopeInk.subtle)
                .frame(width: 12, alignment: .center)

            Text(thread.label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(thread.status == .waiting ? ScopeInk.subtle : ScopeInk.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            if let detail = thread.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(ScopeInk.subtle)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            statusBadge
        }
        .opacity(thread.status == .waiting ? 0.75 : 1)
    }

    private var glyphName: String {
        switch thread.kind {
        case .normalize: return "text.alignleft"
        case .dispatch:  return "arrow.turn.down.right"
        case .executor:  return "sparkles"
        case .response:  return "text.bubble"
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch thread.status {
        case .running:
            Circle().fill(ScopeAmber.solid).frame(width: 6, height: 6)
        case .waiting:
            Text("queued")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ScopeInk.subtle)
        case .failed:
            Text("failed")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.red)
        case .done:
            EmptyView()
        }
    }
}

// MARK: - Idle hero (fresh conversation surface)

/// First-class surface for a fresh conversation. Borrows the "press to
/// transmit" idea from MacWalkie but quieted into something editorial
/// rather than instrumental:
///   - Headline is a question, not a command.
///   - One amber focal point (the mic disc); everything else is ink.
///   - Composer is *inside* the hero so the next action is obvious.
///   - Starters are conversational, not feature labels.
///
/// Studio reference: design/studio/components/studies/MacAgentHome.tsx
/// (the IdleHero / Starters / IdleMic group).
private struct AgentHomeIdleHero: View {
    @Binding var text: String
    let isSending: Bool
    let placeholder: String
    let continuation: AgentHomeContinuationContext?
    @ObservedObject var voiceCapture: AgentHomeVoiceCapture
    let error: String?
    var isFocused: FocusState<Bool>.Binding
    let onClearContinuation: () -> Void
    let onSend: () -> Void
    let onCancelTalkBack: () -> Void
    let onTalkBack: () -> Void
    let onStarter: (String) -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            AgentHomeIdleMic(phase: voiceCapture.phase, action: onTalkBack)

            VStack(spacing: 8) {
                Text("· NEW CONVERSATION")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)

                Text("What are you working on?")
                    .font(.system(size: 26, weight: .medium, design: .serif))
                    .foregroundStyle(ScopeInk.primary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 6) {
                    Text("click the mic, type here, or use")
                    AgentHomeKbd(label: "⌃⌥⌘T")
                    Text("anywhere")
                }
                .font(.system(size: 11.5))
                .foregroundStyle(ScopeInk.faint)
            }

            AgentHomeComposer(
                text: $text,
                isSending: isSending,
                placeholder: placeholder,
                continuation: continuation,
                voiceCapture: voiceCapture,
                error: error,
                isFocused: isFocused,
                onClearContinuation: onClearContinuation,
                onSend: onSend,
                onCancelTalkBack: onCancelTalkBack,
                onTalkBack: onTalkBack
            )
            .padding(.top, 12)

            AgentHomeStarters(onStarter: onStarter)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct AgentHomeIdleMic: View {
    let phase: AgentHomeVoiceCapture.Phase
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(ScopeAmber.glow)
                    .frame(width: 84, height: 84)
                    .blur(radius: 14)
                    .opacity(0.6)

                Circle()
                    .fill(ScopeAmber.solid)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: iconName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: ScopeAmber.solid.opacity(0.22), radius: 8, x: 0, y: 4)
                    .scaleEffect(hovered || phase == .recording ? 1.04 : 1.0)
            }
        }
        .buttonStyle(.plain)
        .disabled(phase == .processing)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.18), value: hovered || phase == .recording)
        .help(helpText)
    }

    private var iconName: String {
        switch phase {
        case .idle: return "mic.fill"
        case .recording: return "stop.fill"
        case .processing: return "hourglass"
        }
    }

    private var helpText: String {
        switch phase {
        case .idle: return "Record in Agent Home"
        case .recording: return "Stop and send"
        case .processing: return "Transcribing"
        }
    }
}

private struct AgentHomeKbd: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(ScopeInk.muted)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(ScopeEdge.subtle, lineWidth: 0.5)
            )
    }
}

private struct AgentHomeStarter: Identifiable {
    let id = UUID()
    let label: String
    let hint: String
}

private let AGENT_HOME_STARTERS: [AgentHomeStarter] = [
    .init(label: "Where did I leave off?",  hint: "recent activity"),
    .init(label: "Search my memos for …",   hint: "library"),
    .init(label: "What's in my tray?",      hint: "captures"),
]

private struct AgentHomeStarters: View {
    let onStarter: (String) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("· OR PICK UP SOMETHING")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.subtle)

            HStack(spacing: 6) {
                ForEach(AGENT_HOME_STARTERS) { starter in
                    AgentHomeStarterChip(starter: starter, onTap: { onStarter(starter.label) })
                }
            }
        }
    }
}

private struct AgentHomeStarterChip: View {
    let starter: AgentHomeStarter
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text(starter.label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(ScopeInk.muted)

                Text(starter.hint.uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(ScopeInk.subtle)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(hovered ? ScopeInk.primary.opacity(0.04) : Color.white)
            )
            .overlay(
                Capsule().stroke(ScopeEdge.subtle, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

// MARK: - Composer

private struct AgentHomeComposer: View {
    @Binding var text: String
    let isSending: Bool
    let placeholder: String
    let continuation: AgentHomeContinuationContext?
    @ObservedObject var voiceCapture: AgentHomeVoiceCapture
    let error: String?
    var isFocused: FocusState<Bool>.Binding
    let onClearContinuation: () -> Void
    let onSend: () -> Void
    let onCancelTalkBack: () -> Void
    let onTalkBack: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Button(action: onTalkBack) {
                    Image(systemName: voiceButtonIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ScopeBrass.solid)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(ScopeAmber.tint))
                }
                .buttonStyle(.plain)
                .disabled(voiceCapture.phase == .processing || isSending)
                .help(voiceButtonHelp)

                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(ScopeInk.primary)
                    .lineLimit(1...5)
                    .focused(isFocused)
                    .onSubmit { if canSend { onSend() } }

                Button(action: onSend) {
                    Image(systemName: isSending ? "hourglass" : "paperplane.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(canSend ? .white : ScopeInk.subtle)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle().fill(canSend ? ScopeAmber.solid : ScopeInk.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help("Send")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(ScopeEdge.faint, lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 1, x: 0, y: 1)
            .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 12)

            if showsVoiceStatus {
                AgentHomeVoiceCaptureStatus(
                    phase: voiceCapture.phase,
                    level: voiceCapture.level,
                    elapsed: voiceCapture.formattedElapsed,
                    error: voiceCapture.errorMessage,
                    onPrimary: onTalkBack,
                    onCancel: onCancelTalkBack
                )
                .padding(.leading, 40)
            }

            if let continuation {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text(continuation.label)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Button(action: onClearContinuation) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ScopeBrass.solid)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(ScopeAmber.tint))
                .padding(.leading, 40)
            }

            if let error, !error.isEmpty {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.leading, 40)
            }
        }
    }

    private var showsVoiceStatus: Bool {
        voiceCapture.phase != .idle || voiceCapture.errorMessage != nil
    }

    private var voiceButtonIcon: String {
        switch voiceCapture.phase {
        case .idle: return "mic.fill"
        case .recording: return "stop.fill"
        case .processing: return "hourglass"
        }
    }

    private var voiceButtonHelp: String {
        switch voiceCapture.phase {
        case .idle: return "Record a voice reply here"
        case .recording: return "Stop and send this voice reply"
        case .processing: return "Transcribing voice reply"
        }
    }
}

private struct AgentHomeVoiceCaptureStatus: View {
    let phase: AgentHomeVoiceCapture.Phase
    let level: Float
    let elapsed: String
    let error: String?
    let onPrimary: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AgentHomeVoiceMiniMeter(level: level, active: phase == .recording)
                .frame(width: 52, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(titleColor)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(ScopeInk.subtle)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if showsPrimaryButton {
                Button(action: onPrimary) {
                    Label(primaryLabel, systemImage: primaryIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(ScopeAmber.solid)
                        )
                }
                .buttonStyle(.plain)
                .help(primaryHelp)
            }

            if showsCancelButton {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(ScopeInk.subtle)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(ScopeInk.primary.opacity(0.04)))
                }
                .buttonStyle(.plain)
                .help("Cancel")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ScopeEdge.faint, lineWidth: 0.5)
        )
    }

    private var title: String {
        switch phase {
        case .recording: return "Listening \(elapsed)"
        case .processing: return "Transcribing voice reply"
        case .idle: return error == nil ? "Voice ready" : "Voice reply failed"
        }
    }

    private var detail: String? {
        if let error, !error.isEmpty { return error }
        switch phase {
        case .recording: return "Stop when you're done. This stays in Agent Home."
        case .processing: return "Talkie will add it as the next turn."
        case .idle: return nil
        }
    }

    private var titleColor: Color {
        phase == .idle && error != nil ? .red : ScopeInk.muted
    }

    private var showsPrimaryButton: Bool {
        phase == .recording || (phase == .idle && error != nil)
    }

    private var primaryLabel: String {
        phase == .recording ? "Stop & send" : "Try again"
    }

    private var primaryIcon: String {
        phase == .recording ? "stop.fill" : "mic.fill"
    }

    private var primaryHelp: String {
        phase == .recording ? "Stop recording and send" : "Record another voice reply"
    }

    private var showsCancelButton: Bool {
        phase == .recording || error != nil
    }
}

private struct AgentHomeVoiceMiniMeter: View {
    let level: Float
    let active: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let barCount = 14
                let spacing: CGFloat = 2
                let barWidth = max(1, (size.width - CGFloat(barCount - 1) * spacing) / CGFloat(barCount))
                let now = timeline.date.timeIntervalSinceReferenceDate
                let baseLevel = active ? max(0.08, CGFloat(level)) : 0.04

                for index in 0..<barCount {
                    let phase = Double(index) * 0.62 + now * 7.0
                    let pulse = active ? CGFloat((sin(phase) + 1.0) * 0.5) : 0
                    let height = max(3, size.height * (0.18 + baseLevel * (0.35 + pulse * 0.65)))
                    let x = CGFloat(index) * (barWidth + spacing)
                    let y = (size.height - height) / 2
                    let rect = CGRect(x: x, y: y, width: barWidth, height: height)
                    let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                    context.fill(path, with: .color(active ? ScopeAmber.solid : ScopeInk.subtle.opacity(0.45)))
                }
            }
        }
    }
}

#Preview {
    AgentHomeView(onDismiss: {}, onOpenSettings: {})
        .frame(width: 980, height: 700)
}
