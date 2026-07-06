//
//  ListeningBubble.swift
//  Talkie iOS
//
//  Floats above the center Talkie pivot during the listening state.
//  Live waveform · "HOLD · LISTENING" smallcap · captured-command
//  snippet (M2 wires the real transcription; Phase 0 shows a
//  placeholder snippet).
//
//  Design ref: design/studio/app/complications/ (variant
//  voice-listening).
//

import SwiftUI

struct ListeningBubble: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 10) {
            WaveformBars(color: theme.currentTheme.chrome.accent)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text("Hold · Listening")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Text("Release to send")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(theme.colors.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 184, alignment: .leading)
        .background(
            // Theme-aware corner radius — Tactical's chromeCorner:0
            // gives sharp square edges; Lift's :8 gives soft cards.
            // Bubble corner scales above the chrome chip baseline so
            // it still reads as a floating element, not chrome.
            ZStack {
                let radius = theme.currentTheme.chrome.chromeCorner + 6
                RoundedRectangle(cornerRadius: radius)
                    .fill(theme.colors.cardBackground.opacity(0.88))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(theme.currentTheme.chrome.accentStrong, lineWidth: theme.currentTheme.chrome.hairlineWidth)
            }
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // Sits above the center pivot. Button bottom = 12, height = 56,
        // gap = 16, so bubble bottom = 12 + 56 + 16 = 84.
        .padding(.bottom, 84)
    }
}

/// Compact "SENDING…" variant shown between release-to-send and command
/// dispatch. Reuses ListeningBubble's chassis (material card, theme corner,
/// accent hairline, center anchor) so it reads as the same object
/// settling into a processing beat rather than a new element. The waveform
/// gives way to a single travelling dot — motion that means "in flight",
/// stilled under Reduce Motion.
struct ProcessingBubble: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 10) {
            SendingIndicator(color: theme.currentTheme.chrome.accent)
                .frame(width: 16, height: 16)

            Text("Sending…")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(theme.currentTheme.chrome.accent)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 184, alignment: .leading)
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
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // Same slot the ListeningBubble occupied (see its padding note).
        .padding(.bottom, 84)
    }
}

/// A single dot travelling left→right on a faint track — the mag-tape
/// "tape-head crossing" read, minus the VU bars. Cycle ~0.9s. Paused
/// (dot rests centered) when Reduce Motion is on.
private struct SendingIndicator: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: TalkieMotion.isReduced)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // Ping-pong 0→1→0 so the dot sweeps and returns without a jump.
            // Under Reduce Motion the dot rests centered instead of frozen
            // at an arbitrary sweep position.
            let phase = TalkieMotion.isReduced ? 0.5 : (sin(t * 2 * .pi / 0.9 - .pi / 2) + 1) / 2
            GeometryReader { proxy in
                let track = proxy.size.width
                let dot: CGFloat = 4
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.22))
                        .frame(height: 1.5)
                        .frame(maxHeight: .infinity, alignment: .center)
                    Circle()
                        .fill(color)
                        .frame(width: dot, height: dot)
                        .offset(x: phase * (track - dot))
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(width: 16, height: 16)
        }
    }
}

/// Four pulsing bars driven by TimelineView — staggered ease so it
/// reads as a real audio-level meter, not a marquee. Cycle ~1.2s.
private struct WaveformBars: View {
    let color: Color
    private let baseHeights: [CGFloat] = [6, 10, 8, 14]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: TalkieMotion.isReduced)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(baseHeights.indices, id: \.self) { i in
                    let phase = sin(t * 2 * .pi / 1.2 + Double(i) * 0.6)
                    let scale = 0.55 + (phase + 1) / 2 * 0.45
                    Capsule()
                        .fill(color)
                        .frame(width: 2, height: baseHeights[i] * scale)
                }
            }
            .frame(width: 16, height: 16, alignment: .center)
        }
    }
}
