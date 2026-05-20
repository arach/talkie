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

    var label: String {
        switch self {
        case .wave: return "Wave"
        case .frontispiece: return "Frontispiece"
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

    private var isVisible: Bool {
        controller.state.isRecording || controller.state.isPreparing
    }

    var body: some View {
        Group {
            if isVisible {
                content
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
            }
        }
        .animation(.easeInOut(duration: 0.28), value: isVisible)
    }

    @ViewBuilder
    private var content: some View {
        switch variant {
        case .wave:
            WaveOnlyContent(controller: controller)
        case .frontispiece:
            FrontispieceContent(controller: controller)
        }
    }
}

// MARK: - Wave-only variant

private struct WaveOnlyContent: View {
    let controller: MemoRecordingController

    // Smoothed audio level. Updated by a low-rate task; the wave reads
    // this so amplitude breathes instead of snapping with each frame.
    @State private var smoothedLevel: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(RecordingCompanionTokens.ink.opacity(0.16))
                .frame(height: 0.5)

            VStack(spacing: 28) {
                eyebrow
                animatedWave
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

    private var animatedWave: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // Constant phase speed — wave traverses at a steady rate,
            // so motion reads as travel, not erratic excitement.
            let phaseSpeed: CGFloat = 1.5
            // Amplitude is the only audio-reactive parameter, and it
            // reads off the smoothed level so voice modulation breathes.
            let amp: CGFloat = 0.30 + smoothedLevel * 0.50

            InkFlourishShape(
                amplitude: amp,
                phase: CGFloat(t) * phaseSpeed
            )
            .stroke(amberGradient, lineWidth: 2.4)
            .shadow(color: RecordingCompanionTokens.amberGlow.opacity(0.34), radius: 3)
            .frame(width: 880, height: 196)
        }
        .allowsHitTesting(false)
    }

    private var captionRow: some View {
        HStack {
            Text("\(timeString) · RECORDING MEMO")
                .font(RecordingCompanionFonts.mono(size: 10))
                .tracking(2.8)
                .foregroundColor(RecordingCompanionTokens.inkFaint)
                .allowsHitTesting(false)
            Spacer()
            StopButton(action: stopRecording)
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

    // MARK: - Smoothing

    @MainActor
    private func runSmoothing() async {
        // Exponential moving average. α=0.90 at ~60Hz gives a ~150ms
        // time constant — fast enough to feel responsive, slow enough
        // to read as breathing, not jumping.
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            let target = CGFloat(min(max(controller.audioLevel, 0), 1))
            smoothedLevel = smoothedLevel * 0.90 + target * 0.10
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
    var body: some View {
        Circle()
            .fill(Color(red: 0.753, green: 0.227, blue: 0.165))     // #C03A2A
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(Color(red: 0.753, green: 0.227, blue: 0.165).opacity(0.25), lineWidth: 2)
            )
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
