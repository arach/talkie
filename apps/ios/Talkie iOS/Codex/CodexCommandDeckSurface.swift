//
//  CodexCommandDeckSurface.swift
//  Talkie iOS
//
//  THESIS: This is an exact-task instrument, not a generic remote-control grid.
//  OWN WORLD: Surfaces, keycaps, ink, and accents derive from the active
//  AppTheme chrome tokens so Mineral, Linear, Ghost, Lift, Graphite, Carbon,
//  and Scope each keep their own identity. Failures stay a single cold red.
//  STORY: Pick one known task in the console lid, speak, see where the turn went,
//  then read or hear the answer without returning to the Mac.
//  FIRST VIEWPORT: Live console, mounted lane spine, then a stable command
//  keybed. The console owns task activity; the keybed owns talk.
//  FORM: Extends Talkie's established instrument language and existing
//  bridge behavior. A lane is a direct destination, not a separate claim.
//  Carbon gets a deliberately minimal keybed: index + symbol, labels via a11y.
//

import SwiftUI
import UIKit

struct CodexCommandDeckSurface: View {
    let onShowSpaces: () -> Void

    @ObservedObject private var store = CodexLaneStore.shared
    @ObservedObject private var theme = ThemeManager.shared
    @State private var appSettings = TalkieAppSettings.shared
    @State private var voicePlayback = WalkieFX.shared
    @State private var showingMapper = false
    @State private var showingNewTask = false
    @State private var showingHistory = false
    @State private var showingReadoutHistory = false
    @State private var showingPlaybackTranscript = false
    @State private var playbackTranscriptTitle: String?
    @State private var playbackTranscriptText = ""
    @State private var selectedResponseTurn: CodexTurnRecord?
    @State private var showingTaskDetails = false
    @State private var copiedResponse = false
    @State private var isCaptureGestureActive = false
    @State private var captureDragTranslation: CGSize = .zero
    @State private var isCaptureCancelArmed = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            CodexCommandConsole(
                isCaptureActive: isCaptureGestureActive || store.phase == .listening,
                isCaptureCancelArmed: isCaptureCancelArmed,
                onShowMapper: openMapper,
                onCreateNewTask: openNewTask
            )
                // Grows into whatever the keybed leaves behind — see
                // `consoleMinHeight`. Held at a hard 316 this left a band of
                // dead page under the last key row on anything taller than an
                // SE, because nothing else in the stack was flexible either.
                .frame(minHeight: consoleMinHeight, maxHeight: .infinity)
                .animation(
                    .spring(response: 0.32, dampingFraction: 0.74),
                    value: store.selectedTask?.id
                )
                .animation(
                    .spring(response: 0.32, dampingFraction: 0.74),
                    value: store.newTaskProject?.id
                )

            keybed
                .layoutPriority(60)
        }
        .padding(.top, 0)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            if voicePlayback.isVoicePlaybackActive {
                voicePlaybackRail
                    .padding(.bottom, 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: voicePlayback.isVoicePlaybackActive)
        .sheet(isPresented: $showingMapper) {
            CodexLaneMapperView()
        }
        .sheet(isPresented: $showingNewTask, onDismiss: {
            showingNewTask = false
        }) {
            CodexNewTaskView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingHistory) {
            if let task = store.selectedTask {
                CodexChannelHistorySheet(task: task)
            }
        }
        .sheet(isPresented: $showingReadoutHistory) {
            CodexReadoutHistorySheet()
        }
        .sheet(isPresented: $showingPlaybackTranscript) {
            VoicePlaybackTranscriptSheet(
                title: playbackTranscriptTitle,
                transcript: playbackTranscriptText
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedResponseTurn) { turn in
            CodexResponseSheet(turn: turn)
        }
        .sheet(isPresented: $showingTaskDetails) {
            CodexTaskDetailsSheet()
        }
        .onDisappear(perform: cancelActiveCapture)
    }

    private var voicePlaybackRail: some View {
        HStack(spacing: 6) {
            Button(action: voicePlayback.toggleVoicePlayback) {
                Image(systemName: voicePlayback.voicePlaybackState == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.chrome.accent)
            .accessibilityLabel(voicePlayback.voicePlaybackState == .paused ? "Resume narration" : "Pause narration")

            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    Text("VOICE")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(utilityInkFaint)

                    Spacer(minLength: 0)

                    Text(playbackTimeReadout)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(utilityInkFaint)
                }

                VoicePlaybackWaveform(
                    samples: voicePlayback.voiceWaveform,
                    progress: voicePlayback.voicePlaybackProgress,
                    isPlaying: voicePlayback.voicePlaybackState == .playing,
                    accent: theme.chrome.accent,
                    inactive: utilityInkFaint.opacity(0.22),
                    onSeek: voicePlayback.seekVoicePlayback,
                    onSkip: skipVoicePlayback
                )
            }

            Button(action: showPlaybackTranscript) {
                VStack(spacing: 2) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 11, weight: .semibold))
                    Text("TEXT")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                }
                .frame(width: 44, height: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.chrome.accent)
            .disabled(voicePlayback.voicePlaybackTranscript.isEmpty)
            .accessibilityLabel("Show playback transcript")
            .accessibilityHint("Shows the full text currently being narrated")

            Button(action: store.interruptNarration) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .foregroundStyle(utilityInkFaint)
            .accessibilityLabel("Dismiss narration")
        }
        .padding(.horizontal, 4)
        .frame(height: 54)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(theme.chrome.panel.opacity(colorScheme == .dark ? 0.96 : 0.98))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(utilityInkFaint.opacity(0.16), lineWidth: theme.chrome.hairlineWidth)
                }
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.12), radius: 8, y: 3)
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
    }

    private var playbackTimeReadout: String {
        "\(formatPlaybackTime(voicePlayback.voicePlaybackCurrentTime))  ·  −\(formatPlaybackTime(max(0, voicePlayback.voicePlaybackDuration - voicePlayback.voicePlaybackCurrentTime)))"
    }

    private func formatPlaybackTime(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
    }

    private func skipVoicePlayback(by interval: TimeInterval) {
        voicePlayback.skipVoicePlayback(by: interval)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func showPlaybackTranscript() {
        let transcript = voicePlayback.voicePlaybackTranscript
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        playbackTranscriptTitle = voicePlayback.voicePlaybackTitle
        playbackTranscriptText = transcript
        showingPlaybackTranscript = true
    }

    private var keybed: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: isIconMinimalDeck ? 6 : 8) {
            GridRow {
                audioKey(index: 1)
                actionKey(index: 2, label: "Mapper", icon: "rectangle.3.group", action: openMapper)
                actionKey(index: 3, label: "Spaces", icon: "square.grid.2x2", action: onShowSpaces)
                statusReadoutKey(index: 4)
            }
            .frame(height: keybedRowHeight)

            GridRow {
                actionKey(
                    index: 5,
                    label: "History",
                    icon: "clock.arrow.circlepath",
                    isEnabled: store.selectedTask != nil,
                    action: { showingHistory = true }
                )
                actionKey(
                    index: 6,
                    label: "Read",
                    icon: "doc.text",
                    isEnabled: activeLaneTurn != nil,
                    action: { selectedResponseTurn = activeLaneTurn }
                )
                actionKey(
                    index: 7,
                    label: copiedResponse ? "Copied" : "Copy",
                    icon: copiedResponse ? "checkmark" : "doc.on.doc",
                    isEnabled: activeLaneTurn != nil,
                    action: copyActiveLaneResponse
                )
                actionKey(
                    index: 8,
                    label: "Refresh",
                    icon: "arrow.clockwise",
                    isEnabled: !store.isLoadingCatalog,
                    action: { Task { await store.refreshCatalog() } }
                )
            }
            .frame(height: keybedRowHeight)

            GridRow {
                laneStepKey(index: 9, direction: -1)
                actionKey(
                    index: 10,
                    label: "Replay",
                    icon: "speaker.wave.2",
                    isEnabled: activeLaneTurn != nil && store.phase != .preparingSpeech,
                    action: replayActiveLaneResponse
                )
                actionKey(
                    index: 11,
                    label: "Stop",
                    icon: "stop.fill",
                    isEnabled: store.phase == .speaking,
                    action: store.interruptNarration
                )
                laneStepKey(index: 12, direction: 1)
            }
            .frame(height: keybedRowHeight)

            GridRow {
                actionKey(
                    index: 13,
                    label: "Task",
                    icon: "square.badge.plus",
                    isEnabled: store.canCreateChannel && !store.isCreatingTask,
                    action: openNewTask
                )
                captureKey
                    .gridCellColumns(2)
                actionKey(
                    index: 16,
                    label: "Readout",
                    icon: "waveform",
                    action: { showingReadoutHistory = true }
                )
            }
            .frame(height: keybedRowHeight)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .dynamicTypeSize(.xSmall ... .xxxLarge)
        .sensoryFeedback(.success, trigger: copiedResponse)
    }

    /// Carbon: terminal monochrome — keys communicate via index + SF Symbol.
    private var isIconMinimalDeck: Bool {
        theme.currentTheme == .carbon
    }

    private var keyCornerRadius: CGFloat {
        switch theme.currentTheme {
        case .carbon: return 4
        case .tactical: return 3
        case .graphite, .midnight, .ember: return 10
        default: return 14
        }
    }

    private var keybedRowHeight: CGFloat { 65 }

    // MARK: - Shared key metrics
    //
    // One keypad, one metric. Every key on this bed is the same object — a
    // keycap with a glyph and an engraved legend — so the legend is a constant,
    // not a channel. State belongs to ink and fill; size never carries meaning
    // here, because a grid whose type sizes wander reads as unstable and makes
    // the eye hunt for a rule that doesn't exist.
    //
    // It didn't before. Four builders each picked their own caption size (9 /
    // 8 / 7.5 / 7.5) and tracking (1.1 / 0.8 / 0.7 / 0.7), and `actionKey`'s
    // 0.65 scale floor was actually engaging — so the keys declaring the
    // *largest* type rendered the *smallest*. MAPPER shipped at roughly 6.3pt
    // against OUTPUT's 7.5. The hierarchy was inverted at render time, which is
    // why the sizing read as arbitrary: it was.

    /// Height of the engraved legend's line box.
    ///
    /// Fixed, so the caption is a rail every key shares rather than the last
    /// item in each key's own stack. Stacked, a 36pt instrument pushed its
    /// caption ~6pt below the caption of a key holding a 25pt icon, and the
    /// legends across one row never sat on a common baseline.
    private var keyCaptionHeight: CGFloat { 11 }

    /// Space above the legend that a key's glyph or instrument gets to occupy.
    /// `keybedRowHeight` less the row's own 2pt inset, the legend rail, and the
    /// padding on either side of it.
    private var keyContentBandHeight: CGFloat { 37 }

    private var keyTopPadding: CGFloat { 6 }
    private var keyBottomPadding: CGFloat { 7 }

    /// The engraved legend. Every caption on the keybed goes through here.
    private func keyCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
            .tracking(1.0)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(height: keyCaptionHeight)
    }

    /// The console's floor, not its ceiling.
    ///
    /// The keybed's four rows are a fixed `keybedRowHeight` each — a keypad
    /// whose keys stretch with the screen stops reading as a keypad. That
    /// makes the console the only part of the surface that can absorb a tall
    /// phone's extra height, so it takes everything the keybed doesn't and the
    /// keys settle at the bottom, in thumb reach.
    private var consoleMinHeight: CGFloat { 316 }

    private var deckFailureColor: Color {
        Color(red: 0.92, green: 0.42, blue: 0.30)
    }

    private func actionKey(
        index: Int,
        label: String,
        icon: String,
        isEnabled: Bool = true,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        ZStack {
            keycapSurface(active: isActive, isEmpty: false)
                .allowsHitTesting(false)

            Button(action: action) {
                Group {
                    if isIconMinimalDeck {
                        ZStack {
                            Image(systemName: icon)
                                .font(.system(size: 15, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                    } else {
                        VStack(spacing: 0) {
                            // No ring around the glyph. A circle filled at 0.055
                            // and stroked at 0.14 / 0.6pt isn't a container, it's
                            // a smudge — and it nested a second rounded shape
                            // inside a keycap that is already a rounded shape,
                            // sixteen times over. The keycap is the container;
                            // the symbol just gets big enough to carry the key.
                            Image(systemName: icon)
                                .font(.system(size: 15, weight: .medium))
                                .frame(height: keyContentBandHeight)

                            keyCaption(label.uppercased())
                        }
                        .padding(.horizontal, 5)
                        .padding(.top, keyTopPadding)
                        .padding(.bottom, keyBottomPadding)
                    }
                }
                .foregroundStyle(
                    isEnabled
                        ? utilityInk
                        : disabledControlInk
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: keyCornerRadius, style: .continuous))
                .overlay(alignment: .topLeading) { keyIndexLabel(index: index) }
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityLabel(label)
            .accessibilityAddTraits(isActive ? .isSelected : [])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 44, minHeight: 44)
    }

    private var captureKey: some View {
        ZStack {
            talkKeySurface
                .allowsHitTesting(false)

            Button(action: {}) {
                Group {
                    if isIconMinimalDeck {
                        VStack(spacing: 3) {
                            Spacer(minLength: 0)
                            Image(systemName: captureIcon)
                                .font(.system(size: 16, weight: .semibold))
                            Text(captureTitle)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .tracking(0.8)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                    } else {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)

                            // TALK is the one key allowed to break the metric:
                            // it is the only one that spans two columns and the
                            // only one that is a verb. So it stays a horizontal
                            // lockup one step up in size — a deliberate
                            // exception, not more drift. Its glyph matches the
                            // 15pt every other key now uses, and its scale floor
                            // comes up to the shared 0.85 so it can't quietly
                            // shrink to 7.2pt on "PROCESSING".
                            HStack(spacing: 7) {
                                Image(systemName: captureIcon)
                                    .font(.system(size: 15, weight: .semibold))
                                Text(captureTitle)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .tracking(1.2)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                    }
                }
                .foregroundStyle(
                    store.hasDispatchDestination
                        ? captureAccent
                        : disabledControlInk
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(x: captureContentOffset)
                .contentShape(RoundedRectangle(cornerRadius: keyCornerRadius, style: .continuous))
                .overlay(alignment: .topLeading) { keyIndexLabel(index: 14) }
                .overlay(alignment: .topTrailing) { trailingKeyIndexLabel(index: 15) }
            }
            .buttonStyle(.plain)
            .highPriorityGesture(captureGesture)
            .disabled(!canCapture)
            .accessibilityLabel(captureAccessibilityLabel)
            .accessibilityHint(captureAccessibilityHint)
            .accessibilityAction { store.handleCaptureControl() }
        }
        .scaleEffect(isCaptureGestureActive ? 0.985 : 1)
        .animation(.easeOut(duration: 0.10), value: isCaptureGestureActive)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 44, minHeight: 44)
    }

    private var canCapture: Bool {
        store.hasDispatchDestination
            && (!store.phase.isBusy
                || store.phase.isCapturing
                || store.phase == .speaking
                || store.isTurnInFlight)
    }

    private var captureTitle: String {
        if isCaptureCancelArmed { return "CANCEL" }
        switch store.phase {
        case .listening: return "RELEASE"
        case .speaking: return "TALK"
        case .preparingSpeech: return "INBOUND"
        case .submitting where store.selectedDestinationIsInFlight:
            return selectedCaptureModeTitle
        case .transcribing: return "PROCESSING"
        case .submitting: return "SENDING"
        case .idle, .failed:
            return store.selectedDestinationIsInFlight ? selectedCaptureModeTitle : "TALK"
        }
    }

    private var selectedCaptureModeTitle: String {
        store.selectedMessageMode == .queue ? "Q" : "STEER"
    }

    private var captureAccessibilityLabel: String {
        if isCaptureCancelArmed { return "Release to discard dictation" }
        switch store.phase {
        case .listening:
            return store.selectedDestinationIsInFlight
                ? "Release to \(store.selectedMessageMode.label)"
                : "Release to send"
        case .speaking: return "Interrupt narration and talk"
        case .preparingSpeech: return "Voice response inbound"
        case .submitting where store.selectedDestinationIsInFlight:
            return "Hold to \(store.selectedMessageMode.label)"
        case .transcribing: return "Processing speech"
        case .submitting: return "Sending to Codex"
        case .idle, .failed: return "Hold to talk"
        }
    }

    private var captureIcon: String {
        if isCaptureCancelArmed { return "xmark" }
        switch store.phase {
        case .listening: return "arrow.up"
        case .speaking: return "waveform"
        case .submitting where store.selectedDestinationIsInFlight: return "mic"
        case .transcribing, .submitting, .preparingSpeech: return "ellipsis"
        case .idle, .failed: return "mic"
        }
    }

    private var captureAccessibilityHint: String {
        if store.phase == .listening {
            return "Release to send, or slide left to cancel"
        }
        guard store.selectedDestinationIsInFlight else {
            return "Sends speech to the selected Codex task"
        }
        switch store.selectedMessageMode {
        case .queue:
            return "Queues the message to run after the current Codex turn"
        case .steer:
            return "Steers the current Codex turn immediately"
        case .auto:
            return "Sends speech to the active Codex task"
        }
    }

    private var captureAccent: Color {
        isCaptureCancelArmed ? deckFailureColor : theme.chrome.accent
    }

    private var captureContentOffset: CGFloat {
        guard isCaptureGestureActive else { return 0 }
        return min(0, max(-12, captureDragTranslation.width * 0.12))
    }

    private var captureGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard canCapture else { return }

                if !isCaptureGestureActive {
                    isCaptureGestureActive = true
                    Haptics.confirm.fire()
                    Haptics.prepare(.transition)
                    store.beginPushToTalk()
                }

                captureDragTranslation = value.translation
                let horizontalDistance = abs(value.translation.width)
                let shouldArmCancel = value.translation.width <= -68
                    && horizontalDistance >= abs(value.translation.height) * 0.75

                guard shouldArmCancel != isCaptureCancelArmed else { return }
                isCaptureCancelArmed = shouldArmCancel
                if shouldArmCancel {
                    Haptics.stop.fire()
                } else {
                    Haptics.toggle.fire()
                }
            }
            .onEnded { _ in
                guard isCaptureGestureActive else { return }
                let shouldCancel = isCaptureCancelArmed
                resetCaptureGesture()
                if shouldCancel {
                    store.cancelCapture()
                } else {
                    Haptics.transition.fire()
                    store.endPushToTalk()
                }
            }
    }

    private func cancelActiveCapture() {
        guard isCaptureGestureActive else { return }
        resetCaptureGesture()
        store.cancelCapture()
    }

    private func resetCaptureGesture() {
        isCaptureGestureActive = false
        captureDragTranslation = .zero
        isCaptureCancelArmed = false
    }

    private func audioKey(index: Int) -> some View {
        Button(action: cycleOutputRoute) {
            VStack(spacing: 0) {
                outputRouteSelectorPlate
                    .frame(height: keyContentBandHeight)

                keyCaption("OUTPUT")
                    .foregroundStyle(utilityInk)
            }
                .padding(.top, keyTopPadding)
                .padding(.bottom, keyBottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: keyCornerRadius, style: .continuous))
                .background(keycapSurface(active: false, isEmpty: false))
                .overlay(alignment: .topLeading) { keyIndexLabel(index: index) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Response output, \(outputRoute.displayName)")
        .accessibilityHint("Cycles through silent, Watch, and iPhone output")
        .sensoryFeedback(.selection, trigger: outputRoute.rawValue)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 44, minHeight: 44)
    }

    private func statusReadoutKey(index: Int) -> some View {
        Button(action: { showingTaskDetails = true }) {
            VStack(spacing: 0) {
                statusInstrument
                    .frame(height: keyContentBandHeight)

                keyCaption("DETAILS ›")
                    .foregroundStyle(utilityInk)
            }
                .padding(.top, keyTopPadding)
                .padding(.bottom, keyBottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: keyCornerRadius, style: .continuous))
                .background(keycapSurface(active: false, isEmpty: false))
                .overlay(alignment: .topLeading) { keyIndexLabel(index: index) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Task details, current status \(deckStatusLabel)")
        .accessibilityHint("Opens the selected task summary, activity, history, and changed files")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 44, minHeight: 44)
    }

    /// One line: the route that is actually selected.
    ///
    /// This was a permanently-displayed three-position menu — SILENT / WATCH /
    /// IPHONE stacked — which is a settings panel wearing a keycap costume. It
    /// needed 36pt of height in a 65pt row, so it sat on top of the key's own
    /// index numeral and pushed its legend below every other legend in the row.
    /// The key's job is to answer "where does audio go," and the answer is one
    /// word; the other two routes only matter in the instant you tap, and the
    /// tap reveals them by changing this. Cycling stays discoverable through the
    /// accessibility hint and the fact that the plate visibly changes.
    private var outputRouteSelectorPlate: some View {
        let isSilent = outputRoute == .silent
        return HStack(spacing: 4) {
            Circle()
                .fill(isSilent ? .clear : theme.chrome.panelAccent)
                .overlay {
                    Circle()
                        .strokeBorder(
                            isSilent ? theme.chrome.panelInkFaint : theme.chrome.panelAccent,
                            lineWidth: 0.7
                        )
                }
                .frame(width: 4, height: 4)
                .shadow(
                    color: isSilent ? .clear : theme.chrome.accentGlow.opacity(0.40),
                    radius: 1.5
                )

            Text(outputRoute.displayName.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(isSilent ? theme.chrome.panelInkFaint : theme.chrome.panelAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 6)
        .frame(width: 54, height: 24)
        .background(deckLEDPlateSurface(signalColor: theme.chrome.panelAccent, isSignaled: !isSilent))
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.15),
            value: outputRoute.rawValue
        )
        .accessibilityHidden(true)
    }

    /// Lamp, then state — the same reading order as `outputRouteSelectorPlate`,
    /// because these two are a matched pair sitting in the same row.
    ///
    /// The second line is gone. It printed `deckStatusLabel` at 6.5pt with a
    /// 0.65 scale floor — roughly 4pt, below the size at which type is type —
    /// directly under `statusInstrumentLabel`, which is nothing but an
    /// abbreviation *of that same string*. It was the same word twice, one copy
    /// unreadable. Present-but-illegible type is a large part of why this deck
    /// felt off: the eye registers something it can never resolve.
    private var statusInstrument: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusInstrumentSignalColor)
                .frame(width: 4, height: 4)
                .shadow(
                    color: statusInstrumentSignalColor.opacity(deckMeterIsActive ? 0.38 : 0.12),
                    radius: deckMeterIsActive ? 2 : 1
                )

            Text(statusInstrumentLabel)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(statusInstrumentSignalColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 6)
        .frame(width: 54, height: 24)
        .background(
            deckLEDPlateSurface(
                signalColor: statusInstrumentSignalColor,
                isSignaled: deckMeterIsActive || deckMeterIsFailure
            )
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: deckStatusLabel
        )
        .accessibilityHidden(true)
    }

    private var statusInstrumentLabel: String {
        switch deckStatusLabel {
        case "READY": return "RDY"
        // Was "—", which only worked because "NO TASK" was spelled out on the
        // second line. That line is gone, so this has to say something.
        case "NO TASK": return "NONE"
        case "QUEUED": return "QUE"
        case "RECEIVED", "RESPONSE", "VOICE INBOUND", "SPEAKING": return "RX"
        case "ERROR": return "ERR"
        default: return "RUN"
        }
    }

    /// Three ink tiers, no alpha.
    ///
    /// These plates are dark in every theme, so fading ink with `.opacity()`
    /// walks it *toward* the plate and destroys the contrast — "quieter" was
    /// being spelled in the one way that also means "unreadable." NONE and RDY
    /// were landing at 1.6:1 and 1.9:1 against their own plate.
    ///
    /// So quiet is carried by *which* ink, not by how faded it is, and all
    /// three tiers are panel-space tokens tuned for this surface rather than
    /// page-space `accent`/`textTertiary`:
    ///
    ///   nothing loaded → `panelInkFaint`  (dim, still legible)
    ///   standing by    → `panelInk`       (neutral: on, not working)
    ///   working        → `panelAccent`    (colored: something is happening)
    ///
    /// Colour now means activity, which is what the lamp beside it already
    /// meant — the two finally agree.
    private var statusInstrumentSignalColor: Color {
        if deckMeterIsFailure {
            return deckFailureColor
        }
        if deckStatusLabel == "NO TASK" {
            return theme.chrome.panelInkFaint
        }
        if deckStatusLabel == "READY" {
            return theme.chrome.panelInk
        }
        return theme.chrome.panelAccent
    }

    private func deckLEDPlateSurface(signalColor: Color, isSignaled: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return shape
            .fill(
                LinearGradient(
                    colors: [theme.chrome.panelAlt, theme.chrome.panel],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                if !isIconMinimalDeck {
                    shape
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(colorScheme == .dark ? 0.035 : 0.16), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .overlay {
                shape.strokeBorder(
                    theme.chrome.panelEdge.opacity(isSignaled ? 0.62 : 0.44),
                    lineWidth: 0.55
                )
            }
            .compositingGroup()
            .shadow(
                color: isIconMinimalDeck ? .clear : Color.black.opacity(colorScheme == .dark ? 0.28 : 0.10),
                radius: 2,
                y: 1
            )
            .shadow(
                color: isSignaled ? signalColor.opacity(0.06) : .clear,
                radius: 2,
                y: 1
            )
    }

    private func laneStepKey(index: Int, direction: Int) -> some View {
        let number = adjacentLaneNumber(direction: direction)
        let lane = number.flatMap(store.lane)
        let isEnabled = number != nil && !store.phase.isCapturing

        return ZStack {
            keycapSurface(active: false, isEmpty: false)
                .allowsHitTesting(false)

            Button {
                guard let number else { return }
                guard lane != nil else {
                    openMapper()
                    return
                }
                Task { await store.activate(number) }
            } label: {
                Group {
                    if isIconMinimalDeck {
                        Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 6)
                    } else {
                        VStack(spacing: 0) {
                            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(height: keyContentBandHeight)

                            keyCaption(number.map { "LANE \($0 < 10 ? "0\($0)" : "\($0)")" } ?? "LANE")
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, keyTopPadding)
                        .padding(.bottom, keyBottomPadding)
                    }
                }
                .foregroundStyle(isEnabled ? utilityInk : disabledControlInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: keyCornerRadius, style: .continuous))
                .overlay(alignment: .topLeading) { keyIndexLabel(index: index) }
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityLabel(direction < 0 ? "Previous lane" : "Next lane")
            .accessibilityHint(lane == nil ? "Opens the mapper for this empty lane" : "Selects lane \(number ?? 0)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 44, minHeight: 44)
    }

    private func openSocket(index: Int) -> some View {
        keycapSurface(active: false, isEmpty: true)
        .overlay(alignment: .topLeading) { keyIndexLabel(index: index) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Empty deck slot \(index)")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var talkKeySurface: some View {
        let shape = RoundedRectangle(cornerRadius: keyCornerRadius, style: .continuous)
        return shape
            .fill(captureAccent.opacity(store.phase.isCapturing ? 0.30 : 0.17))
            .overlay {
                if !isIconMinimalDeck {
                    shape.fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.10), .clear, Color.black.opacity(0.10)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .overlay {
                shape.strokeBorder(
                    captureAccent.opacity(store.phase.isCapturing ? 0.92 : 0.55),
                    lineWidth: store.phase.isCapturing ? 1.5 : theme.chrome.hairlineWidth + 0.5
                )
            }
            .shadow(
                color: Color.black.opacity(isIconMinimalDeck ? 0.16 : 0.28),
                radius: isIconMinimalDeck ? 3 : 7,
                y: isIconMinimalDeck ? 2 : 4
            )
    }

    private func keycapSurface(active: Bool, isEmpty: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: keyCornerRadius, style: .continuous)
        let raisedShadow = colorScheme == .dark ? Color.black.opacity(0.30) : Color.black.opacity(0.11)
        return shape
            .fill(
                active
                    ? theme.chrome.accent.opacity(0.18)
                    : (isEmpty ? emptyKeyFace : utilityFace)
            )
            .overlay {
                if !isEmpty && !isIconMinimalDeck {
                    shape.fill(
                        LinearGradient(
                            colors: [Color.white.opacity(colorScheme == .dark ? 0.07 : 0.26), .clear, Color.black.opacity(0.035)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .overlay {
                if active {
                    shape.strokeBorder(theme.chrome.accent.opacity(0.72), lineWidth: 1)
                } else {
                    // 0.10 was a rumour of an edge. With the page now carrying
                    // tone, the cap has a real value step to sit on and the
                    // border's job is to terminate it, not to invent it.
                    shape.strokeBorder(
                        isEmpty ? theme.chrome.edgeFaint : utilityInkFaint.opacity(isIconMinimalDeck ? 0.16 : 0.15),
                        lineWidth: theme.chrome.hairlineWidth
                    )
                }
            }
            .compositingGroup()
            .shadow(
                color: isEmpty || isIconMinimalDeck ? .clear : raisedShadow,
                radius: isEmpty ? 0 : 5,
                y: isEmpty ? 0 : 3
            )
            .shadow(
                color: isEmpty || isIconMinimalDeck ? .clear : Color.black.opacity(0.10),
                radius: isEmpty ? 0 : 1,
                y: isEmpty ? 0 : 1
            )
    }

    /// Tucked tighter into the corner than it was, so the instrument plates on
    /// keys 01 and 04 clear it instead of sitting on top of it.
    ///
    /// Full-strength `utilityInkFaint`, not a fade of it. At 8.5pt this is
    /// already the smallest type on the deck; the extra 0.56 alpha put it below
    /// 4.5:1 in every theme, in both modes. These numerals are how you name a
    /// key — they have to survive being read.
    private func keyIndexLabel(index: Int) -> some View {
        Text(index < 10 ? "0\(index)" : "\(index)")
            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
            .foregroundStyle(utilityInkFaint)
            .padding(.top, 5)
            .padding(.leading, 6)
            .allowsHitTesting(false)
    }

    private func trailingKeyIndexLabel(index: Int) -> some View {
        Text("\(index)")
            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
            .foregroundStyle(utilityInkFaint.opacity(0.56))
            .padding(.top, 5)
            .padding(.trailing, 6)
            .allowsHitTesting(false)
    }

    private var outputRoute: AIResponseSpeechRoute {
        AIResponseSpeechRoute(rawValue: appSettings.aiVoiceOutputRoute) ?? .phone
    }

    private var activeLaneTurn: CodexTurnRecord? {
        guard let taskID = store.selectedTask?.id else { return nil }
        return store.latestTurn(forTaskID: taskID)
    }

    private var utilityFace: Color {
        // Raised key face from the active theme card, not a fixed cream brown.
        theme.colors.cardBackground
    }

    private var emptyKeyFace: Color {
        theme.colors.textPrimary.opacity(0.04)
    }

    private var utilityInk: Color {
        theme.colors.textPrimary
    }

    private var utilityInkFaint: Color {
        theme.colors.textTertiary
    }

    private var disabledControlInk: Color {
        utilityInk.opacity(0.68)
    }

    private func cycleOutputRoute() {
        let next: AIResponseSpeechRoute
        switch outputRoute {
        case .silent: next = .watch
        case .watch: next = .phone
        case .phone: next = .silent
        }
        appSettings.aiVoiceOutputRoute = next.rawValue
    }

    private func copyActiveLaneResponse() {
        guard let response = activeLaneTurn?.response, !response.isEmpty else { return }
        UIPasteboard.general.string = response
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        withAnimation(.easeInOut(duration: 0.16)) {
            copiedResponse = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeInOut(duration: 0.16)) {
                copiedResponse = false
            }
        }
    }

    private func replayActiveLaneResponse() {
        guard let taskID = store.selectedTask?.id else { return }
        store.narrateLatestResponse(forTaskID: taskID)
    }

    private func adjacentLaneNumber(direction: Int) -> Int? {
        guard let active = store.activeLaneNumber else {
            return direction < 0 ? CodexLane.range.upperBound : CodexLane.range.lowerBound
        }
        if direction < 0 {
            return active == CodexLane.range.lowerBound ? CodexLane.range.upperBound : active - 1
        }
        return active == CodexLane.range.upperBound ? CodexLane.range.lowerBound : active + 1
    }

    private var deckStatusLabel: String {
        switch store.phase {
        case .listening: return "LISTENING"
        case .transcribing: return "TRANSCRIBING"
        case .submitting:
            return store.selectedActivity?.statusLabel
                ?? (store.selectedMessageMode == .queue ? "QUEUED" : "SENDING")
        case .preparingSpeech: return "VOICE INBOUND"
        case .speaking: return "SPEAKING"
        case .failed: return "ERROR"
        case .idle:
            guard let activity = store.selectedActivity else {
                return store.hasDispatchDestination ? "READY" : "NO TASK"
            }
            return activity.statusLabel
        }
    }

    private var deckMeterIsFailure: Bool { deckStatusLabel == "ERROR" }

    private var deckMeterIsActive: Bool {
        !["READY", "NO TASK", "NO LANE", "ERROR"].contains(deckStatusLabel)
    }

    private var deckPhaseColor: Color {
        deckMeterIsFailure ? deckFailureColor : theme.chrome.accent
    }

    private func openMapper() {
        showingMapper = true
    }

    private func openNewTask() {
        guard store.canCreateChannel, !store.isCreatingTask else { return }
        showingNewTask = true
    }

}

private struct VoicePlaybackWaveform: View {
    let samples: [Double]
    let progress: Double
    let isPlaying: Bool
    let accent: Color
    let inactive: Color
    let onSeek: (Double) -> Void
    let onSkip: (TimeInterval) -> Void
    @State private var scrubProgress: Double?
    @State private var skipFeedback: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1 / 15, paused: !isPlaying || reduceMotion || scrubProgress != nil)) { timeline in
                let count = max(1, samples.count)
                let spacing: CGFloat = 1.5
                let width = max(1, (geometry.size.width - (CGFloat(count - 1) * spacing)) / CGFloat(count))
                let playhead = min(1, max(0, scrubProgress ?? progress))
                let phase = timeline.date.timeIntervalSinceReferenceDate * 3.8

                ZStack {
                    HStack(spacing: spacing) {
                        ForEach(samples.enumerated(), id: \.offset) { index, sample in
                            let position = Double(index + 1) / Double(count)
                            let isPassed = position <= playhead
                            let motion = isPlaying && !reduceMotion && scrubProgress == nil
                                ? 0.95 + (0.05 * sin(phase + (Double(index) * 0.52)))
                                : 1

                            Capsule()
                                .fill(isPassed ? accent : inactive)
                                .frame(
                                    width: width,
                                    height: max(1.5, geometry.size.height * sample * motion)
                                )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                    Rectangle()
                        .fill(accent)
                        .frame(width: 1, height: geometry.size.height)
                        .shadow(color: accent.opacity(scrubProgress == nil ? 0 : 0.35), radius: 3)
                        .position(x: max(0.5, geometry.size.width * playhead), y: geometry.size.height / 2)

                    if let skipFeedback {
                        Text(skipFeedback > 0 ? "+15" : "−15")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(themeFill)
                            .clipShape(.rect(cornerRadius: 4))
                            .frame(maxWidth: .infinity, alignment: skipFeedback > 0 ? .trailing : .leading)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .contentShape(.rect)
                .gesture(scrubGesture(width: geometry.size.width))
                .simultaneousGesture(tapGesture(width: geometry.size.width))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
        .accessibilityElement()
        .accessibilityLabel("Narration position")
        .accessibilityValue("\(Int((scrubProgress ?? progress) * 100)) percent")
        .accessibilityAdjustableAction { direction in
            onSkip(direction == .increment ? 15 : -15)
        }
        .accessibilityAction(named: "Skip back 15 seconds") { onSkip(-15) }
        .accessibilityAction(named: "Skip forward 15 seconds") { onSkip(15) }
        .accessibilityHint("Drag to seek. Double tap the left or right half to skip 15 seconds.")
    }

    private var themeFill: Color {
        Color(uiColor: .secondarySystemBackground).opacity(0.92)
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                scrubProgress = progress(at: value.location.x, width: width)
            }
            .onEnded { value in
                let target = progress(at: value.location.x, width: width)
                scrubProgress = nil
                onSeek(target)
            }
    }

    private func tapGesture(width: CGFloat) -> some Gesture {
        SpatialTapGesture(count: 2, coordinateSpace: .local)
            .exclusively(before: SpatialTapGesture(count: 1, coordinateSpace: .local))
            .onEnded { value in
                switch value {
                case let .first(doubleTap):
                    let interval: TimeInterval = doubleTap.location.x < width / 2 ? -15 : 15
                    onSkip(interval)
                    showSkipFeedback(Int(interval))
                case let .second(singleTap):
                    onSeek(progress(at: singleTap.location.x, width: width))
                }
            }
    }

    private func showSkipFeedback(_ interval: Int) {
        withAnimation(.easeOut(duration: 0.12)) {
            skipFeedback = interval
        }
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            withAnimation(.easeOut(duration: 0.16)) {
                skipFeedback = nil
            }
        }
    }

    private func progress(at xPosition: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(1, max(0, xPosition / width))
    }
}

private struct CodexCommandConsole: View {
    let isCaptureActive: Bool
    let isCaptureCancelArmed: Bool
    let onShowMapper: () -> Void
    let onCreateNewTask: () -> Void

    @ObservedObject private var store = CodexLaneStore.shared
    @ObservedObject private var theme = ThemeManager.shared
    @State private var bridge = BridgeManager.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLaneTransport
                accessibilityTaskIdentity
            } else {
                lanePicker
                taskIdentity
            }
        }
        .padding(.horizontal, 10)
        .dynamicTypeSize(.xSmall ... .accessibility1)
    }

    private var lanePicker: some View {
        HStack(spacing: 0) {
            ForEach(Array(CodexLane.range), id: \.self) { number in
                if store.isTemporaryTaskSelected && number == CodexLane.range.upperBound {
                    temporaryTaskButton
                } else {
                    lanePickerButton(number)
                }

                if number != CodexLane.range.upperBound {
                    Rectangle()
                        .fill(
                            theme.chrome.panelInk.opacity(
                                colorScheme == .dark ? 0.09 : 0.20
                            )
                        )
                        .frame(width: theme.chrome.hairlineWidth, height: 14)
                }
            }
        }
        // Dense monospaced rail; full 44pt row so lane keys meet HIG.
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: max(6, theme.chrome.chromeCorner + 2), style: .continuous)
                .fill(theme.chrome.panel.opacity(colorScheme == .dark ? 0.78 : 0.94))
        )
        .overlay {
            RoundedRectangle(cornerRadius: max(6, theme.chrome.chromeCorner + 2), style: .continuous)
                .stroke(
                    theme.chrome.panelEdge.opacity(colorScheme == .dark ? 0.55 : 0.82),
                    lineWidth: theme.chrome.hairlineWidth
                )
        }
        .frame(height: 44)
        .contentShape(Rectangle())
        .sensoryFeedback(.selection, trigger: store.selectedTask?.id)
        .accessibilityLabel("Codex lanes")
    }

    private var temporaryTaskButton: some View {
        let isEnabled = !store.phase.isCapturing

        return Button(action: store.clearSelection) {
            ZStack(alignment: .top) {
                Capsule()
                    .fill(theme.chrome.panelAccent)
                    .frame(width: 22, height: 2)
                    .talkieAccentGlow(radius: 3)

                VStack(spacing: 1) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 8, weight: .semibold))

                    Text("TEMP")
                        .font(.system(size: 5.5, weight: .bold, design: .monospaced))
                        .tracking(0.4)
                }
                .foregroundStyle(theme.chrome.panelAccent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("Temporary Codex task selected")
        .accessibilityHint("Closes the temporary task and restores Lane 6")
        .accessibilityAddTraits(.isSelected)
    }

    private func lanePickerButton(_ number: Int) -> some View {
        let lane = store.lane(number)
        let isActive = store.activeLaneNumber == number
        let isEnabled = !store.phase.isCapturing

        return Button {
            guard let lane else {
                onShowMapper()
                return
            }
            Task { await store.activate(lane.number) }
        } label: {
            ZStack(alignment: .top) {
                if isActive {
                    Capsule()
                        .fill(theme.chrome.panelAccent)
                        .frame(width: 22, height: 2)
                        .talkieAccentGlow(radius: 3)
                }

                VStack(spacing: 1) {
                    Text(number < 10 ? "0\(number)" : "\(number)")
                        .font(.system(size: 8, weight: isActive ? .bold : .medium, design: .monospaced))
                        .tracking(0.55)

                    if let signal = laneRailSignal(number: number, lane: lane) {
                        HStack(spacing: 2) {
                            Circle()
                                .fill(signal.color)
                                .frame(width: 3, height: 3)
                                .talkieAccentGlow(radius: signal.isLive ? 2 : 0)

                            Text(signal.label)
                                .font(.system(size: 5.5, weight: .semibold, design: .monospaced))
                                .tracking(0.4)
                        }
                        .foregroundStyle(signal.color)
                    }
                }
                .foregroundStyle(
                    lane == nil
                        ? emptyLaneRailColor
                        : (isActive ? theme.chrome.panelAccent : mappedLaneRailColor)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled || isActive ? 1 : 0.76)
        .accessibilityLabel(lanePickerAccessibilityLabel(number: number, lane: lane, isActive: isActive))
        .accessibilityHint(lane == nil ? "Opens the task mapper" : "Selects this exact Codex task")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var emptyLaneRailColor: Color {
        colorScheme == .dark
            ? theme.chrome.panelInkFaint.opacity(0.28)
            : theme.chrome.panelInk.opacity(0.55)
    }

    private var mappedLaneRailColor: Color {
        colorScheme == .dark
            ? theme.chrome.panelInkFaint.opacity(0.72)
            : theme.chrome.panelInk.opacity(0.88)
    }

    private func laneKeySurface(isActive: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return shape
            .fill(isActive ? theme.colors.accent.opacity(0.20) : theme.chrome.panel)
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), .clear, Color.black.opacity(0.16)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay {
                shape.stroke(
                    isActive ? theme.colors.accent.opacity(0.78) : theme.chrome.panelInk.opacity(0.15),
                    lineWidth: isActive ? 1 : theme.chrome.hairlineWidth
                )
            }
            .shadow(color: Color.black.opacity(0.12), radius: 3, y: 2)
    }

    private func laneRailSignal(
        number: Int,
        lane: CodexLane?
    ) -> (label: String, color: Color, isLive: Bool)? {
        guard lane != nil else { return nil }

        let queuedCount = store.queuedMessageCount(for: number)
        if queuedCount > 0 {
            return (queuedCount > 1 ? "Q\(min(queuedCount, 9))" : "QUE", theme.chrome.panelAccent, true)
        }

        if let activity = store.activity(for: number) {
            switch activity.state {
            case .working(let mode):
                return (mode == .queue ? "QUE" : "RUN", theme.chrome.panelAccent, true)
            case .accepted(let delivery):
                return (
                    delivery == .queuedTurn ? "QUE" : "RUN",
                    theme.chrome.panelAccent,
                    true
                )
            case .receiving:
                return ("RX", theme.chrome.panelAccent, true)
            case .failed:
                return ("ERR", deckFailureColor, false)
            }
        }

        if store.isTurnInFlight(on: number) {
            return ("RUN", theme.chrome.panelAccent, true)
        }

        if store.latestTurn(for: number) != nil {
            return (
                "RX",
                colorScheme == .dark
                    ? theme.chrome.panelInkFaint.opacity(0.78)
                    : theme.chrome.panelInk.opacity(0.82),
                false
            )
        }

        return (
            "RDY",
            colorScheme == .dark
                ? theme.chrome.panelInkFaint.opacity(0.50)
                : theme.chrome.panelInk.opacity(0.70),
            false
        )
    }

    private func lanePickerAccessibilityLabel(
        number: Int,
        lane: CodexLane?,
        isActive: Bool
    ) -> String {
        guard let lane else { return "Lane \(number), empty" }
        return "Lane \(number), \(lane.task.title), \(isActive ? "selected" : "mapped")"
    }

    private var consoleHeader: some View {
        HStack(spacing: 7) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 9, weight: .medium))
            Text((bridge.pairedMacDisplayName ?? "MAC").uppercased())
                .lineLimit(1)
            Text("/")
                .foregroundStyle(consoleInkFaint.opacity(0.60))
            Text("CODEX")

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Circle()
                    .fill(phaseColor)
                    .frame(width: 5, height: 5)
                Text(consoleStatusLabel)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(phaseColor.opacity(0.13))
            )
            .overlay(
                Capsule().stroke(phaseColor.opacity(0.42), lineWidth: 0.6)
            )
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .tracking(1.2)
        .foregroundStyle(consoleInk)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(consoleInk.opacity(0.16))
                .frame(height: theme.chrome.hairlineWidth)
        }
    }

    private var taskIdentity: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(destinationTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.chrome.panelInk)
                    .lineLimit(1)

                if store.isTemporaryTaskSelected {
                    Label("TEMP", systemImage: "desktopcomputer")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(theme.chrome.panelInk.opacity(0.08))
                        )
                        .overlay {
                            Capsule().stroke(
                                theme.chrome.panelInk.opacity(0.18),
                                lineWidth: theme.chrome.hairlineWidth
                            )
                        }
                        .foregroundStyle(theme.chrome.panelInkFaint)
                        .accessibilityLabel("Temporary task")
                }

                Spacer(minLength: 6)
            }
            if let task = store.selectedTask {
                projectLocator(
                    name: task.projectName,
                    compactPath: task.compactPath,
                    branchName: task.branchName
                )
            } else if let project = store.newTaskProject {
                projectLocator(
                    name: project.name,
                    compactPath: project.compactPath,
                    branchName: nil
                )
            } else {
                Text("Use NEW to create a task, or open Mapper to choose an existing channel.")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(theme.chrome.panelInkFaint)
                    .lineLimit(2)
            }

            conversationPreview

            Spacer(minLength: 0)

            taskFooter
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background {
            RoundedRectangle(cornerRadius: taskIdentityCornerRadius, style: .continuous)
                .fill(theme.chrome.panel)
        }
        .overlay {
            RoundedRectangle(cornerRadius: taskIdentityCornerRadius, style: .continuous)
                .stroke(theme.chrome.panelEdge.opacity(0.78), lineWidth: theme.chrome.hairlineWidth)
        }
        .overlay {
            CodexCapturePerimeter(
                cornerRadius: taskIdentityCornerRadius,
                isActive: isCaptureActive,
                isCancelArmed: isCaptureCancelArmed,
                level: store.captureLevel,
                accent: theme.chrome.panelAccent,
                cancelColor: deckFailureColor
            )
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(taskIdentityAccessibilityLabel)
    }

    private func projectLocator(
        name: String,
        compactPath: String,
        branchName: String?
    ) -> some View {
        HStack(spacing: 5) {
            Label(name, systemImage: "folder")
                .fontWeight(.medium)
                .lineLimit(1)
                .layoutPriority(2)

            Text("|")
                .foregroundStyle(theme.chrome.panelInkFaint.opacity(0.46))
                .accessibilityHidden(true)

            Text(compactPath)
                .foregroundStyle(theme.chrome.panelInkFaint.opacity(0.70))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            if let branchName {
                Text("|")
                    .foregroundStyle(theme.chrome.panelInkFaint.opacity(0.46))
                    .accessibilityHidden(true)

                Label(branchName, systemImage: "arrow.triangle.branch")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.system(size: 8.5, weight: .regular, design: .monospaced))
        .foregroundStyle(theme.chrome.panelInkFaint)
        .lineLimit(1)
    }

    @ViewBuilder
    private var taskFooter: some View {
        if let footerStatus = taskFooterStatus {
            Rectangle()
                .fill(theme.chrome.panelInk.opacity(0.08))
                .frame(height: theme.chrome.hairlineWidth)

            HStack(spacing: 4) {
                Text(footerStatus.text)
                    .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                    .tracking(0.35)
                    .foregroundStyle(
                        footerStatus.isFailure
                            ? deckFailureColor
                            : theme.chrome.panelInkFaint.opacity(0.76)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 4)

                if let lane = store.activeLane {
                    laneModeSelector(lane)
                }

                if store.hasDispatchDestination {
                    clearTaskSelectionButton
                }
            }
            .frame(minHeight: 44)
        }
    }

    private var clearTaskSelectionButton: some View {
        Button(action: store.clearSelection) {
            ZStack {
                Circle()
                    .fill(theme.chrome.panelInk.opacity(0.06))
                    .frame(width: 24, height: 24)
                    .overlay {
                        Circle().stroke(
                            theme.chrome.panelInk.opacity(0.14),
                            lineWidth: theme.chrome.hairlineWidth
                        )
                    }

                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
            }
            .frame(width: 44, height: 44)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.chrome.panelInkFaint)
        .disabled(store.phase.isCapturing)
        .accessibilityIdentifier("codex-clear-task-selection")
        .accessibilityLabel("Deselect Codex task")
        .accessibilityHint("Returns the deck to no task selected")
    }

    private var taskIdentityCornerRadius: CGFloat {
        max(8, theme.chrome.chromeCorner + 4)
    }

    private var deckFailureColor: Color {
        Color(red: 0.92, green: 0.42, blue: 0.30)
    }

    @ViewBuilder
    private var conversationPreview: some View {
        if let number = store.activeLaneNumber,
           !store.activities(for: number).isEmpty {
            activityTimeline(store.activities(for: number), laneNumber: number)
        } else if !store.selectedDirectActivities.isEmpty {
            activityTimeline(store.selectedDirectActivities, laneNumber: nil)
        } else if let failure = store.failure {
            Label(failure.combined, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(deckFailureColor)
                .lineLimit(2)
        } else if let number = store.activeLaneNumber,
                  let turn = store.latestTurn(for: number) {
            VStack(alignment: .leading, spacing: 4) {
                conversationLine(label: "YOU", text: turn.instruction, lineLimit: 1)
                conversationLine(label: "CODEX", text: turn.response, lineLimit: 2)
            }
            .padding(.top, 2)
        } else if let taskID = store.selectedTask?.id,
                  let turn = store.latestTurn(forTaskID: taskID) {
            VStack(alignment: .leading, spacing: 4) {
                conversationLine(label: "YOU", text: turn.instruction, lineLimit: 1)
                conversationLine(label: "CODEX", text: turn.response, lineLimit: 2)
            }
            .padding(.top, 2)
        } else if store.newTaskProject != nil {
            Text("Hold the 14–15 key to create this task with your first ask.")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(theme.chrome.panelInkFaint)
                .lineLimit(2)
        } else if store.selectedTask != nil {
            Text("Hold the 14–15 key to talk directly to this task.")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(theme.chrome.panelInkFaint)
                .lineLimit(2)
        } else {
            Text("Use NEW to create a task, pick a lane above, or open Mapper.")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(theme.chrome.panelInkFaint)
                .lineLimit(2)
        }
    }

    private func laneModeSelector(_ lane: CodexLane) -> some View {
        HStack(spacing: 2) {
            laneModeButton(.steer, lane: lane)
            laneModeButton(.queue, lane: lane)
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.chrome.panelInk.opacity(0.07))
                .frame(height: 24)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(theme.chrome.panelInk.opacity(0.13), lineWidth: theme.chrome.hairlineWidth)
                .frame(height: 24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lane \(lane.number) delivery mode")
    }

    private func laneModeButton(_ mode: CodexMessageMode, lane: CodexLane) -> some View {
        let isActive = lane.preferredMessageMode == mode
        return Button {
            store.setMessageMode(mode, for: lane.number)
        } label: {
            Text(mode.label.uppercased())
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(isActive ? theme.chrome.panel : theme.chrome.panelInkFaint)
                .frame(width: 38, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isActive ? theme.chrome.panelAccent : Color.clear)
                )
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func activityTimeline(
        _ activities: [CodexLaneActivity],
        laneNumber: Int?
    ) -> some View {
        let visibleActivities = Array(activities.suffix(3))
        return VStack(alignment: .leading, spacing: 7) {
            ForEach(visibleActivities) { activity in
                liveActivity(
                    activity,
                    laneNumber: laneNumber,
                    isLatest: activity.id == visibleActivities.last?.id
                )
            }
        }
        .animation(.easeOut(duration: 0.18), value: visibleActivities)
    }

    private func liveActivity(
        _ activity: CodexLaneActivity,
        laneNumber: Int?,
        isLatest: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            conversationLine(label: "TX", text: activity.instruction, lineLimit: isLatest ? 2 : 1)

            switch activity.state {
            case .working(let mode):
                if isLatest, !activity.updates.isEmpty {
                    ForEach(Array(activity.updates.suffix(2))) { update in
                        progressLine(
                            update,
                            isLatest: update.id == activity.updates.last?.id
                        )
                    }
                }
                if !isLatest {
                    technicalLine(mode == .queue ? "Q> WAITING" : "HOST> WORKING")
                }
            case .accepted(let delivery):
                if isLatest, !activity.updates.isEmpty {
                    ForEach(Array(activity.updates.suffix(2))) { update in
                        progressLine(
                            update,
                            isLatest: update.id == activity.updates.last?.id
                        )
                    }
                }
                if !isLatest {
                    if activity.retryCount > 0 {
                        technicalLine(
                            "NET> RECONNECTING \(activity.retryCount) // RECEIPT SAFE"
                        )
                    } else {
                        technicalLine(acceptedTechnicalLine(for: delivery))
                    }
                }
            case .receiving:
                if let response = activity.response {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("RX")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(theme.chrome.panelAccent)
                            .frame(width: 38, alignment: .leading)

                        CodexPipedText(
                            text: response,
                            color: theme.chrome.panelInk.opacity(0.88)
                        )
                    }
                }
                if isLatest, let narrationLine = narrationTechnicalLine(for: laneNumber) {
                    technicalLine(narrationLine.text, isFailure: narrationLine.isFailure)
                }
            case .failed(let message):
                technicalLine("ERR> \(message)", isFailure: true)
            }
        }
        .padding(.top, 2)
    }

    private func progressLine(_ update: CodexProgressUpdate, isLatest: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(update.kind == "tool" ? "SYS" : "LIVE")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(
                    update.kind == "tool"
                        ? theme.chrome.panelInkFaint
                        : theme.chrome.panelAccent
                )
                .frame(width: 38, alignment: .leading)

            Text(update.text)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(theme.chrome.panelInk.opacity(isLatest ? 0.90 : 0.62))
                .lineLimit(isLatest && update.kind != "tool" ? 3 : 1)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .accessibilityElement(children: .combine)
    }

    private func technicalLine(_ text: String, isFailure: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(0.25)
            .foregroundStyle(
                isFailure
                    ? deckFailureColor
                    : theme.chrome.panelInkFaint
            )
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private func conversationLine(label: String, text: String, lineLimit: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(theme.chrome.panelAccent)
                .frame(width: 38, alignment: .leading)

            Text(text)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(theme.chrome.panelInk.opacity(0.82))
                .lineLimit(lineLimit)
        }
    }

    private func narrationTechnicalLine(
        for laneNumber: Int?
    ) -> (text: String, isFailure: Bool)? {
        guard store.narrationState.laneNumber == laneNumber else { return nil }

        switch store.narrationState {
        case .idle:
            return nil
        case .preparing(_, let route):
            return ("VOICE> \(route.displayName.uppercased()) // INBOUND", false)
        case .speaking(_, let route):
            return ("VOICE> \(route.displayName.uppercased()) // PLAYING", false)
        case .failed:
            return ("VOICE> FAILED // TAP NARRATE", true)
        case .suppressed(_, let route):
            if route == .silent {
                return ("VOICE> SILENT // KEY 01", false)
            }
            return ("VOICE> NOT PLAYED // TAP NARRATE", false)
        }
    }

    private func acceptedTechnicalLine(for delivery: CodexTurnDelivery) -> String {
        switch delivery {
        case .startedTurn:
            return "CODEX> ACCEPTED // WORKING"
        case .queuedTurn:
            return "CODEX> ACCEPTED // QUEUED TURN"
        case .steeredActiveTurn:
            return "CODEX> STEER ACCEPTED // TURN CONTINUES"
        }
    }

    private var taskFooterStatus: (text: String, isFailure: Bool)? {
        switch store.phase {
        case .listening:
            return ("MIC> LISTENING", false)
        case .transcribing:
            return ("MIC> TRANSCRIBING", false)
        case .preparingSpeech:
            return ("VOICE> PREPARING", false)
        case .speaking:
            return ("VOICE> SPEAKING", false)
        case .failed where store.selectedActivity == nil:
            return ("CODEX> ERROR", true)
        case .submitting, .idle, .failed:
            break
        }

        guard let activity = store.selectedActivity else {
            return store.hasDispatchDestination ? ("CODEX> READY", false) : nil
        }

        if activity.retryCount > 0 {
            let receipt = activity.jobID == nil ? "SAME DISPATCH" : "RECEIPT SAFE"
            return ("NET> RECONNECTING \(activity.retryCount) // \(receipt)", false)
        }

        switch activity.state {
        case .working(let mode):
            guard activity.jobID != nil else {
                return ("TX> SENDING // ONE DISPATCH", false)
            }
            return (
                mode == .queue
                    ? "HOST> RECEIVED // QUEUED"
                    : "HOST> RECEIVED // WAITING FOR CODEX",
                false
            )
        case .accepted(let delivery):
            return (acceptedTechnicalLine(for: delivery), false)
        case .receiving:
            return ("CODEX> RESPONSE // RECEIVED", false)
        case .failed:
            return ("CODEX> ERROR", true)
        }
    }

    private var consoleStatusLabel: String {
        if let narrationStatus = activeNarrationStatusLabel {
            return narrationStatus
        }

        switch store.phase {
        case .listening, .transcribing:
            return store.phase.label.uppercased()
        case .preparingSpeech, .speaking:
            break
        case .failed:
            return "ERROR"
        case .submitting:
            return store.selectedActivity?.statusLabel
                ?? (store.selectedMessageMode == .queue ? "QUEUED" : "SENDING")
        case .idle:
            break
        }

        guard let activity = store.selectedActivity else {
            return store.hasDispatchDestination ? "READY" : "NO TASK"
        }
        return activity.statusLabel
    }

    private var activeNarrationStatusLabel: String? {
        guard let number = store.activeLaneNumber,
              store.narrationState.laneNumber == number else { return nil }

        switch store.narrationState {
        case .idle:
            return nil
        case .preparing:
            return "VOICE INBOUND"
        case .speaking:
            return "SPEAKING"
        case .failed:
            return "VOICE FAILED"
        case .suppressed(_, let route):
            return route == .silent ? "SILENT" : "VOICE SKIPPED"
        }
    }

    private var phaseColor: Color {
        if let number = store.activeLaneNumber,
           store.narrationState.laneNumber == number,
           case .failed = store.narrationState {
            return deckFailureColor
        }
        if let number = store.activeLaneNumber,
           case .failed = store.activity(for: number)?.state {
            return deckFailureColor
        }
        switch store.phase {
        case .failed: return deckFailureColor
        case .idle: return !store.hasDispatchDestination
            ? theme.chrome.panelInkFaint
            : theme.chrome.panelAccent
        default: return theme.chrome.panelAccent
        }
    }

    private var consoleChassis: Color {
        theme.colors.cardBackground
    }

    private var consoleInk: Color {
        theme.colors.textPrimary
    }

    private var consoleInkFaint: Color {
        theme.colors.textTertiary
    }

    private var accessibilityLaneTransport: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Array(CodexLane.range), id: \.self) { number in
                    lanePickerButton(number)
                        .frame(width: 44)
                }

                Button(action: onShowMapper) {
                    Label("Map", systemImage: "rectangle.3.group")
                        .font(.caption.bold())
                        .frame(minWidth: 64, minHeight: 44)
                        .background(laneKeySurface(isActive: false))
                }
                .buttonStyle(.plain)

                Button(action: onCreateNewTask) {
                    Label("New", systemImage: "square.badge.plus")
                        .font(.caption.bold())
                        .frame(minWidth: 64, minHeight: 44)
                        .background(laneKeySurface(isActive: false))
                }
                .buttonStyle(.plain)
                .disabled(!store.canCreateChannel)
            }
            .padding(6)
        }
        .scrollIndicators(.hidden)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.chrome.panel)
        )
        .accessibilityLabel("Codex lane transport")
    }

    private var accessibilityTaskIdentity: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(destinationAccessibilityHeading)
                .font(.caption.bold())
                .foregroundStyle(theme.chrome.panelAccent)

            Text(destinationTitle)
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.chrome.panelInk)
                .lineLimit(2)

            Text(store.selectedDestinationIsInFlight ? "Turn active. Delivery mode is set for this destination." : "Hold key 14–15 to talk directly to this task.")
                .font(.caption)
                .foregroundStyle(theme.chrome.panelInkFaint)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 102, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.chrome.panel)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(taskIdentityAccessibilityLabel)
    }

    private var taskIdentityAccessibilityLabel: String {
        if let project = store.newTaskProject {
            return "New Codex task in \(project.name), ready for the first ask"
        }
        guard let task = store.selectedTask else {
            return "No active Codex task. Choose a lane or open the channel catalogue."
        }
        let destination = store.activeLaneNumber.map { "Lane \($0)" } ?? "Temporary task"
        return "\(destination), \(task.projectName), \(task.title), \(consoleStatusLabel)"
    }

    private var destinationAccessibilityHeading: String {
        if let project = store.newTaskProject {
            return "New task, \(project.name)"
        }
        guard let task = store.selectedTask else { return "No active task" }
        if let laneNumber = store.activeLaneNumber {
            return "Lane \(laneNumber), \(task.projectName)"
        }
        return "Temporary task, \(task.projectName)"
    }

    private var destinationTitle: String {
        if store.newTaskProject != nil { return "New task" }
        return store.selectedTask?.title ?? "Choose a channel"
    }
}

private struct CodexWorkingSignal: View {
    let mode: CodexMessageMode
    let queuedCount: Int
    let color: Color
    let secondaryColor: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                signal(frame: 0)
            } else {
                TimelineView(.animation(minimumInterval: 0.14)) { timeline in
                    let frame = Int(timeline.date.timeIntervalSinceReferenceDate * 7) % 7
                    signal(frame: frame)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func signal(frame: Int) -> some View {
        let cells = (0..<7)
            .map { $0 == frame ? "◆" : "·" }
            .joined()
        return HStack(spacing: 7) {
            Text("HOST>")
                .foregroundStyle(color)
            Text("[\(cells)]")
                .foregroundStyle(color)
            Text(statusText)
                .foregroundStyle(secondaryColor)
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .tracking(0.25)
        .lineLimit(1)
    }

    private var statusText: String {
        switch mode {
        case .queue:
            return queuedCount > 0 ? "QUEUE \(queuedCount) // WAIT" : "QUEUE // WAIT"
        case .steer:
            return "STEER // WORK"
        case .auto:
            return "TURN // WORK"
        }
    }

    private var accessibilityLabel: String {
        switch mode {
        case .queue: return "Message queued. Codex is working."
        case .steer: return "Steering message sent. Codex is working."
        case .auto: return "Message sent. Codex is working."
        }
    }
}

private struct CodexPipedText: View {
    let text: String
    let color: Color

    @State private var visibleCharacterCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(displayedText)
            .font(.system(size: 10, weight: .regular))
            .foregroundStyle(color)
            .lineLimit(2)
            .task(id: text) {
                await revealText()
            }
            .accessibilityLabel(text)
    }

    private var displayedText: String {
        let visible = String(text.prefix(visibleCharacterCount))
        return visibleCharacterCount < text.count ? "\(visible)▌" : visible
    }

    private func revealText() async {
        guard !reduceMotion else {
            visibleCharacterCount = text.count
            return
        }

        visibleCharacterCount = 0
        while visibleCharacterCount < text.count, !Task.isCancelled {
            visibleCharacterCount = min(text.count, visibleCharacterCount + 4)
            try? await Task.sleep(for: .milliseconds(24))
        }
    }
}

private struct CodexCapturePerimeter: View {
    let cornerRadius: CGFloat
    let isActive: Bool
    let isCancelArmed: Bool
    let level: Float
    let accent: Color
    let cancelColor: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isActive {
                if reduceMotion || isCancelArmed {
                    perimeter(rotation: 0, pulse: 0.5, includesMovingSignal: false)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate
                        let rotation = phase.truncatingRemainder(dividingBy: 3.4) * (360 / 3.4)
                        let pulse = 0.5 + (0.5 * sin(phase * 2.6))
                        perimeter(rotation: rotation, pulse: pulse, includesMovingSignal: true)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isActive)
        .animation(.easeInOut(duration: 0.14), value: isCancelArmed)
        .accessibilityHidden(true)
    }

    private func perimeter(rotation: Double, pulse: Double, includesMovingSignal: Bool) -> some View {
        let normalizedLevel = min(max(CGFloat(level), 0), 1)
        // Lift quieter speech without flattening louder moments so the console
        // reads as live across a natural speaking range.
        let audioResponse = normalizedLevel.squareRoot()
        let signal = 0.14 + audioResponse * 0.86
        let color = isCancelArmed ? cancelColor : accent
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return ZStack {
            shape
                .stroke(color.opacity(0.14 + signal * 0.22), lineWidth: 11 + signal * 10)
                .blur(radius: 7 + signal * 6)

            shape
                .stroke(color.opacity(0.24 + signal * 0.30), lineWidth: 4 + signal * 5)
                .blur(radius: 2 + signal * 3)

            shape
                .stroke(color.opacity(0.66 + signal * 0.28), lineWidth: 1.4 + signal * 2.2)

            if includesMovingSignal {
                shape.stroke(
                    AngularGradient(
                        colors: [
                            .clear,
                            color.opacity(0.06),
                            color.opacity(0.38 + audioResponse * 0.34),
                            color.opacity(0.96),
                            Color.white.opacity(0.82 + audioResponse * 0.18),
                            color.opacity(0.72 + audioResponse * 0.26),
                            color.opacity(0.10),
                            .clear,
                            .clear,
                        ],
                        center: .center,
                        startAngle: .degrees(rotation - 132),
                        endAngle: .degrees(rotation + 228)
                    ),
                    lineWidth: 3 + audioResponse * 4.8 + CGFloat(pulse) * 1.5
                )
                .shadow(
                    color: color.opacity(0.34 + audioResponse * 0.44),
                    radius: 4 + audioResponse * 7
                )

                shape.stroke(
                    AngularGradient(
                        colors: [
                            .clear,
                            color.opacity(0.05),
                            color.opacity(0.42 + audioResponse * 0.30),
                            .clear,
                            .clear,
                        ],
                        center: .center,
                        startAngle: .degrees(rotation + 48),
                        endAngle: .degrees(rotation + 408)
                    ),
                    lineWidth: 1.2 + audioResponse * 2.4
                )
                .blur(radius: 0.4 + audioResponse)
            }
        }
        .animation(.easeOut(duration: 0.09), value: audioResponse)
        .transition(.opacity)
    }
}

private struct CodexTaskDetailsSheet: View {
    @ObservedObject private var store = CodexLaneStore.shared
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let taskID = statusTaskID {
                    CodexStatusDocumentView(
                        taskID: taskID,
                        jobID: store.selectedTask?.id == taskID
                            ? store.selectedActivity?.jobID
                            : nil
                    )
                } else {
                    ContentUnavailableView(
                        "Choose a Codex task",
                        systemImage: "terminal",
                        description: Text("Select a channel to inspect its repository and live turn dossier.")
                    )
                    .background(theme.colors.background)
                }
            }
            .navigationTitle("Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.colors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(theme.chrome.accent)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var statusTaskID: String? {
        store.selectedTask?.id ?? store.lastTurn?.taskID
    }

}

private extension AIResponseSpeechRoute {
    var shortLabel: String {
        switch self {
        case .phone: return "PHONE"
        case .watch: return "WATCH"
        case .silent: return "MUTE"
        }
    }
}
