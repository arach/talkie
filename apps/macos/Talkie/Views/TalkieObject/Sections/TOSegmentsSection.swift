//
//  TOSegmentsSection.swift
//  Talkie
//
//  Segment list for continued memos.
//  Shows all segments (including original) with individual playback
//  and transcript previews. Replaces the singular playback section
//  when a memo has been continued.
//  Self-gates: renders nothing if fewer than 2 segments.
//

import SwiftUI
import AVFoundation
import TalkieKit

struct TOSegmentsSection: View {
    let slot: SectionSlot
    let recording: TalkieObject
    let settings: SettingsManager
    var onContinue: () -> Void = {}

    /// Set by parent to hide the regular playback section when segments are shown
    var onSegmentsLoaded: ((Bool) -> Void)?

    @State private var segments: [TalkieObject] = []
    @State private var isLoaded = false

    // Per-segment playback
    @State private var activePlayer: AVAudioPlayer?
    @State private var activeSegmentId: UUID?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var playbackTimer: Timer?

    private let repository = TalkieObjectRepository()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if segments.count > 1 {
                // Header
                HStack {
                    Text("SEGMENTS")
                        .font(settings.fontXSMedium)
                        .tracking(Tracking.wide)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    Text("\(segments.count)")
                        .font(.techLabelSmall)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.current.foreground.opacity(0.08))
                        .clipShape(Capsule())
                }

                // Segment rows
                VStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        segmentRow(segment, index: index)

                        if index < segments.count - 1 {
                            Divider()
                                .padding(.leading, 36)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(Theme.current.foreground.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(Theme.current.foreground.opacity(0.06), lineWidth: 0.5)
                )
            }
        }
        .frame(minHeight: 1)
        .task(id: recording.id) {
            await loadSegments()
        }
    }

    // MARK: - Segment Row

    private func segmentRow(_ segment: TalkieObject, index: Int) -> some View {
        let isActive = activeSegmentId == segment.id
        let segIsPlaying = isActive && isPlaying

        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                // Play button
                if segment.hasAudio {
                    Button {
                        togglePlayback(segment)
                    } label: {
                        Image(systemName: segIsPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(segIsPlaying ? settings.resolvedAccentColor : Theme.current.foregroundSecondary)
                            .frame(width: 26, height: 26)
                            .background(
                                Circle()
                                    .fill(segIsPlaying ? settings.resolvedAccentColor.opacity(0.12) : Theme.current.foreground.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                } else {
                    Circle()
                        .fill(Theme.current.foregroundMuted.opacity(0.3))
                        .frame(width: 6, height: 6)
                        .frame(width: 26, height: 26)
                }

                // Meta
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Spacing.xs) {
                        Text("Segment \(index + 1)")
                            .font(settings.fontXSMedium)
                            .foregroundColor(index == 0 ? settings.resolvedAccentColor : Theme.current.foregroundSecondary)

                        Text("·")
                            .foregroundColor(Theme.current.foregroundMuted)

                        Text(formatDate(segment.createdAt))
                            .font(settings.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)

                        if segment.duration > 0 {
                            Text("·")
                                .foregroundColor(Theme.current.foregroundMuted)
                            Text(formatDuration(segment.duration))
                                .font(.techLabelSmall)
                                .foregroundColor(Theme.current.foregroundMuted)
                        }
                    }

                    // Progress bar when playing
                    if isActive {
                        HStack(spacing: Spacing.xs) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Theme.current.foreground.opacity(0.08))
                                    Capsule()
                                        .fill(settings.resolvedAccentColor)
                                        .frame(width: duration > 0 ? geo.size.width * (currentTime / duration) : 0)
                                }
                            }
                            .frame(height: 3)

                            Text(formatTime(currentTime))
                                .font(.monoSmall)
                                .foregroundColor(settings.resolvedAccentColor)
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            // Transcript preview
            if let text = segment.text, !text.isEmpty {
                Text(text)
                    .font(settings.fontSM)
                    .foregroundColor(Theme.current.foreground.opacity(0.8))
                    .lineLimit(3)
                    .padding(.leading, 36)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
    }

    // MARK: - Playback

    private func togglePlayback(_ segment: TalkieObject) {
        if activeSegmentId == segment.id, let player = activePlayer {
            if player.isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
                startTimer()
            }
            return
        }

        stopPlayback()

        guard let url = segment.audioURL else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = SettingsManager.shared.playbackVolume
            player.prepareToPlay()
            player.play()

            activePlayer = player
            activeSegmentId = segment.id
            isPlaying = true
            duration = player.duration
            currentTime = 0
            startTimer()
        } catch {
            Log(.audio).error("Failed to play segment: \(error)")
        }
    }

    private func stopPlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        activePlayer?.stop()
        activePlayer = nil
        isPlaying = false
        currentTime = 0
        activeSegmentId = nil
    }

    private func startTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 10.0, repeats: true) { _ in
            Task { @MainActor in
                guard let player = activePlayer else { stopPlayback(); return }
                if !player.isPlaying && isPlaying { stopPlayback(); return }
                currentTime = player.currentTime
            }
        }
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            return "Today \(f.string(from: date))"
        }
        return Self.dateFormatter.string(from: date)
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        } else {
            let m = Int(seconds) / 60
            let s = Int(seconds) % 60
            return "\(m)m \(s)s"
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let m = Int(time) / 60
        let s = Int(time) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func loadSegments() async {
        do {
            let fetched = try await repository.fetchSegments(forNoteId: recording.id)
            await MainActor.run {
                segments = fetched
                isLoaded = true
                onSegmentsLoaded?(fetched.count > 1)
            }
        } catch {
            Log(.database).error("Failed to load segments: \(error)")
            await MainActor.run { isLoaded = true }
        }
    }
}
