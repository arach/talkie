//
//  AudioPlaybackManager.swift
//  TalkieKit
//
//  Reusable audio playback manager for Talkie apps
//

import Foundation
import AVFoundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.jdi.talkiekit", category: "AudioPlayback")

// MARK: - Audio Playback Manager

/// A shared audio playback manager that handles audio file playback with progress tracking
///
/// Usage:
/// ```swift
/// // Using the shared instance
/// AudioPlaybackManager.shared.play(url: audioURL, id: "unique-id")
///
/// // Observing state
/// struct MyView: View {
///     @ObservedObject var playback = AudioPlaybackManager.shared
///
///     var body: some View {
///         Text(playback.isPlaying ? "Playing" : "Paused")
///     }
/// }
/// ```
@MainActor
public final class AudioPlaybackManager: NSObject, ObservableObject {
    /// Shared singleton instance
    public static let shared = AudioPlaybackManager()

    // MARK: - Published State

    /// Whether audio is currently playing
    @Published public private(set) var isPlaying = false

    /// Current playback position in seconds
    @Published public private(set) var currentTime: TimeInterval = 0

    /// Total duration of the current audio in seconds
    @Published public private(set) var duration: TimeInterval = 0

    /// Playback progress as a value from 0 to 1
    @Published public private(set) var progress: Double = 0

    /// ID of the currently loaded audio (used to track which audio is playing)
    @Published public private(set) var currentAudioID: String?

    // MARK: - Private

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?

    private override init() {
        super.init()
    }

    // MARK: - Computed Properties

    /// Get the current playback state as a value type
    public var state: AudioPlaybackState {
        AudioPlaybackState(
            isPlaying: isPlaying,
            currentTime: currentTime,
            duration: duration,
            progress: progress,
            currentAudioID: currentAudioID
        )
    }

    /// Check if a specific audio ID is currently loaded
    public func isLoaded(id: String) -> Bool {
        currentAudioID == id
    }

    /// Check if a specific audio ID is currently playing
    public func isPlaying(id: String) -> Bool {
        currentAudioID == id && isPlaying
    }

    // MARK: - Public API

    /// Play audio from a URL with an identifier
    ///
    /// If the same ID is already playing, this toggles pause/resume.
    /// If a different audio is playing, it stops that and starts the new one.
    ///
    /// - Parameters:
    ///   - url: The URL of the audio file
    ///   - id: A unique identifier for this audio (used for tracking)
    public func play(url: URL, id: String) {
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

    /// Load audio without playing (useful for seeking before playback)
    ///
    /// - Parameters:
    ///   - url: The URL of the audio file
    ///   - id: A unique identifier for this audio
    public func load(url: URL, id: String) {
        // Already loaded
        if currentAudioID == id && player != nil {
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

            logger.info("Loaded audio: \(url.lastPathComponent)")
        } catch {
            logger.error("Failed to load audio: \(error.localizedDescription)")
            reset()
        }
    }

    /// Pause the current playback
    public func pause() {
        player?.pause()
        isPlaying = false
        stopProgressTimer()
        logger.info("Paused audio")
    }

    /// Resume playback from current position
    public func resume() {
        guard player != nil else { return }
        player?.play()
        isPlaying = true
        startProgressTimer()
        logger.info("Resumed audio")
    }

    /// Stop playback and reset state
    public func stop() {
        player?.stop()
        reset()
        logger.info("Stopped audio")
    }

    /// Seek to a position in the audio
    ///
    /// - Parameter progress: Position as a value from 0 to 1
    public func seek(to progress: Double) {
        guard let player = player else { return }
        let clampedProgress = max(0, min(1, progress))
        let time = clampedProgress * player.duration
        player.currentTime = time
        currentTime = time
        self.progress = clampedProgress
    }

    /// Seek to a specific time in seconds
    ///
    /// - Parameter time: Time in seconds
    public func seek(toTime time: TimeInterval) {
        guard let player = player, player.duration > 0 else { return }
        let clampedTime = max(0, min(player.duration, time))
        player.currentTime = clampedTime
        currentTime = clampedTime
        progress = clampedTime / player.duration
    }

    /// Toggle play/pause for a specific audio
    ///
    /// - Parameters:
    ///   - url: The URL of the audio file
    ///   - id: A unique identifier for this audio
    public func togglePlayPause(url: URL, id: String) {
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

    // MARK: - Private Methods

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
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.progress = flag ? 1.0 : self.progress
            self.currentTime = flag ? self.duration : self.currentTime
            self.stopProgressTimer()
            logger.info("Audio playback finished")
        }
    }

    nonisolated public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            logger.error("Audio decode error: \(error?.localizedDescription ?? "unknown")")
            self.reset()
        }
    }
}
