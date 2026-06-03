//
//  ChromeOverlay.swift
//  Talkie iOS
//
//  Summoned chrome layer. Three corner pills (Done top-left,
//  Settings top-right, Keyboard bottom-right) + a liquid-glass
//  bottom tray (Camera · Browse · Mic FAB · Ask AI · Terminal).
//  Bottom-left is left empty — that's where the voice button
//  lives. Tray slot counts stay odd so the mic FAB stays the
//  visual center; pair additions across the FAB, never one-sided.
//
//  Design ref: design/studio/app/complications/ (variant `full`).
//

import SwiftUI

struct ChromeOverlay: View {
    @EnvironmentObject private var chrome: ShellChrome
    @EnvironmentObject private var router: AppShellRouter
    @ObservedObject private var theme = ThemeManager.shared

    /// Compose has its own bottom voice/keyboard tray + inline mic,
    /// so the universal create-tray (Camera · Mic · Compose) and the
    /// bottom-right Keyboard pill would just duplicate. On Compose
    /// the chrome shrinks to its nav corners (Done + Settings) and
    /// the shell voice button handles long-press voice commands.
    private var showCreateTray: Bool {
        if case .compose = router.surface { return false }
        return true
    }

    var body: some View {
        ZStack {
            // topLeading: the view owns this slot at rest (back chevrons,
            // titles, etc). When chrome is summoned the view's content
            // yields and chrome registers a Home pill in its place —
            // a "back to root" affordance from anywhere. On the home
            // surface itself the pill is suppressed (Home → Home is a
            // no-op), so the slot stays clean.
            if router.surface != .home {
                CornerSlot(
                    zone: .topLeading,
                    glyph: AnyView(Image(systemName: "house").font(.system(size: 15, weight: .regular))),
                    label: "Home"
                ) {
                    AppShellRouter.shared.openHome()
                    chrome.dismissChrome()
                }
            }

            CornerSlot(
                zone: .topTrailing,
                glyph: AnyView(Image(systemName: "gearshape").font(.system(size: 15, weight: .regular))),
                label: "Settings"
            ) {
                AppShellRouter.shared.openSettings()
            }

            if showCreateTray {
                // Keyboard now lives as the right-most slot inside the
                // full-width LiquidGlassTray (see below), so it no longer
                // needs its own bottom-trailing corner pill.
                LiquidGlassTray()
            }
        }
    }
}

/// One of the four corner pill buttons. Anchored via ScreenZone so
/// it shares placement vocabulary with screen-native UI; safe-area-
/// respecting padding handles the inset.
private struct CornerSlot: View {
    let zone: ScreenZone
    let glyph: AnyView
    let label: String
    let action: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    private var isTop: Bool {
        zone == .topLeading || zone == .topTrailing
    }

    private var isBottom: Bool {
        zone == .bottomLeading || zone == .bottomTrailing
    }

    var body: some View {
        let hairline = theme.currentTheme.chrome.hairlineWidth
        InZone(zone) {
            Button(action: action) {
                ZStack {
                    Circle().fill(theme.colors.cardBackground)
                    Circle().strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: hairline)
                    glyph.foregroundStyle(theme.colors.textSecondary)
                }
                .frame(width: 48, height: 48)
                .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
        }
        .padding(.horizontal, 20)
        .padding(.top, isTop ? 6 : 0)
        // Bottom corner slots sit 16pt above the edge so their 48pt
        // circles share a center-Y (40pt from safe area) with the
        // LiquidGlassTray, the bottom-left VoicePivotButton, and the
        // bottom-center MicFAB. Top corners keep the tighter 6pt inset
        // since the top band has no tray to align against.
        .padding(.bottom, isBottom ? 16 : 0)
    }
}

/// Full-width liquid-glass nav band that encompasses every bottom-row
/// complication equally: Voice · Home · Capture · Mic FAB · Ask AI ·
/// Terminal · Keyboard. The band spans edge-to-edge (matching the 20pt
/// chrome inset) with the seven slots distributed evenly, so the Mic
/// FAB stays the geometric center with three satellites on each side.
///
/// Voice (left end) and Mic (center) are show-through gaps: the
/// always-visible VoicePivotButton and persistent MicFAB are rendered
/// standalone by AppShellNext and sit *inside* this band at its left
/// end and center. Keeping them standalone preserves the summon
/// affordance, the listening-bubble origin, and the hero FAB sizing.
/// The band reserves matching gaps so they read as in-band slots.
private struct LiquidGlassTray: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var chrome: ShellChrome
    @EnvironmentObject private var router: AppShellRouter

    var body: some View {
        // End slots are 48pt wide to match the 48pt Voice/Keyboard
        // circles and keep the band symmetric about center; mid slots
        // stay 32pt. The center reserves room for whichever mic is
        // active (56pt hero on home, 48pt inline elsewhere).
        let micGapSize: CGFloat = router.surface == .home ? 56 : 48

        HStack(spacing: 0) {
            // Left end — VoicePivotButton shows through (standalone).
            Color.clear.frame(width: 48, height: 36)

            Spacer(minLength: 0)

            TraySlot(
                glyph: AnyView(
                    Image("TalkieT")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 26, height: 26)
                ),
                label: "Home"
            ) {
                AppShellRouter.shared.openHome()
                chrome.dismissChrome()
            }

            Spacer(minLength: 0)

            TraySlot(
                glyph: AnyView(Image(systemName: "plus.viewfinder").font(.system(size: 15, weight: .regular))),
                label: "Capture"
            ) {
                AppShellRouter.shared.openCaptureCompose()
                chrome.dismissChrome()
            }

            Spacer(minLength: 0)

            // Center — on home the standalone MicFAB (rendered by
            // AppShellNext) shows through this gap; on sub-surfaces the
            // band carries the FAB inline.
            if router.surface == .home {
                Color.clear.frame(width: micGapSize, height: 36)
            } else {
                MicFAB()
            }

            Spacer(minLength: 0)

            TraySlot(
                glyph: AnyView(Image(systemName: "sparkles").font(.system(size: 13, weight: .regular))),
                label: "Ask AI"
            ) {
                AppShellRouter.shared.openAskAI()
                chrome.dismissChrome()
            }

            Spacer(minLength: 0)

            TraySlot(
                glyph: AnyView(Image(systemName: "terminal").font(.system(size: 13, weight: .regular))),
                label: "Terminal"
            ) {
                AppShellRouter.shared.openTerminal()
                chrome.dismissChrome()
            }

            Spacer(minLength: 0)

            // Right end — Keyboard, moved in from the old corner pill.
            // Opens a fresh Compose document with the embedded Talkie
            // keyboard already up.
            TraySlot(
                glyph: AnyView(Image(systemName: "keyboard").font(.system(size: 14, weight: .regular))),
                label: "Keyboard",
                width: 48
            ) {
                AppShellRouter.shared.openComposeWithKeyboard()
            }
        }
        // Pin the band's content height so the capsule shape is the same
        // on every surface. Without this, sub-surfaces (which carry the
        // 48pt MicFAB inline) grew a taller capsule than home (which only
        // reserves a gap), pushing the band's center ~6pt higher there.
        // The inline MicFAB now overhangs this fixed height by ~1pt —
        // visually centered — instead of dictating it.
        .frame(height: 36)
        // Zero internal horizontal padding so the 48pt end slots align
        // their centers to the standalone Voice circle (20pt leading
        // inset → 44pt center) and a mirrored Keyboard on the right.
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                Capsule()
                    .fill(theme.colors.cardBackground.opacity(0.70))
                    .background(.ultraThinMaterial, in: Capsule())
                Capsule()
                    .strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: theme.currentTheme.chrome.hairlineWidth)
            }
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // 20pt outer inset matches the Voice button's leading inset, so
        // the band's left edge and the Voice circle share an origin.
        .padding(.horizontal, 20)
        // Bottom inset keeps the band's center-Y (~40pt above the safe
        // area) aligned with the Voice circle and the standalone MicFAB.
        .padding(.bottom, 17)
    }
}

private struct TraySlot: View {
    let glyph: AnyView
    let label: String
    var width: CGFloat = 32
    let action: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Button(action: action) {
            glyph
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: width, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The always-visible mic FAB — primary create action. Lives at the
/// bottom-center of the shell whether or not chrome is summoned, so
/// "record a memo" is a single tap. When chrome IS summoned the
/// FAB sits visually centered in the tray's gap; when chrome is
/// resting the FAB still anchors the bottom on its own.
struct MicFAB: View {
    let size: CGFloat
    @ObservedObject private var theme = ThemeManager.shared

    init(size: CGFloat = 48) {
        self.size = size
    }

    var body: some View {
        Button(action: {
            RecordingSheetController.shared.isPresented = true
        }) {
            ZStack {
                Circle().fill(theme.currentTheme.chrome.accent)
                Image(systemName: "mic.fill")
                    .font(.system(size: size >= 56 ? 25 : 22, weight: .medium))
                    .foregroundStyle(theme.colors.cardBackground)
            }
            .frame(width: size, height: size)
            .shadow(color: theme.currentTheme.chrome.accentGlow, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Record memo")
    }
}

private extension Alignment {
    var isTop: Bool {
        self == .top || self == .topLeading || self == .topTrailing
    }
    var isBottom: Bool {
        self == .bottom || self == .bottomLeading || self == .bottomTrailing
    }
}
