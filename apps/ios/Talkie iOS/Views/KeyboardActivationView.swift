//
//  KeyboardActivationView.swift
//  Talkie iOS
//
//  Minimal ready screen for keyboard dictation.
//  Technical aesthetic — dark, instrument-panel feel.
//

import SwiftUI
import TalkieMobileKit

struct KeyboardActivationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var headlessService = HeadlessDictationService.shared

    @State private var hasReturned = false
    @State private var isKeyboardModeEnabled = false
    @State private var recordingStartTime: Date?
    @State private var recordingDuration: TimeInterval = 0
    @State private var currentState: DictationSharedState.Phase = .idle
    @State private var checker = DictationReadinessChecker()
    @State private var returnAttemptCount = 0
    @State private var showReturnExplainer = false
    @State private var previousState: DictationSharedState.Phase = .idle
    @State private var activityLog: [ActivityEntry] = []
    @State private var flowStartTime: Date = Date()
    @State private var returnInfoDismissed = false
    @State private var wasModelLoading = false
    @State private var loggedEngineForTranscription = false
    @State private var audioRetryCount = 0
    @State private var lastTranscript: String?
    @State private var copiedToClipboard = false

    private let bridge = KeyboardBridge.shared
    private let sharedStore = DictationSharedStore.shared
    private let deepLinkManager = DeepLinkManager.shared

    private struct ActivityEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let event: String
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surfacePrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Log — pinned to top, compact (hidden in screenshots)
                    if !ProcessInfo.processInfo.arguments.contains("-FASTLANE_SNAPSHOT") {
                        activityTicker
                            .padding(.top, Spacing.sm)
                            .padding(.horizontal, Spacing.lg)
                    }

                    // Transcript — fixed reserved area below logs
                    // Always allocated so layout doesn't shift when transcript appears
                    transcriptRegion
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, Spacing.sm)

                    Spacer()

                    // Status indicator — centered in remaining space
                    statusContent
                        .padding(.horizontal, Spacing.lg)

                    Spacer()

                    // Return info or help icon — bottom center
                    bottomInfoArea
                        .padding(.horizontal, Spacing.lg)
                        .padding(.bottom, Spacing.md)

                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-FASTLANE_SNAPSHOT") == false {
                        debugSection
                    }
                    #endif
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    TalkieEyebrow(text: "Keyboard Mode")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    KeyboardModeToggle(isEnabled: $isKeyboardModeEnabled)
                }
            }
        }
        .onAppear {
            flowStartTime = Date()
            logActivity("Initializing")
            headlessService.handleDictationRequest()
            attemptReturnIfPossible()
            isKeyboardModeEnabled = headlessService.isActive

            // Shared store is the single source of truth
            let initialState = sharedStore.phase
            currentState = initialState
            previousState = initialState

            // If recording is already in progress, seed the timer from the actual start time
            if initialState == .recording {
                let phaseStart = sharedStore.phaseUpdatedAt
                if phaseStart > 0 {
                    recordingStartTime = Date(timeIntervalSince1970: phaseStart)
                }
            }

            checker.evaluate()
        }
        .onChange(of: headlessService.isActive) { _, newValue in
            isKeyboardModeEnabled = newValue
        }
        .onReceive(Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()) { _ in
            // Shared store is the single source of truth
            let newState = sharedStore.phase
            if newState != previousState {
                handleStateTransition(from: previousState, to: newState)
                previousState = newState
            }
            currentState = newState
            updateRecordingDuration()
            checkForReturn()
            checker.evaluate()
            trackModelLoading()
            trackEngineSelection()
            autoRecoverAudioSession()
        }
    }

    // MARK: - Status Content

    @ViewBuilder
    private var statusContent: some View {
        VStack(spacing: Spacing.lg) {
            if let error = sharedStore.lastError?.message {
                errorView(error)
            } else {
                switch currentState {
                case .recording:
                    if isRecordingPipelineActive {
                        recordingView
                    } else {
                        connectingView
                    }

                case .stopping, .transcribing:
                    processingView

                case .done:
                    doneView

                case .ready:
                    readyView

                case .idle, .arming:
                    if headlessService.isActive {
                        readyView
                    } else {
                        connectingView
                    }

                case .error:
                    // Error phase without payload — show connecting
                    connectingView
                }
            }
        }
    }

    // MARK: - Connecting (with activity detail)

    private var connectingView: some View {
        VStack(spacing: Spacing.md) {
            if let blocker = checker.readiness.firstBlocker {
                // Blocked — show what's wrong
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: blocker.icon)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.textTertiary)
                        Text(blocker.detail ?? blocker.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }

                    if let action = blocker.recovery {
                        techButton(action)
                    }
                }
            } else {
                // Actively connecting — show progress detail
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        BrailleSpinner(size: 14, color: .textTertiary)
                        TalkieEyebrow(text: "Initializing", tint: .ink, showLeader: false)
                    }

                    // Show what's happening under the hood
                    VStack(spacing: 4) {
                        activityRow(
                            "Audio session",
                            active: headlessService.isInReadyMode || headlessService.isRecording,
                            pending: true
                        )
                        activityRow(
                            "Keyboard mode",
                            active: headlessService.isActive,
                            pending: !headlessService.isActive
                        )
                        activityRow(
                            "Bridge sync",
                            active: bridge.isAppReady(),
                            pending: !bridge.isAppReady()
                        )
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    /// Single row showing a subsystem's status
    private func activityRow(_ label: String, active: Bool, pending: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active ? Color.success.opacity(0.8) : (pending ? Color.textTertiary.opacity(0.4) : Color.textTertiary.opacity(0.2)))
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(active ? .textSecondary : .textTertiary)
            Spacer()
            if active {
                Text("OK")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.success.opacity(0.7))
            } else if pending {
                Text("...")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.textTertiary)
            }
        }
        .frame(maxWidth: 180)
    }

    // MARK: - Ready

    private var readyView: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: 8) {
                Circle()
                    .fill(checker.readiness.isFullyReady ? Color.success : Color.warning)
                    .frame(width: 10, height: 10)
                Text("Ready")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.textSecondary)
            }

            Button(action: {
                headlessService.handleDictationRequest()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Start Dictation")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.active)
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(Color.active.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Only show retry after auto-recovery has failed several times
            if audioRetryCount > 5 && checker.readiness.hasWarnings {
                Button(action: {
                    audioRetryCount = 0
                    headlessService.handleDictationRequest()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        Text("RECONNECT")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                    }
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.textTertiary.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.textTertiary.opacity(0.25), lineWidth: 0.5)
                    )
                    .cornerRadius(4)
                }
            }
        }
    }

    // MARK: - Recording

    private var recordingView: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.recording)
                    .frame(width: 10, height: 10)
                Text(formatDuration(recordingDuration))
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundColor(.textSecondary)
            }

            Button(action: stopRecording) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("End Dictation")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.recording)
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(Color.recording.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .onAppear {
            if recordingStartTime == nil {
                // Use the shared store's phase timestamp for accurate duration
                // (recording may have started before this view appeared)
                let phaseStart = sharedStore.phaseUpdatedAt
                if phaseStart > 0 {
                    recordingStartTime = Date(timeIntervalSince1970: phaseStart)
                } else {
                    recordingStartTime = Date()
                }
            }
        }
    }

    // MARK: - Processing

    private var processingView: some View {
        HStack(spacing: 8) {
            BrailleSpinner(size: 14, color: .textSecondary)
            Text(processingLabel)
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
        }
        .onAppear {
            recordingStartTime = nil
        }
    }

    private var processingLabel: String {
        let engineName = TranscriptionService.lastUsedEngineName
        if !engineName.isEmpty {
            // Transcription is actively running — show which engine
            return "Processing (\(engineName))..."
        }
        // No engine selected yet — might still be selecting/loading
        let manager = ParakeetModelManager.shared
        switch manager.state {
        case .loading:
            return "Loading AI model..."
        case .ready where !manager.isWarmedUp:
            return "Warming up AI..."
        default:
            return "Processing..."
        }
    }

    // MARK: - Done

    private var doneView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.success)
            Text("Done")
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
        }
    }

    // MARK: - Transcript Region (fixed reserved area)

    /// Fixed 180pt reserved area below the logs.
    /// Always allocated so layout stays stable.
    /// Shows transcript content when done, empty placeholder otherwise.
    private var transcriptRegion: some View {
        ZStack(alignment: .topTrailing) {
            if let transcript = lastTranscript, currentState == .done {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(transcript)
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .padding(.trailing, 28)
                }
                .background(Color.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.textTertiary.opacity(0.15), lineWidth: 0.5)
                )
                .transition(.opacity)

                Button(action: {
                    UIPasteboard.general.string = transcript
                    copiedToClipboard = true
                }) {
                    Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(copiedToClipboard ? .success : .textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Color.textTertiary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(6)
                .transition(.opacity)
            }
        }
        .frame(height: 180)
        .animation(.easeInOut(duration: 0.3), value: lastTranscript != nil && currentState == .done)
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: Spacing.sm) {
            Text("ERROR")
                .font(.techLabelSmall)
                .tracking(1.5)
                .foregroundColor(.recording)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                if message.lowercased().contains("permission") ||
                   message.lowercased().contains("denied") ||
                   message.lowercased().contains("not authorized") {
                    techButton(.openSettings, label: "Settings")
                }

                techButton(.retryConnection, label: "Retry")

                if sharedStore.phaseAge > 15 {
                    techButton(.forceReset, label: "Reset")
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Bottom Info Area

    @ViewBuilder
    private var bottomInfoArea: some View {
        if showReturnExplainer && !returnInfoDismissed {
            returnInfoCard
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if returnInfoDismissed {
            // Collapsed help icon
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    returnInfoDismissed = false
                }
            }) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.textTertiary.opacity(0.4))
            }
            .transition(.opacity)
        }
    }

    private var returnInfoCard: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Switch back to your app to continue")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)

                    Text("iOS doesn't allow keyboard extensions to switch apps automatically. This is an Apple platform limitation.")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: {
                        if let url = URL(string: "https://developer.apple.com/documentation/uikit/keyboards_and_input/creating_a_custom_keyboard") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Text("Learn more")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.active)
                    }
                }

                Spacer()

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        returnInfoDismissed = true
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.textTertiary)
                        .frame(width: 22, height: 22)
                        .background(Color.textTertiary.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }
        .padding(14)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.textTertiary.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Technical Recovery Buttons

    private func techButton(_ action: RecoveryAction, label: String? = nil) -> some View {
        let btnLabel = label ?? recoveryLabel(action)
        let btnIcon = recoveryIcon(action)

        return Button(action: { checker.perform(action) }) {
            HStack(spacing: 4) {
                Image(systemName: btnIcon)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                Text(btnLabel.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.5)
            }
            .foregroundColor(.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.textTertiary.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.textTertiary.opacity(0.25), lineWidth: 0.5)
            )
            .cornerRadius(4)
        }
    }

    private func recoveryLabel(_ action: RecoveryAction) -> String {
        switch action {
        case .openSettings: return "Settings"
        case .enableKeyboardMode: return "Enable"
        case .retryConnection: return "Retry"
        case .forceReset: return "Reset"
        }
    }

    private func recoveryIcon(_ action: RecoveryAction) -> String {
        switch action {
        case .openSettings: return "gear"
        case .enableKeyboardMode: return "keyboard"
        case .retryConnection: return "arrow.clockwise"
        case .forceReset: return "arrow.counterclockwise"
        }
    }

    // MARK: - Debug Section

    #if DEBUG
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            TalkieEyebrow(text: "Debug", tint: .ink, showLeader: false)

            VStack(alignment: .leading, spacing: 2) {
                Text("state: \(sharedStore.phase.rawValue)")
                Text("active: \(headlessService.isActive ? "yes" : "no")  ready: \(headlessService.isInReadyMode ? "yes" : "no")")
                Text("engine selection: apple \u{2713}  parakeet \(parakeetIsReady ? "\u{2713}" : parakeetStatus)  \u{2192} \(parakeetIsReady ? "parakeet" : "apple")")
                Text("parakeet: \(parakeetStatus)")
                Text("deeplink: \(deepLinkManager.lastDeepLinkURL ?? "nil")")
            }
            .font(.system(size: 9, weight: .regular, design: .monospaced))
            .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.sm)
    }
    private var parakeetStatus: String {
        ParakeetModelManager.shared.statusDescription
    }

    private var parakeetIsReady: Bool {
        ParakeetModelManager.shared.isReady
    }
    #endif

    // MARK: - Activity Ticker

    @ViewBuilder
    private var activityTicker: some View {
        if !activityLog.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                TalkieEyebrow(text: "Log", tint: .ink, showLeader: false)
                    .padding(.bottom, 8)

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(activityLog.enumerated()), id: \.element.id) { index, entry in
                                let distanceFromEnd = activityLog.count - 1 - index
                                let opacity: Double = switch distanceFromEnd {
                                    case 0: 1.0
                                    case 1: 0.7
                                    case 2: 0.55
                                    case 3: 0.45
                                    case 4: 0.35
                                    case 5: 0.28
                                    case 6: 0.22
                                    case 7: 0.18
                                    case 8: 0.14
                                    default: 0.10
                                }

                                Text("\(entry.event)  +\(relativeTime(entry.timestamp))")
                                    .font(.system(size: 10, weight: distanceFromEnd == 0 ? .medium : .regular, design: .monospaced))
                                    .foregroundColor(.textTertiary.opacity(opacity))
                                    .id(entry.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                    .onChange(of: activityLog.count) { _, _ in
                        if let last = activityLog.last {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func attemptReturnIfPossible() {
        guard !hasReturned else { return }
        if deepLinkManager.callSuccessCallback() {
            hasReturned = true
        }
    }

    private func checkForReturn() {
        guard !hasReturned else { return }
        if currentState == .done || currentState == .ready {
            returnAttemptCount += 1
            if deepLinkManager.returnToSourceBestEffort() {
                hasReturned = true
            } else if returnAttemptCount > 10 && !showReturnExplainer {
                // After ~2 seconds of trying, show the explainer
                withAnimation(.easeIn(duration: 0.3)) {
                    showReturnExplainer = true
                }
            }
        }
    }

    private func stopRecording() {
        logActivity("Stop requested")
        if let sessionId = sharedStore.activeSessionId {
            _ = sharedStore.keyboardRequestStop(sessionId: sessionId)
        } else {
            logActivity("Stop via bridge fallback")
        }
        bridge.requestStopRecording()
    }

    /// Auto-retry audio session when keyboard mode is active but audio isn't ready.
    /// Silently handles the "audio session not active" state so users don't see technical buttons.
    private func autoRecoverAudioSession() {
        guard currentState == .ready || currentState == .idle || currentState == .arming || currentState == .recording else { return }

        // Shared state can occasionally get stuck in .recording while no recorder is active.
        // Treat that as a recoverable connection issue and re-trigger dictation setup.
        if currentState == .recording && !isRecordingPipelineActive {
            audioRetryCount += 1
            guard UIApplication.shared.applicationState == .active else { return }
            if audioRetryCount % 10 == 1 {
                logActivity("Recovering recorder state")
                headlessService.handleDictationRequest()
            }
            return
        }

        guard headlessService.isActive && !headlessService.isInReadyMode && !headlessService.isRecording else {
            audioRetryCount = 0
            return
        }

        // Don't attempt recovery when app isn't active — handleDictationRequest will
        // just timeout waiting for .active state, force-reset, and cascade into an
        // infinite loop of retries.
        guard UIApplication.shared.applicationState == .active else { return }

        audioRetryCount += 1
        // Auto-retry every ~2 seconds (10 ticks at 0.2s interval)
        if audioRetryCount % 10 == 1 {
            logActivity("Reconnecting audio")
            headlessService.handleDictationRequest()
        }
    }

    private func updateRecordingDuration() {
        if let start = recordingStartTime, currentState == .recording, isRecordingPipelineActive {
            recordingDuration = Date().timeIntervalSince(start)
        } else if currentState != .recording {
            recordingDuration = 0
            recordingStartTime = nil
        }
    }

    private var isRecordingPipelineActive: Bool {
        headlessService.isRecording || bridge.isRecordingInProgress()
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Activity Log

    private func handleStateTransition(from old: DictationSharedState.Phase, to new: DictationSharedState.Phase) {
        switch new {
        case .ready:
            logActivity("Ready")
        case .recording:
            logActivity("Capturing voice")
        case .stopping:
            logActivity("Stopping")
        case .transcribing:
            loggedEngineForTranscription = false
            let engine = TranscriptionService.lastUsedEngineName
            if !engine.isEmpty {
                logActivity("Transcribing via \(engine)")
                loggedEngineForTranscription = true
            } else {
                logActivity("Transcribing")
            }
        case .done:
            if let text = sharedStore.lastResult?.text, !text.isEmpty {
                lastTranscript = text
                copiedToClipboard = false
            }
            logActivity("Done")
        case .idle, .arming, .error:
            break
        }
    }

    /// If engine name becomes available after the "Transcribing" log was written, update it
    private func trackEngineSelection() {
        guard currentState == .transcribing, !loggedEngineForTranscription else { return }
        let engine = TranscriptionService.lastUsedEngineName
        guard !engine.isEmpty else { return }
        logActivity("Engine: \(engine)")
        loggedEngineForTranscription = true
    }

    private func trackModelLoading() {
        let manager = ParakeetModelManager.shared
        let isLoading: Bool
        if case .loading = manager.state { isLoading = true } else { isLoading = false }

        if isLoading && !wasModelLoading {
            logActivity("Loading model")
        } else if !isLoading && wasModelLoading {
            logActivity("Model ready")
        }
        wasModelLoading = isLoading
    }

    private func logActivity(_ event: String) {
        let entry = ActivityEntry(timestamp: Date(), event: event)
        withAnimation(.easeInOut(duration: 0.4)) {
            activityLog.append(entry)
            if activityLog.count > 15 {
                activityLog.removeFirst(activityLog.count - 15)
            }
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(date.timeIntervalSince(flowStartTime))
        return "\(max(0, seconds))s"
    }
}

#Preview {
    KeyboardActivationView()
}
