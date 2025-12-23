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

    // Static cached formatters - avoid recreating on every render
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, h:mm a"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()

    private static let calendar = Calendar.current

    private var memoTitle: String {
        memo.title ?? "Recording"
    }

    private var memoCreatedAt: Date {
        memo.createdAt ?? Date()
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {  // 8pt - standard component spacing
            VStack(alignment: .leading, spacing: Spacing.xxs) {  // 2pt - micro gap
                // Title - 13pt medium, primary (100%)
                Text(memoTitle)
                    .font(Theme.current.fontBodyMedium)
                    .foregroundColor(Theme.current.foreground)
                    .lineLimit(1)
                    .debugFont("13pt")
                    .debugHierarchy("100%")

                // Metadata row - 10pt, secondary (70%)
                HStack(spacing: Spacing.xs) {  // 4pt - tight grouping
                    // Source icon - 10pt (on scale)
                    if memo.source != .unknown {
                        Image(systemName: memo.source.icon)
                            .font(Theme.current.fontXS)  // 10pt (was 9pt - off scale!)
                            .foregroundColor(memo.source.color)
                            .debugFont("10pt")
                    }

                    // Duration - MONOSPACE for alignment
                    Text(formatDuration(memo.duration))
                        .font(.monoXSmall)  // Monospace for technical data
                        .debugFont("mono")

                    // Separator - muted (40%)
                    Text("·")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                        .debugHierarchy("40%")

                    // Timestamp
                    Text(formatDateCompact(memoCreatedAt))
                        .font(Theme.current.fontXS)
                        .debugFont("10pt")
                }
                .foregroundColor(Theme.current.foregroundSecondary)
                .debugHierarchy("70%")
                .debugSpacing("xs=4pt")
            }
            .debugSpacing("xxs=2pt")

            Spacer()

            // Processing indicator
            if memo.isTranscribing {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: IconSize.xs, height: IconSize.xs)  // 12pt
            }
        }
        .padding(.vertical, Spacing.sm)  // 8pt (was 6pt - off grid!)
        .padding(.horizontal, Spacing.xs)  // 4pt
        .debugSpacing("sm=8pt")
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatDateCompact(_ date: Date) -> String {
        if Self.calendar.isDateInToday(date) {
            return "Today, \(Self.timeFormatter.string(from: date))"
        } else if Self.calendar.isDateInYesterday(date) {
            return "Yesterday, \(Self.timeFormatter.string(from: date))"
        } else if Self.calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            return Self.weekdayFormatter.string(from: date)
        } else {
            return Self.dateFormatter.string(from: date)
        }
    }

}
