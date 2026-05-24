//
//  CaptureAICommandsSheet.swift
//  Talkie iOS
//
//  One-shot AI commands over capture text, with optional speak-back.
//

import SwiftUI
import TalkieMobileKit

private enum CaptureAICommandPath: String {
    case direct
    case mac

    var title: String {
        switch self {
        case .direct:
            return "API"
        case .mac:
            return "Mac"
        }
    }

    var systemImage: String {
        switch self {
        case .direct:
            return "network"
        case .mac:
            return "desktopcomputer"
        }
    }
}

private struct CaptureAIQuickPrompt: Identifiable {
    let id = UUID()
    let title: String
    let prompt: String
}

private struct CaptureAICommandExecution {
    let id: UUID
    let instruction: String
    let responseText: String
    let providerName: String
    let modelId: String
    let fallbackReason: String?
    let createdAt: Date
}

struct CaptureAICommandsSheet: View {
    let capture: Capture
    let initialInstruction: String?
    let onExecutionSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInstructionFocused: Bool

    @StateObject private var audioPlayer = AudioPlayerManager()
    @State private var bridgeManager = BridgeManager.shared
    @State private var appSettings = TalkieAppSettings.shared
    @State private var commandStore = CaptureAICommandStore.shared
    @State private var instruction = ""
    @State private var isRunning = false
    @State private var isLoadingSpeech = false
    @State private var errorMessage: String?
    @State private var latestExecution: CaptureAICommandExecution?
    @State private var executionHistory: [CaptureAICommandExecution] = []
    @State private var isShowingHistory = false
    @State private var speakWhenReady = false
    @State private var spokenResponseText: String?
    @State private var spokenAudioData: Data?
    @State private var directOptions: ComposeDirectOptionsResult?
    @State private var isLoadingDirectOptions = false
    @State private var directOptionsRequestID = 0
    @State private var directOptionsError: String?
    @State private var dictationState: InlineDictationController.State = .idle
    @State private var dictationError: String?
    @State private var dictationController = InlineDictationController()
    @State private var didConfigureDictation = false
    @State private var didConsumeSeed = false
    @State private var showingBridgeSettings = false

    private let quickPrompts: [CaptureAIQuickPrompt] = [
        CaptureAIQuickPrompt(
            title: "Two Key Points",
            prompt: "What are the two most important points here?"
        ),
        CaptureAIQuickPrompt(
            title: "Summarize",
            prompt: "Summarize this in five sentences."
        ),
        CaptureAIQuickPrompt(
            title: "Explain",
            prompt: "Explain this simply."
        ),
        CaptureAIQuickPrompt(
            title: "Relate",
            prompt: "How does this relate to speech synthesis?"
        ),
        CaptureAIQuickPrompt(
            title: "Research",
            prompt: "If an author or creator is mentioned, give me a short background summary of their work."
        ),
    ]

    init(
        capture: Capture,
        initialInstruction: String? = nil,
        onExecutionSaved: @escaping () -> Void = {}
    ) {
        self.capture = capture
        self.initialInstruction = initialInstruction
        self.onExecutionSaved = onExecutionSaved
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    contextCard
                    runnerControls
                    quickPromptsSection
                    commandInputCard

                    Toggle(isOn: $speakWhenReady) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Speak when ready")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                            Text("Read the result aloud using your Talkie voice settings.")
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

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.recording)
                    }

                    if let latestExecution {
                        resultCard(latestExecution)
                    }

                    executionHistorySection
                }
                .padding(Spacing.md)
            }
            .background(Color.surfacePrimary.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("AI Commands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .navigationDestination(isPresented: $showingBridgeSettings) {
                BridgeSettingsView()
            }
            .onAppear {
                configureDictationIfNeeded()
                audioPlayer.setPlaybackRate(Float(appSettings.ttsPlaybackRate))
                loadLatestExecution()
                refreshDirectOptionsIfNeeded()
                consumeInitialInstructionIfNeeded()
            }
            .onChange(of: appSettings.ttsPlaybackRate) { _, newRate in
                audioPlayer.setPlaybackRate(Float(newRate))
            }
            .onChange(of: bridgeManager.isPaired) { _, isPaired in
                if !isPaired {
                    directOptions = nil
                    directOptionsError = nil
                } else {
                    refreshDirectOptionsIfNeeded(force: true)
                }
            }
            .onChange(of: bridgeManager.status) { _, newStatus in
                guard bridgeManager.isPaired else { return }
                if newStatus == .connected {
                    refreshDirectOptionsIfNeeded(force: true)
                }
            }
            .onDisappear {
                dictationController.cancel()
                audioPlayer.stopPlayback()
            }
        }
    }

    private var selectedPath: CaptureAICommandPath {
        CaptureAICommandPath(rawValue: appSettings.composeRevisionPath) ?? .direct
    }

    private var availableDirectProviders: [ComposeDirectProviderOption] {
        directOptions?.providers ?? []
    }

    private var selectedDirectProvider: ComposeDirectProviderOption? {
        if let matchingProvider = availableDirectProviders.first(where: {
            $0.providerId == appSettings.composeDirectProviderId
        }) {
            return matchingProvider
        }

        return availableDirectProviders.first
    }

    private var selectedDirectModel: ComposeDirectModelOption? {
        guard let selectedDirectProvider else { return nil }

        return resolvedDirectModel(for: selectedDirectProvider)
    }

    private var phoneAIProvider: ComposeBorrowedProvider? {
        TalkieAIProviderResolver.shared.configuredProvider()
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 8) {
                Image(systemName: sourceIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)

                Text(sourceLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)

                Spacer()

                Text("\(capture.wordCount) words")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
            }

            if let title = captureTitle {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
            }

            Text(capture.text)
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

    private var runnerControls: some View {
        CaptureAICommandRunnerControlsRow(
            selectedPath: selectedPath,
            isPaired: bridgeManager.isPaired,
            connectionStatus: bridgeManager.status,
            pairedMacName: bridgeManager.pairedMacName,
            pairedMacs: bridgeManager.pairedMacs,
            activePairedMacID: bridgeManager.activePairedMacID,
            availableDirectProviders: availableDirectProviders,
            selectedDirectProviderId: appSettings.composeDirectProviderId,
            selectedDirectModelId: appSettings.composeDirectModelId,
            isLoadingDirectOptions: isLoadingDirectOptions,
            directOptionsError: directOptionsError,
            hasPhoneAIProvider: phoneAIProvider != nil,
            phoneAIProviderName: phoneAIProvider?.providerName,
            selectPath: selectPath,
            selectPairedMac: { macID in
                Task { await bridgeManager.activatePairedMac(id: macID) }
            },
            selectDirectProvider: selectDirectProvider,
            selectDirectModel: selectDirectModel,
            reconnectToMac: reconnectToMac,
            openBridgeSettings: openBridgeSettings
        )
    }

    private var quickPromptsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            TalkieEyebrow(text: "Quick Commands")

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
            TalkieEyebrow(text: "Command")

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
                    Text("Listening…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.recording)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44, alignment: .center)
            } else if dictationState == .transcribing {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Transcribing…")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44, alignment: .center)
            } else {
                TextField("Ask something about this capture…", text: $instruction, axis: .vertical)
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

    private func resultCard(_ execution: CaptureAICommandExecution) -> some View {
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
                    toggleSpeechPlayback(for: execution)
                } label: {
                    if isLoadingSpeech {
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 64)
                    } else {
                        Label(
                            speechButtonTitle(for: execution),
                            systemImage: speechButtonIcon(for: execution)
                        )
                        .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoadingSpeech || (!hasCachedSpeech(for: execution) && !canGenerateSpeech))

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

    private var executionHistorySection: some View {
        let previousExecutions = executionHistory.filter { run in
            run.id != latestExecution?.id
        }

        return Group {
            if !previousExecutions.isEmpty {
                DisclosureGroup(isExpanded: $isShowingHistory) {
                    VStack(spacing: Spacing.xs) {
                        ForEach(previousExecutions, id: \.id) { execution in
                            historyRow(execution)
                        }
                    }
                    .padding(.top, Spacing.sm)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                        Text("Past Commands")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text("\(previousExecutions.count)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .tint(Color.textSecondary)
                .padding(Spacing.md)
                .background(Color.surfaceSecondary)
                .clipShape(.rect(cornerRadius: CornerRadius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(Color.borderPrimary, lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func historyRow(_ execution: CaptureAICommandExecution) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(execution.instruction)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)

                Spacer()

                Text(execution.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
            }

            Text(execution.responseText)
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(3)

            Text("\(execution.providerName) · \(execution.modelId)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
        }
        .padding(Spacing.sm)
        .background(Color.surfacePrimary)
        .clipShape(.rect(cornerRadius: CornerRadius.sm))
    }

    private var captureTitle: String? {
        if let title = capture.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }

        guard let sourceURL = capture.sourceURL, !sourceURL.isEmpty else {
            return nil
        }

        return sourceURL
    }

    private var sourceLabel: String {
        switch capture.sourceType {
        case "photo":
            return "Scanned Page"
        case "url":
            return "Captured Web Page"
        case "text":
            return "Captured Text"
        default:
            return "Capture"
        }
    }

    private var sourceIcon: String {
        switch capture.sourceType {
        case "photo":
            return "doc.viewfinder"
        case "url":
            return "link"
        case "text":
            return "doc.text"
        default:
            return "sparkles.rectangle.stack"
        }
    }

    private var sourceDescription: String {
        if let sourceURL = capture.sourceURL, !sourceURL.isEmpty {
            return "\(sourceLabel) from \(sourceURL)"
        }

        return sourceLabel
    }

    private var canSubmitCommand: Bool {
        !isRunning
            && dictationState != .transcribing
            && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private func loadLatestExecution() {
        guard let latestRun = commandStore.latestRun(for: capture.id) else { return }
        latestExecution = CaptureAICommandExecution(
            id: latestRun.id,
            instruction: latestRun.instruction,
            responseText: latestRun.responseText,
            providerName: latestRun.providerName,
            modelId: latestRun.modelId,
            fallbackReason: latestRun.fallbackReason,
            createdAt: latestRun.createdAt
        )
        loadExecutionHistory()
    }

    private func loadExecutionHistory() {
        executionHistory = commandStore.runs(for: capture.id).map { run in
            CaptureAICommandExecution(
                id: run.id,
                instruction: run.instruction,
                responseText: run.responseText,
                providerName: run.providerName,
                modelId: run.modelId,
                fallbackReason: run.fallbackReason,
                createdAt: run.createdAt
            )
        }
    }

    private func consumeInitialInstructionIfNeeded() {
        guard !didConsumeSeed else { return }
        guard executionHistory.isEmpty else { return }
        guard !isRunning else { return }
        guard let command = initialInstruction?.trimmingCharacters(in: .whitespacesAndNewlines),
              !command.isEmpty
        else { return }

        didConsumeSeed = true
        instruction = command
        submitCommand(command)
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

        errorMessage = nil
        audioPlayer.stopPlayback()
        clearSpokenAudio()
        isInstructionFocused = false
        isRunning = true
        let shouldSpeakWhenReady = speakWhenReady

        Task {
            do {
                let result: CaptureAICommandResult

                switch selectedPath {
                case .direct:
                    let provider: ComposeBorrowedProvider
                    if let phoneProvider = TalkieAIProviderResolver.shared.configuredProvider() {
                        provider = phoneProvider
                    } else {
                        guard let selectedDirectProvider else {
                            throw BridgeError.messageFailed(
                                directOptionsError ?? "Set up AI credentials in Settings -> AI, or pair a Mac provider."
                            )
                        }

                        provider = try await bridgeManager.composeBorrowedProvider(
                            providerId: selectedDirectProvider.providerId,
                            modelId: selectedDirectModel?.id ?? appSettings.composeDirectModelId
                        )
                    }

                    result = try await CaptureAICommandService.shared.run(
                        context: capture.text,
                        instruction: command,
                        title: captureTitle,
                        sourceDescription: sourceDescription,
                        provider: provider
                    )

                case .mac:
                    let response = try await bridgeManager.composeCommand(
                        context: capture.text,
                        instruction: command,
                        title: captureTitle,
                        sourceDescription: sourceDescription
                    )

                    result = CaptureAICommandResult(
                        responseText: response.outputText,
                        providerName: response.providerName,
                        modelId: response.modelId,
                        fallbackReason: response.fallbackReason
                    )
                }

                await MainActor.run {
                    let execution = CaptureAICommandExecution(
                        id: UUID(),
                        instruction: command,
                        responseText: result.responseText,
                        providerName: result.providerName,
                        modelId: result.modelId,
                        fallbackReason: result.fallbackReason,
                        createdAt: .now
                    )
                    latestExecution = execution
                    commandStore.addRun(
                        CaptureAICommandRun(
                            id: execution.id,
                            captureId: capture.id,
                            instruction: execution.instruction,
                            responseText: execution.responseText,
                            providerName: execution.providerName,
                            modelId: execution.modelId,
                            fallbackReason: execution.fallbackReason,
                            createdAt: execution.createdAt
                        )
                    )
                    loadExecutionHistory()
                    onExecutionSaved()
                    errorMessage = nil
                    instruction = command
                    isRunning = false
                }

                if shouldSpeakWhenReady {
                    await speak(executionText: result.responseText)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRunning = false
                }
            }
        }
    }

    private func selectPath(_ path: CaptureAICommandPath) {
        appSettings.composeRevisionPath = path.rawValue
    }

    private func reconnectToMac() {
        guard bridgeManager.isPaired else { return }
        guard bridgeManager.status != .connecting else { return }

        Task {
            await bridgeManager.connect()
        }
    }

    private func openBridgeSettings() {
        showingBridgeSettings = true
    }

    private func refreshDirectOptionsIfNeeded(force: Bool = false) {
        guard bridgeManager.isPaired else { return }
        guard force || bridgeManager.status == .connected || bridgeManager.shouldConnect else { return }

        directOptionsRequestID += 1
        let requestID = directOptionsRequestID
        isLoadingDirectOptions = true

        Task {
            do {
                let options = try await bridgeManager.composeDirectOptions()
                guard requestID == directOptionsRequestID else { return }
                directOptions = options
                directOptionsError = nil
                reconcileDirectSelection(with: options)
            } catch {
                guard requestID == directOptionsRequestID else { return }
                directOptionsError = error.localizedDescription
            }

            if requestID == directOptionsRequestID {
                isLoadingDirectOptions = false
            }
        }
    }

    private func reconcileDirectSelection(with options: ComposeDirectOptionsResult) {
        guard !options.providers.isEmpty else {
            appSettings.composeDirectProviderId = options.selectedProviderId
            appSettings.composeDirectModelId = options.selectedModelId
            return
        }

        let selectedProvider = options.providers.first(where: {
            $0.providerId == appSettings.composeDirectProviderId
        }) ?? options.providers.first(where: {
            $0.providerId == options.selectedProviderId
        }) ?? options.providers[0]

        let selectedModel = resolvedDirectModel(
            for: selectedProvider,
            savedModelId: appSettings.composeDirectModelId,
            serverSelectedModelId: options.selectedModelId
        )

        appSettings.composeDirectProviderId = selectedProvider.providerId
        appSettings.composeDirectModelId = selectedModel?.id ?? ""
    }

    private func selectDirectProvider(_ providerId: String) {
        guard let provider = availableDirectProviders.first(where: { $0.providerId == providerId }) else { return }
        appSettings.composeDirectProviderId = provider.providerId

        let savedModelId = appSettings.composeDirectModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldKeepSavedModel = shouldKeepSavedDirectModel(savedModelId, providerId: provider.providerId)
            && provider.models.contains(where: { $0.id == savedModelId })

        if !shouldKeepSavedModel {
            appSettings.composeDirectModelId = resolvedDirectModel(
                for: provider,
                savedModelId: savedModelId
            )?.id ?? ""
        }
    }

    private func selectDirectModel(_ modelId: String) {
        guard let selectedDirectProvider else { return }
        guard selectedDirectProvider.models.contains(where: { $0.id == modelId }) else { return }
        appSettings.composeDirectModelId = modelId
    }

    private func resolvedDirectModel(
        for provider: ComposeDirectProviderOption,
        savedModelId: String? = nil,
        serverSelectedModelId: String? = nil
    ) -> ComposeDirectModelOption? {
        let savedModelId = (savedModelId ?? appSettings.composeDirectModelId)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if shouldKeepSavedDirectModel(savedModelId, providerId: provider.providerId),
           let matchingModel = provider.models.first(where: { $0.id == savedModelId }) {
            return matchingModel
        }

        if let preferredModel = preferredDirectModel(in: provider) {
            return preferredModel
        }

        if let serverSelectedModelId,
           let serverModel = provider.models.first(where: { $0.id == serverSelectedModelId }) {
            return serverModel
        }

        if let legacyModel = provider.models.first(where: { $0.id == savedModelId }) {
            return legacyModel
        }

        return provider.models.first
    }

    private func preferredDirectModel(in provider: ComposeDirectProviderOption) -> ComposeDirectModelOption? {
        let preferredModelId = TalkieAIProviderCredentialPayload.defaultModel(for: provider.providerId)
        return provider.models.first { $0.id == preferredModelId }
    }

    private func shouldKeepSavedDirectModel(_ modelId: String, providerId: String) -> Bool {
        guard !modelId.isEmpty else { return false }
        return !TalkieAIProviderCredentialPayload.isLegacyDefaultModel(modelId, for: providerId)
    }

    private var canGenerateSpeech: Bool {
        TTSService.canSynthesizeConfiguredAudio(
            settings: appSettings,
            bridgeStatus: bridgeManager.status
        )
    }

    private func hasCachedSpeech(for execution: CaptureAICommandExecution) -> Bool {
        spokenResponseText == execution.responseText && spokenAudioData != nil
    }

    private func isPlayingSpeech(for execution: CaptureAICommandExecution) -> Bool {
        hasCachedSpeech(for: execution) && audioPlayer.isPlaying
    }

    private func speechButtonTitle(for execution: CaptureAICommandExecution) -> String {
        if isPlayingSpeech(for: execution) {
            return "Pause"
        }

        if hasCachedSpeech(for: execution) {
            return "Play"
        }

        return "Speak"
    }

    private func speechButtonIcon(for execution: CaptureAICommandExecution) -> String {
        isPlayingSpeech(for: execution) ? "pause.fill" : "play.fill"
    }

    private func toggleSpeechPlayback(for execution: CaptureAICommandExecution) {
        if hasCachedSpeech(for: execution), let spokenAudioData {
            audioPlayer.togglePlayPause(data: spokenAudioData)
            return
        }

        Task {
            await speak(executionText: execution.responseText)
        }
    }

    @MainActor
    private func speak(executionText: String) async {
        guard !isLoadingSpeech else { return }

        isLoadingSpeech = true

        defer {
            isLoadingSpeech = false
        }

        do {
            let audioData = try await TTSService.synthesizeConfigured(
                text: executionText,
                settings: appSettings
            )

            spokenResponseText = executionText
            spokenAudioData = audioData
            errorMessage = nil
            audioPlayer.playAudio(data: audioData)
        } catch {
            errorMessage = "Couldn’t speak result — \(error.localizedDescription)"
        }
    }

    private func clearSpokenAudio() {
        spokenResponseText = nil
        spokenAudioData = nil
    }
}

private struct CaptureAICommandRunnerControlsRow: View {
    let selectedPath: CaptureAICommandPath
    let isPaired: Bool
    let connectionStatus: BridgeManager.ConnectionStatus
    let pairedMacName: String?
    let pairedMacs: [BridgeManager.PairedMac]
    let activePairedMacID: String?
    let availableDirectProviders: [ComposeDirectProviderOption]
    let selectedDirectProviderId: String
    let selectedDirectModelId: String
    let isLoadingDirectOptions: Bool
    let directOptionsError: String?
    let hasPhoneAIProvider: Bool
    let phoneAIProviderName: String?
    let selectPath: (CaptureAICommandPath) -> Void
    let selectPairedMac: (String) -> Void
    let selectDirectProvider: (String) -> Void
    let selectDirectModel: (String) -> Void
    let reconnectToMac: () -> Void
    let openBridgeSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits {
                selectionChips
                    .frame(maxWidth: .infinity, alignment: .center)

                ScrollView(.horizontal, showsIndicators: false) {
                    selectionChips
                }
            }

            if let statusMessage {
                HStack(spacing: 6) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(statusColor)

                    Text(statusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var selectionChips: some View {
        HStack(spacing: Spacing.xs) {
            Menu {
                Button {
                    selectPath(.direct)
                } label: {
                    Label(CaptureAICommandPath.direct.title, systemImage: CaptureAICommandPath.direct.systemImage)
                }

                if isPaired {
                    if connectionStatus == .connected {
                        Button {
                            selectPath(.mac)
                        } label: {
                            Label(CaptureAICommandPath.mac.title, systemImage: CaptureAICommandPath.mac.systemImage)
                        }
                    } else if connectionStatus == .connecting {
                        Button {
                        } label: {
                            Label("Connecting to Mac", systemImage: "wifi.exclamationmark")
                        }
                        .disabled(true)
                    } else {
                        Button {
                            reconnectToMac()
                        } label: {
                            Label("Reconnect Mac", systemImage: "arrow.clockwise")
                        }
                    }

                    Button {
                        openBridgeSettings()
                    } label: {
                        Label("Mac Settings", systemImage: "gearshape")
                    }
                } else {
                    Button {
                        openBridgeSettings()
                    } label: {
                        Label("Pair Mac", systemImage: "desktopcomputer.badge.plus")
                    }
                }
            } label: {
                chip(
                    title: selectedPathTitle,
                    systemImage: selectedPathIcon,
                    tint: selectedPath == .direct ? Color.textSecondary : statusColor,
                    showsMenuIndicator: true
                )
            }

            if pairedMacs.count > 1 {
                Menu {
                    ForEach(pairedMacs) { pairedMac in
                        Button {
                            selectPairedMac(pairedMac.id)
                        } label: {
                            Label(pairedMacTitle(for: pairedMac), systemImage: pairedMac.id == activePairedMacID ? "checkmark.circle.fill" : "desktopcomputer")
                        }
                    }
                } label: {
                    chip(
                        title: activeMacTitle,
                        systemImage: "desktopcomputer",
                        tint: statusColor,
                        showsMenuIndicator: true
                    )
                }
            }

            if selectedPath == .direct {
                if let selectedProvider {
                    Menu {
                        ForEach(availableDirectProviders) { provider in
                            Button {
                                selectDirectProvider(provider.providerId)
                            } label: {
                                Label(provider.providerName, systemImage: providerSymbol(for: provider.providerId))
                            }
                        }
                    } label: {
                        chip(
                            title: selectedProvider.providerName,
                            systemImage: providerSymbol(for: selectedProvider.providerId),
                            tint: providerTint(for: selectedProvider.providerId),
                            showsMenuIndicator: true
                        )
                    }

                    if let selectedModel {
                        Menu {
                            ForEach(selectedProvider.models) { model in
                                Button(model.name) {
                                    selectDirectModel(model.id)
                                }
                            }
                        } label: {
                            chip(
                                title: selectedModel.name,
                                systemImage: "cpu",
                                tint: Color.textSecondary,
                                showsMenuIndicator: true
                            )
                        }
                    } else if showsDirectSelectionPlaceholders {
                        chip(
                            title: directModelPlaceholderTitle,
                            systemImage: directModelPlaceholderIcon,
                            tint: directPlaceholderTint,
                            isEnabled: false,
                            showsLoadingIndicator: isLoadingDirectOptions
                        )
                    }
                } else if showsDirectSelectionPlaceholders {
                    chip(
                        title: directProviderPlaceholderTitle,
                        systemImage: directProviderPlaceholderIcon,
                        tint: directPlaceholderTint,
                        isEnabled: false,
                        showsLoadingIndicator: isLoadingDirectOptions
                    )

                    chip(
                        title: directModelPlaceholderTitle,
                        systemImage: directModelPlaceholderIcon,
                        tint: directPlaceholderTint,
                        isEnabled: false,
                        showsLoadingIndicator: isLoadingDirectOptions
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var selectedProvider: ComposeDirectProviderOption? {
        availableDirectProviders.first(where: { $0.providerId == selectedDirectProviderId })
            ?? availableDirectProviders.first
    }

    private var activeMacTitle: String {
        if let activeMac = pairedMacs.first(where: { $0.id == activePairedMacID }) {
            return pairedMacTitle(for: activeMac)
        }

        return pairedMacName ?? "Active Mac"
    }

    private func pairedMacTitle(for pairedMac: BridgeManager.PairedMac) -> String {
        pairedMac.pairedMacName.isEmpty ? pairedMac.hostname : pairedMac.pairedMacName
    }

    private var selectedModel: ComposeDirectModelOption? {
        guard let selectedProvider else { return nil }

        return selectedProvider.models.first(where: { $0.id == selectedDirectModelId })
            ?? selectedProvider.models.first
    }

    private var statusMessage: String? {
        switch selectedPath {
        case .direct:
            if hasPhoneAIProvider {
                return phoneAIProviderName.map { "Using iPhone \($0) credentials." }
                    ?? "Using iPhone AI credentials."
            }

            if !isPaired {
                return "Set up AI credentials in Settings -> AI, or pair your Mac once."
            }

            switch connectionStatus {
            case .connected:
                if isLoadingDirectOptions && availableDirectProviders.isEmpty {
                    return "Loading API providers from your Mac."
                }
                return availableDirectProviders.isEmpty
                    ? (directOptionsError ?? "Add OpenAI or Groq on your Mac to use API AI Commands.")
                    : nil
            case .connecting, .disconnected:
                return isLoadingDirectOptions
                    ? "Connecting to your Mac and loading API providers."
                    : "Reconnect to your Mac to load API providers."
            case .error:
                return directOptionsError ?? "Couldn’t load API providers from your Mac."
            }

        case .mac:
            if !isPaired {
                return "Pair Mac to run AI Commands there."
            }

            switch connectionStatus {
            case .connected:
                return pairedMacName.map { "Running on \($0)." }
            case .connecting, .disconnected:
                return "Reconnect to your Mac to run AI Commands there."
            case .error:
                return "Couldn’t reach your Mac for AI Commands."
            }
        }
    }

    private var statusIcon: String {
        if selectedPath == .direct, hasPhoneAIProvider {
            return "iphone"
        }

        if !isPaired {
            return "desktopcomputer.badge.plus"
        }

        switch connectionStatus {
        case .connecting:
            return "wifi.exclamationmark"
        case .disconnected:
            return "wifi.slash"
        case .error:
            return "exclamationmark.triangle.fill"
        case .connected:
            return selectedPath == .mac ? "desktopcomputer" : "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        if selectedPath == .direct, hasPhoneAIProvider {
            return Color.success
        }

        if !isPaired {
            return Color.warning
        }

        switch connectionStatus {
        case .connecting, .disconnected:
            return Color.warning
        case .error:
            return Color.recording
        case .connected:
            return Color.success
        }
    }

    private var selectedPathTitle: String {
        switch selectedPath {
        case .direct:
            return CaptureAICommandPath.direct.title
        case .mac:
            guard isPaired else { return "Pair Mac" }

            switch connectionStatus {
            case .connected:
                return CaptureAICommandPath.mac.title
            case .connecting:
                return "Connecting…"
            case .disconnected, .error:
                return "Reconnect Mac"
            }
        }
    }

    private var selectedPathIcon: String {
        switch selectedPath {
        case .direct:
            return CaptureAICommandPath.direct.systemImage
        case .mac:
            guard isPaired else { return "desktopcomputer.badge.plus" }

            switch connectionStatus {
            case .connected:
                return CaptureAICommandPath.mac.systemImage
            case .connecting:
                return "wifi.exclamationmark"
            case .disconnected, .error:
                return "arrow.clockwise"
            }
        }
    }

    private var showsDirectSelectionPlaceholders: Bool {
        isPaired || isLoadingDirectOptions || directOptionsError != nil
    }

    private var directProviderPlaceholderTitle: String {
        if !isPaired {
            return "Saved APIs"
        }

        if isLoadingDirectOptions {
            return "Loading APIs"
        }

        if directOptionsError != nil {
            return "API Unavailable"
        }

        return "No APIs"
    }

    private var directProviderPlaceholderIcon: String {
        if directOptionsError != nil {
            return "exclamationmark.triangle.fill"
        }

        if connectionStatus == .connecting || connectionStatus == .disconnected {
            return "wifi.exclamationmark"
        }

        return "network"
    }

    private var directModelPlaceholderTitle: String {
        if isLoadingDirectOptions {
            return "Loading Model"
        }

        if directOptionsError != nil {
            return "Model Unavailable"
        }

        return "Choose Model"
    }

    private var directModelPlaceholderIcon: String {
        directOptionsError == nil ? "cpu" : "exclamationmark.triangle.fill"
    }

    private var directPlaceholderTint: Color {
        if directOptionsError != nil {
            return Color.recording
        }

        if isLoadingDirectOptions || connectionStatus == .connecting || connectionStatus == .disconnected {
            return Color.warning
        }

        return Color.textTertiary
    }

    private func providerSymbol(for providerId: String) -> String {
        switch providerId {
        case "openai":
            return "sparkles"
        case "groq":
            return "bolt.fill"
        default:
            return "network"
        }
    }

    private func providerTint(for providerId: String) -> Color {
        switch providerId {
        case "openai":
            return Color.textSecondary
        case "groq":
            return Color.textSecondary
        default:
            return Color.textSecondary
        }
    }

    @ViewBuilder
    private func chip(
        title: String,
        systemImage: String,
        tint: Color,
        showsMenuIndicator: Bool = false,
        isEnabled: Bool = true,
        showsLoadingIndicator: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            if showsLoadingIndicator {
                ProgressView()
                    .controlSize(.mini)
                    .tint(tint)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            if showsMenuIndicator {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.surfaceSecondary)
        .clipShape(.capsule)
        .overlay {
            Capsule()
                .stroke(Color.borderPrimary.opacity(0.7), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .opacity(isEnabled ? 1 : 0.74)
    }
}
