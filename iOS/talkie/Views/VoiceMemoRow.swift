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
        guard let filename = memo.fileURL else { return nil }
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(filename)
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
        Button(action: { showingDetail = true }) {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    // Title
                    Text(memoTitle)
                        .font(.bodyMedium)
                        .fontWeight(.medium)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    // Date, duration, and status
                    HStack(spacing: Spacing.xs) {
                        Text(formatDateCompact(memoCreatedAt))
                            .font(.labelSmall)
                            .foregroundColor(.textSecondary)

                        Text("•")
                            .font(.labelSmall)
                            .foregroundColor(.textTertiary)

                        Text(formatDuration(memo.duration))
                            .font(.monoSmall)
                            .foregroundColor(.textSecondary)

                        if memo.isTranscribing {
                            Text("•")
                                .font(.labelSmall)
                                .foregroundColor(.textTertiary)

                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Transcribing")
                                    .font(.labelSmall)
                                    .foregroundColor(.transcribing)
                            }
                        } else if memo.transcription != nil {
                            Text("•")
                                .font(.labelSmall)
                                .foregroundColor(.textTertiary)

                            HStack(spacing: 4) {
                                Image(systemName: "text.alignleft")
                                    .font(.system(size: 10, weight: .medium))
                                Text("Transcript")
                                    .font(.labelSmall)
                            }
                            .foregroundColor(.success)
                        }
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(.vertical, Spacing.md)
            .padding(.horizontal, Spacing.md)
            .background(Color.surfaceSecondary)
            .cornerRadius(CornerRadius.md)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingDetail) {
            VoiceMemoDetailView(memo: memo, audioPlayer: audioPlayer)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash.fill")
            }
            .tint(.recording)
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
