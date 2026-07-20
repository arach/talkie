//
//  RecordingCompanionSurface.swift
//  Talkie
//
//  Big-screen recording companion. Shows on the cream canvas while a
//  memo recording is active. The title-bar pill stays the always-on
//  baseline; this surface is the editorial echo of that pill across
//  the available canvas.
//
//  Studio sources of truth:
//    design/studio/app/mac-recording-state/light-instrument.tsx (disc + glass)
//    design/studio/app/mac-record-to-memo/page.tsx (wave → transcript transition)
//
//  Three variants ship side-by-side, swappable at runtime via the
//  `recordingCompanion.variant` defaults key:
//
//    .wave         — voice-adaptive amber flourish on a frosted glass
//                    disc (light-instrument sizing, heavy pour); corner
//                    chrome rests near-invisible until hover; on stop the
//                    wave settles into a baseline rule and the transcript
//                    emerges in place (record-to-memo choreography).
//    .frontispiece — book title page: hairline rules bracket eyebrow
//                    + monumental serif timer + italic byline + flourish.
//
//  Stop affordance lives in the caption row of both variants so big-
//  screen users don't have to chase the title-bar pill to end the
//  recording.
//

import SwiftUI
import TalkieKit
import Observation

// MARK: - Variant

enum RecordingCompanionVariant: String, CaseIterable {
    case wave
    case frontispiece
    case hud

    var label: String {
        switch self {
        case .wave: return "Wave"
        case .frontispiece: return "Frontispiece"
        case .hud: return "HUD"
        }
    }
}

// MARK: - Coordinator

/// Shared collapse state between the companion surface and the chrome-bar
/// pill, so the pill can tell whether its click means "stop" (the disc is
/// up) or "bring the disc back" (the recording is living in the capsule).
@MainActor
@Observable
final class RecordingCompanionCoordinator {
    static let shared = RecordingCompanionCoordinator()

    /// True while the recording surface is collapsed to the PiP capsule
    /// (manual minimize or auto-collapse after navigating away).
    var isCollapsed = false

    /// Incremented by the chrome-bar pill to ask the surface to expand.
    var expandRequestCount = 0

    private init() {}
}

// MARK: - Surface

struct RecordingCompanionSurface: View {
    let windowID: UUID

    private var controller: MemoRecordingController { MemoRecordingController.shared }

    @Environment(\.navigationState) private var navigationState

    @AppStorage("recordingCompanion.variant")
    private var variantRaw: String = RecordingCompanionVariant.wave.rawValue

    private var variant: RecordingCompanionVariant {
        RecordingCompanionVariant(rawValue: variantRaw) ?? .wave
    }

    /// Holds the surface visible past `.complete` so the transition into
    /// the emergent transcript has room to play out before dismissal.
    @State private var holdAfterComplete: Bool = false

    /// PiP mode: while recording, the user can collapse the full canvas
    /// surface into a floating pill in the bottom-right so they can keep
    /// working. Only meaningful while `controller.state.isRecording` —
    /// the surface auto-expands when the transition starts so the user
    /// sees the wave → memo emergence.
    @State private var minimized: Bool = false

    /// Section where the active recording began. Leaving it collapses
    /// the surface into the PiP capsule automatically — the recording
    /// follows you around the app — and returning brings the disc back.
    /// Cleared when the recording ends.
    @State private var recordingHomeSection: NavigationSection?

    /// One-shot override behind the capsule's expand affordance and the
    /// chrome-bar pill: brings the disc back even away from the
    /// recording's home section. Cleared on the next navigation, which
    /// re-collapses to the capsule if the user wanders off again.
    @State private var expandOverride = false

    private let coordinator = RecordingCompanionCoordinator.shared

    /// Auto-collapse: recording is live but the user has navigated away
    /// from where it started.
    private var autoMinimized: Bool {
        guard controller.state.isRecording, let home = recordingHomeSection else { return false }
        return navigationState.selectedSection != home
    }

    /// Effective collapse — manual or automatic, unless an explicit
    /// expand is currently overriding both.
    private var isCollapsed: Bool {
        (minimized || autoMinimized) && !expandOverride
    }

    private var isVisible: Bool {
        guard ownsPresentation else { return false }

        let state = controller.state
        if state.isRecording || state.isPreparing || state.isProcessing { return true }
        if case .complete = state { return holdAfterComplete }
        return false
    }

    private var ownsPresentation: Bool {
        guard let ownerID = controller.presentationOwnerID else { return true }
        return ownerID == windowID
    }

    /// PiP only shows while we're actively recording (manually minimized
    /// or auto-collapsed by navigating away). As soon as the transition
    /// kicks off (.processing → .complete), force the full surface back
    /// so the user sees the wave settle and transcript emerge.
    private var shouldShowPip: Bool {
        isCollapsed && controller.state.isRecording
    }

    /// Expand from the capsule — shared by the capsule's ↗ button and
    /// the chrome-bar pill. The override holds the disc up until the
    /// user navigates again, which re-arms the auto-collapse.
    private func expandFromCapsule() {
        minimized = false
        expandOverride = true
    }

    var body: some View {
        Group {
            if isVisible {
                if shouldShowPip {
                    pipMount
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottomTrailing)))
                } else {
                    content
                        .overlay(alignment: .topLeading) { minimizeButton }
                        // Dock under the chrome bar — the disc is a
                        // companion strip, not a modal covering the
                        // whole canvas height.
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 24)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.36), value: isVisible)
        .animation(.easeInOut(duration: 0.28), value: shouldShowPip)
        .onChange(of: controller.state.signalToken) { _, newValue in
            handleStateChange(token: newValue)
            // Any phase that isn't .recording snaps us back to the full
            // surface — the wave-settles-into-transcript moment is the
            // whole point of the surface; never hide it behind a pill.
            if newValue != "recording" {
                minimized = false
                expandOverride = false
            }
        }
        .onChange(of: navigationState.selectedSection) {
            // Moving on re-arms the auto-collapse — an explicit expand
            // only holds until the user moves on.
            expandOverride = false
        }
        .onChange(of: coordinator.expandRequestCount) {
            expandFromCapsule()
        }
        .onChange(of: shouldShowPip) { _, collapsed in
            coordinator.isCollapsed = collapsed
        }
        .onAppear {
            coordinator.isCollapsed = shouldShowPip
        }
    }

    /// Bottom-right pinned PiP capsule. Wraps in a full-size frame so
    /// the parent's `.overlay(alignment: .center)` mount point doesn't
    /// strand the capsule in the middle of the canvas.
    private var pipMount: some View {
        RecordingPipCapsule(
            controller: controller,
            onExpand: expandFromCapsule
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, Spacing.md)
        .padding(.bottom, Spacing.xl)
        .allowsHitTesting(true)
    }

    /// Quiet minimize affordance on the full surface — sits top-left so
    /// it can't be mistaken for the top-right cancel cluster.
    private var minimizeButton: some View {
        Button {
            minimized = true
        } label: {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(RecordingCompanionTokens.inkFaint)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .opacity(0.45)
        .padding(.leading, 18)
        .padding(.top, 14)
        .help("Minimize (recording continues)")
    }

    private func handleStateChange(token: String) {
        if token == "complete" {
            // Keep the surface mounted while the transcript emerges, then
            // fade. The total hold is decay (~400ms) + emergence (~1100ms)
            // + post-hold (~900ms) so the user has a beat to read the
            // settled transcript before it dismisses.
            holdAfterComplete = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(2400))
                if case .complete = controller.state {
                    holdAfterComplete = false
                }
            }
        } else {
            // Any non-complete state (idle / recording / preparing /
            // processing / error) — drop the post-complete hold.
            holdAfterComplete = false
        }

        // Track where the recording lives so leaving the section can
        // auto-collapse the surface into the PiP capsule.
        if token == "preparing" || token == "recording" {
            if recordingHomeSection == nil {
                recordingHomeSection = navigationState.selectedSection
            }
        } else if token == "idle" || token == "error" {
            recordingHomeSection = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch variant {
        case .wave:
            WaveOnlyContent(controller: controller)
        case .frontispiece:
            FrontispieceContent(controller: controller)
        case .hud:
            RecordingHUDView()
        }
    }
}

// MARK: - Wave-only variant

/// Phases of the recording → memo transition. Driven by `MemoRecordingController.state`
/// transitions; mapped at `syncPhase()`.
private enum TransitionPhase {
    case recording   // wave at audio amplitude
    case stopping    // wave amplitude decaying to 0
    case settling    // wave is now a flat baseline; transcription in flight
    case emerging    // transcript revealing left→right along the baseline
    case complete    // transcript fully revealed; surface holds before dismissal
}

/// Geometry for the wave disc. Between the studio light-instrument
/// (560×184) and the first port (980×~310) — big enough to feel like
/// an instrument, small enough to stay a companion strip.
private enum WaveLayout {
    static let waveWidth: CGFloat = 700
    static let waveHeight: CGFloat = 150
    static let cardMaxWidth: CGFloat = 820
    /// Exact card height. Must be explicit — a `minHeight` frame lets
    /// the chrome layer's Spacer stretch the glass sheet to the full
    /// height the overlay proposes. Taller than the first port (250) so
    /// the live transcript gets its own lane below the wave instead of
    /// colliding with the caption/STOP row.
    static let cardHeight: CGFloat = 320
    static let cardHPadding: CGFloat = 44
    static let cardVPadding: CGFloat = 30
    static let transcriptMaxWidth: CGFloat = 700
}

private struct WaveOnlyContent: View {
    let controller: MemoRecordingController

    // Visible amplitude. Smoothing task writes during .recording only;
    // explicit withAnimation drives it to 0 during .stopping.
    @State private var amplitude: CGFloat = 0.30

    // Where in the transition we are.
    @State private var phase: TransitionPhase = .recording

    // Progress of the left→right text reveal (0 = hidden, 1 = full).
    @State private var emergeProgress: CGFloat = 0

    // Transcript captured from `.complete(MemoModel)`.
    @State private var transcript: String = ""

    /// Card hover state. The corner clusters (top-right detail cluster
    /// + bottom-right STOP) sit near-invisible at rest (`restOpacity`)
    /// and sharpen to full opacity when the pointer enters the surface.
    /// Space-bar + ⌘. keyboard paths still work either way.
    @State private var isHoveringCard: Bool = false

    /// Studio source of truth: `design/studio/app/mac-recording-state/light-instrument.tsx`.
    /// Decorations rest near-invisible — the surface IS the wave — and
    /// only the cursor brings them out.
    private let restOpacity: Double = 0.06

    var body: some View {
        ZStack {
            // The wave owns the card's vertical center, nudged up so it
            // clears the bottom deck's transcript lane. Chrome (top row
            // + bottom deck) layers above it.
            waveAndTranscript
                .offset(y: -16)
            chromeLayer
        }
        .padding(.horizontal, WaveLayout.cardHPadding)
        .padding(.vertical, WaveLayout.cardVPadding)
        .frame(maxWidth: WaveLayout.cardMaxWidth)
        .frame(height: WaveLayout.cardHeight)
        // Glass disc: deeper blur + a heavier pour than the first port,
        // per the studio light-instrument recipe (blur 64 · saturate 1.6
        // · white gradient 0.82 → 0.55). The disc reads as its own
        // surface — the canvas stops leaking through.
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: RecordingCompanionTokens.paper.opacity(0.82), location: 0.00),
                                    .init(color: RecordingCompanionTokens.paper.opacity(0.68), location: 0.50),
                                    .init(color: RecordingCompanionTokens.paper.opacity(0.55), location: 1.00),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .shadow(color: RecordingCompanionTokens.cardShadow, radius: 24, y: 9)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            RecordingCompanionTokens.edgeHighlight.opacity(0.45),
                            RecordingCompanionTokens.edgeLowlight.opacity(0.12),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .onHover { isHoveringCard = $0 }
        .task { await runSmoothing() }
        .onChange(of: controller.state.signalToken) { _, _ in
            syncPhase()
        }
        .onAppear { syncPhase() }
    }

    // MARK: - Opacity ramps

    /// Top-right details cluster visibility. Visible only while we are
    /// actively recording; rest near-invisible until the pointer enters
    /// the card. Once the transition starts the wave owns the canvas.
    private var detailsOpacity: Double {
        guard phase == .recording else { return 0 }
        return isHoveringCard ? 1.0 : restOpacity
    }

    /// STOP pill visibility. Stays essentially fully visible while
    /// recording — the way out of the surface shouldn't be a hover
    /// secret (rest 0.92 → 1.0 on hover). Hidden after .recording:
    /// there's nothing left to stop once the transition starts.
    private var stopOpacity: Double {
        guard phase == .recording else { return 0 }
        return isHoveringCard ? 1.0 : 0.92
    }

    // MARK: - Pieces

    private var chromeLayer: some View {
        VStack(spacing: 0) {
            topChromeRow
            Spacer(minLength: 0)
            bottomDeck
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    /// Bottom deck: the live-transcript ticker gets its own full-width
    /// lane above the caption/STOP row, left-aligned with the caption so
    /// the whole deck shares one left edge. The original overlap came
    /// from the ticker living in the wave's VStack while the caption row
    /// floated into the same band from the chrome ZStack — two layouts,
    /// one strip of space. STOP sits at the right end of the caption
    /// row and stays visible (see `stopOpacity`).
    private var bottomDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            liveTranscriptLine
            HStack(alignment: .center, spacing: 12) {
                DiscCaption(text: captionText, active: phase == .recording)
                    .animation(.easeOut(duration: 0.24), value: captionText)
                Spacer(minLength: 0)
                DiscStop(action: stopRecording)
                    .opacity(stopOpacity)
                    .allowsHitTesting(phase == .recording)
            }
        }
        .animation(.easeOut(duration: 0.20), value: isHoveringCard)
        .animation(.easeOut(duration: 0.24), value: phase)
    }

    private var topChromeRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                DiscDetails(phase: phase, timeString: timeString)
                DiscClose(action: cancelRecording)
            }
            .opacity(detailsOpacity)
            .allowsHitTesting(phase == .recording && isHoveringCard)
        }
        .animation(.easeOut(duration: 0.20), value: isHoveringCard)
        .animation(.easeOut(duration: 0.24), value: phase)
    }

    /// The wave and the emerging transcript share the same vertical slot,
    /// so as the wave collapses into a baseline the text appears in the
    /// same place — the wave literally becomes the writing.
    private var waveAndTranscript: some View {
        ZStack {
            animatedWave
            baselineRule
            emergingTranscript
        }
        .frame(width: WaveLayout.waveWidth, height: WaveLayout.waveHeight)
        .allowsHitTesting(false)
    }

    /// Amber rule at the wave's midline. The wave settles INTO this line
    /// rather than vanishing (the record-to-memo port note). While
    /// transcription runs, a bright segment travels along it — the quiet
    /// "still working" signal. As the transcript types in, the line
    /// fades out so the text never fights the rule.
    private var baselineRule: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Rectangle()
                .fill(amberGradient)
                .frame(width: WaveLayout.waveWidth, height: 1.2)
                .overlay {
                    shimmerSegment(t: t)
                }
                .opacity(baselineOpacity)
        }
    }

    /// Traveling bright segment while `.settling` — a "transcribing"
    /// pulse sweeping left → right along the steady baseline.
    private func shimmerSegment(t: TimeInterval) -> some View {
        let sweep = CGFloat((t / 1.6).truncatingRemainder(dividingBy: 1))
        let x = (sweep - 0.5) * (WaveLayout.waveWidth + 80)
        return Capsule()
            .fill(RecordingCompanionTokens.amberGlow)
            .frame(width: 56, height: 3)
            .blur(radius: 1.5)
            .offset(x: x)
            .opacity(phase == .settling ? 1 : 0)
    }

    private var baselineOpacity: Double {
        switch phase {
        case .recording, .stopping:
            // Fade in smoothly as the wave flattens through ~0.08 → 0.04.
            let t = (0.08 - amplitude) / 0.04
            return 0.85 * Double(min(max(t, 0), 1))
        case .settling:
            return 0.85
        case .emerging:
            // The line hands the slot to the text — gone by ~40% reveal.
            return 0.85 * Double(max(0, 1 - emergeProgress * 2.5))
        case .complete:
            return 0
        }
    }

    /// Real-time transcription confirmation — the "it's hearing you"
    /// ticker. Lives in its own full-width lane at the top of the bottom
    /// deck, left-aligned with the caption row beneath it, so the text
    /// never overlaps the card chrome. The lane height is always
    /// reserved so the card never jumps when the first words land; the
    /// line fades in with the first update and fades out as the wave
    /// starts to settle. Rendering is a `DecryptTicker` — incoming text
    /// streams in fast bursts with a glyph-cycling head.
    private var liveTranscriptLine: some View {
        DecryptTicker(target: controller.liveTranscript)
            .lineLimit(1)
            .truncationMode(.head)  // ticker — the newest words stay visible
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 20)
            .opacity(liveLineOpacity)
            .animation(.easeOut(duration: 0.3), value: controller.liveTranscript.isEmpty)
            .animation(.easeOut(duration: 0.24), value: phase)
    }

    private var liveLineOpacity: Double {
        guard phase == .recording, !controller.liveTranscript.isEmpty else { return 0 }
        return 0.9
    }

    private var animatedWave: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // Negative phase advance flows the wave right→left across
            // the canvas (matches how the user reads "audio is being
            // captured" — leading edge enters from the right). Bumped
            // toward the studio's livelier traversal.
            let phaseSpeed: CGFloat = -3.6
            // Organic breathing on top of the voice envelope so the wave
            // shimmers between syllables. Multiplicative — silence stays
            // calm because it scales with the level-driven amplitude.
            let breath = 1 + 0.06 * sin(t * 1.6) + 0.04 * sin(t * 3.9 + 1.1)

            InkFlourishShape(
                amplitude: amplitude * breath,
                phase: CGFloat(t) * phaseSpeed
            )
            .stroke(amberGradient, lineWidth: waveStroke)
            .shadow(color: RecordingCompanionTokens.amberGlow.opacity(waveGlow), radius: 3)
            .opacity(waveOpacity)
        }
    }

    /// The wave hands its midline to the baseline rule as it flattens —
    /// otherwise the flattened stroke lingers as a second line behind
    /// the emerging text. Crossfades with `baselineOpacity`.
    private var waveOpacity: Double {
        switch phase {
        case .recording, .stopping:
            let t = (0.08 - amplitude) / 0.04
            return 1 - Double(min(max(t, 0), 1))
        case .settling, .emerging, .complete:
            return 0
        }
    }

    /// Stroke thins slightly as the wave settles so the transition into a
    /// quiet baseline feels deliberate rather than abrupt.
    private var waveStroke: CGFloat {
        switch phase {
        case .recording: return 2.4
        case .stopping: return 2.0
        case .settling, .emerging, .complete: return 1.2
        }
    }

    private var waveGlow: Double {
        switch phase {
        // Loud voice blooms; quiet voice stays crisp. Tracks the
        // smoothed envelope so the glow breathes with the amplitude.
        case .recording: return 0.20 + 0.30 * Double(min(amplitude, 1))
        case .stopping: return 0.20
        case .settling, .emerging, .complete: return 0.0
        }
    }

    /// Transcript text reveals along the wave's baseline via a feathered
    /// left→right sweep paired with a 6pt baseline rise — letters
    /// dissolve in instead of being clipped mid-glyph. The baseline
    /// rule is already fading by the time the first words land, so the
    /// ending is just the letters.
    private var emergingTranscript: some View {
        Text(transcript)
            .font(RecordingCompanionFonts.serif(size: 22))
            .foregroundColor(RecordingCompanionTokens.ink)
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .truncationMode(.tail)
            .frame(maxWidth: WaveLayout.transcriptMaxWidth)
            .padding(.horizontal, 16)
            .offset(y: (1 - emergeProgress) * 6)
            .opacity(emergeProgress > 0 ? Double(emergeProgress) : 0)
            .mask(
                GeometryReader { geo in
                    let feather: CGFloat = 36
                    let head = (geo.size.width + feather) * emergeProgress - feather
                    let solidEnd = max(0, min(1, head / geo.size.width))
                    let fadeEnd = max(0, min(1, (head + feather) / geo.size.width))
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: solidEnd),
                            .init(color: .clear, location: fadeEnd),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            )
    }

    private var captionText: String {
        if phase == .recording, let message = controller.captureStatusMessage {
            return "\(timeString) · \(message.uppercased())"
        }

        switch phase {
        case .recording: return "\(timeString) · RECORDING MEMO"
        case .stopping: return "\(timeString) · STOPPING"
        case .settling: return "\(timeString) · TRANSCRIBING…"
        case .emerging: return "\(timeString) · TRANSCRIBING…"
        case .complete: return "\(timeString) · MEMO FILED"
        }
    }

    // MARK: - Derived strings & actions

    private var timeString: String {
        let total = max(0, Int(controller.elapsedTime))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func stopRecording() {
        controller.stopRecording()
    }

    /// Discard the in-flight recording. Matches the X-affordance from
    /// the legacy `inlineRecordingUI`. Clears continuingMemoId /
    /// targetNoteId / temp file so the surface unmounts cleanly.
    private func cancelRecording() {
        controller.cancelRecording()
    }

    private var amberGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: RecordingCompanionTokens.amber.opacity(0.0), location: 0.00),
                .init(color: RecordingCompanionTokens.amber.opacity(0.95), location: 0.04),
                .init(color: RecordingCompanionTokens.amber.opacity(0.90), location: 0.94),
                .init(color: RecordingCompanionTokens.amber.opacity(0.0), location: 1.00),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Phase machine

    /// Maps `controller.state` to our local `phase` and runs the right
    /// animations on each transition.
    @MainActor
    private func syncPhase() {
        switch controller.state {
        case .preparing, .recording:
            // Amplitude is driven by the smoothing task below; nothing to
            // do here besides ensuring phase is correct.
            if phase != .recording {
                phase = .recording
                emergeProgress = 0
                transcript = ""
            }

        case .processing:
            guard phase == .recording else { return }
            // Decay the wave amplitude to zero — the wave settles INTO a
            // baseline rather than disappearing. The smoothing task gates
            // on phase so it stops fighting the animation.
            phase = .stopping
            withAnimation(.easeOut(duration: 0.42)) {
                amplitude = 0
            }
            // After the decay completes, mark settling. The wave is now a
            // flat baseline at midY (amplitude = 0 → all yOffsets = 0).
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(420))
                if phase == .stopping {
                    phase = .settling
                }
            }

        case .complete(let memo):
            // Transcript is in. Begin the emergence reveal — text fills in
            // along the baseline left→right.
            transcript = memo.transcription ?? ""
            // If somehow we skipped processing (extremely fast pipeline),
            // collapse amplitude immediately.
            if amplitude > 0.01 {
                withAnimation(.easeOut(duration: 0.20)) {
                    amplitude = 0
                }
            }
            phase = .emerging
            withAnimation(.timingCurve(0.22, 0.61, 0.36, 1.0, duration: 0.85)) {
                emergeProgress = 1
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(850))
                if phase == .emerging {
                    phase = .complete
                }
            }

        case .idle, .error:
            phase = .recording
            amplitude = 0.30
            emergeProgress = 0
            transcript = ""
        }
    }

    // MARK: - Smoothing

    @MainActor
    private func runSmoothing() async {
        // Envelope follower — only writes amplitude during .recording.
        // In every other phase the explicit transitions own the value
        // so the wave can settle / hold cleanly.
        //
        // Asymmetric attack / release:
        //  - attack 0.50: the wave snaps onto a loud syllable almost
        //    immediately — voice modulation reads in real time
        //  - release 0.16: the tail lets go faster than before so quiet
        //    gaps between words actually read as gaps
        //
        // Gamma 0.55 (was 0.72) opens up travel for conversational
        // voice — normal speech swings the wave through most of its
        // range instead of hovering mid-amplitude. Floor 0.16 keeps a
        // whisper of motion at true silence.
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            guard phase == .recording else { continue }
            let raw = CGFloat(min(max(controller.audioLevel, 0), 1))
            let shaped = pow(raw, 0.55)
            let desired = 0.16 + shaped * 0.84
            let blend: CGFloat = desired > amplitude ? 0.50 : 0.16
            amplitude = amplitude * (1 - blend) + desired * blend
        }
    }
}

// MARK: - Live decrypt ticker

/// Live-transcript ticker with a typewriter cadence and a decrypt head.
///
/// Two ideas stacked:
///   1. Typewriter catch-up — incoming transcript isn't stamped onto
///      the lane the moment it arrives; it's queued and typed out in
///      fast bursts (the bigger the backlog, the more chars per tick),
///      so each new phrase reads as a little stream instead of a jumpy
///      whole-line replace.
///   2. Decrypt head — the newest few characters spend a handful of
///      ticks cycling random glyphs (mono, amber) before locking into
///      the settled serif text. Reads as "listening AND decoding"
///      without slowing the stream down.
///
/// Live transcription sometimes revises its own tail; when the target
/// stops sharing our typed prefix we resync to the common prefix and
/// retype from there.
private struct DecryptTicker: View {
    /// The live transcript as reported by the controller.
    let target: String

    /// Fully locked-in text (serif italic, faint ink).
    @State private var committed: String = ""

    /// Newest characters still cycling glyphs before they lock.
    @State private var head: [(ch: Character, cycles: Int)] = []

    /// Ticker cadence. ~24ms keeps the scramble smooth without paying
    /// for a full 60fps TimelineView on a one-line readout.
    private let tickInterval = Duration.milliseconds(24)

    /// Ticks a character spends scrambling before it locks.
    private let glyphCycles = 3

    /// Glyph pool for the decrypt head — lowercase plus a few marks so
    /// the scramble reads as decoding, not static.
    private let scramblePool: [Character] = Array("abcdefghjkmnpqrstuvwxyz·•×+")

    var body: some View {
        (Text(committed.isEmpty && head.isEmpty ? " " : committed)
            .font(RecordingCompanionFonts.serifItalic(size: 15))
            .foregroundColor(RecordingCompanionTokens.inkFaint)
        + Text(scrambledHead)
            .font(RecordingCompanionFonts.mono(size: 12))
            .foregroundColor(RecordingCompanionTokens.amber.opacity(0.85)))
        .task { await pump() }
    }

    /// The decrypt head rendered: settled spaces pass through, letters
    /// show a random pool glyph (re-rolled every tick's re-render).
    private var scrambledHead: String {
        String(head.map { entry in
            entry.ch.isWhitespace ? entry.ch : (scramblePool.randomElement() ?? "·")
        })
    }

    @MainActor
    private func pump() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: tickInterval)
            tick()
        }
    }

    private func tick() {
        // Live transcription revises its tail — resync to the shared
        // prefix and retype whatever changed.
        let typed = committed + String(head.map { $0.ch })
        if !target.hasPrefix(typed) {
            committed = String(typed.commonPrefix(with: target))
            head = []
        }

        // Age the decrypt head; locked chars join the settled text.
        for i in head.indices { head[i].cycles -= 1 }
        while let first = head.first, first.cycles <= 0 {
            committed.append(first.ch)
            head.removeFirst()
        }

        // Pull new chars — the deeper the backlog, the more per tick,
        // so long updates stream in fast bursts instead of lagging.
        let typedCount = committed.count + head.count
        let backlog = target.count - typedCount
        guard backlog > 0 else { return }
        let pull = min(backlog, max(1, backlog / 6))
        let start = target.index(target.startIndex, offsetBy: typedCount)
        let end = target.index(start, offsetBy: pull)
        for ch in target[start..<end] {
            if ch.isWhitespace {
                committed.append(ch)
            } else {
                head.append((ch, glyphCycles))
            }
        }
    }
}

// MARK: - PiP capsule (minimized recording)

/// Floating recording capsule. Lives in the bottom-right corner while
/// the full surface is minimized so the user can keep working without
/// losing the "you're still recording" signal.
///
/// Studio source of truth:
///   design/studio/app/mac-record-to-memo/page.tsx — PipCapsule + PipMiniWave.
///
/// Persistent (always visible at full opacity): red REC dot + timer.
/// Affordances (expand · STOP) ghost at 40% rest, snap to full on hover —
/// same contract as the full surface's corner clusters.
private struct RecordingPipCapsule: View {
    let controller: MemoRecordingController
    let onExpand: () -> Void

    @State private var amplitude: CGFloat = 0.32
    @State private var hovered: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            // Persistent — these never fade. Without them the user
            // can't tell at a glance whether recording is still live.
            HStack(spacing: 6) {
                RecDot()
                Text(timeString)
                    .font(RecordingCompanionFonts.mono(size: 10))
                    .monospacedDigit()
                    .foregroundColor(RecordingCompanionTokens.ink)
                    .allowsHitTesting(false)
            }

            // Mini wave — supporting voice signal, kept at low opacity
            // so it doesn't shout.
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                InkFlourishShape(
                    amplitude: amplitude,
                    phase: CGFloat(t) * -2.6
                )
                .stroke(
                    RecordingCompanionTokens.amber.opacity(0.85),
                    lineWidth: 1.4
                )
            }
            .frame(width: 80, height: 18)
            .opacity(0.55)
            .allowsHitTesting(false)

            // Hover-revealed cluster: expand + STOP.
            HStack(spacing: 4) {
                Button(action: onExpand) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(RecordingCompanionTokens.inkFaint)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("Expand recording surface")

                Button(action: { controller.stopRecording() }) {
                    Text("STOP")
                        .font(RecordingCompanionFonts.mono(size: 9))
                        .tracking(1.8)
                        .foregroundColor(Color(red: 1.0, green: 0.969, blue: 0.961))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(red: 0.753, green: 0.227, blue: 0.165))
                        )
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .keyboardShortcut(".", modifiers: [.command])
                .help("Stop recording (⌘.)")
            }
            .opacity(hovered ? 1.0 : 0.4)
            .animation(.easeOut(duration: 0.18), value: hovered)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(RecordingCompanionTokens.pillTint.opacity(0.45))
                )
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(RecordingCompanionTokens.edgeHighlight.opacity(0.28), lineWidth: 0.5)
        )
        .onHover { hovered = $0 }
        .task { await runSmoothing() }
    }

    private var timeString: String {
        let total = max(0, Int(controller.elapsedTime))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Same smoothing contract as `WaveOnlyContent.runSmoothing` — quiet
    /// floor, generous headroom for peaks, asymmetric attack/release.
    @MainActor
    private func runSmoothing() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            guard controller.state.isRecording else { continue }
            let raw = CGFloat(min(max(controller.audioLevel, 0), 1))
            let shaped = pow(raw, 0.55)
            let desired = 0.16 + shaped * 0.64
            let blend: CGFloat = desired > amplitude ? 0.50 : 0.16
            amplitude = amplitude * (1 - blend) + desired * blend
        }
    }
}

// MARK: - Frontispiece variant

private struct FrontispieceContent: View {
    let controller: MemoRecordingController

    @State private var smoothedLevel: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(RecordingCompanionTokens.ink.opacity(0.18))
                .frame(height: 0.5)

            VStack(spacing: 28) {
                eyebrow
                timerDisplay
                byline
                animatedFlourish
            }
            .padding(.vertical, 48)

            Rectangle()
                .fill(RecordingCompanionTokens.ink.opacity(0.18))
                .frame(height: 0.5)

            HStack(spacing: 14) {
                Text("RECORDING MEMO")
                    .font(RecordingCompanionFonts.mono(size: 10))
                    .tracking(2.8)
                    .foregroundColor(RecordingCompanionTokens.inkFaint)
                    .allowsHitTesting(false)
                Spacer()
                CancelButton(action: cancelRecording)
                StopButton(action: stopRecording)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 72)
        .frame(maxWidth: 880)
        .task { await runSmoothing() }
    }

    // MARK: - Pieces

    private var eyebrow: some View {
        HStack(spacing: 12) {
            RecDot()
            Text("RECORDING")
                .font(RecordingCompanionFonts.mono(size: 10))
                .tracking(3.6)
                .foregroundColor(RecordingCompanionTokens.inkFaint)
            Text("·")
                .font(RecordingCompanionFonts.mono(size: 10))
                .foregroundColor(RecordingCompanionTokens.inkFainter)
            Text("LIBRARY")
                .font(RecordingCompanionFonts.mono(size: 10))
                .tracking(3.6)
                .foregroundColor(RecordingCompanionTokens.inkFaint)
            Text("·")
                .font(RecordingCompanionFonts.mono(size: 10))
                .foregroundColor(RecordingCompanionTokens.inkFainter)
            Text("SCOPE")
                .font(RecordingCompanionFonts.mono(size: 10))
                .tracking(3.6)
                .foregroundColor(RecordingCompanionTokens.inkFaint)
        }
        .allowsHitTesting(false)
    }

    private var timerDisplay: some View {
        Text(timeString)
            .font(RecordingCompanionFonts.serif(size: 196))
            .foregroundColor(RecordingCompanionTokens.ink)
            .kerning(-9)
            .monospacedDigit()
            .fixedSize()
            .allowsHitTesting(false)
    }

    private var byline: some View {
        Text(bylineText)
            .font(RecordingCompanionFonts.serifItalic(size: 16))
            .foregroundColor(RecordingCompanionTokens.inkFaint)
            .allowsHitTesting(false)
    }

    private var animatedFlourish: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // Steadier than the wave variant — flourish is supporting
            // cast under the monumental timer.
            let phaseSpeed: CGFloat = 1.1
            let amp: CGFloat = 0.32 + smoothedLevel * 0.40

            InkFlourishShape(
                amplitude: amp,
                phase: CGFloat(t) * phaseSpeed
            )
            .stroke(amberGradient, lineWidth: 1.6)
            .frame(width: 680, height: 56)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Derived strings & actions

    private var timeString: String {
        let total = max(0, Int(controller.elapsedTime))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var bylineText: String {
        let start = Date().addingTimeInterval(-controller.elapsedTime)
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mm a"
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "d MMM yyyy"
        return "since \(timeFmt.string(from: start)) · \(dateFmt.string(from: start))"
    }

    private func stopRecording() {
        controller.stopRecording()
    }

    private func cancelRecording() {
        controller.cancelRecording()
    }

    private var amberGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: RecordingCompanionTokens.amber.opacity(0.0), location: 0.00),
                .init(color: RecordingCompanionTokens.amber.opacity(0.95), location: 0.10),
                .init(color: RecordingCompanionTokens.amber.opacity(0.90), location: 0.90),
                .init(color: RecordingCompanionTokens.amber.opacity(0.0), location: 1.00),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    @MainActor
    private func runSmoothing() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            let target = CGFloat(min(max(controller.audioLevel, 0), 1))
            smoothedLevel = smoothedLevel * 0.90 + target * 0.10
        }
    }
}

// MARK: - Corner cluster (light-instrument)

/// Top-right details cluster: REC dot + REC + timer. Pure marginalia —
/// rests near-invisible and sharpens on hover. Mirrors the studio's
/// `DiscDetails` helper.
private struct DiscDetails: View {
    let phase: TransitionPhase
    let timeString: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(red: 0.753, green: 0.227, blue: 0.165))
                .frame(width: 6, height: 6)
            Text("REC")
                .font(RecordingCompanionFonts.mono(size: 9))
                .tracking(2.2)
                .foregroundColor(RecordingCompanionTokens.ink)
            Text("·")
                .font(RecordingCompanionFonts.mono(size: 9))
                .foregroundColor(RecordingCompanionTokens.inkFainter)
            Text(timeString)
                .font(RecordingCompanionFonts.mono(size: 9))
                .tracking(1.6)
                .monospacedDigit()
                .foregroundColor(RecordingCompanionTokens.ink)
        }
        .allowsHitTesting(false)
    }
}

/// Bottom-left status caption. Mirrors the top-right details cluster's
/// compact dot/text rhythm so the card has matching top and bottom chrome.
private struct DiscCaption: View {
    let text: String
    let active: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(active ? RecordingCompanionTokens.amber : RecordingCompanionTokens.inkFainter)
                .frame(width: 5, height: 5)
            Text(text)
                .font(RecordingCompanionFonts.mono(size: 9))
                .tracking(2.8)
                .foregroundColor(RecordingCompanionTokens.inkFaint)
                .lineLimit(1)
        }
        .opacity(0.58)
        .allowsHitTesting(false)
    }
}

/// Cancel button — circular `×`. Mirrors the studio's `DiscClose`.
private struct DiscClose: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(hovered ? RecordingCompanionTokens.ink : RecordingCompanionTokens.inkFaint)
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .strokeBorder(
                            hovered
                                ? RecordingCompanionTokens.ink
                                : RecordingCompanionTokens.ink.opacity(0.20),
                            lineWidth: 1
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovered = $0 }
        .help("Discard recording (Esc)")
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

/// Bottom-right STOP pill — red surface with `⌘.` keybinding hint.
/// Mirrors the studio's `DiscStop`.
private struct DiscStop: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color(red: 1.0, green: 0.969, blue: 0.961))
                    .frame(width: 6, height: 6)
                Text("STOP")
                    .font(RecordingCompanionFonts.mono(size: 9))
                    .tracking(2.0)
                    .foregroundColor(Color(red: 1.0, green: 0.969, blue: 0.961))
                Text("⌘.")
                    .font(RecordingCompanionFonts.mono(size: 9))
                    .foregroundColor(Color(red: 1.0, green: 0.969, blue: 0.961).opacity(0.65))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(red: 0.753, green: 0.227, blue: 0.165))
                    .shadow(color: Color(red: 0.753, green: 0.227, blue: 0.165).opacity(0.22), radius: 6, y: 2)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    .blendMode(.plusLighter)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help("Stop recording (⌘.)")
    }
}

// MARK: - Stop button

private struct StopButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("⌘.")
                    .font(RecordingCompanionFonts.mono(size: 9))
                    .foregroundColor(RecordingCompanionTokens.inkFainter)
                Text("STOP")
                    .font(RecordingCompanionFonts.mono(size: 10))
                    .tracking(2.8)
                    .foregroundColor(
                        hovered
                            ? Color(red: 0.753, green: 0.227, blue: 0.165)
                            : RecordingCompanionTokens.inkFaint
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovered = $0 }
        .help("Stop recording (⌘.)")
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

// MARK: - Cancel button

/// Discard affordance — parity with the legacy `inlineRecordingUI` X.
/// Reads as a secondary action (text-only, fainter ink) so it never
/// competes with STOP for the primary slot, but stays close enough to
/// be discovered without hunting.
private struct CancelButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text("CANCEL")
                .font(RecordingCompanionFonts.mono(size: 10))
                .tracking(2.8)
                .foregroundColor(
                    hovered
                        ? RecordingCompanionTokens.ink
                        : RecordingCompanionTokens.inkFainter
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovered = $0 }
        .help("Discard recording")
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

// MARK: - Recording dot

private struct RecDot: View {
    var active: Bool = true

    var body: some View {
        Circle()
            .fill(Color(red: 0.753, green: 0.227, blue: 0.165))     // #C03A2A
            .opacity(active ? 1 : 0.55)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(
                        Color(red: 0.753, green: 0.227, blue: 0.165).opacity(active ? 0.25 : 0),
                        lineWidth: 2
                    )
            )
            .animation(.easeOut(duration: 0.3), value: active)
    }
}

// MARK: - Tokens

private enum RecordingCompanionTokens {
    static let ink = adaptive(
        light: RGB(0.165, 0.149, 0.125),     // #2A2620
        dark: RGB(0.914, 0.878, 0.812)       // warm phosphor
    )
    static let inkFaint = ink.opacity(0.55)
    static let inkFainter = ink.opacity(0.32)
    static let paper = adaptive(
        light: RGB(0.957, 0.945, 0.918),     // #F4F1EA
        dark: RGB(0.055, 0.058, 0.060)       // graphite glass tint
    )
    static let cream = adaptive(
        light: RGB(0.984, 0.984, 0.980),     // #FBFBFA
        dark: RGB(0.035, 0.037, 0.039)
    )
    static let amber = adaptive(
        light: RGB(0.769, 0.490, 0.110),     // #C47D1C
        dark: RGB(0.874, 0.561, 0.157)       // #DF8F28
    )
    static let amberGlow = adaptive(
        light: RGB(0.910, 0.604, 0.235),     // #E89A3C
        dark: RGB(1.000, 0.690, 0.337)       // #FFB056
    )
    static let edgeHighlight = adaptive(
        light: RGB(1.000, 1.000, 1.000),
        dark: RGB(1.000, 0.949, 0.835)
    )
    static let edgeLowlight = adaptive(
        light: RGB(0.165, 0.149, 0.125),
        dark: RGB(0.000, 0.000, 0.000)
    )
    static let pillTint = adaptive(
        light: RGB(1.000, 1.000, 1.000),
        dark: RGB(0.090, 0.087, 0.078)
    )
    static let cardShadow = adaptive(
        light: RGB(0.000, 0.000, 0.000, alpha: 0.12),
        dark: RGB(0.000, 0.000, 0.000, alpha: 0.34)
    )

    private struct RGB {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        init(_ red: Double, _ green: Double, _ blue: Double, alpha: Double = 1) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }
    }

    private static func adaptive(light: RGB, dark: RGB) -> Color {
        #if os(macOS)
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let rgb = isDark ? dark : light
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: rgb.alpha)
        })
        #else
        Color(red: light.red, green: light.green, blue: light.blue, opacity: light.alpha)
        #endif
    }
}

// MARK: - Fonts

private enum RecordingCompanionFonts {
    static func serif(size: CGFloat) -> Font {
        for name in ["Newsreader-Regular", "Newsreader"] {
            #if os(macOS)
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
            #endif
        }
        return .system(size: size, weight: .regular, design: .serif)
    }

    static func serifItalic(size: CGFloat) -> Font {
        for name in ["Newsreader-Italic", "Newsreader-RegularItalic"] {
            #if os(macOS)
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
            #endif
        }
        return Font.custom("Newsreader-Regular", size: size).italic()
    }

    static func mono(size: CGFloat) -> Font {
        for name in ["JetBrainsMono-Medium", "JetBrainsMono-Regular"] {
            #if os(macOS)
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
            #endif
        }
        return .system(size: size, weight: .medium, design: .monospaced)
    }
}

// MARK: - Ink flourish (phase-animated)

/// Mirrors the studio's `InkFlourish` SVG — multi-frequency sine sum
/// tapered at both ends with sin(π·t). Phase advances over time so the
/// wave flows. Amplitude is a fraction of half-height, modulated by
/// the caller (typically smoothed audio level).
struct InkFlourishShape: Shape {
    var amplitude: CGFloat = 0.45
    var phase: CGFloat = 0
    var samples: Int = 280

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(amplitude, phase) }
        set {
            amplitude = newValue.first
            phase = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = rect.midY
        let halfH = rect.height / 2
        let amp = halfH * amplitude

        for i in 0...samples {
            let t = CGFloat(i) / CGFloat(samples)
            let x = t * rect.width
            let fade = sin(.pi * t)
            let yOffset =
                sin(CGFloat(i) * 0.18 + phase * 1.00) * (amp * 0.46) +
                sin(CGFloat(i) * 0.07 + 1.2 + phase * 0.72) * (amp * 0.28) +
                sin(CGFloat(i) * 0.42 + 0.5 + phase * 1.35) * (amp * 0.18) +
                sin(CGFloat(i) * 0.91 + 0.3 + phase * 0.55) * (amp * 0.08)
            let y = mid + fade * yOffset

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}
