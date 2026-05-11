import Foundation

// MARK: - Tray Settings

/// Single source of truth for all tray settings (external badge, viewer, shelf).
/// Replaces scattered @AppStorage declarations across TrayBadge,
/// TrayViewer, and NotchSettingsView.
///
/// The declarative config file is the source of truth. Legacy UserDefaults keys
/// remain as compatibility mirrors for older runtime paths.
@MainActor
@Observable
final class TraySettings {
    static let shared = TraySettings()

    // MARK: - External Badge

    var externalBadgeEnabled: Bool = false {
        didSet { persist(\.externalBadgeEnabled, value: externalBadgeEnabled, legacyKey: Keys.externalBadgeEnabled) }
    }

    var badgeModeRaw: String = TrayBadgeMode.pill.rawValue {
        didSet { persist(\.badgeModeRaw, value: badgeModeRaw, legacyKey: Keys.badgeMode) }
    }

    var badgeMode: TrayBadgeMode {
        get { TrayBadgeMode(rawValue: badgeModeRaw) ?? .pill }
        set { badgeModeRaw = newValue.rawValue }
    }

    var badgeFollowNotchWidth: Bool = false {
        didSet { persist(\.badgeFollowNotchWidth, value: badgeFollowNotchWidth, legacyKey: Keys.badgeFollowNotchWidth) }
    }

    var badgeWidth: Double = 220.0 {
        didSet { persist(\.badgeWidth, value: badgeWidth, legacyKey: Keys.badgeWidth) }
    }

    var badgeHeight: Double = 6.0 {
        didSet { persist(\.badgeHeight, value: badgeHeight, legacyKey: Keys.badgeHeight) }
    }

    var badgeDotSize: Double = 2.0 {
        didSet { persist(\.badgeDotSize, value: badgeDotSize, legacyKey: Keys.badgeDotSize) }
    }

    var badgeMaxDots: Int = 5 {
        didSet { persist(\.badgeMaxDots, value: badgeMaxDots, legacyKey: Keys.badgeMaxDots) }
    }

    var badgeYOffset: Double = 6.0 {
        didSet { persist(\.badgeYOffset, value: badgeYOffset, legacyKey: Keys.badgeYOffset) }
    }

    var badgeHoverTargetHeight: Double = 6.0 {
        didSet { persist(\.badgeHoverTargetHeight, value: badgeHoverTargetHeight, legacyKey: Keys.badgeHoverTargetHeight) }
    }

    // MARK: - Viewer

    var viewerModeRaw: String = TrayViewMode.gallery.rawValue {
        didSet { persist(\.viewerModeRaw, value: viewerModeRaw, legacyKey: Keys.viewerMode) }
    }

    var viewerMode: TrayViewMode {
        get { TrayViewMode(rawValue: viewerModeRaw) ?? .gallery }
        set { viewerModeRaw = newValue.rawValue }
    }

    // MARK: - Shelf

    var shelfHeight: Double = 130.0 {
        didSet { persist(\.shelfHeight, value: shelfHeight, legacyKey: Keys.shelfHeight) }
    }

    var shelfHotkey: String = "" {
        didSet { persist(\.shelfHotkey, value: shelfHotkey, legacyKey: Keys.shelfHotkey) }
    }

    // MARK: - Init

    @ObservationIgnored
    private var isLoading = true

    private init() {
        let config = TalkieSettingsConfigurationStore.shared.configuration.tray

        externalBadgeEnabled = config.externalBadgeEnabled
        badgeModeRaw = config.badgeModeRaw
        badgeFollowNotchWidth = config.badgeFollowNotchWidth
        badgeWidth = config.badgeWidth
        badgeHeight = config.badgeHeight
        badgeDotSize = config.badgeDotSize
        badgeMaxDots = config.badgeMaxDots
        badgeYOffset = config.badgeYOffset
        badgeHoverTargetHeight = config.badgeHoverTargetHeight
        viewerModeRaw = config.viewerModeRaw
        shelfHeight = config.shelfHeight
        shelfHotkey = config.shelfHotkey

        isLoading = false
    }

    private func persist<Value>(
        _ keyPath: WritableKeyPath<TalkieSettingsConfiguration.Tray, Value>,
        value: Value,
        legacyKey: String
    ) {
        guard !isLoading else { return }
        TalkieSettingsConfigurationStore.shared.update { configuration in
            configuration.tray[keyPath: keyPath] = value
        }
        UserDefaults.standard.set(value, forKey: legacyKey)
    }

    // MARK: - Legacy Keys

    private enum Keys {
        // External Badge
        static let externalBadgeEnabled = "externalTrayBadgeEnabled"
        static let badgeMode = "trayBadgeMode"
        static let badgeFollowNotchWidth = "trayBadgeStripFollowNotchWidth"
        static let badgeWidth = "trayBadgeStripWidth"
        static let badgeHeight = "trayBadgeStripHeight"
        static let badgeDotSize = "trayBadgeStripDotSize"
        static let badgeMaxDots = "trayBadgeStripMaxDots"
        static let badgeYOffset = "trayBadgeStripYOffset"
        static let badgeHoverTargetHeight = "trayBadgeStripHoverTargetHeight"

        // Viewer
        static let viewerMode = "trayViewMode"

        // Shelf
        static let shelfHeight = "trayShelfHeight"
        static let shelfHotkey = "trayShelfHotkey"
    }
}
