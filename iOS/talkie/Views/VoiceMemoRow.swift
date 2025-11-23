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

    private var isPlaying: Bool {
        guard let memoURL = memo.wrappedFileURL else { return false }
        return audioPlayer.isPlaying && audioPlayer.currentPlayingURL == memoURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Play/Pause button
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(memo.wrappedTitle)
                        .font(.headline)

                    Text(formatDate(memo.wrappedCreatedAt))
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
                WaveformView(levels: levels, height: 40)
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
    }

    private func togglePlayback() {
        guard let url = memo.wrappedFileURL else { return }
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
