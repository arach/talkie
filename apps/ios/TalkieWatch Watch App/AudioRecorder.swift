//
//  AudioRecorder.swift
//  TalkieWatch
//
//  Simple audio recording for watchOS with level metering
//

import Foundation
import AVFoundation

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var currentLevel: Float = 0  // 0.0 to 1.0 for visualization

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var timer: Timer?
    private var stopContinuation: CheckedContinuation<URL?, Never>?
    private var finalizationTimeoutTask: Task<Void, Never>?
    private var discardRecordingOnFinish = false

    private let fileManager = FileManager.default

    override init() {
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch {
            WatchConsole.info("[Watch] Audio session setup failed: \(error)")
        }
    }

    func startRecording() {
        guard audioRecorder == nil, stopContinuation == nil else {
            WatchConsole.info("[Watch] Recording start ignored while the previous file is finalizing")
            return
        }

        // Generate unique filename
        let filename = "talkie_\(Int(Date().timeIntervalSince1970)).m4a"
        let tempDir = fileManager.temporaryDirectory
        recordingURL = tempDir.appendingPathComponent(filename)

        guard let url = recordingURL else { return }

        // Recording settings optimized for speech
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true  // Enable metering
            guard recorder.record() else {
                WatchConsole.info("[Watch] Recording failed to start: AVAudioRecorder rejected the request")
                recordingURL = nil
                return
            }
            audioRecorder = recorder
            isRecording = true
            isPaused = false
            recordingDuration = 0
            currentLevel = 0

            // Update duration and level timer
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self, let recorder = self.audioRecorder else { return }

                    self.recordingDuration = recorder.currentTime

                    guard !self.isPaused else {
                        self.currentLevel = 0
                        return
                    }

                    // Update audio level
                    recorder.updateMeters()
                    let db = recorder.averagePower(forChannel: 0)
                    // Convert dB (-160 to 0) to 0.0-1.0 range
                    // Typical speech is around -30 to -10 dB
                    let normalizedLevel = max(0, min(1, (db + 50) / 50))
                    self.currentLevel = normalizedLevel
                }
            }

            let inputRoute = AVAudioSession.sharedInstance().currentRoute.inputs
                .map { "\($0.portName) [\($0.portType.rawValue)]" }
                .joined(separator: ", ")
            WatchConsole.info(
                "[Watch] Recording started: \(url.lastPathComponent); input: "
                    + (inputRoute.isEmpty ? "system-selected Watch input" : inputRoute)
            )
        } catch {
            WatchConsole.info("[Watch] Recording failed to start: \(error)")
        }
    }

    /// Pause or resume the current file without ending the capture session.
    /// `isRecording` stays true while paused because the recording still owns
    /// the active file and can be finished and sent normally.
    @discardableResult
    func togglePause() -> Bool {
        guard let recorder = audioRecorder else { return false }

        if isPaused {
            guard recorder.record() else {
                WatchConsole.info("[Watch] Recording failed to resume")
                return false
            }
            isPaused = false
        } else {
            guard recorder.isRecording else { return false }
            recorder.pause()
            isPaused = true
            currentLevel = 0
        }

        return true
    }

    func stopRecording() async -> URL? {
        timer?.invalidate()
        timer = nil

        isRecording = false
        isPaused = false
        currentLevel = 0

        guard let recorder = audioRecorder, recordingURL != nil else {
            return nil
        }

        discardRecordingOnFinish = false
        return await withCheckedContinuation { continuation in
            stopContinuation = continuation
            finalizationTimeoutTask?.cancel()
            finalizationTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.finishRecording(
                    recorder,
                    successfully: false,
                    reason: "finalization timed out"
                )
            }
            recorder.stop()
        }
    }

    func cancelRecording() {
        timer?.invalidate()
        timer = nil

        discardRecordingOnFinish = true
        audioRecorder?.stop()
        isRecording = false
        isPaused = false
        currentLevel = 0
        recordingDuration = 0
    }

    private func finishRecording(
        _ recorder: AVAudioRecorder,
        successfully: Bool,
        reason: String? = nil
    ) {
        guard audioRecorder === recorder else { return }

        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = nil

        let url = recordingURL
        let shouldDiscard = discardRecordingOnFinish
        discardRecordingOnFinish = false
        audioRecorder = nil
        recordingURL = nil
        isPaused = false

        guard let continuation = stopContinuation else {
            if shouldDiscard, let url {
                try? fileManager.removeItem(at: url)
            }
            return
        }
        stopContinuation = nil

        guard successfully, !shouldDiscard, let url else {
            WatchConsole.info("[Watch] Recording did not finalize: \(reason ?? "recorder reported failure")")
            if let url { try? fileManager.removeItem(at: url) }
            continuation.resume(returning: nil)
            return
        }

        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            let byteCount = values.fileSize ?? 0
            guard byteCount > 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            _ = try AVAudioFile(forReading: url)
            WatchConsole.info(
                "[Watch] Recording finalized and validated: \(url.lastPathComponent) (\(byteCount) bytes)"
            )
            continuation.resume(returning: url)
        } catch {
            WatchConsole.info("[Watch] Recording validation failed: \(error.localizedDescription)")
            try? fileManager.removeItem(at: url)
            continuation.resume(returning: nil)
        }
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder,
        successfully flag: Bool
    ) {
        Task { @MainActor [weak self] in
            self?.finishRecording(recorder, successfully: flag)
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(
        _ recorder: AVAudioRecorder,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.finishRecording(
                recorder,
                successfully: false,
                reason: error?.localizedDescription ?? "encoder error"
            )
        }
    }
}
