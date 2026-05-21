//
//  MemoAgentSheetNext.swift
//  Talkie iOS
//
//  Next-style multi-turn AI agent conversation for voice memos.
//

import SwiftUI

struct MemoAgentSheetNext: View {
    let memo: VoiceMemoDetailStore.MemoDisplay

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var dictation = MemoAgentDictationWrapper()

    @State private var instruction: String = ""
    @State private var agentState: AgentState = .idle
    @State private var streamingResponse: String = ""
    @State private var agentError: String?
    @State private var turns: [AgentTurn] = []
    @State private var claudeSessionId: String?
    @State private var handoffState: HandoffState = .idle

    private enum AgentState {
        case idle
        case sending
    }

    private enum HandoffState: Equatable {
        case idle
        case sending
        case done
        case error(String)
    }

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            memoContextCard

                            ForEach(turns) { turn in
                                turnBubble(turn)
                            }

                            if agentState == .sending && !streamingResponse.isEmpty {
                                streamingBubble
                            }

                            if agentState == .sending && streamingResponse.isEmpty {
                                typingIndicator
                            }

                            if let agentError {
                                errorCard(agentError)
                            }

                            if !turns.isEmpty && agentState == .idle {
                                scoutHandoffCard
                            }

                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: streamingResponse) {
                        scrollToBottom(proxy)
                    }
                    .onChange(of: turns.count) {
                        scrollToBottom(proxy)
                    }
                }

                inputBar
            }
        }
        .onAppear {
            setupDictation()
            loadSession()
        }
        .onDisappear {
            dictation.controller.cancel()
        }
    }

    private var header: some View {
        HStack {
            Button("Close") {
                dismiss()
            }
            .talkieType(.fieldLabel)
            .foregroundStyle(theme.colors.textSecondary)

            Spacer()

            VStack(spacing: 2) {
                Text("Memo Agent")
                    .talkieType(.headlineSecondary)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(connectionLabel)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(connectionColor)
            }

            Spacer()

            Text(turns.count.formatted(.number.precision(.integerLength(2))))
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: 44, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth),
            alignment: .bottom
        )
    }

    private var memoContextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.currentTheme.chrome.accent)

                Text(memo.title)
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text("PINNED")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
            }

            Text(memoTranscriptPreview)
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            theme.currentTheme.chrome.edgeFaint,
                            lineWidth: theme.currentTheme.chrome.hairlineWidth
                        )
                )
        )
    }

    private func turnBubble(_ turn: AgentTurn) -> some View {
        HStack {
            if turn.role == "user" { Spacer(minLength: 46) }

            VStack(alignment: turn.role == "user" ? .trailing : .leading, spacing: 5) {
                Text(turn.content)
                    .talkieType(.preview)
                    .foregroundStyle(turn.role == "user" ? theme.colors.cardBackground : theme.colors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: turn.role == "user" ? .trailing : .leading)

                Text(turn.timestamp, format: .dateTime.hour().minute())
                    .talkieType(.timestamp)
                    .foregroundStyle(turn.role == "user" ? theme.colors.cardBackground.opacity(0.72) : theme.colors.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(turn.role == "user" ? theme.currentTheme.chrome.accent : theme.colors.cardBackground)
            )

            if turn.role == "assistant" { Spacer(minLength: 46) }
        }
    }

    private var streamingBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(streamingResponse)
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 5) {
                    ProgressView()
                        .scaleEffect(0.55)
                    Text("STREAMING")
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 16).fill(theme.colors.cardBackground))

            Spacer(minLength: 46)
        }
    }

    private var typingIndicator: some View {
        HStack {
            HStack(spacing: 7) {
                ProgressView()
                    .scaleEffect(0.65)
                Text("Thinking…")
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 16).fill(theme.colors.cardBackground))

            Spacer(minLength: 46)
        }
    }

    private func errorCard(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
            Text(text)
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textSecondary)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.colors.cardBackground))
    }

    private var scoutHandoffCard: some View {
        Button(action: handoffToScout) {
            HStack(spacing: 8) {
                switch handoffState {
                case .idle:
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                    Text("Continue in Scout")
                        .talkieType(.fieldLabel)
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.colors.textTertiary)
                case .sending:
                    ProgressView().scaleEffect(0.65)
                    Text("Handing off…")
                        .talkieType(.fieldLabel)
                        .foregroundStyle(theme.colors.textSecondary)
                    Spacer()
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.green)
                    Text("Handed off to Scout")
                        .talkieType(.fieldLabel)
                        .foregroundStyle(.green)
                    Spacer()
                case .error(let message):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text(message)
                        .talkieType(.fieldLabel)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(2)
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(theme.colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                theme.currentTheme.chrome.edgeFaint,
                                lineWidth: theme.currentTheme.chrome.hairlineWidth
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(handoffState == .sending || handoffState == .done)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 9) {
            Button(action: toggleDictation) {
                Image(systemName: dictation.state == .recording ? "stop.circle.fill" : "mic.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(dictation.state == .recording ? Color.red : theme.colors.textSecondary)
                    .frame(width: 32, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(agentState == .sending || dictation.state == .transcribing)

            ZStack(alignment: .leading) {
                if dictation.state == .recording {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text("Listening…")
                            .talkieType(.preview)
                            .foregroundStyle(Color.red)
                    }
                    .padding(.horizontal, 10)
                } else if dictation.state == .transcribing {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.58)
                        Text("Transcribing…")
                            .talkieType(.preview)
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                    .padding(.horizontal, 10)
                } else {
                    TextField(turns.isEmpty ? "Ask about this memo…" : "Follow up…", text: $instruction, axis: .vertical)
                        .talkieType(.preview)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1...4)
                        .disabled(agentState == .sending)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                }
            }
            .frame(minHeight: 38)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                theme.currentTheme.chrome.edgeFaint,
                                lineWidth: theme.currentTheme.chrome.hairlineWidth
                            )
                    )
            )

            Button(action: sendToAgent) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(canSend ? theme.currentTheme.chrome.accent : theme.colors.textTertiary.opacity(0.45))
                    .frame(width: 32, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.colors.background)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth),
            alignment: .top
        )
    }

    private var memoTranscriptPreview: String {
        let text = memo.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "No transcript yet." }
        let prefix = text.prefix(240)
        return String(prefix) + (text.count > 240 ? "…" : "")
    }

    private var canSend: Bool {
        agentState == .idle
        && dictation.state == .idle
        && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var connectionLabel: String {
        if BridgeManager.shared.status == .connected { return "MAC CONNECTED" }
        if BridgeManager.shared.isPaired { return "MAC PAIRED" }
        return "PAIR MAC TO STREAM"
    }

    private var connectionColor: Color {
        if BridgeManager.shared.status == .connected { return .green }
        if BridgeManager.shared.isPaired { return theme.currentTheme.chrome.accent }
        return theme.colors.textTertiary
    }

    private func loadSession() {
        guard let session = AgentSessionStore.shared.existingSession(forMemoId: memo.id) else { return }
        turns = session.turns
        claudeSessionId = session.claudeSessionId
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
            Task {
                await dictation.controller.start()
            }
        }
    }

    private func sendToAgent() {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard BridgeManager.shared.isPaired else {
            agentError = "Pair a Talkie Mac to use the memo agent."
            return
        }

        let userTurn = AgentTurn(role: "user", content: trimmed)
        turns.append(userTurn)
        _ = AgentSessionStore.shared.session(forMemoId: memo.id, memoTitle: memo.title)
        AgentSessionStore.shared.addUserTurn(memoId: memo.id, content: trimmed)

        let sentInstruction = trimmed
        let memoID = memo.id
        let memoTitle = memo.title
        let memoTranscript = memo.transcript
        let existingSessionID = claudeSessionId
        instruction = ""
        agentState = .sending
        agentError = nil
        streamingResponse = ""
        handoffState = .idle

        let prompt = promptForAgent(
            instruction: sentInstruction,
            memoTitle: memoTitle,
            memoTranscript: memoTranscript,
            isFirstTurn: existingSessionID == nil
        )

        Task { @MainActor in
            do {
                if BridgeManager.shared.status != .connected {
                    await BridgeManager.shared.connect()
                }
                guard BridgeManager.shared.status == .connected else {
                    throw BridgeError.connectionFailed
                }

                let result = try await BridgeManager.shared.client.headlessStream(
                    message: prompt,
                    sessionId: existingSessionID
                ) { chunk in
                    Task { @MainActor in
                        streamingResponse += chunk
                    }
                }

                if streamingResponse.isEmpty {
                    agentError = "No response from agent."
                } else {
                    let assistantText = streamingResponse
                    let assistantTurn = AgentTurn(role: "assistant", content: assistantText)
                    turns.append(assistantTurn)
                    AgentSessionStore.shared.addAssistantTurn(memoId: memoID, content: assistantText)

                    if let sessionID = result.sessionId, claudeSessionId == nil {
                        claudeSessionId = sessionID
                        AgentSessionStore.shared.setClaudeSessionId(sessionID, forMemoId: memoID)
                    }
                }

                streamingResponse = ""
                agentState = .idle
            } catch {
                agentError = error.localizedDescription
                streamingResponse = ""
                agentState = .idle
            }
        }
    }

    private func promptForAgent(
        instruction: String,
        memoTitle: String,
        memoTranscript: String,
        isFirstTurn: Bool
    ) -> String {
        if !isFirstTurn {
            return instruction
        }

        return """
        The user has a voice memo and wants you to process it. Here is the memo:

        Title: \(memoTitle)

        Transcript:
        \(memoTranscript)

        User instruction:
        \(instruction)

        Respond directly with the result. Be concise.
        """
    }

    private func handoffToScout() {
        guard !turns.isEmpty else { return }
        guard BridgeManager.shared.isPaired else {
            handoffState = .error("Pair a Talkie Mac first.")
            return
        }

        let memoID = memo.id
        let memoTitle = memo.title
        let memoTranscript = memo.transcript
        let conversationTurns = turns
        let sessionID = claudeSessionId
        handoffState = .sending

        Task { @MainActor in
            do {
                if BridgeManager.shared.status != .connected {
                    await BridgeManager.shared.connect()
                }
                guard BridgeManager.shared.status == .connected else {
                    throw BridgeError.connectionFailed
                }

                let response = try await BridgeManager.shared.client.handoffToScout(
                    memoId: memoID,
                    memoTitle: memoTitle,
                    memoTranscript: memoTranscript,
                    turns: conversationTurns,
                    claudeSessionId: sessionID
                )

                handoffState = response.success
                    ? .done
                    : .error(response.error ?? "Handoff failed")
            } catch {
                handoffState = .error(error.localizedDescription)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

@MainActor
private final class MemoAgentDictationWrapper: ObservableObject {
    let controller = InlineDictationController()
    @Published var state: InlineDictationController.State = .idle
}
