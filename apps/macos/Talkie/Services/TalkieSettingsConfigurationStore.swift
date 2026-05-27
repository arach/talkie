//
//  TalkieSettingsConfigurationStore.swift
//  Talkie macOS
//
//  Human-editable settings store persisted to Application Support.
//

import AppKit
import Foundation
import Observation
import TalkieKit

private let settingsConfigLog = Log(.system)

@Observable
final class TalkieSettingsConfigurationStore {
    static let shared = TalkieSettingsConfigurationStore()

    private(set) var configuration: TalkieSettingsConfiguration
    let fileURL: URL

    private init() {
        let settingsDirectory = TalkieEnvironment.current.appSupportDirectory
            .appendingPathComponent("settings", isDirectory: true)

        try? FileManager.default.createDirectory(at: settingsDirectory, withIntermediateDirectories: true)

        fileURL = settingsDirectory.appendingPathComponent("config.json")

        if let loaded = Self.load(from: fileURL) {
            var refreshed = loaded
            refreshed.refreshDefaultDeviceShortcutBoardCatalog()
            Self.normalizeLaunchMode(&refreshed)
            configuration = refreshed
            save()
        } else {
            var bootstrap = Self.bootstrapFromLegacyStorage()
            bootstrap.refreshDefaultDeviceShortcutBoardCatalog()
            Self.normalizeLaunchMode(&bootstrap)
            configuration = bootstrap
            save()
        }
    }

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return fileURL.path.replacingOccurrences(of: home, with: "~")
    }

    func reloadFromDisk() {
        guard let loaded = Self.load(from: fileURL) else { return }
        var refreshed = loaded
        refreshed.refreshDefaultDeviceShortcutBoardCatalog()
        Self.normalizeLaunchMode(&refreshed)
        configuration = refreshed
        save()
    }

    func update(_ update: (inout TalkieSettingsConfiguration) -> Void) {
        var next = configuration
        update(&next)
        configuration = next
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(configuration)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            settingsConfigLog.error("Failed to save declarative settings: \(error.localizedDescription)")
        }
    }

    private static func load(from fileURL: URL) -> TalkieSettingsConfiguration? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        do {
            return try JSONDecoder().decode(TalkieSettingsConfiguration.self, from: data)
        } catch {
            settingsConfigLog.error("Failed to decode declarative settings: \(error.localizedDescription)")
            return nil
        }
    }

    private static func normalizeLaunchMode(_ configuration: inout TalkieSettingsConfiguration) {
        configuration.appearance.detailLevel = .max
        configuration.appearance.settingsAudience = .pro
    }

    private static func bootstrapFromLegacyStorage() -> TalkieSettingsConfiguration {
        let defaults = UserDefaults.standard
        let shared = TalkieSharedSettings

        var config = TalkieSettingsConfiguration()

        config.onboarding.firstLaunchDate = defaults.object(forKey: "firstLaunchDate") as? Date
        config.onboarding.onboardingCardsDismissed = defaults.bool(forKey: "onboardingCardsDismissed")

        config.sync.syncOnLaunch = defaults.bool(forKey: "syncOnLaunch")
        config.sync.minimumSyncInterval = defaults.double(forKey: "minimumSyncInterval") == 0 ? 300 : defaults.double(forKey: "minimumSyncInterval")
        if defaults.object(forKey: "iCloudSyncEnabled") != nil {
            config.sync.iCloudSyncEnabled = defaults.bool(forKey: "iCloudSyncEnabled")
        }
        if let savedMinutes = defaults.object(forKey: "syncIntervalMinutes") as? Int {
            config.sync.syncIntervalMinutes = savedMinutes
        }

        config.remoteEngine.enabled = shared.bool(forKey: AgentSettingsKey.remoteEngineEnabled)
        config.remoteEngine.host = shared.string(forKey: AgentSettingsKey.remoteEngineHost) ?? ""
        let remotePort = shared.integer(forKey: AgentSettingsKey.remoteEnginePort)
        config.remoteEngine.port = remotePort > 0 ? remotePort : 19821

        if let raw = defaults.string(forKey: "appearanceMode"),
           let value = AppearanceMode(rawValue: raw) {
            config.appearance.mode = value
        }
        if let raw = defaults.string(forKey: "accentColor"),
           let value = AccentColorOption(rawValue: raw) {
            config.appearance.accentColor = value
        }
        if let raw = defaults.string(forKey: "currentTheme"),
           let value = ThemePreset(rawValue: raw) {
            config.appearance.currentTheme = value
        }
        if defaults.object(forKey: "enableGlassEffects") != nil {
            config.appearance.enableGlassEffects = defaults.bool(forKey: "enableGlassEffects")
        }
        if let raw = defaults.string(forKey: "uiFontStyle"),
           let value = FontStyleOption(rawValue: raw) {
            config.appearance.uiFontStyle = value
        }
        if let raw = defaults.string(forKey: "contentFontStyle"),
           let value = FontStyleOption(rawValue: raw) {
            config.appearance.contentFontStyle = value
        }
        if let raw = defaults.string(forKey: "uiFontSize"),
           let value = FontSizeOption(rawValue: raw) {
            config.appearance.uiFontSize = value
        }
        if let raw = defaults.string(forKey: "contentFontSize"),
           let value = FontSizeOption(rawValue: raw) {
            config.appearance.contentFontSize = value
        }
        if let raw = defaults.string(forKey: "consoleTerminalTheme"),
           let value = ConsoleTerminalThemeOption(rawValue: raw) {
            config.appearance.consoleTerminalTheme = value
        }
        if let raw = defaults.string(forKey: "consoleTerminalFont"),
           let value = ConsoleTerminalFontOption(rawValue: raw) {
            config.appearance.consoleTerminalFont = value
        }
        if let raw = defaults.string(forKey: "consoleTerminalFontSize"),
           let value = ConsoleTerminalFontSizeOption(rawValue: raw) {
            config.appearance.consoleTerminalFontSize = value
        }
        if defaults.object(forKey: "uiAllCaps") != nil {
            config.appearance.uiAllCaps = defaults.bool(forKey: "uiAllCaps")
        }
        if let raw = defaults.string(forKey: "detailLevel"),
           let value = DetailLevel(rawValue: raw) {
            config.appearance.detailLevel = value
        }
        if let raw = defaults.string(forKey: "settingsAudience"),
           let value = SettingsAudience(rawValue: raw) {
            config.appearance.settingsAudience = value
        }

        if let data = defaults.data(forKey: "homeLayoutConfig"),
           let layout = try? JSONDecoder().decode(HomeLayoutConfig.self, from: data) {
            config.home.layout = layout
        }

        config.compose.providerId = defaults.string(forKey: "composeLLMProviderId")
        config.compose.modelId = defaults.string(forKey: "composeLLMModelId")
        if let prompt = defaults.string(forKey: "composeAssistantPrompt"),
           !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config.compose.assistantPrompt = prompt
        }

        if defaults.object(forKey: "saveTranscriptsLocally") != nil {
            config.localFiles.saveTranscriptsLocally = defaults.bool(forKey: "saveTranscriptsLocally")
        }
        config.localFiles.transcriptsFolderPath = defaults.string(forKey: "transcriptsFolderPath") ?? SettingsManager.defaultTranscriptsFolderPath
        if defaults.object(forKey: "saveAudioLocally") != nil {
            config.localFiles.saveAudioLocally = defaults.bool(forKey: "saveAudioLocally")
        }
        config.localFiles.audioFolderPath = defaults.string(forKey: "audioFolderPath") ?? SettingsManager.defaultAudioFolderPath

        if defaults.object(forKey: "autoRunWorkflowsEnabled") != nil {
            config.workflow.autoRunEnabled = defaults.bool(forKey: "autoRunWorkflowsEnabled")
        }

        if defaults.object(forKey: "autoStartBridge") != nil {
            config.bridge.autoStartBridge = defaults.bool(forKey: "autoStartBridge")
        }
        if defaults.object(forKey: "talkieServerEnabled") != nil {
            config.bridge.talkieServerEnabled = defaults.bool(forKey: "talkieServerEnabled")
        }
        if defaults.object(forKey: "talkieGatewayEnabled") != nil {
            config.bridge.talkieGatewayEnabled = defaults.bool(forKey: "talkieGatewayEnabled")
        }
        if defaults.object(forKey: "talkieClaudeSessionsEnabled") != nil {
            config.bridge.talkieClaudeSessionsEnabled = defaults.bool(forKey: "talkieClaudeSessionsEnabled")
        }
        if defaults.object(forKey: "extensionsFrameworkEnabled") != nil {
            config.bridge.extensionsFrameworkEnabled = defaults.bool(forKey: "extensionsFrameworkEnabled")
        }
        if defaults.object(forKey: "companionShortcutModeEnabled") != nil {
            config.bridge.shortcutBoardEnabled = defaults.bool(forKey: "companionShortcutModeEnabled")
            config.bridge.companionShortcutModeEnabled = defaults.bool(forKey: "companionShortcutModeEnabled")
        }

        if defaults.object(forKey: "askOnInterstitialDismiss") != nil {
            config.interstitial.askOnDismiss = defaults.bool(forKey: "askOnInterstitialDismiss")
        }

        if let raw = defaults.string(forKey: "llmQualityTier"),
           let value = LLMCostTier(rawValue: raw) {
            config.models.llmCostTier = value
        }
        config.models.selectedModel = defaults.string(forKey: "selectedModel") ?? (LLMConfig.shared.defaultModel(for: "gemini") ?? "")
        config.models.liveTranscriptionModelId =
            shared.string(forKey: AgentSettingsKey.selectedModelId)
            ?? defaults.string(forKey: "liveTranscriptionModelId")
            ?? TalkieDefaults.dictationModelId

        if let savedVolume = defaults.object(forKey: "playbackVolume") as? Float {
            config.audio.playbackVolume = savedVolume
        }
        if let raw = defaults.string(forKey: "jsonExportSchedule"),
           let value = JSONExportSchedule(rawValue: raw) {
            config.audio.jsonExportSchedule = value
        }
        config.audio.selectedTTSVoiceId =
            shared.string(forKey: AgentSettingsKey.selectedTTSVoiceId)
            ?? defaults.string(forKey: "selectedTTSVoiceId")
            ?? TTSVoiceCatalog.recommendedSettingsVoiceId(hasOpenAIKey: false)

        if let raw = defaults.string(forKey: "captureHUDPosition"),
           let value = CaptureHUDPosition(rawValue: raw) {
            config.capture.hudPosition = value
        }
        if let raw = defaults.string(forKey: "preferredScreenshotLauncher"),
           let value = ScreenshotLauncher(rawValue: raw) {
            config.capture.screenshotLauncher = value
        }

        if let raw = defaults.string(forKey: "cameraBubbleSize"),
           let value = CameraBubbleSize(rawValue: raw) {
            config.camera.bubbleSize = value
        }
        if let raw = defaults.string(forKey: "cameraQuality"),
           let value = CameraQuality(rawValue: raw) {
            config.camera.quality = value
        }
        if let raw = defaults.string(forKey: "cameraVideoCodec"),
           let value = CameraVideoCodec(rawValue: raw) {
            config.camera.videoCodec = value
        }
        config.camera.deviceID = defaults.string(forKey: "cameraDeviceID") ?? ""
        let maxClipDuration = defaults.double(forKey: "cameraMaxClipDuration")
        if maxClipDuration > 0 {
            config.camera.maxClipDuration = maxClipDuration
        }

        if defaults.object(forKey: "settings.sidebar.iconsOnly") != nil {
            config.ui.settingsSidebarIconsOnly = defaults.bool(forKey: "settings.sidebar.iconsOnly")
        }

        let hasBuiltInNotchedDisplay = NSScreen.screens.contains { screen in
            let info = NotchInfo.detect(for: screen)
            return info.hasNotch && CGDisplayIsBuiltin(info.displayID) != 0
        }

        config.notch.enabled = defaults.object(forKey: "notchCapabilityEnabled") as? Bool ?? config.notch.enabled
        config.notch.externalEnabled = defaults.object(forKey: "notchExternalMonitorEnabled") as? Bool ?? config.notch.externalEnabled
        config.notch.shellStyleRaw = defaults.string(forKey: "notchVirtualDisplayStyle") ?? config.notch.shellStyleRaw
        config.notch.islandVisualStyleEnabled = defaults.object(forKey: "notchIslandVisualStyleEnabled") as? Bool ?? config.notch.islandVisualStyleEnabled
        config.notch.alwaysVisible = defaults.object(forKey: "notchAlwaysVisible") as? Bool ?? config.notch.alwaysVisible
        if defaults.object(forKey: "notchOverlayOpacity") != nil {
            config.notch.overlayOpacity = defaults.double(forKey: "notchOverlayOpacity")
        }
        if defaults.object(forKey: "notchTrayBarEnabled") != nil {
            config.notch.trayStripEnabled = defaults.bool(forKey: "notchTrayBarEnabled")
        } else {
            config.notch.trayStripEnabled = hasBuiltInNotchedDisplay
        }
        config.notch.trayStripPlacement = defaults.string(forKey: "notchTrayStripPlacement") ?? config.notch.trayStripPlacement
        config.notch.trayStripShowDots = defaults.object(forKey: "notchTrayIndicatorShowDots") as? Bool ?? config.notch.trayStripShowDots
        if defaults.object(forKey: "notchTrayIndicatorWidth") != nil {
            config.notch.trayStripWidth = defaults.double(forKey: "notchTrayIndicatorWidth")
        }
        if defaults.object(forKey: "notchTrayIndicatorHeight") != nil {
            config.notch.trayStripHeight = defaults.double(forKey: "notchTrayIndicatorHeight")
        }
        if defaults.object(forKey: "notchTrayIndicatorDotSize") != nil {
            config.notch.trayStripDotSize = defaults.double(forKey: "notchTrayIndicatorDotSize")
        }
        if defaults.object(forKey: "notchTrayIndicatorMaxDots") != nil {
            config.notch.trayStripMaxDots = defaults.integer(forKey: "notchTrayIndicatorMaxDots")
        }
        if defaults.object(forKey: "notchTrayIndicatorBorderOpacity") != nil {
            config.notch.trayStripBorderOpacity = defaults.double(forKey: "notchTrayIndicatorBorderOpacity")
        }
        if defaults.object(forKey: "notchTrayIndicatorYOffset") != nil {
            config.notch.trayStripYOffset = defaults.double(forKey: "notchTrayIndicatorYOffset")
        }
        config.notch.trayPreviewWhileRecordingEnabled = defaults.object(forKey: "notchTrayPreviewWhileRecordingEnabled") as? Bool ?? config.notch.trayPreviewWhileRecordingEnabled
        if defaults.object(forKey: "notchHoverZoneWidthExternal") != nil {
            config.notch.hoverZoneWidthExternal = defaults.double(forKey: "notchHoverZoneWidthExternal")
        }
        if defaults.object(forKey: "notchHoverZoneWidthNotch") != nil {
            config.notch.hoverZoneWidthNotch = defaults.double(forKey: "notchHoverZoneWidthNotch")
        }
        if defaults.object(forKey: "notchHoverZoneHeight") != nil {
            config.notch.hoverZoneHeight = defaults.double(forKey: "notchHoverZoneHeight")
        }
        if defaults.object(forKey: "notchHoverZonePaddingX") != nil {
            config.notch.hoverZonePaddingX = defaults.double(forKey: "notchHoverZonePaddingX")
        }
        if defaults.object(forKey: "notchHoverZonePaddingY") != nil {
            config.notch.hoverZonePaddingY = defaults.double(forKey: "notchHoverZonePaddingY")
        }
        if let data = defaults.data(forKey: "notchPerMonitorHoverZones"),
           let hoverZones = try? JSONDecoder().decode([String: HoverZoneConfig].self, from: data) {
            config.notch.perMonitorHoverZones = hoverZones
        }
        config.notch.communicationDemoEnabled = defaults.object(forKey: "notchCommunicationDemoEnabled") as? Bool ?? config.notch.communicationDemoEnabled
        config.notch.inspectorEnabled = defaults.object(forKey: "notchAnimationInspectorEnabled") as? Bool ?? config.notch.inspectorEnabled
        config.notch.inspectorScrubEnabled = defaults.object(forKey: "notchAnimationInspectorScrubEnabled") as? Bool ?? config.notch.inspectorScrubEnabled
        if defaults.object(forKey: "notchAnimationInspectorProgress") != nil {
            config.notch.inspectorProgress = defaults.double(forKey: "notchAnimationInspectorProgress")
        }
        if defaults.object(forKey: "notchAnimationInspectorExtensionWidthDelta") != nil {
            config.notch.inspectorExtensionWidthDelta = defaults.double(forKey: "notchAnimationInspectorExtensionWidthDelta")
        }
        if defaults.object(forKey: "notchAnimationInspectorExtensionWidthMatch") != nil {
            config.notch.inspectorExtensionWidthMatch = defaults.double(forKey: "notchAnimationInspectorExtensionWidthMatch")
        }
        config.notch.inspectorExtensionWidthReferenceRaw = defaults.string(forKey: "notchAnimationInspectorExtensionWidthReference") ?? config.notch.inspectorExtensionWidthReferenceRaw
        if defaults.object(forKey: "notchAnimationInspectorExtensionYOffset") != nil {
            config.notch.inspectorExtensionYOffset = defaults.double(forKey: "notchAnimationInspectorExtensionYOffset")
        }
        if defaults.object(forKey: "notchAnimationInspectorExtensionDropDistance") != nil {
            config.notch.inspectorExtensionDropDistance = defaults.double(forKey: "notchAnimationInspectorExtensionDropDistance")
        }
        if defaults.object(forKey: "notchAnimationInspectorExpansionStart") != nil {
            config.notch.inspectorExpansionStart = defaults.double(forKey: "notchAnimationInspectorExpansionStart")
        }
        if defaults.object(forKey: "notchAnimationInspectorBarAttachStart") != nil {
            config.notch.inspectorBarAttachStart = defaults.double(forKey: "notchAnimationInspectorBarAttachStart")
        }
        if defaults.object(forKey: "notchAnimationInspectorBarAttachDuration") != nil {
            config.notch.inspectorBarAttachDuration = defaults.double(forKey: "notchAnimationInspectorBarAttachDuration")
        }
        config.notch.inspectorRecordingExtensionPreviewRaw = defaults.string(forKey: "notchAnimationInspectorRecordingExtensionPreview") ?? config.notch.inspectorRecordingExtensionPreviewRaw
        if defaults.object(forKey: "notchAnimationInspectorPlaybackSpeed") != nil {
            config.notch.inspectorPlaybackSpeed = defaults.double(forKey: "notchAnimationInspectorPlaybackSpeed")
        }
        config.notch.aggressiveDebugLogging = defaults.object(forKey: "notchAggressiveDebugLogging") as? Bool ?? config.notch.aggressiveDebugLogging

        config.tray.externalBadgeEnabled = defaults.object(forKey: "externalTrayBadgeEnabled") as? Bool ?? config.tray.externalBadgeEnabled
        config.tray.badgeModeRaw = defaults.string(forKey: "trayBadgeMode") ?? config.tray.badgeModeRaw
        config.tray.badgeFollowNotchWidth = defaults.object(forKey: "trayBadgeStripFollowNotchWidth") as? Bool ?? config.tray.badgeFollowNotchWidth
        if defaults.object(forKey: "trayBadgeStripWidth") != nil {
            config.tray.badgeWidth = defaults.double(forKey: "trayBadgeStripWidth")
        }
        if defaults.object(forKey: "trayBadgeStripHeight") != nil {
            config.tray.badgeHeight = defaults.double(forKey: "trayBadgeStripHeight")
        }
        if defaults.object(forKey: "trayBadgeStripDotSize") != nil {
            config.tray.badgeDotSize = defaults.double(forKey: "trayBadgeStripDotSize")
        }
        if defaults.object(forKey: "trayBadgeStripMaxDots") != nil {
            config.tray.badgeMaxDots = defaults.integer(forKey: "trayBadgeStripMaxDots")
        }
        if defaults.object(forKey: "trayBadgeStripYOffset") != nil {
            config.tray.badgeYOffset = defaults.double(forKey: "trayBadgeStripYOffset")
        }
        if defaults.object(forKey: "trayBadgeStripHoverTargetHeight") != nil {
            config.tray.badgeHoverTargetHeight = defaults.double(forKey: "trayBadgeStripHoverTargetHeight")
        }
        config.tray.viewerModeRaw = defaults.string(forKey: "trayViewMode") ?? config.tray.viewerModeRaw
        if defaults.object(forKey: "trayShelfHeight") != nil {
            config.tray.shelfHeight = defaults.double(forKey: "trayShelfHeight")
        }
        config.tray.shelfHotkey = defaults.string(forKey: "trayShelfHotkey") ?? config.tray.shelfHotkey

        let notchLiveDefaults = UserDefaults(suiteName: NotchTuning.liveSuiteName)
        if let value = notchLiveDefaults?.object(forKey: NotchTuning.liveHoverPokeOutKey) as? Double {
            config.notchLab.hoverPokeOut = value
        }
        if let value = notchLiveDefaults?.object(forKey: NotchTuning.liveActivePokeOutKey) as? Double {
            config.notchLab.activePokeOut = value
        }
        if let value = notchLiveDefaults?.object(forKey: NotchTuning.liveTopOuterRadiusKey) as? Double {
            config.notchLab.topOuterRadius = value
        }
        if let value = notchLiveDefaults?.object(forKey: NotchTuning.liveLeftTopOuterRadiusKey) as? Double {
            config.notchLab.leftTopOuterRadius = value
        }
        if let value = notchLiveDefaults?.object(forKey: NotchTuning.liveRightTopOuterRadiusKey) as? Double {
            config.notchLab.rightTopOuterRadius = value
        }
        if let value = notchLiveDefaults?.object(forKey: NotchTuning.liveTopInnerRadiusKey) as? Double {
            config.notchLab.topInnerRadius = value
        }
        if let value = notchLiveDefaults?.object(forKey: NotchTuning.liveBottomRadiusKey) as? Double {
            config.notchLab.bottomRadius = value
        }
        if let value = notchLiveDefaults?.object(forKey: NotchTuning.liveNotchOverlapKey) as? Double {
            config.notchLab.notchOverlap = value
        }
        if let value = notchLiveDefaults?.object(forKey: NotchTuning.liveHeightInsetKey) as? Double {
            config.notchLab.heightInset = value
        }
        config.notchLab.innerCurveModeRawValue = notchLiveDefaults?.string(forKey: NotchTuning.liveInnerCurveModeKey) ?? config.notchLab.innerCurveModeRawValue

        let appEnabledStates = defaults.dictionaryRepresentation().reduce(into: [String: Bool]()) { partial, entry in
            guard entry.key.hasPrefix("app."), entry.key.hasSuffix(".enabled") else { return }
            let appId = String(entry.key.dropFirst(4).dropLast(8))
            guard !appId.isEmpty else { return }
            if let enabled = entry.value as? Bool {
                partial[appId] = enabled
            }
        }
        if !appEnabledStates.isEmpty {
            config.apps.enabledStates = appEnabledStates
        }

        if defaults.object(forKey: "dev.useCalendarWidget") != nil {
            config.developer.useCalendarWidget = defaults.bool(forKey: "dev.useCalendarWidget")
        }
        let confidence = defaults.double(forKey: "voiceCommand.confidenceThreshold")
        if confidence > 0 {
            config.developer.voiceCommandConfidenceThreshold = confidence
        }

        return config
    }
}
