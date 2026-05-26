//
//  SettingsManager.swift
//  Talkie macOS
//
//  Manages app settings stored in UserDefaults
//  API keys are stored securely in macOS Keychain
//

import Foundation
import SwiftUI
import AppKit
import CoreData
import os
import Observation
import TalkieKit
#if canImport(TermBridgeKit)
import TermBridgeKit
#endif

private let logger = Logger(subsystem: "to.talkie.app.mac", category: "Settings")

// MARK: - Cached Theme Tokens

/// All theme-derived values calculated once per theme change
/// Eliminates per-access computation for fonts, colors, etc.
struct CachedThemeTokens {
    // MARK: - Font Tokens (UI Chrome)
    var fontXS: Font
    var fontXSMedium: Font
    var fontXSBold: Font
    var fontSM: Font
    var fontSMMedium: Font
    var fontSMBold: Font
    var fontBody: Font
    var fontBodyMedium: Font
    var fontBodyBold: Font
    var fontTitle: Font
    var fontTitleMedium: Font
    var fontTitleBold: Font
    var fontHeadline: Font
    var fontHeadlineMedium: Font
    var fontHeadlineBold: Font
    var fontPageTitle: Font        // 24pt - Main page headers (Home, Stats, etc.)
    var fontDisplay: Font
    var fontDisplayMedium: Font
    var fontStat: Font             // New York serif for stats numbers
    var fontStatLarge: Font        // New York large for hero stats

    // MARK: - Defaults
    static let `default` = CachedThemeTokens(
        fontXS: .system(size: 10),
        fontXSMedium: .system(size: 10, weight: .medium),
        fontXSBold: .system(size: 10, weight: .semibold),
        fontSM: .system(size: 11),
        fontSMMedium: .system(size: 11, weight: .medium),
        fontSMBold: .system(size: 11, weight: .semibold),
        fontBody: .system(size: 13),
        fontBodyMedium: .system(size: 13, weight: .medium),
        fontBodyBold: .system(size: 13, weight: .semibold),
        fontTitle: .system(size: 15),
        fontTitleMedium: .system(size: 15, weight: .medium),
        fontTitleBold: .system(size: 15, weight: .bold),
        fontHeadline: .system(size: 18),
        fontHeadlineMedium: .system(size: 18, weight: .medium),
        fontHeadlineBold: .system(size: 18, weight: .bold),
        fontPageTitle: .system(size: 24, weight: .medium),
        fontDisplay: .system(size: 32, weight: .light),
        fontDisplayMedium: .system(size: 32),
        fontStat: .system(size: 24, weight: .regular, design: .serif),
        fontStatLarge: .system(size: 32, weight: .regular, design: .serif)
    )
}

// MARK: - Appearance Mode
enum AppearanceMode: String, CaseIterable, CustomStringConvertible, Codable {
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
        get {
            _ = settingsConfigurationRevision
            return TalkieSettingsConfigurationStore.shared.configuration.sync.syncOnLaunch
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "syncOnLaunch")
            persistDeclarativeSettings { $0.sync.syncOnLaunch = newValue }
        }
    }

    /// Minimum interval between automatic syncs (seconds)
    var minimumSyncInterval: TimeInterval {
        get {
            _ = settingsConfigurationRevision
            return TalkieSettingsConfigurationStore.shared.configuration.sync.minimumSyncInterval
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "minimumSyncInterval")
            persistDeclarativeSettings { $0.sync.minimumSyncInterval = newValue }
        }
    }
}

// MARK: - Onboarding & First Run Settings
extension SettingsManager {
    private static let firstLaunchDateKey = "firstLaunchDate"
    private static let onboardingDismissedKey = "onboardingCardsDismissed"

    /// Date when the app was first launched (set automatically on first run)
    var firstLaunchDate: Date? {
        get {
            _ = settingsConfigurationRevision
            return TalkieSettingsConfigurationStore.shared.configuration.onboarding.firstLaunchDate
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.firstLaunchDateKey)
            persistDeclarativeSettings { $0.onboarding.firstLaunchDate = newValue }
        }
    }

    /// Record first launch if not already set
    func recordFirstLaunchIfNeeded() {
        if firstLaunchDate == nil {
            firstLaunchDate = Date()
        }
    }

    /// Number of days since first launch
    var daysSinceFirstLaunch: Int {
        guard let firstLaunch = firstLaunchDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: firstLaunch, to: Date()).day ?? 0
    }

    /// Whether user has dismissed the onboarding cards
    var onboardingCardsDismissed: Bool {
        get {
            _ = settingsConfigurationRevision
            return TalkieSettingsConfigurationStore.shared.configuration.onboarding.onboardingCardsDismissed
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.onboardingDismissedKey)
            persistDeclarativeSettings { $0.onboarding.onboardingCardsDismissed = newValue }
        }
    }

    /// Whether to show onboarding cards on Home screen
    /// Shows for first 3 days unless user dismisses them
    /// In sandbox mode, always shows onboarding (simulates fresh user)
    var shouldShowOnboardingCards: Bool {
        #if DEBUG
        if Self.isSandboxMode {
            return true  // Always show in sandbox mode
        }
        #endif
        return !onboardingCardsDismissed && daysSinceFirstLaunch < 3
    }
}

// MARK: - iCloud Sync Settings
extension SettingsManager {
    private static let iCloudSyncEnabledKey = "iCloudSyncEnabled"

    /// Whether iCloud sync is enabled (user opt-in)
    /// Defaults to false - user must explicitly enable via onboarding or settings
    var iCloudSyncEnabled: Bool {
        get {
            _ = settingsConfigurationRevision
            return TalkieSettingsConfigurationStore.shared.configuration.sync.iCloudSyncEnabled
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.iCloudSyncEnabledKey)
            persistDeclarativeSettings { $0.sync.iCloudSyncEnabled = newValue }
            // Notify ServiceManager to register/unregister TalkieSync
            NotificationCenter.default.post(name: .iCloudSyncSettingChanged, object: nil)
        }
    }
}

extension Notification.Name {
    static let iCloudSyncSettingChanged = Notification.Name("iCloudSyncSettingChanged")
    static let helperLifecycleModeChanged = Notification.Name("helperLifecycleModeChanged")
}

// MARK: - Helper Lifecycle Settings
extension SettingsManager {
    private static let agentLifecycleKey = "helperLifecycle.agent"
    private static let syncLifecycleKey = "helperLifecycle.sync"

    /// Lifecycle mode governing TalkieAgent. Default: .alwaysOn.
    var agentLifecycle: HelperLifecycleMode {
        get {
            _ = settingsConfigurationRevision
            let raw = TalkieSettingsConfigurationStore.shared.configuration.helpers.agentLifecycle
            return HelperLifecycleMode(rawValue: raw) ?? TalkieHelper.agent.defaultLifecycleMode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.agentLifecycleKey)
            persistDeclarativeSettings { $0.helpers.agentLifecycle = newValue.rawValue }
            NotificationCenter.default.post(
                name: .helperLifecycleModeChanged,
                object: nil,
                userInfo: ["helper": TalkieHelper.agent.rawValue, "mode": newValue.rawValue]
            )
        }
    }

    /// Lifecycle mode governing TalkieSync. Default: .attached.
    var syncLifecycle: HelperLifecycleMode {
        get {
            _ = settingsConfigurationRevision
            let raw = TalkieSettingsConfigurationStore.shared.configuration.helpers.syncLifecycle
            return HelperLifecycleMode(rawValue: raw) ?? TalkieHelper.sync.defaultLifecycleMode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.syncLifecycleKey)
            persistDeclarativeSettings { $0.helpers.syncLifecycle = newValue.rawValue }
            NotificationCenter.default.post(
                name: .helperLifecycleModeChanged,
                object: nil,
                userInfo: ["helper": TalkieHelper.sync.rawValue, "mode": newValue.rawValue]
            )
        }
    }

    /// Lookup the current lifecycle mode for a given helper.
    /// Helpers without a user-facing setting fall back to their default mode.
    func lifecycleMode(for helper: TalkieHelper) -> HelperLifecycleMode {
        switch helper {
        case .agent: return agentLifecycle
        case .sync: return syncLifecycle
        case .engine: return helper.defaultLifecycleMode
        }
    }
}

// MARK: - Remote Engine Settings
extension SettingsManager {
    /// Whether to use a remote TalkieAgent embedded engine instead of local XPC
    var remoteEngineEnabled: Bool {
        get {
            _ = settingsConfigurationRevision
            return TalkieSettingsConfigurationStore.shared.configuration.remoteEngine.enabled
        }
        set {
            TalkieSharedSettings.set(newValue, forKey: AgentSettingsKey.remoteEngineEnabled)
            persistDeclarativeSettings { $0.remoteEngine.enabled = newValue }
        }
    }

    /// Remote engine hostname (e.g. mac-mini.tail1234.ts.net)
    var remoteEngineHost: String {
        get {
            _ = settingsConfigurationRevision
            return TalkieSettingsConfigurationStore.shared.configuration.remoteEngine.host
        }
        set {
            TalkieSharedSettings.set(newValue, forKey: AgentSettingsKey.remoteEngineHost)
            persistDeclarativeSettings { $0.remoteEngine.host = newValue }
        }
    }

    /// Remote engine port (default: 19821)
    var remoteEnginePort: Int {
        get {
            _ = settingsConfigurationRevision
            return TalkieSettingsConfigurationStore.shared.configuration.remoteEngine.port
        }
        set {
            TalkieSharedSettings.set(newValue, forKey: AgentSettingsKey.remoteEnginePort)
            persistDeclarativeSettings { $0.remoteEngine.port = newValue }
        }
    }
}

// MARK: - Workflow Control Plane Settings
extension SettingsManager {
    /// Whether the built-in Talkie live workflow executor is enabled on this Mac.
    /// Backed by workflows/config.json so it can be managed without the settings UI.
    var workflowControlPlaneEnabled: Bool {
        get {
            _ = workflowControlPlaneConfigRevision
            return WorkflowConfigurationStore.shared.configuration.controlPlane.enabled
        }
        set {
            WorkflowConfigurationStore.shared.updateControlPlane { $0.enabled = newValue }
            workflowControlPlaneConfigRevision += 1
        }
    }

    /// Idle poll interval in seconds when the executor service is armed but not executing work.
    /// Backed by workflows/config.json and clamped to a low-cost minimum.
    var workflowControlPlaneIdlePollInterval: TimeInterval {
        get {
            _ = workflowControlPlaneConfigRevision
            return WorkflowConfigurationStore.shared.configuration.controlPlane.idlePollInterval
        }
        set {
            WorkflowConfigurationStore.shared.updateControlPlane {
                $0.idlePollInterval = max(60, newValue)
            }
            workflowControlPlaneConfigRevision += 1
        }
    }

    /// Stable executor device identifier for the local Mac.
    var workflowControlPlaneDeviceId: String {
        get {
            _ = workflowControlPlaneConfigRevision
            return WorkflowConfigurationStore.shared.configuration.controlPlane.deviceId
        }
        set {
            WorkflowConfigurationStore.shared.updateControlPlane { $0.deviceId = newValue }
            workflowControlPlaneConfigRevision += 1
        }
    }

    var workflowControlPlaneConfigPath: String {
        _ = workflowControlPlaneConfigRevision
        return WorkflowConfigurationStore.shared.displayPath
    }

    func reloadWorkflowControlPlaneConfiguration() {
        WorkflowConfigurationStore.shared.reloadFromDisk()
        workflowControlPlaneConfigRevision += 1
    }

    var hasWorkflowControlPlaneConfiguration: Bool {
        workflowControlPlaneEnabled
    }
}

// MARK: - Sandbox Mode (Debug)
#if DEBUG
extension SettingsManager {
    nonisolated private static let sandboxModeKey = "debugSandboxMode"

    /// Whether sandbox mode is enabled (uses empty database for testing onboarding)
    /// Requires app restart to take effect
    var sandboxMode: Bool {
        get { UserDefaults.standard.bool(forKey: Self.sandboxModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.sandboxModeKey) }
    }

    /// Check sandbox mode directly from UserDefaults (for use before SettingsManager init)
    nonisolated static var isSandboxMode: Bool {
        UserDefaults.standard.bool(forKey: sandboxModeKey)
    }
}
#endif

private extension Double {
    func orDefault(_ defaultValue: Double) -> Double {
        self == 0 ? defaultValue : self
    }
}

// MARK: - Accent Color Options
enum AccentColorOption: String, CaseIterable, Codable {
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
enum FontStyleOption: String, CaseIterable, Codable {
    case system = "system"
    case monospace = "monospace"
    case rounded = "rounded"
    case serif = "serif"
    case jetbrainsMono = "jetbrainsMono"
    case geistMono = "geistMono"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .monospace: return "Monospace"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .jetbrainsMono: return "JetBrains Mono"
        case .geistMono: return "Geist Mono"
        }
    }

    var icon: String {
        switch self {
        case .system: return "textformat"
        case .monospace: return "chevron.left.forwardslash.chevron.right"
        case .rounded: return "a.circle"
        case .serif: return "text.book.closed"
        case .jetbrainsMono: return "terminal"
        case .geistMono: return "chevron.left.forwardslash.chevron.right"
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
        case .jetbrainsMono:
            // JetBrains Mono - falls back to system monospace if not installed
            let fontName: String
            switch weight {
            case .ultraLight, .thin, .light:
                fontName = "JetBrainsMono-Light"
            case .regular:
                fontName = "JetBrainsMono-Regular"
            case .medium:
                fontName = "JetBrainsMono-Medium"
            case .semibold:
                fontName = "JetBrainsMono-SemiBold"
            case .bold, .heavy, .black:
                fontName = "JetBrainsMono-Bold"
            default:
                fontName = "JetBrainsMono-Regular"
            }
            if let _ = NSFont(name: fontName, size: size) {
                return .custom(fontName, size: size)
            }
            // Fallback to system monospace
            return .system(size: size, weight: weight, design: .monospaced)
        case .geistMono:
            // Geist Mono by Vercel - clean, technical aesthetic
            let fontName: String
            switch weight {
            case .ultraLight, .thin, .light, .regular:
                fontName = "GeistMono-Regular"
            case .medium, .semibold, .bold, .heavy, .black:
                fontName = "GeistMono-Medium"
            default:
                fontName = "GeistMono-Regular"
            }
            if let _ = NSFont(name: fontName, size: size) {
                return .custom(fontName, size: size)
            }
            // Fallback to system monospace
            return .system(size: size, weight: weight, design: .monospaced)
        }
    }
}

// MARK: - Font Size Options
/// Design system font sizes - canonical integer sizes, no fractional scaling
/// Each size tier defines proper integer point sizes for crisp rendering
enum FontSizeOption: String, CaseIterable, Codable {
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

// MARK: - Console Terminal Appearance
enum ConsoleTerminalThemeOption: String, CaseIterable, Codable {
    case graphite = "graphite"
    case tokyoNight = "tokyoNight"
    case nord = "nord"
    case catppuccin = "catppuccin"
    case solarizedLight = "solarizedLight"

    var displayName: String {
        switch self {
        case .graphite: return "Graphite"
        case .tokyoNight: return "Tokyo Night"
        case .nord: return "Nord"
        case .catppuccin: return "Catppuccin"
        case .solarizedLight: return "Solarized Light"
        }
    }

    var description: String {
        switch self {
        case .graphite: return "Quiet charcoal with soft contrast"
        case .tokyoNight: return "Crisp indigo dark with bright syntax"
        case .nord: return "Cool slate blues with restrained accents"
        case .catppuccin: return "Soft mocha palette with warm contrast"
        case .solarizedLight: return "Classic light theme with low glare"
        }
    }

    var previewColors: (bg: Color, fg: Color, accent: Color) {
        switch self {
        case .graphite:
            return (
                Color(red: 0.043, green: 0.067, blue: 0.090),
                Color(red: 0.902, green: 0.929, blue: 0.961),
                Color(red: 0.490, green: 0.769, blue: 1.000)
            )
        case .tokyoNight:
            return (
                Color(red: 0.15, green: 0.17, blue: 0.27),
                Color(red: 0.78, green: 0.84, blue: 0.96),
                Color(red: 0.49, green: 0.66, blue: 0.98)
            )
        case .nord:
            return (
                Color(red: 0.18, green: 0.20, blue: 0.25),
                Color(red: 0.85, green: 0.88, blue: 0.91),
                Color(red: 0.53, green: 0.75, blue: 0.82)
            )
        case .catppuccin:
            return (
                Color(red: 0.14, green: 0.14, blue: 0.21),
                Color(red: 0.80, green: 0.84, blue: 0.96),
                Color(red: 0.54, green: 0.67, blue: 0.94)
            )
        case .solarizedLight:
            return (
                Color(red: 0.99, green: 0.96, blue: 0.89),
                Color(red: 0.35, green: 0.43, blue: 0.46),
                Color(red: 0.15, green: 0.55, blue: 0.82)
            )
        }
    }

    var backgroundColor: Color { previewColors.bg }
    var foregroundColor: Color { previewColors.fg }

}

enum ConsoleTerminalFontOption: String, CaseIterable, Codable {
    case monaspaceNeon = "monaspaceNeon"
    case jetbrainsMono = "jetbrainsMono"
    case geistMono = "geistMono"
    case sfMono = "sfMono"
    case menlo = "menlo"

    var displayName: String {
        switch self {
        case .monaspaceNeon: return "Monaspace Neon"
        case .jetbrainsMono: return "JetBrains Mono"
        case .geistMono: return "Geist Mono"
        case .sfMono: return "SF Mono"
        case .menlo: return "Menlo"
        }
    }

    var description: String {
        switch self {
        case .monaspaceNeon: return "Textured and elegant"
        case .jetbrainsMono: return "Sharp and familiar"
        case .geistMono: return "Clean and compact"
        case .sfMono: return "Native macOS mono"
        case .menlo: return "Reliable system fallback"
        }
    }

    var isAvailable: Bool {
        NSFont(name: fontFamilyName, size: 13) != nil
    }

    static var availableOptions: [ConsoleTerminalFontOption] {
        let installed = allCases.filter { $0.isAvailable }
        return installed.isEmpty ? [.menlo] : installed
    }

    static var recommendedDefault: ConsoleTerminalFontOption {
        let preferredOrder: [ConsoleTerminalFontOption] = [
            .monaspaceNeon,
            .jetbrainsMono,
            .geistMono,
            .sfMono,
            .menlo
        ]

        return preferredOrder.first(where: \.isAvailable) ?? .menlo
    }

    private var fontFamilyName: String {
        switch self {
        case .monaspaceNeon: return "Monaspace Neon"
        case .jetbrainsMono: return "JetBrains Mono"
        case .geistMono: return "Geist Mono"
        case .sfMono: return "SF Mono"
        case .menlo: return "Menlo"
        }
    }

    private var effectiveFontFamilyName: String {
        if isAvailable {
            return fontFamilyName
        }

        return Self.recommendedDefault.fontFamilyName
    }

}

enum ConsoleTerminalFontSizeOption: String, CaseIterable, Codable {
    case compact = "compact"
    case regular = "regular"
    case comfortable = "comfortable"

    var displayName: String {
        switch self {
        case .compact: return "Compact"
        case .regular: return "Regular"
        case .comfortable: return "Comfortable"
        }
    }

    var description: String {
        switch self {
        case .compact: return "12 pt"
        case .regular: return "13 pt"
        case .comfortable: return "14 pt"
        }
    }

    var pointSize: Double {
        switch self {
        case .compact: return 12
        case .regular: return 13
        case .comfortable: return 14
        }
    }
}

// MARK: - Detail Level

/// Controls how much technical detail is shown across the UI.
/// From simple summaries to the most technical presentation.
enum DetailLevel: String, CaseIterable, Codable {
    case minimal = "minimal"     // Just the essentials - "Ready to go"
    case standard = "standard"   // Default - shows issues and key info
    case detailed = "detailed"   // More context - model names, hotkeys
    case max = "max"             // Highest detail level - technical presentation

    var displayName: String {
        switch self {
        case .minimal: return "Minimal"
        case .standard: return "Standard"
        case .detailed: return "Detailed"
        case .max: return "Technical"
        }
    }

    var description: String {
        switch self {
        case .minimal: return "Clean and simple"
        case .standard: return "Key info at a glance"
        case .detailed: return "More context and stats"
        case .max: return "Most context, diagnostics, and implementation detail"
        }
    }

    /// Whether to show developer-oriented UI elements
    var showDevInfo: Bool {
        self == .detailed || self == .max
    }

    /// Whether to use terminal/monospace style
    var useTerminalStyle: Bool {
        self == .max
    }
}

// MARK: - Settings Audience

/// Controls how much diagnostic surface area is exposed in Settings.
/// User-facing labels are Simple, Advanced, and Pro.
enum SettingsAudience: String, CaseIterable, Codable {
    case simple = "simple"
    case advanced = "advanced"
    // Raw value "developer" retained for UserDefaults compatibility.
    case pro = "developer"

    var displayName: String {
        switch self {
        case .simple: return "Simple"
        case .advanced: return "Advanced"
        case .pro: return "Pro"
        }
    }

    private var rank: Int {
        switch self {
        case .simple: return 0
        case .advanced: return 1
        case .pro: return 2
        }
    }

    func canAccess(_ required: SettingsAudience) -> Bool {
        rank >= required.rank
    }
}

// MARK: - Curated Theme Presets
enum ThemePreset: String, CaseIterable, Codable {
    case talkiePro = "talkiePro"    // Professional dark theme (default)
    case technical = "linear"        // Technical, Vercel-inspired (raw value kept for compat)
    case terminal = "terminal"      // Ghostty-style: clean, monospace, sharp
    case darkMatte = "darkMatte"    // Deterministic dark + warm hue-65 undertones
    case classic = "classic"        // Comfortable defaults with blue accents
    case warm = "warm"              // Cozy dark mode with orange tones
    case light = "light"            // Deterministic light mode, designed palette
    case liquidGlass = "liquidGlass" // Experimental glass effects
    case scope = "scope"            // Cream-phosphor oscilloscope (homepage parity)

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // Migrate retired rawValues so existing user settings don't wipe on load
        switch raw {
        case "minimal": self = .light
        default:
            guard let preset = ThemePreset(rawValue: raw) else {
                self = .talkiePro
                return
            }
            self = preset
        }
    }

    var displayName: String {
        switch self {
        case .talkiePro: return "Pro"
        case .technical: return "Technical"
        case .terminal: return "Terminal"
        case .darkMatte: return "Dark Matte"
        case .classic: return "Classic"
        case .warm: return "Warm"
        case .light: return "Light"
        case .liquidGlass: return "Liquid Glass"
        case .scope: return "Scope"
        }
    }

    var description: String {
        switch self {
        case .talkiePro: return "Professional dark theme with balanced contrast"
        case .technical: return "Technical, dense, V0-inspired"
        case .terminal: return "Clean monospace, sharp corners, no frills"
        case .darkMatte: return "Dark with warm matte undertones and amber accents"
        case .classic: return "Comfortable defaults with blue accents"
        case .warm: return "Cozy dark mode with orange tones"
        case .light: return "Clean light mode with neutral surfaces"
        case .liquidGlass: return "Experimental: maximum glass effects"
        case .scope: return "Cream-paper canvas with brass amber chrome — instrument panel"
        }
    }

    var icon: String {
        switch self {
        case .talkiePro: return "waveform"
        case .technical: return "square.stack.3d.up"
        case .terminal: return "terminal"
        case .darkMatte: return "moon.stars"
        case .classic: return "star"
        case .warm: return "flame"
        case .light: return "sun.max"
        case .liquidGlass: return "drop.fill"
        case .scope: return "waveform.path.ecg"
        }
    }

    @MainActor
    var previewColors: (bg: Color, fg: Color, accent: Color) {
        switch self {
        case .talkiePro:
            return (Color(white: 0.08), Color(white: 0.85), Color(red: 0.4, green: 0.7, blue: 1.0))
        case .technical:
            // Vercel/Linear style — adapts to appearance
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? (Color.black, Color.white, Color(red: 0.0, green: 0.83, blue: 1.0))
                : (Color.white, Color.black, Color(red: 0.0, green: 0.55, blue: 0.85))
        case .terminal:
            // Ghostty-style: black bg, light gray text, subtle gray accent
            return (Color.black, Color(white: 0.85), Color(white: 0.5))
        case .darkMatte:
            // Dark warm: oklch(0.14 0.008 65) bg, oklch(0.88 0.01 75) fg, oklch(0.72 0.12 70) amber
            return (
                Color(red: 0.0449, green: 0.0333, blue: 0.0242),
                Color(red: 0.8603, green: 0.8416, blue: 0.8171),
                Color(red: 0.8326, green: 0.5895, blue: 0.2837)
            )
        case .classic:
            return (Color(white: 0.15), Color(white: 0.9), Color.blue)
        case .warm:
            return (Color(red: 0.1, green: 0.08, blue: 0.06), Color(white: 0.9), Color.orange)
        case .light:
            // Clean light: oklch(0.98 0 0) bg, oklch(0.18 0.005 250) fg, oklch(0.7 0.16 60) accent
            return (
                Color(red: 0.9737, green: 0.9737, blue: 0.9737),
                Color(red: 0.0625, green: 0.0697, blue: 0.0774),
                Color(red: 0.8961, green: 0.5104, blue: 0.0706)
            )
        case .liquidGlass:
            return (Color(white: 0.05), Color.white, Color.cyan)
        case .scope:
            return (ScopeCanvas.canvas, ScopeInk.primary, ScopeAmber.solid)
        }
    }

    // Theme preset values — each preset is deterministic (no .system)
    var appearanceMode: AppearanceMode {
        switch self {
        case .talkiePro: return .dark
        case .technical: return .dark
        case .terminal: return .dark
        case .darkMatte: return .dark
        case .classic: return .dark
        case .warm: return .dark
        case .light: return .light
        case .liquidGlass: return .dark
        case .scope: return .light          // Cream-phosphor — forced light
        }
    }

    /// UI chrome font style (labels, headers, buttons, badges)
    var uiFontStyle: FontStyleOption {
        switch self {
        case .talkiePro: return .system
        case .technical: return .system            // Technical, but smoother than full mono
        case .terminal: return .jetbrainsMono   // JetBrains Mono throughout
        case .darkMatte: return .system
        case .classic: return .system
        case .warm: return .system
        case .light: return .system
        case .liquidGlass: return .system
        case .scope: return .monospace          // Instrument-panel labels — mono chrome
        }
    }

    /// Content font style (transcripts, notes, markdown)
    var contentFontStyle: FontStyleOption {
        switch self {
        case .talkiePro: return .system
        case .technical: return .system            // Keep readable/elegant in Technical theme
        case .terminal: return .jetbrainsMono   // JetBrains Mono throughout
        case .darkMatte: return .system
        case .classic: return .system
        case .warm: return .monospace           // Monospace content for warm theme
        case .light: return .system
        case .liquidGlass: return .system
        case .scope: return .system
        }
    }

    var accentColor: AccentColorOption {
        switch self {
        case .talkiePro: return .blue
        case .technical: return .blue
        case .terminal: return .gray        // No gimmicks, just gray
        case .darkMatte: return .orange     // Amber accent from designed palette
        case .classic: return .blue
        case .warm: return .orange
        case .light: return .orange         // Warm amber accent
        case .liquidGlass: return .blue
        case .scope: return .orange         // Closest stock match for amber/brass
        }
    }

    /// Font size option for this theme
    var fontSize: FontSizeOption {
        switch self {
        case .talkiePro: return .medium
        case .technical: return .small         // Dense, information-rich
        case .terminal: return .small       // Condensed, information-dense
        case .darkMatte: return .medium
        case .classic: return .medium
        case .warm: return .medium
        case .light: return .medium
        case .liquidGlass: return .medium
        case .scope: return .medium
        }
    }

    /// Whether this theme uses true black backgrounds
    var usesTrueBlack: Bool {
        switch self {
        case .technical, .terminal, .liquidGlass: return true
        default: return false
        }
    }

    /// Glass depth level for this theme
    var glassDepth: GlassDepth {
        switch self {
        case .talkiePro: return .standard
        case .classic: return .standard
        case .warm: return .standard
        case .darkMatte: return .subtle        // Matte: minimal glass, deliberate surfaces
        case .light: return .subtle            // Light: minimal glass for clarity
        case .technical: return .subtle        // Flat, technical aesthetic
        case .terminal: return .subtle      // Flat, minimal glass
        case .liquidGlass: return .extreme
        case .scope: return .subtle         // Flat — instrument aesthetic
        }
    }

    /// Corner radius style for this theme
    var cornerRadiusMultiplier: CGFloat {
        switch self {
        case .terminal: return 0            // Sharp corners - no rounding
        case .technical: return 0.5            // Tight corners - technical aesthetic
        case .scope: return 0.5             // Sharper instrument feel — md=6pt, sm=4pt, xs=2pt
        case .light: return 0.75            // Slightly reduced
        default: return 1.0                 // Standard
        }
    }

    /// Whether to use light font weights
    var usesLightFonts: Bool {
        switch self {
        case .terminal: return true         // Thin, clean lines
        case .technical: return false          // Crisper system rendering on true-black surfaces
        case .liquidGlass: return true      // Light, ethereal feel
        default: return false
        }
    }

    /// Border width for this theme
    var borderWidth: CGFloat {
        switch self {
        case .technical: return 0.33           // Ultra-thin hairline borders
        case .terminal: return 0.5          // Thin 1px borders
        default: return 1.0
        }
    }

    /// Whether this theme prefers lowercase UI labels
    var prefersLowercase: Bool {
        switch self {
        case .technical: return true           // Technical aesthetic: all lowercase
        default: return false
        }
    }

    /// Text case for UI labels based on theme preference
    var uiTextCase: Text.Case? {
        if prefersLowercase { return .lowercase }
        return nil
    }
}

@MainActor @Observable
final class SettingsManager {
    static let shared = SettingsManager()

    // MARK: - Batch Update Flag (prevents cascade Theme.refresh() calls)

    /// When true, skip Theme.refresh() in property didSets (call once at end of batch)
    @ObservationIgnored private var isBatchingUpdates = false

    // MARK: - Cached Theme Tokens (calculated once per theme change)

    /// All computed font/color values - recalculated only when theme changes
    @ObservationIgnored private(set) var cachedTokens: CachedThemeTokens = .default

    // MARK: - Overlay State (transient, not persisted)

    /// Whether the content search overlay is currently shown
    var isContentSearchPresented: Bool = false

    /// Whether the command palette overlay is currently shown
    var isCommandPalettePresented: Bool = false

    /// Whether the voice command overlay is currently shown
    var isVoiceCommandPresented: Bool = false

    /// Whether the keyboard shortcuts help sheet is presented
    var isKeyboardHelpPresented: Bool = false

    /// Non-modal corner panel listing key hints (⌘⇧? / ⌃⇧?)
    var showInlineKeyboardHints: Bool = false

    /// Revision counter so @Observable tracks the file-backed declarative settings.
    private(set) var settingsConfigurationRevision: Int = 0

    /// Revision counter so @Observable tracks the file-backed workflow control plane settings.
    private(set) var workflowControlPlaneConfigRevision: Int = 0

    // MARK: - Appearance Settings (UserDefaults - device-specific)

    private let appearanceModeKey = "appearanceMode"
    private let accentColorKey = "accentColor"
    private let uiFontStyleKey = "uiFontStyle"
    private let contentFontStyleKey = "contentFontStyle"
    private let fontSizeKey = "fontSize"  // Legacy, maps to uiFontSize
    private let uiFontSizeKey = "uiFontSize"
    private let contentFontSizeKey = "contentFontSize"
    private let consoleTerminalThemeKey = "consoleTerminalTheme"
    private let consoleTerminalFontKey = "consoleTerminalFont"
    private let consoleTerminalFontSizeKey = "consoleTerminalFontSize"
    private let currentThemeKey = "currentTheme"
    private let uiAllCapsKey = "uiAllCaps"
    private let enableGlassEffectsKey = "enableGlassEffects"
    private let detailLevelKey = "detailLevel"
    private let settingsAudienceKey = "settingsAudience"
    private let isProToolsActiveKey = "isDeveloperModeActive"
    private let hasCompletedProOnboardingKey = "hasCompletedDeveloperOnboarding"
    private let legacySettingsViewModeKey = "settingsViewMode"
    private let homeLayoutConfigKey = "homeLayoutConfig"
    private let composeLLMProviderIdKey = "composeLLMProviderId"
    private let composeLLMModelIdKey = "composeLLMModelId"
    private let composeAssistantPromptKey = "composeAssistantPrompt"

    nonisolated static let defaultComposeAssistantPrompt = """
        You are helping edit transcribed speech. Apply the user's instruction to transform the text.
        Return only the transformed text, nothing else. Preserve the original meaning unless asked otherwise.
        """

    var settingsConfigurationPath: String {
        _ = settingsConfigurationRevision
        return TalkieSettingsConfigurationStore.shared.displayPath
    }

    func reloadDeclarativeSettingsFromDisk() {
        TalkieSettingsConfigurationStore.shared.reloadFromDisk()
        applyDeclarativeSettingsConfiguration(TalkieSettingsConfigurationStore.shared.configuration)
        settingsConfigurationRevision += 1
    }

    private func persistDeclarativeSettings(_ update: (inout TalkieSettingsConfiguration) -> Void) {
        TalkieSettingsConfigurationStore.shared.update(update)
        settingsConfigurationRevision += 1
    }

    private func applyDeclarativeSettingsConfiguration(_ declarativeSettings: TalkieSettingsConfiguration) {
        isBatchingUpdates = true

        firstLaunchDate = declarativeSettings.onboarding.firstLaunchDate
        onboardingCardsDismissed = declarativeSettings.onboarding.onboardingCardsDismissed
        syncOnLaunch = declarativeSettings.sync.syncOnLaunch
        minimumSyncInterval = declarativeSettings.sync.minimumSyncInterval
        iCloudSyncEnabled = declarativeSettings.sync.iCloudSyncEnabled
        remoteEngineEnabled = declarativeSettings.remoteEngine.enabled
        remoteEngineHost = declarativeSettings.remoteEngine.host
        remoteEnginePort = declarativeSettings.remoteEngine.port

        appearanceMode = declarativeSettings.appearance.mode
        accentColor = declarativeSettings.appearance.accentColor
        enableGlassEffects = declarativeSettings.appearance.enableGlassEffects
        uiFontStyle = declarativeSettings.appearance.uiFontStyle
        contentFontStyle = declarativeSettings.appearance.contentFontStyle
        uiFontSize = declarativeSettings.appearance.uiFontSize
        contentFontSize = declarativeSettings.appearance.contentFontSize
        consoleTerminalTheme = declarativeSettings.appearance.consoleTerminalTheme
        consoleTerminalFont = declarativeSettings.appearance.consoleTerminalFont
        consoleTerminalFontSize = declarativeSettings.appearance.consoleTerminalFontSize
        uiAllCaps = declarativeSettings.appearance.uiAllCaps
        detailLevel = declarativeSettings.appearance.detailLevel
        settingsAudience = declarativeSettings.appearance.settingsAudience
        currentTheme = declarativeSettings.appearance.currentTheme

        var loadedLayout = declarativeSettings.home.layout
        loadedLayout.migrateForNewFeatures()
        homeLayoutConfig = loadedLayout
        composeLLMProviderId = declarativeSettings.compose.providerId
        composeLLMModelId = declarativeSettings.compose.modelId
        _composeAssistantPrompt = declarativeSettings.compose.assistantPrompt

        saveTranscriptsLocally = declarativeSettings.localFiles.saveTranscriptsLocally
        transcriptsFolderPath = declarativeSettings.localFiles.transcriptsFolderPath
        saveAudioLocally = declarativeSettings.localFiles.saveAudioLocally
        audioFolderPath = declarativeSettings.localFiles.audioFolderPath

        autoRunWorkflowsEnabled = declarativeSettings.workflow.autoRunEnabled
        extensionsFrameworkEnabled = declarativeSettings.bridge.extensionsFrameworkEnabled
        autoStartBridge = declarativeSettings.bridge.autoStartBridge
        talkieServerEnabled = declarativeSettings.bridge.talkieServerEnabled
        talkieGatewayEnabled = declarativeSettings.bridge.talkieGatewayEnabled
        talkieClaudeSessionsEnabled = declarativeSettings.bridge.talkieClaudeSessionsEnabled
        companionShortcutModeEnabled = declarativeSettings.bridge.shortcutBoardEnabled
        companionShortcutSlots = Self.normalizedCompanionShortcutSlots(declarativeSettings.resolvedShortcutSlots())
        askOnInterstitialDismiss = declarativeSettings.interstitial.askOnDismiss
        llmCostTier = declarativeSettings.models.llmCostTier
        syncIntervalMinutes = declarativeSettings.sync.syncIntervalMinutes
        jsonExportSchedule = declarativeSettings.audio.jsonExportSchedule
        playbackVolume = declarativeSettings.audio.playbackVolume
        selectedTTSVoiceId = declarativeSettings.audio.selectedTTSVoiceId
        selectedModel = declarativeSettings.models.selectedModel
        liveTranscriptionModelId = declarativeSettings.models.liveTranscriptionModelId
        captureHUDPosition = declarativeSettings.capture.hudPosition
        preferredScreenshotLauncher = declarativeSettings.capture.screenshotLauncher
        screenshotCapturePreset = declarativeSettings.capture.screenshotCapturePreset
        screenRecordingQualityPreset = declarativeSettings.capture.screenRecordingQuality
        cameraBubbleSize = declarativeSettings.camera.bubbleSize
        cameraQuality = declarativeSettings.camera.quality
        cameraVideoCodec = declarativeSettings.camera.videoCodec
        cameraDeviceID = declarativeSettings.camera.deviceID
        cameraMaxClipDuration = declarativeSettings.camera.maxClipDuration
        settingsSidebarIconsOnly = declarativeSettings.ui.settingsSidebarIconsOnly
        useCalendarWidget = declarativeSettings.developer.useCalendarWidget
        voiceCommandConfidenceThreshold = declarativeSettings.developer.voiceCommandConfidenceThreshold

        isBatchingUpdates = false
        Theme.refresh()
        applyThemeConfig()
    }

    /// The currently active theme preset
    var currentTheme: ThemePreset? {
        didSet {
            if let theme = currentTheme {
                UserDefaults.standard.set(theme.rawValue, forKey: currentThemeKey)
                persistDeclarativeSettings { $0.appearance.currentTheme = theme }
            } else {
                UserDefaults.standard.removeObject(forKey: currentThemeKey)
            }
            if !isBatchingUpdates {
                Theme.refresh()
                applyThemeConfig()
            }
        }
    }

    /// Whether to use light/thin font weights (for sharp aesthetics)
    var useLightFonts: Bool {
        currentTheme?.usesLightFonts ?? false
    }

    /// Whether current theme uses high-contrast colors
    var useTacticalColors: Bool {
        currentTheme == .talkiePro
    }

    /// Check if linear theme is active (Vercel/Linear-inspired)
    var isTechnicalTheme: Bool {
        currentTheme == .technical
    }

    /// Check if terminal theme is active
    var isTerminalTheme: Bool {
        currentTheme == .terminal
    }

    /// Check if dark-matte theme is active
    var isDarkMatteTheme: Bool {
        currentTheme == .darkMatte
    }

    /// Check if light theme is active
    var isLightTheme: Bool {
        currentTheme == .light
    }

    /// Check if classic theme is active
    var isClassicTheme: Bool {
        currentTheme == .classic
    }

    /// Check if warm theme is active
    var isWarmTheme: Bool {
        currentTheme == .warm
    }

    /// Check if scope (cream-phosphor) theme is active
    var isScopeTheme: Bool {
        currentTheme == .scope
    }

    /// Current glass depth based on theme
    var currentGlassDepth: GlassDepth {
        currentTheme?.glassDepth ?? .standard
    }

    /// Current corner radius multiplier based on theme
    var currentCornerRadiusMultiplier: CGFloat {
        currentTheme?.cornerRadiusMultiplier ?? 1.0
    }

    /// Current border width based on theme
    var currentBorderWidth: CGFloat {
        currentTheme?.borderWidth ?? 1.0
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
            TalkieSharedSettings.set(appearanceMode.rawValue, forKey: AgentSettingsKey.appearanceMode)
            persistDeclarativeSettings { $0.appearance.mode = appearanceMode }
            if !isBatchingUpdates { Theme.refresh() }
            applyAppearanceMode()
        }
    }

    var accentColor: AccentColorOption {
        didSet {
            UserDefaults.standard.set(accentColor.rawValue, forKey: accentColorKey)
            persistDeclarativeSettings { $0.appearance.accentColor = accentColor }
        }
    }

    /// Resolved accent color for UI elements (toggles, buttons, etc.)
    var resolvedAccentColor: Color {
        accentColor.color ?? .accentColor
    }

    /// Whether glass effects are enabled (requires restart to take effect)
    var enableGlassEffects: Bool {
        didSet {
            UserDefaults.standard.set(enableGlassEffects, forKey: enableGlassEffectsKey)
            persistDeclarativeSettings { $0.appearance.enableGlassEffects = enableGlassEffects }
        }
    }

    /// Check if glass setting differs from current runtime (needs restart)
    var glassEffectsNeedsRestart: Bool {
        enableGlassEffects != GlassConfig.enableGlassEffects
    }

    /// Font style for UI chrome: labels, headers, buttons, badges, navigation
    var uiFontStyle: FontStyleOption {
        didSet {
            UserDefaults.standard.set(uiFontStyle.rawValue, forKey: uiFontStyleKey)
            persistDeclarativeSettings { $0.appearance.uiFontStyle = uiFontStyle }
            if !isBatchingUpdates { Theme.refresh() }
        }
    }

    /// Font style for content: transcripts, notes, markdown, user-generated text
    var contentFontStyle: FontStyleOption {
        didSet {
            UserDefaults.standard.set(contentFontStyle.rawValue, forKey: contentFontStyleKey)
            persistDeclarativeSettings { $0.appearance.contentFontStyle = contentFontStyle }
            if !isBatchingUpdates { Theme.refresh() }
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
            persistDeclarativeSettings { $0.appearance.uiFontSize = uiFontSize }
            if !isBatchingUpdates { Theme.refresh() }
        }
    }

    /// Content font size (transcripts, notes, markdown)
    var contentFontSize: FontSizeOption {
        didSet {
            UserDefaults.standard.set(contentFontSize.rawValue, forKey: contentFontSizeKey)
            persistDeclarativeSettings { $0.appearance.contentFontSize = contentFontSize }
            if !isBatchingUpdates { Theme.refresh() }
        }
    }

    /// Global terminal theme for Talkie's embedded Ghostty surfaces.
    var consoleTerminalTheme: ConsoleTerminalThemeOption {
        didSet {
            UserDefaults.standard.set(consoleTerminalTheme.rawValue, forKey: consoleTerminalThemeKey)
            persistDeclarativeSettings { $0.appearance.consoleTerminalTheme = consoleTerminalTheme }
        }
    }

    /// Global terminal font family for Talkie's embedded Ghostty surfaces.
    var consoleTerminalFont: ConsoleTerminalFontOption {
        didSet {
            UserDefaults.standard.set(consoleTerminalFont.rawValue, forKey: consoleTerminalFontKey)
            persistDeclarativeSettings { $0.appearance.consoleTerminalFont = consoleTerminalFont }
        }
    }

    var effectiveConsoleTerminalFont: ConsoleTerminalFontOption {
        consoleTerminalFont.isAvailable ? consoleTerminalFont : ConsoleTerminalFontOption.recommendedDefault
    }

    /// Global terminal font size for Talkie's embedded Ghostty surfaces.
    var consoleTerminalFontSize: ConsoleTerminalFontSizeOption {
        didSet {
            UserDefaults.standard.set(consoleTerminalFontSize.rawValue, forKey: consoleTerminalFontSizeKey)
            persistDeclarativeSettings { $0.appearance.consoleTerminalFontSize = consoleTerminalFontSize }
        }
    }

    var consoleTerminalAppearance: ManagedAgentTerminalAppearance {
        .init(
            theme: consoleTerminalTheme,
            fontSize: consoleTerminalFontSize.pointSize
        )
    }

    /// Whether UI chrome labels should be ALL CAPS (tactical style)
    var uiAllCaps: Bool {
        didSet {
            UserDefaults.standard.set(uiAllCaps, forKey: uiAllCapsKey)
            persistDeclarativeSettings { $0.appearance.uiAllCaps = uiAllCaps }
        }
    }

    /// How much technical detail to show across the UI
    var detailLevel: DetailLevel {
        didSet {
            UserDefaults.standard.set(detailLevel.rawValue, forKey: detailLevelKey)
            persistDeclarativeSettings { $0.appearance.detailLevel = detailLevel }
        }
    }

    /// Settings visibility mode (simple/advanced/pro).
    var settingsAudience: SettingsAudience {
        didSet {
            UserDefaults.standard.set(settingsAudience.rawValue, forKey: settingsAudienceKey)
            persistDeclarativeSettings { $0.appearance.settingsAudience = settingsAudience }
            if settingsAudience != .pro && isProToolsActive {
                isProToolsActive = false
            }
        }
    }

    /// Whether Pro Tools has been activated via the onboarding flow.
    /// UserDefaults key retained as "isDeveloperModeActive" for data compatibility.
    var isProToolsActive: Bool {
        didSet {
            UserDefaults.standard.set(isProToolsActive, forKey: isProToolsActiveKey)
            if isProToolsActive {
                if settingsAudience != .pro {
                    settingsAudience = .pro
                }
                if detailLevel != .max {
                    detailLevel = .max
                }
            }
        }
    }

    /// Whether the user has ever completed the Pro Tools onboarding flow.
    /// Used to determine whether to show full onboarding or quick revalidation.
    var hasCompletedProOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedProOnboarding, forKey: hasCompletedProOnboardingKey)
        }
    }

    /// Whether advanced features (Compose, Context, Workflows) are unlocked.
    /// Combines manual override (settingsAudience) with usage-based gating (7+ transcriptions).
    var hasUnlockedAdvancedFeatures: Bool {
        // Manual override: user explicitly chose advanced/pro
        if settingsAudience != .simple { return true }
        // Usage-based: read onboarding state directly from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "onboardingProgressState"),
           let state = try? JSONDecoder().decode(OnboardingState.self, from: data) {
            let total = state.totalMemoCount + state.totalDictationCount
            return total >= 7
        }
        return false
    }

    /// Home screen layout configuration
    var homeLayoutConfig: HomeLayoutConfig {
        didSet {
            if let data = try? JSONEncoder().encode(homeLayoutConfig) {
                UserDefaults.standard.set(data, forKey: homeLayoutConfigKey)
            }
            persistDeclarativeSettings { $0.home.layout = homeLayoutConfig }
        }
    }

    /// Preferred LLM provider for Compose/Interstitial rewrite actions.
    var composeLLMProviderId: String? {
        didSet {
            if let value = composeLLMProviderId, !value.isEmpty {
                UserDefaults.standard.set(value, forKey: composeLLMProviderIdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: composeLLMProviderIdKey)
            }
            persistDeclarativeSettings { $0.compose.providerId = composeLLMProviderId }
        }
    }

    /// Preferred LLM model for Compose/Interstitial rewrite actions.
    var composeLLMModelId: String? {
        didSet {
            if let value = composeLLMModelId, !value.isEmpty {
                UserDefaults.standard.set(value, forKey: composeLLMModelIdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: composeLLMModelIdKey)
            }
            persistDeclarativeSettings { $0.compose.modelId = composeLLMModelId }
        }
    }

    /// Personality/system prompt used by Compose/Interstitial rewrite actions.
    var composeAssistantPrompt: String {
        get {
            let raw = _composeAssistantPrompt
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? SettingsManager.defaultComposeAssistantPrompt : raw
        }
        set {
            _composeAssistantPrompt = newValue
            UserDefaults.standard.set(newValue, forKey: composeAssistantPromptKey)
            persistDeclarativeSettings { $0.compose.assistantPrompt = newValue }
        }
    }
    private var _composeAssistantPrompt: String = SettingsManager.defaultComposeAssistantPrompt

    /// Text case for UI labels - respects theme preference or user override
    var uiTextCase: Text.Case? {
        // User override takes precedence
        if uiAllCaps { return .uppercase }
        // Theme preference (e.g., Technical theme uses lowercase)
        return currentTheme?.uiTextCase
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

    // MARK: - UI Font Tokens (Cached - calculated once per theme change)
    // For UI chrome: labels, headers, buttons, badges, navigation
    // Uses uiFontStyle (themed/branded)

    /// Extra small UI text - labels, badges (10pt base)
    var fontXS: Font { cachedTokens.fontXS }
    var fontXSMedium: Font { cachedTokens.fontXSMedium }
    var fontXSBold: Font { cachedTokens.fontXSBold }

    /// Small UI text - secondary info, metadata (11pt base)
    var fontSM: Font { cachedTokens.fontSM }
    var fontSMMedium: Font { cachedTokens.fontSMMedium }
    var fontSMBold: Font { cachedTokens.fontSMBold }

    /// Body UI text - primary UI elements (13pt base)
    var fontBody: Font { cachedTokens.fontBody }
    var fontBodyMedium: Font { cachedTokens.fontBodyMedium }
    var fontBodyBold: Font { cachedTokens.fontBodyBold }

    /// Title UI text - section headers (15pt base)
    var fontTitle: Font { cachedTokens.fontTitle }
    var fontTitleMedium: Font { cachedTokens.fontTitleMedium }
    var fontTitleBold: Font { cachedTokens.fontTitleBold }

    /// Headline UI text - large headers (18pt base)
    var fontHeadline: Font { cachedTokens.fontHeadline }
    var fontHeadlineMedium: Font { cachedTokens.fontHeadlineMedium }
    var fontHeadlineBold: Font { cachedTokens.fontHeadlineBold }

    /// Page title - main page headers (24pt base, light for glass themes)
    var fontPageTitle: Font { cachedTokens.fontPageTitle }

    /// Display UI text - hero elements (32pt base)
    var fontDisplay: Font { cachedTokens.fontDisplay }
    var fontDisplayMedium: Font { cachedTokens.fontDisplayMedium }

    /// Stats - New York serif for numbers
    var fontStat: Font { cachedTokens.fontStat }
    var fontStatLarge: Font { cachedTokens.fontStatLarge }

    // MARK: - Theme Color Tokens
    // Returns themed colors based on active theme, falls back to system colors

    /// Primary background
    var tacticalBackground: Color {
        if isScopeTheme { return ScopeCanvas.canvas }
        if useTacticalColors {
            return isDarkMode ? Color(white: 0.05) : Color(white: 0.96)
        }
        if isTechnicalTheme {
            return isDarkMode ? Color.black : Color.white
        }
        if isDarkMatteTheme {
            return Color(red: 0.0449, green: 0.0333, blue: 0.0242)
        }
        if isLightTheme {
            return Color(red: 0.9737, green: 0.9737, blue: 0.9737)
        }
        if isTerminalTheme {
            // Terminal: True black - Ghostty style
            return Color.black
        }
        return Color(NSColor.windowBackgroundColor)
    }

    /// Secondary background (slightly lighter/darker)
    var tacticalBackgroundSecondary: Color {
        if isScopeTheme { return ScopeCanvas.canvasAlt }
        if useTacticalColors {
            return isDarkMode ? Color(white: 0.08) : Color(white: 0.88)
        }
        if isTechnicalTheme {
            return isDarkMode ? Color(white: 0.04) : Color(white: 0.98)
        }
        if isDarkMatteTheme {
            return Color(red: 0.0702, green: 0.0578, blue: 0.0463)
        }
        if isLightTheme {
            return Color(red: 1.0, green: 1.0, blue: 1.0)
        }
        if isTerminalTheme {
            // Terminal: Very subtle elevation
            return Color(white: 0.04)
        }
        return Color(NSColor.controlBackgroundColor)
    }

    /// Tertiary background for cards/panels
    var tacticalBackgroundTertiary: Color {
        if isScopeTheme { return ScopeCanvas.surface }
        if useTacticalColors {
            return isDarkMode ? Color(white: 0.12) : Color(white: 0.90)
        }
        if isTechnicalTheme {
            return isDarkMode ? Color(white: 0.067) : Color(white: 0.96)
        }
        if isDarkMatteTheme {
            return Color(red: 0.0966, green: 0.0837, blue: 0.0717)
        }
        if isLightTheme {
            return Color(red: 0.9803, green: 0.9803, blue: 0.9803)
        }
        if isTerminalTheme {
            // Terminal: Subtle card surface
            return Color(white: 0.08)
        }
        return isDarkMode ? Color(white: 0.13) : Color(white: 0.94)
    }

    /// Primary text
    var tacticalForeground: Color {
        if isScopeTheme { return ScopeInk.primary }
        if useTacticalColors {
            return isDarkMode ? Color(white: 0.98) : Color(white: 0.08)
        }
        if isTechnicalTheme {
            return isDarkMode ? Color.white : Color(white: 0.06)
        }
        if isDarkMatteTheme {
            return Color(red: 0.8603, green: 0.8416, blue: 0.8171)
        }
        if isLightTheme {
            return Color(red: 0.0625, green: 0.0697, blue: 0.0774)
        }
        if isTerminalTheme {
            // Terminal: Light gray - clean, no gimmicks (Ghostty style)
            return Color(white: 0.85)
        }
        return Color.primary
    }

    /// Secondary text
    var tacticalForegroundSecondary: Color {
        if isScopeTheme { return ScopeInk.muted }
        if useTacticalColors {
            return isDarkMode ? Color(white: 0.78) : Color(white: 0.28)
        }
        if isTechnicalTheme {
            return isDarkMode ? Color(white: 0.65) : Color(white: 0.35)
        }
        if isDarkMatteTheme {
            // Midpoint between foreground and muted foreground
            return Color(red: 0.6694, green: 0.6462, blue: 0.6234)
        }
        if isLightTheme {
            return Color(red: 0.2176, green: 0.2305, blue: 0.2443)
        }
        if isTerminalTheme {
            // Terminal: Secondary gray - readable but subdued
            return Color(white: 0.68)
        }
        return Color.secondary
    }

    /// Muted text for timestamps, metadata
    var tacticalForegroundMuted: Color {
        if isScopeTheme { return ScopeInk.faint }
        if useTacticalColors {
            return isDarkMode ? Color(white: 0.58) : Color(white: 0.45)
        }
        if isTechnicalTheme {
            return isDarkMode ? Color(white: 0.50) : Color(white: 0.50)
        }
        if isDarkMatteTheme {
            return Color(red: 0.4784, green: 0.4507, blue: 0.4296)
        }
        if isLightTheme {
            return Color(red: 0.3727, green: 0.3912, blue: 0.4112)
        }
        if isTerminalTheme {
            // Terminal: Subtle gray - still readable
            return Color(white: 0.52)
        }
        return isDarkMode ? Color(white: 0.50) : Color(white: 0.55)
    }

    /// Divider/border color
    var tacticalDivider: Color {
        if isScopeTheme { return ScopeEdge.faint }
        if useTacticalColors {
            return isDarkMode ? Color(white: 0.2) : Color(white: 0.65)
        }
        if isTechnicalTheme {
            return isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
        }
        if isDarkMatteTheme {
            return Color(red: 0.1522, green: 0.1383, blue: 0.1256)
        }
        if isLightTheme {
            return Color(red: 0.8901, green: 0.8966, blue: 0.9035)
        }
        if isTerminalTheme {
            // Terminal: Thin gray border - minimal separation
            return Color.white.opacity(0.12)
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
        if isScopeTheme { return ScopeCanvas.canvas }
        if isTechnicalTheme {
            return isDarkMode ? Color.black : Color.white
        }
        if isDarkMatteTheme {
            return Color(red: 0.0449, green: 0.0333, blue: 0.0242)
        }
        if isLightTheme {
            return Color(red: 0.9737, green: 0.9737, blue: 0.9737)
        }
        return isDarkMode ? Color(white: 0.05) : Color(white: 0.98)
    }

    /// Surface Level 1: Primary content areas (slightly elevated)
    var surface1: Color {
        if isScopeTheme { return ScopeCanvas.canvasAlt }
        if isTechnicalTheme {
            return isDarkMode ? Color(white: 0.04) : Color(white: 0.98)
        }
        if isDarkMatteTheme {
            return Color(red: 0.0702, green: 0.0578, blue: 0.0463)
        }
        if isLightTheme {
            return Color(red: 1.0, green: 1.0, blue: 1.0)
        }
        return isDarkMode ? Color(white: 0.08) : Color(white: 0.95)
    }

    /// Surface Level 2: Cards, panels, modals (more elevated)
    var surface2: Color {
        if isScopeTheme { return ScopeCanvas.surface }
        if isTechnicalTheme {
            return isDarkMode ? Color(white: 0.067) : Color(white: 0.96)
        }
        if isDarkMatteTheme {
            return Color(red: 0.0966, green: 0.0837, blue: 0.0717)
        }
        if isLightTheme {
            return Color(red: 0.9803, green: 0.9803, blue: 0.9803)
        }
        return isDarkMode ? Color(white: 0.12) : Color(white: 0.92)
    }

    /// Surface Level 3: Elevated elements (popovers, tooltips, menus)
    var surface3: Color {
        if isScopeTheme { return ScopeCanvas.surface }
        if isTechnicalTheme {
            return isDarkMode ? Color(white: 0.10) : Color(white: 0.94)
        }
        if isDarkMatteTheme {
            return Color(red: 0.1333, green: 0.1197, blue: 0.1072)
        }
        if isLightTheme {
            return Color(red: 0.9355, green: 0.942, blue: 0.949)
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

    /// Modal backdrop color - darkens content behind modals/overlays
    /// Use with .opacity(0.4-0.7) depending on desired dimming
    var modalBackdrop: Color {
        // Both modes use black for dimming, but light mode needs slightly more opacity
        // to achieve the same visual effect against light backgrounds
        Color.black
    }

    /// Standard modal backdrop with appropriate opacity for current mode
    var modalBackdropStandard: Color {
        isDarkMode ? Color.black.opacity(0.4) : Color.black.opacity(0.5)
    }

    /// Heavy modal backdrop for drop zones, loading states
    var modalBackdropHeavy: Color {
        isDarkMode ? Color.black.opacity(0.7) : Color.black.opacity(0.75)
    }

    /// Text/Input background (slightly elevated from base)
    var surfaceInput: Color {
        if isScopeTheme { return ScopeCanvas.surface }
        if isTechnicalTheme {
            return isDarkMode ? Color(white: 0.05) : Color(white: 0.97)
        }
        if isDarkMatteTheme {
            return Color(red: 0.0702, green: 0.0578, blue: 0.0463)
        }
        if isLightTheme {
            return Color(red: 1.0, green: 1.0, blue: 1.0)
        }
        return isDarkMode ? Color(white: 0.08) : Color(white: 0.95)
    }

    // MARK: - Interactive Surface States (Appearance-Aware Solid Colors)
    // These are used as overlays on known backgrounds, so we pre-compute the blend result

    /// Hover state overlay - dark: 0.05+0.05=0.10, light: 0.95-0.05=0.90
    var surfaceHover: Color {
        if isScopeTheme { return ScopeCanvas.canvasAlt }
        if isTechnicalTheme {
            return isDarkMode ? Color(white: 0.08) : Color(white: 0.95)
        }
        if isDarkMatteTheme {
            return Color(red: 0.0966, green: 0.0837, blue: 0.0717)
        }
        if isLightTheme {
            return Color(red: 0.9485, green: 0.955, blue: 0.9621)
        }
        return isDarkMode ? Color(white: 0.10) : Color(white: 0.90)
    }

    /// Active/pressed state overlay
    var surfaceActive: Color {
        if isScopeTheme { return ScopeCanvas.surface }
        if isTechnicalTheme {
            return isDarkMode ? Color(white: 0.10) : Color(white: 0.92)
        }
        if isDarkMatteTheme {
            return Color(red: 0.1148, green: 0.1015, blue: 0.0893)
        }
        if isLightTheme {
            return Color(red: 0.9355, green: 0.942, blue: 0.949)
        }
        return isDarkMode ? Color(white: 0.13) : Color(white: 0.87)
    }

    /// Selected state overlay
    var surfaceSelected: Color {
        if isScopeTheme { return ScopeAmber.tint }
        if isTechnicalTheme {
            return isDarkMode ? Color(white: 0.12) : Color(white: 0.90)
        }
        if isDarkMatteTheme {
            return Color(red: 0.1333, green: 0.1197, blue: 0.1072)
        }
        if isLightTheme {
            return Color(red: 0.8993, green: 0.9101, blue: 0.9218)
        }
        return isDarkMode ? Color(white: 0.15) : Color(white: 0.85)
    }

    /// Alternating row background (for lists)
    var surfaceAlternate: Color {
        if isScopeTheme { return ScopeCanvas.canvasAlt }
        if isTechnicalTheme {
            return isDarkMode ? Color(white: 0.03) : Color(white: 0.98)
        }
        if isDarkMatteTheme {
            return Color(red: 0.0578, green: 0.0455, blue: 0.0351)
        }
        if isLightTheme {
            return Color(red: 0.9620, green: 0.9620, blue: 0.9620)
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
        if isScopeTheme { return ScopeEdge.normal }
        return isDarkMode ? Color(white: 0.13) : Color(white: 0.87)
    }

    /// Strong border (more visible) - dark: ~0.20 (15% of white on 0.05), light: ~0.80
    var borderStrong: Color {
        if isScopeTheme { return ScopeEdge.strong }
        return isDarkMode ? Color(white: 0.20) : Color(white: 0.80)
    }

    /// Divider for separating content - dark: ~0.11 (6% of white on 0.05), light: ~0.89
    var divider: Color {
        if isScopeTheme { return ScopeEdge.faint }
        return isDarkMode ? Color(white: 0.11) : Color(white: 0.89)
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
            Theme.refresh()  // Single refresh at the end
        }

        currentTheme = theme
        appearanceMode = theme.appearanceMode
        uiFontStyle = theme.uiFontStyle
        contentFontStyle = theme.contentFontStyle
        accentColor = theme.accentColor
        fontSize = theme.fontSize

        // Configure TalkieKit's ThemeConfig for design system tokens
        applyThemeConfig(theme)
    }

    /// Apply theme configuration to TalkieKit's global ThemeConfig
    /// This updates corner radii, fonts, and other design tokens
    func applyThemeConfig(_ theme: ThemePreset? = nil) {
        let activeTheme = theme ?? currentTheme
        if let activeTheme = activeTheme {
            ThemeConfig.configure(
                cornerRadiusMultiplier: activeTheme.cornerRadiusMultiplier,
                useLightFonts: activeTheme.usesLightFonts,
                borderWidth: activeTheme.borderWidth,
                customFontName: activeTheme.uiFontStyle == .jetbrainsMono ? "JetBrainsMono" : nil
            )
        } else {
            ThemeConfig.reset()
        }

        // Flat themes (Scope) skip glass material rendering entirely —
        // the aesthetic is fundamentally flat and the materials cost
        // frames in light mode without any visual win. Runtime-only;
        // doesn't persist or override user preference for other themes.
        GlassConfig.themeFlatOverride = (activeTheme == .scope)

        // Recalculate all cached font tokens
        recalculateCachedTokens()
    }

    /// Recalculate all cached theme tokens (called once per theme change)
    private func recalculateCachedTokens() {
        let lightFonts = useLightFonts
        let scale = uiFontSize.scale
        let style = uiFontStyle

        let regularWeight: Font.Weight = lightFonts ? .light : .regular
        let mediumWeight: Font.Weight = lightFonts ? .regular : .medium
        let boldWeight: Font.Weight = lightFonts ? .medium : .semibold
        let displayWeight: Font.Weight = lightFonts ? .light : .regular

        // Helper to create themed font
        func font(_ baseSize: CGFloat, _ weight: Font.Weight) -> Font {
            style.font(size: baseSize * scale, weight: weight)
        }

        // Use lighter cuts only for explicitly light-weight themes.
        cachedTokens = CachedThemeTokens(
            fontXS: font(10, regularWeight),
            fontXSMedium: font(10, mediumWeight),
            fontXSBold: font(10, boldWeight),
            fontSM: font(11, regularWeight),
            fontSMMedium: font(11, mediumWeight),
            fontSMBold: font(11, boldWeight),
            fontBody: font(13, regularWeight),
            fontBodyMedium: font(13, mediumWeight),
            fontBodyBold: font(13, boldWeight),
            fontTitle: font(15, regularWeight),
            fontTitleMedium: font(15, mediumWeight),
            fontTitleBold: font(15, boldWeight),
            fontHeadline: font(18, regularWeight),
            fontHeadlineMedium: font(18, mediumWeight),
            fontHeadlineBold: font(18, boldWeight),
            fontPageTitle: font(24, regularWeight),
            fontDisplay: font(32, displayWeight),
            fontDisplayMedium: font(32, mediumWeight),
            fontStat: .system(size: 24 * scale, weight: .regular, design: .serif),      // New York
            fontStatLarge: .system(size: 32 * scale, weight: lightFonts ? .light : .regular, design: .serif)    // New York large
        )
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

    // MARK: - Capture HUD Position (UserDefaults - device-specific)

    private let captureHUDPositionKey = "captureHUDPosition"
    private let screenshotCapturePresetKey = "screenshotCapturePreset"
    private let screenRecordingQualityKey = "screenRecordingQuality"

    var captureHUDPosition: CaptureHUDPosition {
        get {
            _ = settingsConfigurationRevision
            guard let raw = UserDefaults.standard.string(forKey: captureHUDPositionKey),
                  let position = CaptureHUDPosition(rawValue: raw) else {
                return TalkieSettingsConfigurationStore.shared.configuration.capture.hudPosition
            }
            return position
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: captureHUDPositionKey)
            persistDeclarativeSettings { $0.capture.hudPosition = newValue }
            captureHUDPositionRevision += 1
        }
    }

    /// Revision counter so @Observable tracks the UserDefaults-backed property above.
    private(set) var captureHUDPositionRevision: Int = 0

    var screenshotCapturePreset: ScreenshotCapturePreset {
        get {
            _ = settingsConfigurationRevision
            guard let raw = UserDefaults.standard.string(forKey: screenshotCapturePresetKey),
                  let preset = ScreenshotCapturePreset(rawValue: raw) else {
                return TalkieSettingsConfigurationStore.shared.configuration.capture.screenshotCapturePreset
            }
            return preset
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: screenshotCapturePresetKey)
            persistDeclarativeSettings { $0.capture.screenshotCapturePreset = newValue }
            captureHUDPositionRevision += 1
        }
    }

    var screenRecordingQualityPreset: ScreenRecordingQualityPreset {
        get {
            _ = settingsConfigurationRevision
            guard let raw = UserDefaults.standard.string(forKey: screenRecordingQualityKey),
                  let preset = ScreenRecordingQualityPreset(rawValue: raw) else {
                return TalkieSettingsConfigurationStore.shared.configuration.capture.screenRecordingQuality
            }
            return preset
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: screenRecordingQualityKey)
            persistDeclarativeSettings { $0.capture.screenRecordingQuality = newValue }
            captureHUDPositionRevision += 1
        }
    }

    // MARK: - Preferred Screenshot Launcher (UserDefaults - device-specific)

    private let screenshotLauncherKey = "preferredScreenshotLauncher"

    var preferredScreenshotLauncher: ScreenshotLauncher {
        get {
            _ = settingsConfigurationRevision
            guard let raw = UserDefaults.standard.string(forKey: screenshotLauncherKey),
                  let launcher = ScreenshotLauncher(rawValue: raw) else {
                return TalkieSettingsConfigurationStore.shared.configuration.capture.screenshotLauncher
            }
            return launcher
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: screenshotLauncherKey)
            persistDeclarativeSettings { $0.capture.screenshotLauncher = newValue }
            screenshotLauncherRevision += 1
        }
    }

    private(set) var screenshotLauncherRevision: Int = 0

    // MARK: - Camera Capture Settings (file-backed, mirrored to UserDefaults)

    private let cameraBubbleSizeKey = "cameraBubbleSize"
    private let cameraQualityKey = "cameraQuality"
    private let cameraVideoCodecKey = "cameraVideoCodec"
    private let cameraDeviceIDKey = "cameraDeviceID"
    private let cameraMaxClipDurationKey = "cameraMaxClipDuration"

    var cameraBubbleSize: CameraBubbleSize {
        get {
            _ = settingsConfigurationRevision
            guard let raw = UserDefaults.standard.string(forKey: cameraBubbleSizeKey),
                  let bubbleSize = CameraBubbleSize(rawValue: raw) else {
                return TalkieSettingsConfigurationStore.shared.configuration.camera.bubbleSize
            }
            return bubbleSize
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: cameraBubbleSizeKey)
            persistDeclarativeSettings { $0.camera.bubbleSize = newValue }
            cameraSettingsRevision += 1
        }
    }

    var cameraQuality: CameraQuality {
        get {
            _ = settingsConfigurationRevision
            guard let raw = UserDefaults.standard.string(forKey: cameraQualityKey),
                  let quality = CameraQuality(rawValue: raw) else {
                return TalkieSettingsConfigurationStore.shared.configuration.camera.quality
            }
            return quality
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: cameraQualityKey)
            persistDeclarativeSettings { $0.camera.quality = newValue }
            cameraSettingsRevision += 1
        }
    }

    var cameraVideoCodec: CameraVideoCodec {
        get {
            _ = settingsConfigurationRevision
            guard let raw = UserDefaults.standard.string(forKey: cameraVideoCodecKey),
                  let codec = CameraVideoCodec(rawValue: raw) else {
                return TalkieSettingsConfigurationStore.shared.configuration.camera.videoCodec
            }
            return codec
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: cameraVideoCodecKey)
            persistDeclarativeSettings { $0.camera.videoCodec = newValue }
            cameraSettingsRevision += 1
        }
    }

    var cameraDeviceID: String {
        get {
            _ = settingsConfigurationRevision
            if let deviceID = UserDefaults.standard.string(forKey: cameraDeviceIDKey) {
                return deviceID
            }
            return TalkieSettingsConfigurationStore.shared.configuration.camera.deviceID
        }
        set {
            UserDefaults.standard.set(newValue, forKey: cameraDeviceIDKey)
            persistDeclarativeSettings { $0.camera.deviceID = newValue }
            cameraSettingsRevision += 1
        }
    }

    var cameraMaxClipDuration: Double {
        get {
            _ = settingsConfigurationRevision
            let savedDuration = UserDefaults.standard.double(forKey: cameraMaxClipDurationKey)
            if savedDuration > 0 {
                return savedDuration
            }
            return TalkieSettingsConfigurationStore.shared.configuration.camera.maxClipDuration
        }
        set {
            let clampedDuration = min(120, max(15, newValue))
            UserDefaults.standard.set(clampedDuration, forKey: cameraMaxClipDurationKey)
            persistDeclarativeSettings { $0.camera.maxClipDuration = clampedDuration }
            cameraSettingsRevision += 1
        }
    }

    private(set) var cameraSettingsRevision: Int = 0

    // MARK: - Settings UI Layout

    private let settingsSidebarIconsOnlyKey = "settings.sidebar.iconsOnly"

    var settingsSidebarIconsOnly: Bool {
        get {
            _ = settingsConfigurationRevision
            if UserDefaults.standard.object(forKey: settingsSidebarIconsOnlyKey) != nil {
                return UserDefaults.standard.bool(forKey: settingsSidebarIconsOnlyKey)
            }
            return TalkieSettingsConfigurationStore.shared.configuration.ui.settingsSidebarIconsOnly
        }
        set {
            UserDefaults.standard.set(newValue, forKey: settingsSidebarIconsOnlyKey)
            persistDeclarativeSettings { $0.ui.settingsSidebarIconsOnly = newValue }
            settingsSidebarRevision += 1
        }
    }

    private(set) var settingsSidebarRevision: Int = 0

    // MARK: - Local File Storage Settings (UserDefaults - device-specific)
    // Where transcript and audio files live on disk - your data, your files
    // These are independent opt-in features for users who want local file ownership

    private let saveTranscriptsLocallyKey = "saveTranscriptsLocally"
    private let transcriptsFolderPathKey = "transcriptsFolderPath"
    private let saveAudioLocallyKey = "saveAudioLocally"
    private let audioFolderPathKey = "audioFolderPath"

    /// Default transcripts folder: ~/Documents/Talkie/Transcripts
    nonisolated static var defaultTranscriptsFolderPath: String {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return NSTemporaryDirectory() + "Talkie/Transcripts"
        }
        return documentsPath.appendingPathComponent("Talkie/Transcripts").path
    }

    /// Default audio folder: ~/Documents/Talkie/Audio
    nonisolated static var defaultAudioFolderPath: String {
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
            persistDeclarativeSettings { $0.localFiles.saveTranscriptsLocally = value }
        }
    }

    /// Where transcript files are saved
    var transcriptsFolderPath: String {
        didSet {
            let path = transcriptsFolderPath
            DispatchQueue.main.async {
                UserDefaults.standard.set(path, forKey: self.transcriptsFolderPathKey)
            }
            persistDeclarativeSettings { $0.localFiles.transcriptsFolderPath = path }
        }
    }

    /// Whether to save M4A audio files locally (default: false)
    var saveAudioLocally: Bool {
        didSet {
            let value = saveAudioLocally
            DispatchQueue.main.async {
                UserDefaults.standard.set(value, forKey: self.saveAudioLocallyKey)
            }
            persistDeclarativeSettings { $0.localFiles.saveAudioLocally = value }
        }
    }

    /// Where audio files are saved
    var audioFolderPath: String {
        didSet {
            let path = audioFolderPath
            DispatchQueue.main.async {
                UserDefaults.standard.set(path, forKey: self.audioFolderPathKey)
            }
            persistDeclarativeSettings { $0.localFiles.audioFolderPath = path }
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
            persistDeclarativeSettings { $0.workflow.autoRunEnabled = value }
        }
    }

    // MARK: - Extensions Framework Settings (UserDefaults - device-specific)
    // Global kill switch for all extension framework runtime work (JS apps + extension events)

    private let extensionsFrameworkEnabledKey = "extensionsFrameworkEnabled"

    /// Whether the extensions framework is enabled (default: false for fast startup)
    var extensionsFrameworkEnabled: Bool {
        didSet {
            let value = extensionsFrameworkEnabled
            DispatchQueue.main.async {
                UserDefaults.standard.set(value, forKey: self.extensionsFrameworkEnabledKey)
            }
            persistDeclarativeSettings { $0.bridge.extensionsFrameworkEnabled = value }
            NotificationCenter.default.post(
                name: .extensionsFrameworkSettingDidChange,
                object: nil,
                userInfo: ["enabled": value]
            )
        }
    }

    // MARK: - Bridge/Gateway Settings (UserDefaults - device-specific)
    // Controls whether the iOS bridge auto-starts on launch

    private let autoStartBridgeKey = "autoStartBridge"
    private let talkieServerEnabledKey = "talkieServerEnabled"
    private let talkieGatewayEnabledKey = "talkieGatewayEnabled"
    private let talkieClaudeSessionsEnabledKey = "talkieClaudeSessionsEnabled"
    private let companionShortcutModeEnabledKey = "companionShortcutModeEnabled"

    /// Whether to auto-start the iOS bridge on app launch (default: false)
    /// When disabled, the bridge can still be started manually from Settings > iOS
    var autoStartBridge: Bool {
        didSet {
            let value = autoStartBridge
            DispatchQueue.main.async {
                UserDefaults.standard.set(value, forKey: self.autoStartBridgeKey)
            }
            persistDeclarativeSettings { $0.bridge.autoStartBridge = value }
        }
    }

    /// Whether TalkieServer is allowed to run at all (default: false)
    /// This is an explicit opt-in gate for the Bridge/Gateway server.
    var talkieServerEnabled: Bool {
        didSet {
            let value = talkieServerEnabled
            DispatchQueue.main.async {
                UserDefaults.standard.set(value, forKey: self.talkieServerEnabledKey)
            }
            persistDeclarativeSettings { $0.bridge.talkieServerEnabled = value }
        }
    }

    /// Whether the Gateway module is enabled when TalkieServer starts (default: false)
    /// Requires a server restart to take effect.
    var talkieGatewayEnabled: Bool {
        didSet {
            let value = talkieGatewayEnabled
            DispatchQueue.main.async {
                UserDefaults.standard.set(value, forKey: self.talkieGatewayEnabledKey)
            }
            persistDeclarativeSettings { $0.bridge.talkieGatewayEnabled = value }
        }
    }

    /// Whether Claude Code session discovery is enabled (default: false)
    /// Requires server restart to apply.
    var talkieClaudeSessionsEnabled: Bool {
        didSet {
            let value = talkieClaudeSessionsEnabled
            DispatchQueue.main.async {
                UserDefaults.standard.set(value, forKey: self.talkieClaudeSessionsEnabledKey)
            }
            persistDeclarativeSettings { $0.bridge.talkieClaudeSessionsEnabled = value }
        }
    }

    /// Whether the Mac is currently requesting companion shortcut mode from connected mobile devices.
    var companionShortcutModeEnabled: Bool {
        didSet {
            let value = companionShortcutModeEnabled
            DispatchQueue.main.async {
                UserDefaults.standard.set(value, forKey: self.companionShortcutModeEnabledKey)
            }
            persistDeclarativeSettings {
                $0.bridge.shortcutBoardEnabled = value
                $0.bridge.companionShortcutModeEnabled = value
            }
        }
    }

    /// Ordered 16-slot device shortcut board layout sent to paired mobile devices.
    var companionShortcutSlots: [String] {
        didSet {
            let normalized = Self.normalizedCompanionShortcutSlots(companionShortcutSlots)
            if normalized != companionShortcutSlots {
                companionShortcutSlots = normalized
                return
            }
            persistDeclarativeSettings { $0.bridge.companionShortcutSlots = normalized }
        }
    }

    static func normalizedCompanionShortcutSlots(_ slots: [String]) -> [String] {
        let trimmed = Array(slots.prefix(16))
        if trimmed.count == 16 {
            return trimmed
        }
        return trimmed + Array(repeating: "", count: 16 - trimmed.count)
    }

    var defaultDeviceShortcutBoard: TalkieSettingsConfiguration.ShortcutBoard {
        _ = settingsConfigurationRevision
        return TalkieSettingsConfigurationStore.shared.configuration.devices.defaults.shortcutBoard
            ?? TalkieSettingsConfiguration.defaultDeviceShortcutBoard()
    }

    var defaultDeviceShortcutBoardSlots: [String] {
        _ = settingsConfigurationRevision
        return Self.normalizedCompanionShortcutSlots(
            TalkieSettingsConfigurationStore.shared.configuration.resolvedShortcutSlots()
        )
    }

    var deviceSettingsPublishRevision: Int {
        _ = settingsConfigurationRevision
        return TalkieSettingsConfigurationStore.shared.configuration.devices.publishRevision
    }

    var lastDeviceSettingsPublishedAt: Date? {
        _ = settingsConfigurationRevision
        guard let isoString = TalkieSettingsConfigurationStore.shared.configuration.devices.lastPublishedAt else {
            return nil
        }
        return TalkieDate.fromISO8601(isoString)
    }

    func publishDeviceSettingsNow() {
        let publishedAt = ISO8601DateFormatter().string(from: Date())
        persistDeclarativeSettings { configuration in
            configuration.devices.publishRevision += 1
            configuration.devices.lastPublishedAt = publishedAt
        }
    }

    func removeDeviceSettingsOverride(for deviceID: String) {
        let trimmedDeviceID = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDeviceID.isEmpty else { return }
        guard TalkieSettingsConfigurationStore.shared.configuration.devices.overrides[trimmedDeviceID] != nil else {
            return
        }

        let publishedAt = ISO8601DateFormatter().string(from: Date())
        persistDeclarativeSettings { configuration in
            configuration.devices.overrides.removeValue(forKey: trimmedDeviceID)
            configuration.devices.publishRevision += 1
            configuration.devices.lastPublishedAt = publishedAt
        }
    }

    func resetDefaultDeviceShortcutBoardToStarterKit() {
        setDefaultDeviceShortcutBoardSlots(TalkieSettingsConfiguration.defaultLegacyShortcutSlots)
    }

    func setDefaultDeviceShortcutBoard(_ board: TalkieSettingsConfiguration.ShortcutBoard) {
        let normalized = Self.normalizedCompanionShortcutSlots(Self.legacyShortcutSlots(from: board))

        persistDeclarativeSettings { configuration in
            configuration.devices.defaults.shortcutBoard = board
            configuration.bridge.companionShortcutSlots = normalized
        }

        companionShortcutSlots = normalized
    }

    func setDefaultDeviceShortcutBoardSlots(_ slots: [String]) {
        let normalized = Self.normalizedCompanionShortcutSlots(slots)
        persistDeclarativeSettings { configuration in
            if configuration.devices.defaults.shortcutBoard == nil {
                configuration.devices.defaults.shortcutBoard = TalkieSettingsConfiguration.defaultDeviceShortcutBoard()
            }

            if var talkieSpace = configuration.devices.defaults.shortcutBoard?.spaces.first(where: { $0.id == "talkie" }) {
                talkieSpace.tiles = normalized.enumerated().map { index, slotID in
                    TalkieSettingsConfiguration.shortcutBoardTile(for: slotID, fallbackIndex: index, spaceID: "talkie")
                }

                if let talkieIndex = configuration.devices.defaults.shortcutBoard?.spaces.firstIndex(where: { $0.id == "talkie" }) {
                    configuration.devices.defaults.shortcutBoard?.spaces[talkieIndex] = talkieSpace
                }
            }

            configuration.bridge.companionShortcutSlots = normalized
        }

        companionShortcutSlots = normalized
    }

    private static func legacyShortcutSlots(
        from board: TalkieSettingsConfiguration.ShortcutBoard
    ) -> [String] {
        let talkieSpace = board.spaces.first { $0.id == "talkie" } ?? board.spaces.first
        let derived = talkieSpace?.tiles.prefix(16).map { tile in
            tile.legacySlotID ?? ""
        } ?? []
        let trimmed = Array(derived.prefix(16))
        if trimmed.count == 16 {
            return trimmed
        }
        return trimmed + Array(repeating: "", count: 16 - trimmed.count)
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
            persistDeclarativeSettings { $0.models.llmCostTier = tier }
        }
    }

    // MARK: - Interstitial Settings (UserDefaults - device-specific)
    // Controls behavior of the floating interstitial editor

    private let askOnInterstitialDismissKey = "askOnInterstitialDismiss"

    /// Whether to show the "Save as Memo?" dialog when dismissing interstitial (default: true)
    /// Power users can disable this to dismiss without being asked
    var askOnInterstitialDismiss: Bool {
        didSet {
            let value = askOnInterstitialDismiss
            DispatchQueue.main.async {
                UserDefaults.standard.set(value, forKey: self.askOnInterstitialDismissKey)
            }
            persistDeclarativeSettings { $0.interstitial.askOnDismiss = value }
        }
    }

    // MARK: - Dev Toggles (UserDefaults - device-specific)
    // Debug and development settings for testing alternative UI/features

    private let useCalendarWidgetKey = "dev.useCalendarWidget"

    /// Use calendar widget instead of activity heatmap on home page (default: false)
    /// Dev toggle for testing the calendar JS widget
    var useCalendarWidget: Bool = UserDefaults.standard.bool(forKey: "dev.useCalendarWidget") {
        didSet {
            UserDefaults.standard.set(useCalendarWidget, forKey: useCalendarWidgetKey)
            persistDeclarativeSettings { $0.developer.useCalendarWidget = useCalendarWidget }
        }
    }

    // MARK: - Voice Command Settings

    private let voiceCommandConfidenceThresholdKey = "voiceCommand.confidenceThreshold"

    /// Confidence threshold for auto-executing voice commands (default: 0.75 = 75%)
    /// Higher values require more confidence before auto-executing (safer but needs more confirmation)
    /// Lower values auto-execute more readily (faster but may misfire)
    /// Range: 0.5 to 1.0
    var voiceCommandConfidenceThreshold: Double {
        get {
            let value = UserDefaults.standard.double(forKey: voiceCommandConfidenceThresholdKey)
            if value > 0 { return value }
            _ = settingsConfigurationRevision
            return TalkieSettingsConfigurationStore.shared.configuration.developer.voiceCommandConfidenceThreshold
        }
        set {
            let clamped = min(1.0, max(0.5, newValue))  // Clamp to 0.5-1.0
            UserDefaults.standard.set(clamped, forKey: voiceCommandConfidenceThresholdKey)
            persistDeclarativeSettings { $0.developer.voiceCommandConfidenceThreshold = clamped }
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
            persistDeclarativeSettings { $0.sync.syncIntervalMinutes = minutes }
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
            persistDeclarativeSettings { $0.audio.playbackVolume = volume }
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
            persistDeclarativeSettings { $0.audio.jsonExportSchedule = schedule }
            // Notify JSONExportService to update its timer
            NotificationCenter.default.post(name: .jsonExportScheduleDidChange, object: nil)
        }
    }

    // Internal storage - API keys now use Keychain (secure)
    private var _geminiApiKey: String = ""
    private var _openaiApiKey: String?
    private var _anthropicApiKey: String?
    private var _groqApiKey: String?
    // Model settings - stored in UserDefaults (no Core Data dependency)
    private static let selectedModelKey = "selectedModel"
    private static let liveTranscriptionModelIdKey = "liveTranscriptionModelId"

    private var _selectedModel: String = ""
    private var _liveTranscriptionModelId: String = TalkieDefaults.dictationModelId

    // TTS voice settings
    private var _selectedTTSVoiceId: String = TTSVoiceCatalog.recommendedSettingsVoiceId(hasOpenAIKey: false)

    private let apiKeys = APIKeyStore.shared

    // Public accessors - API keys loaded from Keychain in init()
    // Also syncs to TalkieSharedSettings for TalkieAgent interstitial access
    var geminiApiKey: String {
        get { _geminiApiKey }
        set {
            _geminiApiKey = newValue
            apiKeys.set(newValue.isEmpty ? nil : newValue, for: .gemini)
            // Sync to shared settings for TalkieAgent interstitial
            TalkieSharedSettings.set(newValue.isEmpty ? nil : newValue, forKey: AgentSettingsKey.geminiApiKey)
        }
    }

    var openaiApiKey: String? {
        get { _openaiApiKey }
        set {
            _openaiApiKey = newValue
            apiKeys.set(newValue, for: .openai)
            // Sync to shared settings for TalkieAgent interstitial
            TalkieSharedSettings.set(newValue, forKey: AgentSettingsKey.openaiApiKey)
        }
    }

    var anthropicApiKey: String? {
        get { _anthropicApiKey }
        set {
            _anthropicApiKey = newValue
            apiKeys.set(newValue, for: .anthropic)
            // Sync to shared settings for TalkieAgent interstitial
            TalkieSharedSettings.set(newValue, forKey: AgentSettingsKey.anthropicApiKey)
        }
    }

    var groqApiKey: String? {
        get { _groqApiKey }
        set {
            _groqApiKey = newValue
            apiKeys.set(newValue, for: .groq)
            // Sync to shared settings for TalkieAgent interstitial
            TalkieSharedSettings.set(newValue, forKey: AgentSettingsKey.groqApiKey)
        }
    }

    var elevenLabsApiKey: String? {
        get { apiKeys.get(.elevenLabs) }
        set {
            apiKeys.set(newValue, for: .elevenLabs)
            TalkieSharedSettings.set(newValue, forKey: AgentSettingsKey.elevenLabsApiKey)
        }
    }

    // MARK: - API Key Checks

    func hasOpenAIKey() -> Bool {
        apiKeys.hasKey(for: .openai)
    }

    func hasAnthropicKey() -> Bool {
        apiKeys.hasKey(for: .anthropic)
    }

    func hasGroqKey() -> Bool {
        apiKeys.hasKey(for: .groq)
    }

    func hasElevenLabsKey() -> Bool {
        apiKeys.hasKey(for: .elevenLabs)
    }

    /// Fetch API key (now instant, no keychain prompt)
    func fetchOpenAIKey() -> String? {
        apiKeys.get(.openai)
    }

    func fetchAnthropicKey() -> String? {
        apiKeys.get(.anthropic)
    }

    func fetchGroqKey() -> String? {
        apiKeys.get(.groq)
    }

    func fetchElevenLabsKey() -> String? {
        apiKeys.get(.elevenLabs)
    }

    /// Sync API keys to TalkieSharedSettings for TalkieAgent interstitial access
    /// Called on app launch and whenever keys change
    private func syncAPIKeysToSharedSettings() {
        TalkieSharedSettings.set(_geminiApiKey.isEmpty ? nil : _geminiApiKey, forKey: AgentSettingsKey.geminiApiKey)
        TalkieSharedSettings.set(_openaiApiKey, forKey: AgentSettingsKey.openaiApiKey)
        TalkieSharedSettings.set(_anthropicApiKey, forKey: AgentSettingsKey.anthropicApiKey)
        TalkieSharedSettings.set(_groqApiKey, forKey: AgentSettingsKey.groqApiKey)
        TalkieSharedSettings.set(apiKeys.get(.elevenLabs), forKey: AgentSettingsKey.elevenLabsApiKey)
    }

    var selectedModel: String {
        get { _selectedModel }
        set {
            _selectedModel = newValue
            UserDefaults.standard.set(newValue, forKey: Self.selectedModelKey)
            persistDeclarativeSettings { $0.models.selectedModel = newValue }
        }
    }

    // Transcription model for Live Mode (real-time transcription)
    var liveTranscriptionModelId: String {
        get { _liveTranscriptionModelId }
        set {
            _liveTranscriptionModelId = newValue
            UserDefaults.standard.set(newValue, forKey: Self.liveTranscriptionModelIdKey)
            TalkieSharedSettings.set(newValue, forKey: AgentSettingsKey.selectedModelId)
            persistDeclarativeSettings { $0.models.liveTranscriptionModelId = newValue }
        }
    }

    // TTS voice for text-to-speech synthesis
    var selectedTTSVoiceId: String {
        get { _selectedTTSVoiceId }
        set {
            let normalizedVoiceId = Self.normalizeSelectedTTSVoiceId(newValue, hasOpenAIKey: hasOpenAIKey())
            _selectedTTSVoiceId = normalizedVoiceId
            UserDefaults.standard.set(normalizedVoiceId, forKey: "selectedTTSVoiceId")
            TalkieSharedSettings.set(normalizedVoiceId, forKey: AgentSettingsKey.selectedTTSVoiceId)
            persistDeclarativeSettings { $0.audio.selectedTTSVoiceId = normalizedVoiceId }
        }
    }

    private static func normalizeSelectedTTSVoiceId(_ voiceId: String, hasOpenAIKey: Bool) -> String {
        guard !voiceId.hasPrefix("kokoro:") else {
            return TTSVoiceCatalog.recommendedSettingsVoiceId(hasOpenAIKey: hasOpenAIKey)
        }

        return voiceId
    }

    private init() {
        StartupProfiler.shared.mark("singleton.SettingsManager.start")
        // Suppress Theme.refresh() during init to avoid recursive dispatch_once
        // (Theme.refresh() accesses SettingsManager.shared which is still being initialized)
        isBatchingUpdates = true
        let declarativeSettings = TalkieSettingsConfigurationStore.shared.configuration
        _ = ContextRuleStore.shared

        self.appearanceMode = declarativeSettings.appearance.mode
        self.accentColor = declarativeSettings.appearance.accentColor
        self.enableGlassEffects = declarativeSettings.appearance.enableGlassEffects
        self.uiFontStyle = declarativeSettings.appearance.uiFontStyle
        self.contentFontStyle = declarativeSettings.appearance.contentFontStyle
        self.uiFontSize = declarativeSettings.appearance.uiFontSize
        self.contentFontSize = declarativeSettings.appearance.contentFontSize
        self.consoleTerminalTheme = declarativeSettings.appearance.consoleTerminalTheme
        self.consoleTerminalFont = declarativeSettings.appearance.consoleTerminalFont
        self.consoleTerminalFontSize = declarativeSettings.appearance.consoleTerminalFontSize
        self.uiAllCaps = declarativeSettings.appearance.uiAllCaps
        self.detailLevel = declarativeSettings.appearance.detailLevel
        self.settingsAudience = declarativeSettings.appearance.settingsAudience
        self.isProToolsActive = UserDefaults.standard.bool(forKey: isProToolsActiveKey)
        self.hasCompletedProOnboarding = UserDefaults.standard.bool(forKey: hasCompletedProOnboardingKey)
        self.currentTheme = declarativeSettings.appearance.currentTheme

        self.saveTranscriptsLocally = declarativeSettings.localFiles.saveTranscriptsLocally
        self.transcriptsFolderPath = declarativeSettings.localFiles.transcriptsFolderPath
        self.saveAudioLocally = declarativeSettings.localFiles.saveAudioLocally
        self.audioFolderPath = declarativeSettings.localFiles.audioFolderPath

        self.autoRunWorkflowsEnabled = declarativeSettings.workflow.autoRunEnabled
        self.extensionsFrameworkEnabled = declarativeSettings.bridge.extensionsFrameworkEnabled
        self.autoStartBridge = declarativeSettings.bridge.autoStartBridge
        self.talkieServerEnabled = declarativeSettings.bridge.talkieServerEnabled
        self.talkieGatewayEnabled = declarativeSettings.bridge.talkieGatewayEnabled
        self.talkieClaudeSessionsEnabled = declarativeSettings.bridge.talkieClaudeSessionsEnabled
        self.companionShortcutModeEnabled = declarativeSettings.bridge.shortcutBoardEnabled
        self.companionShortcutSlots = Self.normalizedCompanionShortcutSlots(declarativeSettings.resolvedShortcutSlots())
        self.askOnInterstitialDismiss = declarativeSettings.interstitial.askOnDismiss
        self.llmCostTier = declarativeSettings.models.llmCostTier
        self.syncIntervalMinutes = declarativeSettings.sync.syncIntervalMinutes
        self.jsonExportSchedule = declarativeSettings.audio.jsonExportSchedule
        self.playbackVolume = declarativeSettings.audio.playbackVolume
        self._selectedTTSVoiceId = Self.normalizeSelectedTTSVoiceId(
            declarativeSettings.audio.selectedTTSVoiceId,
            hasOpenAIKey: apiKeys.hasKey(for: .openai)
        )
        self._selectedModel = declarativeSettings.models.selectedModel
        self._liveTranscriptionModelId = declarativeSettings.models.liveTranscriptionModelId

        // Load API keys from encrypted Keychain store (NO Core Data dependency)
        self._geminiApiKey = apiKeys.get(.gemini) ?? ""
        self._openaiApiKey = apiKeys.get(.openai)
        self._anthropicApiKey = apiKeys.get(.anthropic)
        self._groqApiKey = apiKeys.get(.groq)

        var initialLayout = declarativeSettings.home.layout
        initialLayout.migrateForNewFeatures()
        self.homeLayoutConfig = initialLayout
        self.composeLLMProviderId = declarativeSettings.compose.providerId
        self.composeLLMModelId = declarativeSettings.compose.modelId
        self._composeAssistantPrompt = declarativeSettings.compose.assistantPrompt
        TalkieSharedSettings.set(self._selectedTTSVoiceId, forKey: AgentSettingsKey.selectedTTSVoiceId)

        // Grandfather clause: existing Pro users get auto-activated
        if declarativeSettings.appearance.settingsAudience == .pro
            && !self.isProToolsActive {
            self.isProToolsActive = true
            self.hasCompletedProOnboarding = true
            UserDefaults.standard.set(true, forKey: isProToolsActiveKey)
            UserDefaults.standard.set(true, forKey: hasCompletedProOnboardingKey)
        }

        // If users have a saved theme but no explicit typography override, apply theme defaults.
        if let theme = self.currentTheme {
            let hasUIFontOverride =
                UserDefaults.standard.string(forKey: uiFontStyleKey) != nil ||
                UserDefaults.standard.string(forKey: "fontStyle") != nil
            let hasContentFontOverride = UserDefaults.standard.string(forKey: contentFontStyleKey) != nil

            if !hasUIFontOverride {
                self.uiFontStyle = theme.uiFontStyle
                UserDefaults.standard.set(theme.uiFontStyle.rawValue, forKey: uiFontStyleKey)
            }
            if !hasContentFontOverride {
                self.contentFontStyle = theme.contentFontStyle
                UserDefaults.standard.set(theme.contentFontStyle.rawValue, forKey: contentFontStyleKey)
            }
        }

        // One-time migration: older Technical defaults were mono-heavy.
        // Normalize Linear/Technical to system fonts for cleaner rendering.
        let linearFontMigrationKey = "settingsManager.linearFontMigration.v2"
        if !UserDefaults.standard.bool(forKey: linearFontMigrationKey),
           self.currentTheme == .technical {
            let monoStyles: Set<FontStyleOption> = [.monospace, .jetbrainsMono, .geistMono]
            if monoStyles.contains(self.uiFontStyle) || monoStyles.contains(self.contentFontStyle) {
                self.uiFontStyle = .system
                self.contentFontStyle = .system
                UserDefaults.standard.set(FontStyleOption.system.rawValue, forKey: uiFontStyleKey)
                UserDefaults.standard.set(FontStyleOption.system.rawValue, forKey: contentFontStyleKey)
            }
            UserDefaults.standard.set(true, forKey: linearFontMigrationKey)
        }

        // Sync API keys to TalkieSharedSettings for TalkieAgent interstitial
        syncAPIKeysToSharedSettings()

        // Apply appearance mode on launch
        applyAppearanceMode()

        // Apply theme config to TalkieKit design tokens
        applyThemeConfig()

        // Keep helper apps aligned with the selected transcription model.
        TalkieSharedSettings.set(_liveTranscriptionModelId, forKey: AgentSettingsKey.selectedModelId)

        // Sync appearance mode so TalkieAgent matches on next launch
        TalkieSharedSettings.set(appearanceMode.rawValue, forKey: AgentSettingsKey.appearanceMode)

        // Configure theme with current values (use explicit values to avoid recursive access to .shared)
        Theme.configure(
            cornerMultiplier: currentCornerRadiusMultiplier,
            borderMultiplier: currentBorderWidth
        )

        // Re-enable per-property Theme.refresh() now that init is complete
        isBatchingUpdates = false

        StartupProfiler.shared.mark("singleton.SettingsManager.done")
    }

    // MARK: - Core Data Migration Helper

    /// Attempt to read a setting value from the legacy Core Data AppSettings entity.
    /// Returns nil if Core Data isn't ready or the setting doesn't exist.
    private static func migrateSettingFromCoreData(key: String) -> String? {
        // NOTE: Core Data removed from main app - settings migration no longer available
        // Settings now stored in UserDefaults/KeychainManager only
        logger.debug("Core Data migration skipped for \(key) - Core Data moved to TalkieSync")
        return nil
    }

    // MARK: - Validation
    var hasValidApiKey: Bool {
        !geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - JSON Export
    /// Export current settings as JSON (excluding sensitive data like API keys)
    func exportSettingsAsJSON() -> String {

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

        // Compose / Interstitial
        settings["composeAssistant"] = [
            "providerId": composeLLMProviderId as Any,
            "modelId": composeLLMModelId as Any,
            "prompt": composeAssistantPrompt
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
    static let extensionsFrameworkSettingDidChange = Notification.Name("extensionsFrameworkSettingDidChange")
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
