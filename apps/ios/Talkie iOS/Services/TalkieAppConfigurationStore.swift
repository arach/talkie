//
//  TalkieAppConfigurationStore.swift
//  Talkie iOS
//
//  JSON-backed storage for user-manageable iPhone app configuration.
//

import Foundation
import TalkieMobileKit

final class TalkieAppConfigurationStore {
    static let shared = TalkieAppConfigurationStore()
    private static let pinnedWorkflowsKey = "pinnedWorkflows"

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()
    private let fileURL: URL

    var displayPath: String {
        fileURL.path
    }

    var configuration: TalkieAppConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked()
    }

    private init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        fileURL = Self.makeFileURL(fileManager: fileManager)

        lock.lock()
        defer { lock.unlock() }
        ensureDirectoryExistsLocked()
        let configuration = loadLocked()
        saveLocked(configuration)
    }

    func reload() -> TalkieAppConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked()
    }

    @discardableResult
    func update(_ mutate: (inout TalkieAppConfiguration) -> Void) -> TalkieAppConfiguration {
        lock.lock()
        defer { lock.unlock() }

        var configuration = loadLocked()
        mutate(&configuration)
        saveLocked(configuration)
        return configuration
    }

    @discardableResult
    func synchronizePinnedWorkflowMirror() -> [TalkieAppConfiguration.PinnedWorkflow] {
        lock.lock()
        defer { lock.unlock() }

        NSUbiquitousKeyValueStore.default.synchronize()

        var configuration = loadLocked()
        if let latestPinnedWorkflows = Self.loadPinnedWorkflowMirror(using: decoder),
           configuration.workflows.pinnedMacActions != latestPinnedWorkflows {
            configuration.workflows.pinnedMacActions = latestPinnedWorkflows
            saveLocked(configuration)
        }

        return configuration.workflows.pinnedMacActions
    }

    private func loadLocked() -> TalkieAppConfiguration {
        ensureDirectoryExistsLocked()

        guard
            let data = try? Data(contentsOf: fileURL),
            let configuration = try? decoder.decode(TalkieAppConfiguration.self, from: data)
        else {
            let configuration = bootstrapFromLegacyState()
            saveLocked(configuration)
            return configuration
        }

        return configuration
    }

    private func saveLocked(_ configuration: TalkieAppConfiguration) {
        ensureDirectoryExistsLocked()

        do {
            let data = try encoder.encode(configuration)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLogger.app.error("Failed to save app configuration: \(error.localizedDescription)")
        }
    }

    private func ensureDirectoryExistsLocked() {
        let directoryURL = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    private func ensureFileExistsLocked() {
        guard !fileManager.fileExists(atPath: fileURL.path) else { return }
        saveLocked(bootstrapFromLegacyState())
    }

    private func bootstrapFromLegacyState() -> TalkieAppConfiguration {
        let defaults = UserDefaults.standard
        let groupDefaults = UserDefaults(suiteName: kTalkieAppGroup)
        let keyboardBridge = KeyboardBridge.shared

        var configuration = TalkieAppConfiguration()

        configuration.appearance.theme = defaults.string(forKey: "selectedTheme") ?? configuration.appearance.theme
        configuration.appearance.mode = defaults.string(forKey: "appearanceMode") ?? configuration.appearance.mode

        configuration.recording.tagLocationEnabled = defaults.bool(forKey: "recording.tagLocation")
        configuration.recording.locationTipDismissed = defaults.bool(forKey: "tips.locationDismissed")

        if defaults.object(forKey: "keyboard.ledIndicators") != nil {
            configuration.keyboard.ledIndicatorsEnabled = defaults.bool(forKey: "keyboard.ledIndicators")
        }
        if defaults.object(forKey: "keyboard.autoCapitalize") != nil {
            configuration.keyboard.autoCapitalizeEnabled = defaults.bool(forKey: "keyboard.autoCapitalize")
        }
        configuration.keyboard.hapticFeedbackEnabled = keyboardBridge.getHapticFeedbackEnabled()
        configuration.keyboard.gridPreset = keyboardBridge.getGridPreset().rawValue
        configuration.keyboard.modeEnabled = keyboardBridge.getKeyboardModeEnabled()
        configuration.keyboard.activeLayout = keyboardBridge.getActiveLayout() ?? configuration.keyboard.activeLayout
        configuration.keyboard.lastSelectedModeId = keyboardBridge.getLastSelectedModeId() ?? configuration.keyboard.lastSelectedModeId
        configuration.keyboard.lastSelectedModeAt = groupDefaults?.double(forKey: KeyboardBridgeKey.lastSelectedModeAt.rawValue) ?? 0
        configuration.keyboard.modeSlotOverrides = bootstrapModeSlotOverrides(using: keyboardBridge)

        configuration.transcription.keyboardEngine = defaults.string(forKey: "transcription.keyboardEngine") ?? configuration.transcription.keyboardEngine
        configuration.transcription.memoEngine = defaults.string(forKey: "transcription.memoEngine") ?? configuration.transcription.memoEngine
        configuration.transcription.preferredParakeetModel = defaults.string(forKey: "parakeet.preferredModel") ?? configuration.transcription.preferredParakeetModel

        configuration.sync.iCloudEnabled = defaults.object(forKey: SyncSettingsKey.iCloudEnabled) as? Bool ?? true
        if
            let data = defaults.data(forKey: "sync_preferred_methods"),
            let methods = try? decoder.decode([SyncMethod].self, from: data)
        {
            configuration.sync.preferredMethods = methods.map(\.rawValue)
        }
        configuration.sync.bannerDismissed = defaults.bool(forKey: "iCloudBannerDismissed")

        configuration.developer.hasSeenOnboarding = defaults.bool(forKey: "hasSeenOnboarding")
        configuration.developer.hasSeenResumeTooltip = defaults.bool(forKey: "hasSeenResumeTooltip")

        configuration.bridge.deviceId = defaults.string(forKey: "bridge.deviceId") ?? ""
        let legacyBridgeHostname = defaults.string(forKey: "bridge.hostname") ?? ""
        let legacyBridgePort = defaults.integer(forKey: "bridge.port")
        let legacyPairedMacName = defaults.string(forKey: "bridge.pairedMacName") ?? ""
        let legacyBridgeServerPublicKey = defaults.string(forKey: "bridge.serverPublicKey") ?? ""
        let legacyBridgePrivateKey = defaults.string(forKey: "bridge.privateKey") ?? ""

        if
            !legacyBridgeHostname.isEmpty,
            legacyBridgePort > 0,
            !legacyBridgeServerPublicKey.isEmpty,
            !legacyBridgePrivateKey.isEmpty
        {
            let migratedBridge = TalkieAppConfiguration.Bridge.PairedMac(
                hostname: legacyBridgeHostname,
                port: legacyBridgePort,
                pairedMacName: legacyPairedMacName,
                serverPublicKey: legacyBridgeServerPublicKey,
                privateKey: legacyBridgePrivateKey
            )
            configuration.bridge.pairedMacs = [migratedBridge]
            configuration.bridge.activePairedMacID = migratedBridge.id
        }

        configuration.ssh.host = defaults.string(forKey: "sshTerminal.host") ?? configuration.ssh.host
        configuration.ssh.port = defaults.string(forKey: "sshTerminal.port") ?? configuration.ssh.port
        configuration.ssh.username = defaults.string(forKey: "sshTerminal.username") ?? configuration.ssh.username
        configuration.ssh.startupCommand = defaults.string(forKey: "sshTerminal.startupCommand") ?? configuration.ssh.startupCommand
        configuration.ssh.startupCommandResetVersion = defaults.integer(forKey: "sshTerminal.startupCommandResetVersion")
        configuration.ssh.startupProfile = defaults.string(forKey: "sshTerminal.startupProfile") ?? configuration.ssh.startupProfile
        configuration.ssh.primaryActionMode = defaults.string(forKey: "sshTerminal.primaryActionMode") ?? configuration.ssh.primaryActionMode
        configuration.ssh.renderer = defaults.string(forKey: "sshTerminal.renderer") ?? configuration.ssh.renderer

        if
            let savedHostData = defaults.data(forKey: SSHTerminalSavedHostStore.defaultsKey),
            let savedHosts = try? decoder.decode([SSHTerminalSavedHost].self, from: savedHostData)
        {
            configuration.ssh.savedHosts = savedHosts
        }

        configuration.ssh.knownHosts = defaults.dictionary(forKey: SSHKnownHostStore.defaultsKey) as? [String: String] ?? [:]
        if let pinnedMacActions = Self.loadPinnedWorkflowMirror(using: decoder) {
            configuration.workflows.pinnedMacActions = pinnedMacActions
        }

        return configuration
    }

    private func bootstrapModeSlotOverrides(using keyboardBridge: KeyboardBridge) -> [String: [String: SlotConfig]] {
        var overrides: [String: [String: SlotConfig]] = [:]

        for mode in KeyboardMode.builtIn {
            let configs = keyboardBridge.getAllSlotConfigs(forMode: mode.id)
            guard !configs.isEmpty else { continue }

            var serializedSlots: [String: SlotConfig] = [:]
            for (slot, data) in configs {
                guard let config = try? decoder.decode(SlotConfig.self, from: data) else { continue }
                serializedSlots[String(slot)] = config
            }

            if !serializedSlots.isEmpty {
                overrides[mode.id] = serializedSlots
            }
        }

        return overrides
    }

    private static func makeFileURL(fileManager: FileManager) -> URL {
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: kTalkieAppGroup) {
            return containerURL
                .appending(path: "Library", directoryHint: .isDirectory)
                .appending(path: "Application Support", directoryHint: .isDirectory)
                .appending(path: "Talkie", directoryHint: .isDirectory)
                .appending(path: "settings", directoryHint: .isDirectory)
                .appending(path: "config.json")
        }

        return URL.applicationSupportDirectory
            .appending(path: "Talkie", directoryHint: .isDirectory)
            .appending(path: "settings", directoryHint: .isDirectory)
            .appending(path: "config.json")
    }

    private static func loadPinnedWorkflowMirror(using decoder: JSONDecoder) -> [TalkieAppConfiguration.PinnedWorkflow]? {
        guard
            let data = NSUbiquitousKeyValueStore.default.data(forKey: pinnedWorkflowsKey),
            let pinnedWorkflows = try? decoder.decode([TalkieAppConfiguration.PinnedWorkflow].self, from: data)
        else {
            return nil
        }

        return pinnedWorkflows
    }
}
