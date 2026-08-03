//
//  PresetPickerView.swift
//  TalkieWatch
//
//  Capture surface — idle. A quiet Talkie wordmark, one wide signal key, and
//  one subordinate AI route. The primary action reads as a control rather than
//  a miniature watch face.
//

import SwiftUI
import WatchKit

struct PresetPickerView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager
    @Environment(\.watchThemeName) private var themeName
    @Binding var selectedPreset: WatchPreset?
    @Binding var isRecording: Bool
    var onOpenAsks: () -> Void = {}

    var body: some View {
        ZStack {
            TalkieCaptureBackground()

            GeometryReader { proxy in
                let compact = proxy.size.height < 190

                VStack(spacing: 0) {
                    Text("talkie")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(themeName.captureStyle.material.ink.opacity(0.90))

                    // The slot is always reserved, even when there is nothing to
                    // say. An ask starting or finishing must not shove the record
                    // key down the face — the same reason recording states swap
                    // into a fixed-size puck instead of resizing the button.
                    AskStrip(onOpen: onOpenAsks)
                        .padding(.top, compact ? 2 : 3)

                    Spacer()
                        .frame(height: compact ? 9 : 12)

                    RecordButton(kind: .start) { startCapture(forceAI: false) }

                    Spacer()
                        .frame(height: compact ? 10 : 14)

                    AIPill { startCapture(forceAI: true) }
                }
                .padding(.top, compact ? 2 : 5)
                .padding(.bottom, compact ? 3 : 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private func startCapture(forceAI: Bool) {
        WKInterfaceDevice.current().play(.click)
        selectedPreset = forceAI ? .ai : .go
        isRecording = true
    }
}

// MARK: - Talkie capture face

/// A restrained, brand-first capture composition. The wordmark establishes
/// identity; one porcelain key carries the primary action; an optional route
/// stays visibly subordinate. No decorative telemetry appears at rest.
struct TalkieCaptureLayout<HeaderAccessory: View, Primary: View, Caption: View, Secondary: View>: View {
    @Environment(\.watchThemeName) private var themeName
    private let headerAccessory: HeaderAccessory
    private let primary: Primary
    private let caption: Caption
    private let secondary: Secondary

    init(
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder caption: () -> Caption,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.headerAccessory = headerAccessory()
        self.primary = primary()
        self.caption = caption()
        self.secondary = secondary()
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                let capture = themeName.captureStyle

                Text("talkie")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(capture.material.ink.opacity(0.90))
                    .position(x: width * 0.50, y: height * 0.12)

                headerAccessory
                    .frame(width: width * 0.72, height: 24)
                    .position(x: width * 0.50, y: height * 0.25)

                primary
                    .position(x: width * 0.50, y: height * 0.51)

                caption
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(capture.material.inkFaint)
                    .lineLimit(1)
                    .position(x: width * 0.50, y: height * 0.75)

                secondary
                    .position(x: width * 0.50, y: height * 0.86)
            }
        }
    }
}

/// A sober light-mineral or black-ceramic field with one directional light
/// source. It remains quiet enough for the key and system time to lead.
struct TalkieCaptureBackground: View {
    @Environment(\.watchThemeName) private var themeName

    var body: some View {
        let capture = themeName.captureStyle
        let material = capture.material
        ZStack {
            material.field

            LinearGradient(
                colors: [
                    material.fieldLift.opacity(0.72),
                    material.field.opacity(0.90),
                    material.fieldShade
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.white.opacity(0.10), .clear],
                center: UnitPoint(x: 0.30, y: 0.12),
                startRadius: 0,
                endRadius: 128
            )

            RadialGradient(
                colors: [capture.atmosphere, .clear],
                center: UnitPoint(x: 0.76, y: 0.70),
                startRadius: 0,
                endRadius: 150
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Shared scope chrome

/// Instrument header — a compact, truthful two-column readout. The timer and
/// phone link state sit below the system clock without repeating the product
/// wordmark or competing with watchOS toolbar chrome.
struct InstrumentHeader: View {
    let elapsed: TimeInterval
    let isLive: Bool

    @EnvironmentObject var sessionManager: WatchSessionManager

    var body: some View {
        let chrome = WatchTheme.current
        HStack(spacing: 6) {
            Text(formatElapsed(elapsed))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(isLive ? chrome.panelInk : chrome.panelInkFaint)
                .frame(minWidth: 36, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Circle()
                    .fill(sessionManager.isReachable ? Color.green : chrome.panelInkFaint)
                    .frame(width: 5, height: 5)
                    .shadow(
                        color: sessionManager.isReachable ? Color.green.opacity(0.65) : .clear,
                        radius: 2
                    )

                Text(sessionManager.isReachable ? "LINK" : "WAIT")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(chrome.panelInkFaint)
            }
            .frame(minWidth: 40, alignment: .trailing)
        }
    }

    private func formatElapsed(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let secondsText = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        return "\(minutes):\(secondsText)"
    }
}

/// Recessed Watch instrument surface shared by capture and Codex. Its depth
/// comes from a restrained surface ladder and one border, not ornamental
/// brackets or simulated hardware texture.
struct WatchInstrumentPanel<Content: View>: View {
    var annotation: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        let chrome = WatchTheme.current
        ZStack {
            RoundedRectangle(cornerRadius: chrome.chromeCorner + 3, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [chrome.panelAlt, chrome.panel],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: chrome.chromeCorner + 3, style: .continuous)
                        .stroke(chrome.panelEdge, lineWidth: chrome.hairlineWidth)
                )

            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            if let annotation {
                PanelAnnotation(text: annotation)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// Quiet panel label for contexts that need one; omitted on capture where the
/// ready state already names the action.
private struct PanelAnnotation: View {
    let text: String

    var body: some View {
        let chrome = WatchTheme.current
        Text(text.uppercased())
            .font(.system(size: 7, weight: .medium, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(chrome.panelInkFaint.opacity(0.72))
            .padding(.leading, 10)
            .padding(.top, 7)
    }
}

enum ScopeTreatment {
    /// Smooth oscilloscope sine trace — calm at rest, blooms with energy.
    case line
    /// Scrolling vertical bars — mirrors the macOS LiveWaveformBars.
    case bars
}

/// Two-mode waveform. Default `.line` reads like a calm scope trace and
/// pairs well with the bigger slot; `.bars` is the macOS-style scrolling
/// bar visualizer kept available so we can A/B without losing it.
struct ScopeWaveform: View {
    let audioLevel: Float
    let isLive: Bool
    var treatment: ScopeTreatment = .line

    var body: some View {
        switch treatment {
        case .line:
            ScopeLineTrace(audioLevel: audioLevel, isLive: isLive)
        case .bars:
            ScopeBars(audioLevel: audioLevel, isLive: isLive)
        }
    }
}

/// Sine-modulated continuous trace. At rest holds a low-amplitude calm
/// line; while live the amplitude grows with audio level and the line
/// gets a soft glow underneath for the lit-chrome instrument feel.
struct ScopeLineTrace: View {
    let audioLevel: Float
    let isLive: Bool

    var body: some View {
        let chrome = WatchTheme.current
        TimelineView(.animation(minimumInterval: 0.040, paused: !isLive)) { timeline in
            Canvas { ctx, size in
                let centerY = size.height / 2
                let t = timeline.date.timeIntervalSinceReferenceDate
                let raw = max(0.05, CGFloat(audioLevel))
                let amplitude = centerY * (isLive ? (0.18 + raw * 0.78) : 0.18)

                // Faint scope ticks: short vertical marks at quarters.
                for col in 1..<4 {
                    var tick = Path()
                    let x = size.width * CGFloat(col) / 4
                    tick.move(to: CGPoint(x: x, y: centerY - 5))
                    tick.addLine(to: CGPoint(x: x, y: centerY + 5))
                    ctx.stroke(tick, with: .color(chrome.edgeSubtle), lineWidth: 0.4)
                }

                // The trace.
                var trace = Path()
                let samples = 96
                for i in 0..<samples {
                    let progress = CGFloat(i) / CGFloat(samples - 1)
                    let x = progress * size.width

                    let phase = (isLive ? t * 5 : t * 1.5) + Double(progress) * 7.5
                    let primary = sin(phase) * Double(amplitude)
                    let harmonic = sin(phase * 2.7) * Double(amplitude) * 0.30
                    let y = centerY + CGFloat(primary + harmonic)

                    if i == 0 {
                        trace.move(to: CGPoint(x: x, y: y))
                    } else {
                        trace.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                ctx.stroke(trace, with: .color(chrome.accent), lineWidth: 1.4)

                // Glow under the trace.
                ctx.addFilter(.blur(radius: 2.5))
                ctx.stroke(trace, with: .color(chrome.accent.opacity(0.32)), lineWidth: 2.2)
            }
        }
    }
}

/// Scrolling vertical bars — mirrors the macOS LiveWaveformBars. At rest
/// (`isLive == false`) we hold a quiet 0.15-level baseline; while live
/// the bars shift right-to-left and the rightmost takes the current
/// audio level, evoking a moving scope trace.
struct ScopeBars: View {
    let audioLevel: Float
    let isLive: Bool

    @State private var bars: [CGFloat] = Array(repeating: 0.15, count: 56)

    private let barWidth: CGFloat = 2
    private let gap: CGFloat = 2

    var body: some View {
        let chrome = WatchTheme.current
        GeometryReader { proxy in
            let count = max(20, Int(proxy.size.width / (barWidth + gap)))

            TimelineView(.animation(minimumInterval: 0.05, paused: !isLive)) { timeline in
                Canvas { ctx, size in
                    let totalWidth = CGFloat(count) * (barWidth + gap) - gap
                    let startX = (size.width - totalWidth) / 2
                    let maxHeight = size.height * 0.85
                    let centerY = size.height / 2

                    for i in 0..<count {
                        let x = startX + CGFloat(i) * (barWidth + gap)

                        let seed = Double(i) * 1.618
                        let variation: CGFloat = 0.65 + CGFloat(sin(seed * 3)) * 0.35
                        let level = bars[i % bars.count] * variation
                        let h = max(2, level * maxHeight)
                        let opacity = isLive ? (0.45 + Double(level) * 0.55) : 0.32

                        let rect = CGRect(
                            x: x,
                            y: centerY - h / 2,
                            width: barWidth,
                            height: h
                        )
                        ctx.fill(
                            RoundedRectangle(cornerRadius: 1).path(in: rect),
                            with: .color(chrome.accent.opacity(opacity))
                        )
                    }
                }
                .onChange(of: timeline.date) { _, _ in
                    advance(count: count)
                }
            }
        }
        .onAppear {
            bars = Array(repeating: isLive ? 0.20 : 0.15, count: bars.count)
        }
    }

    private func advance(count: Int) {
        let raw = CGFloat(audioLevel)
        let target: CGFloat = isLive ? max(0.18, pow(raw, 0.5)) : 0.15

        var next = bars
        let effective = min(count, bars.count)
        for i in 0..<(effective - 1) {
            next[i] = next[i + 1]
        }
        if effective > 0 {
            next[effective - 1] = target
        }
        bars = next
    }
}

/// Calm, deterministic instrument background. The low-contrast cobalt lift
/// provides hierarchy without procedural grain or frame-to-frame noise.
struct WatchInstrumentBackground: View {
    var body: some View {
        let chrome = WatchTheme.current
        ZStack {
            chrome.panel

            LinearGradient(
                colors: [chrome.panelAlt.opacity(0.70), chrome.panel.opacity(0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [chrome.accent.opacity(0.10), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 150
            )
        }
        .ignoresSafeArea()
    }
}

/// Primary capture action. The idle key carries Talkie's trace and an explicit
/// recording legend; semantic red appears only where recording is meant.
struct RecordButton: View {
    enum Kind { case start, stop }
    let kind: Kind
    var audioLevel: Float = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            switch kind {
            case .start:
                TalkieCaptureKey()
            case .stop:
                TalkieStopKey(audioLevel: audioLevel)
            }
        }
        .buttonStyle(TalkieRecordButtonStyle())
        .accessibilityLabel(kind == .start ? "Start recording" : "Stop and send")
    }
}

private struct TalkieRecordButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .offset(y: configuration.isPressed ? 1.5 : 0)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A wide light-mineral or black-ceramic recording key. Its horizontal
/// geometry, elevated edge, and press response keep it from reading as a
/// miniature device nested inside the Watch.
private struct TalkieCaptureKey: View {
    @Environment(\.watchThemeName) private var themeName
    private let width: CGFloat = 128
    private let height: CGFloat = 64
    private let cornerRadius: CGFloat = 18

    var body: some View {
        let capture = themeName.captureStyle
        let material = capture.material
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            material.keyTop,
                            material.keyMiddle,
                            material.keyBottom
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: material.shadow, radius: 7, y: 5)

            VStack(spacing: 4) {
                TalkieTraceReveal(color: capture.trace)
                    .frame(width: 86, height: 22)

                HStack(spacing: 5) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.92))

                    Text("REC")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .tracking(1.35)
                        .foregroundStyle(material.keyInk.opacity(0.86))
                }
            }
        }
        .frame(width: width, height: height)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// One deliberate Talkie signal: quiet lead-in, peak, trough, recovery, rest.
/// The asymmetry keeps it from reading as a generic waveform or equalizer.
private struct TalkieSignalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let middle = rect.midY
        let height = rect.height

        path.move(to: CGPoint(x: rect.minX, y: middle))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.24, y: middle))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.42, y: middle - height * 0.34),
            control1: CGPoint(x: rect.minX + rect.width * 0.33, y: middle),
            control2: CGPoint(x: rect.minX + rect.width * 0.35, y: middle - height * 0.34)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.57, y: middle + height * 0.28),
            control1: CGPoint(x: rect.minX + rect.width * 0.47, y: middle - height * 0.34),
            control2: CGPoint(x: rect.minX + rect.width * 0.51, y: middle + height * 0.28)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.70, y: middle - height * 0.13),
            control1: CGPoint(x: rect.minX + rect.width * 0.62, y: middle + height * 0.28),
            control2: CGPoint(x: rect.minX + rect.width * 0.65, y: middle - height * 0.13)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.80, y: middle),
            control1: CGPoint(x: rect.minX + rect.width * 0.74, y: middle - height * 0.13),
            control2: CGPoint(x: rect.minX + rect.width * 0.76, y: middle)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: middle))
        return path
    }
}

/// One-shot trace reveal with a brief moving highlight. Reduce Motion keeps
/// the same final state and substitutes a short opacity transition.
private struct TalkieTraceReveal: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAnimated = false
    @State private var revealProgress: CGFloat = 0
    @State private var highlightProgress: CGFloat = 0
    @State private var highlightOpacity = 0.0
    @State private var traceOpacity = 0.0

    var body: some View {
        ZStack {
            TalkieSignalLine()
                .trim(from: 0, to: revealProgress)
                .stroke(
                    color.opacity(0.82),
                    style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round)
                )
                .opacity(traceOpacity)

            TalkieSignalLine()
                .trim(
                    from: max(0, highlightProgress - 0.18),
                    to: min(1, highlightProgress)
                )
                .stroke(
                    Color.white.opacity(0.84),
                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: color.opacity(0.46), radius: 2)
                .opacity(highlightOpacity)
        }
        .onAppear(perform: animateOnce)
    }

    private func animateOnce() {
        guard !hasAnimated else { return }
        hasAnimated = true

        if reduceMotion {
            revealProgress = 1
            withAnimation(.easeOut(duration: 0.18)) {
                traceOpacity = 1
            }
            return
        }

        traceOpacity = 1
        withAnimation(.easeOut(duration: 0.72).delay(0.08)) {
            revealProgress = 1
        }
        withAnimation(.easeIn(duration: 0.12).delay(0.18)) {
            highlightOpacity = 0.72
        }
        withAnimation(.easeInOut(duration: 0.68).delay(0.18)) {
            highlightProgress = 1
        }
        withAnimation(.easeOut(duration: 0.20).delay(0.78)) {
            highlightOpacity = 0
        }
    }
}

/// The live stop action remains unmistakably semantic and intentionally does
/// not inherit the idle key's decorative material or load animation.
private struct TalkieStopKey: View {
    let audioLevel: Float

    var body: some View {
        let level = min(max(audioLevel, 0), 1)
        ZStack {
            Circle()
                .stroke(Color.red.opacity(0.24 + Double(level) * 0.48), lineWidth: 1.5)
                .frame(width: 67, height: 67)
                .scaleEffect(1 + CGFloat(level) * 0.06)

            Circle()
                .fill(Color.red)
                .frame(width: 60, height: 60)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.34), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.40), radius: 7, y: 5)

            Image(systemName: "stop.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(watchHex: "F7FAFF"))
        }
        .frame(width: 70, height: 70)
        .contentShape(Circle())
    }
}

/// Optional explicit-AI route. Its low-contrast outline keeps it subordinate
/// to capture while remaining an obvious second action.
struct AIPill: View {
    @Environment(\.watchThemeName) private var themeName
    let action: () -> Void

    var body: some View {
        let capture = themeName.captureStyle
        let material = capture.material
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .semibold))
                Text("Ask AI")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
            .foregroundStyle(material.ink.opacity(0.76))
            .frame(width: 88, height: 32)
            .background(
                Capsule(style: .continuous)
                    .fill(material.secondaryFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(material.secondaryEdge, lineWidth: 0.8)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(capture.secondaryAccentEdge, lineWidth: 0.6)
                            .padding(1)
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(width: 96, height: 44)
        .accessibilityLabel("Start AI conversation")
    }
}

#Preview {
    PresetPickerView(
        selectedPreset: .constant(nil),
        isRecording: .constant(false)
    )
    .environmentObject(WatchSessionManager.shared)
}
