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
    @EnvironmentObject private var router: AppShellRouter
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 350ms matches iOS context-menu feel - long enough that a
    /// slow tap doesn't fire it, short enough to feel responsive.
    private let longPressThreshold: Double = 0.35

    // MARK: - The resting beacon
    //
    // At rest the pivot was drawn with the faintest edge token and a 10% black
    // drop shadow, which on a dark page means a dark circle on a dark page: the
    // T is legible, but nothing about it says "press me". It was being polite
    // at the cost of being a control. So the ring now carries the theme's own
    // accent at a weight you can see, and every so often the button breathes
    // once - a light coming on, not an animation running.
    //
    // Once on arrival, then at a slow interval. Only while resting: expanded
    // and listening already glow continuously, and a pulse on top of that would
    // read as a glitch.

    /// The state at the top of a breath, 0...1. Drives the halo alone - the
    /// button's geometry never moves, so nothing reflows underneath it.
    @State private var beacon: Double = 0

    private static let beaconRise: Double = 0.9
    private static let beaconFall: Double = 1.1
    /// Gap between breaths. Long enough that it reads as ambient rather than as
    /// something demanding an answer.
    private static let beaconInterval: Double = 9
    /// A floor under the theme's glow. Themes are allowed to want no glow, but
    /// none of them want an invisible button - this part is affordance, not
    /// decoration, so it does not go to zero.
    private static let beaconMinRadius: CGFloat = 9
    /// The breath is drawn from `chrome.accent`, not `chrome.accentGlow`.
    /// Several themes set `accentGlow` to literally zero alpha - Graphite and
    /// Press both do, deliberately, because they want no halo anywhere in the
    /// app - and honouring that here would mean the flattest themes, the exact
    /// ones where the pivot is hardest to find, are the only ones that never
    /// get the hint. A bloom of the accent at this weight reads as a light
    /// coming on rather than as a second ring.
    private static let beaconAlpha: Double = 0.45

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
                    // The breath. Stacked rather than folded into `shadowColor`
                    // so the resting drop shadow keeps lifting the button off
                    // the page while the halo comes and goes above it.
                    .shadow(color: beaconColor, radius: beaconRadius)

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
        // Compose owns a contextual rail at the bottom. Raise the pivot into
        // the dedicated cursor/keyboard lane so quick transforms and diff
        // actions remain fully visible beneath it. Other surfaces keep the
        // original bottom-center placement.
        .padding(.bottom, router.isComposeSurface ? 55 : 12)
        .animation(.easeOut(duration: 0.2), value: router.isComposeSurface)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .task { await runBeacon() }
    }

    /// One breath on arrival, then one every `beaconInterval`. Cancelled with
    /// the view, so it costs nothing on screens the pivot isn't on.
    private func runBeacon() async {
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            if chrome.state == .resting {
                withAnimation(.easeOut(duration: Self.beaconRise)) { beacon = 1 }
                try? await Task.sleep(for: .seconds(Self.beaconRise))
                withAnimation(.easeIn(duration: Self.beaconFall)) { beacon = 0 }
                try? await Task.sleep(for: .seconds(Self.beaconFall))
            }
            try? await Task.sleep(for: .seconds(Self.beaconInterval))
        }
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
        // The resting ring used to be `edgeFaint`, which is the token for a
        // division between two regions - correct for a hairline, wrong for the
        // outline of the one thing on screen you are meant to touch. It reads
        // as the same family as the T inside it now, so the whole control is
        // one mark rather than a glyph sitting in a barely-there circle.
        case .resting:   return theme.currentTheme.chrome.accent
        case .expanded:  return theme.currentTheme.chrome.accentStrong
        case .listening: return theme.currentTheme.chrome.accentStrong
        }
    }

    /// One weight in every state. Resting used to be half this, which read as a
    /// smudge; the states are already told apart by fill, glyph and the halo
    /// ring, so the outline doesn't need to thin out to make the point.
    private var buttonBorderWidth: CGFloat { 1.0 }

    private var beaconColor: Color {
        guard chrome.state == .resting, beacon > 0 else { return .clear }
        return theme.currentTheme.chrome.accent.opacity(Self.beaconAlpha * beacon)
    }

    private var beaconRadius: CGFloat {
        let base = max(theme.currentTheme.chrome.glowRadius, Self.beaconMinRadius)
        return base * (1 + beacon)
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
