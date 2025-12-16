//
//  AudioCapture.swift
//  TalkieLive
//
//  Real microphone capture using AVAudioEngine
//

import AVFoundation
import AppKit
import Combine
import CoreAudio
import os.log

private let logger = Logger(subsystem: "jdi.talkie.live", category: "AudioCapture")

/// Shared audio level for UI visualization and silent mic detection
@MainActor
final class AudioLevelMonitor: ObservableObject {
    static let shared = AudioLevelMonitor()

    @Published var level: Float = 0
    @Published var isSilent: Bool = false  // True when mic appears silent during recording
    @Published var selectedMicName: String = "System Default"

    // Silent detection settings
    private let silenceThreshold: Float = 0.02  // Level below this is considered silent
    private let silenceWindowSeconds: TimeInterval = 2.0  // How long silence before warning
    private var silentSampleCount: Int = 0
    private var totalSampleCount: Int = 0
    private let samplesPerSecond: Int = 10  // Approximate samples per second

    private var cancellables = Set<AnyCancellable>()

    private init() {
        refreshMicName()

        // Listen for device changes
        AudioDeviceManager.shared.$inputDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshMicName()
            }
            .store(in: &cancellables)

        // Listen for settings changes (user changed mic selection)
        LiveSettings.shared.$selectedMicrophoneID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshMicName()
            }
            .store(in: &cancellables)
    }

    /// Call on each level update during recording
    func updateLevel(_ newLevel: Float, isRecording: Bool) {
        level = newLevel

        if isRecording {
            totalSampleCount += 1

            if newLevel < silenceThreshold {
                silentSampleCount += 1
            } else {
                // Reset if we get any audio
                silentSampleCount = 0
                if isSilent {
                    isSilent = false
                }
            }

            // Check if we've been silent for the window duration
            let windowSamples = Int(silenceWindowSeconds) * samplesPerSecond
            if silentSampleCount >= windowSamples && !isSilent {
                isSilent = true
                playAlertSound()
            }
        }
    }

    /// Reset silence tracking when recording starts/stops
    func resetSilenceTracking() {
        silentSampleCount = 0
        totalSampleCount = 0
        isSilent = false
    }

    /// Refresh the displayed mic name from current selection
    func refreshMicName() {
        Task { @MainActor in
            let deviceManager = AudioDeviceManager.shared
            let selectedID = deviceManager.selectedDeviceID

            if let device = deviceManager.inputDevices.first(where: { $0.id == selectedID }) {
                selectedMicName = device.name
            } else if let defaultDevice = deviceManager.inputDevices.first(where: { $0.isDefault }) {
                selectedMicName = defaultDevice.name
            } else {
                selectedMicName = "No Microphone"
            }
        }
    }

    private func playAlertSound() {
        // Play system alert sound
        NSSound.beep()
    }
}

final class MicrophoneCapture: LiveAudioCapture {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var onChunk: ((String) -> Void)?  // Callback receives file path
    private var isCapturing = false
    private var fileCreated = false

    /// Callback for capture failure - called on main thread
    var onCaptureError: ((String) -> Void)?

    func startCapture(onChunk: @escaping (String) -> Void) {
        guard !isCapturing else {
            logger.warning("Already capturing")
            return
        }

        self.onChunk = onChunk
        self.fileCreated = false

        // Set the selected input device before accessing inputNode
        setInputDevice()

        // Reset silence tracking for new recording
        Task { @MainActor in
            AudioLevelMonitor.shared.resetSilenceTracking()
            AudioLevelMonitor.shared.refreshMicName()
        }

        let inputNode = engine.inputNode

        // Prepare temp file URL
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        self.tempFileURL = fileURL

        // Install tap with nil format - we'll create the file lazily based on actual buffer format
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Create file lazily on first buffer - ensures format matches exactly
            if !self.fileCreated {
                self.createAudioFile(matching: buffer)
            }

            guard let audioFile = self.audioFile else { return }

            // Write to file
            do {
                try audioFile.write(from: buffer)
            } catch {
                logger.error("Failed to write audio buffer: \(error.localizedDescription)")
            }

            // Calculate RMS level for visualization and silence detection
            let level = self.calculateRMSLevel(buffer: buffer)
            Task { @MainActor in
                AudioLevelMonitor.shared.updateLevel(level, isRecording: true)
            }
        }

        do {
            try engine.start()
            isCapturing = true
            logger.info("Microphone capture started")
        } catch {
            logger.error("Failed to start audio engine: \(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
            tempFileURL = nil
            fileCreated = false

            // Notify about the failure
            let errorMsg = error.localizedDescription
            Task { @MainActor [weak self] in
                self?.onCaptureError?(errorMsg)
            }
        }
    }

    private func createAudioFile(matching buffer: AVAudioPCMBuffer) {
        guard let fileURL = tempFileURL else { return }

        let format = buffer.format
        logger.info("Actual buffer format: \(format.sampleRate)Hz, \(format.channelCount)ch, \(format.commonFormat.rawValue)")

        // Create file with AAC encoding matching the actual buffer format
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: settings)
            fileCreated = true
            logger.info("Created audio file: \(format.sampleRate)Hz, \(format.channelCount)ch")
        } catch {
            logger.error("Failed to create audio file: \(error.localizedDescription)")
        }
    }

    private func calculateRMSLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }

        let channelDataValue = channelData.pointee
        let frameLength = Int(buffer.frameLength)

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelDataValue[i]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameLength))
        // Aggressive amplification for better visual response
        let level = min(1.0, rms * 8.0)
        return level
    }

    func stopCapture() {
        guard isCapturing else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false

        // Reset audio level and silence tracking
        Task { @MainActor in
            AudioLevelMonitor.shared.level = 0
            AudioLevelMonitor.shared.resetSilenceTracking()
        }

        // Close the audio file
        audioFile = nil

        // Deliver the file path - caller is responsible for cleanup after transcription
        if let fileURL = tempFileURL {
            // Check file size to validate recording
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let size = attrs[.size] as? Int {
                logger.info("Captured audio file: \(fileURL.lastPathComponent) (\(size) bytes)")

                if size > 1000 {
                    onChunk?(fileURL.path)  // Pass path, not data - engine reads directly
                } else {
                    logger.warning("Audio file too small (\(size) bytes), likely empty recording")
                    try? FileManager.default.removeItem(at: fileURL)
                }
            } else {
                logger.error("Failed to get audio file attributes")
                try? FileManager.default.removeItem(at: fileURL)
            }
        } else {
            logger.warning("No temp file URL - file may not have been created")
        }

        tempFileURL = nil
        onChunk = nil
        fileCreated = false
        logger.info("Microphone capture stopped")
    }

    /// Set the input device on the audio engine's input node
    private func setInputDevice() {
        // Read directly from UserDefaults to avoid MainActor isolation
        let selectedID = UInt32(UserDefaults.standard.integer(forKey: "selectedMicrophoneID"))
        guard selectedID != 0 else {
            logger.info("Using system default microphone")
            return
        }

        // Get the audio unit from the engine's input node
        let inputNode = engine.inputNode
        let audioUnit = inputNode.audioUnit

        guard let audioUnit = audioUnit else {
            logger.warning("Could not get audio unit from input node")
            return
        }

        // Set the input device
        var deviceID = selectedID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status == noErr {
            logger.info("Set input device to: \(selectedID)")
        } else {
            logger.warning("Failed to set input device: \(status)")
        }
    }
}
