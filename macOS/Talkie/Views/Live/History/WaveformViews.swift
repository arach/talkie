//
//  WaveformViews.swift
//  TalkieLive
//
//  Waveform visualization components for audio playback
//

import SwiftUI
import AppKit
import TalkieKit

// MARK: - Cursor Modifier

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Seekable Waveform (wraps MinimalWaveformBars with click-to-seek)

struct SeekableWaveform: View {
    let progress: Double
    let isPlaying: Bool
    let hasAudio: Bool
    let onSeek: (Double) -> Void

    @State private var isHovered = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // The actual waveform visualization
                MinimalWaveformBars(progress: progress, isPlaying: isPlaying)
                    .allowsHitTesting(false)

                // Full-width click target overlay
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                guard hasAudio else { return }
                                let clickX = value.location.x
                                let width = geometry.size.width
                                let seekProgress = max(0, min(1, clickX / width))
                                print("👆 Waveform clicked at \(Int(seekProgress * 100))% (x: \(Int(clickX)), width: \(Int(width)))")
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
            .cursor(hasAudio ? .pointingHand : .arrow)
        }
    }
}

// MARK: - Minimal Waveform Bars

struct MinimalWaveformBars: View {
    let progress: Double
    var isPlaying: Bool = false

    // Pre-computed bar heights for consistency (seeded pseudo-random)
    private static let barHeights: [Double] = {
        var heights: [Double] = []
        for i in 0..<40 {
            let seed = Double(i) * 1.618
            let h = 0.3 + sin(seed * 2.5) * 0.25 + cos(seed * 1.3) * 0.2
            heights.append(max(0.15, min(1.0, h)))
        }
        return heights
    }()

    private static let barCount: Int = 40

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: !isPlaying)) { timeline in
            WaveformBarsContent(
                progress: progress,
                isPlaying: isPlaying,
                time: timeline.date.timeIntervalSinceReferenceDate
            )
        }
    }
}

// MARK: - Waveform Bars Content

struct WaveformBarsContent: View {
    let progress: Double
    let isPlaying: Bool
    let time: TimeInterval

    // Fixed bar dimensions
    private static let barWidth: CGFloat = 2
    private static let barSpacing: CGFloat = 2

    /// Generate deterministic height for a bar index using golden ratio seeding
    private static func barHeight(for index: Int) -> Double {
        let seed = Double(index) * 1.618
        let h = 0.3 + sin(seed * 2.5) * 0.25 + cos(seed * 1.3) * 0.2
        return max(0.15, min(1.0, h))
    }

    var body: some View {
        GeometryReader { geo in
            let barCount = max(1, Int(geo.size.width / (Self.barWidth + Self.barSpacing)))

            HStack(spacing: Self.barSpacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    WaveformBar(
                        index: i,
                        totalBars: barCount,
                        baseHeight: Self.barHeight(for: i),
                        progress: progress,
                        isPlaying: isPlaying,
                        time: time,
                        containerHeight: geo.size.height,
                        barWidth: Self.barWidth
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Single Waveform Bar

struct WaveformBar: View {
    let index: Int
    let totalBars: Int
    let baseHeight: Double
    let progress: Double
    let isPlaying: Bool
    let time: TimeInterval
    let containerHeight: CGFloat
    let barWidth: CGFloat

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
        if isPlaying && isPast {
            return baseHeight + sin(time * 4 + Double(index) * 0.5) * 0.1
        }
        return baseHeight
    }

    private var barColor: Color {
        if isCurrent {
            return .primary
        } else if isPast {
            return .accentColor
        } else {
            return .secondary.opacity(0.3)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(barColor)
            .frame(width: barWidth, height: containerHeight * max(0.15, animatedHeight))
    }
}

// MARK: - Waveform Visualization (Canvas-based)

struct WaveformVisualization: View {
    let progress: Double
    var isPlaying: Bool = false
    var onSeek: ((Double) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Clickable background
                Rectangle()
                    .fill(Color.clear)  // Nearly invisible but clickable
                    .onTapGesture { location in
                        if let onSeek = onSeek {
                            let newProgress = max(0, min(1, location.x / geo.size.width))
                            print("👆 Waveform tapped at \(Int(newProgress * 100))%")
                            onSeek(newProgress)
                        }
                    }

                // Waveform canvas (non-interactive)
                TimelineView(.animation(minimumInterval: 0.05, paused: !isPlaying)) { timeline in
                    Canvas { context, size in
                        let barCount = 60
                        let barWidth: CGFloat = 2
                        let gap: CGFloat = 2
                        let totalWidth = CGFloat(barCount) * (barWidth + gap)
                        let startX = (size.width - totalWidth) / 2

                        for i in 0..<barCount {
                            let seed = Double(i) * 1.618
                            let time = timeline.date.timeIntervalSinceReferenceDate

                            // Generate pseudo-random but consistent heights
                            let baseHeight = 0.3 + sin(seed * 2.5) * 0.2 + cos(seed * 1.3) * 0.15

                            // Animate only when playing
                            let animatedHeight: Double
                            if isPlaying {
                                animatedHeight = baseHeight + sin(time * 3 + seed) * 0.15
                            } else {
                                animatedHeight = baseHeight
                            }

                            let barHeight = max(4, CGFloat(animatedHeight) * size.height * 0.8)
                            let x = startX + CGFloat(i) * (barWidth + gap)
                            let y = (size.height - barHeight) / 2

                            let barRect = CGRect(x: x, y: y, width: barWidth, height: barHeight)

                            let progressPoint = CGFloat(i) / CGFloat(barCount)
                            let opacity = progressPoint < progress ? 0.8 : 0.25

                            context.fill(
                                RoundedRectangle(cornerRadius: 1).path(in: barRect),
                                with: .color(.accentColor.opacity(opacity))
                            )
                        }
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Waveform Card

struct WaveformCard: View {
    let utterance: Utterance
    @ObservedObject private var playback = AudioPlaybackManager.shared

    private var isThisPlaying: Bool {
        playback.currentAudioID == utterance.id.uuidString && playback.isPlaying
    }

    private var isThisLoaded: Bool {
        playback.currentAudioID == utterance.id.uuidString
    }

    private var displayProgress: Double {
        isThisLoaded ? playback.progress : 0
    }

    private var displayCurrentTime: TimeInterval {
        isThisLoaded ? playback.currentTime : 0
    }

    private var hasAudio: Bool {
        utterance.metadata.hasAudio
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Label("AUDIO", systemImage: "waveform")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(TalkieTheme.textMuted)

                Spacer()

                if hasAudio {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(SemanticColor.success.opacity(0.6))
                } else {
                    Text("No audio file")
                        .font(.system(size: 9))
                        .foregroundColor(TalkieTheme.textMuted)
                }

                if let duration = utterance.durationSeconds {
                    Text(formatDuration(duration))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
            }

            // Waveform visualization (click/drag to seek)
            WaveformVisualization(
                progress: displayProgress,
                isPlaying: isThisPlaying,
                onSeek: hasAudio ? { progress in
                    seekToPosition(progress)
                } : nil
            )
            .frame(height: 48)

            // Playback controls
            HStack(spacing: Spacing.md) {
                // Play button
                Button(action: togglePlayback) {
                    ZStack {
                        Circle()
                            .fill(hasAudio ? Color.accentColor : TalkieTheme.surfaceElevated)

                        Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14))
                            .foregroundColor(hasAudio ? .white : TalkieTheme.textMuted)
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(!hasAudio)

                // Progress slider
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(TalkieTheme.surfaceElevated)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * displayProgress)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if hasAudio {
                                    let newProgress = max(0, min(1, value.location.x / geo.size.width))
                                    seekToPosition(newProgress)
                                }
                            }
                    )
                }
                .frame(height: 4)

                // Time display
                Text("\(formatDuration(displayCurrentTime)) / \(formatDuration(utterance.durationSeconds ?? 0))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(TalkieTheme.textMuted)
            }

            // File info row
            if let audioURL = utterance.metadata.audioURL {
                HStack(spacing: 4) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 8))
                        .foregroundColor(TalkieTheme.textMuted)

                    Text(audioURL.lastPathComponent)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(TalkieTheme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button(action: { revealInFinder(audioURL) }) {
                        Text("Reveal")
                            .font(.system(size: 8))
                            .foregroundColor(.accentColor.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(TalkieTheme.divider)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(TalkieTheme.surface, lineWidth: 1)
        )
    }

    private func togglePlayback() {
        guard let url = utterance.metadata.audioURL else { return }
        playback.togglePlayPause(url: url, id: utterance.id.uuidString)
    }

    /// Seek to a position - loads audio first if not already loaded
    private func seekToPosition(_ progress: Double) {
        guard let url = utterance.metadata.audioURL else {
            print("⚠️ seekToPosition: No audio URL")
            return
        }

        print("🎯 seekToPosition: \(Int(progress * 100))% - isLoaded: \(isThisLoaded)")

        // If audio isn't loaded yet, load it first then seek
        if !isThisLoaded {
            print("📂 Loading audio first...")
            playback.play(url: url, id: utterance.id.uuidString)
            playback.pause()  // Load but don't auto-play
        }
        playback.seek(to: progress)
        print("✅ Seeked to \(Int(progress * 100))%")
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func formatDuration(_ duration: Double) -> String {
        let seconds = Int(duration)
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
