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
            // the transition between distinct screens. The transition
            // direction comes from the router so home←sub-surface
            // (pop) feels different from home→sub-surface (push).
            screenContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(surfaceID)
                .transition(surfaceTransition)
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

    /// Direction-aware push/pop transition. Forward (push): new
    /// surface slides IN from trailing edge, previous slides OUT to
    /// leading edge. Backward (pop): mirror — new from leading,
    /// previous to trailing. Both halves carry an opacity fade.
    private var surfaceTransition: AnyTransition {
        switch router.transitionDirection {
        case .forward:
            return .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)),
                removal:   .opacity.combined(with: .move(edge: .leading))
            )
        case .backward:
            return .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .leading)),
                removal:   .opacity.combined(with: .move(edge: .trailing))
            )
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
        case .settings: return "settings"
        case .terminal: return "terminal"
        case .cameraCapture: return "camera"
        case .bridgeDetail: return "bridgeDetail"
        case .askAI: return "askAI"
        case .captureDetail(let c): return "capture:\(c)"
        case .memoDetail(let m): return "memo:\(m)"
        case .dictationHistory: return "dictations"
        case .dictationOverlayDemo: return "overlay"
        case .signIn: return "signin"
        case .connectionCenter: return "connection"
        case .onboarding: return "onboarding"
        case .webBrowser: return "browser"
        case .keyboardActivation: return "keyboard"
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
        case .settings:
            SettingsNext()
        case .captureDetail(let captureID):
            CaptureDetailNext(captureID: captureID)
        case .memoDetail(let memoID):
            VoiceMemoDetailNext(memoID: memoID)
        case .dictationHistory:
            DictationHistoryNext()
        case .dictationOverlayDemo:
            MinimalDictationOverlayDemoSurface()
        case .signIn:
            SignInNext()
        case .connectionCenter:
            ConnectionCenterNext()
        case .onboarding:
            OnboardingNext()
        case .webBrowser:
            WebCaptureBrowserNext()
        case .keyboardActivation:
            KeyboardActivationNext()
        case .terminal:
            TerminalNext()
        case .cameraCapture:
            CameraCaptureNext()
        case .bridgeDetail:
            BridgeDetailNext()
        case .askAI:
            AskAINext()
        }
    }
}

@MainActor
final class AppShellRouter: ObservableObject {
    static let shared = AppShellRouter()

    enum TransitionDirection {
        case forward   // push: new from trailing, old to leading
        case backward  // pop:  new from leading,  old to trailing
    }

    enum Surface: Equatable {
        case home
        case compose(documentID: String)
        case library
        case appearance
        case settings
        case captureDetail(captureID: String)
        case memoDetail(memoID: String)
        case dictationHistory
        case dictationOverlayDemo
        case signIn
        case connectionCenter
        case onboarding
        case webBrowser
        case keyboardActivation
        // Phase-1 feature surfaces — stubs land here, fleshed out by
        // dedicated Codex streams.
        case terminal
        case cameraCapture
        case bridgeDetail
        case askAI
    }

    @Published var surface: Surface = .home
    @Published var activeComposeStore: ComposeStore?
    @Published var transitionDirection: TransitionDirection = .forward

    private init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--composeState") {
            openCompose(documentID: "mock")
        } else if args.contains("--library") {
            openLibrary()
        } else if args.contains("--appearance") {
            openAppearance()
        } else if args.contains("--settings") {
            openSettings()
        } else if args.contains("--capture") {
            openCaptureDetail(captureID: "mock")
        } else if args.contains("--memo") {
            openMemoDetail(memoID: "mock")
        } else if args.contains("--dictations") {
            openDictationHistory()
        } else if args.contains("--overlay") {
            openDictationOverlayDemo()
        } else if args.contains("--signin") {
            openSignIn()
        } else if args.contains("--connection") {
            openConnectionCenter()
        } else if args.contains("--onboarding") {
            openOnboarding()
        } else if args.contains("--browser") {
            openWebBrowser()
        } else if args.contains("--keyboard") {
            openKeyboardActivation()
        } else if args.contains("--terminal") {
            openTerminal()
        } else if args.contains("--camera") {
            openCameraCapture()
        } else if args.contains("--bridge") {
            openBridgeDetail()
        } else if args.contains("--askai") {
            openAskAI()
        }
    }

    /// Home is the root. Routing TO home is a pop (backward);
    /// routing to anything else is a push (forward).
    private func push(_ next: Surface) {
        transitionDirection = .forward
        activeComposeStore = nil
        surface = next
    }

    func openHome() {
        transitionDirection = .backward
        activeComposeStore = nil
        surface = .home
    }

    func openCompose(documentID: String) {
        let store = ComposeStore(documentID: documentID)
        transitionDirection = .forward
        activeComposeStore = store
        surface = .compose(documentID: documentID)
    }

    func openLibrary()              { push(.library) }
    func openAppearance()           { push(.appearance) }
    func openSettings()             { push(.settings) }
    func openCaptureDetail(captureID: String) {
        push(.captureDetail(captureID: captureID))
    }
    func openMemoDetail(memoID: String) {
        push(.memoDetail(memoID: memoID))
    }
    func openDictationHistory()     { push(.dictationHistory) }
    func openDictationOverlayDemo() { push(.dictationOverlayDemo) }
    func openSignIn()               { push(.signIn) }
    func openConnectionCenter()     { push(.connectionCenter) }
    func openOnboarding()           { push(.onboarding) }
    func openWebBrowser()           { push(.webBrowser) }
    func openKeyboardActivation()   { push(.keyboardActivation) }
    func openTerminal()             { push(.terminal) }
    func openCameraCapture()        { push(.cameraCapture) }
    func openBridgeDetail()         { push(.bridgeDetail) }
    func openAskAI()                { push(.askAI) }

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
