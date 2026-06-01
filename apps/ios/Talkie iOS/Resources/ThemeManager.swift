//
//  ThemeManager.swift
//  Talkie iOS
//
//  Manages app themes with 5 configurable options
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
    case midnight = "midnight"
    case tactical = "tactical"
    case ghost = "ghost"
    case lift = "lift"
    case graphite = "graphite"
    case carbon = "carbon"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .scope: return "Scope"
        case .midnight: return "Linear"
        case .tactical: return "Tactical"
        case .ghost: return "Ghost"
        case .lift: return "Lift"
        case .graphite: return "Vercel"
        case .carbon: return "Carbon"
        }
    }

    var description: String {
        switch self {
        case .scope: return "Paper chassis with brass instrument chrome"
        case .midnight: return "Linear-style · flat indigo dark, clean"
        case .tactical: return "High contrast, sharp edges"
        case .ghost: return "Soft, muted elegance"
        case .lift: return "Pure white surfaces with indigo lift"
        case .graphite: return "Vercel-style · monochrome white-on-black"
        case .carbon: return "True-black terminal · monochrome, one signal"
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
private let cachedMidnightColors = ThemeColors(
    tableHeaderBackground: Color(hex: "16171A"),
    tableCellBackground: Color(hex: "08090A"),
    tableDivider: Color(hex: "FFFFFF").opacity(0.10),
    tableBorder: Color(hex: "FFFFFF").opacity(0.14),
    background: Color(hex: "08090A"),
    cardBackground: Color(hex: "131417"),
    searchBackground: Color(hex: "1A1B1F"),
    textPrimary: Color(hex: "F7F8F8"),
    textSecondary: Color(hex: "DADDE2"),
    textTertiary: Color(hex: "ABB0B8"),
    accent: Color(hex: "5E6AD2"),
    success: Color(hex: "4CB782")
)

private let cachedTacticalColors = ThemeColors(
    tableHeaderBackground: Color(hex: "1F1F1F"),
    tableCellBackground: Color(hex: "0F0F0F"),
    tableDivider: Color(hex: "4A4A4A"),
    tableBorder: Color(hex: "5C5C5C"),
    background: Color(hex: "0A0A0A"),
    cardBackground: Color(hex: "1F1F1F"),
    searchBackground: Color(hex: "1E1E1E"),
    textPrimary: Color(hex: "F0F0F0"),
    textSecondary: Color(hex: "C4C4C4"),
    textTertiary: Color(hex: "A4A4A4"),
    accent: Color(hex: "FF8800"),
    success: Color(hex: "00D26A")
)

private let cachedGhostColors = ThemeColors(
    tableHeaderBackground: Color(hex: "F0F0F0", darkHex: "1E1E1E"),
    tableCellBackground: Color(hex: "FAFAFA", darkHex: "141414"),
    tableDivider: Color(hex: "E5E5E5", darkHex: "2A2A2A"),
    tableBorder: Color(hex: "DDDDDD", darkHex: "333333"),
    background: Color(hex: "F5F5F5", darkHex: "0E0E0E"),
    cardBackground: Color(hex: "FFFFFF", darkHex: "1A1A1A"),
    searchBackground: Color(hex: "FFFFFF", darkHex: "1A1A1A"),
    textPrimary: Color(hex: "2A2A2A", darkHex: "E5E5E5"),
    textSecondary: Color(hex: "7A7A7A", darkHex: "8A8A8A"),
    // textTertiary was A0A0A0 / 5A5A5A — both failed WCAG AA at the
    // 3:1 large-text bar (light 2.40:1 / dark 2.68:1). Bumped to land
    // at 3.17:1 (light) and 4.40:1 (dark) while preserving the
    // secondary > tertiary hierarchy.
    textTertiary: Color(hex: "8A8A8A", darkHex: "909090"),
    accent: Color(hex: "6366F1"),
    success: Color(hex: "10B981")
)

private let cachedLiftColors = ThemeColors(
    tableHeaderBackground: Color(hex: "FAFAFA", darkHex: "1A1A1A"),
    tableCellBackground: Color(hex: "FFFFFF", darkHex: "1A1A1A"),
    tableDivider: Color(hex: "000000", darkHex: "FFFFFF").opacity(0.04),
    tableBorder: Color(hex: "000000", darkHex: "FFFFFF").opacity(0.10),
    background: Color(hex: "FFFFFF", darkHex: "1A1A1A"),
    cardBackground: Color(hex: "FFFFFF", darkHex: "1A1A1A"),
    searchBackground: Color(hex: "FAFAFA", darkHex: "181818"),
    textPrimary: Color(hex: "1A1A1A", darkHex: "FAFAFA"),
    textSecondary: Color(hex: "525252", darkHex: "A0A0A0"),
    // textTertiary was A0A0A0 / 707070 — light failed AA at 3:1
    // large-text bar (2.63:1). Bumped light to 8A8A8A → 3.45:1.
    // Dark side stays at 707070 (already passes large-text on
    // 1A1A1A at 3.10:1).
    textTertiary: Color(hex: "8A8A8A", darkHex: "8A8A8A"),
    accent: Color(hex: "6366F1"),
    success: Color(hex: "10B981")
)

// Scope: black-and-gold instrument chassis. Paper-white canvas, warm-graphite
// instrument panels, brass-amber accent. Mirrors the latest direction on
// `ui/instrument-bay-polish` — softer brass over emerald, paper over pure
// white. Dividers/borders derive from ink and auto-flip with mode.
private let cachedScopeColors = ThemeColors(
    tableHeaderBackground: Color(hex: "F5F3EE", darkHex: "1A1714"),
    tableCellBackground: Color(hex: "F8F6F1", darkHex: "13110E"),
    tableDivider: ScopeMobile.ink.opacity(0.06),
    tableBorder: ScopeMobile.ink.opacity(0.10),
    background: Color(hex: "FBFAF7", darkHex: "0A0907"),
    cardBackground: Color(hex: "F8F6F1", darkHex: "13110E"),
    searchBackground: Color(hex: "F2F0EA", darkHex: "151310"),
    textPrimary: Color(hex: "1A1612", darkHex: "F5F3EE"),
    textSecondary: Color(hex: "5A5045", darkHex: "A8A096"),
    // textTertiary light A39989 failed at 2.69:1 (large-text 3:1).
    // Darkened to 8A7E6C → 3.78:1 while keeping the warm graphite
    // tone the theme depends on. Dark side stays at 7D6E5E (4.06:1).
    textTertiary: Color(hex: "8A7E6C", darkHex: "968876"),
    accent: Color(hex: "B5823A", darkHex: "E89A3C"),
    success: Color(hex: "6F7D3E", darkHex: "9CB35A")
)

// EXPLORATION — "Vercel" approach (Graphite slot). Geist-style true
// monochrome: pure-black canvas, neutral-gray elevated surfaces, and a WHITE
// accent — so every accent-driven icon/control goes white automatically (no
// hue anywhere, zero view refactor). Vercel's gray ramp: #EDEDED / #A1A1A1 /
// #8F8F8F. Recording red stays the one permitted pop (it's a universal token,
// not the theme accent).
private let cachedGraphiteColors = ThemeColors(
    tableHeaderBackground: Color(hex: "0F0F0F"),
    tableCellBackground: Color(hex: "000000"),
    tableDivider: Color(hex: "FFFFFF").opacity(0.13),
    tableBorder: Color(hex: "FFFFFF").opacity(0.18),
    background: Color(hex: "000000"),
    cardBackground: Color(hex: "0E0E0E"),
    searchBackground: Color(hex: "171717"),
    // Gray-on-black is the battleground. Vercel's authentic ramp (#A1A1A1 /
    // #8F8F8F) is too dim on a phone — secondary lifted to ~83% white,
    // tertiary to ~67%. Readability over strict hierarchy.
    textPrimary: Color(hex: "F4F4F4"),
    textSecondary: Color(hex: "DADADA"),
    textTertiary: Color(hex: "B0B0B0"),
    accent: Color(hex: "FAFAFA"),
    success: Color(hex: "4CC38A")
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
    background: Color(hex: "FFFFFF", darkHex: "000000"),
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
    accent: Color(hex: "0E8F4F", darkHex: "3DE08A"),
    success: Color(hex: "0E8F4F", darkHex: "3DE08A")
)

// MARK: - Theme Color Access (O(1) lookup, no parsing)

extension AppTheme {
    var colors: ThemeColors {
        switch self {
        case .scope: return cachedScopeColors
        case .midnight: return cachedMidnightColors
        case .tactical: return cachedTacticalColors
        case .ghost: return cachedGhostColors
        case .lift: return cachedLiftColors
        case .graphite: return cachedGraphiteColors
        case .carbon: return cachedCarbonColors
        }
    }

    var isScope: Bool {
        self == .scope
    }
}

// MARK: - Theme Manager

@MainActor
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    private let appSettings = TalkieAppSettings.shared

    @Published var currentTheme: AppTheme {
        didSet {
            appSettings.theme = currentTheme
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
        self.currentTheme = AppTheme(rawValue: configuration.appearance.theme) ?? .scope
        self.appearanceMode = AppearanceMode(rawValue: configuration.appearance.mode) ?? .system
    }

    func reloadFromDisk() {
        let configuration = TalkieAppConfigurationStore.shared.reload()
        currentTheme = AppTheme(rawValue: configuration.appearance.theme) ?? .scope
        appearanceMode = AppearanceMode(rawValue: configuration.appearance.mode) ?? .system
    }

    func apply(theme: AppTheme, appearanceMode: AppearanceMode? = nil) {
        currentTheme = theme
        if let appearanceMode {
            self.appearanceMode = appearanceMode
        }
    }
}
