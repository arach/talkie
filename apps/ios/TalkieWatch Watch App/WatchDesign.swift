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

// MARK: - Active Theme Resolver
//
// The Watch target doesn't have an App Group entitlement yet (TalkieWatch has no
// .entitlements file — only TalkieWatchWidget does). Until one is set up we
// always return scope chrome, which is a reasonable default — the watch is
// rarely customized.
//
// If a future change adds the App Group to the Watch target, this resolver
// can read `selectedTheme` from the shared UserDefaults — see iOS
// `TalkieAppConfigurationStore` for the key.

enum WatchThemeName: String {
    case scope
    case midnight
    case tactical
    case ghost

    var chrome: WatchChromeTokens {
        switch self {
        case .scope:    return watchScopeChrome
        case .midnight: return watchMidnightChrome
        case .tactical: return watchTacticalChrome
        case .ghost:    return watchGhostChrome
        }
    }
}

enum WatchTheme {
    /// Shared App Group identifier (matches iOS). Reads of this group will
    /// silently no-op on the watch until the entitlement is added.
    static let appGroupIdentifier = "group.to.talkie.app"

    /// Active theme. Reads `selectedTheme` from the shared App Group; falls
    /// back to scope if the group is unavailable (no entitlement on watch).
    static var current: WatchChromeTokens {
        if let defaults = UserDefaults(suiteName: appGroupIdentifier),
           let raw = defaults.string(forKey: "selectedTheme"),
           let theme = WatchThemeName(rawValue: raw) {
            return theme.chrome
        }
        return watchScopeChrome
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
