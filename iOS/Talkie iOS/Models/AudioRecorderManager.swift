//
//  AudioRecorderManager.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import Foundation
import AVFoundation
import SwiftUI
import Combine

class AudioRecorderManager: NSObject, ObservableObject {

    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevels: [Float] = []
    @Published var currentRecordingURL: URL?
    @Published var isInterrupted = false

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var levelTimer: Timer?
    private var lastDisplayLevel: Float = 0.02  // Track last level for decay
    private var wasRecordingBeforeInterruption = false

    override init() {
        super.init()
        setupAudioSession()
        setupNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupAudioSession() {
        configureAudioSession()
    }

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Check if Bluetooth/headphones are connected
            let currentRoute = audioSession.currentRoute
            let hasExternalOutput = currentRoute.outputs.contains { output in
                [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .headphones, .airPlay].contains(output.portType)
            }

            // Configure options based on current audio route
            var options: AVAudioSession.CategoryOptions = [.allowBluetooth, .allowBluetoothA2DP]

            if !hasExternalOutput {
                // No headphones/Bluetooth - use main speaker instead of earpiece
                options.insert(.defaultToSpeaker)
            }
            // When external output is connected, don't use .defaultToSpeaker
            // This allows audio to properly route to Bluetooth/headphones

            try audioSession.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: options
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            AppLogger.recording.info("Audio session configured - external output: \(hasExternalOutput)")
        } catch {
            AppLogger.recording.error("Failed to set up audio session: \(error.localizedDescription)")
        }
    }

    private func setupNotifications() {
        // Handle audio session interruptions (phone calls, alarms, etc.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )

        // Handle audio route changes (headphones plugged/unplugged)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )

        // Handle app going to background/foreground
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            // Interruption began (phone call, alarm, etc.)
            AppLogger.recording.warning("Audio session interrupted")
            wasRecordingBeforeInterruption = isRecording
            if isRecording {
                // Pause recording - the system will stop the recorder
                isInterrupted = true
                audioRecorder?.pause()
                timer?.invalidate()
                levelTimer?.invalidate()
            }

        case .ended:
            // Interruption ended
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)

            if options.contains(.shouldResume) && wasRecordingBeforeInterruption {
                AppLogger.recording.info("Resuming recording after interruption")
                // Reactivate session and resume
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    audioRecorder?.record()
                    startTimers()
                    isInterrupted = false
                } catch {
                    AppLogger.recording.error("Failed to resume after interruption: \(error)")
                }
            }

        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            // Headphones/Bluetooth unplugged - reconfigure to use speaker
            AppLogger.recording.info("Audio route changed: device unavailable, reconfiguring...")
            configureAudioSession()
        case .newDeviceAvailable:
            // New headphones/Bluetooth connected - reconfigure to use them
            AppLogger.recording.info("Audio route changed: new device available, reconfiguring...")
            configureAudioSession()
        case .categoryChange, .override, .routeConfigurationChange:
            AppLogger.recording.debug("Audio route changed: \(reason.rawValue)")
        default:
            break
        }
    }

    @objc private func handleAppWillResignActive() {
        if isRecording {
            AppLogger.recording.info("App going to background while recording - continuing...")
            // Recording continues in background due to UIBackgroundModes audio
        }
    }

    @objc private func handleAppDidBecomeActive() {
        if isRecording {
            AppLogger.recording.info("App returned to foreground - recording still active")
        }
    }

    func startRecording() {
        // Ensure audio session is active before recording
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            AppLogger.recording.error("Failed to activate audio session: \(error)")
        }

        let audioFilename = getDocumentsDirectory().appendingPathComponent("\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128000
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true

            if audioRecorder?.record() == true {
                AppLogger.recording.info("Recording started at: \(audioFilename.path)")
                currentRecordingURL = audioFilename
                isRecording = true
                isInterrupted = false
                recordingDuration = 0
                audioLevels = []
                lastDisplayLevel = 0.02  // Reset decay tracker

                startTimers()
            } else {
                AppLogger.recording.error("Failed to start recording - record() returned false")
            }

        } catch {
            AppLogger.recording.error("Failed to start recording: \(error.localizedDescription)")
        }
    }

    private func startTimers() {
        // Invalidate existing timers first
        timer?.invalidate()
        levelTimer?.invalidate()

        // Start duration timer - use RunLoop.common to work in background
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.recordingDuration = self.audioRecorder?.currentTime ?? 0
            }
        }
        RunLoop.current.add(timer!, forMode: .common)

        // Start level monitoring timer - faster updates for responsive visualization (~60fps)
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.updateAudioLevels()
        }
        RunLoop.current.add(levelTimer!, forMode: .common)
    }

    func stopRecording() {
        audioRecorder?.stop()
        timer?.invalidate()
        timer = nil
        levelTimer?.invalidate()
        levelTimer = nil
        isRecording = false
        isInterrupted = false
        wasRecordingBeforeInterruption = false

        if let url = currentRecordingURL {
            let fileExists = FileManager.default.fileExists(atPath: url.path)
            AppLogger.recording.info("Recording stopped. File exists: \(fileExists) at \(url.path)")

            if fileExists {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    let fileSize = attributes[.size] as? Int64 ?? 0
                    AppLogger.recording.debug("File size: \(fileSize) bytes")
                } catch {
                    AppLogger.recording.warning("Could not get file attributes: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Resume recording after an interruption
    func resumeRecording() {
        guard isInterrupted, audioRecorder != nil else { return }

        do {
            try AVAudioSession.sharedInstance().setActive(true)
            audioRecorder?.record()
            startTimers()
            isInterrupted = false
            AppLogger.recording.info("Recording resumed")
        } catch {
            AppLogger.recording.error("Failed to resume recording: \(error)")
        }
    }

    private func updateAudioLevels() {
        audioRecorder?.updateMeters()

        let power = audioRecorder?.averagePower(forChannel: 0) ?? -160

        // Simple linear mapping from dB to 0-1
        // -50 dB = silence, 0 dB = max
        let normalized = (power + 50) / 50
        let clampedLevel = min(1.0, max(0.0, normalized))

        // Smooth decay only
        let decayRate: Float = 0.4

        let displayLevel: Float
        if clampedLevel >= lastDisplayLevel {
            displayLevel = clampedLevel
        } else {
            displayLevel = lastDisplayLevel - (lastDisplayLevel - clampedLevel) * decayRate
        }

        lastDisplayLevel = max(0.0, displayLevel)
        audioLevels.append(lastDisplayLevel)

        if audioLevels.count > 1200 {
            audioLevels.removeFirst()
        }
    }

    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func getAudioDuration(url: URL) -> TimeInterval {
        // Use AVAudioFile for synchronous duration (local files only)
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            return duration
        } catch {
            return 0
        }
    }
}

extension AudioRecorderManager: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            AppLogger.recording.error("Recording failed")
        }
    }
}
