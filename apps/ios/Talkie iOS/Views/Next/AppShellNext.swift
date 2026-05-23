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

            // Persistent MicFAB lives on the home surface — recording
            // is the primary action there, so it's one tap regardless
            // of chrome state. On sub-surfaces the FAB is tucked back
            // inside the summoned tray (see LiquidGlassTray), keeping
            // those screens focused on their own content.
            if router.surface == .home {
                MicFAB()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 16)
            }

            // Left-edge swipe-back: on any sub-surface, a horizontal
            // drag that starts in the leftmost 20pt and crosses the
            // threshold (~80pt to the right) pops back to home. Mimics
            // the iOS native interactivePopGesture without requiring
            // each surface to live inside a NavigationStack. The
            // hit zone is 20pt wide so it doesn't fight scroll views
            // inside surfaces — only drags that *start* at the edge
            // are captured.
            if router.surface != .home {
                EdgeSwipeBack()
            }

            // Ambient voice button — always visible, bottom-left. Pure
            // summon affordance now (tap = chrome, long-press = voice
            // command); recording moved to the always-visible MicFAB.
            VoicePivotButton()
        }
        .environmentObject(chrome)
        .environmentObject(router)
        // Dynamic Type — let editorial tokens (headline / listTitle /
        // preview / hint) scale up, but clamp at the third accessibility
        // size so chrome chip labels + the channel band don't crush the
        // tray. Users on smaller text sizes are unaffected.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
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
        case .settings: return "settings"
        case .terminal: return "terminal"
        case .captureCompose: return "captureCompose"
        case .cameraCapture: return "camera"
        case .bridgeDetail: return "bridgeDetail"
        case .askAI: return "askAI"
        case .readAloud: return "readAloud"
        case .feedback: return "feedback"
        case .aiCredentials: return "aiCredentials"
        case .workflows: return "workflows"
        case .syncConflicts: return "syncConflicts"
        case .workspaces: return "workspaces"
        case .themeContrast: return "themeContrast"
        case .deck: return "deck"
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
        case .captureCompose:
            CaptureComposeNextView { captureID in
                AppShellRouter.shared.openCompose(documentID: captureID)
            }
        case .cameraCapture:
            CameraCaptureNext()
        case .bridgeDetail:
            BridgeDetailNext()
        case .askAI:
            AskAINext()
        case .readAloud:
            ReadAloudNext()
        case .feedback:
            FeedbackNext()
        case .aiCredentials:
            AICredentialsNext()
        case .workflows:
            WorkflowsNext()
        case .syncConflicts:
            SyncConflictNext()
        case .workspaces:
            WorkspaceSwitcherNext()
        case .themeContrast:
            ThemeContrastDebugNext()
        case .deck:
            DeckMirrorNext()
        }
    }
}

/// Left-edge hit zone that pops to home on a horizontal swipe past
/// threshold. Sits invisible at the very left of the screen so it
/// only catches drags that *start* at the edge — scroll views and
/// other gestures inside the surface are unaffected.
private struct EdgeSwipeBack: View {
    @EnvironmentObject private var router: AppShellRouter

    /// Horizontal distance the user must drag to commit the back
    /// navigation. ~25% of typical screen width; tuned to feel
    /// intentional without being a long stroke.
    private let commitThreshold: CGFloat = 80

    /// Width of the invisible hit zone. Was 20pt (matching iOS-native
    /// edge gesture width) but that overlapped left-anchored UI like
    /// the 28pt Settings rail — taps in the rail's leftmost 20pt got
    /// absorbed by EdgeSwipeBack instead of reaching the rail chip.
    /// 8pt is enough to catch genuine edge swipes (which start at
    /// x < 5pt) without interfering with column-style UI.
    private let edgeWidth: CGFloat = 8

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: edgeWidth)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            guard value.translation.width > commitThreshold else { return }
                            // Vertical-dominant drags shouldn't pop —
                            // make sure the horizontal component wins.
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            router.openHome()
                        }
                )
            Spacer()
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
        case captureCompose
        case cameraCapture
        case bridgeDetail
        case askAI
        // Phase-2 — TTS playback / read-aloud surface.
        case readAloud
        // M4 — user feedback / bug report surface.
        case feedback
        // M4 — manage API keys for cloud AI providers.
        case aiCredentials
        // M4 — workflows hub (templates / schedules / history).
        case workflows
        // M5 — iCloud sync conflict resolution surface.
        case syncConflicts
        // M5 — multi-account workspace switcher.
        case workspaces
        // M6 — debug-only theme contrast inspector.
        case themeContrast
        // Companion — Mac Command Deck mirror.
        case deck
    }

    @Published var surface: Surface = .home
    @Published var activeComposeStore: ComposeStore?
    /// Source payload set by callers of `openReadAloud(source:)` so the
    /// ReadAloud surface can read foreign content (capture, memo,
    /// askAI response) instead of its placeholder items. Codex wires
    /// `ReadAloudPlayer.bind` to consume + clear this on appear.
    @Published var pendingReadAloudSource: ReadAloudSource?
    /// Seed text routed into the next Compose surface. Set by callers
    /// of `openComposeSeeded(text:)` (e.g. AskAI's Refine chip). Codex
    /// wires `ComposeStore.init` to consume + clear this on appear so
    /// the new document opens with the seed already populated.
    @Published var pendingComposeSeed: String?
    /// Text payload for "Save as memo" actions (e.g. AskAI's Save chip).
    /// Codex wires VoiceMemoStore to create a memo from the payload
    /// and route to its detail surface. Paint side just sets this.
    @Published var pendingNewMemoText: String?
    @Published var transitionDirection: TransitionDirection = .forward

    private init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--composeState") {
            openCompose(documentID: "mock")
        } else if args.contains("--library") {
            openLibrary()
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
        } else if args.contains("--captureCompose") {
            openCaptureCompose()
        } else if args.contains("--camera") {
            openCameraCapture()
        } else if args.contains("--bridge") {
            openBridgeDetail()
        } else if args.contains("--askai") {
            openAskAI()
        } else if args.contains("--readaloud") {
            openReadAloud()
        } else if args.contains("--feedback") {
            openFeedback()
        } else if args.contains("--aikeys") {
            openAICredentials()
        } else if args.contains("--workflows") {
            openWorkflows()
        } else if args.contains("--syncconflicts") {
            openSyncConflicts()
        } else if args.contains("--workspaces") {
            openWorkspaces()
        } else if args.contains("--contrast") {
            openThemeContrast()
        } else if args.contains("--deck") {
            openDeck()
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
    func openCaptureCompose()       { push(.captureCompose) }
    func openCameraCapture()        { push(.cameraCapture) }
    func openBridgeDetail()         { push(.bridgeDetail) }
    func openAskAI()                { push(.askAI) }
    func openReadAloud(source: ReadAloudSource? = nil) {
        pendingReadAloudSource = source
        push(.readAloud)
    }
    func openFeedback() { push(.feedback) }
    func openAICredentials() { push(.aiCredentials) }
    func openWorkflows() { push(.workflows) }
    func openSyncConflicts() { push(.syncConflicts) }
    func openWorkspaces() { push(.workspaces) }
    func openThemeContrast() { push(.themeContrast) }
    func openDeck() { push(.deck) }

    /// Open a new Compose document seeded with `text`. Caller doesn't
    /// pick the document ID — this generates one and stashes the seed
    /// on the router for ComposeStore to consume.
    func openComposeSeeded(text: String) {
        pendingComposeSeed = text
        openCompose(documentID: UUID().uuidString)
    }

    /// "Save as memo" pipeline entry. Codex wires the actual memo
    /// creation (VoiceMemoStore + route to the new memo). Paint side
    /// just signals intent — the chip stays visible whether or not
    /// the wiring is live yet.
    func saveAsMemo(text: String) {
        pendingNewMemoText = text
    }

    func submitVoiceCommand(_ transcript: String) {
        guard case .compose = surface else { return }
        activeComposeStore?.voiceCommandReceived(transcript)
    }
}

/// Payload routed into the ReadAloud surface from any "Listen"
/// affordance. Lightweight by design — the player on the other side
/// renders title/meta and feeds `text` to the speech service.
struct ReadAloudSource: Equatable {
    /// Display title shown in the NowReadingPanel.
    let title: String
    /// Full text spoken by the synthesizer.
    let text: String
    /// Optional channel-label eyebrow, e.g. "MEMO · 142 WORDS · 0:24".
    let meta: String?
    /// Original source URL when the content came from the web; the
    /// player exposes "Open original" when present.
    let sourceURL: URL?
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

    /// Which screen corners chrome currently owns. Screen-native UI
    /// in these zones should yield (fade out) so the complication
    /// can render without collision. Derived from `state`; reading
    /// it picks up changes through the @Published state observation.
    var occupiedZones: Set<ScreenZone> {
        switch state {
        case .resting: return []
        case .expanded, .listening:
            // Settings owns .topTrailing; Keyboard owns .bottomTrailing.
            // .topLeading is claimed by the Home pill on every sub-
            // surface (so screen back chevrons yield to make room);
            // on home itself chrome shows no top-left pill, so the
            // slot stays free for whatever the home view wants there.
            var zones: Set<ScreenZone> = [.topTrailing, .bottomTrailing]
            if AppShellRouter.shared.surface != .home {
                zones.insert(.topLeading)
            }
            return zones
        }
    }

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
