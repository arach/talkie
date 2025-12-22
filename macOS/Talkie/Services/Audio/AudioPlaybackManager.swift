//
//  AudioPlaybackManager.swift
//  TalkieLive
//
//  Audio playback for utterance recordings
//

import Foundation
import AVFoundation
import Combine
import os.log
import Observation

private let logger = Logger(subsystem: "jdi.talkie.live", category: "AudioPlayback")

@MainActor
@Observable
final class AudioPlaybackManager: NSObject {
    static let shared = AudioPlaybackManager()

    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var progress: Double = 0
    private(set) var currentAudioID: String?

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?

    private override init() {
        super.init()
    }

    // MARK: - Public API

    func play(url: URL, id: String) {
        // If already playing this audio, toggle pause
        if currentAudioID == id && player != nil {
            if isPlaying {
                pause()
            } else {
                resume()
            }
            return
        }

        // Stop any current playback
        stop()

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()

            duration = player?.duration ?? 0
            currentAudioID = id
            currentTime = 0
            progress = 0

            player?.play()
            isPlaying = true
            startProgressTimer()

            logger.info("Playing audio: \(url.lastPathComponent)")
        } catch {
            logger.error("Failed to play audio: \(error.localizedDescription)")
            reset()
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopProgressTimer()
        logger.info("Paused audio")
    }

    func resume() {
        player?.play()
        isPlaying = true
        startProgressTimer()
        logger.info("Resumed audio")
    }

    func stop() {
        player?.stop()
        reset()
        logger.info("Stopped audio")
    }

    func seek(to progress: Double) {
        guard let player = player else { return }
        let time = progress * player.duration
        player.currentTime = time
        currentTime = time
        self.progress = progress
    }

    func togglePlayPause(url: URL, id: String) {
        if currentAudioID == id {
            if isPlaying {
                pause()
            } else {
                resume()
            }
        } else {
            play(url: url, id: id)
        }
    }

    // MARK: - Private

    private func reset() {
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        progress = 0
        currentAudioID = nil
        stopProgressTimer()
    }

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateProgress()
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func updateProgress() {
        guard let player = player else { return }
        currentTime = player.currentTime
        if player.duration > 0 {
            progress = player.currentTime / player.duration
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlaybackManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.progress = flag ? 1.0 : self.progress
            self.currentTime = flag ? self.duration : self.currentTime
            self.stopProgressTimer()
            logger.info("Audio playback finished")
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            logger.error("Audio decode error: \(error?.localizedDescription ?? "unknown")")
            self.reset()
        }
    }
}
