import AppKit
import CoreGraphics
import Foundation
import TalkieKit

// MARK: - Per-Monitor Hover Zone Config

struct HoverZoneConfig: Codable, Equatable {
    var width: Double = 80
    var height: Double = 24
    var paddingX: Double = 10
    var paddingY: Double = 8

    static let defaultExternal = HoverZoneConfig()
}

// MARK: - Notch Settings

/// Single source of truth for all notch/shell settings.
/// Replaces scattered @AppStorage declarations across NotchComposerView,
/// NotchAnimationInspector, and the notch/surface settings screens.
///
/// The declarative config file is the source of truth. Legacy UserDefaults keys
/// remain as compatibility mirrors for older runtime paths.
@MainActor
@Observable
final class NotchSettings {
    static let shared = NotchSettings()

    // MARK: - Shell

    var enabled: Bool = true {
        didSet { persist(\.enabled, value: enabled, legacyKey: Keys.enabled) }
    }

    /// Whether to enable surface on external (non-notch) monitors. Off by default — opt-in only.
    var externalEnabled: Bool = false {
        didSet { persist(\.externalEnabled, value: externalEnabled, legacyKey: Keys.externalEnabled) }
    }

    var shellStyleRaw: String = NotchVirtualDisplayStyle.auto.rawValue {
        didSet { persist(\.shellStyleRaw, value: shellStyleRaw, legacyKey: Keys.shellStyle) }
    }

    var shellStyle: NotchVirtualDisplayStyle {
        get { NotchVirtualDisplayStyle(rawValue: shellStyleRaw) ?? .auto }
        set { shellStyleRaw = newValue.rawValue }
    }

    /// Resolves the shell style for the current display. Physical-notch displays
    /// always render the notch shape; virtual displays honor the user preference.
    func resolvedShellStyle(for notchInfo: NotchInfo) -> NotchVirtualDisplayStyle {
        guard notchInfo.isVirtual else { return .notch }
        switch shellStyle {
        case .auto:
            return .island
        case .island, .notch:
            return shellStyle
        }
    }

    func usesIslandShellShape(for notchInfo: NotchInfo) -> Bool {
        resolvedShellStyle(for: notchInfo) == .island
    }

    /// Applies notch-surface settings authored by TalkieAgent via the shared
    /// suite (see `TalkieNotchBridge`). Only keys that are actually present are
    /// applied, so Talkie's own config isn't clobbered by defaults when the
    /// agent has never written them. Returns true if anything changed.
    @discardableResult
    func applyAgentSharedOverrides() -> Bool {
        let shared = TalkieSharedSettings
        var changed = false

        if let value = shared.object(forKey: AgentSettingsKey.notchSurfaceEnabled) as? Bool, value != enabled {
            enabled = value
            changed = true
        }
        if let value = shared.object(forKey: AgentSettingsKey.notchSurfaceExternalEnabled) as? Bool, value != externalEnabled {
            externalEnabled = value
            changed = true
        }
        if let value = shared.object(forKey: AgentSettingsKey.notchSurfaceAlwaysVisible) as? Bool, value != alwaysVisible {
            alwaysVisible = value
            changed = true
        }
        if let raw = shared.string(forKey: AgentSettingsKey.notchSurfaceShellStyle),
           NotchVirtualDisplayStyle(rawValue: raw) != nil,
           raw != shellStyleRaw {
            shellStyleRaw = raw
            changed = true
        }

        return changed
    }

    func overlayOwnsTrayDiscovery(isOverlayActive: Bool) -> Bool {
        enabled && trayStripEnabled && isOverlayActive
    }

    /// Whether any tray dots are configured (inside or outside). Used by observation tracking.
    var trayDotsActive: Bool { trayStripEnabled && (trayDotsInside || trayDotsOutside) }

    /// Legacy compatibility flag from the old notch lab. The renderer no longer
    /// reads this directly; use `shellStyle` for live shell shape selection.
    var islandVisualStyleEnabled: Bool = false {
        didSet { persist(\.islandVisualStyleEnabled, value: islandVisualStyleEnabled, legacyKey: Keys.islandVisualStyle) }
    }

    /// When true, the overlay panel stays on screen even with no active intent.
    var alwaysVisible: Bool = false {
        didSet { persist(\.alwaysVisible, value: alwaysVisible, legacyKey: Keys.alwaysVisible) }
    }

    /// Overlay background opacity (0 = fully transparent, 1 = fully opaque).
    var overlayOpacity: Double = 1.0 {
        didSet { persist(\.overlayOpacity, value: overlayOpacity, legacyKey: Keys.overlayOpacity) }
    }

    // MARK: - Tray Strip (in-shell dots)

    var trayStripEnabled: Bool = false {
        didSet { persist(\.trayStripEnabled, value: trayStripEnabled, legacyKey: Keys.trayStripEnabled) }
    }

    /// Where to show tray dots: "inside" (in notch body), "outside" (strip below notch), or "both".
    var trayStripPlacement: String = "inside" {
        didSet { persist(\.trayStripPlacement, value: trayStripPlacement, legacyKey: Keys.trayStripPlacement) }
    }

    var trayDotsInside: Bool { trayStripEnabled && (trayStripPlacement == "inside" || trayStripPlacement == "both") }
    var trayDotsOutside: Bool { trayStripEnabled && (trayStripPlacement == "outside" || trayStripPlacement == "both") }

    var trayStripShowDots: Bool = true {
        didSet { persist(\.trayStripShowDots, value: trayStripShowDots, legacyKey: Keys.trayStripShowDots) }
    }

    var trayStripWidth: Double = 50.0 {
        didSet { persist(\.trayStripWidth, value: trayStripWidth, legacyKey: Keys.trayStripWidth) }
    }

    var trayStripHeight: Double = 11.0 {
        didSet { persist(\.trayStripHeight, value: trayStripHeight, legacyKey: Keys.trayStripHeight) }
    }

    var trayStripDotSize: Double = 2.6 {
        didSet { persist(\.trayStripDotSize, value: trayStripDotSize, legacyKey: Keys.trayStripDotSize) }
    }

    var trayStripMaxDots: Int = 5 {
        didSet { persist(\.trayStripMaxDots, value: trayStripMaxDots, legacyKey: Keys.trayStripMaxDots) }
    }

    var trayStripBorderOpacity: Double = 0.24 {
        didSet { persist(\.trayStripBorderOpacity, value: trayStripBorderOpacity, legacyKey: Keys.trayStripBorderOpacity) }
    }

    var trayStripYOffset: Double = 46.0 {
        didSet { persist(\.trayStripYOffset, value: trayStripYOffset, legacyKey: Keys.trayStripYOffset) }
    }

    /// Controls whether the tray preview surface can appear while recording is active.
    /// When off, recording UI stays focused and tray preview remains hidden.
    var trayPreviewWhileRecordingEnabled: Bool = false {
        didSet { persist(\.trayPreviewWhileRecordingEnabled, value: trayPreviewWhileRecordingEnabled, legacyKey: Keys.trayPreviewWhileRecordingEnabled) }
    }

    // MARK: - Hover Zone

    /// Width of the hover trigger zone on external/virtual displays (points).
    var hoverZoneWidthExternal: Double = 80 {
        didSet { persist(\.hoverZoneWidthExternal, value: hoverZoneWidthExternal, legacyKey: Keys.hoverZoneWidthExternal) }
    }

    /// Width of the hover trigger zone on notch Macs (points). Defaults to notch width.
    var hoverZoneWidthNotch: Double = 180 {
        didSet { persist(\.hoverZoneWidthNotch, value: hoverZoneWidthNotch, legacyKey: Keys.hoverZoneWidthNotch) }
    }

    /// Height of the hover trigger zone (points).
    var hoverZoneHeight: Double = 24 {
        didSet { persist(\.hoverZoneHeight, value: hoverZoneHeight, legacyKey: Keys.hoverZoneHeight) }
    }

    /// Extra padding around the zone on each side (X axis).
    var hoverZonePaddingX: Double = 10 {
        didSet { persist(\.hoverZonePaddingX, value: hoverZonePaddingX, legacyKey: Keys.hoverZonePaddingX) }
    }

    /// Extra padding around the zone on each side (Y axis).
    var hoverZonePaddingY: Double = 8 {
        didSet { persist(\.hoverZonePaddingY, value: hoverZonePaddingY, legacyKey: Keys.hoverZonePaddingY) }
    }

    // MARK: - Per-Monitor Hover Zone

    /// Per-monitor hover zone configs keyed by CGDirectDisplayID string.
    /// Only used for external/virtual displays. Laptop always uses full notch width.
    @ObservationIgnored
    private(set) var perMonitorHoverZones: [String: HoverZoneConfig] = [:] {
        didSet {
            guard !isLoading else { return }
            persistPerMonitorHoverZones()
        }
    }

    /// Get the hover zone config for a specific display. Returns the per-monitor
    /// config if one exists, otherwise falls back to the global defaults.
    func hoverZoneConfig(for displayID: CGDirectDisplayID) -> HoverZoneConfig {
        let key = String(displayID)
        if let config = perMonitorHoverZones[key] {
            return config
        }

        return HoverZoneConfig(
            width: hoverZoneWidthExternal,
            height: hoverZoneHeight,
            paddingX: hoverZonePaddingX,
            paddingY: hoverZonePaddingY
        )
    }

    /// Set hover zone config for a specific display.
    func setHoverZoneConfig(_ config: HoverZoneConfig, for displayID: CGDirectDisplayID) {
        let key = String(displayID)
        perMonitorHoverZones[key] = config
    }

    /// Remove per-monitor override (reverts to global defaults).
    func removeHoverZoneConfig(for displayID: CGDirectDisplayID) {
        let key = String(displayID)
        perMonitorHoverZones.removeValue(forKey: key)
    }

    // MARK: - Communication

    var communicationDemoEnabled: Bool = false {
        didSet { persist(\.communicationDemoEnabled, value: communicationDemoEnabled, legacyKey: Keys.communicationDemo) }
    }

    // MARK: - Animation Inspector (DEBUG)

    var inspectorEnabled: Bool = false {
        didSet { persist(\.inspectorEnabled, value: inspectorEnabled, legacyKey: Keys.inspectorEnabled) }
    }

    var inspectorScrubEnabled: Bool = false {
        didSet { persist(\.inspectorScrubEnabled, value: inspectorScrubEnabled, legacyKey: Keys.inspectorScrubEnabled) }
    }

    var inspectorProgress: Double = 0.0 {
        didSet { persist(\.inspectorProgress, value: inspectorProgress, legacyKey: Keys.inspectorProgress) }
    }

    var inspectorExtensionWidthDelta: Double = 0.0 {
        didSet { persist(\.inspectorExtensionWidthDelta, value: inspectorExtensionWidthDelta, legacyKey: Keys.inspectorExtensionWidthDelta) }
    }

    var inspectorExtensionWidthMatch: Double = 1.0 {
        didSet { persist(\.inspectorExtensionWidthMatch, value: inspectorExtensionWidthMatch, legacyKey: Keys.inspectorExtensionWidthMatch) }
    }

    var inspectorExtensionWidthReferenceRaw: String = "full" {
        didSet { persist(\.inspectorExtensionWidthReferenceRaw, value: inspectorExtensionWidthReferenceRaw, legacyKey: Keys.inspectorExtensionWidthReference) }
    }

    var inspectorExtensionYOffset: Double = -7.5 {
        didSet { persist(\.inspectorExtensionYOffset, value: inspectorExtensionYOffset, legacyKey: Keys.inspectorExtensionYOffset) }
    }

    var inspectorExtensionDropDistance: Double = 8.0 {
        didSet { persist(\.inspectorExtensionDropDistance, value: inspectorExtensionDropDistance, legacyKey: Keys.inspectorExtensionDropDistance) }
    }

    var inspectorExpansionStart: Double = 0.24 {
        didSet { persist(\.inspectorExpansionStart, value: inspectorExpansionStart, legacyKey: Keys.inspectorExpansionStart) }
    }

    var inspectorBarAttachStart: Double = 0.06 {
        didSet { persist(\.inspectorBarAttachStart, value: inspectorBarAttachStart, legacyKey: Keys.inspectorBarAttachStart) }
    }

    var inspectorBarAttachDuration: Double = 0.20 {
        didSet { persist(\.inspectorBarAttachDuration, value: inspectorBarAttachDuration, legacyKey: Keys.inspectorBarAttachDuration) }
    }

    var inspectorRecordingExtensionPreviewRaw: String = "live" {
        didSet { persist(\.inspectorRecordingExtensionPreviewRaw, value: inspectorRecordingExtensionPreviewRaw, legacyKey: Keys.inspectorRecordingExtensionPreview) }
    }

    var inspectorPlaybackSpeed: Double = 1.0 {
        didSet { persist(\.inspectorPlaybackSpeed, value: inspectorPlaybackSpeed, legacyKey: Keys.inspectorPlaybackSpeed) }
    }

    // MARK: - Debug

    var aggressiveDebugLogging: Bool = false {
        didSet { persist(\.aggressiveDebugLogging, value: aggressiveDebugLogging, legacyKey: Keys.aggressiveDebugLogging) }
    }

    // MARK: - Init

    @ObservationIgnored
    private var isLoading = true

    private init() {
        let config = TalkieSettingsConfigurationStore.shared.configuration.notch

        enabled = config.enabled
        externalEnabled = config.externalEnabled
        shellStyleRaw = config.shellStyleRaw
        islandVisualStyleEnabled = config.islandVisualStyleEnabled
        alwaysVisible = config.alwaysVisible
        overlayOpacity = config.overlayOpacity
        trayStripEnabled = config.trayStripEnabled
        trayStripPlacement = config.trayStripPlacement
        trayStripShowDots = config.trayStripShowDots
        trayStripWidth = config.trayStripWidth
        trayStripHeight = config.trayStripHeight
        trayStripDotSize = config.trayStripDotSize
        trayStripMaxDots = config.trayStripMaxDots
        trayStripBorderOpacity = config.trayStripBorderOpacity
        trayStripYOffset = config.trayStripYOffset
        trayPreviewWhileRecordingEnabled = config.trayPreviewWhileRecordingEnabled
        hoverZoneWidthExternal = config.hoverZoneWidthExternal
        hoverZoneWidthNotch = config.hoverZoneWidthNotch
        hoverZoneHeight = config.hoverZoneHeight
        hoverZonePaddingX = config.hoverZonePaddingX
        hoverZonePaddingY = config.hoverZonePaddingY
        perMonitorHoverZones = config.perMonitorHoverZones
        communicationDemoEnabled = config.communicationDemoEnabled
        inspectorEnabled = config.inspectorEnabled
        inspectorScrubEnabled = config.inspectorScrubEnabled
        inspectorProgress = config.inspectorProgress
        inspectorExtensionWidthDelta = config.inspectorExtensionWidthDelta
        inspectorExtensionWidthMatch = config.inspectorExtensionWidthMatch
        inspectorExtensionWidthReferenceRaw = config.inspectorExtensionWidthReferenceRaw
        inspectorExtensionYOffset = config.inspectorExtensionYOffset
        inspectorExtensionDropDistance = config.inspectorExtensionDropDistance
        inspectorExpansionStart = config.inspectorExpansionStart
        inspectorBarAttachStart = config.inspectorBarAttachStart
        inspectorBarAttachDuration = config.inspectorBarAttachDuration
        inspectorRecordingExtensionPreviewRaw = config.inspectorRecordingExtensionPreviewRaw
        inspectorPlaybackSpeed = config.inspectorPlaybackSpeed
        aggressiveDebugLogging = config.aggressiveDebugLogging

        isLoading = false
    }

    private func persist<Value>(
        _ keyPath: WritableKeyPath<TalkieSettingsConfiguration.Notch, Value>,
        value: Value,
        legacyKey: String
    ) {
        guard !isLoading else { return }
        TalkieSettingsConfigurationStore.shared.update { configuration in
            configuration.notch[keyPath: keyPath] = value
        }
        UserDefaults.standard.set(value, forKey: legacyKey)
    }

    private func persistPerMonitorHoverZones() {
        TalkieSettingsConfigurationStore.shared.update { configuration in
            configuration.notch.perMonitorHoverZones = perMonitorHoverZones
        }

        if let data = try? JSONEncoder().encode(perMonitorHoverZones) {
            UserDefaults.standard.set(data, forKey: Keys.perMonitorHoverZones)
        }
    }

    // MARK: - Legacy Keys

    /// Maps to the same UserDefaults keys that older `@AppStorage` paths used.
    /// Single declaration point — no string literals elsewhere.
    private enum Keys {
        // Shell
        static let enabled = "notchCapabilityEnabled"
        static let externalEnabled = "notchExternalMonitorEnabled"
        static let shellStyle = "notchVirtualDisplayStyle"
        static let islandVisualStyle = "notchIslandVisualStyleEnabled"
        static let alwaysVisible = "notchAlwaysVisible"
        static let overlayOpacity = "notchOverlayOpacity"

        // Tray Strip
        static let trayStripEnabled = "notchTrayBarEnabled"
        static let trayStripPlacement = "notchTrayStripPlacement"
        static let trayStripShowDots = "notchTrayIndicatorShowDots"
        static let trayStripWidth = "notchTrayIndicatorWidth"
        static let trayStripHeight = "notchTrayIndicatorHeight"
        static let trayStripDotSize = "notchTrayIndicatorDotSize"
        static let trayStripMaxDots = "notchTrayIndicatorMaxDots"
        static let trayStripBorderOpacity = "notchTrayIndicatorBorderOpacity"
        static let trayStripYOffset = "notchTrayIndicatorYOffset"
        static let trayPreviewWhileRecordingEnabled = "notchTrayPreviewWhileRecordingEnabled"

        // Hover Zone
        static let hoverZoneWidthExternal = "notchHoverZoneWidthExternal"
        static let hoverZoneWidthNotch = "notchHoverZoneWidthNotch"
        static let hoverZoneHeight = "notchHoverZoneHeight"
        static let hoverZonePaddingX = "notchHoverZonePaddingX"
        static let hoverZonePaddingY = "notchHoverZonePaddingY"
        static let perMonitorHoverZones = "notchPerMonitorHoverZones"

        // Communication
        static let communicationDemo = "notchCommunicationDemoEnabled"

        // Inspector
        static let inspectorEnabled = "notchAnimationInspectorEnabled"
        static let inspectorScrubEnabled = "notchAnimationInspectorScrubEnabled"
        static let inspectorProgress = "notchAnimationInspectorProgress"
        static let inspectorExtensionWidthDelta = "notchAnimationInspectorExtensionWidthDelta"
        static let inspectorExtensionWidthMatch = "notchAnimationInspectorExtensionWidthMatch"
        static let inspectorExtensionWidthReference = "notchAnimationInspectorExtensionWidthReference"
        static let inspectorExtensionYOffset = "notchAnimationInspectorExtensionYOffset"
        static let inspectorExtensionDropDistance = "notchAnimationInspectorExtensionDropDistance"
        static let inspectorExpansionStart = "notchAnimationInspectorExpansionStart"
        static let inspectorBarAttachStart = "notchAnimationInspectorBarAttachStart"
        static let inspectorBarAttachDuration = "notchAnimationInspectorBarAttachDuration"
        static let inspectorRecordingExtensionPreview = "notchAnimationInspectorRecordingExtensionPreview"
        static let inspectorPlaybackSpeed = "notchAnimationInspectorPlaybackSpeed"

        // Debug
        static let aggressiveDebugLogging = "notchAggressiveDebugLogging"
    }
}
