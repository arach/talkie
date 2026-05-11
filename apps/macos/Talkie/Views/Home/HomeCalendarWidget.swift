//
//  HomeCalendarWidget.swift
//  Talkie
//
//  Native SwiftUI calendar widget for the Home page.
//  Shows monthly calendar with activity dots and date navigation.
//

import SwiftUI
import TalkieKit

struct HomeCalendarWidget: View, HomeWidget {
    let widgetID = "native-calendar"
    let title = "Calendar"
    let size: HomeWidgetSize = .half

    @State private var displayedMonth = Date()
    @State private var activityData: [String: Int] = [:]

    private let settings = SettingsManager.shared
    private let calendar = Calendar.current
    private let repository = TalkieObjectRepository()

    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]
    private let months = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Month header with navigation
            monthHeader

            // Weekday labels
            weekdayLabels

            // Calendar grid
            calendarGrid
        }
        .cardStyle()
        .task {
            await loadActivityData()
        }
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    goToPreviousMonth()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(monthYearLabel)
                .font(Theme.current.fontSMMedium)
                .tracking(settings.uiAllCaps ? 1 : 0)
                .foregroundColor(Theme.current.foregroundMuted)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    goToNextMonth()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var monthYearLabel: String {
        let month = calendar.component(.month, from: displayedMonth)
        let year = calendar.component(.year, from: displayedMonth)
        let monthName = months[month - 1]
        return settings.uiAllCaps ? "\(monthName.uppercased()) \(year)" : "\(monthName) \(year)"
    }

    // MARK: - Weekday Labels

    private var weekdayLabels: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdays.enumerated()), id: \.offset) { _, day in
                Text(day)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        let days = buildCalendarDays()
        let rows = stride(from: 0, to: days.count, by: 7).map {
            Array(days[$0..<min($0 + 7, days.count)])
        }

        return VStack(spacing: 2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(row) { day in
                        CalendarDayCell(
                            day: day,
                            onTap: { date in
                                navigateToDate(date)
                            }
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // MARK: - Calendar Day Model

    struct CalendarDay: Identifiable {
        let id = UUID()
        let number: Int
        let date: Date?
        let isCurrentMonth: Bool
        let isToday: Bool
        let activityCount: Int
    }

    // MARK: - Build Calendar Days

    private func buildCalendarDays() -> [CalendarDay] {
        var days: [CalendarDay] = []

        let today = calendar.startOfDay(for: Date())
        let month = calendar.component(.month, from: displayedMonth)
        let year = calendar.component(.year, from: displayedMonth)

        // First day of the month
        guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return days
        }

        // Day of week for first day (0 = Sunday)
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth) - 1

        // Days in current month
        guard let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count else {
            return days
        }

        // Days in previous month
        let prevMonth = calendar.date(byAdding: .month, value: -1, to: firstOfMonth)!
        let daysInPrevMonth = calendar.range(of: .day, in: .month, for: prevMonth)?.count ?? 30

        // Add trailing days from previous month
        for i in (0..<firstWeekday).reversed() {
            let dayNumber = daysInPrevMonth - i
            days.append(CalendarDay(
                number: dayNumber,
                date: nil,
                isCurrentMonth: false,
                isToday: false,
                activityCount: 0
            ))
        }

        // Add days of current month
        for day in 1...daysInMonth {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
                continue
            }
            let dateStr = TalkieDate.dbDateKey(date)
            let count = activityData[dateStr] ?? 0
            let isToday = calendar.isDate(date, inSameDayAs: today)

            days.append(CalendarDay(
                number: day,
                date: date,
                isCurrentMonth: true,
                isToday: isToday,
                activityCount: count
            ))
        }

        // Add leading days from next month to complete the grid
        let totalCells = days.count
        let remainingCells = totalCells % 7 == 0 ? 0 : 7 - (totalCells % 7)
        if remainingCells > 0 {
            for day in 1...remainingCells {
                days.append(CalendarDay(
                    number: day,
                    date: nil,
                    isCurrentMonth: false,
                    isToday: false,
                    activityCount: 0
                ))
            }
        }

        return days
    }

    // MARK: - Navigation

    private func goToPreviousMonth() {
        if let newDate = calendar.date(byAdding: .month, value: -1, to: displayedMonth) {
            displayedMonth = newDate
        }
    }

    private func goToNextMonth() {
        if let newDate = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
            displayedMonth = newDate
        }
    }

    private func navigateToDate(_ date: Date) {
        NavigationState.shared.navigateToDate(date)
    }

    // MARK: - Data Loading

    @MainActor
    private func loadActivityData() async {
        // Load activity data from both memos and dictations
        // Activity data uses "yyyy-MM-dd" keys (from TalkieDate.dbDateKey)
        var combinedData: [String: Int] = [:]

        // Load memo heatmap data
        let memoData = MemosViewModel.shared.heatmapData
        for (dateStr, count) in memoData {
            combinedData[dateStr, default: 0] += count
        }

        // Load dictation activity data
        if DatabaseManager.shared.isInitialized {
            if let dictationActivity = try? await repository.dictationActivityByDay(days: 365) {
                for (dateStr, count) in dictationActivity {
                    combinedData[dateStr, default: 0] += count
                }
            }
        }

        activityData = combinedData
    }
}

// MARK: - Calendar Day Cell

private struct CalendarDayCell: View {
    let day: HomeCalendarWidget.CalendarDay
    let onTap: (Date) -> Void

    @State private var isHovered = false

    private let cellSize: CGFloat = 26

    var body: some View {
        Button {
            if let date = day.date {
                onTap(date)
            }
        } label: {
            ZStack {
                // Today highlight
                if day.isToday {
                    Circle()
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(width: cellSize, height: cellSize)
                }

                // Hover highlight
                if isHovered && day.isCurrentMonth {
                    Circle()
                        .fill(Theme.current.surfaceHover)
                        .frame(width: cellSize, height: cellSize)
                }

                VStack(spacing: 1) {
                    // Day number
                    Text("\(day.number)")
                        .font(.system(size: 11, weight: day.isToday ? .semibold : .regular))
                        .foregroundColor(dayTextColor)

                    // Activity dot
                    if day.activityCount > 0 && day.isCurrentMonth {
                        Circle()
                            .fill(activityDotColor)
                            .frame(width: 4, height: 4)
                    } else {
                        Spacer()
                            .frame(height: 4)
                    }
                }
            }
            .frame(width: cellSize, height: cellSize + 6)
        }
        .buttonStyle(.plain)
        .disabled(!day.isCurrentMonth)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var dayTextColor: Color {
        if day.isToday {
            return Color.accentColor
        } else if day.isCurrentMonth {
            return Theme.current.foreground
        } else {
            return Theme.current.foregroundMuted.opacity(0.5)
        }
    }

    private var activityDotColor: Color {
        if day.activityCount >= 3 {
            return Color.green
        } else {
            return Color.green.opacity(0.5)
        }
    }
}

// MARK: - Preview

#Preview {
    HomeCalendarWidget()
        .frame(width: 280)
        .padding()
}
