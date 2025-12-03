//
//  SettingsManager.swift
//  Talkie macOS
//
//  Manages app settings stored in Core Data
//

import Foundation
import CoreData
import SwiftUI
import AppKit

// MARK: - Appearance Mode
enum AppearanceMode: String, CaseIterable {
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

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
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
enum FontSizeOption: String, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"

    var displayName: String {
        rawValue.capitalized
    }

    var scale: CGFloat {
        switch self {
        case .small: return 0.9   // Tight but readable
        case .medium: return 1.0
        case .large: return 1.15
        }
    }

    var icon: String {
        switch self {
        case .small: return "textformat.size.smaller"
        case .medium: return "textformat.size"
        case .large: return "textformat.size.larger"
        }
    }

    /// Preview font size for the label itself
    var previewFontSize: CGFloat {
        switch self {
        case .small: return 9
        case .medium: return 11
        case .large: return 13
        }
    }
}

// MARK: - Curated Theme Presets
enum ThemePreset: String, CaseIterable {
    case talkiePro = "talkiePro"
    case terminal = "terminal"
    case minimal = "minimal"
    case classic = "classic"
    case warm = "warm"

    var displayName: String {
        switch self {
        case .talkiePro: return "Talkie Pro"
        case .terminal: return "Terminal"
        case .minimal: return "Minimal"
        case .classic: return "Classic"
        case .warm: return "Warm"
        }
    }

    var description: String {
        switch self {
        case .talkiePro: return "Sharp, professional, high contrast"
        case .terminal: return "Terminal vibes with green accents"
        case .minimal: return "Clean and subtle, adapts to system"
        case .classic: return "Comfortable defaults with blue accents"
        case .warm: return "Cozy dark mode with orange tones"
        }
    }

    var icon: String {
        switch self {
        case .talkiePro: return "waveform"
        case .terminal: return "terminal"
        case .minimal: return "circle"
        case .classic: return "star"
        case .warm: return "flame"
        }
    }

    var previewColors: (bg: Color, fg: Color, accent: Color) {
        switch self {
        case .talkiePro:
            return (Color(white: 0.08), Color.white.opacity(0.85), Color(red: 0.4, green: 0.7, blue: 1.0))
        case .terminal:
            return (Color.black, Color.green.opacity(0.9), Color.green)
        case .minimal:
            return (Color(white: 0.96), Color.black.opacity(0.8), Color.gray)
        case .classic:
            return (Color(white: 0.15), Color.white.opacity(0.9), Color.blue)
        case .warm:
            return (Color(red: 0.1, green: 0.08, blue: 0.06), Color.white.opacity(0.9), Color.orange)
        }
    }

    // Theme preset values
    var appearanceMode: AppearanceMode {
        switch self {
        case .talkiePro: return .dark
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
        case .terminal: return .monospace   // Full terminal experience
        case .minimal: return .system       // Clean system font for content
        case .classic: return .system       // Standard system font
        case .warm: return .monospace       // Monospace content for warm theme
        }
    }

    var accentColor: AccentColorOption {
        switch self {
        case .talkiePro: return .blue
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
        case .terminal: return .medium
        case .minimal: return .medium
        case .classic: return .medium
        case .warm: return .medium
        }
    }
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

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
    @Published var currentTheme: ThemePreset? {
        didSet {
            if let theme = currentTheme {
                UserDefaults.standard.set(theme.rawValue, forKey: currentThemeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: currentThemeKey)
            }
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

    /// Check if system is in dark mode
    var isSystemDarkMode: Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    @Published var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: appearanceModeKey)
            applyAppearanceMode()
        }
    }

    @Published var accentColor: AccentColorOption {
        didSet {
            UserDefaults.standard.set(accentColor.rawValue, forKey: accentColorKey)
        }
    }

    /// Resolved accent color for UI elements (toggles, buttons, etc.)
    var resolvedAccentColor: Color {
        accentColor.color ?? .accentColor
    }

    /// Font style for UI chrome: labels, headers, buttons, badges, navigation
    @Published var uiFontStyle: FontStyleOption {
        didSet {
            UserDefaults.standard.set(uiFontStyle.rawValue, forKey: uiFontStyleKey)
        }
    }

    /// Font style for content: transcripts, notes, markdown, user-generated text
    @Published var contentFontStyle: FontStyleOption {
        didSet {
            UserDefaults.standard.set(contentFontStyle.rawValue, forKey: contentFontStyleKey)
        }
    }

    /// Legacy accessor - maps to uiFontStyle for backwards compatibility
    var fontStyle: FontStyleOption {
        get { uiFontStyle }
        set { uiFontStyle = newValue }
    }

    /// UI chrome font size (labels, headers, buttons, badges)
    @Published var uiFontSize: FontSizeOption {
        didSet {
            UserDefaults.standard.set(uiFontSize.rawValue, forKey: uiFontSizeKey)
        }
    }

    /// Content font size (transcripts, notes, markdown)
    @Published var contentFontSize: FontSizeOption {
        didSet {
            UserDefaults.standard.set(contentFontSize.rawValue, forKey: contentFontSizeKey)
        }
    }

    /// Whether UI chrome labels should be ALL CAPS (tactical style)
    @Published var uiAllCaps: Bool {
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
            return appearanceMode == .dark ? Color(white: 0.05) : Color(white: 0.98)
        }
        if isMinimalTheme {
            return isSystemDarkMode ? Color(white: 0.11) : Color(white: 0.97)
        }
        return Color(NSColor.windowBackgroundColor)
    }

    /// Secondary background (slightly lighter/darker)
    var tacticalBackgroundSecondary: Color {
        if useTacticalColors {
            return appearanceMode == .dark ? Color(white: 0.08) : Color(white: 0.94)
        }
        if isMinimalTheme {
            return isSystemDarkMode ? Color(white: 0.14) : Color(white: 0.94)
        }
        return Color(NSColor.controlBackgroundColor)
    }

    /// Tertiary background for cards/panels
    var tacticalBackgroundTertiary: Color {
        if useTacticalColors {
            return appearanceMode == .dark ? Color(white: 0.12) : Color(white: 0.90)
        }
        if isMinimalTheme {
            return isSystemDarkMode ? Color(white: 0.18) : Color(white: 0.91)
        }
        return Color(NSColor.controlBackgroundColor).opacity(0.5)
    }

    /// Primary text
    var tacticalForeground: Color {
        if useTacticalColors {
            return appearanceMode == .dark ? Color(white: 0.98) : Color(white: 0.08)
        }
        if isMinimalTheme {
            return isSystemDarkMode ? Color(white: 0.92) : Color(white: 0.12)
        }
        return Color.primary
    }

    /// Secondary text
    var tacticalForegroundSecondary: Color {
        if useTacticalColors {
            return appearanceMode == .dark ? Color(white: 0.72) : Color(white: 0.32)
        }
        if isMinimalTheme {
            return isSystemDarkMode ? Color(white: 0.65) : Color(white: 0.38)
        }
        return Color.secondary
    }

    /// Muted text for timestamps, metadata
    var tacticalForegroundMuted: Color {
        if useTacticalColors {
            return appearanceMode == .dark ? Color(white: 0.52) : Color(white: 0.48)
        }
        if isMinimalTheme {
            return isSystemDarkMode ? Color(white: 0.48) : Color(white: 0.50)
        }
        return Color.secondary.opacity(0.7)
    }

    /// Divider/border color
    var tacticalDivider: Color {
        if useTacticalColors {
            return appearanceMode == .dark ? Color(white: 0.2) : Color(white: 0.85)
        }
        if isMinimalTheme {
            return isSystemDarkMode ? Color(white: 0.22) : Color(white: 0.88)
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

    // MARK: - Surface System (Talkie Pro)
    // Layered background surfaces from deepest to topmost
    // Other themes can override these tokens for their own look

    /// Surface Level 0: Window/App background (deepest layer)
    var surfaceBase: Color {
        Color(NSColor.windowBackgroundColor)
    }

    /// Surface Level 1: Primary content areas (sidebar, main content)
    var surface1: Color {
        Color(NSColor.controlBackgroundColor)
    }

    /// Surface Level 2: Cards, panels, modals
    var surface2: Color {
        Color(NSColor.controlBackgroundColor).opacity(0.7)
    }

    /// Surface Level 3: Elevated elements (popovers, tooltips, menus)
    var surface3: Color {
        Color(NSColor.controlBackgroundColor).opacity(0.9)
    }

    /// Surface Overlay: Dark tint for premium depth effect
    var surfaceOverlay: Color {
        Color.black.opacity(0.12)
    }

    /// Surface Gradient: Subtle top highlight
    var surfaceGradientTop: Color {
        Color.primary.opacity(0.03)
    }

    /// Text/Input background
    var surfaceInput: Color {
        Color(NSColor.textBackgroundColor)
    }

    // MARK: - Interactive Surface States

    /// Hover state overlay
    var surfaceHover: Color {
        Color.primary.opacity(0.05)
    }

    /// Active/pressed state overlay
    var surfaceActive: Color {
        Color.primary.opacity(0.08)
    }

    /// Selected state overlay
    var surfaceSelected: Color {
        Color.primary.opacity(0.1)
    }

    /// Alternating row background (for lists)
    var surfaceAlternate: Color {
        Color.primary.opacity(0.02)
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

    // MARK: - Border & Divider Colors

    /// Default border (subtle)
    var borderDefault: Color {
        Color.primary.opacity(0.08)
    }

    /// Strong border (more visible)
    var borderStrong: Color {
        Color.primary.opacity(0.15)
    }

    /// Divider for separating content
    var divider: Color {
        Color.primary.opacity(0.06)
    }

    /// Success border
    var borderSuccess: Color {
        Color.green.opacity(0.25)
    }

    /// Ready/info border
    var borderInfo: Color {
        Color.blue.opacity(0.3)
    }

    // MARK: - Status Colors

    var statusActive: Color { Color.green }
    var statusReady: Color { Color.blue.opacity(0.7) }
    var statusOffline: Color { Color.secondary.opacity(0.4) }
    var statusWarning: Color { Color.orange }
    var statusError: Color { Color.red.opacity(0.7) }

    // MARK: - Shadow Intensities

    var shadowLight: Color { Color.black.opacity(0.04) }
    var shadowMedium: Color { Color.black.opacity(0.08) }
    var shadowStrong: Color { Color.black.opacity(0.15) }

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

    // MARK: - Spec/Label Colors (for data displays)

    var specLabelColor: Color { Color.secondary.opacity(0.5) }
    var specValueColor: Color { Color.primary.opacity(0.85) }
    var specUnitColor: Color { Color.secondary.opacity(0.6) }

    // MARK: - Midnight Theme Colors (Website Aesthetic)
    // True black backgrounds with high contrast white text
    // Used for Models page and premium UI sections

    /// Midnight base: True black background
    var midnightBase: Color { Color(white: 0.04) }

    /// Midnight surface: Slightly elevated cards
    var midnightSurface: Color { Color(white: 0.08) }

    /// Midnight surface elevated: Hover/expanded states
    var midnightSurfaceElevated: Color { Color(white: 0.11) }

    /// Midnight border: Subtle card outlines
    var midnightBorder: Color { Color.white.opacity(0.06) }

    /// Midnight border active: Expanded/focused states
    var midnightBorderActive: Color { Color.white.opacity(0.12) }

    /// Midnight text primary: High contrast white
    var midnightTextPrimary: Color { Color.white.opacity(0.92) }

    /// Midnight text secondary: Muted labels
    var midnightTextSecondary: Color { Color.white.opacity(0.5) }

    /// Midnight text tertiary: Very subtle hints
    var midnightTextTertiary: Color { Color.white.opacity(0.3) }

    /// Midnight accent bar: Section header vertical accent
    var midnightAccentBar: Color { Color(red: 1.0, green: 0.6, blue: 0.2) }  // Orange/amber

    /// Midnight recommended badge
    var midnightBadgeRecommended: Color { Color(red: 1.0, green: 0.85, blue: 0.2) }  // Gold/yellow

    /// Midnight active status
    var midnightStatusActive: Color { Color(red: 0.3, green: 0.85, blue: 0.4) }  // Bright green

    /// Midnight ready status
    var midnightStatusReady: Color { Color(red: 0.3, green: 0.7, blue: 0.35) }  // Muted green

    /// Midnight download button
    var midnightButtonPrimary: Color { Color.white.opacity(0.12) }

    /// Midnight download button hover
    var midnightButtonHover: Color { Color.white.opacity(0.18) }

    // MARK: - Legacy Aliases (for backwards compatibility)
    // TODO: Migrate views to use new surface tokens, then remove these

    var cardBackground: Color { surface2 }
    var cardBackgroundHover: Color { surface3 }
    var cardBackgroundDark: Color { surfaceOverlay }
    var cardBorderDefault: Color { borderDefault }
    var cardBorderActive: Color { borderSuccess }
    var cardBorderReady: Color { borderInfo }
    var specDividerOpacity: Double { 0.08 }

    /// Apply a curated theme preset
    func applyTheme(_ theme: ThemePreset) {
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
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("Talkie/Transcripts").path
    }

    /// Default audio folder: ~/Documents/Talkie/Audio
    static var defaultAudioFolderPath: String {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("Talkie/Audio").path
    }

    /// Whether to save transcripts as Markdown files locally (default: false)
    @Published var saveTranscriptsLocally: Bool {
        didSet {
            UserDefaults.standard.set(saveTranscriptsLocally, forKey: saveTranscriptsLocallyKey)
        }
    }

    /// Where transcript files are saved
    @Published var transcriptsFolderPath: String {
        didSet {
            UserDefaults.standard.set(transcriptsFolderPath, forKey: transcriptsFolderPathKey)
        }
    }

    /// Whether to save M4A audio files locally (default: false)
    @Published var saveAudioLocally: Bool {
        didSet {
            UserDefaults.standard.set(saveAudioLocally, forKey: saveAudioLocallyKey)
        }
    }

    /// Where audio files are saved
    @Published var audioFolderPath: String {
        didSet {
            UserDefaults.standard.set(audioFolderPath, forKey: audioFolderPathKey)
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
    @Published var autoRunWorkflowsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoRunWorkflowsEnabled, forKey: autoRunWorkflowsEnabledKey)
        }
    }

    // Internal storage
    @Published private var _geminiApiKey: String = ""
    @Published private var _openaiApiKey: String?
    @Published private var _anthropicApiKey: String?
    @Published private var _groqApiKey: String?
    @Published private var _selectedModel: String = LLMConfig.shared.defaultModel(for: "gemini") ?? ""

    // Public accessors that ensure initialization
    var geminiApiKey: String {
        get { ensureInitialized(); return _geminiApiKey }
        set { _geminiApiKey = newValue }
    }

    var openaiApiKey: String? {
        get { ensureInitialized(); return _openaiApiKey }
        set { _openaiApiKey = newValue }
    }

    var anthropicApiKey: String? {
        get { ensureInitialized(); return _anthropicApiKey }
        set { _anthropicApiKey = newValue }
    }

    var groqApiKey: String? {
        get { ensureInitialized(); return _groqApiKey }
        set { _groqApiKey = newValue }
    }

    var selectedModel: String {
        get { ensureInitialized(); return _selectedModel }
        set { _selectedModel = newValue }
    }

    private var context: NSManagedObjectContext {
        return PersistenceController.shared.container.viewContext
    }

    private var isInitialized = false

    private init() {
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

        // Apply appearance mode on launch
        applyAppearanceMode()

        // Defer Core Data access until first use
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
        let fetchRequest: NSFetchRequest<AppSettings> = AppSettings.fetchRequest()

        do {
            let results = try context.fetch(fetchRequest)
            if let settings = results.first {
                // Store values locally first
                let gemini = settings.geminiApiKey ?? ""
                let openai = settings.openaiApiKey
                let anthropic = settings.anthropicApiKey
                let groq = settings.groqApiKey
                let model = settings.selectedModel ?? LLMConfig.shared.defaultModel(for: "gemini") ?? ""

                // Update @Published properties on main thread
                // Use sync if already on main, async otherwise
                let updateBlock = {
                    self._geminiApiKey = gemini
                    self._openaiApiKey = openai
                    self._anthropicApiKey = anthropic
                    self._groqApiKey = groq
                    self._selectedModel = model
                }

                if Thread.isMainThread {
                    updateBlock()
                } else {
                    DispatchQueue.main.sync { updateBlock() }
                }

                // Settings loaded silently - API key status visible in Models UI
            } else {
                print("⚠️ No settings found in Core Data, creating defaults...")
                createDefaultSettings()
            }
        } catch {
            print("❌ Failed to load settings: \(error)")
        }
    }

    // MARK: - Save Settings
    func saveSettings() {
        ensureInitialized()
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

            settings.geminiApiKey = geminiApiKey
            settings.openaiApiKey = openaiApiKey
            settings.anthropicApiKey = anthropicApiKey
            settings.groqApiKey = groqApiKey
            settings.selectedModel = selectedModel
            settings.lastModified = Date()

            try context.save()
            print("✅ Settings saved successfully")
        } catch {
            print("❌ Failed to save settings: \(error)")
        }
    }

    // MARK: - Create Default Settings
    private func createDefaultSettings() {
        let defaultModel = LLMConfig.shared.defaultModel(for: "gemini") ?? ""

        let settings = AppSettings(context: context)
        settings.id = UUID()
        settings.geminiApiKey = ""
        settings.selectedModel = defaultModel
        settings.lastModified = Date()

        do {
            try context.save()
            self._geminiApiKey = ""
            self._selectedModel = defaultModel
            print("✅ Created default settings")
        } catch {
            print("❌ Failed to create default settings: \(error)")
        }
    }

    // MARK: - Validation
    var hasValidApiKey: Bool {
        ensureInitialized()
        return !geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
