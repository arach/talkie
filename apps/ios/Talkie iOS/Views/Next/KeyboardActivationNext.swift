//
//  KeyboardActivationNext.swift
//  Talkie iOS
//
//  Faithful re-port of KeyboardActivationView (apps/ios/Talkie iOS/
//  Views/KeyboardActivationView.swift, 829 lines). The donor is a
//  LIVE STATUS / TRANSCRIPT VIEW that runs while the keyboard
//  extension is active — not a setup checklist.
//
//  Donor structure:
//  - Top bar: X dismiss · 'Keyboard Mode' eyebrow · keyboard mode
//    toggle.
//  - 180pt transcript region (fixed reserved area) — shows last
//    transcript when phase == .done with a copy button.
//  - State-driven status content centred below:
//    .idle / .arming / .ready  → "Ready" + "Start Dictation"
//    .recording                 → red dot + duration + "End Dictation"
//    .stopping / .transcribing  → BrailleSpinner + transcription label
//    .done                      → checkmark + "Done"
//    .error                     → error message + recovery buttons
//  - Bottom info card explaining iOS's no-app-switching constraint,
//    dismissable to a question-mark icon.
//
//  Codex wires real bindings against DictationSharedState +
//  HeadlessDictationService + KeyboardBridge + TranscriptionService
//  + DictationReadinessChecker. Paint here uses a mock store with
//  the same Phase enum so all visual states are observable.
//

import SwiftUI
import TalkieMobileKit

@MainActor
final class KeyboardActivationStore: ObservableObject {
    @Published var phase: Phase = .idle
    @Published var keyboardModeEnabled: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var lastTranscript: String?
    @Published var errorMessage: String?
    @Published var returnInfoDismissed: Bool = false {
        didSet {
            guard returnInfoDismissed != oldValue else { return }
            UserDefaults.standard.set(returnInfoDismissed, forKey: Self.returnInfoDismissedKey)
        }
    }

    private static let returnInfoDismissedKey = "KeyboardActivationNext.returnInfoDismissed"

    private let headlessService = HeadlessDictationService.shared
    private let sharedStore = DictationSharedStore.shared
    private let bridge = KeyboardBridge.shared
    private var checker = DictationReadinessChecker()
    private var recordingStartTime: Date?
    private var screenshotPhaseOverride = false

    enum Phase: String {
        case idle, arming, ready, recording, stopping, transcribing, done, error
    }

    var showsKeyboardSetup: Bool {
        switch phase {
        case .idle, .arming, .ready, .error:
            true
        case .recording, .stopping, .transcribing, .done:
            false
        }
    }

    init() {
        returnInfoDismissed = UserDefaults.standard.bool(forKey: Self.returnInfoDismissedKey)

        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--kbdPhase"), i + 1 < args.count {
            self.phase = Phase(rawValue: args[i + 1]) ?? .ready
            self.keyboardModeEnabled = true
            self.screenshotPhaseOverride = true
            // Seed mock transcript so the .done state has content for screenshot/UI test modes.
            self.lastTranscript = "moving the meeting to 4pm if that works for everyone — let me know"
        } else {
            refreshFromLiveState()
        }
    }

    func onAppear() {
        refreshFromLiveState()
        checker.evaluate()
    }

    func tick() {
        guard !screenshotPhaseOverride else { return }
        refreshFromLiveState()
        checker.evaluate()
    }

    func startDictation() {
        headlessService.handleDictationRequest()
        refreshFromLiveState()
    }

    func stopDictation() {
        if let sessionId = sharedStore.activeSessionId {
            _ = sharedStore.keyboardRequestStop(sessionId: sessionId)
        }
        bridge.requestStopRecording()
        refreshFromLiveState()
    }

    func toggleKeyboardMode() {
        if screenshotPhaseOverride {
            keyboardModeEnabled.toggle()
            return
        }

        if headlessService.isActive {
            headlessService.deactivate(explicit: true)
        } else {
            headlessService.activate()
        }
        refreshFromLiveState()
    }

    func performRecovery(_ action: RecoveryAction) {
        checker.perform(action)
        refreshFromLiveState()
    }

    func openKeyboardSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func refreshFromLiveState() {
        let sharedPhase = sharedStore.phase
        let nextPhase = Phase(rawValue: sharedPhase.rawValue) ?? .idle

        if phase != nextPhase {
            handleTransition(to: nextPhase)
        }

        phase = nextPhase
        keyboardModeEnabled = headlessService.isActive
        errorMessage = sharedStore.lastError?.message

        if let text = sharedStore.lastResult?.text, !text.isEmpty {
            lastTranscript = text
        }

        updateRecordingDuration(for: nextPhase)
    }

    private func handleTransition(to newPhase: Phase) {
        if newPhase == .recording {
            let phaseStart = sharedStore.phaseUpdatedAt
            recordingStartTime = phaseStart > 0 ? Date(timeIntervalSince1970: phaseStart) : Date()
        } else if newPhase != .recording {
            recordingStartTime = nil
        }
    }

    private func updateRecordingDuration(for currentPhase: Phase) {
        if currentPhase == .recording,
           let recordingStartTime,
           headlessService.isRecording || bridge.isRecordingInProgress() {
            recordingDuration = Date().timeIntervalSince(recordingStartTime)
        } else if currentPhase != .recording {
            recordingDuration = 0
        }
    }
}

struct KeyboardActivationNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var store = KeyboardActivationStore()
    @State private var copiedToClipboard = false

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                // 180pt reserved transcript region — same fixed
                // height as the donor so layout doesn't shift.
                transcriptRegion
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                Spacer()

                statusContent
                    .padding(.horizontal, 16)

                Spacer()

                if store.showsKeyboardSetup {
                    keyboardSetupCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                bottomInfoArea
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .onAppear { store.onAppear() }
        .onReceive(Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()) { _ in
            store.tick()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button(action: { AppShellRouter.shared.openHome() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close keyboard setup")

            Spacer()

            Text("· KEYBOARD MODE")
                .talkieType(.channelLabel)
                .foregroundStyle(theme.colors.textTertiary)

            Spacer()

            Button(action: store.toggleKeyboardMode) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(store.keyboardModeEnabled ? .green : theme.colors.textTertiary.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text(store.keyboardModeEnabled ? "ON" : "OFF")
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.colors.textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.keyboardModeEnabled ? "Disable keyboard mode" : "Enable keyboard mode")
            .accessibilityValue(store.keyboardModeEnabled ? "On" : "Off")
            .accessibilityHint("Toggles Talkie keyboard dictation mode.")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth),
            alignment: .bottom
        )
    }

    // MARK: - Transcript region (fixed 180pt)

    private var transcriptRegion: some View {
        ZStack(alignment: .topTrailing) {
            if let transcript = store.lastTranscript, store.phase == .done {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(transcript)
                        .talkieType(.preview)
                        .foregroundStyle(theme.colors.textSecondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .padding(.trailing, 32)
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.colors.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                              lineWidth: theme.currentTheme.chrome.hairlineWidth)
                        )
                )
                .transition(.opacity)

                Button(action: { copyTranscript(transcript) }) {
                    Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(copiedToClipboard ? .green : theme.colors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(theme.colors.textTertiary.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
        .frame(height: 180)
        .animation(.easeInOut(duration: 0.3),
                   value: store.lastTranscript != nil && store.phase == .done)
    }

    // MARK: - Status content (state-driven)

    @ViewBuilder
    private var statusContent: some View {
        if let err = store.errorMessage {
            errorView(err)
        } else {
            switch store.phase {
            case .idle, .arming:                connectingView
            case .ready:                        readyView
            case .recording:                    recordingView
            case .stopping, .transcribing:      processingView
            case .done:                         doneView
            case .error:                        connectingView
            }
        }
    }

    private var connectingView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text("INITIALIZING")
                    .talkieType(.channelLabel)
                    .foregroundStyle(theme.colors.textTertiary)
            }

            VStack(spacing: 4) {
                activityRow("Audio session", active: true)
                activityRow("Keyboard mode", active: store.keyboardModeEnabled)
                activityRow("Bridge sync", active: false)
            }
            .padding(.top, 4)
        }
    }

    private func activityRow(_ label: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active ? Color.green.opacity(0.8) : theme.colors.textTertiary.opacity(0.4))
                .frame(width: 5, height: 5)
            Text(label)
                .talkieType(.timestamp)
                .foregroundStyle(active ? theme.colors.textSecondary : theme.colors.textTertiary)
            Spacer()
            Text(active ? "OK" : "…")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(active ? Color.green.opacity(0.7) : theme.colors.textTertiary)
        }
        .frame(maxWidth: 180)
    }

    private var readyView: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.green)
                    .frame(width: 10, height: 10)
                Text("Ready")
                    .talkieType(.listTitle)
                    .foregroundStyle(theme.colors.textSecondary)
            }

            Button(action: store.startDictation) {
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Start Dictation")
                        .talkieType(.preview)
                }
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.currentTheme.chrome.accentTint)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var recordingView: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .shadow(color: .red.opacity(0.6),
                            radius: theme.currentTheme.chrome.glowRadius)
                Text(formatDuration(store.recordingDuration))
                    .talkieType(.instrumentReadoutSmall)
                    .foregroundStyle(theme.colors.textSecondary)
                    .monospacedDigit()
            }

            Button(action: store.stopDictation) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("End Dictation")
                        .talkieType(.preview)
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var processingView: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7)
            Text(processingLabel)
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    private var processingLabel: String {
        store.phase == .stopping ? "Stopping…" : "Transcribing…"
    }

    private var doneView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.green)
            Text("Done")
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    private var keyboardSetupCard: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "keyboard")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(theme.colors.textTertiary.opacity(0.10)))

            VStack(alignment: .leading, spacing: 3) {
                Text("Talkie Keyboard")
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.textSecondary)
                Text("Add it in iOS Settings, then allow full access.")
                    .talkieType(.hint)
                    .foregroundStyle(theme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action: store.openKeyboardSettings) {
                HStack(spacing: 4) {
                    Image(systemName: "gear")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Settings")
                        .talkieType(.channelLabelTiny)
                }
                .foregroundStyle(theme.colors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.colors.textTertiary.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(theme.colors.textTertiary.opacity(0.22), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Talkie settings")
            .accessibilityHint("Shows iOS settings for enabling the Talkie Keyboard extension.")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(theme.colors.textTertiary.opacity(0.15), lineWidth: 0.5)
                )
        )
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Text("· ERROR")
                .talkieType(.channelLabel)
                .foregroundStyle(.red)
            Text(message)
                .talkieType(.fieldLabel)
                .foregroundStyle(theme.colors.textTertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                techButton("Settings", icon: "gear") {
                    store.performRecovery(.openSettings)
                }
                techButton("Retry", icon: "arrow.clockwise") {
                    store.performRecovery(.retryConnection)
                }
            }
        }
    }

    private func techButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                Text(label.uppercased())
                    .talkieType(.channelLabelTiny)
            }
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(theme.colors.textTertiary.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(theme.colors.textTertiary.opacity(0.25), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom info (donor's returnInfoCard)

    @ViewBuilder
    private var bottomInfoArea: some View {
        if !store.returnInfoDismissed {
            returnInfoCard
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            HStack {
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        store.returnInfoDismissed = false
                    }
                }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(theme.colors.textTertiary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var returnInfoCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.colors.textSecondary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("Switch back to your app to continue")
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.textSecondary)
                Text("iOS doesn't allow keyboard extensions to switch apps automatically. This is an Apple platform limitation.")
                    .talkieType(.hint)
                    .foregroundStyle(theme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    store.returnInfoDismissed = true
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(theme.colors.textTertiary.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss tip")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(theme.colors.textTertiary.opacity(0.15), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Helpers

    private func copyTranscript(_ text: String) {
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) { copiedToClipboard = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_200))
            withAnimation(.easeInOut(duration: 0.2)) { copiedToClipboard = false }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
