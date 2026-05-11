//
//  AudioPlayerManager.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import Foundation
import AVFoundation
import SwiftUI
import Combine

class AudioPlayerManager: NSObject, ObservableObject {

    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var currentPlayingURL: URL?
    @Published private(set) var playbackRate: Float = 1.0

    /// Called when playback finishes (natural end or stop)
    /// Use this to release memory (e.g., refresh Core Data objects to release audioData)
    var onPlaybackFinished: (() -> Void)?

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var loadedDurationURL: URL?

    @discardableResult
    private func activateAudioSessionForPlayback() -> Bool {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Use .spokenAudio mode for better voice playback
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [])
            try audioSession.setActive(true)
            return true
        } catch {
            AppLogger.playback.error("Failed to activate playback session: \(error.localizedDescription)")
            return false
        }
    }

    private func deactivateAudioSession(notifyOthers: Bool = true) {
        let options: AVAudioSession.SetActiveOptions = notifyOthers ? [.notifyOthersOnDeactivation] : []

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: options)
            AppLogger.playback.debug("Playback session deactivated")
        } catch {
            AppLogger.playback.debug("Playback session deactivation skipped: \(error.localizedDescription)")
        }
    }

    private func startPlaybackTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.currentTime = self.audioPlayer?.currentTime ?? 0
        }
    }

    func preloadDuration(for url: URL?) {
        guard let url else {
            if !isPlaying {
                duration = 0
                currentTime = 0
            }
            loadedDurationURL = nil
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            AppLogger.playback.warning("Cannot preload duration; audio file does not exist at path: \(url.path)")
            return
        }

        if loadedDurationURL == url, duration > 0 {
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()

            let loadedDuration = player.duration
            duration = loadedDuration.isFinite ? loadedDuration : 0
            loadedDurationURL = url

            if audioPlayer == nil {
                currentTime = 0
            }

            AppLogger.playback.debug("Preloaded audio duration for \(url.lastPathComponent): \(duration)s")
        } catch {
            AppLogger.playback.error("Failed to preload audio duration at \(url.path): \(error.localizedDescription)")
        }
    }

    func playAudio(url: URL) {
        // Always stop and reset before playing a new file
        stopPlayback()

        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            AppLogger.playback.warning("Audio file does not exist at path: \(url.path)")
            return
        }

        guard activateAudioSessionForPlayback() else {
            return
        }

        do {
            // Create fresh player instance
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.volume = 1.0 // Maximum volume
            player.enableRate = true
            player.rate = playbackRate
            player.prepareToPlay()

            audioPlayer = player
            duration = player.duration
            loadedDurationURL = url
            currentPlayingURL = url
            currentTime = 0

            AppLogger.playback.info("Successfully loaded audio file: \(url.lastPathComponent), duration: \(self.duration)s")

            if player.play() {
                player.rate = playbackRate
                isPlaying = true
                startPlaybackTimer()
            } else {
                AppLogger.playback.error("Failed to start playback for \(url.lastPathComponent)")
                audioPlayer = nil
                deactivateAudioSession()
            }

        } catch {
            AppLogger.playback.error("Failed to play audio at \(url.path): \(error.localizedDescription)")
            deactivateAudioSession()
        }
    }

    // Play audio from Data (for CloudKit-synced audio)
    func playAudio(data: Data) {
        stopPlayback()

        guard activateAudioSessionForPlayback() else {
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.volume = 1.0
            audioPlayer?.enableRate = true
            audioPlayer?.rate = playbackRate
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
            loadedDurationURL = nil

            AppLogger.playback.info("Successfully loaded audio from data: \(data.count) bytes, duration: \(self.duration)s")

            if audioPlayer?.play() == true {
                audioPlayer?.rate = playbackRate
                isPlaying = true
                startPlaybackTimer()
            } else {
                AppLogger.playback.error("Failed to start playback from in-memory audio")
                audioPlayer = nil
                deactivateAudioSession()
            }

        } catch {
            AppLogger.playback.error("Failed to play audio from data: \(error.localizedDescription)")
            deactivateAudioSession()
        }
    }

    func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false
        timer?.invalidate()
        deactivateAudioSession()
    }

    func resumePlayback() {
        guard activateAudioSessionForPlayback() else {
            return
        }

        if audioPlayer?.play() == true {
            audioPlayer?.rate = playbackRate
            isPlaying = true
            startPlaybackTimer()
        } else {
            AppLogger.playback.error("Failed to resume playback")
            deactivateAudioSession()
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil  // Release the player to free audio data memory
        timer?.invalidate()
        isPlaying = false
        currentTime = 0
        currentPlayingURL = nil
        deactivateAudioSession()
        onPlaybackFinished?()
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }

    func setPlaybackRate(_ rate: Float) {
        let clampedRate = min(max(rate, 0.75), 2.0)
        playbackRate = clampedRate
        audioPlayer?.enableRate = true
        audioPlayer?.rate = clampedRate
    }

    func togglePlayPause(url: URL) {
        if currentPlayingURL == url && isPlaying {
            pausePlayback()
        } else if currentPlayingURL == url && !isPlaying {
            resumePlayback()
        } else {
            playAudio(url: url)
        }
    }

    func togglePlayPause(data: Data) {
        if isPlaying {
            pausePlayback()
        } else if audioPlayer != nil {
            resumePlayback()
        } else {
            playAudio(data: data)
        }
    }
}

extension AudioPlayerManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentTime = 0
        timer?.invalidate()
        audioPlayer = nil  // Release to free memory
        deactivateAudioSession()
        onPlaybackFinished?()
    }
}
