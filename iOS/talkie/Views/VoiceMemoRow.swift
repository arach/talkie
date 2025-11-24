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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Play/Pause button
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(memoTitle)
                        .font(.headline)

                    Text(formatDate(memoCreatedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(formatDuration(memo.duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if memo.isTranscribing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if memo.transcription != nil {
                    Image(systemName: "text.alignleft")
                        .foregroundColor(.green)
                }
            }

            // Waveform visualization (if available)
            if let waveformData = memo.waveformData,
               let levels = try? JSONDecoder().decode([Float].self, from: waveformData) {
                WaveformView(levels: levels, height: 40, color: isPlaying ? .blue : .blue.opacity(0.3))
                    .animation(.easeInOut(duration: 0.3), value: isPlaying)
            }

            // Transcription preview
            if let transcription = memo.transcription {
                Text(transcription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
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

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
