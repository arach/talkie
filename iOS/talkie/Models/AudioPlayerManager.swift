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
            try audioSession.setCategory(.playback, mode: .default, options: [])
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
            print("Audio file does not exist at path: \(url.path)")
            return
        }

        do {
            // Ensure audio session is active
            try AVAudioSession.sharedInstance().setActive(true)

            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
            currentPlayingURL = url

            print("Successfully loaded audio file: \(url.lastPathComponent), duration: \(duration)s")

            audioPlayer?.play()
            isPlaying = true

            // Start timer to update current time
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.currentTime = self.audioPlayer?.currentTime ?? 0
            }

        } catch {
            print("Failed to play audio at \(url.path): \(error)")
            print("Error details: \(error.localizedDescription)")
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
}

extension AudioPlayerManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentTime = 0
        timer?.invalidate()
    }
}
