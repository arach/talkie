//
//  AudioPlayerTypes.swift
//  TalkieKit
//
//  Shared types for audio player components across Talkie apps
//

import SwiftUI

// MARK: - Audio Playback State

/// Observable state for audio playback
public struct AudioPlaybackState: Equatable {
    public var isPlaying: Bool
    public var currentTime: TimeInterval
    public var duration: TimeInterval
    public var progress: Double
    public var currentAudioID: String?

    public init(
        isPlaying: Bool = false,
        currentTime: TimeInterval = 0,
        duration: TimeInterval = 0,
        progress: Double = 0,
        currentAudioID: String? = nil
    ) {
        self.isPlaying = isPlaying
        self.currentTime = currentTime
        self.duration = duration
        self.progress = progress
        self.currentAudioID = currentAudioID
    }

    public static let idle = AudioPlaybackState()
}

// MARK: - Audio Player Theme

/// Theme configuration for audio player components
public struct AudioPlayerTheme {
    /// Color for played portion of waveform
    public let playedColor: Color

    /// Color for the current position indicator
    public let currentColor: Color

    /// Color for unplayed portion of waveform
    public let unplayedColor: Color

    /// Background color for the player card
    public let background: Color

    /// Secondary background color
    public let backgroundSecondary: Color

    /// Primary text color
    public let textPrimary: Color

    /// Secondary/muted text color
    public let textSecondary: Color

    /// Play button color
    public let playButtonColor: Color

    public init(
        playedColor: Color = .accentColor,
        currentColor: Color = .primary,
        unplayedColor: Color = .secondary.opacity(0.3),
        background: Color = Color(NSColor.controlBackgroundColor),
        backgroundSecondary: Color = Color(NSColor.windowBackgroundColor),
        textPrimary: Color = .primary,
        textSecondary: Color = .secondary,
        playButtonColor: Color = .accentColor
    ) {
        self.playedColor = playedColor
        self.currentColor = currentColor
        self.unplayedColor = unplayedColor
        self.background = background
        self.backgroundSecondary = backgroundSecondary
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.playButtonColor = playButtonColor
    }

    /// Default system theme (adapts to light/dark mode)
    public static let system = AudioPlayerTheme()

    /// Dark theme for console-style UIs
    public static let dark = AudioPlayerTheme(
        playedColor: Color(red: 0.4, green: 0.8, blue: 0.4),
        currentColor: .white,
        unplayedColor: Color.white.opacity(0.2),
        background: Color(red: 0.1, green: 0.1, blue: 0.12),
        backgroundSecondary: Color(red: 0.08, green: 0.08, blue: 0.1),
        textPrimary: .white,
        textSecondary: Color.white.opacity(0.6),
        playButtonColor: Color(red: 0.4, green: 0.8, blue: 0.4)
    )

    /// Minimal/subtle theme
    public static let minimal = AudioPlayerTheme(
        playedColor: .secondary,
        currentColor: .primary,
        unplayedColor: .secondary.opacity(0.15),
        background: .clear,
        backgroundSecondary: .clear,
        textPrimary: .primary,
        textSecondary: .secondary,
        playButtonColor: .primary
    )
}

// MARK: - Waveform Configuration

/// Configuration for waveform visualization
public struct WaveformConfiguration {
    /// Number of bars in the waveform
    public let barCount: Int

    /// Width of each bar in points
    public let barWidth: CGFloat

    /// Spacing between bars in points
    public let barSpacing: CGFloat

    /// Corner radius of bars
    public let barCornerRadius: CGFloat

    /// Minimum bar height as fraction (0-1)
    public let minBarHeight: Double

    /// Whether to animate bars during playback
    public let animateOnPlayback: Bool

    /// Animation speed multiplier
    public let animationSpeed: Double

    public init(
        barCount: Int = 40,
        barWidth: CGFloat = 2,
        barSpacing: CGFloat = 2,
        barCornerRadius: CGFloat = 1,
        minBarHeight: Double = 0.15,
        animateOnPlayback: Bool = true,
        animationSpeed: Double = 1.0
    ) {
        self.barCount = barCount
        self.barWidth = barWidth
        self.barSpacing = barSpacing
        self.barCornerRadius = barCornerRadius
        self.minBarHeight = minBarHeight
        self.animateOnPlayback = animateOnPlayback
        self.animationSpeed = animationSpeed
    }

    /// Default configuration
    public static let `default` = WaveformConfiguration()

    /// Compact configuration for smaller displays
    public static let compact = WaveformConfiguration(
        barCount: 24,
        barWidth: 1.5,
        barSpacing: 1.5,
        barCornerRadius: 0.5
    )

    /// Dense configuration for detailed display
    public static let dense = WaveformConfiguration(
        barCount: 60,
        barWidth: 1.5,
        barSpacing: 1,
        barCornerRadius: 0.5
    )
}

// MARK: - Time Formatting

/// Utility for formatting audio time
public enum AudioTimeFormatter {
    /// Format seconds as "m:ss"
    public static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    /// Format seconds as "mm:ss" (zero-padded minutes)
    public static func formatPadded(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    /// Format seconds as "h:mm:ss" for longer durations
    public static func formatLong(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00:00" }
        let hours = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Waveform Height Generator

/// Generates deterministic pseudo-random heights for waveform bars
public enum WaveformHeightGenerator {
    /// Golden ratio seed for natural-looking distribution
    private static let goldenRatio: Double = 1.618033988749

    /// Generate a deterministic height for a bar index
    /// - Parameters:
    ///   - index: The bar index
    ///   - seed: Optional seed for variation (default 0)
    /// - Returns: Height value between minHeight and 1.0
    public static func height(for index: Int, seed: Double = 0, minHeight: Double = 0.15) -> Double {
        let s = Double(index) * goldenRatio + seed
        let h = 0.3 + sin(s * 2.5) * 0.25 + cos(s * 1.3) * 0.2
        return max(minHeight, min(1.0, h))
    }

    /// Generate an array of heights for a given bar count
    public static func heights(count: Int, seed: Double = 0, minHeight: Double = 0.15) -> [Double] {
        (0..<count).map { height(for: $0, seed: seed, minHeight: minHeight) }
    }
}
