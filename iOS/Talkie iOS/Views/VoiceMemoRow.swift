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

    @State private var showingDetail = false

    private var memoTitle: String {
        memo.title ?? "Recording"
    }

    private var memoCreatedAt: Date {
        memo.createdAt ?? Date()
    }

    /// File size from audioData or estimated from duration
    private var fileSize: String {
        if let data = memo.audioData {
            return formatFileSize(data.count)
        }
        let estimatedBytes = Int(memo.duration * 16000)
        return formatFileSize(estimatedBytes)
    }

    /// Audio format from filename extension
    private var audioFormat: String {
        guard let filename = memo.fileURL else { return "M4A" }
        let ext = (filename as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "M4A" : ext
    }

    var body: some View {
        Button(action: { showingDetail = true }) {
            HStack(alignment: .top, spacing: 12) {
                // Left side: Name and metadata
                VStack(alignment: .leading, spacing: 4) {
                    Text(memoTitle)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    // Metadata: Time | Size | Format
                    HStack(spacing: 0) {
                        Text(formatTime(memoCreatedAt))
                        Text("  |  ").foregroundColor(.textTertiary.opacity(0.5))
                        Text(fileSize)
                        Text("  |  ").foregroundColor(.textTertiary.opacity(0.5))
                        Text(audioFormat)
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
                }

                Spacer(minLength: 8)

                // Right side: Duration and status badges
                VStack(alignment: .trailing, spacing: 6) {
                    Text(formatDuration(memo.duration))
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.textSecondary)

                    // Status badges - TXT → CLOUD → SPARKLES
                    HStack(spacing: 6) {
                        if memo.isTranscribing {
                            Text("...")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.orange)
                        } else if memo.transcription != nil && !memo.transcription!.isEmpty {
                            Text("TXT")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.green)
                        }

                        if memo.cloudSyncedAt != nil {
                            Image(systemName: "checkmark.icloud.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                        }

                        if memo.summary != nil && !memo.summary!.isEmpty {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.purple)
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingDetail) {
            VoiceMemoDetailView(memo: memo, audioPlayer: audioPlayer)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) || calendar.isDateInYesterday(date) {
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        } else {
            let kb = Double(bytes) / 1024
            return String(format: "%.0f KB", kb)
        }
    }
}
