//
//  RecordingCompanionSurface.swift
//  Talkie
//
//  Big-screen recording companion. Shows on the cream canvas while a
//  memo recording is active. The title-bar pill stays the always-on
//  baseline; this surface is the editorial echo of that pill across
//  the available canvas.
//
//  Studio source of truth:
//    design/studio/app/mac-recording-state/page.tsx
//
//  Two variants ship side-by-side, swappable at runtime via the
//  `recordingCompanion.variant` defaults key:
//
//    .wave         — animated amber ink flourish bracketed by hairlines
//                    and an eyebrow; constant phase speed for a
//                    "traversing" feel; amplitude smoothed with an
//                    exponential moving average so voice modulation
//                    breathes rather than jumps.
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

// MARK: - Surface

struct RecordingCompanionSurface: View {
    private var controller: MemoRecordingController { MemoRecordingController.shared }

    @AppStorage("recordingCompanion.variant")
    private var variantRaw: String = RecordingCompanionVariant.wave.rawValue

    private var variant: RecordingCompanionVariant {
        RecordingCompanionVariant(rawValue: variantRaw) ?? .wave
    }

    /// Holds the surface visible past `.complete` so the transition into
    /// the emergent transcript has room to play out before dismissal.
    @State private var holdAfterComplete: Bool = false

    private var isVisible: Bool {
        let state = controller.state
        if state.isRecording || state.isPreparing || state.isProcessing { return true }
        if case .complete = state { return holdAfterComplete }
        return false
    }

    var body: some View {
        Group {
            if isVisible {
                content
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
            }
        }
        .animation(.easeInOut(duration: 0.36), value: isVisible)
        .onChange(of: controller.state.signalToken) { _, newValue in
            handleStateChange(token: newValue)
        }
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
        } else if token != "complete" {
            // Any non-complete state (idle / recording / preparing /
            // processing / error) — drop the post-complete hold.
            holdAfterComplete = false
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

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(RecordingCompanionTokens.ink.opacity(0.16))
                .frame(height: 0.5)

            VStack(spacing: 28) {
                eyebrow
                waveAndTranscript
                captionRow
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 36)

            Rectangle()
                .fill(RecordingCompanionTokens.ink.opacity(0.16))
                .frame(height: 0.5)
        }
        .frame(maxWidth: 980)
        .task { await runSmoothing() }
        .onChange(of: controller.state.signalToken) { _, _ in
            syncPhase()
        }
        .onAppear { syncPhase() }
    }

    // MARK: - Pieces

    private var eyebrow: some View {
        HStack(spacing: 12) {
            RecDot(active: phase == .recording)
            Text(eyebrowVerb)
                .font(RecordingCompanionFonts.mono(size: 10))
                .tracking(3.6)
                .foregroundColor(RecordingCompanionTokens.inkFaint)
                .animation(.easeOut(duration: 0.24), value: eyebrowVerb)
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

    private var eyebrowVerb: String {
        switch phase {
        case .recording: return "RECORDING"
        case .stopping, .settling, .emerging: return "TRANSCRIBING"
        case .complete: return "MEMO"
        }
    }

    /// The wave and the emerging transcript share the same vertical slot,
    /// so as the wave collapses into a baseline the text appears in the
    /// same place — the wave literally becomes the writing.
    private var waveAndTranscript: some View {
        ZStack {
            animatedWave
            emergingTranscript
        }
        .frame(width: 880, height: 196)
        .allowsHitTesting(false)
    }

    private var animatedWave: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phaseSpeed: CGFloat = 1.5

            InkFlourishShape(
                amplitude: amplitude,
                phase: CGFloat(t) * phaseSpeed
            )
            .stroke(amberGradient, lineWidth: waveStroke)
            .shadow(color: RecordingCompanionTokens.amberGlow.opacity(waveGlow), radius: 3)
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
        case .recording: return 0.34
        case .stopping: return 0.20
        case .settling, .emerging, .complete: return 0.0
        }
    }

    /// Transcript text reveals along the wave's baseline via a left→right
    /// mask scale paired with a 6pt baseline rise. Mirrors the studio
    /// mock's `clip-path` + `translateY` pattern.
    private var emergingTranscript: some View {
        Text(transcript)
            .font(RecordingCompanionFonts.serif(size: 22))
            .foregroundColor(RecordingCompanionTokens.ink)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .truncationMode(.tail)
            .frame(maxWidth: 720)
            .padding(.horizontal, 16)
            .offset(y: (1 - emergeProgress) * 6)
            .opacity(emergeProgress > 0 ? Double(emergeProgress) : 0)
            .mask(
                GeometryReader { geo in
                    Rectangle()
                        .frame(
                            width: max(0, geo.size.width * emergeProgress),
                            height: geo.size.height
                        )
                }
            )
    }

    private var captionRow: some View {
        HStack {
            Text(captionText)
                .font(RecordingCompanionFonts.mono(size: 10))
                .tracking(2.8)
                .foregroundColor(RecordingCompanionTokens.inkFaint)
                .animation(.easeOut(duration: 0.24), value: captionText)
                .allowsHitTesting(false)
            Spacer()
            if phase == .recording {
                StopButton(action: stopRecording)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.24), value: phase == .recording)
    }

    private var captionText: String {
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
            withAnimation(.timingCurve(0.22, 0.61, 0.36, 1.0, duration: 1.10)) {
                emergeProgress = 1
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1100))
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
        // Exponential moving average — only writes amplitude during
        // .recording. In every other phase the explicit transitions own
        // the value, so the wave can settle / hold cleanly.
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            guard phase == .recording else { continue }
            let target = CGFloat(min(max(controller.audioLevel, 0), 1))
            // 0.30 floor + 0.50 boost = amp range 0.30 → 0.80. The
            // amplitude state holds the actual rendered value; we smooth
            // toward the target each tick.
            let desired = 0.30 + target * 0.50
            amplitude = amplitude * 0.90 + desired * 0.10
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

            HStack {
                Text("RECORDING MEMO")
                    .font(RecordingCompanionFonts.mono(size: 10))
                    .tracking(2.8)
                    .foregroundColor(RecordingCompanionTokens.inkFaint)
                    .allowsHitTesting(false)
                Spacer()
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
    static let ink         = Color(red: 0.165, green: 0.149, blue: 0.125)  // #2A2620
    static let inkFaint    = Color(red: 0.165, green: 0.149, blue: 0.125).opacity(0.55)
    static let inkFainter  = Color(red: 0.165, green: 0.149, blue: 0.125).opacity(0.32)
    static let paper       = Color(red: 0.957, green: 0.945, blue: 0.918)  // #F4F1EA
    static let cream       = Color(red: 0.984, green: 0.984, blue: 0.980)  // #FBFBFA
    static let amber       = Color(red: 0.769, green: 0.490, blue: 0.110)  // #C47D1C
    static let amberGlow   = Color(red: 0.910, green: 0.604, blue: 0.235)  // #E89A3C
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
