//
//  RecordingHUDView.swift
//  Talkie
//
//  Proximity-aware recording overlay. Big frosted-glass pill anchored
//  in the upper-middle of the canvas while recording. At rest only the
//  wave (audio-reactive) shows — controls and chrome bloom in as the
//  cursor approaches the HUD.
//
//  Studio source of truth:
//    design/studio/components/studies/RecordingHUD.tsx
//
//  Three layers respond to cursor proximity:
//
//    far    →  wave on a frosted backdrop, nothing else
//    medium →  border + shadow fade in, REC + timer pill emerges
//    near   →  channel + sample-rate pill, level meter, stop button,
//              brass glow ring on stop, bezel highlight
//
//  Proximity is computed from the local mouse monitor (NSEvent
//  .mouseMoved). HUD bounds in SwiftUI .global coordinates are tracked
//  via a PreferenceKey; cursor distance to the HUD's edge feeds the
//  ramp.
//

import SwiftUI
import TalkieKit
import AppKit

// MARK: - View

struct RecordingHUDView: View {
    private var controller: MemoRecordingController { MemoRecordingController.shared }

    // Proximity 0..1. 0 = cursor far / off-window. 1 = cursor inside HUD.
    @State private var proximity: CGFloat = 0
    @State private var monitor: Any?
    @State private var hudFrame: CGRect = .zero

    // Smoothed audio amplitude (0..1). Matches the smoothing pattern
    // used in WaveOnlyContent.runSmoothing.
    @State private var amplitude: CGFloat = 0.30

    // MARK: Layout constants

    private let hudWidth: CGFloat = 760
    private let hudHeight: CGFloat = 124
    private let buttonSize: CGFloat = 60
    private let proximityRadius: CGFloat = 460

    // MARK: Body

    var body: some View {
        ZStack {
            surface
            wave
            recPill
            channelPill
            levelPill
            stopButton
            bezelOverlay
        }
        .frame(width: hudWidth, height: hudHeight)
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: HUDFrameKey.self, value: geo.frame(in: .global))
            }
        )
        .onPreferenceChange(HUDFrameKey.self) { hudFrame = $0 }
        .onAppear {
            startMouseTracking()
        }
        .onDisappear {
            stopMouseTracking()
        }
        .task { await runAmplitudeSmoothing() }
    }

    // MARK: Proximity ramps

    private var waveOpacity: Double { 0.55 + 0.45 * Double(proximity) }
    private var stopOpacity: Double { ramp(proximity, 0.20, 0.55) }
    private var borderOp: Double { ramp(proximity, 0.15, 0.55) }
    private var shadowOp: Double { ramp(proximity, 0.30, 0.70) }
    private var recPillOp: Double { ramp(proximity, 0.20, 0.55) }
    private var channelPillOp: Double { ramp(proximity, 0.35, 0.70) }
    private var levelPillOp: Double { ramp(proximity, 0.55, 0.85) }
    private var bezelOp: Double { ramp(proximity, 0.45, 0.85) }

    // MARK: Pieces

    /// Frosted backdrop. `.ultraThinMaterial` provides the always-on
    /// blur (so whatever sits behind the HUD reads as soft tone, not
    /// legible content). Border + shadow ramp with proximity so the
    /// panel gains weight as the user reaches for it.
    private var surface: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        HUDTokens.edgeStrong.opacity(borderOp),
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: HUDTokens.shadow.opacity(0.22 * shadowOp),
                radius: 22,
                x: 0,
                y: 18
            )
    }

    private var wave: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = CGFloat(t) * 1.5
            ZStack {
                // Phosphor halo
                InkFlourishShape(amplitude: amplitude, phase: phase)
                    .stroke(HUDTokens.amber.opacity(0.22 * waveOpacity), lineWidth: 5)
                    .blur(radius: 4)
                // Trace
                InkFlourishShape(amplitude: amplitude, phase: phase)
                    .stroke(HUDTokens.amber.opacity(waveOpacity), lineWidth: 1.8)
            }
        }
        .frame(width: hudWidth - 110 - buttonSize, height: hudHeight - 32)
        .padding(.leading, 28)
        .padding(.trailing, buttonSize + 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }

    private var recPill: some View {
        FloatingPill {
            HStack(spacing: 6) {
                Circle()
                    .fill(HUDTokens.rec)
                    .frame(width: 6, height: 6)
                    .shadow(color: HUDTokens.rec.opacity(0.6), radius: 4)
                Text("REC").foregroundColor(HUDTokens.rec)
                Text("·").foregroundColor(HUDTokens.edgeStrong)
                Text(formattedElapsed())
                    .foregroundColor(HUDTokens.ink)
                    .monospacedDigit()
            }
        }
        .opacity(recPillOp)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .offset(x: 22, y: -14)
        .allowsHitTesting(false)
    }

    private var channelPill: some View {
        FloatingPill {
            HStack(spacing: 6) {
                Text("CH-01").foregroundColor(HUDTokens.inkFaint)
                Text("·").foregroundColor(HUDTokens.edgeStrong)
                Text("48 kHz").foregroundColor(HUDTokens.inkFaint)
            }
        }
        .opacity(channelPillOp)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .offset(x: -(buttonSize + 24), y: -14)
        .allowsHitTesting(false)
    }

    private var levelPill: some View {
        FloatingPill {
            Text("L · \(audioLevelLabel())").foregroundColor(HUDTokens.inkFaint)
        }
        .opacity(levelPillOp)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .offset(x: 22, y: 14)
        .allowsHitTesting(false)
    }

    private var stopButton: some View {
        Button(action: stopRecording) {
            ZStack {
                Circle()
                    .strokeBorder(HUDTokens.amber, lineWidth: 2)
                    .background(
                        Circle()
                            .stroke(HUDTokens.amberRing, lineWidth: 4)
                            .opacity(0.45)
                    )
                RoundedRectangle(cornerRadius: 3)
                    .fill(HUDTokens.amber)
                    .frame(width: 18, height: 18)
            }
            .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(.plain)
        .opacity(stopOpacity)
        .allowsHitTesting(stopOpacity > 0.4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.trailing, 14)
    }

    private var bezelOverlay: some View {
        RoundedRectangle(cornerRadius: 27.5, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.55),
                        Color.clear,
                        Color.clear,
                        Color.black.opacity(0.07)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
            .padding(0.5)
            .opacity(bezelOp)
            .allowsHitTesting(false)
    }

    // MARK: - Helpers

    private func formattedElapsed() -> String {
        let total = max(0, Int(controller.elapsedTime))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func audioLevelLabel() -> String {
        let level = max(0, min(1, Double(controller.audioLevel)))
        // Map 0..1 to dB-ish (-60..0). Quick approximation, no real RMS.
        let db = level > 0.001 ? Int(20 * log10(level)) : -60
        return "\(db) dB"
    }

    private func stopRecording() {
        controller.stopRecording()
    }

    private func ramp(_ p: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> Double {
        Double(max(0, min(1, (p - lo) / (hi - lo))))
    }

    // MARK: - Mouse tracking

    private func startMouseTracking() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            updateProximity(from: event)
            return event
        }
    }

    private func stopMouseTracking() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    /// Convert the AppKit window-space cursor into SwiftUI .global
    /// coordinates (top-left origin), then measure edge distance to
    /// `hudFrame` and ramp proximity 0..1.
    private func updateProximity(from event: NSEvent) {
        guard let window = event.window ?? NSApp.keyWindow else { return }
        guard let contentView = window.contentView else { return }
        let winH = contentView.frame.height
        let cursorX = event.locationInWindow.x
        let cursorY = winH - event.locationInWindow.y

        let dx = max(0,
                     hudFrame.minX - cursorX,
                     cursorX - hudFrame.maxX)
        let dy = max(0,
                     hudFrame.minY - cursorY,
                     cursorY - hudFrame.maxY)
        let dist = hypot(dx, dy)
        let next = max(0, min(1, 1 - dist / proximityRadius))
        // Lightweight smoothing so the ramp never jitters under fast moves.
        proximity = proximity * 0.40 + next * 0.60
    }

    // MARK: - Amplitude smoothing

    /// Same exponential smoothing as the WaveOnlyContent variant. Only
    /// writes during .recording (and decays during .stopping).
    private func runAmplitudeSmoothing() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            let state = controller.state
            if state.isRecording {
                let target = CGFloat(min(max(controller.audioLevel, 0), 1))
                let desired = pow(max(target, 0), 0.55)
                amplitude = amplitude * 0.90 + desired * 0.10
            }
        }
    }
}

// MARK: - Frame preference key

private struct HUDFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// MARK: - Floating pill

private struct FloatingPill<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .font(HUDFonts.mono(size: 9))
            .tracking(1.4)
            .textCase(.uppercase)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(HUDTokens.surface)
            )
            .overlay(
                Capsule().stroke(HUDTokens.edgeStrong, lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1)
            .fixedSize()
    }
}

// MARK: - Tokens

private enum HUDTokens {
    static let ink         = Color(red: 0.165, green: 0.149, blue: 0.125)
    static let inkFaint    = Color(red: 0.165, green: 0.149, blue: 0.125).opacity(0.55)
    static let edgeStrong  = Color(red: 0.165, green: 0.149, blue: 0.125).opacity(0.18)
    static let amber       = Color(red: 0.769, green: 0.490, blue: 0.110)  // #C47D1C
    static let amberRing   = Color(red: 0.910, green: 0.604, blue: 0.235)  // #E89A3C
    static let rec         = Color(red: 0.769, green: 0.227, blue: 0.110)  // #C43A1C
    static let surface     = Color(red: 0.984, green: 0.984, blue: 0.980)  // #FBFBFA
    static let shadow      = Color(red: 0.08, green: 0.094, blue: 0.110)
}

// MARK: - Fonts

private enum HUDFonts {
    static func mono(size: CGFloat) -> Font {
        for name in ["JetBrainsMono-SemiBold", "JetBrainsMono-Medium"] {
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
        }
        return .system(size: size, weight: .semibold, design: .monospaced)
    }
}
