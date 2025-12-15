//
//  AudioDiagnostics.swift
//  TalkieLive
//
//  Audio troubleshooting diagnostics and recovery tools
//

import Foundation
import AVFoundation
import AppKit
import os.log

private let logger = Logger(subsystem: "jdi.talkie.live", category: "AudioDiagnostics")

// MARK: - Diagnostic Check Item

struct DiagnosticCheck: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let status: CheckStatus
    let icon: String

    enum CheckStatus {
        case passed
        case warning
        case failed
        case info

        var color: String {
            switch self {
            case .passed: return "green"
            case .warning: return "yellow"
            case .failed: return "red"
            case .info: return "blue"
            }
        }

        var systemIcon: String {
            switch self {
            case .passed: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .failed: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }
}

// MARK: - Diagnostic Result

struct AudioDiagnosticResult {
    let inputVolume: Int  // 0-100
    let defaultInputDevice: String?
    let selectedDevice: String?
    let deviceCount: Int
    let hasVirtualDevices: Bool
    let engineRunning: Bool
    let possibleIssues: [AudioIssue]
    let suggestedFixes: [AudioFix]
    let checks: [DiagnosticCheck]  // Detailed checklist
    let overallStatus: DiagnosticCheck.CheckStatus
}

enum AudioIssue: Equatable {
    case lowInputVolume(Int)  // Current volume level
    case noInputDevice
    case virtualDeviceSelected
    case engineNotRunning
    case sampleRateMismatch
    case permissionDenied

    var description: String {
        switch self {
        case .lowInputVolume(let level):
            return "Input volume is low (\(level)%)"
        case .noInputDevice:
            return "No input device detected"
        case .virtualDeviceSelected:
            return "Virtual audio device selected (may not capture mic)"
        case .engineNotRunning:
            return "Audio engine not running"
        case .sampleRateMismatch:
            return "Sample rate mismatch between devices"
        case .permissionDenied:
            return "Microphone permission not granted"
        }
    }

    var icon: String {
        switch self {
        case .lowInputVolume: return "speaker.wave.1"
        case .noInputDevice: return "mic.slash"
        case .virtualDeviceSelected: return "waveform.badge.exclamationmark"
        case .engineNotRunning: return "exclamationmark.triangle"
        case .sampleRateMismatch: return "arrow.triangle.2.circlepath"
        case .permissionDenied: return "lock.shield"
        }
    }
}

enum AudioFix: Identifiable {
    case boostInputVolume
    case restartAudioDaemon
    case switchToDefaultMic
    case openSystemSettings
    case grantPermission
    case unplugReplug  // The classic IT fix

    var id: String {
        switch self {
        case .boostInputVolume: return "boost"
        case .restartAudioDaemon: return "restart"
        case .switchToDefaultMic: return "switch"
        case .openSystemSettings: return "settings"
        case .grantPermission: return "permission"
        case .unplugReplug: return "unplug"
        }
    }

    var title: String {
        switch self {
        case .boostInputVolume: return "Boost Input Volume"
        case .restartAudioDaemon: return "Reset Audio System"
        case .switchToDefaultMic: return "Use Default Microphone"
        case .openSystemSettings: return "Open Sound Settings"
        case .grantPermission: return "Grant Mic Permission"
        case .unplugReplug: return "Unplug & Replug Microphone"
        }
    }

    var description: String {
        switch self {
        case .boostInputVolume:
            return "Set system input volume to maximum"
        case .restartAudioDaemon:
            return "Restart macOS audio daemon (fixes most issues)"
        case .switchToDefaultMic:
            return "Switch to the system default microphone"
        case .openSystemSettings:
            return "Open System Settings to check audio configuration"
        case .grantPermission:
            return "Open Privacy settings to grant microphone access"
        case .unplugReplug:
            return "Physically unplug your USB mic, wait 3 seconds, then plug it back in"
        }
    }

    var icon: String {
        switch self {
        case .boostInputVolume: return "speaker.wave.3"
        case .restartAudioDaemon: return "arrow.clockwise"
        case .switchToDefaultMic: return "mic"
        case .openSystemSettings: return "gear"
        case .grantPermission: return "lock.open"
        case .unplugReplug: return "cable.connector"
        }
    }

    var isPrimary: Bool {
        switch self {
        case .restartAudioDaemon: return true
        default: return false
        }
    }

    var isManual: Bool {
        switch self {
        case .unplugReplug: return true
        default: return false
        }
    }

    var stepNumber: Int {
        switch self {
        case .boostInputVolume: return 1
        case .restartAudioDaemon: return 2
        case .switchToDefaultMic: return 3
        case .openSystemSettings: return 4
        case .grantPermission: return 5
        case .unplugReplug: return 6  // Always last resort
        }
    }
}

// MARK: - Audio Diagnostics Manager

@MainActor
final class AudioDiagnostics: ObservableObject {
    static let shared = AudioDiagnostics()

    @Published var isRunningDiagnostics = false
    @Published var lastResult: AudioDiagnosticResult?
    @Published var isApplyingFix = false
    @Published var fixInProgress: AudioFix?
    @Published var lastFixResult: FixResult?

    struct FixResult {
        let fix: AudioFix
        let success: Bool
        let message: String
    }

    private init() {}

    // MARK: - Run Diagnostics

    func runDiagnostics() async -> AudioDiagnosticResult {
        isRunningDiagnostics = true
        defer { isRunningDiagnostics = false }

        // Gather diagnostic info
        let inputVolume = getInputVolume()
        let deviceManager = AudioDeviceManager.shared
        let selectedDevice = deviceManager.inputDevices.first { $0.id == deviceManager.selectedDeviceID }
        let defaultDevice = deviceManager.inputDevices.first { $0.isDefault }

        // Check for virtual devices
        let virtualDeviceNames = ["BlackHole", "Teams Audio", "Speaker Audio Recorder", "Loopback", "Soundflower"]
        let hasVirtualDevices = deviceManager.inputDevices.contains { device in
            virtualDeviceNames.contains { device.name.contains($0) }
        }

        // Build the checklist
        var checks: [DiagnosticCheck] = []
        var issues: [AudioIssue] = []
        var fixes: [AudioFix] = []

        // 1. Check microphone permission
        let permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if permissionStatus == .authorized {
            checks.append(DiagnosticCheck(
                name: "Microphone Permission",
                detail: "TalkieLive has permission to access the microphone",
                status: .passed,
                icon: "lock.open"
            ))
        } else {
            checks.append(DiagnosticCheck(
                name: "Microphone Permission",
                detail: permissionStatus == .denied ? "Permission denied" : "Permission not yet granted",
                status: .failed,
                icon: "lock"
            ))
            issues.append(.permissionDenied)
            fixes.append(.grantPermission)
        }

        // 2. Check if input devices exist
        if !deviceManager.inputDevices.isEmpty {
            checks.append(DiagnosticCheck(
                name: "Input Devices",
                detail: "\(deviceManager.inputDevices.count) device(s) available",
                status: .passed,
                icon: "mic"
            ))
        } else {
            checks.append(DiagnosticCheck(
                name: "Input Devices",
                detail: "No input devices detected",
                status: .failed,
                icon: "mic.slash"
            ))
            issues.append(.noInputDevice)
            fixes.append(.openSystemSettings)
        }

        // 3. Check selected device
        if let device = selectedDevice ?? defaultDevice {
            let isVirtual = virtualDeviceNames.contains { device.name.contains($0) }
            if isVirtual {
                checks.append(DiagnosticCheck(
                    name: "Selected Microphone",
                    detail: "\(device.name) (virtual device)",
                    status: .warning,
                    icon: "waveform.badge.exclamationmark"
                ))
                issues.append(.virtualDeviceSelected)
                fixes.append(.switchToDefaultMic)
            } else {
                checks.append(DiagnosticCheck(
                    name: "Selected Microphone",
                    detail: device.name,
                    status: .passed,
                    icon: "mic.fill"
                ))
            }
        } else {
            checks.append(DiagnosticCheck(
                name: "Selected Microphone",
                detail: "No microphone selected",
                status: .failed,
                icon: "mic.slash"
            ))
        }

        // 4. Check input volume
        if inputVolume >= 80 {
            checks.append(DiagnosticCheck(
                name: "Input Volume",
                detail: "\(inputVolume)% - Good",
                status: .passed,
                icon: "speaker.wave.3"
            ))
        } else if inputVolume >= 50 {
            checks.append(DiagnosticCheck(
                name: "Input Volume",
                detail: "\(inputVolume)% - Could be higher",
                status: .warning,
                icon: "speaker.wave.2"
            ))
            fixes.append(.boostInputVolume)
        } else {
            checks.append(DiagnosticCheck(
                name: "Input Volume",
                detail: "\(inputVolume)% - Too low",
                status: .failed,
                icon: "speaker.wave.1"
            ))
            issues.append(.lowInputVolume(inputVolume))
            fixes.append(.boostInputVolume)
        }

        // 5. Check for USB connection (info only)
        if let device = selectedDevice ?? defaultDevice {
            let isUSB = device.name.lowercased().contains("usb") ||
                        device.name.contains("ATR") ||  // Audio-Technica
                        device.name.contains("Blue") ||  // Blue microphones
                        device.name.contains("Yeti") ||
                        device.name.contains("Shure") ||
                        device.name.contains("Rode")
            if isUSB {
                checks.append(DiagnosticCheck(
                    name: "USB Connection",
                    detail: "USB microphone detected",
                    status: .info,
                    icon: "cable.connector"
                ))
            }
        }

        // 6. Check audio daemon health (we infer from the checks)
        let hasAudioIssues = issues.contains(where: { issue in
            if case .lowInputVolume = issue { return true }
            return false
        })
        if hasAudioIssues {
            checks.append(DiagnosticCheck(
                name: "Audio System",
                detail: "May need reset (coreaudiod)",
                status: .warning,
                icon: "arrow.clockwise"
            ))
        } else {
            checks.append(DiagnosticCheck(
                name: "Audio System",
                detail: "Running normally",
                status: .passed,
                icon: "checkmark.seal"
            ))
        }

        // Build fix list in priority order
        if !fixes.contains(.boostInputVolume) && inputVolume < 100 {
            // Always offer volume boost as first try
            fixes.insert(.boostInputVolume, at: 0)
        }

        // Add standard fixes
        if !fixes.contains(.restartAudioDaemon) {
            fixes.append(.restartAudioDaemon)
        }
        if !fixes.contains(.openSystemSettings) {
            fixes.append(.openSystemSettings)
        }

        // Always add unplug/replug as the last resort
        fixes.append(.unplugReplug)

        // Remove duplicates while preserving order
        var seenFixes = Set<String>()
        fixes = fixes.filter { fix in
            if seenFixes.contains(fix.id) { return false }
            seenFixes.insert(fix.id)
            return true
        }

        // Sort by step number
        fixes.sort { $0.stepNumber < $1.stepNumber }

        // Determine overall status
        let overallStatus: DiagnosticCheck.CheckStatus
        if checks.contains(where: { $0.status == .failed }) {
            overallStatus = .failed
        } else if checks.contains(where: { $0.status == .warning }) {
            overallStatus = .warning
        } else {
            overallStatus = .passed
        }

        let result = AudioDiagnosticResult(
            inputVolume: inputVolume,
            defaultInputDevice: defaultDevice?.name,
            selectedDevice: selectedDevice?.name,
            deviceCount: deviceManager.inputDevices.count,
            hasVirtualDevices: hasVirtualDevices,
            engineRunning: true,
            possibleIssues: issues,
            suggestedFixes: fixes,
            checks: checks,
            overallStatus: overallStatus
        )

        lastResult = result
        logger.info("Diagnostics complete: \(issues.count) issues, \(checks.count) checks")
        return result
    }

    // MARK: - Apply Fixes

    func applyFix(_ fix: AudioFix) async -> FixResult {
        isApplyingFix = true
        fixInProgress = fix
        defer {
            isApplyingFix = false
            fixInProgress = nil
        }

        let result: FixResult

        switch fix {
        case .boostInputVolume:
            result = await boostInputVolume()

        case .restartAudioDaemon:
            result = await restartAudioDaemon()

        case .switchToDefaultMic:
            result = switchToDefaultMic()

        case .openSystemSettings:
            result = openSystemSettings()

        case .grantPermission:
            result = openPrivacySettings()

        case .unplugReplug:
            // This is a manual step - just show instructions
            result = FixResult(
                fix: .unplugReplug,
                success: true,
                message: "Unplug your microphone, wait 3 seconds, then plug it back in"
            )
        }

        lastFixResult = result

        // Re-run diagnostics after applying fix
        if result.success {
            _ = await runDiagnostics()
        }

        return result
    }

    // MARK: - Individual Fixes

    private func getInputVolume() -> Int {
        let script = "input volume of (get volume settings)"
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let volume = Int(output) {
                return volume
            }
        } catch {
            logger.error("Failed to get input volume: \(error.localizedDescription)")
        }

        return 0
    }

    private func boostInputVolume() async -> FixResult {
        logger.info("Boosting input volume to 100")

        let script = "set volume input volume 100"
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                return FixResult(fix: .boostInputVolume, success: true, message: "Input volume set to maximum")
            } else {
                return FixResult(fix: .boostInputVolume, success: false, message: "Failed to set input volume")
            }
        } catch {
            logger.error("Failed to boost input volume: \(error.localizedDescription)")
            return FixResult(fix: .boostInputVolume, success: false, message: error.localizedDescription)
        }
    }

    private func restartAudioDaemon() async -> FixResult {
        logger.info("Restarting coreaudiod")

        // Kill coreaudiod - it will auto-respawn
        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["coreaudiod"]

        do {
            try task.run()
            task.waitUntilExit()

            // Wait for daemon to respawn
            try await Task.sleep(for: .seconds(2))

            // Boost input volume after restart
            _ = await boostInputVolume()

            return FixResult(
                fix: .restartAudioDaemon,
                success: true,
                message: "Audio system reset complete. Try recording again."
            )
        } catch {
            logger.error("Failed to restart audio daemon: \(error.localizedDescription)")
            return FixResult(
                fix: .restartAudioDaemon,
                success: false,
                message: "Could not restart audio. Try: killall coreaudiod in Terminal"
            )
        }
    }

    private func switchToDefaultMic() -> FixResult {
        logger.info("Switching to default microphone")

        let deviceManager = AudioDeviceManager.shared
        if let defaultDevice = deviceManager.inputDevices.first(where: { $0.isDefault }) {
            // Clear the selected mic so it uses system default
            LiveSettings.shared.selectedMicrophoneID = 0
            AudioLevelMonitor.shared.refreshMicName()

            return FixResult(
                fix: .switchToDefaultMic,
                success: true,
                message: "Switched to \(defaultDevice.name)"
            )
        } else {
            return FixResult(
                fix: .switchToDefaultMic,
                success: false,
                message: "No default microphone found"
            )
        }
    }

    private func openSystemSettings() -> FixResult {
        logger.info("Opening System Settings > Sound")

        // Open Sound preferences pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.sound") {
            NSWorkspace.shared.open(url)
            return FixResult(
                fix: .openSystemSettings,
                success: true,
                message: "Opening Sound settings..."
            )
        }
        return FixResult(
            fix: .openSystemSettings,
            success: false,
            message: "Could not open System Settings"
        )
    }

    private func openPrivacySettings() -> FixResult {
        logger.info("Opening Privacy settings for microphone")

        // Open Privacy & Security > Microphone
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
            return FixResult(
                fix: .grantPermission,
                success: true,
                message: "Opening Privacy settings..."
            )
        }
        return FixResult(
            fix: .grantPermission,
            success: false,
            message: "Could not open Privacy settings"
        )
    }

    // MARK: - Quick Fix (One-tap solution)

    /// Attempts the most likely fixes in sequence
    func quickFix() async -> FixResult {
        logger.info("Running quick fix sequence")

        // 1. First boost volume
        let volumeResult = await boostInputVolume()

        // 2. If we had issues before, restart audio daemon
        if let lastResult = lastResult, !lastResult.possibleIssues.isEmpty {
            let daemonResult = await restartAudioDaemon()
            return daemonResult
        }

        return volumeResult
    }
}
