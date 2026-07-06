//
//  VoicePivotButton.swift
//  Talkie iOS
//
//  Bottom-center ambient Talkie pivot. At rest it is the Talkie T
//  summon control; after the menu unfolds it turns into the mic.
//  Tap summons from resting, tap records from expanded, long-press
//  from expanded enters listening (walkie-talkie); release returns.
//  Design ref: design/studio/app/complications/ (variants
//  voice-resting / voice-expanded / voice-listening).
//

import SwiftUI

struct VoicePivotButton: View {
    @EnvironmentObject private var chrome: ShellChrome
    @ObservedObject private var theme = ThemeManager.shared

    /// 350ms matches iOS context-menu feel - long enough that a
    /// slow tap doesn't fire it, short enough to feel responsive.
    private let longPressThreshold: Double = 0.35

    var body: some View {
        Button(action: handleTap) {
            ZStack {
                Circle()
                    .fill(buttonFill)
                    .overlay(
                        Circle().strokeBorder(buttonBorder, lineWidth: buttonBorderWidth)
                    )
                    // Brass halo ring - expanded + listening only.
                    .overlay(
                        Circle()
                            .strokeBorder(theme.currentTheme.chrome.accentStrong, lineWidth: 3)
                            .blur(radius: 0.5)
                            .opacity(chrome.state != .resting ? 1 : 0)
                            .scaleEffect(haloScale)
                            .animation(.spring(response: 0.42, dampingFraction: 0.72), value: chrome.state)
                    )
                    .shadow(
                        color: shadowColor,
                        radius: shadowRadius,
                        x: 0, y: 2
                    )

                TalkiePivotGlyph(isResting: chrome.state == .resting)
                    .foregroundStyle(glyphColor)
            }
            .frame(width: 56, height: 56)
            .scaleEffect(buttonScale)
            .animation(.spring(response: 0.34, dampingFraction: 0.72), value: chrome.state)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // 12pt bottom inset puts this 56pt button's vertical center at
        // ~40pt above the bottom edge, matching the LiquidGlassTray and
        // both bottom complication circles.
        .padding(.bottom, 12)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    // MARK: - State-derived styling

    private var buttonFill: Color {
        switch chrome.state {
        case .resting:
            return theme.colors.cardBackground
        case .expanded:
            return theme.colors.textPrimary
        case .listening:
            return theme.currentTheme.chrome.accent
        }
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
        case .resting:   return theme.currentTheme.chrome.accent
        case .expanded:  return theme.colors.background
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
        // scale directly from theme.chrome.glowRadius with no floor.
        let glow = theme.currentTheme.chrome.glowRadius
        switch chrome.state {
        case .resting:   return 4
        case .expanded:  return glow * 2
        case .listening: return glow * 3
        }
    }

    private var buttonScale: CGFloat {
        switch chrome.state {
        case .resting: return 1.0
        case .expanded: return 1.04
        case .listening: return 1.08
        }
    }

    private var haloScale: CGFloat {
        switch chrome.state {
        case .resting: return 1.0
        case .expanded: return 1.18
        case .listening: return 1.28
        }
    }

    private var accessibilityLabel: String {
        switch chrome.state {
        case .resting:   return "Summon Talkie controls"
        case .expanded:  return "Record memo"
        case .listening: return "Listening, release to send"
        }
    }

    private var accessibilityHint: String {
        switch chrome.state {
        case .resting:
            return "Tap to summon controls."
        case .expanded:
            return "Tap to record. Long-press to talk."
        case .listening:
            return "Release to send the voice command."
        }
    }

    private func handleTap() {
        switch chrome.state {
        case .resting:
            chrome.tapPivotButton()
        case .expanded:
            RecordingSheetController.shared.isPresented = true
            chrome.dismissChrome()
        case .listening:
            break
        }
    }
}

/// Crossfades the brand mark into the mic as chrome unfolds. The offset and
/// scale changes are intentionally small so it reads as a friendly handoff,
/// not a jump cut.
private struct TalkiePivotGlyph: View {
    let isResting: Bool

    var body: some View {
        ZStack {
            Image("TalkieT")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 27, height: 27)
                .opacity(isResting ? 1 : 0)
                .scaleEffect(isResting ? 1 : 0.64)
                .rotationEffect(.degrees(isResting ? 0 : -8))

            Image(systemName: "mic.fill")
                .font(.system(size: 25, weight: .medium))
                .opacity(isResting ? 0 : 1)
                .scaleEffect(isResting ? 0.62 : 1)
                .offset(y: isResting ? 7 : 0)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: isResting)
    }
}
