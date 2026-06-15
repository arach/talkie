//
//  LiveSettings.swift
//  TalkieAgent
//
//  Settings for Talkie Agent
//

import Foundation
import SwiftUI
import Carbon.HIToolbox
import TalkieKit

private let log = Log(.system)

// MARK: - Appearance Types (from TalkieKit)
// OverlayStyle, IndicatorPosition, PillPosition are now in TalkieKit

// Legacy compatibility alias
typealias OverlayPosition = IndicatorPosition

// MARK: - Appearance Mode (Light/Dark/System)

enum AppearanceMode: String, CaseIterable, Codable {
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
        switch self {
        case .system: return "Follow system appearance"
        case .light: return "Always light mode"
        case .dark: return "Always dark mode"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

// MARK: - Visual Theme (Color Schemes)

enum VisualTheme: String, CaseIterable, Codable {
    case live = "live"          // Maps to talkiePro
    case midnight = "midnight"  // Maps to talkiePro (legacy)
    case terminal = "terminal"
    case darkMatte = "darkMatte"
    case light = "light"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // Migrate retired rawValues
        switch raw {
        case "minimal": self = .light
        case "liquidGlass": self = .midnight
        default:
            self = VisualTheme(rawValue: raw) ?? .live
        }
    }

    var displayName: String {
        switch self {
        case .live: return "Pro"
        case .midnight: return "Pro"
        case .terminal: return "Terminal"
        case .darkMatte: return "Dark Matte"
        case .light: return "Light"
        }
    }

    var description: String {
        switch self {
        case .live: return "Professional dark theme"
        case .midnight: return "Professional dark theme"
        case .terminal: return "Clean monospace, sharp corners"
        case .darkMatte: return "Dark with warm matte undertones"
        case .light: return "Clean light mode with neutral surfaces"
        }
    }

    /// Default accent color for this theme
    var accentColor: AccentColorOption {
        switch self {
        case .live: return .blue
        case .midnight: return .blue
        case .terminal: return .gray    // No gimmicks
        case .darkMatte: return .orange
        case .light: return .orange
        }
    }

    /// Suggested appearance mode for this theme (user can override)
    var suggestedAppearance: AppearanceMode {
        switch self {
        case .live: return .dark
        case .midnight: return .dark
        case .terminal: return .dark
        case .darkMatte: return .dark
        case .light: return .light
        }
    }

    /// Preview colors for theme selector
    var previewColors: (bg: Color, fg: Color, accent: Color) {
        switch self {
        case .live:
            return (Color(white: 0.08), Color.white.opacity(0.85), Color.blue)
        case .midnight:
            return (Color(white: 0.08), Color.white.opacity(0.85), Color(red: 0.4, green: 0.7, blue: 1.0))
        case .terminal:
            // Ghostty-style: black bg, light gray text, subtle gray accent
            return (Color.black, Color(white: 0.85), Color(white: 0.5))
        case .darkMatte:
            return (
                Color(red: 0.0449, green: 0.0333, blue: 0.0242),
                Color(red: 0.8603, green: 0.8416, blue: 0.8171),
                Color(red: 0.8326, green: 0.5895, blue: 0.2837)
            )
        case .light:
            return (
                Color(red: 0.9737, green: 0.9737, blue: 0.9737),
                Color(red: 0.0625, green: 0.0697, blue: 0.0774),
                Color(red: 0.8961, green: 0.5104, blue: 0.0706)
            )
        }
    }
}

// Legacy compatibility - maps to new system
@available(*, deprecated, message: "Use AppearanceMode and VisualTheme instead")
typealias AppTheme = AppearanceMode

/// Design system font sizes - canonical integer sizes, no fractional scaling
/// Each size tier defines proper integer point sizes for crisp rendering
enum FontSize: String, CaseIterable, Codable {
    case small = "small"
    case medium = "medium"
    case large = "large"

    var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    // MARK: - Design System Sizes (integers only, no scaling)

    /// Extra-small: metadata, timestamps, labels
    var xs: CGFloat {
        switch self {
        case .small: return 9
        case .medium: return 10
        case .large: return 11
        }
    }

    /// Small: secondary text, captions
    var sm: CGFloat {
        switch self {
        case .small: return 10
        case .medium: return 11
        case .large: return 12
        }
    }

    /// Body: primary transcription text
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

    // MARK: - Convenience Font Accessors

    var xsFont: Font { .system(size: xs) }
    var smFont: Font { .system(size: sm) }
    var bodyFont: Font { .system(size: body) }
    var detailFont: Font { .system(size: detail) }
    var titleFont: Font { .system(size: title, weight: .medium) }

    // Legacy compatibility
    var previewSize: CGFloat { body }
}

enum AccentColorOption: String, CaseIterable, Codable {
    case system = "system"
    case blue = "blue"
    case purple = "purple"
    case pink = "pink"
    case red = "red"
    case orange = "orange"
    case yellow = "yellow"
    case green = "green"
    case teal = "teal"
    case gray = "gray"

    var displayName: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .system: return .accentColor
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .gray: return .gray
        }
    }
}

// Legacy compatibility for ThemePreset
@available(*, deprecated, message: "Use VisualTheme instead")
typealias ThemePreset = VisualTheme

// MARK: - Context Preference

/// Which app context is considered "primary" for utterances
enum PrimaryContextSource: String, CaseIterable, Codable {
    case startApp = "startApp"
    case endApp = "endApp"

    var displayName: String {
        switch self {
        case .startApp: return "Where I Started"
        case .endApp: return "Where I Finished"
        }
    }

    var description: String {
        switch self {
        case .startApp: return "App where you pressed the hotkey"
        case .endApp: return "App where you were when recording stopped"
        }
    }
}

// MARK: - Hotkey Configuration

struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    /// Toggle hotkey default - uses TalkieEnvironment for environment-specific modifiers
    /// Prod: ⌥⌘L, Dev: ⌃⌥⌘L
    static var `default`: HotkeyConfig {
        HotkeyConfig(keyCode: 37, modifiers: TalkieEnvironment.current.defaultHotkeyModifiers)  // L
    }

    /// Push-to-talk hotkey default - uses TalkieEnvironment for environment-specific modifiers
    /// Prod: ⌥⌘;, Dev: ⌃⌥⌘;
    static var defaultPTT: HotkeyConfig {
        HotkeyConfig(keyCode: 41, modifiers: TalkieEnvironment.current.defaultHotkeyModifiers)  // ;
    }

    /// Quick selection action default: ⌥⌘Y
    static var defaultSelectionQuick: HotkeyConfig {
        HotkeyConfig(keyCode: 16, modifiers: UInt32(cmdKey | optionKey))  // Y
    }

    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    private func keyCodeToString(_ code: UInt32) -> String {
        let keyMap: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
            38: "J", 40: "K", 41: ";", 45: "N", 46: "M",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
            22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc"
        ]
        return keyMap[code] ?? "?"
    }
}

// MARK: - File-backed Overlay Indicator Overrides

struct OverlayIndicatorFileOverrides: Codable {
    struct TopBar: Codable {
        var style: OverlayStyle?
        var width: Double?
        var height: Double?
        var cornerRadius: Double?
        var backgroundOpacity: Double?
    }

    struct Pill: Codable {
        var width: Double?
        var developerWidth: Double?
        var height: Double?
        var hitWidth: Double?
    }

    var version: Int = 1
    var topBar = TopBar()
    var pill = Pill()
}

@MainActor
final class OverlayIndicatorOverridesStore {
    static let shared = OverlayIndicatorOverridesStore()

    private let fileManager = FileManager.default
    private let fileURL: URL
    private var cachedOverrides = OverlayIndicatorFileOverrides()
    private var cachedModificationDate: Date?

    private init() {
        let settingsDirectory = TalkieEnvironment.current.appSupportDirectory
            .appendingPathComponent("settings", isDirectory: true)

        try? fileManager.createDirectory(at: settingsDirectory, withIntermediateDirectories: true)
        fileURL = settingsDirectory.appendingPathComponent("overlay-indicators.json")

        writeTemplateIfMissing()
        refreshIfNeeded(force: true)
    }

    var displayPath: String {
        let home = fileManager.homeDirectoryForCurrentUser.path
        return fileURL.path.replacingOccurrences(of: home, with: "~")
    }

    func snapshot() -> OverlayIndicatorFileOverrides {
        refreshIfNeeded()
        return cachedOverrides
    }

    func resolvedOverlayStyle(fallback: OverlayStyle) -> OverlayStyle {
        snapshot().topBar.style ?? fallback
    }

    func topBarWidth(fallback: Double) -> CGFloat {
        CGFloat(snapshot().topBar.width ?? fallback)
    }

    func topBarHeight(fallback: Double) -> CGFloat {
        CGFloat(snapshot().topBar.height ?? fallback)
    }

    func topBarCornerRadius(fallback: Double) -> CGFloat {
        CGFloat(snapshot().topBar.cornerRadius ?? fallback)
    }

    func topBarBackgroundOpacity(fallback: Double) -> Double {
        snapshot().topBar.backgroundOpacity ?? fallback
    }

    func pillWidth(fallback: Double) -> CGFloat {
        CGFloat(snapshot().pill.width ?? fallback)
    }

    func pillDeveloperWidth(fallback: Double) -> CGFloat {
        CGFloat(snapshot().pill.developerWidth ?? fallback)
    }

    func pillHeight(fallback: Double) -> CGFloat {
        CGFloat(snapshot().pill.height ?? fallback)
    }

    func pillHitWidth(fallback: Double) -> CGFloat {
        CGFloat(snapshot().pill.hitWidth ?? fallback)
    }

    private func refreshIfNeeded(force: Bool = false) {
        let modificationDate = fileModificationDate()
        guard force || modificationDate != cachedModificationDate else { return }

        cachedModificationDate = modificationDate

        guard let data = try? Data(contentsOf: fileURL) else {
            cachedOverrides = OverlayIndicatorFileOverrides()
            return
        }

        do {
            cachedOverrides = try JSONDecoder().decode(OverlayIndicatorFileOverrides.self, from: data)
        } catch {
            cachedOverrides = OverlayIndicatorFileOverrides()
            log.error("Failed to decode overlay indicator overrides: \(error.localizedDescription)")
        }
    }

    private func writeTemplateIfMissing() {
        guard !fileManager.fileExists(atPath: fileURL.path) else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(OverlayIndicatorFileOverrides()) else { return }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("Failed to write overlay indicator template: \(error.localizedDescription)")
        }
    }

    private func fileModificationDate() -> Date? {
        try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

// MARK: - Live Settings

@MainActor
final class LiveSettings: ObservableObject {
    static let shared = LiveSettings()
    static let defaultIslandOverlayWidth: Double = 168
    static let defaultIslandOverlayHeight: Double = 32

    // MARK: - Shared Settings Storage
    // Uses TalkieSharedSettings from TalkieKit for cross-app sync with Talkie
    private var storage: UserDefaults { TalkieSharedSettings }
    private var isSynchronizingPlacements = false

    // MARK: - Published Settings

    /// Toggle hotkey (press to start, press to stop)
    @Published var hotkey: HotkeyConfig {
        didSet { save() }
    }

    /// Push-to-talk hotkey (hold to record, release to stop)
    @Published var pttHotkey: HotkeyConfig {
        didSet { save() }
    }

    /// Whether push-to-talk hotkey is enabled
    @Published var pttEnabled: Bool {
        didSet { save() }
    }

    /// Quick selection action hotkey (default: ⌥⌘Y)
    @Published var selectionQuickHotkey: HotkeyConfig {
        didSet { save() }
    }

    /// Selected model ID with family prefix (e.g., "whisper:openai_whisper-small" or "parakeet:v3")
    @Published var selectedModelId: String {
        didSet { save() }
    }

    /// Legacy property for backwards compatibility - maps to selectedModelId
    @available(*, deprecated, message: "Use selectedModelId instead")
    var whisperModel: WhisperModel {
        get {
            // Extract model ID from selectedModelId and try to match
            let (_, modelId) = ModelInfo.parseModelId(selectedModelId)
            return WhisperModel(rawValue: modelId) ?? .small
        }
        set {
            selectedModelId = "whisper:\(newValue.rawValue)"
        }
    }

    @Published var routingMode: RoutingMode {
        didSet { save() }
    }

    /// Selected microphone device ID (0 = system default)
    /// Legacy: kept for migration, prefer using selectedMicrophoneUID
    @Published var selectedMicrophoneID: UInt32 {
        didSet { save() }
    }

    /// Microphone selection mode (system default vs fixed device)
    @Published var selectedMicrophoneMode: MicrophoneSelectionMode {
        didSet { save() }
    }

    /// Persistent UID of selected microphone (survives reconnects)
    @Published var selectedMicrophoneUID: String? {
        didSet { save() }
    }

    /// Display name of selected microphone (for UI when device is unavailable)
    @Published var selectedMicrophoneName: String? {
        didSet { save() }
    }

    @Published var dictationTTLHours: Int {
        didSet {
            save()
            DictationStore.shared.ttlHours = dictationTTLHours
        }
    }

    /// Segment duration for main mic recordings (seconds). 0 = no segmentation.
    @Published var segmentDuration: TimeInterval {
        didSet { save() }
    }

    /// Storage/quality preset for Agent-owned screen recordings.
    @Published var screenRecordingQualityPreset: ScreenRecordingQualityPreset {
        didSet { save() }
    }

    /// Delay before reusing the last screen recording target. 0 starts immediately.
    @Published var screenRecordingCountdownSeconds: Int {
        didSet { save() }
    }

    /// Capture app/system audio in screen recordings.
    @Published var screenRecordingIncludesSystemAudio: Bool {
        didSet { save() }
    }

    /// Capture the selected microphone as a voiceover track in screen recordings.
    @Published var screenRecordingIncludesMicrophone: Bool {
        didSet { save() }
    }

    /// Show Agent's camera bubble while screen recording.
    @Published var screenRecordingShowsCameraBubble: Bool {
        didSet { save() }
    }

    @Published var overlayStyle: OverlayStyle {
        didSet { save() }
    }

    @Published var islandOverlayMotion: Double {
        didSet { save() }
    }

    @Published var islandOverlayReactivity: Double {
        didSet { save() }
    }

    @Published var islandOverlayShape: Double {
        didSet { save() }
    }

    @Published var islandOverlayWidth: Double {
        didSet { save() }
    }

    @Published var islandOverlayHeight: Double {
        didSet { save() }
    }

    var effectiveOverlayStyle: OverlayStyle {
        guard overlayStyle.showsTopOverlay else { return .pillOnly }
        return OverlayIndicatorOverridesStore.shared.resolvedOverlayStyle(fallback: overlayStyle)
    }

    var islandVisualizationSettings: IslandVisualizationSettings {
        IslandVisualizationSettings(
            motion: islandOverlayMotion,
            reactivity: islandOverlayReactivity,
            shape: islandOverlayShape
        )
    }

    @Published var overlayPosition: OverlayPosition {
        didSet {
            guard !isSynchronizingPlacements else { return }
            withPlacementSynchronization {
                overlayPlacement = NormalizedPlacement(indicatorPosition: overlayPosition)
            }
            save()
        }
    }

    @Published var overlayPlacement: NormalizedPlacement {
        didSet {
            guard !isSynchronizingPlacements else { return }
            withPlacementSynchronization {
                overlayPosition = overlayPlacement.nearestIndicatorPosition
            }
            save()
        }
    }

    @Published var pillEnabled: Bool {
        didSet { save() }
    }

    // Floating Pill Settings
    @Published var pillPosition: PillPosition {
        didSet {
            guard !isSynchronizingPlacements else { return }
            withPlacementSynchronization {
                pillPlacement = NormalizedPlacement(pillPosition: pillPosition)
            }
            save()
        }
    }

    @Published var pillPlacement: NormalizedPlacement {
        didSet {
            guard !isSynchronizingPlacements else { return }
            withPlacementSynchronization {
                pillPosition = pillPlacement.nearestPillPosition
            }
            save()
        }
    }

    @Published var pillShowOnAllScreens: Bool {
        didSet { save() }
    }

    @Published var pillExpandsDuringRecording: Bool {
        didSet { save() }
    }

    /// Enable notch overlay on MacBooks with a notch
    @Published var notchOverlayEnabled: Bool {
        didSet { save() }
    }

    @Published var startSound: TalkieSound {
        didSet { save() }
    }

    @Published var finishSound: TalkieSound {
        didSet { save() }
    }

    @Published var pastedSound: TalkieSound {
        didSet { save() }
    }

    /// Sound for graceful cancellations (too short, setup incomplete). Dev-only.
    #if DEBUG
    @Published var cancelledSound: TalkieSound {
        didSet { save() }
    }
    #endif

    @Published var appearanceMode: AppearanceMode {
        didSet {
            save()
            applyAppearance()
        }
    }

    @Published var visualTheme: VisualTheme {
        didSet {
            save()
            // Optionally update accent color to match theme default
            if accentColor == .system {
                // Trigger UI update without changing setting
            }
        }
    }

    @Published var fontSize: FontSize {
        didSet { save() }
    }

    @Published var accentColor: AccentColorOption {
        didSet { save() }
    }

    /// Glass mode enabled via launch argument: --glass-mode
    /// Not a runtime toggle - set at startup only (simpler, no view rebuild issues)
    var glassMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--glass-mode")
    }

    /// Which context (start or end app) is primary for utterances
    @Published var primaryContextSource: PrimaryContextSource {
        didSet { save() }
    }

    /// How much context to capture from the Accessibility API
    @Published var contextCaptureDetail: ContextCaptureDetail {
        didSet { save() }
    }

    /// Session-scoped permission for capturing context (resets on app restart)
    @Published var contextCaptureSessionAllowed: Bool = true

    /// Whether to activate the start app after pasting
    @Published var returnToOriginAfterPaste: Bool {
        didSet { save() }
    }

    /// Press Enter/Return after pasting (useful for chat apps, terminals)
    @Published var pressEnterAfterPaste: Bool {
        didSet { save() }
    }

    /// Legacy setting kept for compatibility; selected text now pastes in place.
    @Published var autoScratchpadOnSelection: Bool = false {
        didSet { save() }
    }

    // MARK: - Selection (Quick Selection / Reader)

    /// Master toggle for selection feature
    @Published var selectionEnabled: Bool {
        didSet { save() }
    }

    /// Default processing mode
    @Published var selectionDefaultMode: SelectionMode {
        didSet { save() }
    }

    /// Word count threshold for auto-verbatim in auto mode
    @Published var selectionShortTextThreshold: Int {
        didSet { save() }
    }

    /// Dedicated TTS voice for selection (nil = use global)
    @Published var selectionTTSVoiceId: String? {
        didSet { save() }
    }

    /// LLM timeout in seconds
    @Published var selectionLLMTimeout: Double {
        didSet { save() }
    }

    /// Show feedback overlay HUD
    @Published var selectionShowFeedbackOverlay: Bool {
        didSet { save() }
    }

    /// Per-app-category mode overrides
    @Published var selectionAppOverrides: [SelectionAppCategoryOverride] {
        didSet { save() }
    }

    // Legacy compatibility - returns appearance mode
    @available(*, deprecated, message: "Use appearanceMode instead")
    var theme: AppearanceMode {
        get { appearanceMode }
        set { appearanceMode = newValue }
    }

    // MARK: - Init

    private init() {
        // Read from shared storage (Talkie is the owner, we're just reading)
        // Note: Use TalkieSharedSettings directly since storage property requires self
        let store = TalkieSharedSettings
        let suiteName = TalkieEnvironment.current.sharedSettingsSuite
        log.info("LiveSettings.init() loading from suite: \(suiteName)")

        // Load toggle hotkey
        if let data = store.data(forKey: AgentSettingsKey.hotkey),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.hotkey = config
            log.debug("Loaded hotkey: \(config.displayString)")
        } else {
            self.hotkey = .default
            log.debug("No saved hotkey, using default: \(HotkeyConfig.default.displayString)")
        }

        // Load push-to-talk hotkey
        if let data = store.data(forKey: AgentSettingsKey.pttHotkey),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.pttHotkey = config
        } else {
            self.pttHotkey = .defaultPTT
        }

        // Load PTT enabled state (default: false)
        self.pttEnabled = store.bool(forKey: AgentSettingsKey.pttEnabled)

        // Load quick selection hotkey
        if let data = store.data(forKey: AgentSettingsKey.selectionQuickHotkey),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.selectionQuickHotkey = config
        } else {
            self.selectionQuickHotkey = .defaultSelectionQuick
        }

        // Load selected model ID
        if let modelId = store.string(forKey: AgentSettingsKey.selectedModelId) {
            self.selectedModelId = modelId
        } else {
            // Default to TalkieKit's single source of truth
            self.selectedModelId = TalkieDefaults.transcriptionModelId
        }

        // Load routing mode
        let routingRaw = store.string(forKey: AgentSettingsKey.routingMode) ?? "paste"
        self.routingMode = routingRaw == "clipboardOnly" ? .clipboardOnly : .paste

        // Load selected microphone (0 = system default)
        let savedMicID = UInt32(store.integer(forKey: AgentSettingsKey.selectedMicrophoneID))
        self.selectedMicrophoneID = savedMicID

        // Load new UID-based microphone selection
        let savedUID = store.string(forKey: AgentSettingsKey.selectedMicrophoneUID)
        self.selectedMicrophoneUID = savedUID
        self.selectedMicrophoneName = store.string(forKey: AgentSettingsKey.selectedMicrophoneName)

        let needsMigration = store.string(forKey: AgentSettingsKey.selectedMicrophoneMode) == nil
        if let modeRaw = store.string(forKey: AgentSettingsKey.selectedMicrophoneMode),
           let mode = MicrophoneSelectionMode(rawValue: modeRaw) {
            // Validate: if mode is fixedUID but no UID, reset to systemDefault
            if mode == .fixedUID && savedUID == nil {
                self.selectedMicrophoneMode = .systemDefault
                // Persist immediately so AudioCapture sees the correct value
                store.set(MicrophoneSelectionMode.systemDefault.rawValue, forKey: AgentSettingsKey.selectedMicrophoneMode)
                log.info("Reset mic mode to systemDefault (fixedUID with no UID)")
            } else {
                self.selectedMicrophoneMode = mode
            }
        } else {
            // Migration: only use fixedUID mode if we have a UID, otherwise default to systemDefault
            // Legacy ID-based selection can't be migrated without UID, user will need to re-select
            let migratedMode: MicrophoneSelectionMode = (savedUID != nil) ? .fixedUID : .systemDefault
            self.selectedMicrophoneMode = migratedMode
            // Persist migration immediately so AudioCapture sees the correct value
            store.set(migratedMode.rawValue, forKey: AgentSettingsKey.selectedMicrophoneMode)
            if needsMigration {
                log.info("Migrated mic mode to \(migratedMode.rawValue)")
            }
        }

        // Load TTL (default 48 hours)
        let ttl = store.integer(forKey: AgentSettingsKey.utteranceTTLHours)
        self.dictationTTLHours = ttl > 0 ? ttl : 48

        // Load segment duration (default 600s = 10 min, 0 = disabled)
        let seg = store.double(forKey: AgentSettingsKey.segmentDuration)
        self.segmentDuration = seg > 0 ? seg : 600

        if let rawValue = store.string(forKey: AgentSettingsKey.screenRecordingQuality)
            ?? UserDefaults.standard.string(forKey: AgentSettingsKey.screenRecordingQuality),
           let preset = ScreenRecordingQualityPreset(rawValue: rawValue) {
            self.screenRecordingQualityPreset = preset
        } else {
            self.screenRecordingQualityPreset = .agent
        }
        let countdown = store.integer(forKey: AgentSettingsKey.screenRecordingCountdownSeconds)
        self.screenRecordingCountdownSeconds = [0, 1, 3, 5].contains(countdown) ? countdown : 0
        self.screenRecordingIncludesSystemAudio = store.object(forKey: AgentSettingsKey.screenRecordingIncludesSystemAudio) as? Bool ?? false
        self.screenRecordingIncludesMicrophone = store.object(forKey: AgentSettingsKey.screenRecordingIncludesMicrophone) as? Bool ?? false
        self.screenRecordingShowsCameraBubble = store.object(forKey: AgentSettingsKey.screenRecordingShowsCameraBubble) as? Bool ?? false

        // Load overlay style
        if let rawValue = store.string(forKey: AgentSettingsKey.overlayStyle),
           let style = OverlayStyle(rawValue: rawValue) {
            self.overlayStyle = style
        } else {
            self.overlayStyle = .particles
        }

        self.islandOverlayMotion = Self.storedOverlayDouble(
            forKey: AgentSettingsKey.islandOverlayMotion,
            from: store,
            defaultValue: IslandVisualizationSettings.defaultValue.motion
        )
        self.islandOverlayReactivity = Self.storedOverlayDouble(
            forKey: AgentSettingsKey.islandOverlayReactivity,
            from: store,
            defaultValue: IslandVisualizationSettings.defaultValue.reactivity
        )
        self.islandOverlayShape = Self.storedOverlayDouble(
            forKey: AgentSettingsKey.islandOverlayShape,
            from: store,
            defaultValue: IslandVisualizationSettings.defaultValue.shape
        )
        self.islandOverlayWidth = Self.storedDimensionDouble(
            forKey: AgentSettingsKey.islandOverlayWidth,
            from: store,
            defaultValue: Self.defaultIslandOverlayWidth,
            range: 112...260
        )
        self.islandOverlayHeight = Self.storedDimensionDouble(
            forKey: AgentSettingsKey.islandOverlayHeight,
            from: store,
            defaultValue: Self.defaultIslandOverlayHeight,
            range: 24...48
        )

        // Load overlay position
        let overlayPosition: OverlayPosition
        if let rawValue = store.string(forKey: AgentSettingsKey.overlayPosition),
           let position = OverlayPosition(rawValue: rawValue) {
            overlayPosition = position
        } else {
            overlayPosition = .topCenter
        }
        self.overlayPosition = overlayPosition
        let overlayPlacement = Self.decodePlacement(
            forKey: AgentSettingsKey.overlayPlacement,
            from: store
        ) ?? NormalizedPlacement(indicatorPosition: overlayPosition)
        self.overlayPlacement = overlayPlacement
            .migratingLegacyIndicatorAnchor(for: overlayPosition)
            .snappedToNearestIndicatorAnchor()

        // Load pill position
        let pillPosition: PillPosition
        if let rawValue = store.string(forKey: AgentSettingsKey.pillPosition),
           let position = PillPosition(rawValue: rawValue) {
            pillPosition = position
        } else {
            pillPosition = .bottomCenter
        }
        self.pillPosition = pillPosition
        let pillPlacement = Self.decodePlacement(
            forKey: AgentSettingsKey.pillPlacement,
            from: store
        ) ?? NormalizedPlacement(pillPosition: pillPosition)
        self.pillPlacement = pillPlacement
            .migratingLegacyPillAnchor(for: pillPosition)
            .snappedToNearestPillAnchor()

        // Load pill settings
        self.pillEnabled = store.object(forKey: AgentSettingsKey.pillEnabled) as? Bool ?? true
        self.pillShowOnAllScreens = store.object(forKey: AgentSettingsKey.pillShowOnAllScreens) as? Bool ?? true
        self.pillExpandsDuringRecording = store.object(forKey: AgentSettingsKey.pillExpandsDuringRecording) as? Bool ?? true
        self.notchOverlayEnabled = store.object(forKey: AgentSettingsKey.notchOverlayEnabled) as? Bool ?? true

        // Load sounds (default to pop for start/finish, tink for pasted)
        if let rawValue = store.string(forKey: AgentSettingsKey.startSound),
           let sound = TalkieSound(rawValue: rawValue) {
            self.startSound = sound
        } else {
            self.startSound = .pop
        }

        if let rawValue = store.string(forKey: AgentSettingsKey.finishSound),
           let sound = TalkieSound(rawValue: rawValue) {
            self.finishSound = sound
        } else {
            self.finishSound = .pop
        }

        if let rawValue = store.string(forKey: AgentSettingsKey.pastedSound),
           let sound = TalkieSound(rawValue: rawValue) {
            self.pastedSound = sound
        } else {
            self.pastedSound = .tink
        }

        #if DEBUG
        if let rawValue = store.string(forKey: AgentSettingsKey.cancelledSound),
           let sound = TalkieSound(rawValue: rawValue) {
            self.cancelledSound = sound
        } else {
            self.cancelledSound = .tink
        }
        #endif

        // Load appearance mode
        if let rawValue = store.string(forKey: AgentSettingsKey.appearanceMode),
           let mode = AppearanceMode(rawValue: rawValue) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .system
        }

        // Load visual theme
        if let rawValue = store.string(forKey: AgentSettingsKey.visualTheme),
           let theme = VisualTheme(rawValue: rawValue) {
            self.visualTheme = theme
        } else {
            self.visualTheme = .live
        }

        // Load font size
        if let rawValue = store.string(forKey: AgentSettingsKey.fontSize),
           let size = FontSize(rawValue: rawValue) {
            self.fontSize = size
        } else {
            self.fontSize = .medium
        }

        // Load accent color
        if let rawValue = store.string(forKey: AgentSettingsKey.accentColor),
           let color = AccentColorOption(rawValue: rawValue) {
            self.accentColor = color
        } else {
            self.accentColor = .system
        }

        // Note: glassMode is now a computed property checking launch arg --glass-mode

        // Load primary context source (default: start app)
        if let rawValue = store.string(forKey: AgentSettingsKey.primaryContextSource),
           let source = PrimaryContextSource(rawValue: rawValue) {
            self.primaryContextSource = source
        } else {
            self.primaryContextSource = .startApp
        }

        // Load context capture detail (default: rich)
        if let rawValue = store.string(forKey: AgentSettingsKey.contextCaptureDetail),
           let detail = ContextCaptureDetail(rawValue: rawValue) {
            self.contextCaptureDetail = detail
        } else {
            self.contextCaptureDetail = .rich
        }

        // Load return to origin setting (default: false)
        self.returnToOriginAfterPaste = store.bool(forKey: AgentSettingsKey.returnToOriginAfterPaste)
        self.pressEnterAfterPaste = store.bool(forKey: AgentSettingsKey.pressEnterAfterPaste)
        self.autoScratchpadOnSelection = store.bool(forKey: AgentSettingsKey.autoScratchpadOnSelection)

        // Load selection settings
        self.selectionEnabled = store.object(forKey: AgentSettingsKey.selectionEnabled) as? Bool ?? true
        self.selectionDefaultMode = store.string(forKey: AgentSettingsKey.selectionDefaultMode).flatMap(SelectionMode.init) ?? .auto
        let selThreshold = store.integer(forKey: AgentSettingsKey.selectionShortTextThreshold)
        self.selectionShortTextThreshold = selThreshold > 0 ? selThreshold : 45
        let storedSelectionVoiceId = store.string(forKey: AgentSettingsKey.selectionTTSVoiceId)
        self.selectionTTSVoiceId = storedSelectionVoiceId?.hasPrefix("kokoro:") == true ? nil : storedSelectionVoiceId
        let selTimeout = store.double(forKey: AgentSettingsKey.selectionLLMTimeout)
        self.selectionLLMTimeout = selTimeout > 0 ? selTimeout : 6.0
        self.selectionShowFeedbackOverlay = store.object(forKey: AgentSettingsKey.selectionShowFeedbackOverlay) as? Bool ?? true
        if let data = store.data(forKey: AgentSettingsKey.selectionAppOverrides),
           let overrides = try? JSONDecoder().decode([SelectionAppCategoryOverride].self, from: data) {
            self.selectionAppOverrides = overrides
        } else {
            self.selectionAppOverrides = SelectionAppCategoryOverride.defaults
        }

        // Apply TTL to store
        DictationStore.shared.ttlHours = dictationTTLHours

        #if DEBUG
        dumpSettingsToFile()
        #endif
    }

    // MARK: - Debug

    #if DEBUG
    private func dumpSettingsToFile() {
        let settings: [String: Any] = [
            "microphone": [
                "id": selectedMicrophoneID,
                "mode": selectedMicrophoneMode.rawValue,
                "uid": selectedMicrophoneUID ?? "(nil)",
                "name": selectedMicrophoneName ?? "(nil)"
            ],
            "model": selectedModelId,
            "routing": routingMode.rawValue,
            "hotkey": hotkey.displayString,
            "pttHotkey": pttHotkey.displayString,
            "pttEnabled": pttEnabled,
            "screenRecording": [
                "quality": screenRecordingQualityPreset.rawValue,
                "systemAudio": screenRecordingIncludesSystemAudio,
                "microphone": screenRecordingIncludesMicrophone,
                "cameraBubble": screenRecordingShowsCameraBubble
            ],
            "overlay": [
                "style": overlayStyle.rawValue,
                "islandMotion": islandOverlayMotion,
                "islandReactivity": islandOverlayReactivity,
                "islandShape": islandOverlayShape,
                "islandWidth": islandOverlayWidth,
                "islandHeight": islandOverlayHeight,
                "position": overlayPosition.rawValue,
                "placement": ["x": overlayPlacement.x, "y": overlayPlacement.y],
                "pillEnabled": pillEnabled,
                "pillPosition": pillPosition.rawValue,
                "pillPlacement": ["x": pillPlacement.x, "y": pillPlacement.y],
                "pillShowOnAllScreens": pillShowOnAllScreens,
                "pillExpandsDuringRecording": pillExpandsDuringRecording,
                "notchOverlayEnabled": notchOverlayEnabled
            ],
            "sounds": [
                "start": startSound.rawValue,
                "finish": finishSound.rawValue,
                "pasted": pastedSound.rawValue
            ],
            "appearance": [
                "mode": appearanceMode.rawValue,
                "theme": visualTheme.rawValue,
                "fontSize": fontSize.rawValue,
                "accentColor": accentColor.rawValue
            ],
            "context": [
                "primarySource": primaryContextSource.rawValue,
                "captureDetail": contextCaptureDetail.rawValue
            ],
            "behavior": [
                "returnToOriginAfterPaste": returnToOriginAfterPaste,
                "pressEnterAfterPaste": pressEnterAfterPaste,
                "autoScratchpadOnSelection": autoScratchpadOnSelection
            ],
            "dictationTTLHours": dictationTTLHours,
            "_dumpedAt": ISO8601DateFormatter().string(from: Date())
        ]

        // Write to Application Support for easy access from Talkie's Settings Inspector
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let dir = appSupport.appendingPathComponent("TalkieAgent")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("settings_dump.json")

        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: file)
        }
    }
    #endif

    // MARK: - Persistence
    // Writes to shared storage so Talkie sees changes (though Talkie is the primary owner)

    private func save() {
        let store = storage
        let suiteName = TalkieEnvironment.current.sharedSettingsSuite
        log.debug("LiveSettings.save() to suite: \(suiteName)")
        #if DEBUG
        AgentConsole.info("💾 LiveSettings.save() - mic mode: \(selectedMicrophoneMode.rawValue), uid: \(selectedMicrophoneUID ?? "nil")")
        #endif

        if let data = try? JSONEncoder().encode(hotkey) {
            store.set(data, forKey: AgentSettingsKey.hotkey)
            log.debug("Saved hotkey: \(hotkey.displayString)")
        }
        if let data = try? JSONEncoder().encode(pttHotkey) {
            store.set(data, forKey: AgentSettingsKey.pttHotkey)
        }
        store.set(pttEnabled, forKey: AgentSettingsKey.pttEnabled)
        if let data = try? JSONEncoder().encode(selectionQuickHotkey) {
            store.set(data, forKey: AgentSettingsKey.selectionQuickHotkey)
        }
        store.set(selectedModelId, forKey: AgentSettingsKey.selectedModelId)
        store.set(routingMode == .clipboardOnly ? "clipboardOnly" : "paste", forKey: AgentSettingsKey.routingMode)
        store.set(Int(selectedMicrophoneID), forKey: AgentSettingsKey.selectedMicrophoneID)
        store.set(selectedMicrophoneMode.rawValue, forKey: AgentSettingsKey.selectedMicrophoneMode)
        store.set(selectedMicrophoneUID, forKey: AgentSettingsKey.selectedMicrophoneUID)
        store.set(selectedMicrophoneName, forKey: AgentSettingsKey.selectedMicrophoneName)
        store.set(dictationTTLHours, forKey: AgentSettingsKey.utteranceTTLHours)
        store.set(segmentDuration, forKey: AgentSettingsKey.segmentDuration)
        store.set(screenRecordingQualityPreset.rawValue, forKey: AgentSettingsKey.screenRecordingQuality)
        UserDefaults.standard.set(screenRecordingQualityPreset.rawValue, forKey: AgentSettingsKey.screenRecordingQuality)
        store.set(screenRecordingCountdownSeconds, forKey: AgentSettingsKey.screenRecordingCountdownSeconds)
        UserDefaults.standard.set(screenRecordingCountdownSeconds, forKey: AgentSettingsKey.screenRecordingCountdownSeconds)
        store.set(screenRecordingIncludesSystemAudio, forKey: AgentSettingsKey.screenRecordingIncludesSystemAudio)
        store.set(screenRecordingIncludesMicrophone, forKey: AgentSettingsKey.screenRecordingIncludesMicrophone)
        store.set(screenRecordingShowsCameraBubble, forKey: AgentSettingsKey.screenRecordingShowsCameraBubble)
        store.set(overlayStyle.rawValue, forKey: AgentSettingsKey.overlayStyle)
        store.set(islandOverlayMotion, forKey: AgentSettingsKey.islandOverlayMotion)
        store.set(islandOverlayReactivity, forKey: AgentSettingsKey.islandOverlayReactivity)
        store.set(islandOverlayShape, forKey: AgentSettingsKey.islandOverlayShape)
        store.set(islandOverlayWidth, forKey: AgentSettingsKey.islandOverlayWidth)
        store.set(islandOverlayHeight, forKey: AgentSettingsKey.islandOverlayHeight)
        store.set(overlayPosition.rawValue, forKey: AgentSettingsKey.overlayPosition)
        if let data = try? JSONEncoder().encode(overlayPlacement) {
            store.set(data, forKey: AgentSettingsKey.overlayPlacement)
        }
        store.set(pillEnabled, forKey: AgentSettingsKey.pillEnabled)
        store.set(pillPosition.rawValue, forKey: AgentSettingsKey.pillPosition)
        if let data = try? JSONEncoder().encode(pillPlacement) {
            store.set(data, forKey: AgentSettingsKey.pillPlacement)
        }
        store.set(pillShowOnAllScreens, forKey: AgentSettingsKey.pillShowOnAllScreens)
        store.set(pillExpandsDuringRecording, forKey: AgentSettingsKey.pillExpandsDuringRecording)
        store.set(notchOverlayEnabled, forKey: AgentSettingsKey.notchOverlayEnabled)
        store.set(startSound.rawValue, forKey: AgentSettingsKey.startSound)
        store.set(finishSound.rawValue, forKey: AgentSettingsKey.finishSound)
        store.set(pastedSound.rawValue, forKey: AgentSettingsKey.pastedSound)
        #if DEBUG
        store.set(cancelledSound.rawValue, forKey: AgentSettingsKey.cancelledSound)
        #endif
        store.set(appearanceMode.rawValue, forKey: AgentSettingsKey.appearanceMode)
        store.set(visualTheme.rawValue, forKey: AgentSettingsKey.visualTheme)
        store.set(fontSize.rawValue, forKey: AgentSettingsKey.fontSize)
        store.set(accentColor.rawValue, forKey: AgentSettingsKey.accentColor)
        // glassMode is now a launch arg, not persisted
        store.set(primaryContextSource.rawValue, forKey: AgentSettingsKey.primaryContextSource)
        store.set(contextCaptureDetail.rawValue, forKey: AgentSettingsKey.contextCaptureDetail)
        store.set(returnToOriginAfterPaste, forKey: AgentSettingsKey.returnToOriginAfterPaste)
        store.set(pressEnterAfterPaste, forKey: AgentSettingsKey.pressEnterAfterPaste)
        store.set(autoScratchpadOnSelection, forKey: AgentSettingsKey.autoScratchpadOnSelection)

        // Selection settings
        store.set(selectionEnabled, forKey: AgentSettingsKey.selectionEnabled)
        store.set(selectionDefaultMode.rawValue, forKey: AgentSettingsKey.selectionDefaultMode)
        store.set(selectionShortTextThreshold, forKey: AgentSettingsKey.selectionShortTextThreshold)
        store.set(selectionTTSVoiceId, forKey: AgentSettingsKey.selectionTTSVoiceId)
        store.set(selectionLLMTimeout, forKey: AgentSettingsKey.selectionLLMTimeout)
        store.set(selectionShowFeedbackOverlay, forKey: AgentSettingsKey.selectionShowFeedbackOverlay)
        if let data = try? JSONEncoder().encode(selectionAppOverrides) {
            store.set(data, forKey: AgentSettingsKey.selectionAppOverrides)
        }

        // Force immediate write to disk (important for dev builds that may be killed by Xcode)
        store.synchronize()

        #if DEBUG
        dumpSettingsToFile()
        #endif
    }

    private func withPlacementSynchronization(_ updates: () -> Void) {
        isSynchronizingPlacements = true
        updates()
        isSynchronizingPlacements = false
    }

    private static func decodePlacement(forKey key: String, from store: UserDefaults) -> NormalizedPlacement? {
        guard let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(NormalizedPlacement.self, from: data)
    }

    private static func storedOverlayDouble(
        forKey key: String,
        from store: UserDefaults,
        defaultValue: Double
    ) -> Double {
        guard store.object(forKey: key) != nil else { return defaultValue }
        return min(1, max(0, store.double(forKey: key)))
    }

    private static func storedDimensionDouble(
        forKey key: String,
        from store: UserDefaults,
        defaultValue: Double,
        range: ClosedRange<Double>
    ) -> Double {
        guard store.object(forKey: key) != nil else { return defaultValue }
        return min(range.upperBound, max(range.lowerBound, store.double(forKey: key)))
    }

    // MARK: - Appearance Application

    func applyAppearance() {
        switch appearanceMode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Apply a visual theme preset (updates theme + accent color)
    func applyVisualTheme(_ theme: VisualTheme) {
        self.visualTheme = theme
        self.accentColor = theme.accentColor
        // Optionally also set appearance to suggested mode
        // self.appearanceMode = theme.suggestedAppearance
    }

    /// Effective accent color considering theme defaults
    var effectiveAccentColor: Color {
        if accentColor == .system {
            return visualTheme.accentColor.color
        }
        return accentColor.color
    }
}
