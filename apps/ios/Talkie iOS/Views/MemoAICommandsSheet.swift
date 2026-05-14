//
//  MemoAICommandsSheet.swift
//  Talkie iOS
//
//  Direct iPhone AI commands for a memo transcript.
//

import SwiftUI
import TalkieMobileKit

private struct MemoAIQuickPrompt: Identifiable {
    let id = UUID()
    let title: String
    let prompt: String
}

private struct MemoAIExecution {
    let instruction: String
    let responseText: String
    let providerName: String
    let modelId: String
    let fallbackReason: String?
    let createdAt: Date
}

struct MemoAICommandsSheet: View {
    let memoTitle: String
    let memoTranscript: String
    let memoId: String?
    let onAnswer: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInstructionFocused: Bool

    @State private var appSettings = TalkieAppSettings.shared
    @State private var instruction = ""
    @State private var isRunning = false
    @State private var isSpeaking = false
    @State private var speakWhenReady = false
    @State private var errorMessage: String?
    @State private var latestExecution: MemoAIExecution?
    @State private var dictationState: InlineDictationController.State = .idle
    @State private var dictationError: String?
    @State private var dictationController = InlineDictationController()
    @State private var didConfigureDictation = false

    private let quickPrompts: [MemoAIQuickPrompt] = [
        MemoAIQuickPrompt(title: "Answer", prompt: "What should I do with this note?"),
        MemoAIQuickPrompt(title: "Summarize", prompt: "Summarize this memo in five concise bullets."),
        MemoAIQuickPrompt(title: "Tasks", prompt: "Extract the concrete tasks and decisions from this memo."),
        MemoAIQuickPrompt(title: "Follow Up", prompt: "Draft a short follow-up message based on this memo."),
        MemoAIQuickPrompt(title: "Explain", prompt: "Explain the important context in plain language."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    memoContextCard
                    quickPromptsSection
                    commandInputCard
                    speakToggle

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.recording)
                    }

                    if let latestExecution {
                        resultCard(latestExecution)
                    }
                }
                .padding(Spacing.md)
            }
            .background(Color.surfacePrimary.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Ask AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                configureDictationIfNeeded()
                speakWhenReady = appSettings.aiVoiceOutputRoute != AIResponseSpeechRoute.silent.rawValue
            }
            .onDisappear {
                dictationController.cancel()
            }
        }
    }

    private var memoContextCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)

                Text("Memo Transcript")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)

                Spacer()

                Text("\(memoTranscript.split(whereSeparator: { $0.isWhitespace }).count) words")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
            }

            Text(memoTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)

            Text(memoTranscript)
                .font(.system(size: 13))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(8)
        }
        .padding(Spacing.md)
        .background(Color.surfaceSecondary)
        .clipShape(.rect(cornerRadius: CornerRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(Color.borderPrimary, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }

    private var quickPromptsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("QUICK COMMANDS")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.textTertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(quickPrompts) { prompt in
                        Button(prompt.title) {
                            instruction = prompt.prompt
                            submitCommand(prompt.prompt)
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.surfaceSecondary)
                        .clipShape(.capsule)
                        .overlay {
                            Capsule()
                                .stroke(Color.borderPrimary.opacity(0.7), lineWidth: 0.5)
                                .allowsHitTesting(false)
                        }
                        .disabled(isRunning || dictationState == .transcribing)
                    }
                }
            }
        }
    }

    private var commandInputCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("COMMAND")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.textTertiary)

            HStack(alignment: .bottom, spacing: Spacing.sm) {
                commandField

                Button {
                    toggleDictation()
                } label: {
                    ZStack {
                        Circle()
                            .fill(dictationState == .recording ? Color.recording.opacity(0.14) : Color.surfacePrimary)
                            .frame(width: 44, height: 44)

                        Image(systemName: dictationState == .recording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(dictationState == .recording ? Color.recording : Color.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isRunning || dictationState == .transcribing)
                .accessibilityLabel(dictationState == .recording ? "Stop recording command" : "Record command")

                Button {
                    submitCommand()
                } label: {
                    if isRunning {
                        ProgressView()
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(canSubmitCommand ? Color.accentColor : Color.textTertiary.opacity(0.5))
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSubmitCommand)
                .accessibilityLabel("Run AI command")
            }

            if dictationState != .idle || dictationError != nil {
                HStack(spacing: 8) {
                    Image(systemName: dictationState == .recording ? "waveform.circle.fill" : "waveform.badge.magnifyingglass")
                        .foregroundStyle(dictationState == .recording ? Color.recording : Color.textSecondary)

                    Text(dictationMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.surfaceSecondary)
        .clipShape(.rect(cornerRadius: CornerRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(Color.borderPrimary, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }

    private var commandField: some View {
        VStack(alignment: .leading, spacing: 6) {
            if dictationState == .recording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.recording)
                        .frame(width: 6, height: 6)
                    Text("Listening...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.recording)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44, alignment: .center)
            } else if dictationState == .transcribing {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Transcribing...")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44, alignment: .center)
            } else {
                TextField("Ask something about this memo...", text: $instruction, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(2...5)
                    .focused($isInstructionFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        submitCommand()
                    }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfacePrimary)
        .clipShape(.rect(cornerRadius: CornerRadius.sm))
    }

    private var speakToggle: some View {
        Toggle(isOn: $speakWhenReady) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Speak when ready")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                Text("Uses Settings -> AI -> AI Voice.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .tint(.accentColor)
        .padding(Spacing.md)
        .background(Color.surfaceSecondary)
        .clipShape(.rect(cornerRadius: CornerRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(Color.borderPrimary, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }

    private func resultCard(_ execution: MemoAIExecution) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Latest Result")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)

                    Text(execution.instruction)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)

                    Text(execution.createdAt, format: .dateTime.hour().minute())
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                }

                Spacer()

                Text(execution.providerName)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.surfacePrimary)
                    .clipShape(.capsule)
            }

            if let fallbackReason = execution.fallbackReason {
                Text(fallbackReason)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
            }

            Text(execution.responseText)
                .font(.system(size: 14))
                .foregroundStyle(Color.textPrimary)
                .textSelection(.enabled)

            HStack(spacing: Spacing.sm) {
                Button {
                    Task {
                        await speak(execution.responseText)
                    }
                } label: {
                    if isSpeaking {
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 64)
                    } else {
                        Label("Speak", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSpeaking)

                Button {
                    UIPasteboard.general.string = execution.responseText
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)

                Spacer()

                Text(execution.modelId)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(Spacing.md)
        .background(Color.surfaceSecondary)
        .clipShape(.rect(cornerRadius: CornerRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(Color.borderPrimary, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }

    private var canSubmitCommand: Bool {
        !isRunning
            && dictationState != .transcribing
            && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !memoTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var dictationMessage: String {
        if let dictationError {
            return dictationError
        }

        switch dictationState {
        case .idle:
            return ""
        case .recording:
            return "Recording your AI command."
        case .transcribing:
            return "Transcribing your command."
        }
    }

    private func configureDictationIfNeeded() {
        guard !didConfigureDictation else { return }
        didConfigureDictation = true

        dictationController.onStateChange = { state in
            Task { @MainActor in
                dictationState = state
            }
        }

        dictationController.onTranscript = { transcript in
            Task { @MainActor in
                dictationError = nil
                instruction = transcript
                isInstructionFocused = false
            }
        }

        dictationController.onError = { message in
            Task { @MainActor in
                dictationError = message
            }
        }
    }

    private func toggleDictation() {
        dictationError = nil

        if dictationState == .recording {
            dictationController.stop(insertTranscript: true)
        } else {
            instruction = ""
            Task {
                await dictationController.start()
            }
        }
    }

    private func submitCommand(_ overrideInstruction: String? = nil) {
        let command = (overrideInstruction ?? instruction).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        guard !isRunning else { return }

        guard let provider = TalkieAIProviderResolver.shared.configuredProvider() else {
            errorMessage = "Set up AI credentials in Settings -> AI, then try again."
            return
        }

        errorMessage = nil
        isInstructionFocused = false
        isRunning = true
        let shouldSpeakWhenReady = speakWhenReady

        Task {
            do {
                let result = try await CaptureAICommandService.shared.run(
                    context: memoTranscript,
                    instruction: command,
                    title: memoTitle,
                    sourceDescription: "Voice memo transcript",
                    provider: provider
                )

                let execution = MemoAIExecution(
                    instruction: command,
                    responseText: result.responseText,
                    providerName: result.providerName,
                    modelId: result.modelId,
                    fallbackReason: result.fallbackReason,
                    createdAt: .now
                )

                if let memoId {
                    _ = AgentSessionStore.shared.session(forMemoId: memoId, memoTitle: memoTitle)
                    AgentSessionStore.shared.addUserTurn(memoId: memoId, content: command)
                    AgentSessionStore.shared.addAssistantTurn(memoId: memoId, content: result.responseText)
                }

                await MainActor.run {
                    latestExecution = execution
                    errorMessage = nil
                    instruction = command
                    isRunning = false
                    onAnswer(result.responseText)
                }

                if shouldSpeakWhenReady {
                    await speak(result.responseText)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRunning = false
                }
            }
        }
    }

    @MainActor
    private func speak(_ text: String) async {
        guard !isSpeaking else { return }
        isSpeaking = true
        defer { isSpeaking = false }

        let provider = TalkieAIProviderResolver.shared.configuredProvider()
        let result = await AIResponseSpeechRouter.shared.speak(
            text,
            provider: provider,
            memoId: memoId,
            preview: text
        )

        if !result.didSpeak && result.route != .silent {
            errorMessage = "Couldn’t speak the answer with the current AI Voice route."
        }
    }
}
