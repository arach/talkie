//
//  MemoRowView.swift
//  Talkie macOS
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI

struct MemoRowView: View {
    @ObservedObject var memo: VoiceMemo

    private var memoTitle: String {
        memo.title ?? "Recording"
    }

    private var memoCreatedAt: Date {
        memo.createdAt ?? Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title
            Text(memoTitle)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)

            // Metadata
            HStack(spacing: 6) {
                // Duration
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                        .font(.system(size: 9, weight: .medium))
                    Text(formatDuration(memo.duration))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                }
                .foregroundColor(.secondary)

                Text("·")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.5))

                // Date
                Text(formatDateCompact(memoCreatedAt))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                // Status
                if memo.isTranscribing {
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))

                    HStack(spacing: 3) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 10, height: 10)
                        Text("PROC")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                    }
                    .foregroundColor(.purple)
                } else if memo.transcription != nil {
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))

                    HStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 8, weight: .semibold))
                        Text("TXT")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                    }
                    .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
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
}
