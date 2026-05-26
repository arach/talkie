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
                // Bottom-right keyboard pill: open a fresh Compose
                // document with the embedded Talkie keyboard already
                // up. Goes to the typing surface, not the keyboard-
                // extension status/learning surface.
                CornerSlot(
                    zone: .bottomTrailing,
                    glyph: AnyView(
                        Image(systemName: "keyboard")
                            .font(.system(size: 15, weight: .regular))
                    ),
                    label: "Keyboard"
                ) {
                    AppShellRouter.shared.openComposeWithKeyboard()
                }

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

/// Bottom-center liquid-glass nav: Camera · Browse · Mic FAB · Ask AI
/// · Terminal. Left of the FAB groups capture-source inputs (Camera
/// + Browse); right pairs intelligence (Ask AI) with the power-user
/// dev affordance (Terminal). The FAB stays the visual center —
/// slot count is kept odd by convention.
private struct LiquidGlassTray: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var chrome: ShellChrome
    @EnvironmentObject private var router: AppShellRouter

    var body: some View {
        GeometryReader { proxy in
            // Pro Max-class phones (≥400pt) get a relaxed tray —
            // more spacing between slots and more capsule h-padding —
            // so the extra horizontal real estate isn't wasted. Mini
            // and base iPhones stay tight (no overlap with corner
            // pills on a 375pt screen).
            let isWide = proxy.size.width >= 400
            let slotSpacing: CGFloat = isWide ? 14 : 8
            let capsulePadH: CGFloat = isWide ? 14 : 10
            let micGapSize: CGFloat = router.surface == .home ? 56 : 48

            HStack(spacing: slotSpacing) {
                TraySlot(
                    glyph: AnyView(
                        Image("TalkieBowtie")
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

                TraySlot(
                    glyph: AnyView(Image(systemName: "plus.viewfinder").font(.system(size: 15, weight: .regular))),
                    label: "Capture"
                ) {
                    AppShellRouter.shared.openCaptureCompose()
                }

                // Tray center: on home the standalone MicFAB (rendered by
                // AppShellNext) is always visible — leave a matching
                // gap so it shows through AND the capsule height is fixed
                // by the FAB (HStack's max-child-height determines the
                // capsule shape). Without the gap the capsule would
                // shrink to the 32pt slot height and the slot row would
                // sit below the standalone FAB's center.
                // On sub-surfaces the persistent FAB is gone, so the tray
                // itself carries the FAB inline.
                if router.surface == .home {
                    Color.clear.frame(width: micGapSize, height: micGapSize)
                } else {
                    MicFAB()
                }

                TraySlot(
                    glyph: AnyView(Image(systemName: "sparkles").font(.system(size: 13, weight: .regular))),
                    label: "Ask AI"
                ) {
                    AppShellRouter.shared.openAskAI()
                }

                TraySlot(
                    glyph: AnyView(Image(systemName: "terminal").font(.system(size: 13, weight: .regular))),
                    label: "Terminal"
                ) {
                    AppShellRouter.shared.openTerminal()
                }
            }
            .padding(.horizontal, capsulePadH)
            .padding(.vertical, 6)
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
            // 20pt outer padding matches the corner-pill horizontal inset.
            // Bottom padding keeps the capsule center aligned with the
            // corner pills and whichever mic size is active on this surface.
            .padding(.horizontal, 20)
            .padding(.bottom, router.surface == .home ? 6 : 10)
        }
    }
}

private struct TraySlot: View {
    let glyph: AnyView
    let label: String
    let action: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Button(action: action) {
            glyph
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 32, height: 32)
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
