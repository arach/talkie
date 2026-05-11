//
//  MemoAgentSheet.swift
//  Talkie iOS
//
//  Multi-turn AI agent conversation for memos.
//  Tap mic → speak instruction → Talkie transcribes → sends to Claude Code
//  via bridge headless endpoint with memo transcript as context.
//  Captures Claude session ID for multi-turn follow-ups.
//

import SwiftUI

struct MemoAgentSheet: View {
    let memoTitle: String
    let memoTranscript: String
    let memoId: String?

    @Environment(\.dismiss) private var dismiss
    @State private var instruction = ""
    @State private var agentState: AgentState = .idle
    @State private var streamingResponse = ""
    @State private var agentError: String?
    @State private var turns: [AgentTurn] = []
    @State private var claudeSessionId: String?

    @State private var handoffState: HandoffState = .idle

    @StateObject private var dictation = DictationWrapper()
    private let bridge = BridgeManager.shared

    private enum AgentState {
        case idle
        case sending
    }

    private enum HandoffState {
        case idle
        case sending
        case done
        case error(String)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Conversation area
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: Spacing.sm) {
                            // Memo context (pinned at top)
                            memoContextCard

                            // Conversation turns
                            ForEach(turns) { turn in
                                turnBubble(turn)
                            }

                            // Live streaming response
                            if agentState == .sending && !streamingResponse.isEmpty {
                                streamingBubble
                            }

                            // Typing indicator
                            if agentState == .sending && streamingResponse.isEmpty {
                                typingIndicator
                            }

                            if let error = agentError {
                                errorCard(error)
                            }

                            // Scout handoff
                            if !turns.isEmpty && agentState == .idle {
                                scoutHandoffCard
                            }

                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.sm)
                        .padding(.bottom, Spacing.md)
                    }
                    .onChange(of: streamingResponse) { _ in
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: turns.count) { _ in
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }

                Divider()

                // Input bar
                inputBar
            }
            .navigationTitle("Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                setupDictation()
                loadSession()
            }
        }
    }

    // MARK: - Memo Context

    private var memoContextCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                Text(memoTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
            }

            Text(memoTranscript.prefix(200) + (memoTranscript.count > 200 ? "..." : ""))
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
    }

    // MARK: - Conversation Turns

    private func turnBubble(_ turn: AgentTurn) -> some View {
        HStack {
            if turn.role == "user" { Spacer(minLength: 48) }

            VStack(alignment: turn.role == "user" ? .trailing : .leading, spacing: 4) {
                Text(turn.content)
                    .font(.system(size: 14))
                    .foregroundStyle(turn.role == "user" ? .white : Color.textPrimary)
                    .textSelection(.enabled)

                Text(turn.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(turn.role == "user" ? .white.opacity(0.7) : Color.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(turn.role == "user" ? Color.accentColor : Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if turn.role == "assistant" { Spacer(minLength: 48) }
        }
    }

    private var streamingBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(streamingResponse)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textPrimary)
                    .textSelection(.enabled)

                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.5)
                    Text("streaming...")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Spacer(minLength: 48)
        }
    }

    private var typingIndicator: some View {
        HStack {
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.7)
                Text("Thinking...")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Spacer(minLength: 48)
        }
    }

    private func errorCard(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
    }

    // MARK: - Scout Handoff

    private var scoutHandoffCard: some View {
        Button {
            handoffToScout()
        } label: {
            HStack(spacing: 8) {
                switch handoffState {
                case .idle:
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    Text("Continue in Scout")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                case .sending:
                    ProgressView().scaleEffect(0.7)
                    Text("Handing off...")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                    Text("Handed off to Scout")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.green)
                    Spacer()
                case .error(let msg):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                    Text(msg)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
        }
        .buttonStyle(.plain)
        .disabled({
            switch handoffState {
            case .sending, .done: return true
            default: return false
            }
        }())
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            // Mic button
            Button {
                toggleDictation()
            } label: {
                Image(systemName: dictation.state == .recording ? "stop.circle.fill" : "mic.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(dictation.state == .recording ? Color.recording : Color.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(agentState == .sending || dictation.state == .transcribing)

            // Text field
            ZStack(alignment: .leading) {
                if instruction.isEmpty && dictation.state != .recording {
                    Text(turns.isEmpty ? "Ask about this memo..." : "Follow up...")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textTertiary)
                }

                if dictation.state == .recording {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.recording)
                            .frame(width: 6, height: 6)
                        Text("Listening...")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.recording)
                    }
                } else if dictation.state == .transcribing {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.6)
                        Text("Transcribing...")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.textTertiary)
                    }
                } else {
                    TextField("", text: $instruction, axis: .vertical)
                        .font(.system(size: 14))
                        .lineLimit(1...4)
                        .disabled(agentState == .sending)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Send button
            Button {
                sendToAgent()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(canSend ? Color.accentColor : Color.textTertiary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .background(Color.surfacePrimary)
    }

    private var canSend: Bool {
        agentState == .idle
        && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && bridge.status == .connected
    }

    // MARK: - Actions

    private func loadSession() {
        guard let memoId = memoId else { return }
        Task { @MainActor in
            if let session = AgentSessionStore.shared.existingSession(forMemoId: memoId) {
                turns = session.turns
                claudeSessionId = session.claudeSessionId
            }
        }
    }

    private func setupDictation() {
        dictation.controller.onStateChange = { [weak dictation] state in
            dictation?.state = state
        }
        dictation.controller.onTranscript = { transcript in
            instruction = transcript
        }
        dictation.controller.onError = { error in
            agentError = error
        }
    }

    private func toggleDictation() {
        if dictation.state == .recording {
            dictation.controller.stop(insertTranscript: true)
        } else {
            instruction = ""
            agentError = nil
            Task { await dictation.controller.start() }
        }
    }

    private func sendToAgent() {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let memoId = memoId else { return }

        guard bridge.status == .connected else {
            agentError = "Not connected to Mac. Check your pairing."
            return
        }

        // Record user turn
        let userTurn = AgentTurn(role: "user", content: trimmed)
        turns.append(userTurn)
        AgentSessionStore.shared.session(forMemoId: memoId, memoTitle: memoTitle)
        AgentSessionStore.shared.addUserTurn(memoId: memoId, content: trimmed)

        let sentInstruction = trimmed
        instruction = ""
        agentState = .sending
        agentError = nil
        streamingResponse = ""

        // Build prompt — include transcript context only on first turn
        let prompt: String
        if claudeSessionId == nil {
            prompt = """
            The user has a voice memo and wants you to process it. Here is the memo:

            **Title:** \(memoTitle)
            **Transcript:**
            \(memoTranscript)

            **User's instruction:** \(sentInstruction)

            Respond directly with the result. Be concise.
            """
        } else {
            prompt = sentInstruction
        }

        Task {
            do {
                let result = try await bridge.client.headlessStream(
                    message: prompt,
                    sessionId: claudeSessionId
                ) { chunk in
                    Task { @MainActor in
                        streamingResponse += chunk
                    }
                }

                await MainActor.run {
                    if streamingResponse.isEmpty {
                        agentError = "No response from agent"
                        agentState = .idle
                    } else {
                        // Save assistant turn
                        let assistantTurn = AgentTurn(role: "assistant", content: streamingResponse)
                        turns.append(assistantTurn)
                        AgentSessionStore.shared.addAssistantTurn(memoId: memoId, content: streamingResponse)

                        // Capture session ID for follow-ups
                        if let sid = result.sessionId, claudeSessionId == nil {
                            claudeSessionId = sid
                            AgentSessionStore.shared.setClaudeSessionId(sid, forMemoId: memoId)
                        }

                        streamingResponse = ""
                        agentState = .idle
                    }
                }
            } catch {
                await MainActor.run {
                    agentError = error.localizedDescription
                    streamingResponse = ""
                    agentState = .idle
                }
            }
        }
    }

    private func handoffToScout() {
        guard let memoId = memoId else { return }
        guard !turns.isEmpty else { return }

        handoffState = .sending

        Task {
            do {
                let response = try await bridge.client.handoffToScout(
                    memoId: memoId,
                    memoTitle: memoTitle,
                    memoTranscript: memoTranscript,
                    turns: turns,
                    claudeSessionId: claudeSessionId
                )

                await MainActor.run {
                    if response.success {
                        handoffState = .done
                    } else {
                        handoffState = .error(response.error ?? "Handoff failed")
                    }
                }
            } catch {
                await MainActor.run {
                    handoffState = .error(error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Dictation Wrapper

/// ObservableObject wrapper for InlineDictationController so SwiftUI can
/// observe state changes via @StateObject (the controller itself is not Observable).
@MainActor
private class DictationWrapper: ObservableObject {
    let controller = InlineDictationController()
    @Published var state: InlineDictationController.State = .idle
}
