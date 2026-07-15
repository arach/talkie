//
//  AskAINext.swift
//  Talkie iOS
//
//  Agentic Ask AI loop surface for the Next shell.
//

import AVFoundation
import Combine
import SwiftUI

struct AskAINext: View {
    @EnvironmentObject private var chrome: ShellChrome
    @FocusState private var isPromptFocused: Bool
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var session = AskAISession()
    @StateObject private var dictation = AskDictationController()
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
            dictation.cancel()
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

            Text("OR · TYPE · DICTATE ·")
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

            // The center slot is shared: text field at rest, live mag-tape
            // strip while dictating/transcribing, and a brief "DIDN'T CATCH
            // THAT" beat when a voice turn produced nothing usable.
            Group {
                switch dictation.phase {
                case .recording, .transcribing:
                    AskDictationStrip(
                        levels: dictation.levels,
                        elapsed: dictation.elapsed,
                        transcribing: dictation.phase == .transcribing
                    )
                case .missed:
                    Text("DIDN'T CATCH THAT")
                        .talkieType(.chipLabel)
                        .foregroundStyle(AskDictationStrip.amber)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .idle:
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
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.16), value: dictation.phase)

            micButton

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
            .disabled(!sendEnabled)
            .opacity(sendEnabled ? 1 : 0.45)
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

    /// SEND is a typed-input affordance; it stays dark while dictating so
    /// the two paths don't fight over the same beat.
    private var sendEnabled: Bool {
        session.canSend && !dictation.isBusy
    }

    /// Tap-to-toggle dictation mic — start on first tap, stop + transcribe
    /// + auto-send on the second. Disabled while a response is in flight
    /// (guardrail: no overlapping turns) and during the transcribe beat.
    private var micButton: some View {
        Button(action: toggleDictation) {
            Image(systemName: dictation.phase == .recording ? "stop.fill" : "mic.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(micTint)
                .frame(width: 42, height: 42)
                .background(Circle().fill(micFill))
                .overlay(
                    Circle().strokeBorder(micStroke, lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        }
        .buttonStyle(.plain)
        .disabled(!micEnabled)
        .opacity(micEnabled ? 1 : 0.4)
        .accessibilityLabel(dictation.phase == .recording ? "Stop dictation" : "Dictate")
    }

    /// The mic can be tapped from idle/missed (to arm) and while recording
    /// (to stop). It's locked while a send is in flight and during the
    /// transcribe hand-off so a stray tap can't start a competing capture.
    private var micEnabled: Bool {
        guard !session.isThinking else { return false }
        return dictation.phase != .transcribing
    }

    private var micTint: Color {
        switch dictation.phase {
        case .recording: return theme.colors.cardBackground
        case .transcribing, .missed: return AskDictationStrip.amber
        case .idle: return theme.currentTheme.chrome.accent
        }
    }

    private var micFill: Color {
        dictation.phase == .recording ? AskDictationStrip.amber : .clear
    }

    private var micStroke: Color {
        switch dictation.phase {
        case .recording: return AskDictationStrip.amber
        case .transcribing, .missed: return AskDictationStrip.amber.opacity(0.6)
        case .idle: return theme.currentTheme.chrome.accent.opacity(0.55)
        }
    }

    private func toggleDictation() {
        switch dictation.phase {
        case .idle, .missed:
            guard !session.isThinking else { return }
            isPromptFocused = false
            dictation.start()
        case .recording:
            dictation.stop { transcript in
                guard let transcript else { return }
                session.submitVoiceTranscript(transcript)
            }
        case .transcribing:
            break
        }
    }

    private func bindShellVoice() {
        // The shell long-press pivot only ever produces voice transcripts,
        // so anything arriving here is voice-originated: send it straight
        // through as a turn instead of parking it in the composer.
        chrome.voiceCommandHandler = { transcript in
            isPromptFocused = false
            session.submitVoiceTranscript(transcript)
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

        if request.autoSend {
            session.submitVoiceTranscript(prompt)
        } else {
            session.receiveVoicePrompt(prompt)
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


// MARK: - Ask-scoped dictation

/// Tap-to-toggle dictation for the Ask composer. Owns a single
/// `AudioRecorderManager` (the same capture stack the shell pivot and the
/// memo recorder use — no new recording engine) and drives a compact live
/// state off its metering. On stop it transcribes with the `.keyboard`
/// use case and hands the transcript back so the caller can auto-send.
///
/// Deliberately drives the live visual from the recorder's own metered
/// `audioLevels` / `recordingDuration` rather than `DictationMicMonitor`:
/// the monitor installs a second `AVAudioEngine` input tap and flips the
/// shared `AVAudioSession` to `.measurement`, which would contend with the
/// `AVAudioRecorder` writing the file we need for transcription. The
/// recorder already exposes a smoothed envelope, so we reuse it.
@MainActor
private final class AskDictationController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case missed
    }

    @Published private(set) var phase: Phase = .idle
    /// Tail of the recorder's smoothed envelope, throttled to ~30Hz so the
    /// strip re-renders calmly rather than at the 60fps metering cadence.
    @Published private(set) var levels: [Float] = []
    @Published private(set) var elapsed: TimeInterval = 0

    /// How many bars the compact strip shows — one per recent envelope
    /// sample, newest on the right.
    static let barCount = 28

    private let recorder = AudioRecorderManager()
    private var bag = Set<AnyCancellable>()
    private var missedResetTask: Task<Void, Never>?

    /// True while the mic owns the beat — used to hold SEND dark and to
    /// keep the composer showing the live strip.
    var isBusy: Bool { phase == .recording || phase == .transcribing }

    init() {
        recorder.$audioLevels
            .throttle(for: .milliseconds(33), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] samples in
                self?.levels = Array(samples.suffix(Self.barCount))
            }
            .store(in: &bag)

        recorder.$recordingDuration
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] duration in
                self?.elapsed = duration
            }
            .store(in: &bag)
    }

    // MARK: Toggle

    func start() {
        guard phase == .idle || phase == .missed else { return }
        missedResetTask?.cancel()

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            beginRecording()
        case .undetermined:
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor in
                    granted ? self.beginRecording() : self.failSoftPermission()
                }
            }
        case .denied:
            failSoftPermission()
        @unknown default:
            failSoftPermission()
        }
    }

    func stop(completion: @MainActor @escaping (String?) -> Void) {
        guard phase == .recording else { return }
        phase = .transcribing
        Haptics.transition.fire()

        recorder.stopRecording()
        let url = recorder.currentRecordingURL
        recorder.finalizeRecording()

        guard let url else {
            finishMissed()
            completion(nil)
            return
        }

        Task { @MainActor in
            let transcript = try? await TranscriptionService.shared.transcribe(
                audioURL: url,
                useCase: .keyboard
            )
            let trimmed = transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                finishMissed()
                completion(nil)
            } else {
                phase = .idle
                levels = []
                elapsed = 0
                completion(trimmed)
            }
        }
    }

    /// Tear down without transcribing — used when the surface disappears
    /// mid-capture so the mic indicator releases immediately.
    func cancel() {
        missedResetTask?.cancel()
        if recorder.isRecording {
            recorder.stopRecording()
            recorder.finalizeRecording()
        }
        phase = .idle
        levels = []
        elapsed = 0
    }

    // MARK: Internals

    private func beginRecording() {
        levels = []
        elapsed = 0
        phase = .recording
        Haptics.confirm.fire()
        recorder.startRecording()
    }

    private func failSoftPermission() {
        phase = .idle
        FeedbackToastCenter.shared.showError(
            "Microphone access is off — enable it in Settings to dictate.",
            actionLabel: "SETTINGS"
        ) {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }

    private func finishMissed() {
        phase = .missed
        levels = []
        elapsed = 0
        Haptics.warning.fire()
        missedResetTask?.cancel()
        missedResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard phase == .missed else { return }
            phase = .idle
        }
    }
}

/// Compact magnetic-tape strip for the Ask composer's live dictation
/// state: an amber recording pip, VU bars riding an amber centerline
/// (drawn from the recorder's rolling envelope), and an elapsed readout.
/// While transcribing the bars dim to signal the recording window closed.
private struct AskDictationStrip: View {
    let levels: [Float]
    let elapsed: TimeInterval
    let transcribing: Bool

    /// Mag-tape amber — brand DNA shared with the Deck cockpit waveform,
    /// not theme-tinted, so the recording state reads as "tape" everywhere.
    static let amber = Color(red: 0.910, green: 0.604, blue: 0.235)

    var body: some View {
        HStack(spacing: 8) {
            RecordingPip(dimmed: transcribing, color: Self.amber)

            AskVUBars(levels: levels, color: Self.amber.opacity(transcribing ? 0.4 : 0.9))
                .frame(maxWidth: .infinity)
                .frame(height: 22)

            Text(Self.timeString(elapsed))
                .talkieType(.timestamp)
                .foregroundStyle(Self.amber)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(transcribing ? "Transcribing" : "Recording, \(Int(elapsed)) seconds")
    }

    private static func timeString(_ value: TimeInterval) -> String {
        let total = max(0, Int(value))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Amber recording dot — softly pulsing while live, statically dim while
/// transcribing (and never animated under Reduce Motion).
private struct RecordingPip: View {
    let dimmed: Bool
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .modifier(PipPulse(active: !dimmed))
            .opacity(dimmed ? 0.4 : 1)
    }
}

private struct PipPulse: ViewModifier {
    let active: Bool
    @State private var lit = false

    func body(content: Content) -> some View {
        content
            .opacity(lit ? 1 : 0.5)
            .onAppear {
                guard active, !TalkieMotion.isReduced else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    lit = true
                }
            }
    }
}

/// Canvas VU bars centered on a faint amber centerline. One bar per
/// sample, newest at the right edge (the tape-head position), so the
/// strip rolls right-to-left as new audio lands.
private struct AskVUBars: View {
    let levels: [Float]
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let centerY = size.height / 2

            // Amber centerline — the tape's reference axis.
            let line = CGRect(x: 0, y: centerY - 0.5, width: size.width, height: 1)
            ctx.fill(Path(line), with: .color(color.opacity(0.28)))

            let n = AskDictationController.barCount
            guard n > 0 else { return }
            let gap: CGFloat = 2.5
            let barWidth = max(1.5, (size.width - CGFloat(n - 1) * gap) / CGFloat(n))

            // Right-align the samples we actually have so a fresh capture
            // fills in from the tape-head rather than stretching to fit.
            let start = n - levels.count
            for (i, sample) in levels.enumerated() {
                let idx = start + i
                let shaped = pow(max(0.04, CGFloat(sample)), 0.65)
                let h = max(2, (size.height - 2) * shaped)
                let x = CGFloat(idx) * (barWidth + gap)
                let rect = CGRect(x: x, y: centerY - h / 2, width: barWidth, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
            }
        }
    }
}
