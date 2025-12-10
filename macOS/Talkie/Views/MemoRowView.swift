//
//  MemoRowView.swift
//  Talkie macOS
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI

struct MemoRowView: View {
    @ObservedObject var memo: VoiceMemo
    private let settings = SettingsManager.shared

    private var memoTitle: String {
        memo.title ?? "Recording"
    }

    private var memoCreatedAt: Date {
        memo.createdAt ?? Date()
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                // Title
                Text(memoTitle)
                    .font(Theme.current.fontBodyMedium)
                    .foregroundColor(settings.tacticalForeground)
                    .lineLimit(1)

                // Minimal metadata: duration + relative time
                HStack(spacing: 4) {
                    Text(formatDuration(memo.duration))
                        .font(settings.fontXS)

                    Text("·")
                        .font(settings.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)

                    Text(formatDateCompact(memoCreatedAt))
                        .font(settings.fontXS)
                }
                .foregroundColor(Theme.current.foregroundSecondary)
            }

            Spacer()

            // Processing indicator (only when active)
            if memo.isTranscribing {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            }
        }
        .padding(.vertical, 6)
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
