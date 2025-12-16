//
//  SeekableWaveform.swift
//  TalkieKit
//
//  Interactive waveform visualization with seeking support
//

import SwiftUI

// MARK: - Seekable Waveform

/// An interactive waveform visualization that supports click-to-seek
///
/// Usage:
/// ```swift
/// SeekableWaveform(
///     progress: 0.5,
///     isPlaying: true,
///     onSeek: { progress in
///         // Handle seek to progress (0-1)
///     }
/// )
/// ```
public struct SeekableWaveform: View {
    /// Current playback progress (0-1)
    public let progress: Double

    /// Whether audio is currently playing
    public let isPlaying: Bool

    /// Whether seeking is enabled (disables interaction when false)
    public let isSeekable: Bool

    /// Theme for colors
    public let theme: AudioPlayerTheme

    /// Waveform configuration
    public let config: WaveformConfiguration

    /// Called when user seeks to a position
    public let onSeek: (Double) -> Void

    @State private var isHovered = false

    public init(
        progress: Double,
        isPlaying: Bool,
        isSeekable: Bool = true,
        theme: AudioPlayerTheme = .system,
        config: WaveformConfiguration = .default,
        onSeek: @escaping (Double) -> Void
    ) {
        self.progress = progress
        self.isPlaying = isPlaying
        self.isSeekable = isSeekable
        self.theme = theme
        self.config = config
        self.onSeek = onSeek
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // The actual waveform visualization
                WaveformBars(
                    progress: progress,
                    isPlaying: isPlaying,
                    theme: theme,
                    config: config
                )
                .allowsHitTesting(false)

                // Full-width click target overlay
                if isSeekable {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    let clickX = value.location.x
                                    let width = geometry.size.width
                                    let seekProgress = max(0, min(1, clickX / width))
                                    onSeek(seekProgress)
                                }
                        )
                        .onContinuousHover { phase in
                            switch phase {
                            case .active:
                                isHovered = true
                            case .ended:
                                isHovered = false
                            }
                        }
                }
            }
            .talkieCursor(isSeekable ? .pointingHand : .arrow)
        }
    }
}

// MARK: - Waveform Bars (Animated Container)

/// Animated waveform bars visualization
///
/// This is the non-interactive waveform. Use `SeekableWaveform` for seeking support.
public struct WaveformBars: View {
    public let progress: Double
    public let isPlaying: Bool
    public let theme: AudioPlayerTheme
    public let config: WaveformConfiguration

    public init(
        progress: Double,
        isPlaying: Bool = false,
        theme: AudioPlayerTheme = .system,
        config: WaveformConfiguration = .default
    ) {
        self.progress = progress
        self.isPlaying = isPlaying
        self.theme = theme
        self.config = config
    }

    public var body: some View {
        let shouldAnimate = isPlaying && config.animateOnPlayback

        TimelineView(.animation(minimumInterval: 0.05, paused: !shouldAnimate)) { timeline in
            WaveformBarsContent(
                progress: progress,
                isPlaying: isPlaying,
                time: timeline.date.timeIntervalSinceReferenceDate,
                theme: theme,
                config: config
            )
        }
    }
}

// MARK: - Waveform Bars Content

private struct WaveformBarsContent: View {
    let progress: Double
    let isPlaying: Bool
    let time: TimeInterval
    let theme: AudioPlayerTheme
    let config: WaveformConfiguration

    var body: some View {
        GeometryReader { geo in
            let barCount = max(1, Int(geo.size.width / (config.barWidth + config.barSpacing)))

            HStack(spacing: config.barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    WaveformBar(
                        index: index,
                        totalBars: barCount,
                        baseHeight: WaveformHeightGenerator.height(
                            for: index,
                            minHeight: config.minBarHeight
                        ),
                        progress: progress,
                        isPlaying: isPlaying,
                        time: time,
                        containerHeight: geo.size.height,
                        theme: theme,
                        config: config
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Individual Waveform Bar

private struct WaveformBar: View {
    let index: Int
    let totalBars: Int
    let baseHeight: Double
    let progress: Double
    let isPlaying: Bool
    let time: TimeInterval
    let containerHeight: CGFloat
    let theme: AudioPlayerTheme
    let config: WaveformConfiguration

    private var barProgress: Double {
        Double(index) / Double(totalBars)
    }

    private var isPast: Bool {
        barProgress < progress
    }

    private var isCurrent: Bool {
        abs(barProgress - progress) < (1.0 / Double(totalBars))
    }

    private var animatedHeight: Double {
        if isPlaying && isPast && config.animateOnPlayback {
            let speed = 4.0 * config.animationSpeed
            return baseHeight + sin(time * speed + Double(index) * 0.5) * 0.1
        }
        return baseHeight
    }

    private var barColor: Color {
        if isCurrent {
            return theme.currentColor
        } else if isPast {
            return theme.playedColor
        } else {
            return theme.unplayedColor
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: config.barCornerRadius)
            .fill(barColor)
            .frame(
                width: config.barWidth,
                height: containerHeight * max(config.minBarHeight, animatedHeight)
            )
    }
}

// MARK: - Cursor Modifier

private struct CursorModifier: ViewModifier {
    let cursor: NSCursor

    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

extension View {
    /// Set the cursor when hovering over this view
    func talkieCursor(_ cursor: NSCursor) -> some View {
        modifier(CursorModifier(cursor: cursor))
    }
}

// MARK: - Previews

#Preview("Seekable Waveform") {
    struct PreviewWrapper: View {
        @State var progress: Double = 0.3
        @State var isPlaying = false

        var body: some View {
            VStack(spacing: 20) {
                Text("Progress: \(Int(progress * 100))%")

                SeekableWaveform(
                    progress: progress,
                    isPlaying: isPlaying,
                    onSeek: { newProgress in
                        progress = newProgress
                    }
                )
                .frame(height: 40)

                HStack {
                    Button(isPlaying ? "Pause" : "Play") {
                        isPlaying.toggle()
                    }

                    Button("Reset") {
                        progress = 0
                    }
                }
            }
            .padding()
            .frame(width: 400)
        }
    }

    return PreviewWrapper()
}

#Preview("Waveform Themes") {
    VStack(spacing: 20) {
        Group {
            Text("System Theme")
            WaveformBars(progress: 0.5, isPlaying: false, theme: .system)
                .frame(height: 30)
        }

        Group {
            Text("Dark Theme")
            WaveformBars(progress: 0.5, isPlaying: false, theme: .dark)
                .frame(height: 30)
                .background(Color.black)
        }

        Group {
            Text("Minimal Theme")
            WaveformBars(progress: 0.5, isPlaying: false, theme: .minimal)
                .frame(height: 30)
        }
    }
    .padding()
    .frame(width: 400)
}
