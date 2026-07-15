//
//  AskAINext.swift
//  Talkie iOS
//
//  Agentic Ask AI loop surface for the Next shell.
//

import SwiftUI

struct AskAINext: View {
    @EnvironmentObject private var chrome: ShellChrome
    @FocusState private var isPromptFocused: Bool
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var session = AskAISession()
    @ObservedObject private var reachability = NetworkReachability.shared
    @ObservedObject private var credentials = AICredentialStore.shared
    @State private var bridgeManager = BridgeManager.shared
    @State private var showingAIKeys = false

    private let presets: [AskAIPreset] = [
        AskAIPreset(
            title: "Summarize",
            template: "Summarize this in five crisp bullets: "
        ),
        AskAIPreset(
            title: "Action items",
            template: "Extract action items, owners, and due dates from this: "
        ),
        AskAIPreset(
            title: "Rewrite",
            template: "Rewrite this to be clearer and more direct: "
        ),
        AskAIPreset(
            title: "Explain",
            template: "Explain this simply, with one example: "
        ),
    ]

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                divider

                if let configurationRecovery {
                    AskAIRecoveryBanner(
                        headline: configurationRecovery.headline,
                        detail: configurationRecovery.detail,
                        onOpenAIKeys: { showingAIKeys = true },
                        onPairMac: openMacPairing
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .transition(.opacity)
                } else if networkStatus != .ok {
                    NetworkStatusBanner(status: networkStatus, onRetry: retrySend)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .transition(.opacity)
                }

                conversationArea
                promptBar
            }
            .animation(.easeInOut(duration: 0.18), value: networkStatus)
        }
        .onAppear {
            bindShellVoice()
            consumePendingRequest()
        }
        .onDisappear {
            session.persistDraft()
            chrome.voiceCommandHandler = { transcript in
                AppShellRouter.shared.submitVoiceCommand(transcript)
            }
        }
        .sheet(isPresented: $showingAIKeys, onDismiss: {
            if session.readiness.isReady {
                session.clearResolvedConfigurationFailure()
                isPromptFocused = true
            }
        }) {
            AICredentialsNext(onClose: { showingAIKeys = false })
        }
    }

    private var header: some View {
        HStack {
            Text("TALKIE · ASK AI")
                .talkieType(.wordmark)
                .foregroundStyle(theme.colors.textPrimary.opacity(0.78))
                .accessibilityIdentifier("askai.header")

            Spacer()

            if !session.turns.isEmpty {
                Button(action: startNewConversation) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(theme.currentTheme.chrome.accent.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Ask AI conversation")
            }

            Button(action: { AppShellRouter.shared.openHome() }) {
                Text("×")
                    .talkieType(.chipLabel)
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(theme.currentTheme.chrome.edgeFaint.opacity(0.5))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Ask AI")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.currentTheme.chrome.edgeFaint)
            .frame(height: theme.currentTheme.chrome.hairlineWidth)
    }

    @ViewBuilder
    private var conversationArea: some View {
        if session.turns.isEmpty {
            idleState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(session.turns) { turn in
                            AskAITurnRow(turn: turn)
                                .id(turn.id)
                        }
                    }
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: session.turns.count) { _, _ in
                    scrollToLatest(proxy)
                }
                .onChange(of: session.lastTurnID) { _, _ in
                    scrollToLatest(proxy)
                }
            }
        }
    }

    private var idleState: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 36)

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                Text("ASK TALKIE")
                    .talkieType(.channelLabelTiny)
            }
            .foregroundStyle(theme.currentTheme.chrome.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(theme.currentTheme.chrome.accent.opacity(0.1))
                    .overlay {
                        Capsule().strokeBorder(
                            theme.currentTheme.chrome.accent.opacity(0.3),
                            lineWidth: theme.currentTheme.chrome.hairlineWidth
                        )
                    }
            }

            Text("What can I help move forward?")
                .talkieType(.headline)
                .foregroundStyle(theme.colors.textPrimary)
                .multilineTextAlignment(.center)

            Text("Ask a question, shape a rough thought, or turn it into a next step.")
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(presets) { preset in
                    Button(action: { applyPreset(preset) }) {
                        Text(preset.title)
                            .talkieType(.chipLabel)
                            .foregroundStyle(theme.colors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(theme.colors.cardBackground)
                            .clipShape(.rect(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(
                                        theme.currentTheme.chrome.edgeFaint,
                                        lineWidth: theme.currentTheme.chrome.hairlineWidth
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 260)

            Text("OR · TYPE · DICTATE · ATTACH ·")
                .talkieType(.channelLabelSmall)
                .foregroundStyle(theme.colors.textTertiary)

            Spacer(minLength: 48)
        }
        .padding(.horizontal, 24)
    }

    private var promptBar: some View {
        HStack(spacing: 10) {
            Text(session.nextTurnCode)
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .strokeBorder(
                            theme.currentTheme.chrome.accent.opacity(0.55),
                            lineWidth: theme.currentTheme.chrome.hairlineWidth
                        )
                )

            TextField(
                "Ask anything…",
                text: Binding(
                    get: { session.prompt },
                    set: { session.updatePrompt($0) }
                ),
                axis: .vertical
            )
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .focused($isPromptFocused)
                .submitLabel(.send)
                .onSubmit(sendPrompt)
                .disabled(session.isThinking)
                .accessibilityIdentifier("askai.prompt-field")

            Button(action: sendPrompt) {
                Text("SEND")
                    .talkieType(.chipLabel)
                    .foregroundStyle(theme.colors.cardBackground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(theme.currentTheme.chrome.accent))
                    .shadow(color: theme.currentTheme.chrome.accentGlow, radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(!session.canSend)
            .opacity(session.canSend ? 1 : 0.45)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .padding(.bottom, 76)
        .background(
            Rectangle()
                .fill(theme.colors.background.opacity(0.96))
                .overlay(alignment: .top) { divider }
        )
    }

    private func bindShellVoice() {
        chrome.voiceCommandHandler = { transcript in
            session.receiveVoicePrompt(transcript)
            session.send()
        }
    }

    private func consumePendingRequest() {
        guard let request = AppShellRouter.shared.pendingAskAIRequest else { return }
        AppShellRouter.shared.pendingAskAIRequest = nil

        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        if request.startsNewSession {
            session.reset()
        }
        session.receiveVoicePrompt(prompt)

        if request.autoSend {
            session.send()
        } else {
            isPromptFocused = true
        }
    }

    private func startNewConversation() {
        session.reset()
        isPromptFocused = true
    }

    private func applyPreset(_ preset: AskAIPreset) {
        session.applyPreset(preset)
        isPromptFocused = true
    }

    private var configurationRecovery: (headline: String, detail: String)? {
        _ = credentials.setProviderIDs
        _ = bridgeManager.isPaired

        if case .credentialsRejected(let providerName) = session.failure {
            return (
                "Update \(providerName) access",
                session.failure?.localizedDescription ?? "The saved credential needs attention."
            )
        }

        if session.failure == .configurationRequired || !session.readiness.isReady {
            return (
                "Connect an AI provider",
                "Add a key on this iPhone or pair a Mac. Your prompt will stay here while you set it up."
            )
        }

        return nil
    }

    private var networkStatus: NetworkStatus {
        if reachability.status == .offline {
            return .offline
        }
        if let failure = session.failure, !failure.needsConfiguration {
            return .requestFailed(message: failure.localizedDescription)
        }
        return .ok
    }

    private func retrySend() {
        session.retry()
    }

    private func sendPrompt() {
        guard session.canSend else {
            session.send()
            return
        }
        isPromptFocused = false
        session.send()
    }

    private func openMacPairing() {
        session.persistDraft()
        AppShellRouter.shared.openConnectionCenter()
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard let id = session.lastTurnID else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }
}

struct AskAIPreset: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let template: String

    init(id: UUID = UUID(), title: String, template: String) {
        self.id = id
        self.title = title
        self.template = template
    }
}

struct AskAITurn: Identifiable, Codable, Equatable {
    enum Speaker: Codable, Equatable {
        case user
        case talkie

        var label: String {
            switch self {
            case .user: return "USER"
            case .talkie: return "TALKIE"
            }
        }
    }

    let id: UUID
    let code: String
    let speaker: Speaker
    let body: String
    let createdAt: Date
    let providerName: String?
    let model: String?
    let latency: String?
    let tokens: Int?
    let isThinking: Bool

    init(
        id: UUID = UUID(),
        code: String,
        speaker: Speaker,
        body: String,
        createdAt: Date,
        providerName: String? = nil,
        model: String? = nil,
        latency: String? = nil,
        tokens: Int? = nil,
        isThinking: Bool = false
    ) {
        self.id = id
        self.code = code
        self.speaker = speaker
        self.body = body
        self.createdAt = createdAt
        self.providerName = providerName
        self.model = model
        self.latency = latency
        self.tokens = tokens
        self.isThinking = isThinking
    }
}

private struct AskAITurnRow: View {
    let turn: AskAITurn

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                Text(turn.code)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(turn.speaker == .talkie ? theme.currentTheme.chrome.accent : theme.colors.textTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .strokeBorder(
                                turn.speaker == .talkie
                                    ? theme.currentTheme.chrome.accent.opacity(0.75)
                                    : theme.currentTheme.chrome.edgeFaint,
                                lineWidth: theme.currentTheme.chrome.hairlineWidth
                            )
                    )

                Text("· \(turn.speaker.label)")
                    .talkieType(.channelLabelSmall)
                    .foregroundStyle(theme.colors.textTertiary)

                Spacer(minLength: 8)

                Text(metaText)
                    .talkieType(.timestamp)
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            if turn.isThinking {
                HStack(spacing: 6) {
                    Text(turn.body)
                        .talkieType(.preview)
                        .italic()
                    PulsingAccentDot()
                }
                .foregroundStyle(theme.colors.textTertiary)
            } else {
                Text(turn.body)
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineSpacing(3)
                    .textSelection(.enabled)

                if turn.speaker == .talkie {
                    nextActionRow
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth)
        }
    }

    /// Save as memo · Listen · Refine — the canonical post-response
    /// affordance row that lets the user act on a TALKIE turn without
    /// leaving the surface. Each chip routes through AppShellRouter
    /// so the surface itself stays paint-only.
    private var nextActionRow: some View {
        HStack(spacing: 6) {
            nextActionChip(systemImage: "tray.and.arrow.down", label: "Save as memo") {
                AppShellRouter.shared.saveAsMemo(text: turn.body)
            }
            nextActionChip(systemImage: "play.circle", label: "Listen") {
                AppShellRouter.shared.openReadAloud(source: ReadAloudSource(
                    title: "Ask AI · \(turn.code)",
                    text: turn.body,
                    meta: "ASK AI · \(turn.model ?? turn.providerName ?? "TALKIE")",
                    sourceURL: nil
                ))
            }
            nextActionChip(systemImage: "pencil.line", label: "Refine") {
                AppShellRouter.shared.openComposeSeeded(text: turn.body)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private func nextActionChip(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .talkieType(.chipLabel)
            }
            .foregroundStyle(theme.currentTheme.chrome.accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .strokeBorder(
                        theme.currentTheme.chrome.accent.opacity(0.6),
                        lineWidth: theme.currentTheme.chrome.hairlineWidth
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var metaText: String {
        let timestamp = turn.createdAt.formatted(.dateTime.hour().minute())
        guard turn.speaker == .talkie else { return timestamp }

        var parts = [timestamp]
        if let model = turn.model, !model.isEmpty {
            parts.append(model)
        } else if let providerName = turn.providerName, !providerName.isEmpty {
            parts.append(providerName)
        }
        if let latency = turn.latency, !latency.isEmpty {
            parts.append(latency)
        }
        if let tokens = turn.tokens {
            parts.append("\(tokens)t")
        }
        return parts.joined(separator: " · ")
    }
}

private struct PulsingAccentDot: View {
    @State private var isLit = false
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Circle()
            .fill(theme.currentTheme.chrome.accent)
            .frame(width: 6, height: 6)
            .opacity(isLit ? 1 : 0.25)
            .scaleEffect(isLit ? 1.15 : 0.72)
            .onAppear {
                if TalkieMotion.isReduced {
                    isLit = true  // statically lit, no pulse
                } else {
                    withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                        isLit = true
                    }
                }
            }
    }
}
