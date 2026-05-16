//
//  ScopeDesign.swift
//  TalkieKit
//
//  Oscilloscope / lab-instrument design tokens, ported from
//  usetalkie.com's cream-phosphor light theme. Additive: lives
//  alongside TalkieTheme / MidnightSurface, doesn't replace either.
//
//  Token roles mirror the site CSS so values can be cross-checked
//  one-for-one against globals.css. Default variant is the cream
//  phosphor (warm aged-paper canvas, dark trace, brass amber);
//  other chassis (ember-cream, notepad, etc.) will land later.
//

import SwiftUI

// MARK: - Hex helper

public extension Color {
    /// Build a Color from a 6-digit hex string. No validation — this is
    /// an internal token helper, the strings are checked at write time.
    static func hex(_ hex: String) -> Color {
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double( rgb & 0x0000FF) / 255
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Surfaces

/// Page-level surfaces. Drafting-paper variant: warm gray-cream, low
/// saturation. Vintage instrument panel without the parchment heat.
///
/// The cream that works on a spacious marketing page reads as loud in
/// a dense app (lists, sidebars, packed panels). Pulled toward neutral
/// — character stays, warmth dialed back.
public enum ScopeCanvas {
    /// Primary page background — near-white with a barely-there warm
    /// uplift. The arc: `#EBECE5` (~92% L, "yellow paper") → `#F7F6F1`
    /// (~97% L, "creamy uplift") → `#FBFAF7` (~98% L, "white paper").
    /// The amber stays the focal point; the canvas reads as paper-white,
    /// not cream.
    public static let canvas = Color.hex("FBFAF7")
    /// "Bay" — sidebar / embedded structural surface. One clear step
    /// darker than `canvas` so the sidebar reads as a distinct surface
    /// without dropping into gray. Mapped to
    /// `tacticalBackgroundSecondary` in SettingsManager.
    public static let canvasAlt = Color.hex("EDECE6")
    /// Card surface — subtle step below canvas so cards read as paper,
    /// not gray panels.
    public static let surface = Color.hex("F5F4EF")
    /// 85% canvas — for floating overlays / pill chrome.
    public static let canvasOverlay = Color.hex("FBFAF7").opacity(0.85)
}

// MARK: - Ink (text)

/// Text hierarchy. 5 levels, each a step darker/grayer than the next.
/// Goes ink (headline) → ink-dim → ink-muted → ink-faint → ink-subtle.
public enum ScopeInk {
    /// Headline / primary text.
    public static let primary  = Color.hex("1A1612")
    /// Subheadline / body lead.
    public static let dim      = Color.hex("2A221E")
    /// Body / paragraph.
    public static let muted    = Color.hex("463B32")
    /// Secondary / captions.
    public static let faint    = Color.hex("6B5D4F")
    /// Tertiary / metadata.
    public static let subtle   = Color.hex("7D6E5E")
}

// MARK: - Edges (hairlines)

/// Hairline opacities relative to the ink color. 4 levels matching the
/// homepage edge-* tokens. All derived from rgba(26,22,18, α).
public enum ScopeEdge {
    private static let base = Color.hex("1A1612")

    /// 30% — strong, framed cards.
    public static let strong  = base.opacity(0.30)
    /// 20% — default card / row border.
    public static let normal  = base.opacity(0.20)
    /// 14% — section divider.
    public static let faint   = base.opacity(0.14)
    /// 8% — graticule lines, ultra-subtle dividers.
    public static let subtle  = base.opacity(0.08)
}

// MARK: - Trace (phosphor / signal line)

/// The "trace" color is the oscilloscope phosphor line. In the
/// cream-phosphor chassis, it's a deep ink-brown rather than a vivid
/// green — the contrast is the precision, not the saturation.
public enum ScopeTrace {
    /// Solid trace — the inked signal.
    public static let solid  = Color.hex("2A2520")
    /// Glow halo around active traces.
    public static let glow   = Color.hex("2A2520").opacity(0.18)
    /// Dim trace — recently active.
    public static let dim    = Color.hex("2A2520").opacity(0.28)
    /// Faint trace — graticule, idle states.
    public static let faint  = Color.hex("2A2520").opacity(0.08)
}

// MARK: - Amber (chrome accent)

/// Amber is the "lit chrome" color — eyebrow labels, status dots,
/// pricing, accent strokes. Brass / copper in cream mode; warmer
/// `FFB84D` in dark phosphor (not yet ported here).
public enum ScopeAmber {
    /// Solid amber — soft brass. Pulled from the saturated copper
    /// `#C47D1C` toward a quieter `#B5823A`: same brass family, lower
    /// chroma, sits on a whiter canvas without shouting.
    public static let solid = Color.hex("B5823A")
    /// 6% tint — button background washes. One notch quieter than the
    /// old 8% to match the softer solid.
    public static let tint = Color.hex("B5823A").opacity(0.06)
    /// 4% tint — even quieter background.
    public static let tintSubtle = Color.hex("B5823A").opacity(0.04)
    /// Glow halo for amber text / dots (use as shadow color).
    public static let glow = Color.hex("B5823A").opacity(0.22)
    /// Brighter glow for dots / focal points.
    public static let glowStrong = Color.hex("B5823A").opacity(0.32)
}

// MARK: - Panel (dark instrument bay on cream desk)

/// The bichromatic move: dark panels embedded in the cream page,
/// like an instrument bay sunk into a wooden console. Amber phosphor
/// trace on near-black background.
public enum ScopePanel {
    /// Panel background — warm graphite. Lifted from the original
    /// near-black (`#1C1814`) toward something softer that still
    /// reads as a dark instrument bay sunk into the cream page, but
    /// no longer feels stark against the surrounding warmth.
    public static let bg     = Color.hex("3A332A")
    /// Panel background — slightly lifted (for stat tiles, etc.).
    public static let bgAlt  = Color.hex("302921")
    /// Panel background — deep recess (for the most-inset surfaces).
    public static let bgDeep = Color.hex("1F1B15")

    /// Panel text — light cream against the dark.
    public static let ink       = Color.hex("F0EAD8")
    public static let inkDim    = Color.hex("D8D2C0")
    public static let inkMuted  = Color.hex("B8B0A0")
    /// Lifted from `#80786A` so chrome labels (channel ids, status text)
    /// still read as muted but actually meet readability on the warm
    /// graphite bg.
    public static let inkFaint  = Color.hex("ADA294")
    /// Lifted from `#6E675B` for the same reason — secondary metadata
    /// (timestamps, model names) needs to be subdued, not invisible.
    public static let inkSubtle = Color.hex("948A7C")

    /// Amber phosphor trace inside dark panels.
    public static let trace      = Color.hex("E89A3C")
    public static let traceGlow  = Color.hex("E89A3C").opacity(0.50)
    public static let traceDim   = Color.hex("E89A3C").opacity(0.18)
    public static let traceFaint = Color.hex("E89A3C").opacity(0.08)

    public enum Edge {
        public static let strong = Color.hex("E89A3C").opacity(0.24)
        public static let normal = Color.hex("E89A3C").opacity(0.15)
        public static let faint  = Color.hex("E89A3C").opacity(0.08)
        public static let subtle = Color.hex("E89A3C").opacity(0.06)
    }

    /// CRT scanline tint (very low alpha — overlay).
    public static let scanline = Color.hex("E89A3C").opacity(0.04)

    /// Opaque metallic-strip gradient for the panel's TOP control rail
    /// — lit-from-above brushed metal cover. Stops are solid colors
    /// (slightly lighter than the panel bg up top, slightly darker at
    /// the bottom) so the strip fully masks the graticule grid that
    /// runs through the rest of the panel — strips vs. body now read
    /// as different surfaces without needing a border.
    public static let stripTop = LinearGradient(
        stops: [
            .init(color: Color.hex("463E33"), location: 0.0),
            .init(color: Color.hex("3F3830"), location: 0.35),
            .init(color: Color.hex("2D2820"), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Opaque metallic-strip gradient for the panel's BOTTOM rail —
    /// recessed feel: shadow at the top edge, gentle catch-light at
    /// the bottom. Asymmetric with `stripTop` on purpose so the two
    /// rails feel like different physical surfaces (top cover vs.
    /// bottom rail).
    public static let stripBottom = LinearGradient(
        stops: [
            .init(color: Color.hex("2A2419"), location: 0.0),
            .init(color: Color.hex("352E26"), location: 0.55),
            .init(color: Color.hex("433C31"), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Typography presets

/// Caption / instrument-label typography. Mirrors the homepage's
/// `text-[9–10px] uppercase tracking-[0.22–0.26em]` pattern.
///
/// SwiftUI tracking is in points (not em), so we use absolute values
/// at the typical 10pt size. Tracking scales with font size in
/// SwiftUI, which is fine — the visual ratio stays close.
public enum ScopeType {
    /// 10pt monospaced bold caps, wide tracking — eyebrow / section label.
    public static let eyebrow = Font.system(size: 10, weight: .semibold, design: .monospaced)
    /// 9pt monospaced caps — channel / pin tags.
    public static let channel = Font.system(size: 9, weight: .semibold, design: .monospaced)
    /// 8pt monospaced — chrome footers, technical metadata.
    public static let chrome  = Font.system(size: 8, weight: .semibold, design: .monospaced)

    /// Tracking values matched to the homepage CSS tracking-[0.20–0.26em].
    /// SwiftUI tracking is points; at 10pt these read close to the site.
    public enum Tracking {
        /// 0.20em-equivalent — body chrome.
        public static let normal:   CGFloat = 1.6
        /// 0.24em-equivalent — eyebrow default.
        public static let wide:     CGFloat = 2.0
        /// 0.26em-equivalent — emphasis caps.
        public static let extraWide: CGFloat = 2.4
    }
}

// MARK: - Motion

/// Restrained motion that matches the homepage's `transition-all` +
/// `hover:-translate-y-0.5` feel. Snappier than the default sidebar.
public enum ScopeMotion {
    /// Tiny lift on hover — 2pt translate.
    public static let hoverLift: CGFloat = 2

    /// Fast snap for hover state changes.
    public static let snap     = Animation.easeOut(duration: 0.18)
    /// Default cross-fade for content swaps.
    public static let crossfade = Animation.easeInOut(duration: 0.22)
    /// Spring for content lift / placement.
    public static let placement = Animation.spring(response: 0.28, dampingFraction: 0.86)
}
