//
//  ScopeDesign.swift
//  TalkieKit
//
//  Oscilloscope / lab-instrument design tokens, re-grounded on
//  usetalkie.com's cool `modern` + `slate` chassis for light mode
//  and its universal `html.dark` chassis as the reference for
//  panel surfaces. Additive: lives alongside TalkieTheme /
//  MidnightSurface, doesn't replace either.
//
//  Earlier values ported the site's warmer `:root` (cream-desk)
//  chassis and drifted further brown over time — `ScopePanel.bg`
//  in particular lifted to `#3A332A`. This pass re-grounds the
//  whole token set on the cooler chassis: neutral off-white
//  canvas, cool-slate ink, gunmetal panel bays, copper amber as
//  a sparingly-used accent.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

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

private extension Color {
    static func scopeAdaptive(light lightHex: String, dark darkHex: String) -> Color {
        #if canImport(AppKit)
        return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(scopeHex: isDark ? darkHex : lightHex)
        }))
        #else
        return Color.hex(lightHex)
        #endif
    }

    /// Adaptive color where each mode carries its own hue AND alpha. Used for
    /// hairlines/edges so dark mode can run a warmer, slightly stronger line
    /// (readable against gunmetal) while light mode stays byte-identical to
    /// the historical cool-ink-at-opacity values.
    static func scopeAdaptive(
        light lightHex: String, lightAlpha: Double,
        dark darkHex: String, darkAlpha: Double
    ) -> Color {
        #if canImport(AppKit)
        return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(scopeHex: darkHex).withAlphaComponent(darkAlpha)
                : NSColor(scopeHex: lightHex).withAlphaComponent(lightAlpha)
        }))
        #else
        return Color.hex(lightHex).opacity(lightAlpha)
        #endif
    }
}

#if canImport(AppKit)
private extension NSColor {
    convenience init(scopeHex hex: String) {
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        self.init(
            srgbRed: CGFloat((rgb & 0xFF0000) >> 16) / 255,
            green: CGFloat((rgb & 0x00FF00) >> 8) / 255,
            blue: CGFloat(rgb & 0x0000FF) / 255,
            alpha: 1
        )
    }
}
#endif

// MARK: - Surfaces

/// Page-level surfaces. Cool-neutral chassis: near-white with the
/// merest blue undertone, no warm/cream bias. Sourced from the
/// website's `modern` + `slate` variants.
///
/// The earlier cream-paper warmth read as loud and dated in dense
/// app contexts (lists, sidebars, packed panels). The cooler ladder
/// keeps the "off-white instrument cover" feel without the
/// parchment heat.
public enum ScopeCanvas {
    /// Primary page background — cool-gray page substrate from the
    /// 2026-05-21 Scope canon. Frosted instrument case; never blue.
    ///
    /// Dark mode: the deepest step of the ladder. The rest of the
    /// surface ladder (bay → card → pane → hover) is now spaced in
    /// clear, even luminance steps ABOVE this page so cards and panels
    /// read as lifted instrument surfaces rather than black-on-black.
    /// A faint blue-over-red cast keeps the gunmetal feel; never a
    /// saturated blue.
    public static let canvas = Color.scopeAdaptive(light: "F8F8F7", dark: "0E1012")
    /// "Bay" — sidebar / embedded structural surface. Lifted a clear
    /// step above the page so the sidebar reads as its own bay, no
    /// yellow. Mapped to `tacticalBackgroundSecondary` in SettingsManager.
    public static let canvasAlt = Color.scopeAdaptive(light: "ECECEB", dark: "181B1E")
    /// Raised Home panel — mirrors Studio's `SCOPE.pane` in light mode
    /// and uses an opaque gunmetal pane in dark mode. Sits above the
    /// card surface so raised panels visibly separate from the page.
    public static let pane = Color.scopeAdaptive(light: "F1F1F0", dark: "20252A")
    /// Hover lift for pane-backed rows and cards — top of the ladder.
    public static let paneHover = Color.scopeAdaptive(light: "EFEFEE", dark: "272D33")
    /// Card surface — cool neutral pane lift / mild emphasis. Now a
    /// genuine lift above canvas + bay so list cards stop sinking into
    /// the page (the old value read a touch darker than the bay).
    public static let surface = Color.scopeAdaptive(light: "EFEFEE", dark: "1C2023")
    /// 85% canvas — for floating overlays / pill chrome.
    public static let canvasOverlay = Color.scopeAdaptive(light: "F8F8F7", dark: "0E1012").opacity(0.85)
}

// MARK: - Ink (text)

/// Text hierarchy. 5 levels, each a step darker/grayer than the next.
/// Cool-neutral ladder sourced from the website's `modern` variant —
/// no warm undertone, reads as ink-on-paper rather than ink-on-tobacco.
public enum ScopeInk {
    /// Headline / primary text. Cool near-black.
    public static let primary  = Color.scopeAdaptive(light: "0F1112", dark: "F0EDE6")
    /// Subheadline / body lead.
    public static let dim      = Color.scopeAdaptive(light: "1F2123", dark: "DCD6CC")
    /// Body / paragraph — neutral slate.
    public static let muted    = Color.scopeAdaptive(light: "4D5256", dark: "B8B2A4")
    /// Secondary / captions — neutral mid. Dark step lifted slightly and
    /// de-browned so captions stay legible against the lifted card ladder
    /// without climbing into body-text territory.
    public static let faint    = Color.scopeAdaptive(light: "737878", dark: "938C7E")
    /// Tertiary / metadata — neutral light. Dark step lifted just enough
    /// that timestamps/counts read as present-but-quiet rather than lost.
    public static let subtle   = Color.scopeAdaptive(light: "9A9E9E", dark: "787163")
}

// MARK: - Edges (hairlines)

/// Hairline opacities relative to the ink color. 4 levels matching the
/// homepage edge-* tokens. Derived from the new cool ink primary so
/// hairlines no longer carry warm-brown tint.
public enum ScopeEdge {
    // Light mode keeps the cool near-black ink hairline at its historical
    // opacities. Dark mode switches to a restrained warm-taupe line, run a
    // step stronger: the old cool-white-at-8-14% edges vanished against the
    // near-black page, which is what read as "flat / floating." The warm
    // base pairs with the amber/brass accents so borders feel intentional
    // and part of the warm-instrument chrome, not an afterthought.
    private static let lightBase = "0F1112"
    private static let darkBase  = "D3C4A8"

    /// 30% — strong, framed cards.
    public static let strong  = Color.scopeAdaptive(light: lightBase, lightAlpha: 0.30, dark: darkBase, darkAlpha: 0.32)
    /// 20% — default card / row border.
    public static let normal  = Color.scopeAdaptive(light: lightBase, lightAlpha: 0.20, dark: darkBase, darkAlpha: 0.22)
    /// 14% — section divider.
    public static let faint   = Color.scopeAdaptive(light: lightBase, lightAlpha: 0.14, dark: darkBase, darkAlpha: 0.16)
    /// 8% — graticule lines, ultra-subtle dividers.
    public static let subtle  = Color.scopeAdaptive(light: lightBase, lightAlpha: 0.08, dark: darkBase, darkAlpha: 0.10)
}

// MARK: - Scope Rule — reusable hairline view
//
// Single source of truth for divider rendering across Scope surfaces.
// Calibrated to render visibly on cream-tinted panels (translucent
// white over the Home canvas). Replaces hand-rolled
// `Rectangle().fill(opacity).frame(height: 0.5)` cocktails, which
// disappeared on translucent backgrounds.
//
// The role names below map to specific visual values. Call sites use
// the role; the visual tuning happens here in one place. The role
// vocabulary is intentional — each one names where it belongs, not how
// loud it is.
//
//   .section      — strong inner break. Under panel titles, before
//                   footer links, between major subsections.
//   .row          — divider between peer rows in a list. The default.
//   .subtle       — tertiary separation where the rhythm carries the
//                   weight and the rule is just a whisper.
//   .action       — accent-tinted rule for action contexts (brass
//                   amber). The selection marker under an active tab,
//                   the leading edge of a primary-action row.
//
// For card outer borders (rounded rectangles), use the
// `.scopeCardBorder()` View modifier defined below — that's a stroke,
// not a rule, and has its own role on the page.
public struct ScopeRule: View {

    public enum Role {
        case section
        case row
        case subtle
        case action
    }

    public enum Axis { case horizontal, vertical }

    private let role: Role
    private let axis: Axis

    public init(_ role: Role = .row, axis: Axis = .horizontal) {
        self.role = role
        self.axis = axis
    }

    public var body: some View {
        Rectangle()
            .fill(color)
            .frame(
                width: axis == .vertical ? thickness : nil,
                height: axis == .horizontal ? thickness : nil
            )
    }

    private var color: Color {
        switch role {
        case .section: return ScopeInk.primary.opacity(0.22)
        case .row:     return ScopeInk.primary.opacity(0.16)
        case .subtle:  return ScopeInk.primary.opacity(0.10)
        case .action:  return ScopeBrass.solid.opacity(0.85)
        }
    }

    private var thickness: CGFloat {
        // Action rules are stronger by their accent color but
        // thinner so they read as a marker, not a heavy bar.
        role == .action ? 1.5 : 1
    }
}

// MARK: - Scope Card Border — outer border modifier
//
// For rounded card / panel outer borders. Use instead of hand-rolled
// `.overlay(RoundedRectangle(cornerRadius: r).stroke(opacity, lineWidth: w))`.
// One place to tune card-edge rendering across all surfaces.

public extension View {
    /// Standard outer border for a Scope card or panel container.
    /// Uses the same calibrated cool-ink color family as `ScopeRule`.
    func scopeCardBorder(
        cornerRadius: CGFloat = 6,
        emphasis: ScopeCardEmphasis = .normal
    ) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(emphasis.color, lineWidth: 0.5)
        )
    }
}

public enum ScopeCardEmphasis {
    /// Default container edge — visible but quiet.
    case normal
    /// Hover or focused state — reads as "this card is alive."
    case strong
    /// Disabled / dimmed state.
    case muted

    public var color: Color {
        switch self {
        case .normal: return ScopeEdge.normal
        case .strong: return ScopeEdge.strong
        case .muted:  return ScopeEdge.subtle
        }
    }
}

// MARK: - Trace (phosphor / signal line)

/// The "trace" color is the oscilloscope phosphor line. In the
/// cool-neutral chassis, it's a deep ink-charcoal rather than a vivid
/// green — the contrast is the precision, not the saturation.
public enum ScopeTrace {
    /// Solid trace — the inked signal.
    public static let solid  = Color.scopeAdaptive(light: "1F2123", dark: "DCD6CC")
    /// Glow halo around active traces.
    public static let glow   = Color.scopeAdaptive(light: "1F2123", dark: "DCD6CC").opacity(0.18)
    /// Dim trace — recently active.
    public static let dim    = Color.scopeAdaptive(light: "1F2123", dark: "DCD6CC").opacity(0.28)
    /// Faint trace — graticule, idle states.
    public static let faint  = Color.scopeAdaptive(light: "1F2123", dark: "DCD6CC").opacity(0.08)
}

// MARK: - Amber (chrome accent)

/// Amber is the "lit chrome" color — eyebrow labels, status dots,
/// pricing, accent strokes. Restored to the website's canonical
/// copper now that the canvas is cooler and amber is genuinely an
/// accent (used sparsely against a neutral ladder, it should pop).
public enum ScopeAmber {
    /// Solid amber — canonical website copper in light; nudged a touch
    /// brighter/warmer in dark so the accent lifts off the deeper gunmetal
    /// surfaces instead of muddying into them. All washes/glows derive
    /// from this base so they track the same per-mode hue.
    public static let solid = Color.scopeAdaptive(light: "C47D1C", dark: "D98A2B")
    /// 6% tint — button background washes.
    public static let tint = solid.opacity(0.06)
    /// 4% tint — even quieter background.
    public static let tintSubtle = solid.opacity(0.04)
    /// Glow halo for amber text / dots (use as shadow color).
    public static let glow = solid.opacity(0.22)
    /// Brighter glow for dots / focal points.
    public static let glowStrong = solid.opacity(0.32)
}

// MARK: - Brass (warm instrument metal)

/// Brass is the secondary warm accent against the cool Scope substrate.
/// It stays warm by canon; use it for memo/dictation metal and quieter
/// secondary action chrome when amber would be too loud.
public enum ScopeBrass {
    /// Canonical brass / memo stripe.
    public static let solid = Color.hex("9A6A22")
    /// Deep brass / pressed or shadowed metal.
    public static let deep = Color.hex("7A521A")
}

// MARK: - Kind tints

/// Per-object-kind stripes. Memo/dictation stay warm; note/capture
/// move to cool grays so the substrate does not reintroduce teal/blue.
public enum ScopeKind {
    public static let memo = Color.hex("9A6A22")
    public static let dict = Color.hex("E89A3C")
    public static let note = Color.hex("767674")
    public static let capture = Color.hex("5C5E5C")
}

// MARK: - Panel (dark instrument bay on cream desk)

/// The bichromatic move: dark panels embedded in the neutral page,
/// like an instrument bay sunk into a brushed console. Amber phosphor
/// trace on cool charcoal — gunmetal, not tobacco.
public enum ScopePanel {
    /// Panel background — warm gunmetal instrument face. Two moves over
    /// the previous cool `#14181A`:
    ///   1. LIFTED (~+6 luma) so the bay reads as a raised instrument
    ///      surface against the now-dark page. On the revised canvas
    ///      ladder the page is `#0E1012`; the old bay sat almost on top
    ///      of it and read flat/floating (the same failure the ScopeEdge
    ///      pass fixed for hairlines). It now lands in the surface/pane
    ///      luma band (canvasAlt `181B1E` → surface `1C2023`).
    ///   2. WARMED — the cast flips from "merest blue" to a restrained
    ///      warm-neutral (r≥g≥b by ~2). This is deliberate bichromatic
    ///      tension: a warm instrument face embedded in the cool console
    ///      page, which is the whole Scope premise and pairs with the
    ///      amber phosphor. It is a 2-point lean, NOT the tobacco/graphite
    ///      `#3A332A` (delta 16) that was purged — still gunmetal.
    public static let bg     = Color.hex("1A1918")
    /// Panel background — deeper recess for stat tiles, etc. Warm-neutral,
    /// a clear step below `bg` so inset tiles read as genuinely recessed.
    public static let bgAlt  = Color.hex("141312")
    /// Panel background — deepest recess (most-inset surfaces).
    public static let bgDeep = Color.hex("0D0C0B")

    /// Panel text — cool off-white against the dark.
    public static let ink       = Color.hex("E8ECEA")
    public static let inkDim    = Color.hex("C8D2CE")
    public static let inkMuted  = Color.hex("9AA8A4")
    /// Cool slate-gray for chrome labels (channel ids, status text)
    /// — reads muted on the new cool-charcoal bg without needing the
    /// brown-era luminance lift.
    public static let inkFaint  = Color.hex("7A8B85")
    /// Cool gray for secondary metadata (timestamps, model names) —
    /// subdued, not invisible.
    public static let inkSubtle = Color.hex("6B7A75")

    /// Amber phosphor trace inside dark panels.
    public static let trace      = Color.hex("E89A3C")
    public static let traceGlow  = Color.hex("E89A3C").opacity(0.50)
    public static let traceDim   = Color.hex("E89A3C").opacity(0.18)
    public static let traceFaint = Color.hex("E89A3C").opacity(0.08)

    /// Amber-phosphor edges. Nudged a step stronger across the board:
    /// against the lifted warm bay the old alphas under-read, so borders
    /// and dividers looked incidental. The bump keeps the hue (the edge
    /// is part of the lit-instrument chrome, not a neutral hairline) while
    /// giving panels intentional definition and better tonal separation.
    public enum Edge {
        public static let strong = Color.hex("E89A3C").opacity(0.28)
        public static let normal = Color.hex("E89A3C").opacity(0.18)
        public static let faint  = Color.hex("E89A3C").opacity(0.10)
        public static let subtle = Color.hex("E89A3C").opacity(0.07)
    }

    /// CRT scanline tint (very low alpha — overlay). One notch quieter
    /// than before because amber pops more against the cooler bg.
    public static let scanline = Color.hex("E89A3C").opacity(0.03)

    /// Opaque metallic-strip gradient for the panel's TOP control rail
    /// — lit-from-above brushed gunmetal cover. Stops are solid cool
    /// charcoal values (lighter at top, darker into the body) so the
    /// strip fully masks the graticule grid that runs through the rest
    /// of the panel.
    public static let stripTop = LinearGradient(
        stops: [
            // Warm gunmetal, widened highlight→shadow travel (~22 luma vs
            // the old ~16) so the cover reads as brushed metal catching
            // light from above rather than a flat tinted band.
            .init(color: Color.hex("262422"), location: 0.0),
            .init(color: Color.hex("1D1B19"), location: 0.35),
            .init(color: Color.hex("100F0E"), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Opaque metallic-strip gradient for the panel's BOTTOM rail —
    /// recessed cool feel: shadow at the top edge, gentle catch-light
    /// at the bottom. Asymmetric with `stripTop` on purpose so the two
    /// rails feel like different physical surfaces (top cover vs.
    /// bottom rail).
    public static let stripBottom = LinearGradient(
        stops: [
            // Warm gunmetal recess: shadow at the top seam, catch-light at
            // the bottom lip. Asymmetric direction vs. `stripTop` so the
            // two rails read as different fabricated pieces (top cover vs.
            // bottom sill).
            .init(color: Color.hex("0E0D0C"), location: 0.0),
            .init(color: Color.hex("1A1917"), location: 0.55),
            .init(color: Color.hex("24221F"), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Command Palette (PORCELAIN — light, sharp, instrument)

/// Light cool-gray tokens for the macOS command palette. PORCELAIN family
/// substrate — lifted enough to read as a panel above the (dimmed) app
/// behind it, with crisp dark hairlines and deep-amber accents that pop
/// against the light. Additive to the broader Scope token ladder; stays
/// scoped to the palette so global app theming is untouched.
public enum ScopePalette {
    // Substrate ladder — reconciled to the canonical cool-neutral Scope
    // canvas. The earlier PORCELAIN/PEARL/STEEL hexes carried a faint blue
    // cast that read as a separate surface next to the neutral lists and
    // chrome; these now map 1:1 onto `ScopeCanvas` so the inspector /
    // command palette sit in the same paper as everything else.
    //   bg      → ScopeCanvas.surface  (pane / base panel)
    //   bgRaised→ ScopeCanvas.canvas   (search field, footer, raised lift)
    //   bgSunk  → ScopeCanvas.canvasAlt (section-header sink)
    public static let bg = ScopeCanvas.surface          // base panel
    public static let bgRaised = ScopeCanvas.canvas      // search field, footer
    public static let bgSunk = ScopeCanvas.canvasAlt     // section header strip

    // Ink ladder — cool-neutral 0F1112 base, matches the `ScopeInk` family
    // (no warm undertone). Same opacity steps as before.
    public static let ink = ScopeInk.primary
    public static let inkFaint = ScopeInk.primary.opacity(0.62)
    public static let inkFainter = ScopeInk.primary.opacity(0.40)
    public static let inkSubtle = ScopeInk.primary.opacity(0.24)

    // Amber accent — canonical website copper (identical to
    // `ScopeAmber.solid`; `amberDeep` matches `ScopeBrass.deep`).
    public static let amber = Color.hex("C47D1C")
    public static let amberFaint = Color.hex("C47D1C").opacity(0.10)
    public static let amberSoft = Color.hex("C47D1C").opacity(0.28)
    public static let amberDeep = Color.hex("7A521A")
    public static let glyphOnAmber = Color.white

    // Rules + edges — cool-neutral 0F1112 base (matches `ScopeEdge`), so
    // hairlines read as the same crisp neutral lines used elsewhere.
    public static let edge = ScopeInk.primary.opacity(0.10)
    public static let edgeStrong = ScopeInk.primary.opacity(0.22)
    public static let rule = ScopeInk.primary.opacity(0.10)
    public static let ruleStrong = ScopeInk.primary.opacity(0.18)
}

// MARK: - Typography presets

/// Caption / instrument-label typography. Mirrors the homepage's
/// `text-[9–10px] uppercase tracking-[0.22–0.26em]` pattern.
///
/// SwiftUI tracking is in points (not em), so we use absolute values
/// at the typical 10pt size. Tracking scales with font size in
/// SwiftUI, which is fine — the visual ratio stays close.
public enum ScopeType {
    // MARK: Display (Cormorant Garamond)
    //
    // Cormorant Garamond is the homepage's `--font-display-modern`.
    // Ships with slight PostScript naming differences across builds,
    // so we try several candidates before falling back to system serif.
    // Single source of truth: don't redefine in view files.

    private static let cormorantRegularCandidates = [
        "CormorantGaramond-Regular",
        "Cormorant Garamond",
        "CormorantGaramond",
    ]
    private static let cormorantMediumCandidates = [
        "CormorantGaramond-Medium",
        "Cormorant Garamond Medium",
    ]
    private static let cormorantItalicCandidates = [
        "CormorantGaramond-Italic",
        "Cormorant Garamond Italic",
    ]

    /// Cormorant Garamond at any size + weight. Falls back to system
    /// serif when the family is missing.
    public static func display(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let candidates = (weight == .medium || weight == .semibold || weight == .bold)
            ? cormorantMediumCandidates
            : cormorantRegularCandidates
        #if canImport(AppKit)
        for name in candidates {
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
        }
        #endif
        return .system(size: size, weight: weight, design: .serif)
    }

    /// Italic display. Cormorant Italic when present, else system serif italic.
    public static func displayItalic(size: CGFloat) -> Font {
        #if canImport(AppKit)
        for name in cormorantItalicCandidates {
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
        }
        #endif
        return .system(size: size, weight: .regular, design: .serif).italic()
    }

    // MARK: Mono (JetBrains Mono)

    /// Studio's `font-mono` is JetBrains Mono. We mirror that here
    /// so the SwiftUI surfaces don't drop to SF Mono (which reads
    /// noticeably differently — wider, rounder digits). Falls back
    /// to system monospaced if the font isn't loaded.
    public static func mono(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        let candidates: [String]
        switch weight {
        case .semibold, .bold:
            candidates = ["JetBrainsMono-SemiBold", "JetBrainsMono-Medium"]
        default:
            candidates = ["JetBrainsMono-Medium", "JetBrainsMono-Regular"]
        }
        #if canImport(AppKit)
        for name in candidates {
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
        }
        #endif
        return .system(size: size, weight: weight, design: .monospaced)
    }

    /// Backwards-compatible mono(size:) — calls the weighted variant
    /// with the historical `.semibold` default.
    private static func mono(size: CGFloat) -> Font { mono(size: size, weight: .semibold) }

    /// 10pt monospaced bold caps, wide tracking — eyebrow / section label.
    public static var eyebrow: Font { mono(size: 10) }
    /// 9pt monospaced caps — channel / pin tags.
    public static var channel: Font { mono(size: 9) }
    /// 8pt monospaced — chrome footers, technical metadata.
    public static var chrome:  Font { mono(size: 8) }

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

    /// Locale-aware thousands grouping for instrument-bay stat counts.
    public static func statCount(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
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
