//
//  ListeningBubble.swift
//  Talkie iOS
//
//  Floats above the voice button during the listening state.
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
        .frame(minWidth: 168, alignment: .leading)
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
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        // Sits above the voice button. Button bottom = 22, height = 48,
        // gap = 14, so bubble bottom = 22 + 48 + 14 = 84.
        .padding(.bottom, 84)
    }
}

/// Four pulsing bars driven by TimelineView — staggered ease so it
/// reads as a real audio-level meter, not a marquee. Cycle ~1.2s.
private struct WaveformBars: View {
    let color: Color
    private let baseHeights: [CGFloat] = [6, 10, 8, 14]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
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
