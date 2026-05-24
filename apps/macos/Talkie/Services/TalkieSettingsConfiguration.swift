//
//  TalkieSettingsConfiguration.swift
//  Talkie macOS
//
//  File-backed declarative settings for agent-manageable configuration.
//

import Foundation
import TalkieKit

struct TalkieSettingsConfiguration: Codable {
    struct Onboarding: Codable {
        var firstLaunchDate: Date?
        var onboardingCardsDismissed: Bool

        init(
            firstLaunchDate: Date? = nil,
            onboardingCardsDismissed: Bool = false
        ) {
            self.firstLaunchDate = firstLaunchDate
            self.onboardingCardsDismissed = onboardingCardsDismissed
        }
    }

    struct Sync: Codable {
        var syncOnLaunch: Bool
        var minimumSyncInterval: TimeInterval
        var iCloudSyncEnabled: Bool
        var syncIntervalMinutes: Int

        init(
            syncOnLaunch: Bool = false,
            minimumSyncInterval: TimeInterval = 300,
            iCloudSyncEnabled: Bool = false,
            syncIntervalMinutes: Int = 10
        ) {
            self.syncOnLaunch = syncOnLaunch
            self.minimumSyncInterval = minimumSyncInterval
            self.iCloudSyncEnabled = iCloudSyncEnabled
            self.syncIntervalMinutes = syncIntervalMinutes
        }
    }

    struct RemoteEngine: Codable {
        var enabled: Bool
        var host: String
        var port: Int

        init(
            enabled: Bool = false,
            host: String = "",
            port: Int = 19821
        ) {
            self.enabled = enabled
            self.host = host
            self.port = port
        }
    }

    struct Appearance: Codable {
        var mode: AppearanceMode
        var accentColor: AccentColorOption
        var currentTheme: ThemePreset
        var enableGlassEffects: Bool
        var uiFontStyle: FontStyleOption
        var contentFontStyle: FontStyleOption
        var uiFontSize: FontSizeOption
        var contentFontSize: FontSizeOption
        var consoleTerminalTheme: ConsoleTerminalThemeOption
        var consoleTerminalFont: ConsoleTerminalFontOption
        var consoleTerminalFontSize: ConsoleTerminalFontSizeOption
        var uiAllCaps: Bool
        var detailLevel: DetailLevel
        var settingsAudience: SettingsAudience

        init(
            mode: AppearanceMode = .system,
            accentColor: AccentColorOption = .system,
            currentTheme: ThemePreset = .technical,
            enableGlassEffects: Bool = false,
            uiFontStyle: FontStyleOption = .system,
            contentFontStyle: FontStyleOption = .system,
            uiFontSize: FontSizeOption = .medium,
            contentFontSize: FontSizeOption = .medium,
            consoleTerminalTheme: ConsoleTerminalThemeOption = .graphite,
            consoleTerminalFont: ConsoleTerminalFontOption = .recommendedDefault,
            consoleTerminalFontSize: ConsoleTerminalFontSizeOption = .regular,
            uiAllCaps: Bool = false,
            detailLevel: DetailLevel = .standard,
            settingsAudience: SettingsAudience = .simple
        ) {
            self.mode = mode
            self.accentColor = accentColor
            self.currentTheme = currentTheme
            self.enableGlassEffects = enableGlassEffects
            self.uiFontStyle = uiFontStyle
            self.contentFontStyle = contentFontStyle
            self.uiFontSize = uiFontSize
            self.contentFontSize = contentFontSize
            self.consoleTerminalTheme = consoleTerminalTheme
            self.consoleTerminalFont = consoleTerminalFont
            self.consoleTerminalFontSize = consoleTerminalFontSize
            self.uiAllCaps = uiAllCaps
            self.detailLevel = detailLevel
            self.settingsAudience = settingsAudience
        }
    }

    struct Home: Codable {
        var layout: HomeLayoutConfig

        init(layout: HomeLayoutConfig = .default) {
            self.layout = layout
        }
    }

    struct Compose: Codable {
        var providerId: String?
        var modelId: String?
        var assistantPrompt: String

        init(
            providerId: String? = nil,
            modelId: String? = nil,
            assistantPrompt: String = SettingsManager.defaultComposeAssistantPrompt
        ) {
            self.providerId = providerId
            self.modelId = modelId
            self.assistantPrompt = assistantPrompt
        }
    }

    struct LocalFiles: Codable {
        var saveTranscriptsLocally: Bool
        var transcriptsFolderPath: String
        var saveAudioLocally: Bool
        var audioFolderPath: String

        init(
            saveTranscriptsLocally: Bool = false,
            transcriptsFolderPath: String = SettingsManager.defaultTranscriptsFolderPath,
            saveAudioLocally: Bool = false,
            audioFolderPath: String = SettingsManager.defaultAudioFolderPath
        ) {
            self.saveTranscriptsLocally = saveTranscriptsLocally
            self.transcriptsFolderPath = transcriptsFolderPath
            self.saveAudioLocally = saveAudioLocally
            self.audioFolderPath = audioFolderPath
        }
    }

    struct Workflow: Codable {
        var autoRunEnabled: Bool

        init(autoRunEnabled: Bool = false) {
            self.autoRunEnabled = autoRunEnabled
        }
    }

    struct Bridge: Codable {
        var autoStartBridge: Bool
        var talkieServerEnabled: Bool
        var talkieGatewayEnabled: Bool
        var talkieClaudeSessionsEnabled: Bool
        var extensionsFrameworkEnabled: Bool
        var shortcutBoardEnabled: Bool
        var companionShortcutModeEnabled: Bool
        var companionShortcutSlots: [String]

        init(
            autoStartBridge: Bool = true,
            talkieServerEnabled: Bool = true,
            talkieGatewayEnabled: Bool = false,
            talkieClaudeSessionsEnabled: Bool = false,
            extensionsFrameworkEnabled: Bool = false,
            shortcutBoardEnabled: Bool = false,
            companionShortcutModeEnabled: Bool = false,
            companionShortcutSlots: [String] = TalkieSettingsConfiguration.defaultLegacyShortcutSlots
        ) {
            self.autoStartBridge = autoStartBridge
            self.talkieServerEnabled = talkieServerEnabled
            self.talkieGatewayEnabled = talkieGatewayEnabled
            self.talkieClaudeSessionsEnabled = talkieClaudeSessionsEnabled
            self.extensionsFrameworkEnabled = extensionsFrameworkEnabled
            self.shortcutBoardEnabled = shortcutBoardEnabled
            self.companionShortcutModeEnabled = companionShortcutModeEnabled
            self.companionShortcutSlots = companionShortcutSlots
        }

        private enum CodingKeys: String, CodingKey {
            case autoStartBridge
            case talkieServerEnabled
            case talkieGatewayEnabled
            case talkieClaudeSessionsEnabled
            case extensionsFrameworkEnabled
            case shortcutBoardEnabled
            case companionShortcutModeEnabled
            case companionShortcutSlots
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            autoStartBridge = try container.decodeIfPresent(Bool.self, forKey: .autoStartBridge) ?? true
            talkieServerEnabled = try container.decodeIfPresent(Bool.self, forKey: .talkieServerEnabled) ?? true
            talkieGatewayEnabled = try container.decodeIfPresent(Bool.self, forKey: .talkieGatewayEnabled) ?? false
            talkieClaudeSessionsEnabled = try container.decodeIfPresent(Bool.self, forKey: .talkieClaudeSessionsEnabled) ?? false
            extensionsFrameworkEnabled = try container.decodeIfPresent(Bool.self, forKey: .extensionsFrameworkEnabled) ?? false
            let legacyShortcutModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .companionShortcutModeEnabled) ?? false
            shortcutBoardEnabled = try container.decodeIfPresent(Bool.self, forKey: .shortcutBoardEnabled) ?? legacyShortcutModeEnabled
            companionShortcutModeEnabled = legacyShortcutModeEnabled || shortcutBoardEnabled
            companionShortcutSlots = try container.decodeIfPresent([String].self, forKey: .companionShortcutSlots)
                ?? TalkieSettingsConfiguration.defaultLegacyShortcutSlots
        }
    }

    struct Devices: Codable {
        enum Platform: String, Codable {
            case ipad
            case iphone
        }

        struct Defaults: Codable {
            var shortcutBoard: ShortcutBoard?

            init(shortcutBoard: ShortcutBoard? = nil) {
                self.shortcutBoard = shortcutBoard
            }
        }

        struct DeviceClassSettings: Codable {
            var shortcutBoardOverride: ShortcutBoardOverride?

            init(shortcutBoardOverride: ShortcutBoardOverride? = nil) {
                self.shortcutBoardOverride = shortcutBoardOverride
            }
        }

        struct Classes: Codable {
            var ipad: DeviceClassSettings
            var iphone: DeviceClassSettings

            init(
                ipad: DeviceClassSettings = .init(),
                iphone: DeviceClassSettings = .init()
            ) {
                self.ipad = ipad
                self.iphone = iphone
            }

            func settings(for platform: Platform) -> DeviceClassSettings {
                switch platform {
                case .ipad:
                    return ipad
                case .iphone:
                    return iphone
                }
            }
        }

        struct DeviceOverride: Codable {
            var displayName: String?
            var platform: Platform?
            var shortcutBoardOverride: ShortcutBoardOverride?

            init(
                displayName: String? = nil,
                platform: Platform? = nil,
                shortcutBoardOverride: ShortcutBoardOverride? = nil
            ) {
                self.displayName = displayName
                self.platform = platform
                self.shortcutBoardOverride = shortcutBoardOverride
            }
        }

        var defaults: Defaults
        var classes: Classes
        var overrides: [String: DeviceOverride]
        var publishRevision: Int
        var lastPublishedAt: String?

        init(
            defaults: Defaults = .init(),
            classes: Classes = .init(),
            overrides: [String: DeviceOverride] = [:],
            publishRevision: Int = 0,
            lastPublishedAt: String? = nil
        ) {
            self.defaults = defaults
            self.classes = classes
            self.overrides = overrides
            self.publishRevision = publishRevision
            self.lastPublishedAt = lastPublishedAt
        }

        private enum CodingKeys: String, CodingKey {
            case defaults
            case classes
            case overrides
            case publishRevision
            case lastPublishedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            defaults = try container.decodeIfPresent(Defaults.self, forKey: .defaults) ?? .init()
            classes = try container.decodeIfPresent(Classes.self, forKey: .classes) ?? .init()
            overrides = try container.decodeIfPresent([String: DeviceOverride].self, forKey: .overrides) ?? [:]
            publishRevision = try container.decodeIfPresent(Int.self, forKey: .publishRevision) ?? 0
            lastPublishedAt = try container.decodeIfPresent(String.self, forKey: .lastPublishedAt)
        }
    }

    struct ShortcutBoard: Codable {
        struct Space: Codable {
            struct Layout: Codable {
                var rows: Int
                var columns: Int

                init(rows: Int = 4, columns: Int = 4) {
                    self.rows = rows
                    self.columns = columns
                }
            }

            struct Tile: Codable {
                struct Action: Codable {
                    var target: String
                    var kind: String
                    var arguments: [String: String]

                    init(
                        target: String,
                        kind: String,
                        arguments: [String: String] = [:]
                    ) {
                        self.target = target
                        self.kind = kind
                        self.arguments = arguments
                    }
                }

                struct LiveUI: Codable {
                    var showsTimer: Bool
                    var showsWaveform: Bool
                    var showsStopControl: Bool

                    init(
                        showsTimer: Bool = false,
                        showsWaveform: Bool = false,
                        showsStopControl: Bool = false
                    ) {
                        self.showsTimer = showsTimer
                        self.showsWaveform = showsWaveform
                        self.showsStopControl = showsStopControl
                    }
                }

                var id: String
                var title: String
                var subtitle: String?
                var icon: String
                var accentColor: String?
                var type: String
                var legacySlotID: String?
                var action: Action
                var liveUI: LiveUI?

                init(
                    id: String,
                    title: String,
                    subtitle: String? = nil,
                    icon: String,
                    accentColor: String? = nil,
                    type: String,
                    legacySlotID: String? = nil,
                    action: Action,
                    liveUI: LiveUI? = nil
                ) {
                    self.id = id
                    self.title = title
                    self.subtitle = subtitle
                    self.icon = icon
                    self.accentColor = accentColor
                    self.type = type
                    self.legacySlotID = legacySlotID
                    self.action = action
                    self.liveUI = liveUI
                }
            }

            var id: String
            var title: String
            var layout: Layout
            var tiles: [Tile]

            init(
                id: String,
                title: String,
                layout: Layout = .init(),
                tiles: [Tile]
            ) {
                self.id = id
                self.title = title
                self.layout = layout
                self.tiles = tiles
            }
        }

        var version: Int
        var spaces: [Space]

        init(version: Int = 1, spaces: [Space]) {
            self.version = version
            self.spaces = spaces
        }
    }

    struct ShortcutBoardOverride: Codable {
        struct SpaceOverride: Codable {
            struct TileOverride: Codable {
                var id: String
                var title: String?
                var subtitle: String?
                var icon: String?
                var accentColor: String?
                var type: String?
                var legacySlotID: String?
                var action: ShortcutBoard.Space.Tile.Action?
                var liveUI: ShortcutBoard.Space.Tile.LiveUI?

                init(
                    id: String,
                    title: String? = nil,
                    subtitle: String? = nil,
                    icon: String? = nil,
                    accentColor: String? = nil,
                    type: String? = nil,
                    legacySlotID: String? = nil,
                    action: ShortcutBoard.Space.Tile.Action? = nil,
                    liveUI: ShortcutBoard.Space.Tile.LiveUI? = nil
                ) {
                    self.id = id
                    self.title = title
                    self.subtitle = subtitle
                    self.icon = icon
                    self.accentColor = accentColor
                    self.type = type
                    self.legacySlotID = legacySlotID
                    self.action = action
                    self.liveUI = liveUI
                }
            }

            var id: String
            var title: String?
            var tileOrder: [String]?
            var tileOverrides: [TileOverride]

            init(
                id: String,
                title: String? = nil,
                tileOrder: [String]? = nil,
                tileOverrides: [TileOverride] = []
            ) {
                self.id = id
                self.title = title
                self.tileOrder = tileOrder
                self.tileOverrides = tileOverrides
            }
        }

        var spaceOverrides: [SpaceOverride]

        init(spaceOverrides: [SpaceOverride] = []) {
            self.spaceOverrides = spaceOverrides
        }
    }

    struct Interstitial: Codable {
        var askOnDismiss: Bool

        init(askOnDismiss: Bool = true) {
            self.askOnDismiss = askOnDismiss
        }
    }

    struct Models: Codable {
        var llmCostTier: LLMCostTier
        var selectedModel: String
        var liveTranscriptionModelId: String

        init(
            llmCostTier: LLMCostTier = .budget,
            selectedModel: String = LLMConfig.shared.defaultModel(for: "gemini") ?? "",
            liveTranscriptionModelId: String = TalkieDefaults.dictationModelId
        ) {
            self.llmCostTier = llmCostTier
            self.selectedModel = selectedModel
            self.liveTranscriptionModelId = liveTranscriptionModelId
        }
    }

    struct Audio: Codable {
        var playbackVolume: Float
        var selectedTTSVoiceId: String
        var jsonExportSchedule: JSONExportSchedule

        init(
            playbackVolume: Float = 1.0,
            selectedTTSVoiceId: String = TalkieSettingsConfiguration.defaultTTSVoiceId(),
            jsonExportSchedule: JSONExportSchedule = .dailyShallowWeeklyDeep
        ) {
            self.playbackVolume = playbackVolume
            self.selectedTTSVoiceId = selectedTTSVoiceId
            self.jsonExportSchedule = jsonExportSchedule
        }
    }

    struct Capture: Codable {
        var hudPosition: CaptureHUDPosition
        var screenshotLauncher: ScreenshotLauncher
        var screenshotCapturePreset: ScreenshotCapturePreset
        var screenRecordingQuality: ScreenRecordingQualityPreset

        init(
            hudPosition: CaptureHUDPosition = .cursor,
            screenshotLauncher: ScreenshotLauncher = .builtin,
            screenshotCapturePreset: ScreenshotCapturePreset = .agent,
            screenRecordingQuality: ScreenRecordingQualityPreset = .agent
        ) {
            self.hudPosition = hudPosition
            self.screenshotLauncher = screenshotLauncher
            self.screenshotCapturePreset = screenshotCapturePreset
            self.screenRecordingQuality = screenRecordingQuality
        }

        enum CodingKeys: String, CodingKey {
            case hudPosition
            case screenshotLauncher
            case screenshotCapturePreset
            case screenRecordingQuality
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hudPosition = try container.decodeIfPresent(CaptureHUDPosition.self, forKey: .hudPosition) ?? .cursor
            screenshotLauncher = try container.decodeIfPresent(ScreenshotLauncher.self, forKey: .screenshotLauncher) ?? .builtin
            screenshotCapturePreset = try container.decodeIfPresent(ScreenshotCapturePreset.self, forKey: .screenshotCapturePreset) ?? .agent
            screenRecordingQuality = try container.decodeIfPresent(ScreenRecordingQualityPreset.self, forKey: .screenRecordingQuality) ?? .agent
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(hudPosition, forKey: .hudPosition)
            try container.encode(screenshotLauncher, forKey: .screenshotLauncher)
            try container.encode(screenshotCapturePreset, forKey: .screenshotCapturePreset)
            try container.encode(screenRecordingQuality, forKey: .screenRecordingQuality)
        }
    }

    struct Camera: Codable {
        var bubbleSize: CameraBubbleSize
        var quality: CameraQuality
        var videoCodec: CameraVideoCodec
        var deviceID: String
        var maxClipDuration: Double

        init(
            bubbleSize: CameraBubbleSize = .standard,
            quality: CameraQuality = .standard,
            videoCodec: CameraVideoCodec = .h264,
            deviceID: String = "",
            maxClipDuration: Double = 60
        ) {
            self.bubbleSize = bubbleSize
            self.quality = quality
            self.videoCodec = videoCodec
            self.deviceID = deviceID
            self.maxClipDuration = max(15, maxClipDuration)
        }
    }

    struct UI: Codable {
        var settingsSidebarIconsOnly: Bool

        init(settingsSidebarIconsOnly: Bool = false) {
            self.settingsSidebarIconsOnly = settingsSidebarIconsOnly
        }
    }

    struct Notch: Codable {
        var enabled: Bool
        var externalEnabled: Bool
        var shellStyleRaw: String
        var islandVisualStyleEnabled: Bool
        var alwaysVisible: Bool
        var overlayOpacity: Double
        var trayStripEnabled: Bool
        var trayStripPlacement: String
        var trayStripShowDots: Bool
        var trayStripWidth: Double
        var trayStripHeight: Double
        var trayStripDotSize: Double
        var trayStripMaxDots: Int
        var trayStripBorderOpacity: Double
        var trayStripYOffset: Double
        var trayPreviewWhileRecordingEnabled: Bool
        var hoverZoneWidthExternal: Double
        var hoverZoneWidthNotch: Double
        var hoverZoneHeight: Double
        var hoverZonePaddingX: Double
        var hoverZonePaddingY: Double
        var perMonitorHoverZones: [String: HoverZoneConfig]
        var communicationDemoEnabled: Bool
        var inspectorEnabled: Bool
        var inspectorScrubEnabled: Bool
        var inspectorProgress: Double
        var inspectorExtensionWidthDelta: Double
        var inspectorExtensionWidthMatch: Double
        var inspectorExtensionWidthReferenceRaw: String
        var inspectorExtensionYOffset: Double
        var inspectorExtensionDropDistance: Double
        var inspectorExpansionStart: Double
        var inspectorBarAttachStart: Double
        var inspectorBarAttachDuration: Double
        var inspectorRecordingExtensionPreviewRaw: String
        var inspectorPlaybackSpeed: Double
        var aggressiveDebugLogging: Bool

        init(
            enabled: Bool = true,
            externalEnabled: Bool = false,
            shellStyleRaw: String = NotchVirtualDisplayStyle.auto.rawValue,
            islandVisualStyleEnabled: Bool = false,
            alwaysVisible: Bool = false,
            overlayOpacity: Double = 1.0,
            trayStripEnabled: Bool = false,
            trayStripPlacement: String = "inside",
            trayStripShowDots: Bool = true,
            trayStripWidth: Double = 50.0,
            trayStripHeight: Double = 11.0,
            trayStripDotSize: Double = 2.6,
            trayStripMaxDots: Int = 5,
            trayStripBorderOpacity: Double = 0.24,
            trayStripYOffset: Double = 46.0,
            trayPreviewWhileRecordingEnabled: Bool = false,
            hoverZoneWidthExternal: Double = 80,
            hoverZoneWidthNotch: Double = 180,
            hoverZoneHeight: Double = 24,
            hoverZonePaddingX: Double = 10,
            hoverZonePaddingY: Double = 8,
            perMonitorHoverZones: [String: HoverZoneConfig] = [:],
            communicationDemoEnabled: Bool = false,
            inspectorEnabled: Bool = false,
            inspectorScrubEnabled: Bool = false,
            inspectorProgress: Double = 0.0,
            inspectorExtensionWidthDelta: Double = 0.0,
            inspectorExtensionWidthMatch: Double = 1.0,
            inspectorExtensionWidthReferenceRaw: String = "full",
            inspectorExtensionYOffset: Double = -7.5,
            inspectorExtensionDropDistance: Double = 8.0,
            inspectorExpansionStart: Double = 0.24,
            inspectorBarAttachStart: Double = 0.06,
            inspectorBarAttachDuration: Double = 0.20,
            inspectorRecordingExtensionPreviewRaw: String = "live",
            inspectorPlaybackSpeed: Double = 1.0,
            aggressiveDebugLogging: Bool = false
        ) {
            self.enabled = enabled
            self.externalEnabled = externalEnabled
            self.shellStyleRaw = shellStyleRaw
            self.islandVisualStyleEnabled = islandVisualStyleEnabled
            self.alwaysVisible = alwaysVisible
            self.overlayOpacity = overlayOpacity
            self.trayStripEnabled = trayStripEnabled
            self.trayStripPlacement = trayStripPlacement
            self.trayStripShowDots = trayStripShowDots
            self.trayStripWidth = trayStripWidth
            self.trayStripHeight = trayStripHeight
            self.trayStripDotSize = trayStripDotSize
            self.trayStripMaxDots = trayStripMaxDots
            self.trayStripBorderOpacity = trayStripBorderOpacity
            self.trayStripYOffset = trayStripYOffset
            self.trayPreviewWhileRecordingEnabled = trayPreviewWhileRecordingEnabled
            self.hoverZoneWidthExternal = hoverZoneWidthExternal
            self.hoverZoneWidthNotch = hoverZoneWidthNotch
            self.hoverZoneHeight = hoverZoneHeight
            self.hoverZonePaddingX = hoverZonePaddingX
            self.hoverZonePaddingY = hoverZonePaddingY
            self.perMonitorHoverZones = perMonitorHoverZones
            self.communicationDemoEnabled = communicationDemoEnabled
            self.inspectorEnabled = inspectorEnabled
            self.inspectorScrubEnabled = inspectorScrubEnabled
            self.inspectorProgress = inspectorProgress
            self.inspectorExtensionWidthDelta = inspectorExtensionWidthDelta
            self.inspectorExtensionWidthMatch = inspectorExtensionWidthMatch
            self.inspectorExtensionWidthReferenceRaw = inspectorExtensionWidthReferenceRaw
            self.inspectorExtensionYOffset = inspectorExtensionYOffset
            self.inspectorExtensionDropDistance = inspectorExtensionDropDistance
            self.inspectorExpansionStart = inspectorExpansionStart
            self.inspectorBarAttachStart = inspectorBarAttachStart
            self.inspectorBarAttachDuration = inspectorBarAttachDuration
            self.inspectorRecordingExtensionPreviewRaw = inspectorRecordingExtensionPreviewRaw
            self.inspectorPlaybackSpeed = inspectorPlaybackSpeed
            self.aggressiveDebugLogging = aggressiveDebugLogging
        }
    }

    struct Tray: Codable {
        var externalBadgeEnabled: Bool
        var badgeModeRaw: String
        var badgeFollowNotchWidth: Bool
        var badgeWidth: Double
        var badgeHeight: Double
        var badgeDotSize: Double
        var badgeMaxDots: Int
        var badgeYOffset: Double
        var badgeHoverTargetHeight: Double
        var viewerModeRaw: String
        var shelfHeight: Double
        var shelfHotkey: String

        init(
            externalBadgeEnabled: Bool = false,
            badgeModeRaw: String = TrayBadgeMode.pill.rawValue,
            badgeFollowNotchWidth: Bool = false,
            badgeWidth: Double = 220.0,
            badgeHeight: Double = 6.0,
            badgeDotSize: Double = 2.0,
            badgeMaxDots: Int = 5,
            badgeYOffset: Double = 6.0,
            badgeHoverTargetHeight: Double = 6.0,
            viewerModeRaw: String = TrayViewMode.gallery.rawValue,
            shelfHeight: Double = 130.0,
            shelfHotkey: String = ""
        ) {
            self.externalBadgeEnabled = externalBadgeEnabled
            self.badgeModeRaw = badgeModeRaw
            self.badgeFollowNotchWidth = badgeFollowNotchWidth
            self.badgeWidth = badgeWidth
            self.badgeHeight = badgeHeight
            self.badgeDotSize = badgeDotSize
            self.badgeMaxDots = badgeMaxDots
            self.badgeYOffset = badgeYOffset
            self.badgeHoverTargetHeight = badgeHoverTargetHeight
            self.viewerModeRaw = viewerModeRaw
            self.shelfHeight = shelfHeight
            self.shelfHotkey = shelfHotkey
        }
    }

    struct NotchLab: Codable {
        var hoverPokeOut: Double
        var activePokeOut: Double
        var topOuterRadius: Double
        var leftTopOuterRadius: Double
        var rightTopOuterRadius: Double
        var topInnerRadius: Double
        var bottomRadius: Double
        var notchOverlap: Double
        var heightInset: Double
        var innerCurveModeRawValue: String

        init(
            hoverPokeOut: Double = 38,
            activePokeOut: Double = 58,
            topOuterRadius: Double = 15,
            leftTopOuterRadius: Double = 15,
            rightTopOuterRadius: Double = 15,
            topInnerRadius: Double = 0,
            bottomRadius: Double = 14,
            notchOverlap: Double = 7,
            heightInset: Double = 2,
            innerCurveModeRawValue: String = NotchInnerCurveMode.canonicalDownward.rawValue
        ) {
            self.hoverPokeOut = hoverPokeOut
            self.activePokeOut = activePokeOut
            self.topOuterRadius = topOuterRadius
            self.leftTopOuterRadius = leftTopOuterRadius
            self.rightTopOuterRadius = rightTopOuterRadius
            self.topInnerRadius = topInnerRadius
            self.bottomRadius = bottomRadius
            self.notchOverlap = notchOverlap
            self.heightInset = heightInset
            self.innerCurveModeRawValue = innerCurveModeRawValue
        }
    }

    struct Apps: Codable {
        var enabledStates: [String: Bool]

        init(enabledStates: [String: Bool] = [:]) {
            self.enabledStates = enabledStates
        }
    }

    struct Developer: Codable {
        var useCalendarWidget: Bool
        var voiceCommandConfidenceThreshold: Double

        init(
            useCalendarWidget: Bool = false,
            voiceCommandConfidenceThreshold: Double = 0.6
        ) {
            self.useCalendarWidget = useCalendarWidget
            self.voiceCommandConfidenceThreshold = voiceCommandConfidenceThreshold
        }
    }

    struct Helpers: Codable {
        /// Raw value of `HelperLifecycleMode` for TalkieAgent.
        var agentLifecycle: String
        /// Raw value of `HelperLifecycleMode` for TalkieSync.
        var syncLifecycle: String

        init(
            agentLifecycle: String = "alwaysOn",
            syncLifecycle: String = "attached"
        ) {
            self.agentLifecycle = agentLifecycle
            self.syncLifecycle = syncLifecycle
        }
    }

    var version: Int
    var onboarding: Onboarding
    var sync: Sync
    var remoteEngine: RemoteEngine
    var appearance: Appearance
    var home: Home
    var compose: Compose
    var localFiles: LocalFiles
    var workflow: Workflow
    var bridge: Bridge
    var devices: Devices
    var interstitial: Interstitial
    var models: Models
    var audio: Audio
    var capture: Capture
    var camera: Camera
    var ui: UI
    var notch: Notch
    var tray: Tray
    var notchLab: NotchLab
    var apps: Apps
    var developer: Developer
    var helpers: Helpers

    init(
        version: Int = 1,
        onboarding: Onboarding = .init(),
        sync: Sync = .init(),
        remoteEngine: RemoteEngine = .init(),
        appearance: Appearance = .init(),
        home: Home = .init(),
        compose: Compose = .init(),
        localFiles: LocalFiles = .init(),
        workflow: Workflow = .init(),
        bridge: Bridge = .init(),
        devices: Devices = .init(),
        interstitial: Interstitial = .init(),
        models: Models = .init(),
        audio: Audio = .init(),
        capture: Capture = .init(),
        camera: Camera = .init(),
        ui: UI = .init(),
        notch: Notch = .init(),
        tray: Tray = .init(),
        notchLab: NotchLab = .init(),
        apps: Apps = .init(),
        developer: Developer = .init(),
        helpers: Helpers = .init()
    ) {
        self.version = version
        self.onboarding = onboarding
        self.sync = sync
        self.remoteEngine = remoteEngine
        self.appearance = appearance
        self.home = home
        self.compose = compose
        self.localFiles = localFiles
        self.workflow = workflow
        self.bridge = bridge
        self.devices = devices
        self.interstitial = interstitial
        self.models = models
        self.audio = audio
        self.capture = capture
        self.camera = camera
        self.ui = ui
        self.notch = notch
        self.tray = tray
        self.notchLab = notchLab
        self.apps = apps
        self.developer = developer
        self.helpers = helpers
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case onboarding
        case sync
        case remoteEngine
        case appearance
        case home
        case compose
        case localFiles
        case workflow
        case bridge
        case devices
        case interstitial
        case models
        case audio
        case capture
        case camera
        case ui
        case notch
        case tray
        case notchLab
        case apps
        case developer
        case helpers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        onboarding = try container.decodeIfPresent(Onboarding.self, forKey: .onboarding) ?? .init()
        sync = try container.decodeIfPresent(Sync.self, forKey: .sync) ?? .init()
        remoteEngine = try container.decodeIfPresent(RemoteEngine.self, forKey: .remoteEngine) ?? .init()
        appearance = try container.decodeIfPresent(Appearance.self, forKey: .appearance) ?? .init()
        home = try container.decodeIfPresent(Home.self, forKey: .home) ?? .init()
        compose = try container.decodeIfPresent(Compose.self, forKey: .compose) ?? .init()
        localFiles = try container.decodeIfPresent(LocalFiles.self, forKey: .localFiles) ?? .init()
        workflow = try container.decodeIfPresent(Workflow.self, forKey: .workflow) ?? .init()
        bridge = try container.decodeIfPresent(Bridge.self, forKey: .bridge) ?? .init()
        devices = try container.decodeIfPresent(Devices.self, forKey: .devices) ?? .init()
        interstitial = try container.decodeIfPresent(Interstitial.self, forKey: .interstitial) ?? .init()
        models = try container.decodeIfPresent(Models.self, forKey: .models) ?? .init()
        audio = try container.decodeIfPresent(Audio.self, forKey: .audio) ?? .init()
        capture = try container.decodeIfPresent(Capture.self, forKey: .capture) ?? .init()
        camera = try container.decodeIfPresent(Camera.self, forKey: .camera) ?? .init()
        ui = try container.decodeIfPresent(UI.self, forKey: .ui) ?? .init()
        notch = try container.decodeIfPresent(Notch.self, forKey: .notch) ?? .init()
        tray = try container.decodeIfPresent(Tray.self, forKey: .tray) ?? .init()
        notchLab = try container.decodeIfPresent(NotchLab.self, forKey: .notchLab) ?? .init()
        apps = try container.decodeIfPresent(Apps.self, forKey: .apps) ?? .init()
        developer = try container.decodeIfPresent(Developer.self, forKey: .developer) ?? .init()
        helpers = try container.decodeIfPresent(Helpers.self, forKey: .helpers) ?? .init()
    }

    private static func defaultTTSVoiceId() -> String {
        TTSVoiceCatalog.recommendedSettingsVoiceId(hasOpenAIKey: false)
    }

    static let originalLegacyShortcutSlots: [String] = [
        "talkie-record",
        "talkie-dictate",
        "talkie-search",
        "mac-sessions",
        "mac-windows",
        "mac-claude",
        "talkie-ssh",
        "talkie-settings",
        "talkie-memos",
        "talkie-keyboard",
        "talkie-home",
        "talkie-agent",
        "talkie-pending",
        "talkie-command",
        "talkie-recent",
        "talkie-devices",
    ]

    static let defaultLegacyShortcutSlotsBeforeImageSharing: [String] = [
        "talkie-dictate",
        "talkie-record",
        "talkie-settings",
        "talkie-search",
        "mac-claude",
        "talkie-agent",
        "talkie-ssh",
        "mac-sessions",
        "mac-windows",
        "talkie-keyboard",
        "talkie-memos",
        "talkie-command",
        "talkie-pending",
        "talkie-recent",
        "talkie-home",
        "talkie-devices",
    ]

    static let defaultLegacyShortcutSlots: [String] = [
        "talkie-dictate",
        "talkie-record",
        "talkie-settings",
        "talkie-search",
        "mac-claude",
        "talkie-agent",
        "talkie-ssh",
        "mac-sessions",
        "mac-windows",
        "talkie-keyboard",
        "talkie-memos",
        "talkie-command",
        "talkie-pending",
        "talkie-recent",
        "talkie-home",
        "mac-paste-image",
    ]

    static func defaultDeviceShortcutBoard() -> ShortcutBoard {
        ShortcutBoard(
            spaces: [
                .init(
                    id: "talkie",
                    title: "Talkie",
                    tiles: defaultLegacyShortcutSlots.enumerated().map { index, slotID in
                        shortcutBoardTile(for: slotID, fallbackIndex: index, spaceID: "talkie")
                    }
                ),
                .init(
                    id: "workspace",
                    title: "Workspace",
                    tiles: Array(0..<16).map { index in
                        shortcutBoardTile(for: "", fallbackIndex: index, spaceID: "workspace")
                    }
                ),
                .init(
                    id: "command",
                    title: "Command",
                    tiles: Array(0..<16).map { index in
                        shortcutBoardTile(for: "", fallbackIndex: index, spaceID: "command")
                    }
                )
            ]
        )
    }

    mutating func refreshDefaultDeviceShortcutBoardCatalog() {
        let normalizedBridgeSlots = Self.normalizedLegacyShortcutSlots(bridge.companionShortcutSlots)
        bridge.companionShortcutSlots = Self.shouldRefreshStarterShortcutSlots(normalizedBridgeSlots)
            ? Self.defaultLegacyShortcutSlots
            : normalizedBridgeSlots

        guard var board = devices.defaults.shortcutBoard else { return }
        guard let talkieIndex = board.spaces.firstIndex(where: { $0.id == "talkie" }) ?? board.spaces.indices.first else {
            return
        }

        let currentSlots = Self.normalizedLegacyShortcutSlots(
            Array(board.spaces[talkieIndex].tiles.prefix(16).map(\.resolvedLegacySlotID))
        )
        let targetSlots = Self.shouldRefreshStarterShortcutSlots(currentSlots)
            ? Self.defaultLegacyShortcutSlots
            : currentSlots
        let spaceID = board.spaces[talkieIndex].id

        board.spaces[talkieIndex].tiles = targetSlots.enumerated().map { index, slotID in
            Self.shortcutBoardTile(for: slotID, fallbackIndex: index, spaceID: spaceID)
        }

        devices.defaults.shortcutBoard = board
        bridge.companionShortcutSlots = targetSlots
    }

    private static func normalizedLegacyShortcutSlots(_ slots: [String]) -> [String] {
        let trimmed = Array(slots.prefix(16))
        if trimmed.count == 16 {
            return trimmed
        }
        return trimmed + Array(repeating: "", count: 16 - trimmed.count)
    }

    private static func shouldRefreshStarterShortcutSlots(_ slots: [String]) -> Bool {
        slots == Self.originalLegacyShortcutSlots ||
        slots == Self.defaultLegacyShortcutSlotsBeforeImageSharing
    }

    static func shortcutBoardTile(for slotID: String, fallbackIndex: Int, spaceID: String) -> ShortcutBoard.Space.Tile {
        let title: String
        let subtitle: String?
        let icon: String
        let accentColor: String?
        let type: String
        let action: ShortcutBoard.Space.Tile.Action

        switch slotID {
        case "talkie-record":
            title = "Memo"
            subtitle = "Start or stop memo recording on your Mac."
            icon = "square.and.pencil"
            accentColor = "indigo"
            type = "liveAction"
            action = .init(target: "talkie", kind: "memo-recording")
        case "talkie-dictate":
            title = "Dictate"
            subtitle = "Start or stop dictation on the paired Mac."
            icon = "waveform.badge.mic"
            accentColor = "orange"
            type = "liveAction"
            action = .init(target: "talkie", kind: "dictation")
        case "talkie-search":
            title = "Search"
            subtitle = "Open Talkie search on the Mac."
            icon = "magnifyingglass"
            accentColor = "blue"
            type = "action"
            action = .init(target: "talkie", kind: "search")
        case "mac-sessions":
            title = "Workflow"
            subtitle = "Open your workflow picker on the Mac."
            icon = "wand.and.stars"
            accentColor = "teal"
            type = "action"
            action = .init(target: "workflow", kind: "open-picker")
        case "mac-windows":
            title = "Desktop Preview"
            subtitle = "See the current state of your Mac desktop."
            icon = "display"
            accentColor = "green"
            type = "action"
            action = .init(target: "talkie", kind: "screenshot")
        case "mac-claude":
            title = "Claude"
            subtitle = "Open the Claude console tab on your Mac."
            icon = "sparkles"
            accentColor = "purple"
            type = "action"
            action = .init(target: "talkie", kind: "console-tab", arguments: ["tabId": "claude"])
        case "talkie-ssh":
            title = "Shell"
            subtitle = "Open the Talkie Shell tab on your Mac."
            icon = "terminal"
            accentColor = "mint"
            type = "action"
            action = .init(target: "talkie", kind: "console-tab", arguments: ["tabId": "talkie-shell"])
        case "talkie-settings":
            title = "Voice Command"
            subtitle = "Start Talkie voice command capture."
            icon = "waveform.badge.plus"
            accentColor = "orange"
            type = "action"
            action = .init(target: "talkie", kind: "voice-command")
        case "talkie-memos":
            title = "Memos"
            subtitle = "Open the memo library."
            icon = "waveform"
            accentColor = "pink"
            type = "action"
            action = .init(target: "talkie", kind: "open-memos")
        case "talkie-keyboard":
            title = "Screen Record"
            subtitle = "Start or stop screen recording on your Mac."
            icon = "record.circle"
            accentColor = "red"
            type = "liveAction"
            action = .init(target: "talkie", kind: "screen-recording")
        case "talkie-home":
            title = "Home"
            subtitle = "Bring Talkie home to the front."
            icon = "house"
            accentColor = "indigo"
            type = "action"
            action = .init(target: "talkie", kind: "home")
        case "talkie-agent":
            title = "Pi"
            subtitle = "Open the Pi console tab on your Mac."
            icon = "circle.grid.cross"
            accentColor = "blue"
            type = "action"
            action = .init(target: "talkie", kind: "console-tab", arguments: ["tabId": "pi"])
        case "talkie-pending":
            title = "Pending"
            subtitle = "Open pending actions."
            icon = "hourglass"
            accentColor = "yellow"
            type = "action"
            action = .init(target: "talkie", kind: "pending")
        case "talkie-command":
            title = "Command"
            subtitle = "Open the command palette."
            icon = "command"
            accentColor = "indigo"
            type = "action"
            action = .init(target: "talkie", kind: "command-palette")
        case "talkie-recent":
            title = "Recent"
            subtitle = "Open recent agent activity."
            icon = "clock.arrow.circlepath"
            accentColor = "gray"
            type = "action"
            action = .init(target: "talkie", kind: "recent")
        case "talkie-devices":
            title = "Devices"
            subtitle = "Open device settings."
            icon = "ipad.and.iphone"
            accentColor = "cyan"
            type = "action"
            action = .init(target: "talkie", kind: "devices")
        case "mac-paste-image":
            title = "Share Image"
            subtitle = "Send a screenshot or photo from your iPhone to the Mac."
            icon = "photo.on.rectangle.angled"
            accentColor = "cyan"
            type = "action"
            action = .init(target: "talkie", kind: "paste-image")
        default:
            title = "Empty"
            subtitle = "Define this key from Talkie on your Mac."
            icon = "plus"
            accentColor = nil
            type = "action"
            action = .init(target: "talkie", kind: "unassigned")
        }

        return .init(
            id: slotID.isEmpty ? "\(spaceID)-slot-\(fallbackIndex + 1)" : slotID,
            title: title,
            subtitle: subtitle,
            icon: icon,
            accentColor: accentColor,
            type: type,
            legacySlotID: slotID.isEmpty ? nil : slotID,
            action: action,
            liveUI: type == "liveAction"
                ? .init(
                    showsTimer: true,
                    showsWaveform: slotID != "talkie-keyboard",
                    showsStopControl: true
                )
                : nil
        )
    }

    func resolvedShortcutBoard(
        platform: Devices.Platform? = nil,
        deviceID: String? = nil
    ) -> ShortcutBoard? {
        guard var board = devices.defaults.shortcutBoard else {
            return nil
        }

        if let platform,
           let classOverride = devices.classes.settings(for: platform).shortcutBoardOverride {
            board.apply(classOverride)
        }

        if let deviceID,
           let deviceOverride = devices.overrides[deviceID]?.shortcutBoardOverride {
            board.apply(deviceOverride)
        }

        return board
    }

    func resolvedShortcutSlots(
        platform: Devices.Platform? = nil,
        deviceID: String? = nil
    ) -> [String] {
        if let board = resolvedShortcutBoard(platform: platform, deviceID: deviceID) {
            let derived = board.legacyShortcutSlots
            if derived.contains(where: { !$0.isEmpty }) {
                return derived
            }
        }

        let legacy = bridge.companionShortcutSlots
        let trimmed = Array(legacy.prefix(16))
        if trimmed.count == 16 {
            return trimmed
        }
        return trimmed + Array(repeating: "", count: 16 - trimmed.count)
    }
}

private extension TalkieSettingsConfiguration.ShortcutBoard {
    var legacyShortcutSlots: [String] {
        let talkieSpace = spaces.first { $0.id == "talkie" } ?? spaces.first
        let derived = talkieSpace?.tiles.prefix(16).map(\.resolvedLegacySlotID) ?? []
        let trimmed = Array(derived.prefix(16))
        if trimmed.count == 16 {
            return trimmed
        }
        return trimmed + Array(repeating: "", count: 16 - trimmed.count)
    }

    mutating func apply(_ override: TalkieSettingsConfiguration.ShortcutBoardOverride) {
        for spaceOverride in override.spaceOverrides {
            guard let index = spaces.firstIndex(where: { $0.id == spaceOverride.id }) else { continue }
            spaces[index].apply(spaceOverride)
        }
    }
}

private extension TalkieSettingsConfiguration.ShortcutBoard.Space {
    mutating func apply(_ override: TalkieSettingsConfiguration.ShortcutBoardOverride.SpaceOverride) {
        if let title = override.title {
            self.title = title
        }

        for tileOverride in override.tileOverrides {
            guard let tileIndex = tiles.firstIndex(where: { $0.id == tileOverride.id }) else { continue }
            tiles[tileIndex].apply(tileOverride)
        }

        if let tileOrder = override.tileOrder, tileOrder.count == tiles.count {
            let tileMap = Dictionary(uniqueKeysWithValues: tiles.map { ($0.id, $0) })
            let reordered = tileOrder.compactMap { tileMap[$0] }
            if reordered.count == tiles.count {
                tiles = reordered
            }
        }
    }
}

private extension TalkieSettingsConfiguration.ShortcutBoard.Space.Tile {
    var resolvedLegacySlotID: String {
        if let legacySlotID {
            return legacySlotID
        }

        switch id {
        case "memo-record":
            return "talkie-record"
        case "dictation":
            return "talkie-dictate"
        case "search":
            return "talkie-search"
        case "workflow-picker":
            return "mac-sessions"
        case "screenshot":
            return "mac-windows"
        case "open-claude":
            return "mac-claude"
        case "ssh":
            return "talkie-ssh"
        case "voice-command":
            return "talkie-settings"
        case "memos":
            return "talkie-memos"
        case "screen-record":
            return "talkie-keyboard"
        default:
            return ""
        }
    }

    mutating func apply(_ override: TalkieSettingsConfiguration.ShortcutBoardOverride.SpaceOverride.TileOverride) {
        if let title = override.title {
            self.title = title
        }
        if let subtitle = override.subtitle {
            self.subtitle = subtitle
        }
        if let icon = override.icon {
            self.icon = icon
        }
        if let accentColor = override.accentColor {
            self.accentColor = accentColor
        }
        if let type = override.type {
            self.type = type
        }
        if let legacySlotID = override.legacySlotID {
            self.legacySlotID = legacySlotID
        }
        if let action = override.action {
            self.action = action
        }
        if let liveUI = override.liveUI {
            self.liveUI = liveUI
        }
    }
}
