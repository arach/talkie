//
//  TalkieAppSettings.swift
//  Talkie iOS
//
//  Observable facade over the file-backed app configuration.
//

import Foundation
import Observation
import TalkieMobileKit

@MainActor
@Observable
final class TalkieAppSettings {
    static let shared = TalkieAppSettings()

    private let store = TalkieAppConfigurationStore.shared
    private var isApplyingConfiguration = false

    var theme: AppTheme = .scope { didSet { persistIfNeeded() } }
    var appearanceMode: AppearanceMode = .system { didSet { persistIfNeeded() } }
    var tagLocationEnabled = false { didSet { persistIfNeeded() } }
    var locationTipDismissed = false { didSet { persistIfNeeded() } }
    var keyboardLEDIndicatorsEnabled = true { didSet { persistIfNeeded() } }
    var keyboardHapticFeedbackEnabled = true { didSet { persistIfNeeded() } }
    var keyboardAutoCapitalizeEnabled = true { didSet { persistIfNeeded() } }
    var keyboardGridPreset: KeyboardGridPreset = .sixteen { didSet { persistIfNeeded() } }
    var transcriptionKeyboardEngine: TranscriptionEnginePreference = .auto { didSet { persistIfNeeded() } }
    var transcriptionMemoEngine: TranscriptionEnginePreference = .appleSpeech { didSet { persistIfNeeded() } }
    var preferredParakeetModel: ParakeetModel = .v3 { didSet { persistIfNeeded() } }
    var iCloudSyncEnabled = true { didSet { persistIfNeeded() } }
    var syncPreferredMethods = ["icloud", "bridge", "dropbox", "local"] { didSet { persistIfNeeded() } }
    var iCloudBannerDismissed = false { didSet { persistIfNeeded() } }
    var pinnedMacWorkflows: [TalkieAppConfiguration.PinnedWorkflow] = []
    var followComputerShortcutMode = false { didSet { persistIfNeeded() } }
    var hasSeenOnboarding = false { didSet { persistIfNeeded() } }
    var hasSeenResumeTooltip = false { didSet { persistIfNeeded() } }
    var keyboardModeEnabled = false { didSet { persistIfNeeded() } }
    var keyboardActiveLayout = "compact" { didSet { persistIfNeeded() } }
    var keyboardLastSelectedModeId = "" { didSet { persistIfNeeded() } }
    var keyboardLastSelectedModeAt: TimeInterval = 0 { didSet { persistIfNeeded() } }
    var ttsMode = "bridge" { didSet { persistIfNeeded() } }
    var ttsProvider = "local" { didSet { persistIfNeeded() } }
    var ttsVoice = "echo" { didSet { persistIfNeeded() } }
    var ttsApiKey = "" { didSet { persistIfNeeded() } }
    var ttsPlaybackRate = 1.0 { didSet { persistIfNeeded() } }
    var aiVoiceOutputRoute = "phone" { didSet { persistIfNeeded() } }

    var composeRevisionPath = "direct" { didSet { persistIfNeeded() } }
    var composeDirectProviderId = "openai" { didSet { persistIfNeeded() } }
    var composeDirectModelId = TalkieAIProviderCredentialPayload.defaultOpenAIModel { didSet { persistIfNeeded() } }
    /// When false (default) HyperScan uploads are ephemeral on the Mac and auto-deleted
    /// after a short TTL. When true the user has opted in to keep them indefinitely.
    var hyperScanRetainCaptures = false { didSet { persistIfNeeded() } }
    var sshHost = "" { didSet { persistIfNeeded() } }
    var sshPort = "22" { didSet { persistIfNeeded() } }
    var sshUsername = "" { didSet { persistIfNeeded() } }
    var sshStartupCommand = SSHTerminalStartupProfile.standardShell.startupCommand { didSet { persistIfNeeded() } }
    var sshStartupCommandResetVersion = 0 { didSet { persistIfNeeded() } }
    var sshStartupProfileRawValue = SSHTerminalStartupProfile.standardShell.rawValue { didSet { persistIfNeeded() } }
    var sshPrimaryActionModeRawValue = "memo" { didSet { persistIfNeeded() } }
    var sshRendererRawValue = SSHTerminalRenderer.ghostty.rawValue { didSet { persistIfNeeded() } }

    var displayPath: String {
        store.displayPath
    }

    private init() {
        apply(store.configuration)
    }

    func reloadFromDisk() {
        apply(store.reload())
    }

    private func apply(_ configuration: TalkieAppConfiguration) {
        isApplyingConfiguration = true

        theme = AppTheme(rawValue: configuration.appearance.theme) ?? .scope
        appearanceMode = AppearanceMode(rawValue: configuration.appearance.mode) ?? .system
        tagLocationEnabled = configuration.recording.tagLocationEnabled
        locationTipDismissed = configuration.recording.locationTipDismissed
        keyboardLEDIndicatorsEnabled = configuration.keyboard.ledIndicatorsEnabled
        keyboardHapticFeedbackEnabled = configuration.keyboard.hapticFeedbackEnabled
        keyboardAutoCapitalizeEnabled = configuration.keyboard.autoCapitalizeEnabled
        keyboardGridPreset = KeyboardGridPreset(rawValue: configuration.keyboard.gridPreset) ?? .sixteen
        transcriptionKeyboardEngine = TranscriptionEnginePreference(rawValue: configuration.transcription.keyboardEngine) ?? .auto
        transcriptionMemoEngine = TranscriptionEnginePreference(rawValue: configuration.transcription.memoEngine) ?? .appleSpeech
        preferredParakeetModel = ParakeetModel(rawValue: configuration.transcription.preferredParakeetModel) ?? .v3
        iCloudSyncEnabled = configuration.sync.iCloudEnabled
        syncPreferredMethods = configuration.sync.preferredMethods
        iCloudBannerDismissed = configuration.sync.bannerDismissed
        pinnedMacWorkflows = configuration.workflows.pinnedMacActions
        followComputerShortcutMode = configuration.bridge.followComputerShortcutMode
        hasSeenOnboarding = configuration.developer.hasSeenOnboarding
        hasSeenResumeTooltip = configuration.developer.hasSeenResumeTooltip
        keyboardModeEnabled = configuration.keyboard.modeEnabled
        keyboardActiveLayout = configuration.keyboard.activeLayout
        keyboardLastSelectedModeId = configuration.keyboard.lastSelectedModeId
        keyboardLastSelectedModeAt = configuration.keyboard.lastSelectedModeAt
        ttsMode = configuration.tts.mode
        ttsProvider = configuration.tts.provider
        ttsVoice = configuration.tts.voice
        ttsApiKey = configuration.tts.apiKey
        ttsPlaybackRate = configuration.tts.playbackRate ?? 1.0
        aiVoiceOutputRoute = configuration.tts.aiVoiceOutputRoute
        composeRevisionPath = configuration.compose.revisionPath
        composeDirectProviderId = configuration.compose.directProviderId
        composeDirectModelId = configuration.compose.directModelId
        hyperScanRetainCaptures = configuration.hyperScan.retainCaptures
        sshHost = configuration.ssh.host
        sshPort = configuration.ssh.port
        sshUsername = configuration.ssh.username
        sshStartupCommand = configuration.ssh.startupCommand
        sshStartupCommandResetVersion = configuration.ssh.startupCommandResetVersion
        sshStartupProfileRawValue = configuration.ssh.startupProfile
        sshPrimaryActionModeRawValue = configuration.ssh.primaryActionMode
        sshRendererRawValue = configuration.ssh.renderer

        synchronizeLegacyMirrors(using: configuration)
        isApplyingConfiguration = false
    }

    func refreshPinnedWorkflowMirror() {
        pinnedMacWorkflows = store.synchronizePinnedWorkflowMirror()
    }

    private func persistIfNeeded() {
        guard !isApplyingConfiguration else { return }

        let updatedConfiguration = store.update { configuration in
            configuration.appearance.theme = theme.rawValue
            configuration.appearance.mode = appearanceMode.rawValue
            configuration.recording.tagLocationEnabled = tagLocationEnabled
            configuration.recording.locationTipDismissed = locationTipDismissed
            configuration.keyboard.ledIndicatorsEnabled = keyboardLEDIndicatorsEnabled
            configuration.keyboard.hapticFeedbackEnabled = keyboardHapticFeedbackEnabled
            configuration.keyboard.autoCapitalizeEnabled = keyboardAutoCapitalizeEnabled
            configuration.keyboard.gridPreset = keyboardGridPreset.rawValue
            configuration.transcription.keyboardEngine = transcriptionKeyboardEngine.rawValue
            configuration.transcription.memoEngine = transcriptionMemoEngine.rawValue
            configuration.transcription.preferredParakeetModel = preferredParakeetModel.rawValue
            configuration.sync.iCloudEnabled = iCloudSyncEnabled
            configuration.sync.preferredMethods = syncPreferredMethods
            configuration.sync.bannerDismissed = iCloudBannerDismissed
            configuration.bridge.followComputerShortcutMode = followComputerShortcutMode
            configuration.developer.hasSeenOnboarding = hasSeenOnboarding
            configuration.developer.hasSeenResumeTooltip = hasSeenResumeTooltip
            configuration.keyboard.modeEnabled = keyboardModeEnabled
            configuration.keyboard.activeLayout = keyboardActiveLayout
            configuration.keyboard.lastSelectedModeId = keyboardLastSelectedModeId
            configuration.keyboard.lastSelectedModeAt = keyboardLastSelectedModeAt
            configuration.tts.mode = ttsMode
            configuration.tts.provider = ttsProvider
            configuration.tts.voice = ttsVoice
            configuration.tts.apiKey = ttsApiKey
            configuration.tts.playbackRate = ttsPlaybackRate
            configuration.tts.aiVoiceOutputRoute = aiVoiceOutputRoute
            configuration.compose.revisionPath = composeRevisionPath
            configuration.compose.directProviderId = composeDirectProviderId
            configuration.compose.directModelId = composeDirectModelId
            configuration.hyperScan.retainCaptures = hyperScanRetainCaptures
            configuration.ssh.host = sshHost
            configuration.ssh.port = sshPort
            configuration.ssh.username = sshUsername
            configuration.ssh.startupCommand = sshStartupCommand
            configuration.ssh.startupCommandResetVersion = sshStartupCommandResetVersion
            configuration.ssh.startupProfile = sshStartupProfileRawValue
            configuration.ssh.primaryActionMode = sshPrimaryActionModeRawValue
            configuration.ssh.renderer = sshRendererRawValue
        }

        synchronizeLegacyMirrors(using: updatedConfiguration)
    }

    private func synchronizeLegacyMirrors(using configuration: TalkieAppConfiguration) {
        let defaults = UserDefaults.standard
        let groupDefaults = UserDefaults(suiteName: kTalkieAppGroup)
        let encoder = JSONEncoder()

        defaults.set(configuration.appearance.theme, forKey: "selectedTheme")
        defaults.set(configuration.appearance.mode, forKey: "appearanceMode")
        groupDefaults?.set(configuration.appearance.mode, forKey: "appearanceMode")

        defaults.set(configuration.recording.tagLocationEnabled, forKey: "recording.tagLocation")
        defaults.set(configuration.recording.locationTipDismissed, forKey: "tips.locationDismissed")

        defaults.set(configuration.keyboard.ledIndicatorsEnabled, forKey: "keyboard.ledIndicators")
        defaults.set(configuration.keyboard.autoCapitalizeEnabled, forKey: "keyboard.autoCapitalize")
        KeyboardBridge.shared.setHapticFeedbackEnabled(configuration.keyboard.hapticFeedbackEnabled)
        if let preset = KeyboardGridPreset(rawValue: configuration.keyboard.gridPreset) {
            KeyboardBridge.shared.setGridPreset(preset)
        }

        defaults.set(configuration.transcription.keyboardEngine, forKey: "transcription.keyboardEngine")
        defaults.set(configuration.transcription.memoEngine, forKey: "transcription.memoEngine")
        defaults.set(configuration.transcription.preferredParakeetModel, forKey: "parakeet.preferredModel")

        defaults.set(configuration.sync.iCloudEnabled, forKey: SyncSettingsKey.iCloudEnabled)
        if let preferredMethodsData = try? encoder.encode(configuration.sync.preferredMethods.compactMap(SyncMethod.init(rawValue:))) {
            defaults.set(preferredMethodsData, forKey: "sync_preferred_methods")
        }
        defaults.set(configuration.sync.bannerDismissed, forKey: "iCloudBannerDismissed")

        defaults.set(configuration.developer.hasSeenOnboarding, forKey: "hasSeenOnboarding")
        defaults.set(configuration.developer.hasSeenResumeTooltip, forKey: "hasSeenResumeTooltip")

        defaults.set(configuration.keyboard.modeEnabled, forKey: KeyboardBridgeKey.keyboardModeEnabled.rawValue)
        KeyboardBridge.shared.setKeyboardModeEnabled(configuration.keyboard.modeEnabled)
        KeyboardBridge.shared.setActiveLayout(configuration.keyboard.activeLayout)
        groupDefaults?.set(configuration.keyboard.lastSelectedModeId, forKey: KeyboardBridgeKey.lastSelectedModeId.rawValue)
        groupDefaults?.set(configuration.keyboard.lastSelectedModeAt, forKey: KeyboardBridgeKey.lastSelectedModeAt.rawValue)
        groupDefaults?.synchronize()
        synchronizeKeyboardModeOverrides(configuration.keyboard.modeSlotOverrides)

        defaults.set(configuration.ssh.host, forKey: "sshTerminal.host")
        defaults.set(configuration.ssh.port, forKey: "sshTerminal.port")
        defaults.set(configuration.ssh.username, forKey: "sshTerminal.username")
        defaults.set(configuration.ssh.startupCommand, forKey: "sshTerminal.startupCommand")
        defaults.set(configuration.ssh.startupCommandResetVersion, forKey: "sshTerminal.startupCommandResetVersion")
        defaults.set(configuration.ssh.startupProfile, forKey: "sshTerminal.startupProfile")
        defaults.set(configuration.ssh.primaryActionMode, forKey: "sshTerminal.primaryActionMode")
        defaults.set(configuration.ssh.renderer, forKey: "sshTerminal.renderer")
        defaults.set(configuration.tts.playbackRate ?? 1.0, forKey: "tts.playbackRate")
        defaults.set(configuration.tts.aiVoiceOutputRoute, forKey: "tts.aiVoiceOutputRoute")
        defaults.set(configuration.hyperScan.retainCaptures, forKey: "hyperScan.retainCaptures")

        if let savedHostsData = try? encoder.encode(configuration.ssh.savedHosts) {
            defaults.set(savedHostsData, forKey: SSHTerminalSavedHostStore.defaultsKey)
        }
        defaults.set(configuration.ssh.knownHosts, forKey: SSHKnownHostStore.defaultsKey)

        let activeBridge = configuration.bridge.pairedMacs.first(where: { $0.id == configuration.bridge.activePairedMacID })
            ?? configuration.bridge.pairedMacs.first

        defaults.set(activeBridge?.hostname ?? "", forKey: "bridge.hostname")
        defaults.set(activeBridge?.port ?? 0, forKey: "bridge.port")
        defaults.set(configuration.bridge.deviceId, forKey: "bridge.deviceId")
        defaults.set(activeBridge?.pairedMacName ?? "", forKey: "bridge.pairedMacName")
        defaults.set(activeBridge?.serverPublicKey ?? "", forKey: "bridge.serverPublicKey")
        defaults.set(activeBridge?.privateKey ?? "", forKey: "bridge.privateKey")
    }

    private func synchronizeKeyboardModeOverrides(_ overrides: [String: [String: SlotConfig]]) {
        let bridge = KeyboardBridge.shared

        for mode in KeyboardMode.builtIn {
            let desiredSlots = overrides[mode.id, default: [:]]
            let desiredSlotNumbers = Set(desiredSlots.keys.compactMap(Int.init))
            let existingSlotNumbers = Set(bridge.getAllSlotConfigs(forMode: mode.id).keys)

            for slot in existingSlotNumbers.subtracting(desiredSlotNumbers) {
                bridge.clearSlotConfig(slot, forMode: mode.id)
            }

            for (slotKey, config) in desiredSlots {
                guard let slot = Int(slotKey), let data = try? JSONEncoder().encode(config) else { continue }
                bridge.setSlotConfig(slot, config: data, forMode: mode.id)
            }
        }
    }
}
