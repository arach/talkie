//
//  VoiceMemoRow.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI

struct VoiceMemoRow: View {
    @ObservedObject var memo: VoiceMemo
    @ObservedObject var audioPlayer: AudioPlayerManager
    let onDelete: () -> Void

    @State private var showingDetail = false

    private var memoURL: URL? {
        guard let urlString = memo.fileURL else { return nil }
        return URL(string: urlString)
    }

    private var isPlaying: Bool {
        guard let url = memoURL else { return false }
        return audioPlayer.isPlaying && audioPlayer.currentPlayingURL == url
    }

    private var memoTitle: String {
        memo.title ?? "Recording"
    }

    private var memoCreatedAt: Date {
        memo.createdAt ?? Date()
    }

    var body: some View {
        HStack(spacing: 12) {
            // Play/Pause button
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .buttonStyle(.plain)

            // Waveform and info
            VStack(alignment: .leading, spacing: 4) {
                // Title and duration on same line
                HStack {
                    Text(memoTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Spacer()

                    Text(formatDuration(memo.duration))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                // Compact waveform
                if let waveformData = memo.waveformData,
                   let levels = try? JSONDecoder().decode([Float].self, from: waveformData) {
                    WaveformView(levels: levels, height: 24, color: isPlaying ? .blue : .blue.opacity(0.3))
                        .animation(.easeInOut(duration: 0.3), value: isPlaying)
                }

                // Date and transcription indicator
                HStack(spacing: 6) {
                    Text(formatDateCompact(memoCreatedAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if memo.isTranscribing {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else if memo.transcription != nil {
                        Image(systemName: "text.alignleft")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            showingDetail = true
        }
        .sheet(isPresented: $showingDetail) {
            VoiceMemoDetailView(memo: memo, audioPlayer: audioPlayer)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func togglePlayback() {
        guard let url = memoURL else { return }
        audioPlayer.togglePlayPause(url: url)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDateCompact(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            formatter.timeStyle = .short
            return "Today, \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            formatter.timeStyle = .short
            return "Yesterday, \(formatter.string(from: date))"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE, h:mm a"
            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: date)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
