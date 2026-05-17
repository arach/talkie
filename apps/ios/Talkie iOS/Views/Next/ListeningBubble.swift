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

            Text("Hold · Listening")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(theme.currentTheme.chrome.accent)

            // Placeholder snippet — M2 swaps for live transcription.
            Text("\u{201C}tighten the second paragraph\u{2026}\u{201D}")
                .font(.system(size: 13))
                .italic()
                .foregroundStyle(theme.colors.textPrimary.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.colors.cardBackground.opacity(0.88))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(theme.currentTheme.chrome.accentStrong, lineWidth: 0.5)
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
