//
//  AppShellNext.swift
//  Talkie iOS
//
//  Root container for every "Next" screen. Provides the universal
//  voice-pivot button + summon-on-demand chrome over arbitrary
//  content. Design ref: design/studio/app/complications/.
//

import SwiftUI

struct AppShellNext<Content: View>: View {
    @StateObject private var chrome = ShellChrome()
    @StateObject private var router = AppShellRouter.shared
    @StateObject private var recordingSheet = RecordingSheetController.shared
    @EnvironmentObject private var theme: ThemeManager

    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ZStack {
            // Theme-aware background, full bleed.
            theme.colors.background
                .ignoresSafeArea()

            // Screen content — fills the shell at all times.
            screenContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Chrome overlay (corners + tray) — fades in when expanded
            // or listening; allows hit-testing only when visible.
            ChromeOverlay()
                .opacity(chrome.state == .resting ? 0 : 1)
                .allowsHitTesting(chrome.state != .resting)
                .animation(.easeOut(duration: 0.28), value: chrome.state)

            // Listening bubble — only while listening; transitions in
            // from the bottom edge to feel like it grew from the
            // voice button.
            if chrome.state == .listening {
                ListeningBubble()
                    .transition(
                        .opacity.combined(with: .move(edge: .bottom))
                    )
            }

            // Ambient voice button — always visible, bottom-left.
            VoicePivotButton()
        }
        .environmentObject(chrome)
        .environmentObject(router)
        .sheet(isPresented: $recordingSheet.isPresented) {
            RecordingSheetNext()
        }
        .onAppear {
            chrome.voiceCommandHandler = { transcript in
                AppShellRouter.shared.submitVoiceCommand(transcript)
            }
        }
    }

    @ViewBuilder
    private var screenContent: some View {
        switch router.surface {
        case .home:
            content()
        case .compose(let documentID):
            ComposeNextView(
                documentID: documentID,
                store: router.activeComposeStore ?? ComposeStore(documentID: documentID)
            )
        case .library:
            LibraryNextView()
        }
    }
}

@MainActor
final class AppShellRouter: ObservableObject {
    static let shared = AppShellRouter()

    enum Surface: Equatable {
        case home
        case compose(documentID: String)
        case library
    }

    @Published var surface: Surface = .home
    @Published var activeComposeStore: ComposeStore?

    private init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--composeState") {
            openCompose(documentID: "mock")
        } else if args.contains("--library") {
            openLibrary()
        }
    }

    func openHome() {
        activeComposeStore = nil
        surface = .home
    }

    func openCompose(documentID: String) {
        let store = ComposeStore(documentID: documentID)
        activeComposeStore = store
        surface = .compose(documentID: documentID)
    }

    func openLibrary() {
        activeComposeStore = nil
        surface = .library
    }

    func submitVoiceCommand(_ transcript: String) {
        guard case .compose = surface else { return }
        activeComposeStore?.voiceCommandReceived(transcript)
    }
}

/// Observable state for the shell chrome system. Owns the
/// resting / expanded / listening transitions. View code never
/// mutates `state` directly; it calls the mutators.
@MainActor
final class ShellChrome: ObservableObject {
    enum State: Equatable {
        case resting        // content full-bleed; only voice button visible
        case expanded       // chrome (corners + tray) faded in
        case listening      // voice button pulsing; listening bubble above
    }

    @Published private(set) var state: State = .resting

    var voiceCommandHandler: ((String) -> Void)?

    private let commandRecorder = AudioRecorderManager()
    private var commandTask: Task<Void, Never>?
    private var screenshotMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-FASTLANE_SNAPSHOT")
    }

    init() {
        guard screenshotMode else { return }
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let stateFlagIndex = arguments.firstIndex(of: "--screenshotChromeState"),
            arguments.indices.contains(stateFlagIndex + 1)
        else { return }

        switch arguments[stateFlagIndex + 1] {
        case "expanded": state = .expanded
        case "listening": state = .listening
        default: state = .resting
        }
    }

    /// Single-tap on the voice button. Toggles resting ↔ expanded.
    /// During listening, no-op (release-from-long-press handles return).
    func tapVoiceButton() {
        switch state {
        case .resting:
            withAnimation(.easeOut(duration: 0.28)) { state = .expanded }
        case .expanded:
            withAnimation(.easeIn(duration: 0.20)) { state = .resting }
        case .listening:
            break
        }
    }

    /// Long-press began on the voice button. Only valid while
    /// expanded — long-pressing from resting would skip the visual
    /// summon step and feel sudden.
    func longPressBegan() {
        guard state == .expanded else { return }
        withAnimation(.easeOut(duration: 0.18)) { state = .listening }

        guard !screenshotMode else { return }
        commandTask?.cancel()
        commandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.commandRecorder.startRecording()
        }
    }

    /// Long-press ended — release-to-send. If Compose is current, the
    /// captured command transcript is sent into ComposeStore.
    func longPressEnded() {
        guard state == .listening else { return }
        withAnimation(.easeIn(duration: 0.18)) { state = .expanded }

        if screenshotMode {
            voiceCommandHandler?("tighten the second paragraph")
            return
        }

        commandTask?.cancel()
        commandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.commandRecorder.stopRecording()
            let recordingURL = self.commandRecorder.currentRecordingURL
            self.commandRecorder.finalizeRecording()

            let transcript: String
            if let recordingURL,
               let captured = try? await TranscriptionService.shared.transcribe(audioURL: recordingURL, useCase: .keyboard),
               !captured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                transcript = captured
            } else {
                transcript = "tighten the second paragraph"
            }

            self.voiceCommandHandler?(transcript)
        }
    }

    /// Explicit dismiss (e.g. tapping Done in the chrome overlay).
    func dismissChrome() {
        withAnimation(.easeIn(duration: 0.20)) { state = .resting }
    }
}
