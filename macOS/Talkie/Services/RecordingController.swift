//
//  RecordingController.swift
//  Talkie
//
//  Recording state management for interactive dictation
//  Adapted from TalkieLive's RecordingOverlayController
//

import SwiftUI
import TalkieKit
import AVFoundation
import Observation

// MARK: - Recording Controller

@MainActor
@Observable
final class RecordingController {
    static let shared = RecordingController()

    var state: LiveState = .idle
    var elapsedTime: TimeInterval = 0
    var transcript: String = ""

    @ObservationIgnored
    private var timer: Timer?
    @ObservationIgnored
    private var startTime: Date?
    @ObservationIgnored
    private var audioRecorder: AVAudioRecorder?
    @ObservationIgnored
    private var audioURL: URL?

    private init() {}

    /// Start recording
    func startRecording() {
        // Check if engine is available
        guard TalkieServiceMonitor.shared.state == .running else {
            // Show one-time toast: "TalkieEngine needed. [Launch Now] [Cancel]"
            NotificationCenter.default.post(name: .showEngineRequiredToast, object: nil)
            return
        }

        // Update state
        updateState(.listening)

        // Setup audio recording
        setupAudioRecording()

        // Start timer for elapsed time
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startTime else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }

        // Start recording
        audioRecorder?.record()
    }

    /// Stop recording and transcribe
    func stopRecording() {
        audioRecorder?.stop()

        timer?.invalidate()
        timer = nil

        // Transition to transcribing
        updateState(.transcribing)

        // Send to TalkieEngine for transcription
        Task {
            await transcribeRecording()
        }
    }

    /// Cancel recording
    func cancelRecording() {
        audioRecorder?.stop()
        audioRecorder = nil

        timer?.invalidate()
        timer = nil
        startTime = nil
        elapsedTime = 0
        transcript = ""

        // Clean up audio file
        if let audioURL = audioURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
        audioURL = nil

        updateState(.idle)
    }

    /// Toggle recording (start if idle, stop if listening)
    func toggleRecording() {
        switch state {
        case .idle:
            startRecording()
        case .listening:
            stopRecording()
        default:
            // Can't toggle during transcribing/routing
            break
        }
    }

    func updateState(_ state: LiveState) {
        self.state = state
    }

    func updateTranscript(_ text: String) {
        self.transcript = text
    }

    // MARK: - Private Methods

    private func setupAudioRecording() {
        // Create temp file for audio
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "talkie-recording-\(UUID().uuidString).m4a"
        let url = tempDir.appendingPathComponent(filename)
        self.audioURL = url

        // Note: macOS doesn't use AVAudioSession (iOS only)
        // AVAudioRecorder works directly on macOS

        // Create recorder
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.prepareToRecord()
        } catch {
            print("Failed to create audio recorder: \(error)")
        }
    }

    private func transcribeRecording() async {
        guard let audioURL = audioURL else {
            updateState(.idle)
            return
        }

        do {
            // Use Talkie's EngineClient to transcribe
            let text = try await EngineClient.shared.transcribe(audioPath: audioURL.path)

            // Update transcript
            await MainActor.run {
                self.transcript = text
                updateState(.routing)
            }

            // Route the transcript (paste or clipboard)
            await routeTranscript(text)

            // Show success briefly, then return to idle
            try? await Task.sleep(for: .milliseconds(500))
            await MainActor.run {
                updateState(.idle)
                self.transcript = ""
                self.elapsedTime = 0
            }

            // Clean up audio file
            try? FileManager.default.removeItem(at: audioURL)
            self.audioURL = nil

        } catch {
            print("Transcription failed: \(error)")
            await MainActor.run {
                updateState(.idle)
                self.transcript = ""
                self.elapsedTime = 0
            }
        }
    }

    private func routeTranscript(_ text: String) async {
        // Get routing mode from settings
        let mode = LiveSettings.shared.routingMode

        switch mode {
        case .paste:
            // Paste into active app
            await pasteText(text)
        case .clipboardOnly:
            // Copy to clipboard only
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    private func pasteText(_ text: String) async {
        // Copy to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        // Wait briefly for clipboard
        try? await Task.sleep(for: .milliseconds(50))

        // Simulate Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)

        vKeyDown?.flags = .maskCommand
        vKeyUp?.flags = .maskCommand

        vKeyDown?.post(tap: .cghidEventTap)
        vKeyUp?.post(tap: .cghidEventTap)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showEngineRequiredToast = Notification.Name("showEngineRequiredToast")
    static let toggleRecording = Notification.Name("toggleRecording")
}
