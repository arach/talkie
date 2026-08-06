//
//  TerminalMessageStrip.swift
//  Talkie iOS
//
//  The amber-CRT Terminal Message Line as a reusable, surface-agnostic
//  component (studio "Strip System" — design/studio/components/studies/
//  CockpitTwoRow.tsx). ONE derived fact on a single phosphor-mono line over dark
//  glass with scanlines, a static block cursor, a right-edge fade for overflow,
//  and an optional right-docked readout lane. It is seated ONLY on Home this pass
//  (the Console's Message Line) but is intentionally NOT Home-coupled: it carries
//  its own terminal material so any surface (Library · Ask · Settings) can host
//  the same travelling message area.
//
//  Vocabulary: design/studio/app/cockpit-two-row/page.tsx (NamesMarginalia —
//  Message Line · Docked Readout · Strip System). Geometry mirrors the studio
//  constants exactly (MSG_FONT 15 · STRIP_PAD_X 10 · DOCK_W 96).
//

import SwiftUI

/// A small right-docked readout lane on the Message Line (studio "Docked
/// Readout") — the useful fact that replaces the dropped clock. The caller
/// supplies the already-resolved label/value/hot so the strip stays agnostic to
/// streak / take-count math.
struct TerminalDockReadout: Equatable {
    let label: String
    let value: String
    let hot: Bool
}

// The terminal strip carries its own theme lookup so it can travel to non-Home
// surfaces while matching the same active chrome vocabulary as the cockpit.
// Shared with the failure toast (FeedbackToastNext) so a dropped voice turn
// speaks the same phosphor language as the Message Line.
enum TerminalStripPalette {
    private static var activeTheme: AppTheme { ActiveTheme.current }

    private static var chrome: ChromeTokens { activeTheme.chrome }

    static var phosphor: Color { chrome.panelAccent }
    static var phosphorDim: Color { tint(chrome.panelAccent, 0.5) }
    static var accent: Color { chrome.accent }
    static var glassTop: Color { chrome.panelAlt }
    static var glassBottom: Color { chrome.panel }
    static var glowInk: Color { chrome.panelAccent }

    /// Whether this theme wants the CRT material at all. A flat theme gets the
    /// glass colour and the word, and nothing in between. See `DeckFinish`.
    static var finish: DeckFinish { activeTheme.finish }

    /// A tint on the terminal glass. `glassBottom` is the plate the strip
    /// actually sits on, so that is what a solid finish resolves against.
    static func tint(_ ink: Color, _ alpha: Double, over plate: Color? = nil) -> Color {
        finish.tint(ink, alpha, over: plate ?? glassBottom)
    }

    /// The ink a strip draws with, resolved for the surface it is actually on.
    ///
    /// A strip that carries its own glass is a lit panel, and `panelAccent` is
    /// the phosphor for it — which on the themes whose plates stay dark in both
    /// modes is a near-white by design (see graphite's `FAFAFA`). Take the glass
    /// away and that same near-white lands on the page: white on white.
    ///
    /// So a flush strip reads its ink off `accent` instead, the token that flips
    /// with the appearance mode and therefore already knows which side of the
    /// page it is on. It also gives up every lit material at once — halo, bloom,
    /// scanlines — because those describe a CRT, and a flush strip has no CRT to
    /// describe. A scanline in particular is a dark band cutting every glyph; on
    /// glass it is the point, and on paper it is damage.
    static func ink(flush: Bool) -> TerminalStripInk {
        guard flush else {
            return TerminalStripInk(
                ink: phosphor, dim: phosphorDim, hot: accent,
                plate: glassBottom, lift: finish.lift
            )
        }
        let colors = activeTheme.colors
        return TerminalStripInk(
            ink: chrome.accent,
            dim: colors.textSecondary,
            hot: chrome.accent,
            plate: colors.cardBackground,
            lift: 0
        )
    }
}

/// One strip's resolved colours plus how much lit material it is allowed.
struct TerminalStripInk {
    let ink: Color
    let dim: Color
    let hot: Color
    /// What a tint on this strip resolves against under a solid finish.
    let plate: Color
    /// Scales every halo, bloom and scanline. Zero means "this is not a screen".
    let lift: Double
}

enum TerminalStripMetrics {
    static let font: CGFloat = 15          // MSG_FONT
    static let tracking: CGFloat = 0.9     // ≈ 0.06em at 15pt
    static let padH: CGFloat = 10          // STRIP_PAD_X
    static let corner: CGFloat = 7
    static let dockWidth: CGFloat = 96     // DOCK_W
    static let scanlineOpacity: Double = 0.30
    static let borderOpacity: Double = 0.16
    static let defaultHeight: CGFloat = 36 // STRIP_H (the bare travelling form)
}

/// The amber-CRT Terminal readout — one glyph row tall, full width. Phosphor
/// mono text with a soft glow + static scanlines. A block cursor ▮ trails a line
/// that fits; a line that overflows is pushed off the clipped right edge under
/// the phosphor fade. An optional Docked Readout rides the right edge as its own
/// hairline-divided lane. Strictly static — nothing scrolls or blinks.
struct TerminalMessageStrip: View {
    let text: String
    var height: CGFloat = TerminalStripMetrics.defaultHeight
    var dock: TerminalDockReadout? = nil
    /// Drop the strip's own container — glass, corners, border — and draw the
    /// line straight onto whatever it is sitting on.
    ///
    /// A strip that carries its own rounded, bordered plate is right when it
    /// floats inside a screen inside a bezel: it needs to say where it begins.
    /// Inside a masthead that is already one continuous surface, that plate is
    /// a third box drawn inside two others, and the border it draws to separate
    /// itself is the same hairline the masthead is drawing anyway.
    var flush: Bool = false

    // The palette below is a static table, invisible to SwiftUI's dependency
    // tracking. Without an explicit observation a theme change leaves the line
    // painted in the outgoing theme's phosphor until `text` happens to change.
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: TerminalStripMetrics.corner, style: .continuous)
        let docked = dock != nil
        let trailingReserve = docked
            ? TerminalStripMetrics.dockWidth + TerminalStripMetrics.padH
            : TerminalStripMetrics.padH
        let finish = TerminalStripPalette.finish
        let ink = TerminalStripPalette.ink(flush: flush)

        // The line rides in an overlay over an empty flexible slot rather than
        // sitting in the layout directly. `fixedSize()` below is what lets a long
        // message run off the clipped edge instead of truncating with an ellipsis
        // — but a fixed-size child also reports its full intrinsic width to
        // whatever contains it, and stacks hand that width straight up to their
        // own parent. Hosted in an overlay the text still draws at full length
        // while the strip only ever claims the width it was offered, so a long
        // message can't quietly widen its host (and, through the cockpit, every
        // screen in the app).
        Color.clear
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                HStack(spacing: 3) {
                    Text(text)
                        .font(finish.font(TerminalStripMetrics.font, .medium))
                        .textCase(.uppercase)
                        .tracking(finish.tracking(TerminalStripMetrics.tracking))
                        .foregroundStyle(ink.ink)
                        // Two stacked halos are what makes a phosphor line look
                        // lit. They are also two films over the word, so a flat
                        // theme takes neither.
                        .shadow(color: TerminalStripPalette.accent.opacity(0.55 * ink.lift), radius: 4)
                        .shadow(color: TerminalStripPalette.glowInk.opacity(0.9 * ink.lift), radius: 1)
                        .lineLimit(1)
                        .fixedSize()

                    // Static block cursor — visible when the line fits; when it
                    // overflows the cursor is pushed past the clipped right edge
                    // (and faded out).
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(ink.ink)
                        .frame(width: TerminalStripMetrics.font * 0.55, height: TerminalStripMetrics.font * 0.95)
                        .shadow(color: TerminalStripPalette.accent.opacity(0.8 * ink.lift), radius: 3)
                }
            }
            .mask(
                LinearGradient(
                    stops: [.init(color: .black, location: 0.74), .init(color: .clear, location: 1.0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .padding(.leading, TerminalStripMetrics.padH)
            .padding(.trailing, trailingReserve)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
            // Dock composited BEFORE the clip so its trailing corners round with
            // the strip while its left divider edge stays straight.
            .overlay(alignment: .trailing) {
                if let dock {
                    DockedReadout(readout: dock, ink: ink)
                        .frame(width: TerminalStripMetrics.dockWidth)
                }
            }
            .background { if !flush { TerminalGlass() } }
            .clipShape(flush ? AnyShape(Rectangle()) : AnyShape(shape))
            // Scanlines are the one film here that lands *on* the letterform
            // rather than around it — a 1-in-3pt dark band cuts every glyph at
            // 15pt. It is the whole point of a CRT and the whole problem with
            // reading one, so a flat theme gets none.
            .overlay(
                ScanlineOverlay()
                    .fill(Color.black.opacity(TerminalStripMetrics.scanlineOpacity * ink.lift))
                    .clipShape(shape)
                    .allowsHitTesting(false)
            )
            .overlay {
                if !flush {
                    shape.strokeBorder(
                        TerminalStripPalette.tint(TerminalStripPalette.accent, TerminalStripMetrics.borderOpacity),
                        lineWidth: 1
                    )
                }
            }
    }
}

// MARK: - Docked Readout

/// The right-docked HUD lane on the Message Line (studio "Docked Readout"): a
/// hairline-divided slot with a whisper of glass carrying a small label + value.
private struct DockedReadout: View {
    let readout: TerminalDockReadout
    let ink: TerminalStripInk

    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        let finish = TerminalStripPalette.finish
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            Text(readout.label)
                .font(finish.font(8, .semibold))
                .tracking(finish.tracking(1.12)) // 0.14em at 8pt
                .foregroundStyle(ink.dim)
            Text(readout.value)
                .font(finish.font(13, .bold).monospacedDigit())
                .tracking(finish.tracking(0.52)) // 0.04em at 13pt
                .foregroundStyle(readout.hot ? ink.hot : ink.dim)
                .shadow(
                    color: readout.hot ? TerminalStripPalette.accent.opacity(0.5 * ink.lift) : .clear,
                    radius: readout.hot ? 3 : 0
                )
        }
        .padding(.trailing, TerminalStripMetrics.padH)
        .frame(maxHeight: .infinity)
        // The lane's wash and divider are how it says "this is a separate slot"
        // on glass. In a masthead the slot is already implied by the margin, and
        // one more vertical rule inside a band whose whole argument is fewer
        // divisions would be the division that breaks it.
        .background(
            LinearGradient(
                colors: [.clear, TerminalStripPalette.tint(TerminalStripPalette.accent, 0.05 * ink.lift, over: ink.plate)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(TerminalStripPalette.tint(TerminalStripPalette.accent, 0.16 * ink.lift, over: ink.plate))
                .frame(width: 1)
        }
        .accessibilityHidden(true) // the hosting surface's label already carries this fact
    }
}

// MARK: - Terminal material (glass + scanlines)

/// The dark amber glass behind the terminal line — a near-black vertical
/// gradient with a soft amber radial bloom (TERM_GLASS in the studio).
struct TerminalGlass: View {
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [TerminalStripPalette.glassTop, TerminalStripPalette.glassBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [TerminalStripPalette.accent.opacity(0.12 * TerminalStripPalette.finish.lift), .clear],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 0,
                endRadius: 90
            )
        }
    }
}

/// Thin dark horizontal raster lines over the terminal glass — a static 1-in-3pt
/// dark band. Drawn as a Shape (path built at layout, never per frame).
struct ScanlineOverlay: Shape {
    var spacing: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var y = rect.minY
        while y < rect.maxY {
            path.addRect(CGRect(x: rect.minX, y: y, width: rect.width, height: 1))
            y += spacing
        }
        return path
    }
}
