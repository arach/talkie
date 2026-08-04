//
//  ThemeManager.swift
//  Talkie iOS
//
//  Manages the app's configurable visual themes.
//

import SwiftUI

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Theme Definitions

enum AppTheme: String, CaseIterable, Identifiable {
    case scope = "scope"
    case porcelain = "porcelain"
    case mineral = "mineral"
    case midnight = "midnight"
    case tactical = "tactical"
    case ghost = "ghost"
    case lift = "lift"
    case graphite = "graphite"
    case carbon = "carbon"
    case ember = "ember"

    /// Product default for new or incomplete appearance configurations.
    /// Keep this centralized so the settings facade and runtime resolver cannot drift.
    static let productDefault: AppTheme = .porcelain

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .scope: return "Scope"
        case .porcelain: return "Porcelain"
        case .mineral: return "Mineral"
        case .midnight: return "Linear"
        case .tactical: return "Tactical"
        case .ghost: return "Ghost"
        case .lift: return "Lift"
        case .graphite: return "Vercel"
        case .carbon: return "Carbon"
        case .ember: return "Ember"
        }
    }

    var description: String {
        switch self {
        case .scope: return "Paper chassis with brass instrument chrome"
        case .porcelain: return "Cool porcelain chassis with cobalt instrument signal"
        case .mineral: return "Blue-gray alloy with copper signal chrome"
        case .midnight: return "Linear-style · flat indigo dark, clean"
        case .tactical: return "High contrast, sharp edges"
        case .ghost: return "Soft, muted elegance"
        case .lift: return "Pure white surfaces with indigo lift"
        case .graphite: return "Vercel-style · monochrome white-on-black"
        case .carbon: return "True-black terminal · monochrome, one signal"
        case .ember: return "Warm charcoal with a single amber signal"
        }
    }
}

// MARK: - Theme Colors

struct ThemeColors {
    // Table colors
    let tableHeaderBackground: Color
    let tableCellBackground: Color
    let tableDivider: Color
    let tableBorder: Color

    // General surfaces
    let background: Color
    let cardBackground: Color
    let searchBackground: Color

    // Text
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    // Accents
    let accent: Color
    let success: Color
}

// MARK: - Cached Theme Colors (parsed once at app launch, not on every access)

// EXPLORATION — "Linear" approach (Midnight slot). A Linear-style clean dark:
// flat near-black blue-tinted canvas (#08090A), softly-elevated surfaces, a
// restrained indigo accent (#5E6AD2 = Linear's actual brand), refined neutral
// text ramp. No glow, generous rounding, 1pt borders. Colored icons read as
// on-brand here rather than as overload.
// Light half added. Every token here was previously a single hex, which meant
// Light and Dark rendered identically — choosing Light on this theme handed you
// a black UI and no way to tell the setting was doing anything. Linear itself
// ships a light theme; this follows it (near-white chassis, indigo unchanged as
// the identity), so the theme keeps its name honestly in both modes.
private let cachedMidnightColors = ThemeColors(
    tableHeaderBackground: Color(hex: "E9EBEF", darkHex: "16171A"),
    tableCellBackground: Color(hex: "FFFFFF", darkHex: "08090A"),
    tableDivider: Color(hex: "08090A", darkHex: "FFFFFF").opacity(0.10),
    tableBorder: Color(hex: "08090A", darkHex: "FFFFFF").opacity(0.14),
    background: Color(hex: "EFF0F3", darkHex: "08090A"),
    cardBackground: Color(hex: "FFFFFF", darkHex: "1C1D22"),
    searchBackground: Color(hex: "E7E9EE", darkHex: "1A1B1F"),
    textPrimary: Color(hex: "08090A", darkHex: "F7F8F8"),
    textSecondary: Color(hex: "4A525F", darkHex: "DADDE2"),
    textTertiary: Color(hex: "656D78", darkHex: "ABB0B8"),
    // Dark side lifts to 747FD8 — 5E6AD2 sat at 3.58:1 on the elevated card.
    accent: Color(hex: "5E6AD2", darkHex: "747FD8"),
    success: Color(hex: "2C7A55", darkHex: "4CB782")
)

// Light half added — see the note on `cachedMidnightColors`. High-contrast is
// the brief, so the light side runs a flat gray chassis with near-black ink.
// The hot orange is the one thing that cannot survive the trip: FF8800 on white
// is 2.39:1, unreadable as text. Light mode deepens it to B35F00 (same hue,
// lightness only) and dark mode keeps the original.
private let cachedTacticalColors = ThemeColors(
    tableHeaderBackground: Color(hex: "E4E4E4", darkHex: "1F1F1F"),
    tableCellBackground: Color(hex: "FFFFFF", darkHex: "0F0F0F"),
    tableDivider: Color(hex: "B4B4B4", darkHex: "4A4A4A"),
    tableBorder: Color(hex: "9A9A9A", darkHex: "5C5C5C"),
    background: Color(hex: "EDEDED", darkHex: "0A0A0A"),
    cardBackground: Color(hex: "FFFFFF", darkHex: "1F1F1F"),
    searchBackground: Color(hex: "E2E2E2", darkHex: "1E1E1E"),
    textPrimary: Color(hex: "0A0A0A", darkHex: "F0F0F0"),
    textSecondary: Color(hex: "343434", darkHex: "C4C4C4"),
    textTertiary: Color(hex: "5A5A5A", darkHex: "A4A4A4"),
    accent: Color(hex: "B35F00", darkHex: "FF8800"),
    success: Color(hex: "008744", darkHex: "00D26A")
)

private let cachedGhostColors = ThemeColors(
    tableHeaderBackground: Color(hex: "F0F0F0", darkHex: "1E1E1E"),
    tableCellBackground: Color(hex: "FAFAFA", darkHex: "141414"),
    tableDivider: Color(hex: "E5E5E5", darkHex: "2A2A2A"),
    tableBorder: Color(hex: "DDDDDD", darkHex: "333333"),
    background: Color(hex: "ECECEC", darkHex: "0E0E0E"),
    cardBackground: Color(hex: "FFFFFF", darkHex: "202020"),
    searchBackground: Color(hex: "FFFFFF", darkHex: "202020"),
    textPrimary: Color(hex: "2A2A2A", darkHex: "E5E5E5"),
    textSecondary: Color(hex: "5D5D5D", darkHex: "A8A8A8"),
    // textTertiary was A0A0A0 / 5A5A5A — both failed WCAG AA at the
    // 3:1 large-text bar (light 2.40:1 / dark 2.68:1). Bumped to land
    // at 3.17:1 (light) and 4.40:1 (dark) while preserving the
    // secondary > tertiary hierarchy.
    textTertiary: Color(hex: "696969", darkHex: "909090"),
    accent: Color(hex: "6063F1", darkHex: "797BF3"),
    success: Color(hex: "10B981")
)

private let cachedLiftColors = ThemeColors(
    tableHeaderBackground: Color(hex: "FAFAFA", darkHex: "1B1B1B"),
    tableCellBackground: Color(hex: "FFFFFF", darkHex: "202020"),
    tableDivider: Color(hex: "000000", darkHex: "FFFFFF").opacity(0.04),
    tableBorder: Color(hex: "000000", darkHex: "FFFFFF").opacity(0.10),
    // Page and card were the SAME hex in both modes — a "raised" surface with
    // nothing to be raised from, leaning entirely on a 4% shadow. The page now
    // steps back so the lift in "Lift" is something you can actually see.
    background: Color(hex: "EBECEF", darkHex: "141414"),
    cardBackground: Color(hex: "FFFFFF", darkHex: "202020"),
    searchBackground: Color(hex: "FAFAFA", darkHex: "1B1B1B"),
    textPrimary: Color(hex: "1A1A1A", darkHex: "FAFAFA"),
    textSecondary: Color(hex: "525252", darkHex: "A0A0A0"),
    // textTertiary was A0A0A0 / 707070 — light failed AA at 3:1
    // large-text bar (2.63:1). Bumped light to 8A8A8A → 3.45:1.
    // Dark side stays at 707070 (already passes large-text on
    // 1A1A1A at 3.10:1).
    textTertiary: Color(hex: "696969", darkHex: "8A8A8A"),
    accent: Color(hex: "6063F1", darkHex: "797BF3"),
    success: Color(hex: "10B981")
)

// Scope: black-and-gold instrument chassis. Paper-white canvas, warm-graphite
// instrument panels, brass-amber accent. Mirrors the latest direction on
// `ui/instrument-bay-polish` — softer brass over emerald, paper over pure
// white. Dividers/borders derive from ink and auto-flip with mode.
private let cachedScopeColors = ThemeColors(
    tableHeaderBackground: Color(hex: "EBE7DE", darkHex: "1A1714"),
    tableCellBackground: Color(hex: "FDFCFA", darkHex: "201D18"),
    tableDivider: ScopeMobile.ink.opacity(0.06),
    tableBorder: ScopeMobile.ink.opacity(0.10),
    // Page carries the tone, cards sit above it — see `ScopeMobile.canvas`.
    // These two were `FBFAF7` page / `F8F6F1` card, which put the raised
    // surface *below* the page it rests on and separated them by ~1%.
    background: Color(hex: "F2EFE7", darkHex: "0A0907"),
    cardBackground: Color(hex: "FDFCFA", darkHex: "201D18"),
    searchBackground: Color(hex: "E9E5DC", darkHex: "151310"),
    textPrimary: Color(hex: "1A1612", darkHex: "F5F3EE"),
    textSecondary: Color(hex: "5A5045", darkHex: "A8A096"),
    // textTertiary light A39989 failed at 2.69:1 (large-text 3:1), then 8A7E6C
    // held 3.78:1 against the old near-white page. The page now carries tone,
    // so this darkens again to 7E7260 — 4.09:1, i.e. better than it has ever
    // been, not merely recovered. Dark side stays at 968876.
    textTertiary: Color(hex: "766B5A", darkHex: "968876"),
    // Brass deepened on the light side (was B5823A, 3.29:1 on a card — brass
    // is a *mid* tone and cards are near-white, so the page-space accent had
    // nowhere to sit). 976C30 is the same hue and saturation, two steps down
    // in lightness only: 4.53:1. The lit brass lives on in `panelTrace`, which
    // is the token that paints dark plates and can afford to glow.
    accent: Color(hex: "976C30", darkHex: "E89A3C"),
    // Scope is intentionally a one-signal instrument: completion and active
    // state stay brass instead of introducing an unrelated olive green.
    success: Color(hex: "976C30", darkHex: "E89A3C")
)

// Porcelain: a cooler light-forward instrument palette. The chassis is a
// soft blue-white rather than cream, the recessed console is deep navy, and
// cobalt is the sole live/active/completion signal. Dark mode keeps the same
// blue family so switching appearance does not change the theme's identity.
private let cachedPorcelainColors = ThemeColors(
    tableHeaderBackground: Color(hex: "E7ECF2", darkHex: "172235"),
    tableCellBackground: Color(hex: "F5F7FA", darkHex: "152439"),
    tableDivider: Color(hex: "18162330", darkHex: "2EECF2FA"),
    tableBorder: Color(hex: "2B162330", darkHex: "47ECF2FA"),
    background: Color(hex: "E2E9F0", darkHex: "0B1320"),
    cardBackground: Color(hex: "FAFBFD", darkHex: "152439"),
    searchBackground: Color(hex: "E5EAF0", darkHex: "17243A"),
    textPrimary: Color(hex: "162330", darkHex: "F2F6FC"),
    textSecondary: Color(hex: "42566B", darkHex: "BBC8D8"),
    textTertiary: Color(hex: "56697D", darkHex: "91A4BA"),
    accent: Color(hex: "2F63D8", darkHex: "78A6FF"),
    success: Color(hex: "2F63D8", darkHex: "78A6FF")
)

// Mineral: softly anodized blue-gray alloy with deep teal ink and a restrained
// copper signal. The light palette intentionally narrows the jump between the
// canvas, cards, and recessed chrome so the interface feels fabricated rather
// than layered from white sheets. Dark mode keeps the same cool-metal identity.
private let cachedMineralColors = ThemeColors(
    tableHeaderBackground: Color(hex: "C4D1D0", darkHex: "203336"),
    tableCellBackground: Color(hex: "E3E9E6", darkHex: "17272A"),
    tableDivider: Color(hex: "1F18353B", darkHex: "33EAF0EC"),
    tableBorder: Color(hex: "3318353B", darkHex: "4DEAF0EC"),
    background: Color(hex: "D2DEDD", darkHex: "122023"),
    cardBackground: Color(hex: "E3E9E6", darkHex: "192B2E"),
    searchBackground: Color(hex: "CBD7D6", darkHex: "213438"),
    textPrimary: Color(hex: "163238", darkHex: "EFF2ED"),
    textSecondary: Color(hex: "334F54", darkHex: "BECBC7"),
    textTertiary: Color(hex: "455E62", darkHex: "9DAEAA"),
    accent: Color(hex: "9B4E27", darkHex: "DF8955"),
    success: Color(hex: "3F7767", darkHex: "63AA91")
)

// EXPLORATION — "Vercel" approach (Graphite slot). Geist-style true
// monochrome: pure-black canvas, neutral-gray elevated surfaces, and a WHITE
// accent — so every accent-driven icon/control goes white automatically (no
// hue anywhere, zero view refactor). Vercel's gray ramp: #EDEDED / #A1A1A1 /
// #8F8F8F. Recording red stays the one permitted pop (it's a universal token,
// not the theme accent).
private let cachedGraphiteColors = ThemeColors(
    tableHeaderBackground: Color(hex: "EDEDED", darkHex: "0F0F0F"),
    tableCellBackground: Color(hex: "FFFFFF", darkHex: "000000"),
    tableDivider: Color(hex: "000000", darkHex: "FFFFFF").opacity(0.13),
    tableBorder: Color(hex: "000000", darkHex: "FFFFFF").opacity(0.18),
    background: Color(hex: "F0F0F0", darkHex: "000000"),
    cardBackground: Color(hex: "FFFFFF", darkHex: "181818"),
    searchBackground: Color(hex: "E8E8E8", darkHex: "171717"),
    // Gray-on-black is the battleground. Vercel's authentic ramp (#A1A1A1 /
    // #8F8F8F) is too dim on a phone — secondary lifted to ~83% white,
    // tertiary to ~67%. Readability over strict hierarchy.
    textPrimary: Color(hex: "0A0A0A", darkHex: "F4F4F4"),
    textSecondary: Color(hex: "404040", darkHex: "DADADA"),
    textTertiary: Color(hex: "6B6B6B", darkHex: "B0B0B0"),
    // The monochrome "signal" flips with the mode rather than staying white:
    // a white accent on a white page is not a restrained signal, it is an
    // invisible one. Geist does the same — black buttons in light, white in
    // dark. Still zero hue, still no view refactor.
    accent: Color(hex: "0A0A0A", darkHex: "FAFAFA"),
    success: Color(hex: "13704A", darkHex: "4CC38A")
)


// Carbon: monochrome terminal. True black in dark, crisp white in light —
// no warm bias, no second hue. The "technical heritage" theme: contrast and
// SF Mono carry the design, and a single cold signal-green is the ONLY color,
// reserved for live/active state. Built deliberately punchier than the other
// themes — secondary text stays high-contrast (not a sleepy mid-gray) and
// hairlines are firm so cards never melt into the canvas. Divider/border
// derive from a black/white flip; everything else is mode-paired.
private let cachedCarbonColors = ThemeColors(
    // Dark cards lift to #161616 on the true-black #000 canvas — panels read
    // as clearly elevated "lit" surfaces while the canvas + empty space stay
    // pure black (the terminal identity). Without this lift Carbon fell into
    // the same melt-into-black trap as the other dark themes.
    tableHeaderBackground: Color(hex: "F7F7F7", darkHex: "161616"),
    tableCellBackground: Color(hex: "FFFFFF", darkHex: "000000"),
    // Mode-aware (AARRGGBB): dark side carries ~2× alpha so table rules read
    // on black the way they already do on white.
    tableDivider: Color(hex: "1F000000", darkHex: "33FFFFFF"),
    tableBorder: Color(hex: "2E000000", darkHex: "57FFFFFF"),
    background: Color(hex: "F2F2F2", darkHex: "000000"),
    cardBackground: Color(hex: "FFFFFF", darkHex: "161616"),
    searchBackground: Color(hex: "F2F2F2", darkHex: "1C1C1C"),
    // Punchy by design — the "muted" complaint was warm-on-warm + sleepy
    // secondary text. Carbon keeps secondary near 11:1 so body copy reads
    // hot. Tertiary lands ~5:1 (light) / ~4.9:1 (dark) for the mono meta line.
    // On true-black, grays should read LIGHT, not dark — the whole point of a
    // dark theme is white-forward text. Secondary lands ~16:1, tertiary (the
    // detail tier: timestamps, inactive tabs, placeholders, hints) ~9:1, so
    // details come out clearly instead of whispering. Light side unchanged.
    textPrimary: Color(hex: "0A0A0A", darkHex: "FAFAFA"),
    textSecondary: Color(hex: "3A3A3A", darkHex: "DADADA"),
    textTertiary: Color(hex: "6E6E6E", darkHex: "B0B0B0"),
    // The one signal — cold phosphor green. Deepened in light mode so it
    // still reads on white; bright in dark for the lit-terminal pip.
    accent: Color(hex: "0D874A", darkHex: "3DE08A"),
    success: Color(hex: "0D874A", darkHex: "3DE08A")
)

// Ember — black and amber, the sober reading of that pair.
//
// Tactical already owns black + hot orange, but it is a cockpit: square
// corners, FF8800, everything shouting. Ember is the same family played
// quietly — a warm charcoal rather than a true black (the neutrals carry a
// few points of red so the amber sits in the same world instead of floating
// on top of a cold gray), and an amber deep enough to read as text rather
// than as a warning lamp.
//
// Amber is a light hue, which is the whole difficulty: it is comfortable on
// dark and nearly invisible on white. So the accent is one hue at two
// lightnesses — D98C2B on the dark side, A3671D on the light — rather than
// one value forced to serve both. Success stays a muted sage instead of
// borrowing the amber, because a theme with a single signal colour cannot
// distinguish "done" from "look here."
private let cachedEmberColors = ThemeColors(
    tableHeaderBackground: Color(hex: "E7E3DC", darkHex: "161512"),
    tableCellBackground: Color(hex: "FFFFFF", darkHex: "1B1A17"),
    // Mode-aware (AARRGGBB): the dark side runs ~2× alpha, since white-on-dark
    // rules read fainter than black-on-light at the same value.
    tableDivider: Color(hex: "1F000000", darkHex: "33FFFFFF"),
    tableBorder: Color(hex: "2E000000", darkHex: "52FFFFFF"),
    background: Color(hex: "ECE8E1", darkHex: "0C0B0A"),
    cardBackground: Color(hex: "FFFFFF", darkHex: "1B1A17"),
    searchBackground: Color(hex: "E4E0D8", darkHex: "1F1E1A"),
    textPrimary: Color(hex: "13120F", darkHex: "F4F1EA"),
    textSecondary: Color(hex: "3C3830", darkHex: "CBC4B6"),
    textTertiary: Color(hex: "635D52", darkHex: "9C9488"),
    accent: Color(hex: "A3671D", darkHex: "D98C2B"),
    success: Color(hex: "3F7A55", darkHex: "6FB98A")
)

// MARK: - Theme Color Access (O(1) lookup, no parsing)

extension AppTheme {
    var colors: ThemeColors {
        switch self {
        case .scope: return cachedScopeColors
        case .porcelain: return cachedPorcelainColors
        case .mineral: return cachedMineralColors
        case .midnight: return cachedMidnightColors
        case .tactical: return cachedTacticalColors
        case .ghost: return cachedGhostColors
        case .lift: return cachedLiftColors
        case .graphite: return cachedGraphiteColors
        case .carbon: return cachedCarbonColors
        case .ember: return cachedEmberColors
        }
    }

    var isScope: Bool {
        self == .scope
    }
}

// MARK: - Active Theme Mirror

/// Nonisolated mirror of the live theme selection.
///
/// Several palettes are plain static color tables (`DesignSystem`, the Home
/// cockpit, the terminal strip). They can't hop to the main actor to ask
/// `ThemeManager`, and reading the persisted configuration instead leaves them
/// one theme behind — the store only catches up after the settings write lands,
/// so the cockpit paints the *previous* theme's accent. This is written on every
/// theme change, so those tables see the choice at the moment it's made.
enum ActiveTheme {
    nonisolated(unsafe) static var current: AppTheme = {
        let raw = TalkieAppConfigurationStore.shared.configuration.appearance.theme
        return AppTheme(rawValue: raw) ?? .productDefault
    }()
}

// MARK: - Theme Manager

@MainActor
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    private let appSettings = TalkieAppSettings.shared

    @Published var currentTheme: AppTheme {
        didSet {
            ActiveTheme.current = currentTheme
            appSettings.theme = currentTheme
            WatchSessionManager.shared.publishAppearanceTheme(currentTheme.rawValue)
        }
    }

    @Published var appearanceMode: AppearanceMode {
        didSet {
            appSettings.appearanceMode = appearanceMode
        }
    }

    var colors: ThemeColors {
        currentTheme.colors
    }

    private init() {
        let configuration = TalkieAppConfigurationStore.shared.configuration
        self.currentTheme = AppTheme(rawValue: configuration.appearance.theme) ?? .productDefault
        self.appearanceMode = AppearanceMode(rawValue: configuration.appearance.mode) ?? .system
    }

    func reloadFromDisk() {
        let configuration = TalkieAppConfigurationStore.shared.reload()
        currentTheme = AppTheme(rawValue: configuration.appearance.theme) ?? .productDefault
        appearanceMode = AppearanceMode(rawValue: configuration.appearance.mode) ?? .system
    }

    func apply(theme: AppTheme, appearanceMode: AppearanceMode? = nil) {
        currentTheme = theme
        if let appearanceMode {
            self.appearanceMode = appearanceMode
        }
    }
}
