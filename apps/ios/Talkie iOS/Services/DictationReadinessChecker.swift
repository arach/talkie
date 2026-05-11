//
//  DictationReadinessChecker.swift
//  Talkie iOS
//
//  Shared readiness logic for dictation landing pages.
//  Evaluates permissions, service state, and audio health.
//

import AVFoundation
import Speech
import SwiftUI
import TalkieMobileKit

// MARK: - Models

enum ReadinessStatus {
    case ready
    case warning
    case blocked
    case undetermined
}

enum RecoveryAction {
    case openSettings
    case enableKeyboardMode
    case retryConnection
    case forceReset
}

struct ReadinessCheck: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let status: ReadinessStatus
    let detail: String?
    let recovery: RecoveryAction?
}

struct DictationReadiness {
    let checks: [ReadinessCheck]

    var isFullyReady: Bool {
        checks.allSatisfy { $0.status == .ready }
    }

    var blockers: [ReadinessCheck] {
        checks.filter { $0.status == .blocked }
    }

    var warnings: [ReadinessCheck] {
        checks.filter { $0.status == .warning }
    }

    var firstBlocker: ReadinessCheck? {
        blockers.first
    }

    var hasBlockers: Bool {
        !blockers.isEmpty
    }

    var hasWarnings: Bool {
        !warnings.isEmpty
    }
}

// MARK: - Checker

@Observable
final class DictationReadinessChecker {

    private(set) var readiness = DictationReadiness(checks: [])

    private let headlessService = HeadlessDictationService.shared
    private let bridge = KeyboardBridge.shared
    private let sharedStore = DictationSharedStore.shared

    func evaluate() {
        var checks: [ReadinessCheck] = []

        // 1. Microphone permission
        let micStatus = AVAudioApplication.shared.recordPermission
        switch micStatus {
        case .granted:
            checks.append(ReadinessCheck(
                label: "Microphone",
                icon: "mic.fill",
                status: .ready,
                detail: "Access granted",
                recovery: nil
            ))
        case .denied:
            checks.append(ReadinessCheck(
                label: "Microphone",
                icon: "mic.slash.fill",
                status: .blocked,
                detail: "Access denied",
                recovery: .openSettings
            ))
        case .undetermined:
            checks.append(ReadinessCheck(
                label: "Microphone",
                icon: "mic.fill",
                status: .undetermined,
                detail: "Permission needed",
                recovery: nil
            ))
        @unknown default:
            break
        }

        // 2. Speech recognition
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        switch speechStatus {
        case .authorized:
            checks.append(ReadinessCheck(
                label: "Speech Recognition",
                icon: "waveform",
                status: .ready,
                detail: "Authorized",
                recovery: nil
            ))
        case .denied, .restricted:
            checks.append(ReadinessCheck(
                label: "Speech Recognition",
                icon: "waveform.slash",
                status: .blocked,
                detail: speechStatus == .restricted ? "Restricted" : "Not authorized",
                recovery: .openSettings
            ))
        case .notDetermined:
            checks.append(ReadinessCheck(
                label: "Speech Recognition",
                icon: "waveform",
                status: .undetermined,
                detail: "Permission needed",
                recovery: nil
            ))
        @unknown default:
            break
        }

        // 3. Keyboard mode
        if headlessService.isActive {
            checks.append(ReadinessCheck(
                label: "Keyboard Mode",
                icon: "keyboard",
                status: .ready,
                detail: "Enabled",
                recovery: nil
            ))
        } else {
            checks.append(ReadinessCheck(
                label: "Keyboard Mode",
                icon: "keyboard",
                status: .warning,
                detail: "Disabled",
                recovery: .enableKeyboardMode
            ))
        }

        // 4. Audio session / ready mode
        if headlessService.isInReadyMode || headlessService.isRecording {
            checks.append(ReadinessCheck(
                label: "Audio Session",
                icon: "speaker.wave.2.fill",
                status: .ready,
                detail: headlessService.isRecording ? "Recording" : "Active",
                recovery: nil
            ))
        } else if headlessService.isActive {
            checks.append(ReadinessCheck(
                label: "Audio Session",
                icon: "speaker.wave.2",
                status: .warning,
                detail: "Not active",
                recovery: .retryConnection
            ))
        }

        // 5. State health - check for stuck states
        let state = sharedStore.phase
        let age = sharedStore.phaseAge
        let stuckThreshold: TimeInterval = 30
        let stuckStates: [DictationSharedState.Phase] = [.arming, .stopping, .transcribing]

        if stuckStates.contains(state) && age > stuckThreshold {
            checks.append(ReadinessCheck(
                label: "State Health",
                icon: "exclamationmark.triangle.fill",
                status: .blocked,
                detail: "Stuck in \(state.rawValue) for \(Int(age))s",
                recovery: .forceReset
            ))
        }

        readiness = DictationReadiness(checks: checks)
    }

    // MARK: - Recovery Actions

    func perform(_ action: RecoveryAction) {
        switch action {
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }

        case .enableKeyboardMode:
            headlessService.activate()

        case .retryConnection:
            headlessService.handleDictationRequest()

        case .forceReset:
            bridge.forceReset()
            sharedStore.forceReset(
                reason: "User-initiated reset from readiness UI",
                preserveCapability: true,
                updatedBy: "app"
            )
        }

        // Re-evaluate after action
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.evaluate()
        }
    }
}
