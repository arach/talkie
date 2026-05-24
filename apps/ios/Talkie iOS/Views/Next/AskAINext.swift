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

                if networkStatus != .ok {
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
            consumePendingPrompt()
        }
        .onDisappear {
            chrome.voiceCommandHandler = { transcript in
                AppShellRouter.shared.submitVoiceCommand(transcript)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("TALKIE · ASK AI")
                .talkieType(.wordmark)
                .foregroundStyle(theme.colors.textPrimary.opacity(0.78))

            Spacer()

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
        VStack(spacing: 20) {
            Spacer(minLength: 36)

            Text("What would you like to ask?")
                .talkieType(.headline)
                .foregroundStyle(theme.colors.textPrimary)
                .multilineTextAlignment(.center)

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

            if let errorMessage = session.errorMessage {
                Text(errorMessage)
                    .talkieType(.hint)
                    .foregroundStyle(Color.recording)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

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

            TextField("Ask anything…", text: $session.prompt, axis: .vertical)
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .focused($isPromptFocused)
                .submitLabel(.send)
                .onSubmit(sendPrompt)
                .disabled(session.isThinking)

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
            isPromptFocused = true
        }
    }

    private func consumePendingPrompt() {
        guard let pending = AppShellRouter.shared.pendingAskAIPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pending.isEmpty
        else { return }

        session.receiveVoicePrompt(pending)
        isPromptFocused = true
        AppShellRouter.shared.pendingAskAIPrompt = nil
    }

    private func applyPreset(_ preset: AskAIPreset) {
        session.applyPreset(preset)
        isPromptFocused = true
    }

    /// Status the offline / request-failed banner observes. Paint-side
    /// derives this from session.errorMessage. Codex layers a real
    /// NetworkReachability observer on top to drive .offline when the
    /// device has lost the network entirely.
    private var networkStatus: NetworkStatus {
        if reachability.status == .offline {
            return .offline
        }
        if let message = session.errorMessage, !message.isEmpty {
            return .requestFailed(message: message)
        }
        return .ok
    }

    private func retrySend() {
        session.errorMessage = nil
        if !session.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           session.canSend {
            sendPrompt()
        }
    }

    private func sendPrompt() {
        guard session.canSend else { return }
        isPromptFocused = false
        session.send()
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard let id = session.lastTurnID else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }
}

@MainActor
private final class AskAISession: ObservableObject {
    @Published var turns: [AskAITurn] = []
    @Published var prompt = ""
    @Published var isThinking = false
    @Published var errorMessage: String?

    private let store = AskAISessionStore.shared
    private let bridgeManager = BridgeManager.shared
    private let appSettings = TalkieAppSettings.shared
    private var lastPreset: AskAIPreset?
    private var lastModel: String?

    var canSend: Bool {
        !isThinking && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var lastTurnID: AskAITurn.ID? { turns.last?.id }

    var nextTurnCode: String { Self.code(for: turns.count + 1) }

    init() {
        guard let snapshot = store.load() else { return }
        turns = snapshot.turns.filter { !$0.isThinking }
        lastPreset = snapshot.lastPreset
        lastModel = snapshot.lastModel
    }

    func receiveVoicePrompt(_ transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        prompt = trimmed
    }

    func applyPreset(_ preset: AskAIPreset) {
        prompt = preset.template
        lastPreset = preset
        persist()
    }

    func send() {
        let instruction = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty, !isThinking else { return }

        errorMessage = nil
        prompt = ""

        let userTurn = AskAITurn(
            code: Self.code(for: turns.count + 1),
            speaker: .user,
            body: instruction,
            createdAt: .now
        )
        turns.append(userTurn)

        let thinkingTurn = AskAITurn(
            code: Self.code(for: turns.count + 1),
            speaker: .talkie,
            body: "Thinking…",
            createdAt: .now,
            model: preferredModelLabel,
            latency: "0.0s",
            tokens: nil,
            isThinking: true
        )
        turns.append(thinkingTurn)
        isThinking = true
        persist()

        Task {
            let startedAt = Date()
            do {
                let result = try await runAI(instruction: instruction)
                let elapsed = Date().timeIntervalSince(startedAt)
                await MainActor.run {
                    replaceThinkingTurn(
                        id: thinkingTurn.id,
                        body: result.responseText,
                        providerName: result.providerName,
                        modelId: result.modelId,
                        latency: Self.latencyString(elapsed),
                        tokens: Self.estimatedTokens(for: result.responseText)
                    )
                    isThinking = false
                    persist()
                }
            } catch {
                await MainActor.run {
                    replaceThinkingTurn(
                        id: thinkingTurn.id,
                        body: "I couldn't complete that request. \(error.localizedDescription)",
                        providerName: "Talkie",
                        modelId: preferredModelLabel,
                        latency: Self.latencyString(Date().timeIntervalSince(startedAt)),
                        tokens: nil
                    )
                    errorMessage = error.localizedDescription
                    isThinking = false
                    persist()
                }
            }
        }
    }

    private func runAI(instruction: String) async throws -> CaptureAICommandResult {
        let context = conversationContext(excludingCurrentInstruction: instruction)

        if let phoneProvider = TalkieAIProviderResolver.shared.configuredProvider() {
            return try await CaptureAICommandService.shared.run(
                context: context,
                instruction: instruction,
                title: "Ask AI",
                sourceDescription: "Ask AI conversation",
                provider: phoneProvider
            )
        }

        if bridgeManager.isPaired {
            let provider = try await bridgeManager.composeBorrowedProvider(
                providerId: appSettings.composeDirectProviderId,
                modelId: appSettings.composeDirectModelId
            )
            return try await CaptureAICommandService.shared.run(
                context: context,
                instruction: instruction,
                title: "Ask AI",
                sourceDescription: "Ask AI conversation",
                provider: provider
            )
        }

        throw BridgeError.messageFailed("Set up AI credentials in Settings -> AI, or pair a Mac provider.")
    }

    private func conversationContext(excludingCurrentInstruction instruction: String) -> String {
        let priorTurns = turns.filter { turn in
            !(turn.speaker == .user && turn.body == instruction && !turn.isThinking)
        }

        guard !priorTurns.isEmpty else {
            return "No prior turns. Answer the user's first Ask AI prompt directly."
        }

        let transcript = priorTurns
            .filter { !$0.isThinking }
            .map { turn in
                "\(turn.speaker.label): \(turn.body)"
            }
            .joined(separator: "\n\n")

        return transcript.isEmpty
            ? "No prior turns. Answer the user's first Ask AI prompt directly."
            : transcript
    }

    private func replaceThinkingTurn(
        id: AskAITurn.ID,
        body: String,
        providerName: String,
        modelId: String,
        latency: String,
        tokens: Int?
    ) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        turns[index] = AskAITurn(
            id: id,
            code: turns[index].code,
            speaker: .talkie,
            body: body,
            createdAt: turns[index].createdAt,
            providerName: providerName,
            model: modelId,
            latency: latency,
            tokens: tokens,
            isThinking: false
        )
    }

    private var preferredModelLabel: String {
        TalkieAIProviderResolver.shared.configuredProvider()?.modelId
            ?? appSettings.composeDirectModelId
    }

    private func persist() {
        lastModel = preferredModelLabel
        let snapshot = AskAISessionSnapshot(
            turns: turns,
            lastPreset: lastPreset,
            lastModel: lastModel,
            lastTurnID: lastTurnID
        )
        Task { await store.save(snapshot) }
    }

    private static func code(for index: Int) -> String {
        "T" + String(index).leftPadded(toLength: 2, with: "0")
    }

    private static func latencyString(_ value: TimeInterval) -> String {
        max(0, value).formatted(.number.precision(.fractionLength(1))) + "s"
    }

    private static func estimatedTokens(for text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / 4.0)))
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
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    isLit = true
                }
            }
    }
}


private extension String {
    func leftPadded(toLength targetLength: Int, with character: Character) -> String {
        guard count < targetLength else { return self }
        return String(repeating: String(character), count: targetLength - count) + self
    }
}
