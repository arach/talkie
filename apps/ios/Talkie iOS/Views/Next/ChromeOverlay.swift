//
//  ChromeOverlay.swift
//  Talkie iOS
//
//  Summoned chrome layer. Top corner pills plus a liquid-glass
//  bottom tray with three circular anchors: Capture at bottom-left,
//  the animated Talkie pivot/mic at center, and Keyboard at
//  bottom-right.
//
//  Design ref: design/studio/app/complications/ (variant `full`).
//

import SwiftUI

struct ChromeOverlay: View {
    @EnvironmentObject private var chrome: ShellChrome
    @EnvironmentObject private var router: AppShellRouter

    /// Compose has its own bottom voice/keyboard tray + inline mic,
    /// so the universal create-tray and bottom corner complications
    /// would duplicate. On Compose the chrome shrinks to its nav
    /// corners (Done + Settings) and the shell pivot handles recording
    /// or long-press voice commands when the keyboard is down.
    private var showCreateTray: Bool {
        if case .compose = router.surface { return false }
        return true
    }

    var body: some View {
        ZStack {
            if chrome.state != .resting {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { chrome.dismissChrome() }
            }

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

            // Ambient, not summoned: an ask in flight is worth seeing whether or
            // not the chrome is open, so this sits outside the tray's reveal.
            AskActivityPill()

            if showCreateTray {
                LiquidGlassTray()

                CornerSlot(
                    zone: .bottomLeading,
                    glyph: AnyView(Image(systemName: "plus.viewfinder").font(.system(size: 15, weight: .regular))),
                    label: "Capture",
                    isAccented: true
                ) {
                    AppShellRouter.shared.openCaptureCompose()
                    chrome.dismissChrome()
                }

                CornerSlot(
                    zone: .bottomTrailing,
                    glyph: AnyView(Image(systemName: "keyboard").font(.system(size: 14, weight: .regular))),
                    label: "Keyboard"
                ) {
                    AppShellRouter.shared.openComposeWithKeyboard()
                    chrome.dismissChrome()
                }
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
    var isAccented: Bool = false
    let action: () -> Void

    @EnvironmentObject private var chrome: ShellChrome
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
                    glyph.foregroundStyle(isAccented ? theme.currentTheme.chrome.accent : theme.colors.textSecondary)
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
        // LiquidGlassTray and the bottom-center Talkie pivot. Top
        // corners keep the tighter 6pt inset since the top band has no
        // tray to align against.
        .padding(.bottom, isBottom ? 16 : 0)
        .scaleEffect(isBottom && chrome.state == .resting ? 0.72 : 1)
        .offset(y: isBottom && chrome.state == .resting ? 8 : 0)
        .animation(.spring(response: 0.36, dampingFraction: 0.76), value: chrome.state)
    }
}

/// Full-width liquid-glass nav band that encompasses every bottom-row
/// complication equally: Capture · Home · Compose · Mic pivot · Ask AI ·
/// Terminal · Keyboard. Capture, the center pivot, and Keyboard are
/// standalone circles rendered above this band; the tray reserves matching
/// gaps so the row reads as one balanced control surface.
private struct LiquidGlassTray: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var chrome: ShellChrome

    var body: some View {
        // End slots match the 48pt corner complications. The center gap
        // matches the 56pt Talkie pivot so its T-to-mic animation can sit
        // inside the tray without resizing the band.
        let centerGapSize: CGFloat = 56

        HStack(spacing: 0) {
            // Left end - Capture complication shows through (standalone).
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
                glyph: AnyView(Image(systemName: "square.and.pencil").font(.system(size: 15, weight: .regular))),
                label: "Compose"
            ) {
                AppShellRouter.shared.openCompose(documentID: UUID().uuidString)
                chrome.dismissChrome()
            }

            Spacer(minLength: 0)

            // Center - the always-visible Talkie pivot shows through and
            // animates from T to mic as this tray unfolds.
            Color.clear.frame(width: centerGapSize, height: 36)

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

            // Right end - Keyboard complication shows through (standalone).
            Color.clear.frame(width: 48, height: 36)
        }
        // Pin the band's content height so the capsule shape is the same
        // on every surface; the standalone circular complications overhang
        // the fixed-height capsule instead of dictating its size.
        .frame(height: 36)
        // Zero internal horizontal padding so the 48pt end slots align
        // their centers to the standalone bottom corner circles.
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
        // 20pt outer inset matches the corner complication inset, so the
        // band's left and right edges share origins with those circles.
        .padding(.horizontal, 20)
        // Bottom inset keeps the band's center-Y (~40pt above the safe
        // area) aligned with the bottom complications and center pivot.
        .padding(.bottom, 17)
        .scaleEffect(x: chrome.state == .resting ? 0.24 : 1, y: 1, anchor: .center)
        .animation(.spring(response: 0.44, dampingFraction: 0.78), value: chrome.state)
    }
}

/// One-line report on an ask spoken from the Watch, sitting just above the
/// bottom tray. Borrows the tray's material so it reads as part of the same
/// control band rather than a notification pasted on top of the app.
///
/// It is deliberately the only always-on chrome besides the pivot: without it
/// an ask could transcribe, answer, and fail with nothing on the phone screen
/// to say so.
private struct AskActivityPill: View {
    @ObservedObject private var registry = AskInFlightRegistry.shared
    @ObservedObject private var theme = ThemeManager.shared

    /// Clears the 48pt bottom corner circles (16pt inset + 48pt) with a small
    /// gap, so the pill stacks on the control band instead of colliding with it.
    private static let bottomInset: CGFloat = 72

    var body: some View {
        Group {
            if let entry = registry.current {
                content(entry)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.horizontal, 20)
        .padding(.bottom, Self.bottomInset)
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: registry.current)
    }

    private func content(_ entry: AskInFlightRegistry.Entry) -> some View {
        let chrome = theme.currentTheme.chrome
        let tint = tint(for: entry.phase)

        return Button {
            AppShellRouter.shared.openMemoDetail(memoID: entry.id)
        } label: {
            HStack(spacing: 8) {
                if entry.phase.isSettled {
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                        .tint(tint)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.phase.pillLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)

                    if let text = entry.text, !text.isEmpty {
                        Text(text)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 0)

                // Only failures need dismissing by hand; an answer retires
                // itself, and an ask still in flight has nothing to dismiss.
                if entry.phase == .failed {
                    Button {
                        registry.dismiss(entry.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.colors.textSecondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss failed ask")
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, entry.phase == .failed ? 2 : 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    Capsule()
                        .fill(theme.colors.cardBackground.opacity(0.70))
                        .background(.ultraThinMaterial, in: Capsule())
                    Capsule()
                        .strokeBorder(chrome.edgeFaint, lineWidth: chrome.hairlineWidth)
                }
            )
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.phase.pillLabel). Open this ask.")
    }

    /// Same semantics the Watch uses: theme accent while working, green for a
    /// finished answer, red for a failure.
    private func tint(for phase: WatchSessionManager.AskPhase) -> Color {
        switch phase {
        case .answered: return .green
        case .failed: return .red
        default: return theme.currentTheme.chrome.accent
        }
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
