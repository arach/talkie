//
//  PresetPickerView.swift
//  TalkieWatch
//
//  Capture surface — idle. Horizontal "instrument slice": a rectangular
//  scope slot framed by rectangle brackets shows a quiet waveform at
//  rest, the timer sits below in elegant monospace, and the clean round
//  record button anchors the bottom in the style used across the iOS
//  and macOS apps. "ASK AI" lives as a small explicit-AI pill — mostly
//  implicit (transcript intent extraction wins) but available when the
//  user knows the answer in advance.
//

import SwiftUI
import WatchKit

struct PresetPickerView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager
    @Binding var selectedPreset: WatchPreset?
    @Binding var isRecording: Bool

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(spacing: 6) {
                // Top region — header + scope. Right-shifted padding
                // keeps the brackets + LINK label clear of the watchOS
                // TabView indicator dots that ride the right edge.
                VStack(spacing: 6) {
                    InstrumentHeader(elapsed: 0, isLive: false)
                        .padding(.top, 32)

                    Spacer(minLength: 18)

                    BracketedScopeSlot {
                        // At rest the slot shows the brand ASCII
                        // wordmark so it reads "Talkie · ready"
                        // instead of "live recorder already going".
                        TalkieASCIILogo()
                    }
                    .frame(maxHeight: 88)
                }
                .padding(.leading, 10)
                .padding(.trailing, 18)

                Spacer(minLength: 8)

                // Bottom region — record button + pill stay centered on
                // the screen with symmetric padding so they don't drift
                // left under the asymmetric top-region inset. Generous
                // spacing between them reads as "two separate actions"
                // not "stacked twins".
                VStack(spacing: 12) {
                    RecordButton(kind: .start) { startCapture(forceAI: false) }

                    AIPill { startCapture(forceAI: true) }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
            }
            .padding(.bottom, 10)
        }
    }

    private func startCapture(forceAI: Bool) {
        WKInterfaceDevice.current().play(.click)
        selectedPreset = forceAI ? .ai : .go
        isRecording = true
    }
}

// MARK: - Shared scope chrome

/// Instrument header — three-column readout that hugs the top edge so
/// the scope slot can claim most of the screen. Left: monospaced timer
/// (counts up while live). Center: tiny `talkie` watermark — brand
/// presence without competing with the trace. Right: link status with
/// reachability dot.
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
                .foregroundColor(isLive ? chrome.panelInk : chrome.panelInkFaint)
                .frame(minWidth: 36, alignment: .leading)

            Spacer(minLength: 0)

            Text("TALKIE")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundColor(chrome.panelInkFaint)

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
                    .foregroundColor(chrome.panelInkFaint)
            }
            .frame(minWidth: 40, alignment: .trailing)
        }
    }

    private func formatElapsed(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Rectangular scope slot with corner brackets at the four edges of the
/// inner rectangle. The shape evokes an oscilloscope screen — content
/// fills the area, brackets nudge slightly outside so the trace reads
/// "inside" the instrument frame, not crowded against the brackets.
///
/// Optional `annotation` prints a small lowercase monospaced caption
/// tucked at the top-left, like an industrial panel label.
struct BracketedScopeSlot<Content: View>: View {
    var annotation: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        let chrome = WatchTheme.current
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(chrome.panelAlt.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(chrome.edgeFaint, lineWidth: chrome.hairlineWidth)
                )

            // Faint mid-line so even an empty trace reads as a scope.
            Rectangle()
                .fill(chrome.edgeFaint)
                .frame(height: 0.4)

            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            ScopeRectBrackets()
                .stroke(chrome.accent.opacity(0.78), lineWidth: chrome.hairlineWidth + 0.4)
                .padding(-5)
                .watchAccentGlow()

            if let annotation {
                BracketAnnotation(text: annotation)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .offset(x: -2, y: -8)
            }
        }
    }
}

/// Tiny industrial-style label tucked in the top-left of a bracketed
/// panel. Sits over the bracket line with a small panel-colored gap
/// behind so the bracket appears to "break" around the caption — same
/// vocabulary as engineering diagrams or schematic callouts.
struct BracketAnnotation: View {
    let text: String

    var body: some View {
        // V5 — stencil-style mark anchored INSIDE the box, top-left,
        // very faint. Reads like a painted-on equipment label, not a
        // chrome callout.
        let chrome = WatchTheme.current
        Text("[ \(text) ]")
            .font(.system(size: 7, weight: .medium, design: .monospaced))
            .tracking(0.6)
            .foregroundColor(chrome.panelInkFaint.opacity(0.75))
            .padding(.leading, 6)
            .padding(.top, 4)
    }
}

/// Rectangle-style brackets at the four corners — they're the four
/// short L-strokes that frame an instrument readout. Hugs the slot.
private struct ScopeRectBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let arm: CGFloat = 6
        // top-leading
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))
        // top-trailing
        p.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))
        // bottom-trailing
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
        // bottom-leading
        p.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))
        return p
    }
}

/// Block-style ASCII wordmark — mirror of the macOS Terminal Setup
/// boot logo so the watch reads as part of the same console family.
/// Sized down (6.5pt monospaced) to fit the 42mm scope slot; uses
/// theme accent + faint glow so it lights up like an instrument
/// readout rather than printing flat text.
struct TalkieASCIILogo: View {
    private static let lines: String = """
████████╗ █████╗ ██╗     ██╗  ██╗██╗███████╗
╚══██╔══╝██╔══██╗██║     ██║ ██╔╝██║██╔════╝
   ██║   ███████║██║     █████╔╝ ██║█████╗
   ██║   ██╔══██║██║     ██╔═██╗ ██║██╔══╝
   ██║   ██║  ██║███████╗██║  ██╗██║███████╗
   ╚═╝   ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝╚══════╝
"""

    var body: some View {
        let chrome = WatchTheme.current
        Text(Self.lines)
            .font(.system(size: 6.5, weight: .bold, design: .monospaced))
            .lineSpacing(0)
            .foregroundColor(chrome.accent)
            .watchAccentGlow()
            .minimumScaleFactor(0.55)
            .lineLimit(6)
            .fixedSize(horizontal: false, vertical: true)
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

/// Subtle paper-grain background. Quiet enough that it reads as texture
/// not noise — gives the instrument panel a physical surface to sit on.
struct PaperBackground: View {
    var body: some View {
        let chrome = WatchTheme.current
        ZStack {
            chrome.panel
            Canvas { ctx, size in
                for _ in 0..<140 {
                    let x = CGFloat.random(in: 0...size.width)
                    let y = CGFloat.random(in: 0...size.height)
                    let r = CGFloat.random(in: 0.3...0.7)
                    let opacity = Double.random(in: 0.02...0.07)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                        with: .color(chrome.panelInk.opacity(opacity))
                    )
                }
            }
            .blendMode(.overlay)
        }
        .ignoresSafeArea()
    }
}

/// Variant B — inline pill: red LED + `REC` / `STOP` label live inside
/// the same bracketed pill. No floating label below; the action and
/// its identity read as one console toggle.
struct RecordButton: View {
    enum Kind { case start, stop }
    let kind: Kind
    let action: () -> Void

    var body: some View {
        let chrome = WatchTheme.current
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.red)
                    .frame(width: 84, height: 36)
                    .blur(radius: 10)
                    .opacity(kind == .stop ? 0.42 : 0.48)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(chrome.panelAlt)
                    .frame(width: 86, height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(chrome.edgeFaint, lineWidth: chrome.hairlineWidth)
                    )

                HStack(spacing: 6) {
                    switch kind {
                    case .start:
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                            .shadow(color: Color.red.opacity(0.85), radius: 3)
                    case .stop:
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                            .shadow(color: Color.red.opacity(0.85), radius: 3)
                    }

                    Text(kind == .start ? "REC" : "STOP")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundColor(chrome.panelInk)
                }

                ScopeRectBrackets()
                    .stroke(chrome.accent.opacity(0.78), lineWidth: chrome.hairlineWidth + 0.4)
                    .frame(width: 92, height: 42)
                    .watchAccentGlow()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind == .start ? "Capture" : "Stop and send")
    }
}

/// Small explicit-AI pill below the record button. Most captures
/// auto-route via transcript intent extraction; this pill is for when
/// the user knows up-front they want an AI conversation.
struct AIPill: View {
    let action: () -> Void

    var body: some View {
        let chrome = WatchTheme.current
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(chrome.accent)
                Text("ASK AI")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.3)
                    .foregroundColor(chrome.panelInk)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .stroke(chrome.accent.opacity(0.5), lineWidth: chrome.hairlineWidth + 0.25)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Force AI conversation")
    }
}

#Preview {
    PresetPickerView(
        selectedPreset: .constant(nil),
        isRecording: .constant(false)
    )
    .environmentObject(WatchSessionManager.shared)
}
