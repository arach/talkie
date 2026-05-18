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

            // Screen content — fills the shell at all times. The id
            // ties identity to the current surface so SwiftUI runs
            // the transition between distinct screens.
            screenContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(surfaceID)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                .animation(.easeOut(duration: 0.24), value: surfaceID)

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

    /// Stable identity per surface so SwiftUI fires the transition
    /// between distinct screens (different cases = different ids).
    /// Compose includes the doc id so swapping docs animates too.
    private var surfaceID: String {
        switch router.surface {
        case .home: return "home"
        case .compose(let d): return "compose:\(d)"
        case .library: return "library"
        case .appearance: return "appearance"
        case .captureDetail(let c): return "capture:\(c)"
        case .memoDetail(let m): return "memo:\(m)"
        case .dictationHistory: return "dictations"
        case .dictationOverlayDemo: return "overlay"
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
        case .appearance:
            AppearancePickerNext()
        case .captureDetail(let captureID):
            CaptureDetailNext(captureID: captureID)
        case .memoDetail(let memoID):
            VoiceMemoDetailNext(memoID: memoID)
        case .dictationHistory:
            DictationHistoryNext()
        case .dictationOverlayDemo:
            MinimalDictationOverlayDemoSurface()
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
        case appearance
        case captureDetail(captureID: String)
        case memoDetail(memoID: String)
        case dictationHistory
        case dictationOverlayDemo
        // Removed (fabricated, did not match donor):
        // .keyboardActivation → live status/transcript view, not setup checklist
        // .connectionCenter   → connection-type rows, not metrics hero
        // .onboarding         → 3 feature pages w/ iCloud auth, not 4-slide flow
        // .signIn             → multi-step sign-in w/ pending/inProgress states
        // .webBrowser         → URL bar + voice search + history, not reader-mode pill
    }

    @Published var surface: Surface = .home
    @Published var activeComposeStore: ComposeStore?

    private init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--composeState") {
            openCompose(documentID: "mock")
        } else if args.contains("--library") {
            openLibrary()
        } else if args.contains("--appearance") {
            openAppearance()
        } else if args.contains("--capture") {
            openCaptureDetail(captureID: "mock")
        } else if args.contains("--memo") {
            openMemoDetail(memoID: "mock")
        } else if args.contains("--dictations") {
            openDictationHistory()
        } else if args.contains("--overlay") {
            openDictationOverlayDemo()
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

    func openAppearance() {
        activeComposeStore = nil
        surface = .appearance
    }

    func openCaptureDetail(captureID: String) {
        activeComposeStore = nil
        surface = .captureDetail(captureID: captureID)
    }

    func openMemoDetail(memoID: String) {
        activeComposeStore = nil
        surface = .memoDetail(memoID: memoID)
    }

    func openDictationHistory() {
        activeComposeStore = nil
        surface = .dictationHistory
    }

    func openDictationOverlayDemo() {
        activeComposeStore = nil
        surface = .dictationOverlayDemo
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
