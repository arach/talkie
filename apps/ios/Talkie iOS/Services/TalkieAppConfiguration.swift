//
//  TalkieAppConfiguration.swift
//  Talkie iOS
//
//  Declarative file-backed configuration for the iPhone app.
//

import Foundation
import TalkieMobileKit

struct TalkieAppConfiguration: Codable {
    struct PinnedWorkflow: Codable, Hashable, Identifiable {
        var id: String = ""
        var name: String = ""
        var icon: String = "gearshape"
    }

    struct Appearance: Codable {
        var theme: String = "scope"
        var mode: String = "system"
        var density: String = "standard"
        var accentIntensity: String = "theme"
        var wordmarkStyle: String = "mono"
        var reduceMotionEnabled = false

        private enum CodingKeys: String, CodingKey {
            case theme
            case mode
            case density
            case accentIntensity
            case wordmarkStyle
            case reduceMotionEnabled
        }

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? "scope"
            mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? "system"
            density = try container.decodeIfPresent(String.self, forKey: .density) ?? "standard"
            accentIntensity = try container.decodeIfPresent(String.self, forKey: .accentIntensity) ?? "theme"
            wordmarkStyle = try container.decodeIfPresent(String.self, forKey: .wordmarkStyle) ?? "mono"
            reduceMotionEnabled = try container.decodeIfPresent(Bool.self, forKey: .reduceMotionEnabled) ?? false
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(theme, forKey: .theme)
            try container.encode(mode, forKey: .mode)
            try container.encode(density, forKey: .density)
            try container.encode(accentIntensity, forKey: .accentIntensity)
            try container.encode(wordmarkStyle, forKey: .wordmarkStyle)
            try container.encode(reduceMotionEnabled, forKey: .reduceMotionEnabled)
        }
    }

    struct Recording: Codable {
        var tagLocationEnabled = false
        var locationTipDismissed = false
        var inputDevice = "system"
        var sampleRate = "system"
        var echoCancellationEnabled = true
        var waveformStyle = "tape"

        private enum CodingKeys: String, CodingKey {
            case tagLocationEnabled
            case locationTipDismissed
            case inputDevice
            case sampleRate
            case echoCancellationEnabled
            case waveformStyle
        }

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tagLocationEnabled = try container.decodeIfPresent(Bool.self, forKey: .tagLocationEnabled) ?? false
            locationTipDismissed = try container.decodeIfPresent(Bool.self, forKey: .locationTipDismissed) ?? false
            inputDevice = try container.decodeIfPresent(String.self, forKey: .inputDevice) ?? "system"
            sampleRate = try container.decodeIfPresent(String.self, forKey: .sampleRate) ?? "system"
            echoCancellationEnabled = try container.decodeIfPresent(Bool.self, forKey: .echoCancellationEnabled) ?? true
            waveformStyle = try container.decodeIfPresent(String.self, forKey: .waveformStyle) ?? "tape"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(tagLocationEnabled, forKey: .tagLocationEnabled)
            try container.encode(locationTipDismissed, forKey: .locationTipDismissed)
            try container.encode(inputDevice, forKey: .inputDevice)
            try container.encode(sampleRate, forKey: .sampleRate)
            try container.encode(echoCancellationEnabled, forKey: .echoCancellationEnabled)
            try container.encode(waveformStyle, forKey: .waveformStyle)
        }
    }

    struct Keyboard: Codable {
        var ledIndicatorsEnabled = true
        var hapticFeedbackEnabled = true
        var autoCapitalizeEnabled = true
        var gridPreset = "sixteen"
        var modeEnabled = false
        var activeLayout = "compact"
        var lastSelectedModeId = ""
        var lastSelectedModeAt: TimeInterval = 0
        var modeSlotOverrides: [String: [String: SlotConfig]] = [:]
    }

    struct Transcription: Codable {
        // Parakeet is the better engine for the live/streaming flows
        // (keyboard dictation, agentic voice commands, terminal SSH
        // dictation) — those want low-latency continuous results that
        // Parakeet can stream on-device once warm. `auto` here means
        // Parakeet when its model is loaded, Apple Speech otherwise.
        var keyboardEngine = "auto"
        // Memos are post-processed audio files (no latency concern,
        // no model warm-up overhead worth paying). Apple Speech is
        // the right default; users can opt into Parakeet via Settings.
        var memoEngine = "apple"
        var preferredParakeetModel = "v3"
    }

    struct Sync: Codable {
        var iCloudEnabled = true
        var preferredMethods = ["icloud", "bridge", "dropbox", "local"]
        var bannerDismissed = false
    }

    struct Workflows: Codable {
        var pinnedMacActions: [PinnedWorkflow] = []
    }

    struct Developer: Codable {
        var hasSeenOnboarding = false
        var hasSeenResumeTooltip = false
    }

    struct Bridge: Codable {
        var deviceId = ""
        var followComputerShortcutMode = false
        var activePairedMacID = ""
        var pairedMacs: [PairedMac] = []

        struct PairedMac: Codable, Identifiable, Hashable {
            var id = UUID().uuidString
            var hostname = ""
            var port = 0
            var pairedMacName = ""
            var serverPublicKey = ""
            var privateKey = ""
            var lastSuccessfulContactAt: TimeInterval = 0
            var lastSelectedAt: TimeInterval = 0

            var isConfigured: Bool {
                !hostname.isEmpty && port > 0 && !serverPublicKey.isEmpty && !privateKey.isEmpty
            }
        }

        private enum CodingKeys: String, CodingKey {
            case deviceId
            case followComputerShortcutMode
            case activePairedMacID
            case pairedMacs
            case hostname
            case port
            case pairedMacName
            case serverPublicKey
            case privateKey
        }

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId) ?? ""
            followComputerShortcutMode = try container.decodeIfPresent(Bool.self, forKey: .followComputerShortcutMode) ?? false
            activePairedMacID = try container.decodeIfPresent(String.self, forKey: .activePairedMacID) ?? ""
            pairedMacs = try container.decodeIfPresent([PairedMac].self, forKey: .pairedMacs) ?? []

            if pairedMacs.isEmpty {
                let hostname = try container.decodeIfPresent(String.self, forKey: .hostname) ?? ""
                let port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 0
                let pairedMacName = try container.decodeIfPresent(String.self, forKey: .pairedMacName) ?? ""
                let serverPublicKey = try container.decodeIfPresent(String.self, forKey: .serverPublicKey) ?? ""
                let privateKey = try container.decodeIfPresent(String.self, forKey: .privateKey) ?? ""

                if !hostname.isEmpty, port > 0, !serverPublicKey.isEmpty, !privateKey.isEmpty {
                    let migrated = PairedMac(
                        hostname: hostname,
                        port: port,
                        pairedMacName: pairedMacName,
                        serverPublicKey: serverPublicKey,
                        privateKey: privateKey
                    )
                    pairedMacs = [migrated]
                    activePairedMacID = migrated.id
                }
            }

            if activePairedMacID.isEmpty, let firstID = pairedMacs.first?.id {
                activePairedMacID = firstID
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(deviceId, forKey: .deviceId)
            try container.encode(followComputerShortcutMode, forKey: .followComputerShortcutMode)
            try container.encode(activePairedMacID, forKey: .activePairedMacID)
            try container.encode(pairedMacs, forKey: .pairedMacs)

            let activePairedMac = pairedMacs.first(where: { $0.id == activePairedMacID }) ?? pairedMacs.first
            try container.encode(activePairedMac?.hostname ?? "", forKey: .hostname)
            try container.encode(activePairedMac?.port ?? 0, forKey: .port)
            try container.encode(activePairedMac?.pairedMacName ?? "", forKey: .pairedMacName)
            try container.encode(activePairedMac?.serverPublicKey ?? "", forKey: .serverPublicKey)
            try container.encode(activePairedMac?.privateKey ?? "", forKey: .privateKey)
        }
    }

    struct TTS: Codable {
        /// "bridge" = route through Mac, "direct" = call cloud API from device
        var mode = "bridge"
        /// "local", "openai", or "elevenlabs"
        var provider = "local"
        /// Voice ID (e.g. "af_heart" for Kokoro; "echo" for OpenAI; voice ID for ElevenLabs)
        var voice = ""
        /// API key for direct mode (stored locally, never synced)
        var apiKey = ""
        /// Shared playback speed for generated audio and on-device readout.
        var playbackRate: Double? = nil
        /// "phone", "watch", or "silent" for spoken AI command responses.
        var aiVoiceOutputRoute = "phone"
    }

    struct Compose: Codable {
        var revisionPath = "direct"
        var directProviderId = "openai"
        var directModelId = TalkieAIProviderCredentialPayload.defaultOpenAIModel
    }

    struct HyperScan: Codable {
        /// When true, uploaded HyperScan captures are retained on the Mac.
        /// When false (default), they are written to a transient directory
        /// and auto-deleted by the Mac after a short TTL.
        var retainCaptures = false
    }

    struct SSH: Codable {
        var host = ""
        var port = "22"
        var username = ""
        var startupCommand = SSHTerminalStartupProfile.standardShell.startupCommand
        var startupCommandResetVersion = 0
        var startupProfile = SSHTerminalStartupProfile.standardShell.rawValue
        var primaryActionMode = "memo"
        var renderer = SSHTerminalRenderer.ghostty.rawValue
        var savedHosts: [SSHTerminalSavedHost] = []
        var knownHosts: [String: String] = [:]
    }

    var version = 1
    var appearance = Appearance()
    var recording = Recording()
    var keyboard = Keyboard()
    var transcription = Transcription()
    var sync = Sync()
    var workflows = Workflows()
    var developer = Developer()
    var bridge = Bridge()
    var tts = TTS()
    var compose = Compose()
    var hyperScan = HyperScan()
    var ssh = SSH()
}
