//
//  WatchDesign.swift
//  TalkieWatch
//
//  Watch-local mirror of the iOS Talkie design system. Sized for 162-205pt
//  screens. The Watch target compiles separately from iOS, so we cannot share
//  `DesignSystem.swift` directly — instead we re-declare a small subset of the
//  same vocabulary here using identical hex values so the watch reads as
//  parallel chrome.
//

import SwiftUI

// MARK: - Hex Color Init (Watch-local)
//
// Watch target uses UIColor too (watchOS). Mirrors iOS hex initializer but
// trimmed to what the watch needs. Light/dark via traitCollection.

extension Color {
    /// watchOS hex initializer. watchOS uses a permanently dark color scheme,
    /// so when a `darkHex` variant is supplied we always use that.
    init(watchHex hex: String, darkHex: String? = nil) {
        let chosen = darkHex ?? hex
        let trimmed = chosen.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch trimmed.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Watch Chrome Tokens
//
// Per-theme "instrument console" vocabulary, mirrored from iOS ChromeTokens but
// sized for the watch. All hex values match iOS so the watch reads as a
// peripheral of the same console (see apps/ios/Talkie iOS/Resources/DesignSystem.swift).

struct WatchChromeTokens {
    // Lit-chrome accent — the theme's signature color
    let accent: Color
    let accentTint: Color
    let accentGlow: Color
    let accentStrong: Color

    // Embedded console panel — recessed contrasting surface
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

/// Stroke weights for the capture face's nested edges, as one ladder.
///
/// The key and the pill read as members of the same set because their rings
/// share a scale. Keeping the weights together means "a little thinner" is one
/// edit rather than four literals drifting apart across two files.
enum WatchEdgeWeight {
    /// The bevel that gives a key its silhouette — the heaviest edge on the
    /// face, and the only one that has to survive against a drop shadow.
    static let bevel: CGFloat = 0.75

    /// An outline on the chassis rather than a body raised off it: the pill.
    static let outline: CGFloat = 0.6

    /// The theme hairline. 0.5pt is exactly one pixel at 2x, so this is as thin
    /// as the watch draws before a line stops being a line and starts being grey.
    static let hairline: CGFloat = 0.5
}

/// The capture face intentionally has only two material families. Theme
/// personality comes from the signal color, not a full-screen color wash.
enum WatchCaptureMaterial: Equatable {
    case lightMineral
    case blackCeramic

    var field: Color {
        switch self {
        case .lightMineral: Color(watchHex: "E8EAEC")
        case .blackCeramic: Color(watchHex: "050505")
        }
    }

    var fieldLift: Color {
        switch self {
        case .lightMineral: Color(watchHex: "FAFAF7")
        case .blackCeramic: Color(watchHex: "171717")
        }
    }

    var fieldShade: Color {
        switch self {
        case .lightMineral: Color(watchHex: "D4D7D9")
        case .blackCeramic: Color(watchHex: "000000")
        }
    }

    var ink: Color {
        switch self {
        case .lightMineral: Color(watchHex: "1A2026")
        case .blackCeramic: Color(watchHex: "E8E2D9")
        }
    }

    var inkFaint: Color {
        switch self {
        case .lightMineral: Color(watchHex: "67717A")
        case .blackCeramic: Color(watchHex: "8B8883")
        }
    }

    var keyTop: Color {
        switch self {
        case .lightMineral: Color(watchHex: "FDFDF9")
        case .blackCeramic: Color(watchHex: "1C1C1C")
        }
    }

    var keyMiddle: Color {
        switch self {
        case .lightMineral: Color(watchHex: "E9EAE5")
        case .blackCeramic: Color(watchHex: "0D0D0D")
        }
    }

    var keyBottom: Color {
        switch self {
        case .lightMineral: Color(watchHex: "C5C8C9")
        case .blackCeramic: Color(watchHex: "020202")
        }
    }

    var keyInk: Color {
        switch self {
        case .lightMineral: Color(watchHex: "222A31")
        case .blackCeramic: Color(watchHex: "D9D4CC")
        }
    }

    /// Top-leading edge of a raised key — the side the chassis light falls on.
    /// Light mineral gets a soft dark contour instead of a highlight: the key
    /// top is already near-white, so there is nothing left to light.
    var keyEdge: Color {
        switch self {
        case .lightMineral: Color.black.opacity(0.10)
        case .blackCeramic: Color.white.opacity(0.20)
        }
    }

    /// Bottom-trailing edge. On both materials the key bottom and the field
    /// sit within a few values of each other, so without a distinct lower edge
    /// the key's silhouette dissolves into the chassis it rests on.
    var keyEdgeLow: Color {
        switch self {
        case .lightMineral: Color.black.opacity(0.26)
        case .blackCeramic: Color.white.opacity(0.05)
        }
    }

    /// The key's bevel as one stroke style, lit on the same diagonal as the
    /// key fill and the chassis gradient beneath it.
    var keyEdgeRing: LinearGradient {
        LinearGradient(
            colors: [keyEdge, keyEdgeLow],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var secondaryFill: Color {
        switch self {
        case .lightMineral: Color.white.opacity(0.30)
        case .blackCeramic: Color.white.opacity(0.035)
        }
    }

    var secondaryEdge: Color {
        switch self {
        case .lightMineral: Color.black.opacity(0.13)
        case .blackCeramic: Color.white.opacity(0.13)
        }
    }

    var shadow: Color {
        switch self {
        case .lightMineral: Color.black.opacity(0.30)
        case .blackCeramic: Color.black.opacity(0.78)
        }
    }
}

struct WatchCaptureStyle {
    let material: WatchCaptureMaterial
    let trace: Color

    /// A quiet theme-colored reflection in the chassis. This keeps the two
    /// primary materials intact while preserving the selected Talkie theme's
    /// signal identity.
    var atmosphere: Color {
        trace.opacity(material == .blackCeramic ? 0.085 : 0.035)
    }

    var keyAccentEdge: Color {
        trace.opacity(material == .blackCeramic ? 0.18 : 0.10)
    }

    var secondaryAccentEdge: Color {
        trace.opacity(material == .blackCeramic ? 0.24 : 0.12)
    }
}

// MARK: Per-theme chrome instances (hex values match iOS DesignSystem.swift)

private let watchScopeChrome: WatchChromeTokens = {
    let ink = Color(watchHex: "1A1612", darkHex: "F0EAD8")
    let amber = Color(watchHex: "C47D1C", darkHex: "E89A3C")
    let trace = Color(watchHex: "2A2520", darkHex: "E89A3C")
    let panelTrace = Color(watchHex: "E89A3C", darkHex: "E89A3C")
    return WatchChromeTokens(
        accent: amber,
        accentTint: amber.opacity(0.08),
        accentGlow: amber.opacity(0.32),
        accentStrong: amber.opacity(0.45),
        panel: Color(watchHex: "1C1814", darkHex: "0A0807"),
        panelAlt: Color(watchHex: "221D18", darkHex: "14110D"),
        panelInk: Color(watchHex: "F0EAD8", darkHex: "F0EAD8"),
        panelInkFaint: Color(watchHex: "80786A", darkHex: "80786A"),
        panelAccent: panelTrace,
        panelEdge: panelTrace.opacity(0.15),
        trace: trace,
        traceFaint: trace.opacity(0.08),
        edgeStrong: ink.opacity(0.30),
        edge: ink.opacity(0.20),
        edgeFaint: ink.opacity(0.14),
        edgeSubtle: ink.opacity(0.08),
        glowRadius: 3,           // 1pt tighter than iOS
        chromeCorner: 3,
        eyebrowLeader: "·",
        hairlineWidth: 0.5       // hairline 0.5pt for watch
    )
}()

/// The default Watch treatment: the same deep-navy instrument bay and cobalt
/// signal used by iOS Porcelain. Unlike Scope, this keeps the small screen to
/// one interaction color and lets semantic red/green states carry meaning.
private let watchPorcelainChrome: WatchChromeTokens = {
    let accent = Color(watchHex: "2F63D8", darkHex: "78A6FF")
    let ink = Color(watchHex: "162330", darkHex: "F3F7FC")
    let panelInk = Color(watchHex: "F3F7FC")
    return WatchChromeTokens(
        accent: accent,
        accentTint: accent.opacity(0.10),
        accentGlow: accent.opacity(0.24),
        accentStrong: accent.opacity(0.40),
        panel: Color(watchHex: "0B1320"),
        panelAlt: Color(watchHex: "142238"),
        panelInk: panelInk,
        panelInkFaint: Color(watchHex: "9DAFC4"),
        panelAccent: accent,
        panelEdge: accent.opacity(0.18),
        trace: accent,
        traceFaint: accent.opacity(0.08),
        edgeStrong: panelInk.opacity(0.28),
        edge: panelInk.opacity(0.18),
        edgeFaint: panelInk.opacity(0.12),
        edgeSubtle: panelInk.opacity(0.06),
        glowRadius: 2,
        chromeCorner: 7,
        eyebrowLeader: "·",
        hairlineWidth: 0.5
    )
}()

private let watchMineralChrome: WatchChromeTokens = {
    let accent = Color(watchHex: "9B4E27", darkHex: "DF8955")
    let ink = Color(watchHex: "18353B", darkHex: "EAF0EC")
    return WatchChromeTokens(
        accent: accent,
        accentTint: accent.opacity(0.10),
        accentGlow: accent.opacity(0.16),
        accentStrong: accent.opacity(0.34),
        panel: Color(watchHex: "1C3034", darkHex: "0F1B1E"),
        panelAlt: Color(watchHex: "263C40", darkHex: "17272A"),
        panelInk: Color(watchHex: "EEF1EA"),
        panelInkFaint: Color(watchHex: "AAB7B2"),
        panelAccent: Color(watchHex: "D27A46"),
        panelEdge: Color(watchHex: "D27A46").opacity(0.24),
        trace: Color(watchHex: "29484E", darkHex: "D67B48"),
        traceFaint: Color(watchHex: "D67B48").opacity(0.10),
        edgeStrong: ink.opacity(0.26),
        edge: ink.opacity(0.17),
        edgeFaint: ink.opacity(0.10),
        edgeSubtle: ink.opacity(0.05),
        glowRadius: 1,
        chromeCorner: 4,
        eyebrowLeader: "·",
        hairlineWidth: 0.75
    )
}()

private let watchMidnightChrome: WatchChromeTokens = {
    let accent = Color(watchHex: "0070F3", darkHex: "0084FF")
    let ink = Color(watchHex: "0A0A0A", darkHex: "FAFAFA")
    return WatchChromeTokens(
        accent: accent,
        accentTint: accent.opacity(0.10),
        accentGlow: accent.opacity(0.28),
        accentStrong: accent.opacity(0.42),
        panel: Color(watchHex: "0F0F0F", darkHex: "000000"),
        panelAlt: Color(watchHex: "151515", darkHex: "070707"),
        panelInk: Color(watchHex: "F5F5F5"),
        panelInkFaint: Color(watchHex: "8A8A8A"),
        panelAccent: Color(watchHex: "0084FF"),
        panelEdge: Color(watchHex: "0084FF").opacity(0.18),
        trace: ink.opacity(0.75),
        traceFaint: ink.opacity(0.08),
        edgeStrong: ink.opacity(0.30),
        edge: ink.opacity(0.18),
        edgeFaint: ink.opacity(0.10),
        edgeSubtle: ink.opacity(0.05),
        glowRadius: 2,
        chromeCorner: 2,
        eyebrowLeader: "—",
        hairlineWidth: 0.5
    )
}()

private let watchTacticalChrome: WatchChromeTokens = {
    let accent = Color(watchHex: "FF6B00", darkHex: "FF8800")
    let ink = Color(watchHex: "1A1A1A", darkHex: "F0F0F0")
    return WatchChromeTokens(
        accent: accent,
        accentTint: accent.opacity(0.12),
        accentGlow: accent.opacity(0.30),
        accentStrong: accent.opacity(0.50),
        panel: Color(watchHex: "1A1A1A", darkHex: "000000"),
        panelAlt: Color(watchHex: "242424", darkHex: "0A0A0A"),
        panelInk: Color(watchHex: "F0F0F0"),
        panelInkFaint: Color(watchHex: "A0A0A0"),
        panelAccent: Color(watchHex: "FF9020"),
        panelEdge: Color(watchHex: "FF9020").opacity(0.22),
        trace: ink.opacity(0.80),
        traceFaint: ink.opacity(0.10),
        edgeStrong: ink.opacity(0.34),
        edge: ink.opacity(0.22),
        edgeFaint: ink.opacity(0.14),
        edgeSubtle: ink.opacity(0.08),
        glowRadius: 1,           // matte — no halo
        chromeCorner: 0,         // square corners
        eyebrowLeader: "›",
        hairlineWidth: 0.75      // heavier hairlines, still watch-sized
    )
}()

private let watchGhostChrome: WatchChromeTokens = {
    let accent = Color(watchHex: "6366F1", darkHex: "818CF8")
    let ink = Color(watchHex: "2A2A2A", darkHex: "E5E5E5")
    return WatchChromeTokens(
        accent: accent,
        accentTint: accent.opacity(0.08),
        accentGlow: accent.opacity(0.36),
        accentStrong: accent.opacity(0.50),
        panel: Color(watchHex: "1E1B4B", darkHex: "0F0F23"),
        panelAlt: Color(watchHex: "27244F", darkHex: "16162C"),
        panelInk: Color(watchHex: "F0F0FA"),
        panelInkFaint: Color(watchHex: "9CA0C4"),
        panelAccent: Color(watchHex: "A5B4FC"),
        panelEdge: Color(watchHex: "A5B4FC").opacity(0.22),
        trace: ink.opacity(0.60),
        traceFaint: ink.opacity(0.06),
        edgeStrong: ink.opacity(0.24),
        edge: ink.opacity(0.16),
        edgeFaint: ink.opacity(0.10),
        edgeSubtle: ink.opacity(0.05),
        glowRadius: 5,           // diffuse but tighter for small screen
        chromeCorner: 5,
        eyebrowLeader: "∘",
        hairlineWidth: 0.5
    )
}()

private let watchLiftChrome: WatchChromeTokens = {
    let accent = Color(watchHex: "6366F1")
    let ink = Color(watchHex: "1A1A1A", darkHex: "FAFAFA")
    return WatchChromeTokens(
        accent: accent,
        accentTint: accent.opacity(0.06),
        accentGlow: accent.opacity(0.10),
        accentStrong: accent.opacity(0.32),
        panel: Color(watchHex: "0F0F23"),
        panelAlt: Color(watchHex: "16162C"),
        panelInk: Color(watchHex: "F0F0FA"),
        panelInkFaint: Color(watchHex: "9CA0C4"),
        panelAccent: Color(watchHex: "A5B4FC"),
        panelEdge: Color(watchHex: "A5B4FC").opacity(0.22),
        trace: ink.opacity(0.45),
        traceFaint: ink.opacity(0.04),
        edgeStrong: ink.opacity(0.14),
        edge: ink.opacity(0.10),
        edgeFaint: ink.opacity(0.07),
        edgeSubtle: ink.opacity(0.03),
        glowRadius: 0,
        chromeCorner: 8,
        eyebrowLeader: "·",
        hairlineWidth: 0.5
    )
}()

private let watchGraphiteChrome: WatchChromeTokens = {
    let ink = Color(watchHex: "EDEDED")
    return WatchChromeTokens(
        accent: Color(watchHex: "FAFAFA"),
        accentTint: Color.white.opacity(0.10),
        accentGlow: .clear,
        accentStrong: Color.white.opacity(0.22),
        panel: Color(watchHex: "0E0E0E"),
        panelAlt: Color(watchHex: "171717"),
        panelInk: ink,
        panelInkFaint: Color(watchHex: "8F8F8F"),
        panelAccent: Color(watchHex: "FAFAFA"),
        panelEdge: ink.opacity(0.18),
        trace: ink.opacity(0.75),
        traceFaint: ink.opacity(0.10),
        edgeStrong: ink.opacity(0.30),
        edge: ink.opacity(0.20),
        edgeFaint: ink.opacity(0.14),
        edgeSubtle: ink.opacity(0.08),
        glowRadius: 0,
        chromeCorner: 6,
        eyebrowLeader: "·",
        hairlineWidth: 1
    )
}()

private let watchCarbonChrome: WatchChromeTokens = {
    let signal = Color(watchHex: "3DE08A")
    let ink = Color(watchHex: "FAFAFA")
    return WatchChromeTokens(
        accent: signal,
        accentTint: signal.opacity(0.10),
        accentGlow: signal.opacity(0.22),
        accentStrong: signal.opacity(0.40),
        panel: .black,
        panelAlt: Color(watchHex: "070707"),
        panelInk: ink,
        panelInkFaint: Color(watchHex: "8A8A8A"),
        panelAccent: signal,
        panelEdge: signal.opacity(0.20),
        trace: ink.opacity(0.80),
        traceFaint: ink.opacity(0.10),
        edgeStrong: Color.white.opacity(0.36),
        edge: Color.white.opacity(0.26),
        edgeFaint: Color.white.opacity(0.19),
        edgeSubtle: Color.white.opacity(0.11),
        glowRadius: 2,
        chromeCorner: 1,
        eyebrowLeader: "›",
        hairlineWidth: 1
    )
}()

// Ember on the wrist. The watch is always a dark surface, so this is the
// dark half of the phone's palette with no light counterpart to reconcile.
private let watchEmberChrome: WatchChromeTokens = {
    let signal = Color(watchHex: "D98C2B")
    let ink = Color(watchHex: "F4F1EA")
    return WatchChromeTokens(
        accent: signal,
        accentTint: signal.opacity(0.10),
        accentGlow: signal.opacity(0.22),
        accentStrong: signal.opacity(0.40),
        panel: Color(watchHex: "121109"),
        panelAlt: Color(watchHex: "1C1A13"),
        panelInk: Color(watchHex: "F6F2E8"),
        panelInkFaint: Color(watchHex: "A79E8C"),
        panelAccent: Color(watchHex: "E2A046"),
        panelEdge: signal.opacity(0.26),
        trace: ink.opacity(0.80),
        traceFaint: ink.opacity(0.10),
        edgeStrong: Color.white.opacity(0.34),
        edge: Color.white.opacity(0.24),
        edgeFaint: Color.white.opacity(0.17),
        edgeSubtle: Color.white.opacity(0.10),
        glowRadius: 3,
        chromeCorner: 4,
        eyebrowLeader: "·",
        hairlineWidth: 1
    )
}()

// Matte on the wrist: the dark half of the phone's palette. The watch is
// always a black surface, so the mode-awareness that makes Matte unusual on
// the phone has nothing to do here — what carries over is the absence of
// warmth and the single blue.
private let watchMatteChrome: WatchChromeTokens = {
    let signal = Color(watchHex: "7FB0FF")
    let ink = Color(watchHex: "F7F7F7")
    return WatchChromeTokens(
        accent: signal,
        accentTint: signal.opacity(0.08),
        accentGlow: signal.opacity(0.18),
        accentStrong: signal.opacity(0.36),
        panel: Color(watchHex: "151515"),
        panelAlt: Color(watchHex: "1C1C1C"),
        panelInk: Color(watchHex: "F7F7F7"),
        panelInkFaint: Color(watchHex: "A8A8A8"),
        panelAccent: signal,
        panelEdge: signal.opacity(0.26),
        trace: ink.opacity(0.82),
        traceFaint: ink.opacity(0.10),
        edgeStrong: Color.white.opacity(0.34),
        edge: Color.white.opacity(0.24),
        edgeFaint: Color.white.opacity(0.17),
        edgeSubtle: Color.white.opacity(0.10),
        glowRadius: 0,
        chromeCorner: 6,
        eyebrowLeader: "\u{00B7}",
        hairlineWidth: 1
    )
}()

// MARK: - Active Theme Resolver
//
// The phone publishes the selected theme through WatchConnectivity and the
// Watch persists that last-known value locally. App Groups do not synchronize
// defaults between separate iPhone and Watch devices.

enum WatchThemeName: String, CaseIterable, Identifiable {
    case scope
    case porcelain
    case mineral
    case midnight
    case tactical
    case ghost
    case lift
    case graphite
    case carbon
    case ember
    case matte

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .scope: return "Scope"
        case .porcelain: return "Porcelain"
        case .mineral: return "Mineral"
        case .midnight: return "Midnight"
        case .tactical: return "Tactical"
        case .ghost: return "Ghost"
        case .lift: return "Lift"
        case .graphite: return "Graphite"
        case .carbon: return "Carbon"
        case .ember: return "Ember"
        case .matte: return "Matte"
        }
    }

    var chrome: WatchChromeTokens {
        switch self {
        case .scope:    return watchScopeChrome
        case .porcelain: return watchPorcelainChrome
        case .mineral:  return watchMineralChrome
        case .midnight: return watchMidnightChrome
        case .tactical: return watchTacticalChrome
        case .ghost:    return watchGhostChrome
        case .lift:     return watchLiftChrome
        case .graphite: return watchGraphiteChrome
        case .carbon:   return watchCarbonChrome
        case .ember:    return watchEmberChrome
        case .matte:    return watchMatteChrome
        }
    }

    var captureStyle: WatchCaptureStyle {
        let material: WatchCaptureMaterial
        switch self {
        case .porcelain, .mineral, .lift:
            material = .lightMineral
        case .scope, .midnight, .tactical, .ghost, .graphite, .carbon, .ember, .matte:
            material = .blackCeramic
        }

        return WatchCaptureStyle(material: material, trace: chrome.accent)
    }
}

enum WatchTheme {
    static let selectedThemeKey = "selectedTheme"
    static let localOverrideKey = "watch.captureThemeOverride"

    static var syncedName: WatchThemeName {
        guard let raw = UserDefaults.standard.string(forKey: selectedThemeKey),
              let theme = WatchThemeName(rawValue: raw) else {
            return .porcelain
        }
        return theme
    }

    static var localOverrideName: WatchThemeName? {
        guard let raw = UserDefaults.standard.string(forKey: localOverrideKey) else {
            return nil
        }
        return WatchThemeName(rawValue: raw)
    }

    static var currentName: WatchThemeName {
        localOverrideName ?? syncedName
    }

    static var current: WatchChromeTokens { currentName.chrome }

    static var capture: WatchCaptureStyle { currentName.captureStyle }
}

private struct WatchThemeNameEnvironmentKey: EnvironmentKey {
    static let defaultValue = WatchTheme.currentName
}

extension EnvironmentValues {
    var watchThemeName: WatchThemeName {
        get { self[WatchThemeNameEnvironmentKey.self] }
        set { self[WatchThemeNameEnvironmentKey.self] = newValue }
    }
}

// MARK: - Watch Primitives
//
// Sized down from iOS counterparts: eyebrow 9pt (vs 10pt), default status dot
// 5pt (vs 6pt). Same vocabulary so screens read as parallel chrome.

/// Small instrument-label eyebrow. `.accent` = lit chrome, `.ink` = neutral on
/// page, `.panelInk` = inside a recessed panel.
struct WatchEyebrow: View {
    enum Tint { case accent, ink, panelInk }

    let text: String
    var tint: Tint = .accent
    var showLeader: Bool = true

    var body: some View {
        let chrome = WatchTheme.current
        Text((showLeader ? "\(chrome.eyebrowLeader) " : "") + text.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(color(chrome: chrome))
            .shadow(color: tint == .accent ? chrome.accentGlow : .clear, radius: chrome.glowRadius)
    }

    private func color(chrome: WatchChromeTokens) -> Color {
        switch tint {
        case .accent:   return chrome.accent
        case .ink:      return Color.white.opacity(0.55)
        case .panelInk: return chrome.panelInkFaint
        }
    }
}

/// Phosphor-style status dot. Defaults to theme accent; pass `color:` to
/// override (e.g. semantic red/green/orange that should stay system-stable).
struct WatchStatusDot: View {
    var diameter: CGFloat = 5
    var pulses: Bool = false
    /// Override color (defaults to theme accent).
    var color: Color? = nil

    @State private var pulse = false

    var body: some View {
        let chrome = WatchTheme.current
        let dotColor = color ?? chrome.accent
        Circle()
            .fill(dotColor)
            .frame(width: diameter, height: diameter)
            .shadow(color: dotColor.opacity(0.55), radius: pulse ? chrome.glowRadius + 1 : chrome.glowRadius)
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
struct WatchDivider: View {
    var hasTick: Bool = false

    var body: some View {
        let chrome = WatchTheme.current
        ZStack {
            Rectangle()
                .fill(chrome.edgeFaint)
                .frame(height: chrome.hairlineWidth)
            if hasTick {
                Rectangle()
                    .fill(chrome.accent)
                    .frame(width: 10, height: chrome.hairlineWidth + 0.25)
            }
        }
    }
}

// MARK: - Convenience accessors

extension View {
    /// Theme-aware accent glow. Applied to text or icons to read as "lit chrome".
    func watchAccentGlow(radius: CGFloat? = nil) -> some View {
        let chrome = WatchTheme.current
        return shadow(color: chrome.accentGlow, radius: radius ?? chrome.glowRadius)
    }
}
