//
//  AudioPlayerCard.swift
//  TalkieKit
//
//  Complete audio player card component with waveform, controls, and time display
//

import SwiftUI

// MARK: - Audio Player Card

/// A complete audio player card with play/pause, seekable waveform, and time display
///
/// Usage with shared manager:
/// ```swift
/// struct MyView: View {
///     @ObservedObject var playback = AudioPlaybackManager.shared
///     let audioURL: URL
///     let audioID: String
///
///     var body: some View {
///         AudioPlayerCard(
///             audioURL: audioURL,
///             audioID: audioID,
///             playback: playback
///         )
///     }
/// }
/// ```
///
/// Usage with manual state:
/// ```swift
/// AudioPlayerCard(
///     progress: 0.5,
///     currentTime: 30,
///     duration: 60,
///     isPlaying: true,
///     onPlayPause: { },
///     onSeek: { progress in }
/// )
/// ```
public struct AudioPlayerCard: View {
    // MARK: - State-based Properties

    private let progress: Double
    private let currentTime: TimeInterval
    private let duration: TimeInterval
    private let isPlaying: Bool
    private let hasAudio: Bool
    private let onPlayPause: () -> Void
    private let onSeek: (Double) -> Void

    // MARK: - Configuration

    private let theme: AudioPlayerTheme
    private let waveformConfig: WaveformConfiguration
    private let showTimeLabels: Bool
    private let showPlayButton: Bool
    private let compactMode: Bool

    // MARK: - Initializers

    /// Initialize with playback manager (recommended)
    ///
    /// - Parameters:
    ///   - audioURL: URL of the audio file
    ///   - audioID: Unique identifier for this audio
    ///   - playback: The audio playback manager
    ///   - theme: Visual theme
    ///   - waveformConfig: Waveform configuration
    ///   - showTimeLabels: Whether to show current/duration time
    ///   - showPlayButton: Whether to show the play/pause button
    ///   - compactMode: Use compact layout
    public init(
        audioURL: URL?,
        audioID: String,
        playback: AudioPlaybackManager,
        theme: AudioPlayerTheme = .system,
        waveformConfig: WaveformConfiguration = .default,
        showTimeLabels: Bool = true,
        showPlayButton: Bool = true,
        compactMode: Bool = false
    ) {
        let isThisAudio = playback.currentAudioID == audioID
        self.progress = isThisAudio ? playback.progress : 0
        self.currentTime = isThisAudio ? playback.currentTime : 0
        self.duration = isThisAudio ? playback.duration : 0
        self.isPlaying = isThisAudio && playback.isPlaying
        self.hasAudio = audioURL != nil

        self.onPlayPause = {
            guard let url = audioURL else { return }
            playback.togglePlayPause(url: url, id: audioID)
        }

        self.onSeek = { seekProgress in
            guard let url = audioURL else { return }
            // Load if not already loaded
            if !playback.isLoaded(id: audioID) {
                playback.load(url: url, id: audioID)
            }
            playback.seek(to: seekProgress)
        }

        self.theme = theme
        self.waveformConfig = waveformConfig
        self.showTimeLabels = showTimeLabels
        self.showPlayButton = showPlayButton
        self.compactMode = compactMode
    }

    /// Initialize with manual state (for custom implementations)
    public init(
        progress: Double,
        currentTime: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool,
        hasAudio: Bool = true,
        theme: AudioPlayerTheme = .system,
        waveformConfig: WaveformConfiguration = .default,
        showTimeLabels: Bool = true,
        showPlayButton: Bool = true,
        compactMode: Bool = false,
        onPlayPause: @escaping () -> Void,
        onSeek: @escaping (Double) -> Void
    ) {
        self.progress = progress
        self.currentTime = currentTime
        self.duration = duration
        self.isPlaying = isPlaying
        self.hasAudio = hasAudio
        self.theme = theme
        self.waveformConfig = waveformConfig
        self.showTimeLabels = showTimeLabels
        self.showPlayButton = showPlayButton
        self.compactMode = compactMode
        self.onPlayPause = onPlayPause
        self.onSeek = onSeek
    }

    // MARK: - Body

    public var body: some View {
        if compactMode {
            compactLayout
        } else {
            standardLayout
        }
    }

    // MARK: - Layouts

    private var standardLayout: some View {
        HStack(spacing: 12) {
            // Play/Pause button
            if showPlayButton {
                playPauseButton
            }

            // Waveform
            SeekableWaveform(
                progress: progress,
                isPlaying: isPlaying,
                isSeekable: hasAudio,
                theme: theme,
                config: waveformConfig,
                onSeek: onSeek
            )
            .frame(height: 32)

            // Time labels
            if showTimeLabels {
                timeLabels
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.background)
        .cornerRadius(8)
    }

    private var compactLayout: some View {
        HStack(spacing: 8) {
            // Play/Pause button (smaller)
            if showPlayButton {
                compactPlayPauseButton
            }

            // Waveform
            SeekableWaveform(
                progress: progress,
                isPlaying: isPlaying,
                isSeekable: hasAudio,
                theme: theme,
                config: .compact,
                onSeek: onSeek
            )
            .frame(height: 24)

            // Time label (current only)
            if showTimeLabels {
                Text(AudioTimeFormatter.format(currentTime))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.textSecondary)
                    .frame(width: 32, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(theme.background)
        .cornerRadius(6)
    }

    // MARK: - Components

    private var playPauseButton: some View {
        Button(action: onPlayPause) {
            ZStack {
                Circle()
                    .fill(theme.playButtonColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.playButtonColor)
                    .offset(x: isPlaying ? 0 : 1) // Visual centering for play icon
            }
        }
        .buttonStyle(.plain)
        .disabled(!hasAudio)
        .opacity(hasAudio ? 1 : 0.5)
    }

    private var compactPlayPauseButton: some View {
        Button(action: onPlayPause) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.playButtonColor)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .disabled(!hasAudio)
        .opacity(hasAudio ? 1 : 0.5)
    }

    private var timeLabels: some View {
        HStack(spacing: 4) {
            Text(AudioTimeFormatter.format(currentTime))
                .foregroundColor(theme.textPrimary)

            Text("/")
                .foregroundColor(theme.textSecondary)

            Text(AudioTimeFormatter.format(duration))
                .foregroundColor(theme.textSecondary)
        }
        .font(.system(size: 11, design: .monospaced))
        .frame(width: 70, alignment: .trailing)
    }
}

// MARK: - Inline Audio Player

/// A minimal inline audio player for use in lists or compact spaces
@MainActor
public struct InlineAudioPlayer: View {
    let audioURL: URL?
    let audioID: String
    @ObservedObject var playback: AudioPlaybackManager
    let theme: AudioPlayerTheme

    public init(
        audioURL: URL?,
        audioID: String,
        playback: AudioPlaybackManager,
        theme: AudioPlayerTheme = .minimal
    ) {
        self.audioURL = audioURL
        self.audioID = audioID
        self.playback = playback
        self.theme = theme
    }

    private var isThisAudio: Bool {
        playback.currentAudioID == audioID
    }

    private var isPlaying: Bool {
        isThisAudio && playback.isPlaying
    }

    private var progress: Double {
        isThisAudio ? playback.progress : 0
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Play button
            Button {
                guard let url = audioURL else { return }
                playback.togglePlayPause(url: url, id: audioID)
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(theme.playButtonColor)
            }
            .buttonStyle(.plain)
            .disabled(audioURL == nil)

            // Progress bar (simple, not waveform)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(theme.unplayedColor)
                        .frame(height: 4)

                    // Progress fill
                    Capsule()
                        .fill(theme.playedColor)
                        .frame(width: geo.size.width * progress, height: 4)
                }
                .frame(height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            guard let url = audioURL else { return }
                            let seekProgress = max(0, min(1, value.location.x / geo.size.width))
                            if !playback.isLoaded(id: audioID) {
                                playback.load(url: url, id: audioID)
                            }
                            playback.seek(to: seekProgress)
                        }
                )
            }
            .frame(height: 20)

            // Duration
            Text(AudioTimeFormatter.format(isThisAudio ? playback.duration : 0))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(theme.textSecondary)
                .frame(width: 28, alignment: .trailing)
        }
    }
}

// MARK: - Previews

#Preview("Audio Player Card") {
    VStack(spacing: 20) {
        // Standard
        AudioPlayerCard(
            progress: 0.4,
            currentTime: 45,
            duration: 120,
            isPlaying: false,
            onPlayPause: {},
            onSeek: { _ in }
        )

        // Playing
        AudioPlayerCard(
            progress: 0.6,
            currentTime: 72,
            duration: 120,
            isPlaying: true,
            onPlayPause: {},
            onSeek: { _ in }
        )

        // Compact
        AudioPlayerCard(
            progress: 0.3,
            currentTime: 30,
            duration: 100,
            isPlaying: false,
            compactMode: true,
            onPlayPause: {},
            onSeek: { _ in }
        )

        // Dark theme
        AudioPlayerCard(
            progress: 0.5,
            currentTime: 60,
            duration: 120,
            isPlaying: false,
            theme: .dark,
            onPlayPause: {},
            onSeek: { _ in }
        )
    }
    .padding()
    .frame(width: 400)
}

#Preview("Inline Audio Player") {
    struct PreviewWrapper: View {
        @ObservedObject var playback = AudioPlaybackManager.shared

        var body: some View {
            VStack(spacing: 12) {
                InlineAudioPlayer(
                    audioURL: nil,
                    audioID: "test-1",
                    playback: playback
                )

                InlineAudioPlayer(
                    audioURL: nil,
                    audioID: "test-2",
                    playback: playback
                )
            }
            .padding()
            .frame(width: 300)
        }
    }

    return PreviewWrapper()
}
