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
        // 16pt bottom inset puts this 48pt button's vertical center at
        // ~40pt above the bottom edge — same Y as the LiquidGlassTray
        // center and the bottom-right Keyboard CornerSlot. The three
        // read as one horizontal chrome band, not a staircase.
        .padding(.bottom, 16)
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
        // Resting uses a small static drop-shadow; expanded + listening
        // scale directly from theme.chrome.glowRadius with NO floor —
        // Tactical's glowRadius:1 → matte 2pt halo; Ghost's :7 → diffuse
        // 14pt halo; Scope's :2 → soft 4pt. Each theme's character shows.
        let glow = theme.currentTheme.chrome.glowRadius
        switch chrome.state {
        case .resting:   return 4
        case .expanded:  return glow * 2
        case .listening: return glow * 3
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

/// Voice-command glyph — bracket-wave with center dot. Uses SF
/// Symbol `dot.radiowaves.left.and.right` which renders the exact
/// "((·))" shape we want, scales cleanly across button sizes, and
/// inherits the foreground color from the parent.
private struct VoiceCmdGlyph: View {
    var body: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: 18, weight: .medium))
    }
}
