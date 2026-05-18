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

@MainActor
final class KeyboardActivationStore: ObservableObject {
    @Published var phase: Phase = .ready
    @Published var keyboardModeEnabled: Bool = true
    @Published var recordingDuration: TimeInterval = 0
    @Published var lastTranscript: String?
    @Published var errorMessage: String?
    @Published var returnInfoDismissed: Bool = false

    enum Phase: String {
        case idle, arming, ready, recording, stopping, transcribing, done, error
    }

    init() {
        // Codex wires phase polling against DictationSharedState.shared.
        // Paint uses .ready by default; --kbdPhase arg switches.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--kbdPhase"), i + 1 < args.count {
            self.phase = Phase(rawValue: args[i + 1]) ?? .ready
        }
        // Seed mock transcript so the .done state has content.
        self.lastTranscript = "moving the meeting to 4pm if that works for everyone — let me know"
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

                bottomInfoArea
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
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

            Spacer()

            Text("· KEYBOARD MODE")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2.4)
                .foregroundStyle(theme.colors.textTertiary)

            Spacer()

            // Keyboard mode indicator — donor uses a real toggle
            // bound to HeadlessDictationService.isActive. Visual
            // pill here; Codex wires the binding.
            HStack(spacing: 4) {
                Circle()
                    .fill(store.keyboardModeEnabled ? .green : theme.colors.textTertiary.opacity(0.4))
                    .frame(width: 6, height: 6)
                Text(store.keyboardModeEnabled ? "ON" : "OFF")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
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
                        .font(.system(size: 13))
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
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2.4)
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
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(active ? theme.colors.textSecondary : theme.colors.textTertiary)
            Spacer()
            Text(active ? "OK" : "…")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
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
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
            }

            Button(action: { /* TODO M3+: headlessService.handleDictationRequest() */ }) {
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Start Dictation")
                        .font(.system(size: 13, weight: .medium))
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
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.colors.textSecondary)
                    .monospacedDigit()
            }

            Button(action: { /* TODO M3+: stop dictation */ }) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("End Dictation")
                        .font(.system(size: 13, weight: .medium))
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
                .font(.system(size: 14))
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
                .font(.system(size: 14))
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Text("· ERROR")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.textTertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                techButton("Settings", icon: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                techButton("Retry", icon: "arrow.clockwise") {
                    // TODO M3+: checker.perform(.retryConnection)
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
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.5)
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
                Text("iOS doesn't allow keyboard extensions to switch apps automatically. This is an Apple platform limitation.")
                    .font(.system(size: 11))
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.2)) { copiedToClipboard = false }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
