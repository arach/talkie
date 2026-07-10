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

// The terminal strip's own material — mirrors HomeTacticalPalette's amber
// phosphor values verbatim, kept here so the component carries no Home
// dependency and can travel to non-Home surfaces unchanged.
private enum TerminalStripPalette {
    static let phosphor = Color(hex: "FFB24A")
    static let phosphorDim = Color(hex: "FFB24A").opacity(0.5) // PHOSPHOR_DIM
    static let accent = Color(hex: "FF8800")
    static let glassTop = Color(hex: "0B0704")
    static let glassBottom = Color(hex: "050301")
    static let glowInk = Color(hex: "FFCD82")
}

private enum TerminalStripMetrics {
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

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: TerminalStripMetrics.corner, style: .continuous)
        let docked = dock != nil
        let trailingReserve = docked
            ? TerminalStripMetrics.dockWidth + TerminalStripMetrics.padH
            : TerminalStripMetrics.padH

        HStack(spacing: 3) {
            Text(text)
                .font(.system(size: TerminalStripMetrics.font, weight: .medium, design: .monospaced))
                .textCase(.uppercase)
                .tracking(TerminalStripMetrics.tracking)
                .foregroundStyle(TerminalStripPalette.phosphor)
                .shadow(color: TerminalStripPalette.accent.opacity(0.55), radius: 4)
                .shadow(color: TerminalStripPalette.glowInk.opacity(0.9), radius: 1)
                .lineLimit(1)
                .fixedSize()

            // Static block cursor — visible when the line fits; when it overflows
            // the cursor is pushed past the clipped right edge (and faded out).
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(TerminalStripPalette.phosphor)
                .frame(width: TerminalStripMetrics.font * 0.55, height: TerminalStripMetrics.font * 0.95)
                .shadow(color: TerminalStripPalette.accent.opacity(0.8), radius: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        // Dock composited BEFORE the clip so its trailing corners round with the
        // strip while its left divider edge stays straight.
        .overlay(alignment: .trailing) {
            if let dock {
                DockedReadout(readout: dock)
                    .frame(width: TerminalStripMetrics.dockWidth)
            }
        }
        .background(TerminalGlass())
        .clipShape(shape)
        .overlay(
            ScanlineOverlay()
                .fill(Color.black.opacity(TerminalStripMetrics.scanlineOpacity))
                .clipShape(shape)
                .allowsHitTesting(false)
        )
        .overlay(shape.strokeBorder(TerminalStripPalette.accent.opacity(TerminalStripMetrics.borderOpacity), lineWidth: 1))
    }
}

// MARK: - Docked Readout

/// The right-docked HUD lane on the Message Line (studio "Docked Readout"): a
/// hairline-divided slot with a whisper of glass carrying a small label + value.
private struct DockedReadout: View {
    let readout: TerminalDockReadout

    var body: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            Text(readout.label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.12) // 0.14em at 8pt
                .foregroundStyle(TerminalStripPalette.phosphorDim)
            Text(readout.value)
                .font(.system(size: 13, weight: .bold, design: .monospaced).monospacedDigit())
                .tracking(0.52) // 0.04em at 13pt
                .foregroundStyle(readout.hot ? TerminalStripPalette.accent : TerminalStripPalette.phosphorDim)
                .shadow(color: readout.hot ? TerminalStripPalette.accent.opacity(0.5) : .clear, radius: readout.hot ? 3 : 0)
        }
        .padding(.trailing, TerminalStripMetrics.padH)
        .frame(maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [.clear, TerminalStripPalette.accent.opacity(0.05)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(TerminalStripPalette.accent.opacity(0.16))
                .frame(width: 1)
        }
        .accessibilityHidden(true) // the hosting surface's label already carries this fact
    }
}

// MARK: - Terminal material (glass + scanlines)

/// The dark amber glass behind the terminal line — a near-black vertical
/// gradient with a soft amber radial bloom (TERM_GLASS in the studio).
private struct TerminalGlass: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [TerminalStripPalette.glassTop, TerminalStripPalette.glassBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [TerminalStripPalette.accent.opacity(0.12), .clear],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 0,
                endRadius: 90
            )
        }
    }
}

/// Thin dark horizontal raster lines over the terminal glass — a static 1-in-3pt
/// dark band. Drawn as a Shape (path built at layout, never per frame).
private struct ScanlineOverlay: Shape {
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
