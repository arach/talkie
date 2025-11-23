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
    }

    func playAudio(url: URL) {
        // Stop current playback if playing different file
        if currentPlayingURL != url {
            stopPlayback()
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
            currentPlayingURL = url

            audioPlayer?.play()
            isPlaying = true

            // Start timer to update current time
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.currentTime = self.audioPlayer?.currentTime ?? 0
            }

        } catch {
            print("Failed to play audio: \(error.localizedDescription)")
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
