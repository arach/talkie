//
//  SettingsManager.swift
//  Talkie macOS
//
//  Manages app settings stored in Core Data
//  API keys are stored securely in macOS Keychain
//

import Foundation
import CoreData
import SwiftUI
import AppKit
import os
import Observation

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Settings")

// MARK: - Appearance Mode
enum AppearanceMode: String, CaseIterable, CustomStringConvertible {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var description: String {
        displayName
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

// MARK: - Sync Settings
extension SettingsManager {
    /// Whether to run CloudKit sync automatically on app launch
    var syncOnLaunch: Bool {
        get { UserDefaults.standard.bool(forKey: "syncOnLaunch") }
        set { UserDefaults.standard.set(newValue, forKey: "syncOnLaunch") }
    }

    /// Minimum interval between automatic syncs (seconds)
    var minimumSyncInterval: TimeInterval {
        get { UserDefaults.standard.double(forKey: "minimumSyncInterval").orDefault(300) } // 5 minutes
        set { UserDefaults.standard.set(newValue, forKey: "minimumSyncInterval") }
    }
}

private extension Double {
    func orDefault(_ defaultValue: Double) -> Double {
        self == 0 ? defaultValue : self
    }
}

// MARK: - Accent Color Options
enum AccentColorOption: String, CaseIterable {
    case system = "system"
    case blue = "blue"
    case purple = "purple"
    case pink = "pink"
    case red = "red"
    case orange = "orange"
    case yellow = "yellow"
    case green = "green"
    case gray = "gray"

    var displayName: String {
        rawValue.capitalized
    }

    var color: Color? {
        switch self {
        case .system: return nil
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .gray: return .gray
        }
    }
}

// MARK: - Font Style Options
enum FontStyleOption: String, CaseIterable {
    case system = "system"
    case monospace = "monospace"
    case rounded = "rounded"
    case serif = "serif"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .monospace: return "Monospace"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        }
    }

    var icon: String {
        switch self {
        case .system: return "textformat"
        case .monospace: return "chevron.left.forwardslash.chevron.right"
        case .rounded: return "a.circle"
        case .serif: return "text.book.closed"
        }
    }

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .system:
            return .system(size: size, weight: weight)
        case .monospace:
            return .system(size: size, weight: weight, design: .monospaced)
        case .rounded:
            return .system(size: size, weight: weight, design: .rounded)
        case .serif:
            return .system(size: size, weight: weight, design: .serif)
        }
    }
}

// MARK: - Font Size Options
/// Design system font sizes - canonical integer sizes, no fractional scaling
/// Each size tier defines proper integer point sizes for crisp rendering
enum FontSizeOption: String, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .small: return "textformat.size.smaller"
        case .medium: return "textformat.size"
        case .large: return "textformat.size.larger"
        }
    }

    // MARK: - Design System Sizes (integers only, no fractional scaling)

    /// Extra-small: metadata, timestamps, badges
    var xs: CGFloat {
        switch self {
        case .small: return 9
        case .medium: return 10
        case .large: return 11
        }
    }

    /// Small: secondary text, captions, labels
    var sm: CGFloat {
        switch self {
        case .small: return 10
        case .medium: return 11
        case .large: return 12
        }
    }

    /// Body: primary content text
    var body: CGFloat {
        switch self {
        case .small: return 12
        case .medium: return 13
        case .large: return 15
        }
    }

    /// Detail: expanded view text
    var detail: CGFloat {
        switch self {
        case .small: return 13
        case .medium: return 14
        case .large: return 16
        }
    }

    /// Title: headings
    var title: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 15
        case .large: return 17
        }
    }

    /// Preview font size for the settings label itself
    var previewFontSize: CGFloat { body }

    // Legacy compatibility - maps to a rough scale for existing code
    // that uses `baseSize * scale`. Will produce integer results for common base sizes.
    var scale: CGFloat {
        switch self {
        case .small: return 0.9
        case .medium: return 1.0
        case .large: return 1.15
        }
    }
}

// MARK: - Curated Theme Presets
enum ThemePreset: String, CaseIterable {
    case talkiePro = "talkiePro"
    case linear = "linear"
    case terminal = "terminal"
    case minimal = "minimal"
    case classic = "classic"
    case warm = "warm"

    var displayName: String {
        switch self {
        case .talkiePro: return "Talkie Pro"
        case .linear: return "Linear"
        case .terminal: return "Terminal"
        case .minimal: return "Minimal"
        case .classic: return "Classic"
        case .warm: return "Warm"
        }
    }

    var description: String {
        switch self {
        case .talkiePro: return "Sharp, professional, high contrast"
        case .linear: return "True black, minimal, Vercel-inspired"
        case .terminal: return "Terminal vibes with green accents"
        case .minimal: return "Clean and subtle, adapts to system"
        case .classic: return "Comfortable defaults with blue accents"
        case .warm: return "Cozy dark mode with orange tones"
        }
    }

    var icon: String {
        switch self {
        case .talkiePro: return "waveform"
        case .linear: return "square.stack.3d.up"
        case .terminal: return "terminal"
        case .minimal: return "circle"
        case .classic: return "star"
        case .warm: return "flame"
        }
    }

    var previewColors: (bg: Color, fg: Color, accent: Color) {
        switch self {
        case .talkiePro:
            // fg: white*0.85 = 0.85
            return (Color(white: 0.08), Color(white: 0.85), Color(red: 0.4, green: 0.7, blue: 1.0))
        case .linear:
            // True black with pure white text, cyan accent (Vercel/Linear style)
            return (Color.black, Color.white, Color(red: 0.0, green: 0.83, blue: 1.0))
        case .terminal:
            // fg: green*0.9 ≈ (0, 0.9*0.85, 0) = (0, 0.765, 0)
            return (Color.black, Color(red: 0, green: 0.765, blue: 0), Color.green)
        case .minimal:
            // fg: black*0.8 = 0.2
            return (Color(white: 0.96), Color(white: 0.2), Color.gray)
        case .classic:
            // fg: white*0.9 = 0.9
            return (Color(white: 0.15), Color(white: 0.9), Color.blue)
        case .warm:
            // fg: white*0.9 = 0.9
            return (Color(red: 0.1, green: 0.08, blue: 0.06), Color(white: 0.9), Color.orange)
        }
    }

    // Theme preset values
    var appearanceMode: AppearanceMode {
        switch self {
        case .talkiePro: return .dark
        case .linear: return .dark
        case .terminal: return .dark
        case .minimal: return .system  // Respects system light/dark
        case .classic: return .dark
        case .warm: return .dark
        }
    }

    /// UI chrome font style (labels, headers, buttons, badges)
    var uiFontStyle: FontStyleOption {
        switch self {
        case .talkiePro: return .system     // SF Pro - clean, professional
        case .linear: return .system        // Clean geometric sans-serif
        case .terminal: return .monospace
        case .minimal: return .system       // Clean system font
        case .classic: return .system
        case .warm: return .system
        }
    }

    /// Content font style (transcripts, notes, markdown)
    var contentFontStyle: FontStyleOption {
        switch self {
        case .talkiePro: return .system     // SF Pro - readable, luxurious
        case .linear: return .system        // Clean, readable content
        case .terminal: return .monospace   // Full terminal experience
        case .minimal: return .system       // Clean system font for content
        case .classic: return .system       // Standard system font
        case .warm: return .monospace       // Monospace content for warm theme
        }
    }

    var accentColor: AccentColorOption {
        switch self {
        case .talkiePro: return .blue
        case .linear: return .blue          // Cyan-ish blue like Linear
        case .terminal: return .green
        case .minimal: return .gray
        case .classic: return .blue
        case .warm: return .orange
        }
    }

    /// Font size option for this theme
    var fontSize: FontSizeOption {
        switch self {
        case .talkiePro: return .medium
        case .linear: return .medium
        case .terminal: return .medium
        case .minimal: return .medium
        case .classic: return .medium
        case .warm: return .medium
        }
    }

    /// Whether this theme uses true black backgrounds (for OLED optimization)
    var usesTrueBlack: Bool {
        switch self {
        case .linear, .terminal: return true
        default: return false
        }
    }
}

@Observable
class SettingsManager {
    static let shared = SettingsManager()

    // MARK: - Batch Update Flag (prevents cascade Theme.invalidate() calls)

    /// When true, skip Theme.invalidate() in property didSets (call once at end of batch)
    @ObservationIgnored private var isBatchingUpdates = false

    // MARK: - Appearance Settings (UserDefaults - device-specific)

    private let appearanceModeKey = "appearanceMode"
    private let accentColorKey = "accentColor"
    private let uiFontStyleKey = "uiFontStyle"
    private let contentFontStyleKey = "contentFontStyle"
    private let fontSizeKey = "fontSize"  // Legacy, maps to uiFontSize
    private let uiFontSizeKey = "uiFontSize"
    private let contentFontSizeKey = "contentFontSize"
    private let currentThemeKey = "currentTheme"
    private let uiAllCapsKey = "uiAllCaps"

    /// The currently active theme preset
    var currentTheme: ThemePreset? {
        didSet {
            if let theme = currentTheme {
                UserDefaults.standard.set(theme.rawValue, forKey: currentThemeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: currentThemeKey)
            }
            if !isBatchingUpdates { Theme.invalidate() }
        }
    }

    /// Whether to use light/thin font weights (for sharp aesthetics)
    var useLightFonts: Bool {
        currentTheme == .talkiePro
    }

    /// Whether current theme uses high-contrast colors
    var useTacticalColors: Bool {
        currentTheme == .talkiePro
    }

    /// Check if minimal theme is active
    var isMinimalTheme: Bool {
        currentTheme == .minimal
    }

    /// Check if linear theme is active (Vercel/Linear-inspired)
    var isLinearTheme: Bool {
        currentTheme == .linear
    }

    /// Check if terminal theme is active
    var isTerminalTheme: Bool {
        currentTheme == .terminal
    }

    /// Check if warm theme is active
    var isWarmTheme: Bool {
        currentTheme == .warm
    }

    /// Check if classic theme is active
    var isClassicTheme: Bool {
        currentTheme == .classic
    }

    /// Whether currently in dark mode (respects manual override)
    var isDarkMode: Bool {
        switch appearanceMode {
        case .dark: return true
        case .light: return false
        case .system: return isSystemDarkMode
        }
    }

    /// Check if system is in dark mode
    var isSystemDarkMode: Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: appearanceModeKey)
            if !isBatchingUpdates { Theme.invalidate() }
            applyAppearanceMode()
        }
    }

    var accentColor: AccentColorOption {
        didSet {
            UserDefaults.standard.set(accentColor.rawValue, forKey: accentColorKey)
        }
    }

    /// Resolved accent color for UI elements (toggles, buttons, etc.)
    var resolvedAccentColor: Color {
        accentColor.color ?? .accentColor
    }

    /// Font style for UI chrome: labels, headers, buttons, badges, navigation
    var uiFontStyle: FontStyleOption {
        didSet {
            UserDefaults.standard.set(uiFontStyle.rawValue, forKey: uiFontStyleKey)
            if !isBatchingUpdates { Theme.invalidate() }
        }
    }

    /// Font style for content: transcripts, notes, markdown, user-generated text
    var contentFontStyle: FontStyleOption {
        didSet {
            UserDefaults.standard.set(contentFontStyle.rawValue, forKey: contentFontStyleKey)
            if !isBatchingUpdates { Theme.invalidate() }
        }
    }

    /// Legacy accessor - maps to uiFontStyle for backwards compatibility
    var fontStyle: FontStyleOption {
        get { uiFontStyle }
        set { uiFontStyle = newValue }
    }

    /// UI chrome font size (labels, headers, buttons, badges)
    var uiFontSize: FontSizeOption {
        didSet {
            UserDefaults.standard.set(uiFontSize.rawValue, forKey: uiFontSizeKey)
            if !isBatchingUpdates { Theme.invalidate() }
        }
    }

    /// Content font size (transcripts, notes, markdown)
    var contentFontSize: FontSizeOption {
        didSet {
            UserDefaults.standard.set(contentFontSize.rawValue, forKey: contentFontSizeKey)
            if !isBatchingUpdates { Theme.invalidate() }
        }
    }

    /// Whether UI chrome labels should be ALL CAPS (tactical style)
    var uiAllCaps: Bool {
        didSet {
            UserDefaults.standard.set(uiAllCaps, forKey: uiAllCapsKey)
        }
    }

    /// Text case for UI labels - returns .uppercase when uiAllCaps is enabled
    var uiTextCase: Text.Case? {
        uiAllCaps ? .uppercase : nil
    }

    /// Legacy accessor - maps to uiFontSize for backwards compatibility
    var fontSize: FontSizeOption {
        get { uiFontSize }
        set { uiFontSize = newValue }
    }

    /// Get a UI font with the current style and size settings applied
    func themedFont(baseSize: CGFloat, weight: Font.Weight = .regular) -> Font {
        let scaledSize = baseSize * uiFontSize.scale
        return uiFontStyle.font(size: scaledSize, weight: weight)
    }

    /// Get a content font with the current style and size settings applied
    func contentFont(baseSize: CGFloat, weight: Font.Weight = .regular) -> Font {
        let scaledSize = baseSize * contentFontSize.scale
        return contentFontStyle.font(size: scaledSize, weight: weight)
    }

    // MARK: - UI Font Tokens
    // For UI chrome: labels, headers, buttons, badges, navigation
    // Uses uiFontStyle (themed/branded)

    /// Extra small UI text - labels, badges (10pt base)
    var fontXS: Font { themedFont(baseSize: 10, weight: useLightFonts ? .regular : .regular) }
    var fontXSMedium: Font { themedFont(baseSize: 10, weight: useLightFonts ? .medium : .medium) }
    var fontXSBold: Font { themedFont(baseSize: 10, weight: useLightFonts ? .semibold : .semibold) }

    /// Small UI text - secondary info, metadata (11pt base)
    var fontSM: Font { themedFont(baseSize: 11, weight: useLightFonts ? .regular : .regular) }
    var fontSMMedium: Font { themedFont(baseSize: 11, weight: useLightFonts ? .medium : .medium) }
    var fontSMBold: Font { themedFont(baseSize: 11, weight: useLightFonts ? .semibold : .semibold) }

    /// Body UI text - primary UI elements (13pt base)
    var fontBody: Font { themedFont(baseSize: 13, weight: useLightFonts ? .regular : .regular) }
    var fontBodyMedium: Font { themedFont(baseSize: 13, weight: useLightFonts ? .medium : .medium) }
    var fontBodyBold: Font { themedFont(baseSize: 13, weight: useLightFonts ? .semibold : .semibold) }

    /// Title UI text - section headers (15pt base)
    var fontTitle: Font { themedFont(baseSize: 15, weight: useLightFonts ? .regular : .regular) }
    var fontTitleMedium: Font { themedFont(baseSize: 15, weight: useLightFonts ? .medium : .medium) }
    var fontTitleBold: Font { themedFont(baseSize: 15, weight: useLightFonts ? .semibold : .bold) }

    /// Headline UI text - large headers (18pt base)
    var fontHeadline: Font { themedFont(baseSize: 18, weight: useLightFonts ? .regular : .regular) }
    var fontHeadlineMedium: Font { themedFont(baseSize: 18, weight: useLightFonts ? .medium : .medium) }
    var fontHeadlineBold: Font { themedFont(baseSize: 18, weight: useLightFonts ? .semibold : .bold) }

    /// Display UI text - hero elements (32pt base)
    var fontDisplay: Font { themedFont(baseSize: 32, weight: .light) }
    var fontDisplayMedium: Font { themedFont(baseSize: 32, weight: useLightFonts ? .regular : .regular) }

    // MARK: - Theme Color Tokens
    // Returns themed colors based on active theme, falls back to system colors

    /// Primary background
    var tacticalBackground: Color {
        if useTacticalColors {
            return isDarkMode ? Color(white: 0.05) : Color(white: 0.96)
        }
        if isLinearTheme {
            // Linear: True black (#000) - Vercel/Linear style
            return Color.black
        }
        if isMinimalTheme {
            return isDarkMode ? Color(white: 0.11) : Color(white: 0.97)
        }
        if isTerminalTheme {
            // Terminal: Black in dark, paper-white in light
            return isDarkMode ? Color.black : Color(white: 0.97)
        }
        if isWarmTheme {
            // Warm: Rich brown-black in dark, warm cream in light
            return isDarkMode ? Color(red: 0.08, green: 0.06, blue: 0.04) : Color(red: 0.99, green: 0.97, blue: 0.94)
        }
        if isClassicTheme {
            // Classic: Dark gray in dark, clean white in light
            return isDarkMode ? Color(white: 0.12) : Color(white: 0.98)
        }
        return Color(NSColor.windowBackgroundColor)
    }

    /// Secondary background (slightly lighter/darker)
    var tacticalBackgroundSecondary: Color {
        if useTacticalColors {
            return isDarkMode ? Color(white: 0.08) : Color(white: 0.88)
        }
        if isLinearTheme {
            // Linear: Very dark gray (#0a0a0a) - subtle elevation
            return Color(white: 0.04)
        }
        if isMinimalTheme {
            return isDarkMode ? Color(white: 0.14) : Color(white: 0.94)
        }
        if isTerminalTheme {
            return isDarkMode ? Color(white: 0.06) : Color(white: 0.94)
        }
        if isWarmTheme {
            return isDarkMode ? Color(red: 0.12, green: 0.09, blue: 0.06) : Color(red: 0.96, green: 0.94, blue: 0.90)
        }
        if isClassicTheme {
            return isDarkMode ? Color(white: 0.15) : Color(white: 0.95)
        }
        return Color(NSColor.controlBackgroundColor)
    }

    /// Tertiary background for cards/panels
    var tacticalBackgroundTertiary: Color {
        if useTacticalColors {
            return isDarkMode ? Color(white: 0.12) : Color(white: 0.90)
        }
        if isLinearTheme {
            // Linear: Card surface (#111111) - for elevated cards
            return Color(white: 0.067)
        }
        if isMinimalTheme {
            return isDarkMode ? Color(white: 0.18) : Color(white: 0.91)
        }
        if isTerminalTheme {
            return isDarkMode ? Color(white: 0.10) : Color(white: 0.91)
        }
        if isWarmTheme {
            return isDarkMode ? Color(red: 0.16, green: 0.12, blue: 0.08) : Color(red: 0.93, green: 0.90, blue: 0.86)
        }
        if isClassicTheme {
            return isDarkMode ? Color(white: 0.18) : Color(white: 0.92)
        }
        return isDarkMode ? Color(white: 0.13) : Color(white: 0.94)
    }

    /// Primary text
    var tacticalForeground: Color {
        if useTacticalColors {
            return isDarkMode ? Color(white: 0.98) : Color(white: 0.08)
        }
        if isLinearTheme {
            // Linear: Pure white text - high contrast
            return Color.white
        }
        if isMinimalTheme {
            return isDarkMode ? Color(white: 0.92) : Color(white: 0.12)
        }
        if isTerminalTheme {
            // Terminal: Green in dark, dark green in light
            return isDarkMode ? Color(red: 0.0, green: 0.85, blue: 0.0) : Color(red: 0.0, green: 0.35, blue: 0.0)
        }
        if isWarmTheme {
            // Warm: Warm white in dark, rich brown in light
            return isDarkMode ? Color(red: 1.0, green: 0.95, blue: 0.88) : Color(red: 0.25, green: 0.18, blue: 0.12)
        }
        if isClassicTheme {
            return isDarkMode ? Color(white: 0.95) : Color(white: 0.10)
        }
        return Color.primary
    }

    /// Secondary text
    var tacticalForegroundSecondary: Color {
        if useTacticalColors {
            return isDarkMode ? Color(white: 0.72) : Color(white: 0.32)
        }
        if isLinearTheme {
            // Linear: Gray text (~#888) - for descriptions
            return Color(white: 0.53)
        }
        if isMinimalTheme {
            return isDarkMode ? Color(white: 0.65) : Color(white: 0.38)
        }
        if isTerminalTheme {
            return isDarkMode ? Color(red: 0.0, green: 0.65, blue: 0.0) : Color(red: 0.0, green: 0.45, blue: 0.0)
        }
        if isWarmTheme {
            return isDarkMode ? Color(red: 0.85, green: 0.78, blue: 0.68) : Color(red: 0.45, green: 0.38, blue: 0.30)
        }
        if isClassicTheme {
            return isDarkMode ? Color(white: 0.70) : Color(white: 0.35)
        }
        return Color.secondary
    }

    /// Muted text for timestamps, metadata
    var tacticalForegroundMuted: Color {
        if useTacticalColors {
            return isDarkMode ? Color(white: 0.52) : Color(white: 0.48)
        }
        if isLinearTheme {
            // Linear: Muted gray (~#666) - for metadata
            return Color(white: 0.40)
        }
        if isMinimalTheme {
            return isDarkMode ? Color(white: 0.48) : Color(white: 0.50)
        }
        if isTerminalTheme {
            return isDarkMode ? Color(red: 0.0, green: 0.45, blue: 0.0) : Color(red: 0.0, green: 0.55, blue: 0.0)
        }
        if isWarmTheme {
            return isDarkMode ? Color(red: 0.65, green: 0.58, blue: 0.48) : Color(red: 0.55, green: 0.48, blue: 0.40)
        }
        if isClassicTheme {
            return isDarkMode ? Color(white: 0.50) : Color(white: 0.50)
        }
        return isDarkMode ? Color(white: 0.42) : Color(white: 0.58)
    }

    /// Divider/border color
    var tacticalDivider: Color {
        if useTacticalColors {
            return isDarkMode ? Color(white: 0.2) : Color(white: 0.65)
        }
        if isLinearTheme {
            // Linear: Subtle border (white at ~10%) - minimal separation
            return Color.white.opacity(0.10)
        }
        if isMinimalTheme {
            return isDarkMode ? Color(white: 0.22) : Color(white: 0.88)
        }
        if isTerminalTheme {
            return isDarkMode ? Color(red: 0.0, green: 0.3, blue: 0.0) : Color(red: 0.0, green: 0.6, blue: 0.0).opacity(0.3)
        }
        if isWarmTheme {
            return isDarkMode ? Color(red: 0.3, green: 0.22, blue: 0.15) : Color(red: 0.85, green: 0.80, blue: 0.72)
        }
        if isClassicTheme {
            return isDarkMode ? Color(white: 0.25) : Color(white: 0.85)
        }
        return Color(NSColor.separatorColor)
    }

    // MARK: - Content Font Tokens
    // For user content: transcripts, notes, markdown, AI results
    // Uses contentFontStyle (optimized for readability)

    /// Small content text - footnotes, captions (10pt base)
    var contentFontSM: Font { contentFont(baseSize: 10, weight: .regular) }
    var contentFontSMMedium: Font { contentFont(baseSize: 10, weight: .medium) }

    /// Body content text - main transcripts, notes (13pt base)
    var contentFontBody: Font { contentFont(baseSize: 13, weight: .regular) }
    var contentFontBodyMedium: Font { contentFont(baseSize: 13, weight: .medium) }
    var contentFontBodyBold: Font { contentFont(baseSize: 13, weight: .bold) }

    /// Large content text - summaries, key points (15pt base)
    var contentFontLarge: Font { contentFont(baseSize: 15, weight: .regular) }
    var contentFontLargeMedium: Font { contentFont(baseSize: 15, weight: .medium) }
    var contentFontLargeBold: Font { contentFont(baseSize: 15, weight: .bold) }

    // MARK: - Surface System (Appearance-Aware)
    // Layered background surfaces from deepest to topmost
    // Adapts to light/dark appearance mode

    /// Surface Level 0: Window/App background (deepest layer)
    var surfaceBase: Color {
        if isLinearTheme {
            return Color.black
        }
        return isDarkMode ? Color(white: 0.05) : Color(white: 0.98)
    }

    /// Surface Level 1: Primary content areas (slightly elevated)
    var surface1: Color {
        if isLinearTheme {
            return Color(white: 0.04)
        }
        return isDarkMode ? Color(white: 0.08) : Color(white: 0.95)
    }

    /// Surface Level 2: Cards, panels, modals (more elevated)
    var surface2: Color {
        if isLinearTheme {
            return Color(white: 0.067)
        }
        return isDarkMode ? Color(white: 0.12) : Color(white: 0.92)
    }

    /// Surface Level 3: Elevated elements (popovers, tooltips, menus)
    var surface3: Color {
        if isLinearTheme {
            return Color(white: 0.10)
        }
        return isDarkMode ? Color(white: 0.16) : Color(white: 0.88)
    }

    /// Surface Overlay: Tint for depth effect
    var surfaceOverlay: Color {
        isDarkMode ? Color.black.opacity(0.12) : Color.black.opacity(0.04)
    }

    /// Surface Gradient: Subtle top highlight
    var surfaceGradientTop: Color {
        isDarkMode ? Color.white.opacity(0.02) : Color.white.opacity(0.5)
    }

    /// Text/Input background (slightly elevated from base)
    var surfaceInput: Color {
        if isLinearTheme {
            return Color(white: 0.05)
        }
        return isDarkMode ? Color(white: 0.08) : Color(white: 0.95)
    }

    // MARK: - Interactive Surface States (Appearance-Aware Solid Colors)
    // These are used as overlays on known backgrounds, so we pre-compute the blend result

    /// Hover state overlay - dark: 0.05+0.05=0.10, light: 0.95-0.05=0.90
    var surfaceHover: Color {
        if isLinearTheme {
            return Color(white: 0.08)
        }
        return isDarkMode ? Color(white: 0.10) : Color(white: 0.90)
    }

    /// Active/pressed state overlay - dark: 0.05+0.08=0.13, light: 0.95-0.08=0.87
    var surfaceActive: Color {
        if isLinearTheme {
            return Color(white: 0.10)
        }
        return isDarkMode ? Color(white: 0.13) : Color(white: 0.87)
    }

    /// Selected state overlay - dark: 0.05+0.1=0.15, light: 0.95-0.1=0.85
    var surfaceSelected: Color {
        if isLinearTheme {
            return Color(white: 0.12)
        }
        return isDarkMode ? Color(white: 0.15) : Color(white: 0.85)
    }

    /// Alternating row background (for lists) - dark: 0.05+0.02=0.07, light: 0.95-0.02=0.93
    var surfaceAlternate: Color {
        if isLinearTheme {
            return Color(white: 0.03)
        }
        return isDarkMode ? Color(white: 0.07) : Color(white: 0.93)
    }

    // MARK: - Semantic Surface Colors

    /// Success background tint
    var surfaceSuccess: Color {
        Color.green.opacity(0.08)
    }

    /// Warning background tint
    var surfaceWarning: Color {
        Color.orange.opacity(0.1)
    }

    /// Error background tint
    var surfaceError: Color {
        Color.red.opacity(0.1)
    }

    /// Info background tint
    var surfaceInfo: Color {
        Color.blue.opacity(0.1)
    }

    // MARK: - Border & Divider Colors (Appearance-Aware Solid Colors)

    /// Default border (subtle) - dark: ~0.13 (8% of white on 0.05), light: ~0.87 (8% of black on 0.95)
    var borderDefault: Color {
        isDarkMode ? Color(white: 0.13) : Color(white: 0.87)
    }

    /// Strong border (more visible) - dark: ~0.20 (15% of white on 0.05), light: ~0.80
    var borderStrong: Color {
        isDarkMode ? Color(white: 0.20) : Color(white: 0.80)
    }

    /// Divider for separating content - dark: ~0.11 (6% of white on 0.05), light: ~0.89
    var divider: Color {
        isDarkMode ? Color(white: 0.11) : Color(white: 0.89)
    }

    /// Success border
    var borderSuccess: Color {
        Color.green.opacity(0.25)
    }

    /// Ready/info border
    var borderInfo: Color {
        Color.blue.opacity(0.3)
    }

    // MARK: - Status Colors (Solid Pre-computed)

    var statusActive: Color { Color.green }
    // blue*0.7 ≈ (0, 0, 0.7)
    var statusReady: Color { Color(red: 0, green: 0.35, blue: 0.7) }
    // secondary*0.4 ≈ dark: 0.24, light: 0.60
    var statusOffline: Color {
        isDarkMode ? Color(white: 0.24) : Color(white: 0.60)
    }
    var statusWarning: Color { Color.orange }
    // red*0.7 ≈ (0.7, 0, 0)
    var statusError: Color { Color(red: 0.7, green: 0, blue: 0) }

    // MARK: - Shadow Intensities (Solid Pre-computed)
    // These are semi-transparent by nature (shadows need to blend), but we can optimize
    // by using appearance-aware solid colors when the background is known

    var shadowLight: Color { Color(white: 0, opacity: 0.04) }
    var shadowMedium: Color { Color(white: 0, opacity: 0.08) }
    var shadowStrong: Color { Color(white: 0, opacity: 0.15) }

    // MARK: - Typography Tokens

    /// Monospaced fonts for technical data
    var monoXS: Font { .system(size: 7, weight: .semibold, design: .monospaced) }
    var monoSM: Font { .system(size: 9, weight: .medium, design: .monospaced) }
    var monoBody: Font { .system(size: 12, weight: .medium, design: .monospaced) }
    var monoLarge: Font { .system(size: 14, weight: .medium, design: .monospaced) }

    /// Tracking values
    var trackingTight: CGFloat { 0.3 }
    var trackingNormal: CGFloat { 0.5 }
    var trackingWide: CGFloat { 0.8 }
    var trackingExtraWide: CGFloat { 1.5 }

    // MARK: - Spec/Label Colors (Appearance-Aware Solid Colors for data displays)

    // secondary*0.5 ≈ dark: 0.30, light: 0.70
    var specLabelColor: Color {
        isDarkMode ? Color(white: 0.30) : Color(white: 0.70)
    }
    // primary*0.85 ≈ dark: 0.85, light: 0.15
    var specValueColor: Color {
        isDarkMode ? Color(white: 0.85) : Color(white: 0.15)
    }
    // secondary*0.6 ≈ dark: 0.36, light: 0.64
    var specUnitColor: Color {
        isDarkMode ? Color(white: 0.36) : Color(white: 0.64)
    }

    // MARK: - Midnight Theme Colors (Appearance-Aware, Solid Colors)
    // Uses pre-computed solid colors instead of opacity blending for performance
    // Used for Models page and premium UI sections

    /// Midnight base: Background
    var midnightBase: Color {
        isDarkMode ? Color(white: 0.04) : Color(white: 0.98)
    }

    /// Midnight surface: Slightly elevated cards (dark: 0.04+0.02=0.06, light: 0.98-0.02=0.96)
    var midnightSurface: Color {
        isDarkMode ? Color(white: 0.06) : Color(white: 0.96)
    }

    /// Midnight surface hover: Mouse hover state
    var midnightSurfaceHover: Color {
        isDarkMode ? Color(white: 0.09) : Color(white: 0.93)
    }

    /// Midnight surface elevated: Expanded states
    var midnightSurfaceElevated: Color {
        isDarkMode ? Color(white: 0.08) : Color(white: 0.94)
    }

    /// Midnight border: Subtle card outlines
    var midnightBorder: Color {
        isDarkMode ? Color(white: 0.10) : Color(white: 0.90)
    }

    /// Midnight border active: Expanded/focused states
    var midnightBorderActive: Color {
        isDarkMode ? Color(white: 0.16) : Color(white: 0.82)
    }

    /// Midnight text primary: High contrast
    var midnightTextPrimary: Color {
        isDarkMode ? Color(white: 0.92) : Color(white: 0.12)
    }

    /// Midnight text secondary: Muted labels
    var midnightTextSecondary: Color {
        isDarkMode ? Color(white: 0.50) : Color(white: 0.45)
    }

    /// Midnight text tertiary: Very subtle hints
    var midnightTextTertiary: Color {
        isDarkMode ? Color(white: 0.30) : Color(white: 0.65)
    }

    /// Midnight accent bar: Section header vertical accent (default)
    var midnightAccentBar: Color { Color(red: 1.0, green: 0.6, blue: 0.2) }  // Orange/amber

    /// Section accent: Local Models - Purple/violet
    var midnightAccentLocalModels: Color { Color(red: 0.6, green: 0.4, blue: 1.0) }  // Purple

    /// Section accent: Speech-to-Text - Green
    var midnightAccentSTT: Color { Color(red: 0.3, green: 0.85, blue: 0.5) }  // Green

    /// Section accent: Cloud Providers - Blue
    var midnightAccentCloud: Color { Color(red: 0.4, green: 0.6, blue: 1.0) }  // Blue

    /// Midnight recommended badge background
    var midnightBadgeRecommended: Color {
        isDarkMode ? Color(red: 0.15, green: 0.13, blue: 0.03) : Color(red: 1.0, green: 0.97, blue: 0.88)
    }
    /// Midnight recommended badge border
    var midnightBadgeRecommendedBorder: Color {
        isDarkMode ? Color(red: 0.5, green: 0.43, blue: 0.1) : Color(red: 0.8, green: 0.68, blue: 0.16)
    }
    var midnightBadgeRecommendedText: Color {
        isDarkMode ? Color(red: 1.0, green: 0.85, blue: 0.2) : Color(red: 0.7, green: 0.5, blue: 0.0)
    }

    /// Midnight active status
    var midnightStatusActive: Color { Color(red: 0.3, green: 0.85, blue: 0.4) }  // Bright green

    /// Midnight ready status
    var midnightStatusReady: Color { Color(red: 0.3, green: 0.7, blue: 0.35) }  // Muted green

    /// Midnight download button
    var midnightButtonPrimary: Color {
        isDarkMode ? Color(white: 0.16) : Color(white: 0.90)
    }

    /// Midnight download button hover
    var midnightButtonHover: Color {
        isDarkMode ? Color(white: 0.22) : Color(white: 0.85)
    }

    // MARK: - Legacy Aliases (for backwards compatibility)
    // TODO: Migrate views to use new surface tokens, then remove these

    var cardBackground: Color { surface2 }
    var cardBackgroundHover: Color { surface3 }
    var cardBackgroundDark: Color { surfaceOverlay }
    var cardBorderDefault: Color { borderDefault }
    var cardBorderActive: Color { borderSuccess }
    var cardBorderReady: Color { borderInfo }
    var specDividerOpacity: Double { 0.08 }

    /// Apply a curated theme preset (batches updates to avoid cascade invalidations)
    func applyTheme(_ theme: ThemePreset) {
        isBatchingUpdates = true
        defer {
            isBatchingUpdates = false
            Theme.invalidate()  // Single invalidation at the end
        }

        currentTheme = theme
        appearanceMode = theme.appearanceMode
        uiFontStyle = theme.uiFontStyle
        contentFontStyle = theme.contentFontStyle
        accentColor = theme.accentColor
        fontSize = theme.fontSize
    }

    func applyAppearanceMode() {
        DispatchQueue.main.async {
            switch self.appearanceMode {
            case .system:
                NSApp.appearance = nil
            case .light:
                NSApp.appearance = NSAppearance(named: .aqua)
            case .dark:
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }

    // MARK: - Local File Storage Settings (UserDefaults - device-specific)
    // Where transcript and audio files live on disk - your data, your files
    // These are independent opt-in features for users who want local file ownership

    private let saveTranscriptsLocallyKey = "saveTranscriptsLocally"
    private let transcriptsFolderPathKey = "transcriptsFolderPath"
    private let saveAudioLocallyKey = "saveAudioLocally"
    private let audioFolderPathKey = "audioFolderPath"

    /// Default transcripts folder: ~/Documents/Talkie/Transcripts
    static var defaultTranscriptsFolderPath: String {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return NSTemporaryDirectory() + "Talkie/Transcripts"
        }
        return documentsPath.appendingPathComponent("Talkie/Transcripts").path
    }

    /// Default audio folder: ~/Documents/Talkie/Audio
    static var defaultAudioFolderPath: String {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return NSTemporaryDirectory() + "Talkie/Audio"
        }
        return documentsPath.appendingPathComponent("Talkie/Audio").path
    }

    /// Whether to save transcripts as Markdown files locally (default: false)
    var saveTranscriptsLocally: Bool {
        didSet {
            let value = saveTranscriptsLocally
            DispatchQueue.main.async {
                UserDefaults.standard.set(value, forKey: self.saveTranscriptsLocallyKey)
            }
        }
    }

    /// Where transcript files are saved
    var transcriptsFolderPath: String {
        didSet {
            let path = transcriptsFolderPath
            DispatchQueue.main.async {
                UserDefaults.standard.set(path, forKey: self.transcriptsFolderPathKey)
            }
        }
    }

    /// Whether to save M4A audio files locally (default: false)
    var saveAudioLocally: Bool {
        didSet {
            let value = saveAudioLocally
            DispatchQueue.main.async {
                UserDefaults.standard.set(value, forKey: self.saveAudioLocallyKey)
            }
        }
    }

    /// Where audio files are saved
    var audioFolderPath: String {
        didSet {
            let path = audioFolderPath
            DispatchQueue.main.async {
                UserDefaults.standard.set(path, forKey: self.audioFolderPathKey)
            }
        }
    }

    // Convenience accessors
    var localFilesEnabled: Bool { saveTranscriptsLocally || saveAudioLocally }
    var transcriptFilesEnabled: Bool { saveTranscriptsLocally }
    var localFilesIncludeAudio: Bool { saveAudioLocally }

    // MARK: - Auto-Run Workflow Settings (UserDefaults - device-specific)
    // Control whether auto-run workflows execute on synced memos

    private let autoRunWorkflowsEnabledKey = "autoRunWorkflowsEnabled"

    /// Whether auto-run workflows are enabled (default: false)
    /// When enabled, workflows marked as autoRun will execute automatically when memos sync
    /// Note: Only memos created in the last 5 minutes are processed (forward-only behavior)
    var autoRunWorkflowsEnabled: Bool {
        didSet {
            let value = autoRunWorkflowsEnabled
            DispatchQueue.main.async {
                UserDefaults.standard.set(value, forKey: self.autoRunWorkflowsEnabledKey)
            }
        }
    }

    // MARK: - LLM Quality Tier Settings (UserDefaults - device-specific)
    // Controls the default quality/cost tier for LLM calls in workflows

    private let llmQualityTierKey = "llmQualityTier"

    /// Global default cost tier for LLM calls (default: .budget for cost-consciousness)
    /// Individual workflow steps can override this with their own tier setting
    var llmCostTier: LLMCostTier {
        didSet {
            let tier = llmCostTier
            DispatchQueue.main.async {
                UserDefaults.standard.set(tier.rawValue, forKey: self.llmQualityTierKey)
            }
        }
    }

    // MARK: - CloudKit Sync Interval Settings (UserDefaults - device-specific)
    // Controls how often automatic sync occurs (manual sync always available)

    private let syncIntervalMinutesKey = "syncIntervalMinutes"
    private let jsonExportScheduleKey = "jsonExportSchedule"

    /// CloudKit sync interval in minutes (default: 10 minutes)
    /// Manual sync button is always available regardless of this setting
    var syncIntervalMinutes: Int {
        didSet {
            let minutes = syncIntervalMinutes
            DispatchQueue.main.async {
                UserDefaults.standard.set(minutes, forKey: self.syncIntervalMinutesKey)
            }
            // Notify CloudKitSyncManager to update its timer
            NotificationCenter.default.post(name: .syncIntervalDidChange, object: nil)
        }
    }

    /// Sync interval converted to seconds for use by CloudKitSyncManager
    var syncIntervalSeconds: TimeInterval {
        TimeInterval(syncIntervalMinutes * 60)
    }

    // MARK: - Audio Playback

    private let playbackVolumeKey = "playbackVolume"

    /// Audio playback volume (0.0 to 1.0, default 1.0)
    var playbackVolume: Float = 1.0 {
        didSet {
            let volume = playbackVolume
            DispatchQueue.main.async {
                UserDefaults.standard.set(volume, forKey: self.playbackVolumeKey)
            }
            NotificationCenter.default.post(name: .playbackVolumeDidChange, object: nil)
        }
    }

    /// JSON export schedule (default: daily shallow, weekly deep)
    var jsonExportSchedule: JSONExportSchedule {
        didSet {
            let schedule = jsonExportSchedule
            DispatchQueue.main.async {
                UserDefaults.standard.set(schedule.rawValue, forKey: self.jsonExportScheduleKey)
            }
            // Notify JSONExportService to update its timer
            NotificationCenter.default.post(name: .jsonExportScheduleDidChange, object: nil)
        }
    }

    // Internal storage - API keys now use Keychain (secure)
    private var _geminiApiKey: String = ""
    private var _openaiApiKey: String?
    private var _anthropicApiKey: String?
    private var _groqApiKey: String?
    private var _selectedModel: String = LLMConfig.shared.defaultModel(for: "gemini") ?? ""

    // Transcription model settings (consolidated from LiveSettings)
    private var _liveTranscriptionModelId: String = "whisper:openai_whisper-small"

    private let keychain = KeychainManager.shared

    // Public accessors that ensure initialization
    var geminiApiKey: String {
        get { ensureInitialized(); return _geminiApiKey }
        set {
            _geminiApiKey = newValue
            _ = keychain.save(newValue, for: KeychainManager.Key.geminiApiKey)
        }
    }

    var openaiApiKey: String? {
        get { ensureInitialized(); return _openaiApiKey }
        set {
            _openaiApiKey = newValue
            if let value = newValue {
                _ = keychain.save(value, for: KeychainManager.Key.openaiApiKey)
            } else {
                keychain.delete(KeychainManager.Key.openaiApiKey)
            }
        }
    }

    var anthropicApiKey: String? {
        get { ensureInitialized(); return _anthropicApiKey }
        set {
            _anthropicApiKey = newValue
            if let value = newValue {
                _ = keychain.save(value, for: KeychainManager.Key.anthropicApiKey)
            } else {
                keychain.delete(KeychainManager.Key.anthropicApiKey)
            }
        }
    }

    var groqApiKey: String? {
        get { ensureInitialized(); return _groqApiKey }
        set {
            _groqApiKey = newValue
            if let value = newValue {
                _ = keychain.save(value, for: KeychainManager.Key.groqApiKey)
            } else {
                keychain.delete(KeychainManager.Key.groqApiKey)
            }
        }
    }

    // MARK: - API Key Existence Checks (no password prompt)

    /// Check if API keys exist without fetching them (avoids password prompt)
    func hasOpenAIKey() -> Bool {
        keychain.exists(.openaiApiKey)
    }

    func hasAnthropicKey() -> Bool {
        keychain.exists(.anthropicApiKey)
    }

    func hasGroqKey() -> Bool {
        keychain.exists(.groqApiKey)
    }

    /// Fetch API key on demand (only when explicitly needed for edit/reveal)
    func fetchOpenAIKey() -> String? {
        keychain.retrieve(for: .openaiApiKey)
    }

    func fetchAnthropicKey() -> String? {
        keychain.retrieve(for: .anthropicApiKey)
    }

    func fetchGroqKey() -> String? {
        keychain.retrieve(for: .groqApiKey)
    }

    var selectedModel: String {
        get { ensureInitialized(); return _selectedModel }
        set { _selectedModel = newValue }
    }

    // Transcription model for Live Mode (real-time transcription)
    var liveTranscriptionModelId: String {
        get { ensureInitialized(); return _liveTranscriptionModelId }
        set { _liveTranscriptionModelId = newValue; saveSettings() }
    }

    private var context: NSManagedObjectContext {
        return PersistenceController.shared.container.viewContext
    }

    private var isInitialized = false

    private init() {
        StartupProfiler.shared.mark("singleton.SettingsManager.start")
        // Initialize appearance settings from UserDefaults
        if let modeString = UserDefaults.standard.string(forKey: appearanceModeKey),
           let mode = AppearanceMode(rawValue: modeString) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .system
        }

        if let colorString = UserDefaults.standard.string(forKey: accentColorKey),
           let color = AccentColorOption(rawValue: colorString) {
            self.accentColor = color
        } else {
            self.accentColor = .system
        }

        // Load UI font style (with migration from old fontStyle key)
        if let uiFontStyleString = UserDefaults.standard.string(forKey: uiFontStyleKey),
           let style = FontStyleOption(rawValue: uiFontStyleString) {
            self.uiFontStyle = style
        } else if let legacyFontStyleString = UserDefaults.standard.string(forKey: "fontStyle"),
                  let style = FontStyleOption(rawValue: legacyFontStyleString) {
            // Migrate from old single fontStyle setting
            self.uiFontStyle = style
        } else {
            self.uiFontStyle = .monospace  // Default to monospace for code-style UI
        }

        // Load content font style
        if let contentFontStyleString = UserDefaults.standard.string(forKey: contentFontStyleKey),
           let style = FontStyleOption(rawValue: contentFontStyleString) {
            self.contentFontStyle = style
        } else {
            self.contentFontStyle = .system  // Default to system for readable content
        }

        // Load UI font size (with migration from legacy fontSizeKey)
        if let uiFontSizeString = UserDefaults.standard.string(forKey: uiFontSizeKey),
           let size = FontSizeOption(rawValue: uiFontSizeString) {
            self.uiFontSize = size
        } else if let legacyFontSizeString = UserDefaults.standard.string(forKey: fontSizeKey),
                  let size = FontSizeOption(rawValue: legacyFontSizeString) {
            self.uiFontSize = size
        } else {
            self.uiFontSize = .medium
        }

        // Load content font size
        if let contentFontSizeString = UserDefaults.standard.string(forKey: contentFontSizeKey),
           let size = FontSizeOption(rawValue: contentFontSizeString) {
            self.contentFontSize = size
        } else {
            self.contentFontSize = .medium
        }

        // Load UI all caps setting (default: false)
        self.uiAllCaps = UserDefaults.standard.object(forKey: uiAllCapsKey) as? Bool ?? false

        // Load current theme
        if let themeString = UserDefaults.standard.string(forKey: currentThemeKey),
           let theme = ThemePreset(rawValue: themeString) {
            self.currentTheme = theme
        } else {
            self.currentTheme = nil
        }

        // Initialize local file storage settings from UserDefaults
        // Default: DISABLED - these are opt-in advanced features for data ownership
        self.saveTranscriptsLocally = UserDefaults.standard.object(forKey: saveTranscriptsLocallyKey) as? Bool ?? false
        self.transcriptsFolderPath = UserDefaults.standard.string(forKey: transcriptsFolderPathKey) ?? SettingsManager.defaultTranscriptsFolderPath
        self.saveAudioLocally = UserDefaults.standard.object(forKey: saveAudioLocallyKey) as? Bool ?? false
        self.audioFolderPath = UserDefaults.standard.string(forKey: audioFolderPathKey) ?? SettingsManager.defaultAudioFolderPath

        // Initialize auto-run workflow settings
        // Default: DISABLED - user must opt-in to auto-run workflows
        self.autoRunWorkflowsEnabled = UserDefaults.standard.object(forKey: autoRunWorkflowsEnabledKey) as? Bool ?? false

        // Initialize LLM cost tier
        // Default: .budget for cost-consciousness
        if let tierString = UserDefaults.standard.string(forKey: llmQualityTierKey),
           let tier = LLMCostTier(rawValue: tierString) {
            self.llmCostTier = tier
        } else {
            self.llmCostTier = .budget
        }

        // Initialize sync interval
        // Default: 10 minutes - manual sync always available
        if let savedMinutes = UserDefaults.standard.object(forKey: syncIntervalMinutesKey) as? Int {
            self.syncIntervalMinutes = savedMinutes
        } else {
            self.syncIntervalMinutes = 10
        }

        // Initialize JSON export schedule
        // Default: daily shallow (recent memos), weekly deep (everything)
        if let scheduleString = UserDefaults.standard.string(forKey: jsonExportScheduleKey),
           let schedule = JSONExportSchedule(rawValue: scheduleString) {
            self.jsonExportSchedule = schedule
        } else {
            self.jsonExportSchedule = .dailyShallowWeeklyDeep
        }

        // Initialize playback volume
        // Default: 1.0 (full volume)
        if let savedVolume = UserDefaults.standard.object(forKey: playbackVolumeKey) as? Float {
            self.playbackVolume = savedVolume
        } else {
            self.playbackVolume = 1.0
        }

        // Apply appearance mode on launch
        applyAppearanceMode()

        // Defer Core Data access until first use
        StartupProfiler.shared.mark("singleton.SettingsManager.done")
    }

    private func ensureInitialized() {
        guard !isInitialized else { return }
        isInitialized = true
        performLoadSettings()
    }

    // MARK: - Load Settings
    func loadSettings() {
        // Public method - always reload
        performLoadSettings()
    }

    private func performLoadSettings() {
        // Load API keys from Keychain (secure storage)
        let geminiFromKeychain = keychain.retrieve(for: KeychainManager.Key.geminiApiKey) ?? ""
        let openaiFromKeychain = keychain.retrieve(for: KeychainManager.Key.openaiApiKey)
        let anthropicFromKeychain = keychain.retrieve(for: KeychainManager.Key.anthropicApiKey)
        let groqFromKeychain = keychain.retrieve(for: KeychainManager.Key.groqApiKey)

        // Load non-sensitive settings from Core Data
        let fetchRequest: NSFetchRequest<AppSettings> = AppSettings.fetchRequest()

        do {
            let results = try context.fetch(fetchRequest)
            if let settings = results.first {
                let model = settings.selectedModel ?? LLMConfig.shared.defaultModel(for: "gemini") ?? ""
                let liveModelId = settings.liveTranscriptionModelId ?? "whisper:openai_whisper-small"

                // Check if we need to migrate API keys from Core Data to Keychain
                let hasCoreDataKeys = (settings.geminiApiKey != nil && !settings.geminiApiKey!.isEmpty) ||
                                      (settings.openaiApiKey != nil && !settings.openaiApiKey!.isEmpty) ||
                                      (settings.anthropicApiKey != nil && !settings.anthropicApiKey!.isEmpty) ||
                                      (settings.groqApiKey != nil && !settings.groqApiKey!.isEmpty)

                if hasCoreDataKeys {
                    // Migrate from Core Data to Keychain
                    _ = keychain.migrateFromCoreData(
                        geminiKey: settings.geminiApiKey,
                        openaiKey: settings.openaiApiKey,
                        anthropicKey: settings.anthropicApiKey,
                        groqKey: settings.groqApiKey
                    ) { [weak self] in
                        // Clear API keys from Core Data after migration
                        self?.clearApiKeysFromCoreData()
                    }

                    // Use migrated values
                    let gemini = keychain.retrieve(for: KeychainManager.Key.geminiApiKey) ?? ""
                    let openai = keychain.retrieve(for: KeychainManager.Key.openaiApiKey)
                    let anthropic = keychain.retrieve(for: KeychainManager.Key.anthropicApiKey)
                    let groq = keychain.retrieve(for: KeychainManager.Key.groqApiKey)

                    DispatchQueue.main.async {
                        self._geminiApiKey = gemini
                        self._openaiApiKey = openai
                        self._anthropicApiKey = anthropic
                        self._groqApiKey = groq
                        self._selectedModel = model
                        self._liveTranscriptionModelId = liveModelId
                    }
                } else {
                    // Use Keychain values directly
                    DispatchQueue.main.async {
                        self._geminiApiKey = geminiFromKeychain
                        self._openaiApiKey = openaiFromKeychain
                        self._anthropicApiKey = anthropicFromKeychain
                        self._groqApiKey = groqFromKeychain
                        self._selectedModel = model
                        self._liveTranscriptionModelId = liveModelId
                    }
                }
            } else {
                logger.info("No settings found in Core Data, creating defaults")
                createDefaultSettings()

                // Still load from Keychain if available
                DispatchQueue.main.async {
                    self._geminiApiKey = geminiFromKeychain
                    self._openaiApiKey = openaiFromKeychain
                    self._anthropicApiKey = anthropicFromKeychain
                    self._groqApiKey = groqFromKeychain
                }
            }

            // Migrate transcription model from LiveSettings if needed
            // This runs once to migrate from the old UserDefaults key
            if let legacyModelId = UserDefaults.standard.string(forKey: "selectedModelId") {
                logger.info("Migrating transcription model from LiveSettings: \(legacyModelId)")
                DispatchQueue.main.async {
                    self._liveTranscriptionModelId = legacyModelId
                }
                // Clear old key (AppStorage auto-saves)
                UserDefaults.standard.removeObject(forKey: "selectedModelId")
            }
        } catch {
            logger.error("Failed to load settings: \(error.localizedDescription)")

            // Fall back to Keychain values on error
            DispatchQueue.main.async {
                self._geminiApiKey = geminiFromKeychain
                self._openaiApiKey = openaiFromKeychain
                self._anthropicApiKey = anthropicFromKeychain
                self._groqApiKey = groqFromKeychain
            }
        }
    }

    /// Clear API keys from Core Data after migration to Keychain
    private func clearApiKeysFromCoreData() {
        let fetchRequest: NSFetchRequest<AppSettings> = AppSettings.fetchRequest()

        do {
            let results = try context.fetch(fetchRequest)
            if let settings = results.first {
                settings.geminiApiKey = nil
                settings.openaiApiKey = nil
                settings.anthropicApiKey = nil
                settings.groqApiKey = nil
                settings.lastModified = Date()
                try context.save()
                logger.info("Cleared API keys from Core Data (migrated to Keychain)")
            }
        } catch {
            logger.error("Failed to clear API keys from Core Data: \(error.localizedDescription)")
        }
    }

    // MARK: - Save Settings
    func saveSettings() {
        ensureInitialized()

        // API keys are automatically saved to Keychain via property setters
        // Only save non-sensitive settings to Core Data
        let fetchRequest: NSFetchRequest<AppSettings> = AppSettings.fetchRequest()

        do {
            let results = try context.fetch(fetchRequest)
            let settings: AppSettings

            if let existingSettings = results.first {
                settings = existingSettings
            } else {
                settings = AppSettings(context: context)
                settings.id = UUID()
            }

            // Only save non-sensitive data to Core Data
            // API keys are stored securely in Keychain
            settings.selectedModel = selectedModel
            settings.liveTranscriptionModelId = liveTranscriptionModelId
            settings.lastModified = Date()

            try context.save()
            logger.debug("Settings saved successfully")
        } catch {
            logger.error("Failed to save settings: \(error.localizedDescription)")
        }
    }

    // MARK: - Create Default Settings
    private func createDefaultSettings() {
        let defaultModel = LLMConfig.shared.defaultModel(for: "gemini") ?? ""

        let settings = AppSettings(context: context)
        settings.id = UUID()
        // API keys are stored in Keychain, not Core Data
        settings.selectedModel = defaultModel
        settings.liveTranscriptionModelId = "whisper:openai_whisper-small"
        settings.lastModified = Date()

        do {
            try context.save()
            // Use async to avoid "publishing changes during view updates" warning
            DispatchQueue.main.async {
                self._selectedModel = defaultModel
                self._liveTranscriptionModelId = "whisper:openai_whisper-small"
            }
            logger.debug("Created default settings")
        } catch {
            logger.error("Failed to create default settings: \(error.localizedDescription)")
        }
    }

    // MARK: - Validation
    var hasValidApiKey: Bool {
        ensureInitialized()
        return !geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - JSON Export
    /// Export current settings as JSON (excluding sensitive data like API keys)
    func exportSettingsAsJSON() -> String {
        ensureInitialized()

        var settings: [String: Any] = [:]

        // Appearance
        settings["appearance"] = [
            "mode": appearanceMode.rawValue,
            "accentColor": accentColor.rawValue,
            "fontStyle": fontStyle.rawValue,
            "fontSize": fontSize.rawValue
        ]

        // Dictation
        settings["dictation"] = [
            "liveTranscriptionModelId": liveTranscriptionModelId
        ]

        // Local Files
        settings["localStorage"] = [
            "saveTranscriptsLocally": saveTranscriptsLocally,
            "transcriptsFolderPath": transcriptsFolderPath,
            "saveAudioLocally": saveAudioLocally,
            "audioFolderPath": audioFolderPath
        ]

        // Automations
        settings["automations"] = [
            "autoRunWorkflowsEnabled": autoRunWorkflowsEnabled
        ]

        // Sync
        settings["sync"] = [
            "syncOnLaunch": syncOnLaunch,
            "syncIntervalMinutes": syncIntervalMinutes,
            "minimumSyncInterval": minimumSyncInterval
        ]

        // AI Models (masked keys)
        settings["aiModels"] = [
            "selectedModel": selectedModel,
            "openaiApiKey": maskApiKey(openaiApiKey),
            "anthropicApiKey": maskApiKey(anthropicApiKey),
            "groqApiKey": maskApiKey(groqApiKey),
            "geminiApiKey": maskApiKey(geminiApiKey)
        ]

        // Convert to JSON
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            return String(data: jsonData, encoding: .utf8) ?? "{}"
        } catch {
            logger.error("Failed to serialize settings to JSON: \(error.localizedDescription)")
            return "{\"error\": \"Failed to serialize settings\"}"
        }
    }

    /// Mask API key for display (show last 4 characters)
    private func maskApiKey(_ key: String?) -> String {
        guard let key = key, !key.isEmpty else {
            return "[not set]"
        }

        // Show prefix + last 4 chars for OpenAI/Anthropic style keys
        if key.count > 8 {
            let prefix = key.prefix(3) // "sk-" or "ant"
            let suffix = key.suffix(4)
            return "\(prefix)...\(suffix)"
        }

        return "[hidden]"
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let syncIntervalDidChange = Notification.Name("syncIntervalDidChange")
    static let jsonExportScheduleDidChange = Notification.Name("jsonExportScheduleDidChange")
    static let playbackVolumeDidChange = Notification.Name("playbackVolumeDidChange")
}

// MARK: - JSON Export Schedule
enum JSONExportSchedule: String, Codable, CaseIterable {
    case manual = "manual"
    case dailyShallow = "dailyShallow"
    case dailyShallowWeeklyDeep = "dailyShallowWeeklyDeep"
    case weeklyDeep = "weeklyDeep"

    var displayName: String {
        switch self {
        case .manual: return "Manual only"
        case .dailyShallow: return "Daily (recent)"
        case .dailyShallowWeeklyDeep: return "Daily + Weekly"
        case .weeklyDeep: return "Weekly (all)"
        }
    }

    var description: String {
        switch self {
        case .manual: return "Export manually when needed"
        case .dailyShallow: return "Daily export of recent recordings"
        case .dailyShallowWeeklyDeep: return "Daily recent + weekly full export"
        case .weeklyDeep: return "Weekly full export of all recordings"
        }
    }
}
