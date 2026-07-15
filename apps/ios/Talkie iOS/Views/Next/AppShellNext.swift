//
//  AppShellNext.swift
//  Talkie iOS
//
//  Root container for every "Next" screen. Provides the universal
//  voice-pivot button + summon-on-demand chrome over arbitrary
//  content. Design ref: design/studio/app/complications/.
//

import SwiftUI
import TalkieMobileKit

struct AppShellNext<Content: View>: View {
    @StateObject private var chrome = ShellChrome()
    @StateObject private var deepLinkManager = DeepLinkManager.shared
    @StateObject private var router = AppShellRouter.shared
    @StateObject private var recordingSheet = RecordingSheetController.shared
    @EnvironmentObject private var theme: ThemeManager

    /// One-time discoverability: the Talkie pivot's long-press has no visible
    /// hint for sighted users (only VoicePivotButton's accessibilityHint). The
    /// first time controls are summoned we surface a "HOLD TO TALK" caption
    /// by the center pivot, then never again.
    @AppStorage("hasSeenWalkieHint") private var hasSeenWalkieHint = false
    @State private var showWalkieHint = false

    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ZStack {
            // Theme-aware background, full bleed.
            theme.colors.background
                .ignoresSafeArea()

            // Ambient canvas light — a faint top-center lift near the wordmark,
            // so every home shadow and highlight has something to be relative to
            // (a uniform backdrop reads flat). plusLighter only lightens, so on
            // paper themes it's a near-noop; on dark themes it lifts the canvas.
            // Scoped to Home to leave other surfaces exactly as they were.
            if router.surface == .home {
                CanvasAmbientLight()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

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

            // Listening bubble - only while listening; transitions in
            // from the bottom edge to feel like it grew from the
            // center Talkie pivot.
            if chrome.state == .listening {
                ListeningBubble()
                    .transition(
                        .opacity.combined(with: .move(edge: .bottom))
                    )
            }

            // Processing indicator — bridges the release-to-dispatch gap.
            // The ListeningBubble is already gone; this compact "SENDING…"
            // variant sits in the same slot until the command lands/errors.
            if chrome.isProcessingCommand {
                ProcessingBubble()
                    .transition(
                        .opacity.combined(with: .move(edge: .bottom))
                    )
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

            // Transient failure toast — the voice loop never fails
            // silently. Top edge, clear of the bottom chrome.
            FeedbackToastOverlay()
                .padding(.top, 8)

            // Ambient Talkie pivot - always visible at bottom-center. At rest
            // it is the Talkie T that summons chrome; as the menu unfolds it
            // becomes the mic. Recording is no longer a persistent bottom FAB.
            // Tucks away while the Compose keyboard is raised so it doesn't
            // sit on the keyboard's bottom row.
            //
            // One-time "HOLD TO TALK" caption - rides just above the pivot
            // button's bottom-center slot the first time controls are summoned,
            // then never again (persisted via hasSeenWalkieHint).
            if showWalkieHint && !router.isEditorKeyboardUp {
                WalkieHintCaption()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            VoicePivotButton()
                .opacity(router.isEditorKeyboardUp ? 0 : 1)
                .allowsHitTesting(!router.isEditorKeyboardUp)
                .animation(.easeOut(duration: 0.2), value: router.isEditorKeyboardUp)
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
            // Warm the Parakeet model at shell mount so the first
            // transcription request — whether from Compose dictation,
            // the voice memo save path, or the in-app keyboard — finds
            // a ready engine instead of falling back to Apple Speech
            // (which returns empty on the simulator). Fire-and-forget;
            // ParakeetModelManager has its own re-entry guards.
            ParakeetModelManager.shared.preheatForKeyboard()
            handleGlobalDeepLinkAction(deepLinkManager.pendingAction)
            consumeControlCenterRecordFlag()
        }
        .onChange(of: router.pendingNewMemoText) { _, text in
            handlePendingNewMemoText(text)
        }
        .onChange(of: chrome.state) { _, newState in
            handleWalkieHintState(newState)
        }
        .onChange(of: deepLinkManager.pendingAction) { _, action in
            handleGlobalDeepLinkAction(action)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Control Center launches the app fresh or foregrounds it —
            // the intent already wrote the flag, so re-check on activation.
            consumeControlCenterRecordFlag()
        }
        .onReceive(NotificationCenter.default.publisher(for: .companionShortcutSurfaceRequested)) { _ in
            openCompanionShortcutSurfaceIfAllowed()
        }
    }

    private func handlePendingNewMemoText(_ text: String?) {
        guard let text else { return }
        router.pendingNewMemoText = nil

        guard let memo = VoiceMemoStore.shared.createTextMemo(
            text: text,
            engine: "ask_ai"
        ), let memoID = memo.id?.uuidString else {
            return
        }

        router.openMemoDetail(memoID: memoID)
    }

    private func handleGlobalDeepLinkAction(_ action: DeepLinkAction) {
        switch action {
        case .importURL(let url, let title):
            SharedCaptureIngress.importURLContent(
                from: url,
                suggestedTitle: title,
                ingestionMethod: "deeplink",
                onCapture: saveAndOpenCapture
            )
            deepLinkManager.clearAction()
        case .processShare(let id):
            SharedCaptureIngress.processQueuedShare(id: id, onCapture: saveAndOpenCapture)
            deepLinkManager.clearAction()
        case .keyboardView:
            // talkie://keyboard → open a fresh Compose doc with the Talkie
            // keyboard already raised.
            router.openComposeWithKeyboard()
            deepLinkManager.clearAction()
        case .record:
            // talkie://record + Siri's StartRecordingIntent both funnel here.
            // Present the recording sheet via the shared controller - the
            // same path the Home command bar uses - so cold-launch and
            // while-running deep links land on the modal.
            recordingSheet.isPresented = true
            deepLinkManager.clearAction()
        default:
            break
        }
    }

    /// Drives the one-time "HOLD TO TALK" hint off chrome transitions.
    /// First time controls are summoned (→ .expanded) we surface it and
    /// arm a ~4s auto-dismiss. The moment the user actually holds to talk
    /// (→ .listening) we mark it seen and hide it — the affordance has been
    /// discovered, so it never returns.
    private func handleWalkieHintState(_ newState: ShellChrome.State) {
        switch newState {
        case .expanded:
            guard !hasSeenWalkieHint, !showWalkieHint else { return }
            // Persist immediately: the hint is a once-per-install nudge, so
            // it shouldn't reappear on the next summon even if the user
            // dismisses it by walking away rather than holding to talk.
            hasSeenWalkieHint = true
            withAnimation(.easeOut(duration: 0.24)) { showWalkieHint = true }
            // Auto-dismiss after a few seconds if the user doesn't act.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                guard showWalkieHint else { return }
                withAnimation(.easeIn(duration: 0.2)) { showWalkieHint = false }
            }
        case .listening:
            // First successful walkie use — retire the hint immediately.
            if showWalkieHint {
                withAnimation(.easeIn(duration: 0.2)) { showWalkieHint = false }
            }
        case .resting:
            if showWalkieHint {
                withAnimation(.easeIn(duration: 0.2)) { showWalkieHint = false }
            }
        }
    }

    /// Control Center's RecordVoiceMemoIntent can't reach `pendingAction`
    /// from the widget process, so it writes a `shouldStartRecording` flag
    /// into the shared App Group defaults and relies on the app opening.
    /// We read+clear it at launch (onAppear) and every foreground
    /// (didBecomeActive) so a Control Center tap opens the recording sheet
    /// whether the app was cold or already running.
    private func consumeControlCenterRecordFlag() {
        guard
            let defaults = UserDefaults(suiteName: TalkieMobileRuntimeIdentifiers.appGroupIdentifier),
            defaults.bool(forKey: "shouldStartRecording")
        else { return }

        defaults.set(false, forKey: "shouldStartRecording")
        recordingSheet.isPresented = true
    }

    private func openCompanionShortcutSurfaceIfAllowed() {
        switch router.surface {
        case .deck, .onboarding, .signIn:
            return
        default:
            router.openDeck()
        }
    }

    private func saveAndOpenCapture(_ capture: Capture) {
        CaptureStore.shared.add(capture)
        CaptureSyncService.shared.syncIfConnected()
        router.openCaptureDetail(captureID: capture.id.uuidString)
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

/// Faint radial lift painted into the Home canvas near the wordmark. The
/// single highest-leverage depth cue: it gives the flat backdrop a light
/// source, so the raised Quick chassis and recessed Recent screen read against
/// a canvas that already has a gradient rather than a dead uniform field.
/// plusLighter means it can only add light — invisible on paper themes.
private struct CanvasAmbientLight: View {
    var body: some View {
        GeometryReader { proxy in
            RadialGradient(
                colors: [Color.white.opacity(0.05), .clear],
                center: UnitPoint(x: 0.5, y: 0.16),
                startRadius: 0,
                endRadius: proxy.size.height * 0.5
            )
            .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }
}

/// One-time "HOLD TO TALK" nudge that rides just above the pivot button's
/// bottom-center slot. Accent smallcap in the chrome vocabulary, with a small
/// chevron pointing down at the button it describes. Non-interactive: it's a
/// caption, not a control; taps fall through to whatever is beneath.
private struct WalkieHintCaption: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 6) {
            Text("Hold to talk")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(theme.currentTheme.chrome.accent)
            Image(systemName: "chevron.compact.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.currentTheme.chrome.accent.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            ZStack {
                let radius = theme.currentTheme.chrome.chromeCorner + 6
                RoundedRectangle(cornerRadius: radius)
                    .fill(theme.colors.cardBackground.opacity(0.88))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(theme.currentTheme.chrome.accentStrong, lineWidth: theme.currentTheme.chrome.hairlineWidth)
            }
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
        .allowsHitTesting(false)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // Pivot button top is 12 (bottom pad) + 56 (button) = 68; float the
        // caption ~8pt above that so the chevron points down at it.
        .padding(.bottom, 76)
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
    /// AppShellNext consumes this, creates the VoiceMemo, and routes
    /// to the new detail surface.
    @Published var pendingNewMemoText: String?
    /// Request routed into the next Ask AI surface. Callers can choose
    /// whether the prompt is only staged for review or sent immediately,
    /// and whether it should begin a clean conversation.
    @Published var pendingAskAIRequest: AskAISeedRequest?
    /// Signals that the next Compose surface should auto-focus its
    /// editor on appear (popping the embedded Talkie keyboard).
    /// ComposeNextView consumes + clears this on appear.
    @Published var pendingComposeFocus: Bool = false
    /// Optional tab to select the next time Library opens. Lets Home
    /// counters route to the bucket they describe instead of a generic
    /// landing page.
    @Published var pendingLibraryTab: LibraryTab?
    /// True while Compose has the Talkie keyboard raised. The global
    /// bottom-center pivot hides itself when this is set so it doesn't
    /// collide with the keyboard's bottom row.
    @Published var isEditorKeyboardUp: Bool = false
    @Published var transitionDirection: TransitionDirection = .forward

    private init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--composeKeyboard") {
            pendingComposeFocus = true
            surface = .compose(documentID: "mock")
        } else if args.contains("--composeState") {
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

    func openLibrary(tab: LibraryTab? = nil) {
        pendingLibraryTab = tab
        push(.library)
    }
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

    var isComposeSurface: Bool {
        if case .compose = surface { return true }
        return false
    }

    /// Open a new Compose document seeded with `text`. Caller doesn't
    /// pick the document ID — this generates one and stashes the seed
    /// on the router for ComposeStore to consume.
    func openComposeSeeded(text: String) {
        pendingComposeSeed = text
        openCompose(documentID: UUID().uuidString)
    }

    /// Open a fresh Compose document with the embedded Talkie keyboard
    /// already up. Used by the bottom-right keyboard complication so
    /// "I want to type" lands directly in a typing-ready editor instead
    /// of the keyboard-extension status surface.
    func openComposeWithKeyboard() {
        pendingComposeFocus = true
        openCompose(documentID: UUID().uuidString)
    }

    /// "Save as memo" pipeline entry. Codex wires the actual memo
    /// creation (VoiceMemoStore + route to the new memo). Paint side
    /// just signals intent — the chip stays visible whether or not
    /// the wiring is live yet.
    func saveAsMemo(text: String) {
        pendingNewMemoText = text
    }

    /// Open Ask AI with a routed prompt. Home and release-to-send voice
    /// commands can dispatch immediately; editing surfaces can still stage
    /// text for review by using the default arguments.
    func openAskAISeeded(
        prompt: String,
        autoSend: Bool = false,
        startsNewSession: Bool = false
    ) {
        pendingAskAIRequest = AskAISeedRequest(
            prompt: prompt,
            autoSend: autoSend,
            startsNewSession: startsNewSession
        )
        openAskAI()
    }

    /// Routes a voice-command transcript to the right place. Surfaces
    /// that override `chrome.voiceCommandHandler` on appear (AskAI,
    /// MemoDetail, CaptureDetail) intercept before reaching this
    /// method. For Compose we route into the active store; for
    /// everything else we fall through to a seeded Ask AI session so
    /// the walkie-talkie always lands somewhere instead of dropping.
    func submitVoiceCommand(_ transcript: String) {
        if case .compose = surface {
            activeComposeStore?.voiceCommandReceived(transcript)
            return
        }
        openAskAISeeded(
            prompt: transcript,
            autoSend: true,
            startsNewSession: true
        )
    }
}

struct AskAISeedRequest: Equatable {
    let prompt: String
    let autoSend: Bool
    let startsNewSession: Bool
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
        case resting        // content full-bleed; only Talkie pivot visible
        case expanded       // chrome (corners + tray) faded in
        case listening      // pivot pulsing; listening bubble above
    }

    @Published private(set) var state: State = .resting

    /// True from release-to-send until the walkie command lands (dispatched)
    /// or errors. Bridges the gap where the ListeningBubble is already gone
    /// but the transcription round-trip hasn't produced anything yet — the
    /// shell paints a compact "SENDING…" indicator while this is set so the
    /// user isn't staring at silence.
    @Published private(set) var isProcessingCommand: Bool = false

    /// Which screen corners chrome currently owns. Screen-native UI
    /// in these zones should yield (fade out) so the complication
    /// can render without collision. Derived from `state`; reading
    /// it picks up changes through the @Published state observation.
    var occupiedZones: Set<ScreenZone> {
        switch state {
        case .resting: return []
        case .expanded, .listening:
            // Settings owns .topTrailing. The create tray owns both bottom
            // corners on every non-Compose surface: Capture on the left,
            // Keyboard on the right.
            // .topLeading is claimed by the Home pill on every sub-
            // surface (so screen back chevrons yield to make room);
            // on home itself chrome shows no top-left pill, so the
            // slot stays free for whatever the home view wants there.
            var zones: Set<ScreenZone> = [.topTrailing]
            if !AppShellRouter.shared.isComposeSurface {
                zones.formUnion([.bottomLeading, .bottomTrailing])
            }
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

    /// Single-tap on the center pivot. From rest it unfolds chrome; once
    /// expanded, the button itself becomes the record mic and the view handles
    /// that tap directly.
    func tapPivotButton() {
        switch state {
        case .resting:
            withAnimation(.easeOut(duration: 0.28)) { state = .expanded }
        case .expanded, .listening:
            break
        }
    }

    /// Long-press began on the center pivot. Only valid while
    /// expanded - long-pressing from resting would skip the visual
    /// summon step and feel sudden.
    func longPressBegan() {
        guard state == .expanded else { return }
        // A fresh listen supersedes any still-in-flight prior command, so
        // the bubble slot only ever holds one thing at a time.
        if isProcessingCommand {
            withAnimation(.easeIn(duration: 0.12)) { isProcessingCommand = false }
        }
        withAnimation(.easeOut(duration: 0.18)) { state = .listening }

        guard !screenshotMode else { return }
        commandTask?.cancel()
        commandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.commandRecorder.startRecording()
        }
    }

    /// Long-press ended - release-to-send. If Compose is current, the
    /// captured command transcript is sent into ComposeStore.
    func longPressEnded() {
        guard state == .listening else { return }
        withAnimation(.easeIn(duration: 0.18)) { state = .expanded }

        if screenshotMode {
            voiceCommandHandler?("tighten the second paragraph")
            return
        }

        // The bubble is gone the instant we leave .listening; show the
        // transient "SENDING…" indicator until the round-trip resolves.
        withAnimation(.easeOut(duration: 0.18)) { isProcessingCommand = true }

        commandTask?.cancel()
        commandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.commandRecorder.stopRecording()
            let recordingURL = self.commandRecorder.currentRecordingURL
            self.commandRecorder.finalizeRecording()

            guard
                let recordingURL,
                let captured = try? await TranscriptionService.shared.transcribe(
                    audioURL: recordingURL,
                    useCase: .keyboard
                ),
                !captured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                // Real-device transcription failed or returned empty —
                // don't synthesize a fake command. Screenshot mode is
                // handled by the early-return above. Never fail silently:
                // the user spoke and released, so tell them it didn't land.
                withAnimation(.easeIn(duration: 0.18)) { self.isProcessingCommand = false }
                FeedbackToastCenter.shared.showError("Didn't catch that — no words came through. Try again.")
                return
            }

            withAnimation(.easeIn(duration: 0.18)) { self.isProcessingCommand = false }
            self.voiceCommandHandler?(captured)
        }
    }

    /// Explicit dismiss (e.g. tapping Done in the chrome overlay).
    func dismissChrome() {
        withAnimation(.easeIn(duration: 0.20)) { state = .resting }
    }
}
