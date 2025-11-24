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
            VStack(spacing: 0) {
                HStack(spacing: Spacing.sm) {
                    // Left: Title and metadata
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        // Title - monospace for dev tool feel
                        Text(memoTitle)
                            .font(.bodyMedium)
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)

                        // Metadata row - compact, technical
                        HStack(spacing: Spacing.xs) {
                            // Duration with icon
                            HStack(spacing: 2) {
                                Image(systemName: "clock")
                                    .font(.system(size: 9, weight: .medium))
                                Text(formatDuration(memo.duration))
                                    .font(.monoSmall)
                            }
                            .foregroundColor(.textSecondary)

                            Text("·")
                                .font(.labelSmall)
                                .foregroundColor(.textTertiary)

                            // Date
                            Text(formatDateCompact(memoCreatedAt))
                                .font(.labelSmall)
                                .foregroundColor(.textSecondary)

                            // Status indicator
                            if memo.isTranscribing {
                                Text("·")
                                    .font(.labelSmall)
                                    .foregroundColor(.textTertiary)

                                HStack(spacing: 3) {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                    Text("PROC")
                                        .font(.techLabelSmall)
                                        .tracking(0.5)
                                }
                                .foregroundColor(.transcribing)
                            } else if memo.transcription != nil {
                                Text("·")
                                    .font(.labelSmall)
                                    .foregroundColor(.textTertiary)

                                HStack(spacing: 2) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 9, weight: .semibold))
                                    Text("TXT")
                                        .font(.techLabelSmall)
                                        .tracking(0.5)
                                }
                                .foregroundColor(.success)
                            }
                        }
                    }

                    Spacer(minLength: Spacing.xs)

                    // Right: Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
                .padding(.vertical, Spacing.sm)
                .padding(.horizontal, Spacing.md)
            }
            .background(Color.surfaceSecondary)
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingDetail) {
            VoiceMemoDetailView(memo: memo, audioPlayer: audioPlayer)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("DEL", systemImage: "trash.fill")
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
