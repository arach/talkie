//
//  VoicePivotButton.swift
//  Talkie iOS
//
//  Bottom-left ambient button. Three visual states tied to
//  ShellChrome. Tap toggles resting ↔ expanded; long-press from
//  expanded enters listening (walkie-talkie); release returns.
//  Design ref: design/studio/app/complications/ (variants
//  voice-resting / voice-expanded / voice-listening).
//

import SwiftUI

struct VoicePivotButton: View {
    @EnvironmentObject private var chrome: ShellChrome
    @ObservedObject private var theme = ThemeManager.shared

    /// 350ms matches iOS context-menu feel — long enough that a
    /// slow tap doesn't fire it, short enough to feel responsive.
    private let longPressThreshold: Double = 0.35

    var body: some View {
        Button(action: { chrome.tapVoiceButton() }) {
            ZStack {
                Circle()
                    .fill(buttonFill)
                    .overlay(
                        Circle().strokeBorder(buttonBorder, lineWidth: buttonBorderWidth)
                    )
                    // Brass halo ring — expanded + listening only.
                    .overlay(
                        Circle()
                            .strokeBorder(theme.currentTheme.chrome.accentStrong, lineWidth: 3)
                            .blur(radius: 0.5)
                            .opacity(chrome.state != .resting ? 1 : 0)
                            .scaleEffect(chrome.state != .resting ? 1.18 : 1.0)
                            .animation(.easeOut(duration: 0.25), value: chrome.state)
                    )
                    .shadow(
                        color: shadowColor,
                        radius: shadowRadius,
                        x: 0, y: 2
                    )

                VoiceCmdGlyph()
                    .foregroundStyle(glyphColor)
            }
            .frame(width: 48, height: 48)
            .scaleEffect(chrome.state == .listening ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.18), value: chrome.state)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        // Combined long-press + release detection. The standard
        // SwiftUI pattern: LongPressGesture chained before a
        // DragGesture sentinel so we get both the press-began and
        // press-ended callbacks.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: longPressThreshold)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    if case .second(true, _) = value {
                        chrome.longPressBegan()
                    }
                }
                .onEnded { _ in
                    chrome.longPressEnded()
                }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.leading, 20)
        .padding(.bottom, 22)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Tap to summon controls. Long-press to talk.")
    }

    // MARK: - State-derived styling

    private var buttonFill: Color {
        chrome.state == .listening
            ? theme.currentTheme.chrome.accent
            : theme.colors.cardBackground
    }

    private var buttonBorder: Color {
        switch chrome.state {
        case .resting:   return theme.currentTheme.chrome.edgeFaint
        case .expanded:  return theme.currentTheme.chrome.accentStrong
        case .listening: return theme.currentTheme.chrome.accentStrong
        }
    }

    private var buttonBorderWidth: CGFloat {
        chrome.state == .resting ? 0.5 : 1.0
    }

    private var glyphColor: Color {
        switch chrome.state {
        case .resting:   return theme.colors.textSecondary
        case .expanded:  return theme.currentTheme.chrome.accent
        case .listening: return theme.colors.cardBackground
        }
    }

    private var shadowColor: Color {
        switch chrome.state {
        case .resting:   return Color.black.opacity(0.10)
        case .expanded:  return theme.currentTheme.chrome.accentGlow
        case .listening: return theme.currentTheme.chrome.accentGlow
        }
    }

    private var shadowRadius: CGFloat {
        switch chrome.state {
        case .resting:   return 4
        case .expanded:  return 8
        case .listening: return 14
        }
    }

    private var accessibilityLabel: String {
        switch chrome.state {
        case .resting:   return "Summon Talkie controls"
        case .expanded:  return "Hold to talk"
        case .listening: return "Listening — release to send"
        }
    }
}

/// Voice-command bracket glyph — matches the studio's VoiceCmdGlyph.
/// Two outer arcs, two inner arcs, center dot. Rendered via Canvas
/// for crisp scaling at any size.
private struct VoiceCmdGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 16
            let cx = size.width / 2
            let cy = size.height / 2
            let lineWidth: CGFloat = 1.1 * s

            func arc(centerX: CGFloat, radius: CGFloat, start: Double, end: Double, clockwise: Bool) -> Path {
                var p = Path()
                p.addArc(
                    center: CGPoint(x: centerX, y: cy),
                    radius: radius,
                    startAngle: .degrees(start),
                    endAngle: .degrees(end),
                    clockwise: clockwise
                )
                return p
            }

            // Outer brackets — wider arcs framing the dot.
            ctx.stroke(
                arc(centerX: cx - 4 * s, radius: 5 * s, start: 135, end: -135, clockwise: false),
                with: .foreground,
                lineWidth: lineWidth
            )
            ctx.stroke(
                arc(centerX: cx + 4 * s, radius: 5 * s, start: 45, end: -45, clockwise: true),
                with: .foreground,
                lineWidth: lineWidth
            )
            // Inner brackets — closer to the dot.
            ctx.stroke(
                arc(centerX: cx - 2 * s, radius: 2.5 * s, start: 135, end: -135, clockwise: false),
                with: .foreground,
                lineWidth: lineWidth
            )
            ctx.stroke(
                arc(centerX: cx + 2 * s, radius: 2.5 * s, start: 45, end: -45, clockwise: true),
                with: .foreground,
                lineWidth: lineWidth
            )
            // Center dot.
            let dot = Path(ellipseIn: CGRect(
                x: cx - 1.3 * s, y: cy - 1.3 * s,
                width: 2.6 * s, height: 2.6 * s
            ))
            ctx.fill(dot, with: .foreground)
        }
        .frame(width: 16, height: 16)
    }
}
