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
            // Top corners — chrome destinations.
            CornerSlot(
                position: .topLeading,
                glyph: AnyView(Image(systemName: "chevron.down").font(.system(size: 15, weight: .medium))),
                label: "Done"
            ) {
                // Dismisses the summoned chrome. Going home lives in the
                // tray (leftmost slot); back/pop is handled by the native
                // NavigationStack chevron at the top of each sub-surface.
                chrome.dismissChrome()
            }

            CornerSlot(
                position: .topTrailing,
                glyph: AnyView(Image(systemName: "gearshape").font(.system(size: 15, weight: .regular))),
                label: "Settings"
            ) {
                AppShellRouter.shared.openSettings()
            }

            if showCreateTray {
                CornerSlot(
                    position: .bottomTrailing,
                    glyph: AnyView(Image(systemName: "keyboard").font(.system(size: 13, weight: .regular))),
                    label: "Keyboard"
                ) {
                    AppShellRouter.shared.openKeyboardActivation()
                }

                LiquidGlassTray()
            }
        }
    }
}

/// One of the four corner pill buttons. Position is a SwiftUI
/// Alignment so we use the full screen to anchor each corner;
/// safe-area-respecting padding handles the inset.
private struct CornerSlot: View {
    let position: Alignment
    let glyph: AnyView
    let label: String
    let action: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let hairline = theme.currentTheme.chrome.hairlineWidth
        Button(action: action) {
            ZStack {
                Circle().fill(theme.colors.cardBackground)
                Circle().strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: hairline)
                glyph.foregroundStyle(theme.colors.textSecondary)
            }
            .frame(width: 40, height: 40)
            .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: position)
        .padding(.horizontal, 20)
        .padding(.top, position.isTop ? 6 : 0)
        // Bottom corner slots sit 20pt above the edge so their 40pt
        // circles share a center-Y (~40pt) with the LiquidGlassTray
        // and the bottom-left VoicePivotButton. Top corners keep the
        // tighter 6pt inset since the top band has no tray to align
        // against.
        .padding(.bottom, position.isBottom ? 20 : 0)
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

    var body: some View {
        HStack(spacing: 14) {
            TraySlot(
                glyph: AnyView(
                    Image("TalkieBowtie")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                ),
                label: "Home"
            ) {
                AppShellRouter.shared.openHome()
                chrome.dismissChrome()
            }

            TraySlot(
                glyph: AnyView(Image(systemName: "plus.viewfinder").font(.system(size: 17, weight: .regular))),
                label: "Capture"
            ) {
                AppShellRouter.shared.openCaptureCompose()
            }

            TrayFAB()

            TraySlot(
                glyph: AnyView(Image(systemName: "sparkles").font(.system(size: 15, weight: .regular))),
                label: "Ask AI"
            ) {
                AppShellRouter.shared.openAskAI()
            }

            TraySlot(
                glyph: AnyView(Image(systemName: "terminal").font(.system(size: 15, weight: .regular))),
                label: "Terminal"
            ) {
                AppShellRouter.shared.openTerminal()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
        .padding(.bottom, 6)
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
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The center mic FAB inside the tray — primary create action.
/// Filled with theme accent so it reads as the hero among the row.
private struct TrayFAB: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Button(action: {
            RecordingSheetController.shared.isPresented = true
        }) {
            ZStack {
                Circle().fill(theme.currentTheme.chrome.accent)
                Image(systemName: "mic.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(theme.colors.cardBackground)
            }
            .frame(width: 48, height: 48)
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
