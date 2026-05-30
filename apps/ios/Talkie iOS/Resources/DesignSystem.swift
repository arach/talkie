//
//  DesignSystem.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI

// MARK: - Color Palette
// Inspired by Apple's precision, Vercel's boldness, Palantir's tactical UI, and Anduril's edge

extension Color {
    // Primary Brand Colors
    static let brandPrimary = Color(hex: "0A0A0A")        // Deep black
    static let brandSecondary = Color(hex: "FAFAFA")      // Pure white
    static let brandAccent = Color(hex: "0084FF")         // Vercel blue (legacy fixed brand)

    // Tactical Grays (Palantir/Anduril inspired)
    static let tactical900 = Color(hex: "0A0A0A")
    static let tactical800 = Color(hex: "1A1A1A")
    static let tactical700 = Color(hex: "2A2A2A")
    static let tactical600 = Color(hex: "3A3A3A")
    static let tactical500 = Color(hex: "6A6A6A")
    static let tactical400 = Color(hex: "9A9A9A")
    static let tactical300 = Color(hex: "CACACA")
    static let tactical200 = Color(hex: "E5E5E5")
    static let tactical100 = Color(hex: "F5F5F5")

    // Semantic Colors — universal (don't theme these)
    static let recording = Color(hex: "FF3B30")           // Apple red
    static let recordingGlow = Color(hex: "FF453A")
    static let success = Color(hex: "34C759")             // Apple green
    static let warning = Color(hex: "FF9F0A")             // Apple orange
    static let transcribing = Color(hex: "5E5CE6")        // Apple purple

    // Theme-aware chrome accents. Read directly from the configuration store
    // (not the @MainActor manager) so these are usable from any context.
    //
    // `active` / `memoAccent` map to the theme's lit accent — RARE color,
    // reserved for genuine status/live/phosphor moments (recording dot, live
    // readouts, status pills). `action` / `actionTint` map to the theme's
    // neutral affordance ink — COMMON color, used for tap target borders,
    // button outlines, and "available/enabled" states that shouldn't shout.
    static var active: Color { activeTheme.chrome.accent }
    static var activeGlow: Color { activeTheme.chrome.accentStrong }
    static var memoAccent: Color { activeTheme.chrome.accent }
    static var memoAccentGlow: Color { activeTheme.chrome.accentStrong }
    static var action: Color { activeTheme.chrome.action }
    static var actionTint: Color { activeTheme.chrome.actionTint }

    private static var activeTheme: AppTheme {
        let raw = TalkieAppConfigurationStore.shared.configuration.appearance.theme
        return AppTheme(rawValue: raw) ?? .scope
    }

    // Surface Colors (adapts to light/dark mode)
    static let surfacePrimary = Color(hex: "FFFFFF", darkHex: "0A0A0A")
    static let surfaceSecondary = Color(hex: "F5F5F5", darkHex: "1A1A1A")
    static let surfaceTertiary = Color(hex: "E5E5E5", darkHex: "2A2A2A")

    // Text Colors
    static let textPrimary = Color(hex: "0A0A0A", darkHex: "FAFAFA")
    static let textSecondary = Color(hex: "6A6A6A", darkHex: "9A9A9A")
    static let textTertiary = Color(hex: "9A9A9A", darkHex: "6A6A6A")

    // Border Colors
    static let borderPrimary = Color(hex: "E5E5E5", darkHex: "2A2A2A")
    static let borderSecondary = Color(hex: "F5F5F5", darkHex: "1A1A1A")
}

// MARK: - Color Hex Initializer
extension Color {
    init(hex: String, darkHex: String? = nil) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: // RGB
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        let lightColor = UIColor(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )

        if let darkHex = darkHex {
            let darkHexTrimmed = darkHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            var darkInt: UInt64 = 0
            Scanner(string: darkHexTrimmed).scanHexInt64(&darkInt)
            let da, dr, dg, db: UInt64
            switch darkHexTrimmed.count {
            case 6:
                (da, dr, dg, db) = (255, darkInt >> 16, darkInt >> 8 & 0xFF, darkInt & 0xFF)
            case 8:
                (da, dr, dg, db) = (darkInt >> 24, darkInt >> 16 & 0xFF, darkInt >> 8 & 0xFF, darkInt & 0xFF)
            default:
                (da, dr, dg, db) = (255, 0, 0, 0)
            }

            let darkColor = UIColor(
                red: CGFloat(dr) / 255,
                green: CGFloat(dg) / 255,
                blue: CGFloat(db) / 255,
                alpha: CGFloat(da) / 255
            )

            self.init(uiColor: UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? darkColor : lightColor
            })
        } else {
            self.init(uiColor: lightColor)
        }
    }
}

// MARK: - Typography (Tactical/Dev-Tool Oriented)
extension Font {
    // Display - More technical, less rounded
    static let displayLarge = Font.system(size: 32, weight: .bold, design: .default)
    static let displayMedium = Font.system(size: 26, weight: .bold, design: .default)
    static let displaySmall = Font.system(size: 22, weight: .semibold, design: .default)

    // Headline - Tactical
    static let headlineLarge = Font.system(size: 18, weight: .semibold, design: .default)
    static let headlineMedium = Font.system(size: 16, weight: .semibold, design: .default)
    static let headlineSmall = Font.system(size: 14, weight: .semibold, design: .default)

    // Body - Prefer monospace for dev tool feel
    static let bodyLarge = Font.system(size: 16, weight: .regular, design: .monospaced)
    static let bodyMedium = Font.system(size: 14, weight: .regular, design: .monospaced)
    static let bodySmall = Font.system(size: 12, weight: .regular, design: .monospaced)

    // Label - Compact and precise
    static let labelLarge = Font.system(size: 13, weight: .medium, design: .default)
    static let labelMedium = Font.system(size: 11, weight: .medium, design: .default)
    static let labelSmall = Font.system(size: 10, weight: .medium, design: .default)

    // Monospace (for durations, technical data) - primary choice
    static let monoLarge = Font.system(size: 16, weight: .medium, design: .monospaced)
    static let monoMedium = Font.system(size: 14, weight: .medium, design: .monospaced)
    static let monoSmall = Font.system(size: 12, weight: .regular, design: .monospaced)

    // Technical labels - uppercase, tracked
    static let techLabel = Font.system(size: 10, weight: .bold, design: .monospaced)
    static let techLabelSmall = Font.system(size: 9, weight: .bold, design: .monospaced)
}

// MARK: - Spacing (Tighter, more tactical)
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
    static let xxl: CGFloat = 40
}

// MARK: - Corner Radius
enum CornerRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let full: CGFloat = 9999
}

// MARK: - Shadow
struct TalkieShadow {
    static let small = (color: Color.black.opacity(0.05), radius: CGFloat(4), x: CGFloat(0), y: CGFloat(2))
    static let medium = (color: Color.black.opacity(0.08), radius: CGFloat(8), x: CGFloat(0), y: CGFloat(4))
    static let large = (color: Color.black.opacity(0.12), radius: CGFloat(16), x: CGFloat(0), y: CGFloat(8))
}

// MARK: - Animations
enum TalkieAnimation {
    static let fast = Animation.easeInOut(duration: 0.2)
    static let medium = Animation.easeInOut(duration: 0.3)
    static let slow = Animation.easeInOut(duration: 0.5)
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.8)
}

// MARK: - Scope Theme Tokens
//
// Modern instrument chassis: paper-white canvas + neutral graphite ink + emerald
// phosphor chrome. Mirrors usetalkie.com's `data-theme="modern"` token set so
// iOS reads as a sibling of the marketing site rather than a vintage variant.
//
// Light = white paper + near-black ink + emerald accent.
// Dark  = near-black canvas + light neutral ink + emerald phosphor.
// All tokens flip together so any view written against ScopeMobile reads correctly in either mode.

enum ScopeMobile {
    // Surfaces: page → embedded rail → card. Paper-white with a barely-there
    // warm uplift — mirrors the polish-branch's `#FBFAF7` "white paper" canvas.
    // Not pure white (cold + clinical), not cream (warm + loud); paper.
    static let canvas    = Color(hex: "FBFAF7", darkHex: "0A0907")
    static let canvasAlt = Color(hex: "F5F3EE", darkHex: "0F0D0A")
    static let surface   = Color(hex: "EFEDE7", darkHex: "1A1714")

    // Ink hierarchy (primary → subtle). Slight warm bias to pair with the
    // paper canvas — still reads as neutral graphite, not brown.
    static let ink       = Color(hex: "1A1612", darkHex: "F5F3EE")
    static let inkDim    = Color(hex: "2A221E", darkHex: "DCD8D0")
    static let inkMuted  = Color(hex: "5A5045", darkHex: "A8A096")
    static let inkFaint  = Color(hex: "7D6E5E", darkHex: "8A8276")
    static let inkSubtle = Color(hex: "A39989", darkHex: "5A5045")

    // Hairlines — fine. Matches the polish branch's ladder at 30/20/14/8% but
    // kept gentle for iOS density (we apply at 0.5pt).
    static let edgeStrong = ink.opacity(0.18)
    static let edge       = ink.opacity(0.10)
    static let edgeFaint  = ink.opacity(0.06)
    static let edgeSubtle = ink.opacity(0.03)

    // Brass-gold chrome — the lit-instrument accent. Polish-branch's soft
    // brass (`#B5823A`), warmer phosphor in dark mode (`#E89A3C`). This is
    // the "gold" half of the black-and-gold direction.
    static let amber       = Color(hex: "B5823A", darkHex: "E89A3C")
    static let amberTint   = amber.opacity(0.08)
    static let amberGlow   = amber.opacity(0.18)
    static let amberStrong = amber.opacity(0.30)

    // Trace — dark ink on paper, brass phosphor in dark. Same convention as
    // the polish branch: trace is the inked signal in light mode.
    static let trace      = Color(hex: "2A2520", darkHex: "E89A3C")
    static let traceFaint = trace.opacity(0.06)
    static let traceDim   = trace.opacity(0.18)

    // Panel — embedded "instrument bay" surface. Warm-graphite chassis (the
    // "black" half of black-and-gold) so live readouts feel like a fabricated
    // panel sitting on paper, not a paste-on UI rectangle.
    static let panel    = Color(hex: "2A221C", darkHex: "0A0807")
    static let panelAlt = Color(hex: "362C24", darkHex: "14110D")

    // Panel ink + trace — brass phosphor on warm graphite, both modes.
    static let panelInk      = Color(hex: "F0EAD8", darkHex: "F0EAD8")
    static let panelInkFaint = Color(hex: "9A8E78", darkHex: "9A8E78")
    static let panelTrace      = Color(hex: "E89A3C", darkHex: "E89A3C")
    static let panelTraceFaint = panelTrace.opacity(0.08)
    static let panelEdge       = panelTrace.opacity(0.18)
}

// MARK: - Scope Components

struct ScopeMobileGraticuleBackground: View {
    var pitch: CGFloat = 44
    var color: Color = ScopeMobile.traceFaint
    var opacity: Double = 0.42

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += pitch
            }

            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += pitch
            }

            context.stroke(path, with: .color(color), lineWidth: 1)
        }
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}

/// Small instrument-label eyebrow. Defaults to amber; pass `tint: .ink` for
/// monochrome eyebrows when amber would compete with nearby chrome.
struct ScopeMobileEyebrow: View {
    enum Tint { case amber, ink, panelInk }

    let text: String
    var tint: Tint = .amber
    var showLeadingDot: Bool = true

    private var color: Color {
        switch tint {
        case .amber:    return ScopeMobile.amber
        case .ink:      return ScopeMobile.inkFaint
        case .panelInk: return ScopeMobile.panelInkFaint
        }
    }

    var body: some View {
        Text((showLeadingDot ? "· " : "") + text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(2)
            .foregroundStyle(color)
            .shadow(color: tint == .amber ? ScopeMobile.amberGlow : .clear, radius: 4)
    }
}

/// Compact channel-code pill (S01, M, D…) — neutral by default, amber when active.
struct ScopeMobileChannelLabel: View {
    let code: String
    var isActive: Bool = false

    var body: some View {
        Text(code.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(isActive ? ScopeMobile.amber : ScopeMobile.inkFaint)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isActive ? ScopeMobile.amberTint : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(isActive ? ScopeMobile.amber.opacity(0.35) : ScopeMobile.edgeFaint, lineWidth: 0.75)
            )
    }
}

/// Phosphor status dot — amber glowing pip used for active/recording/live state.
struct ScopeMobilePhosphorDot: View {
    var diameter: CGFloat = 6
    var color: Color = ScopeMobile.amber
    var pulses: Bool = false

    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .shadow(color: color.opacity(0.55), radius: pulse ? 6 : 4)
            .scaleEffect(pulses && pulse ? 1.08 : 1)
            .onAppear {
                guard pulses else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

/// Hairline divider with optional centered tick — a quieter alternative to Divider.
struct ScopeMobileDivider: View {
    var hasTick: Bool = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(ScopeMobile.edgeFaint)
                .frame(height: 0.75)
            if hasTick {
                Rectangle()
                    .fill(ScopeMobile.amber)
                    .frame(width: 14, height: 1)
            }
        }
    }
}

/// Short signal-path connector (horizontal trace with a dot at each end).
struct ScopeMobileSignalPath: View {
    var length: CGFloat = 24

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(ScopeMobile.amber)
                .frame(width: 4, height: 4)
                .shadow(color: ScopeMobile.amberGlow, radius: 3)
            Rectangle()
                .fill(ScopeMobile.trace.opacity(0.4))
                .frame(width: length, height: 1)
            Circle()
                .stroke(ScopeMobile.amber, lineWidth: 1)
                .frame(width: 4, height: 4)
        }
    }
}

extension View {
    /// Amber phosphor glow — apply to text or icons to read as "lit chrome".
    func scopePhosphorGlow(radius: CGFloat = 4) -> some View {
        shadow(color: ScopeMobile.amberGlow, radius: radius)
    }

    /// Inset stripe — adds a top + bottom hairline pair to a row to read as a
    /// chrome strip embedded in the panel.
    func scopeInsetStripe() -> some View {
        overlay(
            VStack {
                Rectangle().fill(ScopeMobile.edgeFaint).frame(height: 0.75)
                Spacer()
                Rectangle().fill(ScopeMobile.edgeFaint).frame(height: 0.75)
            }
        )
    }
}

// MARK: - Theme-aware Chrome Tokens
//
// Every theme gets its own "instrument console" vocabulary. Scope is the cream-paper
// brass-amber version; tactical is matte hot-orange on gunmetal; ghost is vapory
// indigo on frost; midnight is glassy blue on jet. The Talkie* primitives read
// from these tokens and adapt automatically when the theme changes.

struct ChromeTokens {
    // Lit-chrome accent — RARE. Reserve for genuine status / live / phosphor
    // moments only (recording dot, status pills, LIVE bay, "PASTE-READY"
    // success indicators). Never for tap target borders or "this is available"
    // affordances — those go through `action` below.
    let accent: Color
    let accentTint: Color
    let accentGlow: Color
    let accentStrong: Color

    // Action affordance — COMMON. Neutral ink for interactive borders, button
    // outlines, "this is tappable / available / enabled" states. Quiet by
    // design; the affordance shouldn't compete with the content.
    let action: Color
    let actionTint: Color

    // Embedded console panel — strongly contrasting recessed surface
    let panel: Color
    let panelAlt: Color
    let panelInk: Color
    let panelInkFaint: Color
    let panelAccent: Color
    let panelEdge: Color

    // Active trace (signal line)
    let trace: Color
    let traceFaint: Color

    // Hairlines, derived from theme ink
    let edgeStrong: Color
    let edge: Color
    let edgeFaint: Color
    let edgeSubtle: Color

    // Per-theme style parameters that give each its distinct feeling
    let glowRadius: CGFloat       // diffuse halo size
    let chromeCorner: CGFloat     // rounding on chrome pills/labels
    let eyebrowLeader: String     // glyph before eyebrow text
    let hairlineWidth: CGFloat    // divider stroke weight
}

// MARK: Per-theme chrome instances

private let scopeChrome = ChromeTokens(
    accent: ScopeMobile.amber,
    accentTint: ScopeMobile.amberTint,
    accentGlow: ScopeMobile.amberGlow,
    accentStrong: ScopeMobile.amberStrong,
    action: ScopeMobile.ink.opacity(0.65),
    actionTint: ScopeMobile.ink.opacity(0.06),
    panel: ScopeMobile.panel,
    panelAlt: ScopeMobile.panelAlt,
    panelInk: ScopeMobile.panelInk,
    panelInkFaint: ScopeMobile.panelInkFaint,
    panelAccent: ScopeMobile.panelTrace,
    panelEdge: ScopeMobile.panelEdge,
    trace: ScopeMobile.trace,
    traceFaint: ScopeMobile.traceFaint,
    edgeStrong: ScopeMobile.edgeStrong,
    edge: ScopeMobile.edge,
    edgeFaint: ScopeMobile.edgeFaint,
    edgeSubtle: ScopeMobile.edgeSubtle,
    glowRadius: 2,
    chromeCorner: 3,
    eyebrowLeader: "·",
    hairlineWidth: 0.5
)

private let midnightChrome: ChromeTokens = {
    let accent = Color(hex: "0084FF")
    let ink = Color(hex: "FAFAFA")
    return ChromeTokens(
        accent: accent,
        accentTint: accent.opacity(0.10),
        accentGlow: accent.opacity(0.28),
        accentStrong: accent.opacity(0.42),
        action: ink.opacity(0.65),
        actionTint: ink.opacity(0.06),
        panel: Color(hex: "0F0F0F", darkHex: "000000"),
        panelAlt: Color(hex: "151515", darkHex: "070707"),
        panelInk: Color(hex: "F5F5F5"),
        panelInkFaint: Color(hex: "8A8A8A"),
        panelAccent: Color(hex: "0084FF"),
        panelEdge: Color(hex: "0084FF").opacity(0.18),
        trace: ink.opacity(0.75),
        traceFaint: ink.opacity(0.08),
        edgeStrong: ink.opacity(0.30),
        edge: ink.opacity(0.18),
        edgeFaint: ink.opacity(0.10),
        edgeSubtle: ink.opacity(0.05),
        glowRadius: 3,
        chromeCorner: 2,
        eyebrowLeader: "—",
        hairlineWidth: 0.5
    )
}()

private let tacticalChrome: ChromeTokens = {
    let accent = Color(hex: "FF8800")
    let ink = Color(hex: "F0F0F0")
    return ChromeTokens(
        accent: accent,
        accentTint: accent.opacity(0.12),
        accentGlow: accent.opacity(0.30),
        accentStrong: accent.opacity(0.50),
        action: ink.opacity(0.70),
        actionTint: ink.opacity(0.08),
        panel: Color(hex: "1A1A1A", darkHex: "000000"),
        panelAlt: Color(hex: "242424", darkHex: "0A0A0A"),
        panelInk: Color(hex: "F0F0F0"),
        panelInkFaint: Color(hex: "A0A0A0"),
        panelAccent: Color(hex: "FF9020"),
        panelEdge: Color(hex: "FF9020").opacity(0.22),
        trace: ink.opacity(0.80),
        traceFaint: ink.opacity(0.10),
        edgeStrong: ink.opacity(0.34),
        edge: ink.opacity(0.22),
        edgeFaint: ink.opacity(0.14),
        edgeSubtle: ink.opacity(0.08),
        glowRadius: 1,      // matte — barely any halo
        chromeCorner: 0,    // square corners, no rounding
        eyebrowLeader: "›",
        hairlineWidth: 1.0  // heavier hairlines
    )
}()

private let ghostChrome: ChromeTokens = {
    let accent = Color(hex: "6366F1", darkHex: "818CF8")
    let ink = Color(hex: "2A2A2A", darkHex: "E5E5E5")
    return ChromeTokens(
        accent: accent,
        accentTint: accent.opacity(0.08),
        accentGlow: accent.opacity(0.36),
        accentStrong: accent.opacity(0.50),
        action: ink.opacity(0.55),
        actionTint: ink.opacity(0.05),
        panel: Color(hex: "1E1B4B", darkHex: "0F0F23"),
        panelAlt: Color(hex: "27244F", darkHex: "16162C"),
        panelInk: Color(hex: "F0F0FA"),
        panelInkFaint: Color(hex: "9CA0C4"),
        panelAccent: Color(hex: "A5B4FC"),
        panelEdge: Color(hex: "A5B4FC").opacity(0.22),
        trace: ink.opacity(0.60),
        traceFaint: ink.opacity(0.06),
        edgeStrong: ink.opacity(0.24),
        edge: ink.opacity(0.16),
        edgeFaint: ink.opacity(0.10),
        edgeSubtle: ink.opacity(0.05),
        glowRadius: 7,      // diffuse, vapory halo
        chromeCorner: 5,    // softer rounding
        eyebrowLeader: "∘",
        hairlineWidth: 0.5
    )
}()

private let liftChrome: ChromeTokens = {
    let accent = Color(hex: "6366F1")
    let ink = Color(hex: "1A1A1A", darkHex: "FAFAFA")
    return ChromeTokens(
        accent: accent,
        accentTint: accent.opacity(0.06),
        accentGlow: accent.opacity(0.10),
        accentStrong: accent.opacity(0.32),
        action: ink.opacity(0.55),
        actionTint: ink.opacity(0.04),
        panel: Color(hex: "1E1B4B", darkHex: "0F0F23"),
        panelAlt: Color(hex: "27244F", darkHex: "16162C"),
        panelInk: Color(hex: "F0F0FA"),
        panelInkFaint: Color(hex: "9CA0C4"),
        panelAccent: Color(hex: "A5B4FC"),
        panelEdge: Color(hex: "A5B4FC").opacity(0.22),
        trace: ink.opacity(0.45),
        traceFaint: ink.opacity(0.04),
        edgeStrong: ink.opacity(0.10),
        edge: ink.opacity(0.06),
        edgeFaint: ink.opacity(0.04),
        edgeSubtle: ink.opacity(0.02),
        glowRadius: 0,
        chromeCorner: 8,
        eyebrowLeader: "·",
        hairlineWidth: 0.5
    )
}()

// Graphite: sober black-family. Slate blue-gray accent, near-zero
// halo, lightest hairlines, quiet `·` eyebrow. The accent at ~10%
// chroma vs Midnight's 100%-saturated `#0084FF` — visible enough to
// register as "the accent" without competing with the layout.
private let graphiteChrome: ChromeTokens = {
    let accent = Color(hex: "7B8E9E")
    let ink = Color(hex: "EDEDEE")
    return ChromeTokens(
        accent: accent,
        accentTint: accent.opacity(0.10),
        accentGlow: accent.opacity(0.20),
        accentStrong: accent.opacity(0.40),
        action: ink.opacity(0.65),
        actionTint: ink.opacity(0.05),
        panel: Color(hex: "18181A"),
        panelAlt: Color(hex: "1C1C1E"),
        panelInk: Color(hex: "EDEDEE"),
        panelInkFaint: Color(hex: "7E7E80"),
        panelAccent: accent,
        panelEdge: accent.opacity(0.18),
        trace: ink.opacity(0.70),
        traceFaint: ink.opacity(0.07),
        edgeStrong: ink.opacity(0.28),
        edge: ink.opacity(0.18),
        edgeFaint: ink.opacity(0.10),
        edgeSubtle: ink.opacity(0.05),
        glowRadius: 0,       // no halo
        chromeCorner: 4,
        eyebrowLeader: "·",
        hairlineWidth: 0.5
    )
}()

extension AppTheme {
    var chrome: ChromeTokens {
        switch self {
        case .scope:    return scopeChrome
        case .midnight: return midnightChrome
        case .tactical: return tacticalChrome
        case .ghost:    return ghostChrome
        case .lift:     return liftChrome
        case .graphite: return graphiteChrome
        }
    }
}

extension ThemeManager {
    var chrome: ChromeTokens { currentTheme.chrome }
}

// MARK: - Theme-aware Talkie components
//
// These primitives read from the active theme's chrome tokens. They re-render
// on theme change via @ObservedObject on the singleton manager.

/// Small instrument-label eyebrow. `.accent` = lit chrome, `.ink` = neutral, `.panelInk` = inside-panel.
struct TalkieEyebrow: View {
    enum Tint { case accent, ink, panelInk }

    let text: String
    var tint: Tint = .accent
    var showLeader: Bool = true

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome
        Text((showLeader ? "\(chrome.eyebrowLeader) " : "") + text.uppercased())
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .tracking(2)
            .foregroundStyle(color(chrome: chrome))
    }

    private func color(chrome: ChromeTokens) -> Color {
        switch tint {
        case .accent:   return chrome.accent
        case .ink:      return theme.colors.textTertiary
        case .panelInk: return chrome.panelInkFaint
        }
    }
}

/// Compact channel-code pill (S01, R02, M, D…) — neutral by default, accent when active.
struct TalkieChannelLabel: View {
    let code: String
    var isActive: Bool = false
    var onPanel: Bool = false

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome
        let foreground: Color = {
            if onPanel { return isActive ? chrome.panelAccent : chrome.panelInkFaint }
            return isActive ? chrome.accent : theme.colors.textTertiary
        }()
        let stroke: Color = {
            if onPanel { return isActive ? chrome.panelAccent.opacity(0.40) : chrome.panelEdge }
            return isActive ? chrome.accent.opacity(0.40) : chrome.edgeFaint
        }()
        let fill: Color = isActive ? chrome.accentTint : Color.clear

        Text(code.uppercased())
            .font(.system(size: 9, weight: .regular, design: .monospaced))
            .tracking(1.8)
            .foregroundStyle(foreground)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: chrome.chromeCorner, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: chrome.chromeCorner, style: .continuous)
                    .stroke(stroke, lineWidth: 0.5)
            )
    }
}

/// Phosphor-style status dot (lit chrome). Use for active / live / recording state.
struct TalkieStatusDot: View {
    var diameter: CGFloat = 6
    var pulses: Bool = false
    /// Override color (defaults to theme accent).
    var color: Color? = nil

    @ObservedObject private var theme = ThemeManager.shared
    @State private var pulse = false

    var body: some View {
        let chrome = theme.chrome
        let dotColor = color ?? chrome.accent
        Circle()
            .fill(dotColor)
            .frame(width: diameter, height: diameter)
            .shadow(color: dotColor.opacity(0.55), radius: pulse ? chrome.glowRadius + 2 : chrome.glowRadius)
            .scaleEffect(pulses && pulse ? 1.08 : 1)
            .onAppear {
                guard pulses else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

/// Hairline divider with optional centered accent tick. Quieter than Divider.
struct TalkieDivider: View {
    var hasTick: Bool = false

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome
        ZStack {
            Rectangle()
                .fill(chrome.edgeFaint)
                .frame(height: chrome.hairlineWidth)
            if hasTick {
                Rectangle()
                    .fill(chrome.accent)
                    .frame(width: 14, height: chrome.hairlineWidth + 0.25)
            }
        }
    }
}

/// Short signal-path connector (filled dot → trace → outlined dot).
struct TalkieSignalConnector: View {
    var length: CGFloat = 24

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome
        HStack(spacing: 0) {
            Circle()
                .fill(chrome.accent)
                .frame(width: 4, height: 4)
                .shadow(color: chrome.accentGlow, radius: chrome.glowRadius - 1)
            Rectangle()
                .fill(chrome.trace.opacity(0.40))
                .frame(width: length, height: chrome.hairlineWidth)
            Circle()
                .stroke(chrome.accent, lineWidth: 1)
                .frame(width: 4, height: 4)
        }
    }
}

extension View {
    /// Theme-aware accent glow. Applied to text or icons to read as "lit chrome".
    func talkieAccentGlow(radius: CGFloat? = nil) -> some View {
        modifier(TalkieAccentGlowModifier(radius: radius))
    }

    /// Inset stripe (top + bottom hairlines) — chrome strip across a row.
    func talkieInsetStripe() -> some View {
        modifier(TalkieInsetStripeModifier())
    }
}

private struct TalkieAccentGlowModifier: ViewModifier {
    let radius: CGFloat?
    @ObservedObject private var theme = ThemeManager.shared
    func body(content: Content) -> some View {
        let chrome = theme.chrome
        content.shadow(color: chrome.accentGlow, radius: radius ?? chrome.glowRadius)
    }
}

private struct TalkieInsetStripeModifier: ViewModifier {
    @ObservedObject private var theme = ThemeManager.shared
    func body(content: Content) -> some View {
        let chrome = theme.chrome
        content.overlay(
            VStack {
                Rectangle().fill(chrome.edgeFaint).frame(height: chrome.hairlineWidth)
                Spacer()
                Rectangle().fill(chrome.edgeFaint).frame(height: chrome.hairlineWidth)
            }
        )
    }
}

// MARK: - Higher-level Talkie components
//
// These crystallize patterns that recurred while threading the chrome system
// through the app: section headers, status pills, empty states, and the
// standard themed card chrome. Each component composes the lower-level
// primitives (Eyebrow / StatusDot / Divider) so callers can express intent
// without re-wiring the chrome each time.

/// Eyebrow-headed section. Replaces the manual
/// `VStack { TalkieEyebrow(...); content }` pattern that appears everywhere.
struct TalkieSection<Content: View>: View {
    let eyebrow: String
    var trailing: AnyView? = nil
    @ViewBuilder var content: () -> Content

    init(_ eyebrow: String, @ViewBuilder content: @escaping () -> Content) {
        self.eyebrow = eyebrow
        self.trailing = nil
        self.content = content
    }

    init<Trailing: View>(
        _ eyebrow: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.eyebrow = eyebrow
        self.trailing = AnyView(trailing())
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                TalkieEyebrow(text: eyebrow)
                if trailing != nil {
                    Spacer()
                    trailing
                }
            }
            content()
        }
    }
}

/// Themed status badge — small phosphor dot + uppercase label in a capsule.
/// Default style picks up the theme accent; semantic styles stay universal.
struct TalkieStatusBadge: View {
    enum Style {
        case accent          // theme chrome accent (Ready / Live / Active / Saved)
        case recording       // universal red (REC)
        case success         // universal green (DONE / SYNCED)
        case warning         // universal orange (WARN / OFFLINE)
        case transcribing    // universal purple (TRANSCRIBING)
        case ink             // quiet neutral (PENDING / WAITING)
    }

    let label: String
    var style: Style = .accent
    var pulses: Bool = false
    /// When true, drops the capsule background — for tight inline contexts.
    var bare: Bool = false

    @ObservedObject private var theme = ThemeManager.shared

    private var color: Color {
        switch style {
        case .accent:       return theme.chrome.accent
        case .recording:    return .recording
        case .success:      return .success
        case .warning:      return .warning
        case .transcribing: return .transcribing
        case .ink:          return theme.colors.textTertiary
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            TalkieStatusDot(diameter: 4, pulses: pulses, color: color)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(color)
        }
        .padding(.horizontal, bare ? 0 : 6)
        .padding(.vertical, bare ? 0 : 3)
        .background(
            Group {
                if !bare {
                    Capsule().fill(color.opacity(0.08))
                }
            }
        )
    }
}

/// Empty-state pattern — pulsing status dot + eyebrow + icon + title + message.
/// All slots are optional except `icon` + `title` so callers can compose the
/// variant they need without juggling private structs.
struct TalkieEmptyState<Action: View>: View {
    let icon: String
    let title: String
    var status: String? = nil       // optional pulsing eyebrow above the icon
    var message: String? = nil      // optional body copy
    var action: () -> Action?       // optional CTA below

    @ObservedObject private var theme = ThemeManager.shared

    init(
        icon: String,
        title: String,
        status: String? = nil,
        message: String? = nil,
        @ViewBuilder action: @escaping () -> Action
    ) {
        self.icon = icon
        self.title = title
        self.status = status
        self.message = message
        self.action = action
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            if let status {
                HStack(spacing: 6) {
                    TalkieStatusDot(diameter: 5, pulses: true)
                    TalkieEyebrow(text: status, showLeader: false)
                }
            }

            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(theme.colors.textTertiary)

            TalkieEyebrow(text: title, tint: .ink, showLeader: false)

            if let message {
                Text(message)
                    .font(.bodySmall)
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            action()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }
}

extension TalkieEmptyState where Action == EmptyView {
    /// No-CTA variant.
    init(icon: String, title: String, status: String? = nil, message: String? = nil) {
        self.init(icon: icon, title: title, status: status, message: message) { EmptyView() }
    }
}

extension View {
    /// The quiet sibling of `.bezelChassis()` — just a hairline against the
    /// canvas, no drop shadow, no presence. The *paper* surface to `bezelChassis`'s
    /// *instrument* surface. Use for the everyday card / panel / row where the
    /// surface should sit on the canvas without lifting off it.
    ///
    /// `emphasis` controls the stroke weight: `.subtle` (3% ink, barely there),
    /// `.faint` (6%, default), `.edge` (10%, framed), `.accent` (brass).
    func softCard(
        padding: CGFloat = Spacing.md,
        corner: CGFloat = CornerRadius.sm,
        emphasis: SoftCardEmphasis = .faint,
        fill: Color? = nil
    ) -> some View {
        modifier(SoftCardModifier(padding: padding, corner: corner, emphasis: emphasis, fill: fill))
    }

    /// The single most-recurring polish move from the marketing site, in iOS
    /// idiom: a 0.5pt edgeFaint stroke on the top edge only, with a 1px white
    /// highlight just inside the top. Reads as "this surface has a fabricated
    /// top edge" without ever competing for attention. Apply liberally — it's
    /// the cleanse-and-lightness signature.
    func hairlineEmphasis(corner: CGFloat = CornerRadius.sm) -> some View {
        modifier(HairlineEmphasisModifier(corner: corner))
    }

    /// The tap-lift micro-interaction. On press: 1% scale down, 1pt y-offset,
    /// shadow softens. On release: spring back. Apply to any tappable surface
    /// (CaptureCard, action tiles, settings rows) so touches feel like the
    /// surface acknowledges them. Don't apply to native Buttons that already
    /// have their own press behavior — use on plain views with onTapGesture.
    func softLift(isPressed: Bool) -> some View {
        modifier(SoftLiftModifier(isPressed: isPressed))
    }

    /// Marketing-site bezel chassis — 1px hairline + composite drop shadow.
    /// Mirrors usetalkie.com's `--panel-chassis-shadow` formula (top highlight
    /// inset, two outer drops), calibrated for iOS density. The standard card
    /// surface across the app.
    func bezelChassis(
        padding: CGFloat = Spacing.md,
        corner: CGFloat = CornerRadius.sm,
        accent: Bool = false,
        fill: Color? = nil
    ) -> some View {
        modifier(BezelChassisModifier(padding: padding, corner: corner, accent: accent, fill: fill))
    }

    /// Always-dark CRT bezel — recessed glass on the panel surface. Use only
    /// on live instrument-display surfaces (waveform, recording indicator);
    /// the deliberate "lit screen" moment that quotes the macOS/website bay.
    func screenRecess(
        padding: CGFloat = Spacing.md,
        corner: CGFloat = CornerRadius.sm
    ) -> some View {
        modifier(ScreenRecessModifier(padding: padding, corner: corner))
    }

    /// Standard themed card chrome. Now routes through `bezelChassis` so every
    /// existing callsite picks up the composite-shadow polish.
    func talkieCard(padding: CGFloat = Spacing.md, corner: CGFloat = CornerRadius.md) -> some View {
        bezelChassis(padding: padding, corner: corner, accent: false)
    }

    /// Accent-bordered variant — same bezel, accent-tinted edge.
    func talkieAccentCard(padding: CGFloat = Spacing.md, corner: CGFloat = CornerRadius.md) -> some View {
        bezelChassis(padding: padding, corner: corner, accent: true)
    }
}

enum SoftCardEmphasis {
    case subtle, faint, edge, accent
}

private struct SoftCardModifier: ViewModifier {
    let padding: CGFloat
    let corner: CGFloat
    let emphasis: SoftCardEmphasis
    let fill: Color?

    @ObservedObject private var theme = ThemeManager.shared

    func body(content: Content) -> some View {
        let chrome = theme.chrome
        let stroke: Color = {
            switch emphasis {
            case .subtle: return chrome.edgeSubtle
            case .faint:  return chrome.edgeFaint
            case .edge:   return chrome.edge
            case .accent: return chrome.accent.opacity(0.35)
            }
        }()
        let bg = fill ?? theme.colors.cardBackground
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return content
            .padding(padding)
            .background(bg)
            .clipShape(shape)
            .overlay {
                shape.stroke(stroke, lineWidth: chrome.hairlineWidth)
            }
    }
}

private struct HairlineEmphasisModifier: ViewModifier {
    let corner: CGFloat

    @ObservedObject private var theme = ThemeManager.shared

    func body(content: Content) -> some View {
        let chrome = theme.chrome
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return content
            .overlay(alignment: .top) {
                // 1px white inner highlight — the "fabricated top edge" cue.
                // Sits just inside the corner radius via shape mask.
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                    .blendMode(.plusLighter)
                    .mask(shape)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(chrome.edgeFaint)
                    .frame(height: 0.5)
                    .mask(shape)
                    .allowsHitTesting(false)
            }
    }
}

private struct SoftLiftModifier: ViewModifier {
    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.99 : 1)
            .offset(y: isPressed ? 1 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.85), value: isPressed)
    }
}

private struct BezelChassisModifier: ViewModifier {
    let padding: CGFloat
    let corner: CGFloat
    let accent: Bool
    let fill: Color?

    @ObservedObject private var theme = ThemeManager.shared

    func body(content: Content) -> some View {
        let chrome = theme.chrome
        let stroke: Color = accent ? chrome.accent.opacity(0.40) : chrome.edgeFaint
        let bg = fill ?? theme.colors.cardBackground
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return content
            .padding(padding)
            .background(bg)
            .overlay(alignment: .top) {
                // Inner top highlight — fabricated-edge cue. Masked to the
                // shape so the corners stay clean.
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                    .blendMode(.plusLighter)
                    .mask(shape)
                    .allowsHitTesting(false)
            }
            .clipShape(shape)
            .overlay {
                shape.stroke(stroke, lineWidth: chrome.hairlineWidth)
            }
            .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 8)
    }
}

private struct ScreenRecessModifier: ViewModifier {
    let padding: CGFloat
    let corner: CGFloat

    @ObservedObject private var theme = ThemeManager.shared

    func body(content: Content) -> some View {
        let chrome = theme.chrome
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return content
            .padding(padding)
            .background(chrome.panel)
            .overlay(alignment: .top) {
                // Recessed-glass vignette: light dark gradient at the top edge.
                // Kept gentle — the recess should suggest depth, not shout it.
                LinearGradient(
                    colors: [Color.black.opacity(0.22), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 6)
                .allowsHitTesting(false)
            }
            .clipShape(shape)
            .overlay {
                shape.stroke(Color.black.opacity(0.14), lineWidth: 0.5)
            }
    }
}

/// Channel-prefixed row — small `S01` channel label, vertically separated
/// content, optional trailing status. Generalizes the row pattern used in
/// applied revisions, captures, sidecars, and version history.
struct TalkieRow<Content: View, Trailing: View>: View {
    let channel: String?
    let isChannelActive: Bool
    @ViewBuilder var content: () -> Content
    @ViewBuilder var trailing: () -> Trailing

    init(
        channel: String? = nil,
        isChannelActive: Bool = false,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.channel = channel
        self.isChannelActive = isChannelActive
        self.content = content
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            if let channel {
                TalkieChannelLabel(code: channel, isActive: isChannelActive)
                    .padding(.top, 1)
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
    }
}

extension TalkieRow where Trailing == EmptyView {
    init(
        channel: String? = nil,
        isChannelActive: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(channel: channel, isChannelActive: isChannelActive, content: content) { EmptyView() }
    }
}

// MARK: - Marketing-site chrome grammar
//
// Two label primitives mirroring usetalkie.com's chrome treatment:
// `· INPUT · COMPUTER · JACK 01` mid-dot chains and `← 01 / STARTING POINTS`
// preheaders. SF Mono only — system fonts render best on iPhone, so we don't
// bring in Cormorant or any custom face here. Hierarchy comes from register
// (mono / uppercase / tracking) and ink opacity, not weight.

/// Mid-dot chrome chain — `· INPUT · COMPUTER · JACK 01`. Variadic; each
/// segment is uppercased and joined by ` · `. Optional leading dot. Used on
/// jack labels, card heads, bottom rails — anything that wants to read as
/// instrument chrome rather than copy.
struct ChromeLabel: View {
    let segments: [String]
    var showLeader: Bool
    var tint: Color?

    @ObservedObject private var theme = ThemeManager.shared

    init(_ segments: String..., showLeader: Bool = true, tint: Color? = nil) {
        self.segments = segments
        self.showLeader = showLeader
        self.tint = tint
    }

    init(segments: [String], showLeader: Bool = true, tint: Color? = nil) {
        self.segments = segments
        self.showLeader = showLeader
        self.tint = tint
    }

    var body: some View {
        let parts = segments.map { $0.uppercased() }.joined(separator: " · ")
        let text = showLeader ? "· " + parts : parts
        Text(text)
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .tracking(2)
            .foregroundStyle(tint ?? theme.colors.textTertiary)
    }
}

/// Section preheader — `← 01 / STARTING POINTS`. Used to mark major content
/// breaks in scrollable views (Workflows, Step Library, etc.). The number is
/// optional; omit it for a label-only preheader.
struct SectionPreheader: View {
    let label: String
    let number: String?

    @ObservedObject private var theme = ThemeManager.shared

    init(_ label: String, number: String? = nil) {
        self.label = label
        self.number = number
    }

    var body: some View {
        let body: String = {
            if let number {
                return "← \(number) / \(label.uppercased())"
            }
            return "← \(label.uppercased())"
        }()
        Text(body)
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .tracking(2)
            .foregroundStyle(theme.colors.textTertiary)
    }
}
