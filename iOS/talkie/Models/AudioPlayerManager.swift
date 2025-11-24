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

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?

    override init() {
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Use .spokenAudio mode for better voice playback
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session for playback: \(error.localizedDescription)")
        }
    }

    func playAudio(url: URL) {
        // Stop current playback if playing different file
        if currentPlayingURL != url {
            stopPlayback()
        }

        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("⚠️ Audio file does not exist at path: \(url.path)")
            return
        }

        do {
            // Ensure audio session is active
            try AVAudioSession.sharedInstance().setActive(true)

            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.volume = 1.0 // Maximum volume
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
            currentPlayingURL = url

            print("✅ Successfully loaded audio file: \(url.lastPathComponent), duration: \(duration)s")

            audioPlayer?.play()
            isPlaying = true

            // Start timer to update current time
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.currentTime = self.audioPlayer?.currentTime ?? 0
            }

        } catch {
            print("❌ Failed to play audio at \(url.path): \(error)")
            print("Error details: \(error.localizedDescription)")
        }
    }

    // Play audio from Data (for CloudKit-synced audio)
    func playAudio(data: Data) {
        stopPlayback()

        do {
            // Ensure audio session is active
            try AVAudioSession.sharedInstance().setActive(true)

            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.volume = 1.0
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0

            print("✅ Successfully loaded audio from data: \(data.count) bytes, duration: \(duration)s")

            audioPlayer?.play()
            isPlaying = true

            // Start timer to update current time
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.currentTime = self.audioPlayer?.currentTime ?? 0
            }

        } catch {
            print("❌ Failed to play audio from data: \(error)")
        }
    }

    func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false
        timer?.invalidate()
    }

    func resumePlayback() {
        audioPlayer?.play()
        isPlaying = true

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.currentTime = self.audioPlayer?.currentTime ?? 0
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        timer?.invalidate()
        isPlaying = false
        currentTime = 0
        currentPlayingURL = nil
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
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
    }
}
