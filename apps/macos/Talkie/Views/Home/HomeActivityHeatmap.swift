//
//  HomeActivityHeatmap.swift
//  Talkie
//
//  Activity heatmap grid and tooltip UI for Home surfaces.
//

import SwiftUI
import TalkieKit

// MARK: - Activity Heatmap Grid

struct ActivityHeatmapGrid: View {
    let data: [DayActivity]
    var weeksToShow: Int = 13

    private let spacing: CGFloat = 3
    private let labelWidth: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width - labelWidth - spacing
            // Fixed cell size, expand weeks to fill available width (cap at 26 weeks / ~6 months)
            let cellSize: CGFloat = 13
            let fittableWeeks = min(26, max(weeksToShow, Int((availableWidth + spacing) / (cellSize + spacing))))
            let grid = buildGrid(weeks: fittableWeeks)

            ZStack(alignment: .topLeading) {
                HStack(alignment: .top, spacing: spacing) {
                    // Day labels
                    VStack(alignment: .trailing, spacing: spacing) {
                        ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, day in
                            Text(day)
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.current.foregroundMuted)
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                    .frame(width: labelWidth)

                    // Grid
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(0..<fittableWeeks, id: \.self) { weekIndex in
                            if weekIndex < grid.count {
                                VStack(spacing: spacing) {
                                    ForEach(0..<7, id: \.self) { dayIndex in
                                        if dayIndex < grid[weekIndex].count {
                                            let day = grid[weekIndex][dayIndex]
                                            ActivityHeatmapCell(day: day, cellSize: cellSize)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

            }
            .coordinateSpace(name: "heatmapGrid")
            .overlay(alignment: .topLeading) {
                // Tooltip overlay — renders above all cells, not clipped by grid bounds
                HeatmapTooltipOverlay()
            }
        }
        .frame(height: 7 * 13 + 6 * spacing)
    }

    private func buildGrid(weeks: Int? = nil) -> [[DayActivity]] {
        let effectiveWeeks = weeks ?? weeksToShow
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today)

        var dataByDate: [Date: DayActivity] = [:]
        for day in data {
            dataByDate[calendar.startOfDay(for: day.date)] = day
        }

        let daysBack = (effectiveWeeks - 1) * 7 + (todayWeekday - 1)
        guard let startDate = calendar.date(byAdding: .day, value: -daysBack, to: today) else { return [] }

        var grid: [[DayActivity]] = []
        var currentDate = startDate

        for _ in 0..<effectiveWeeks {
            var week: [DayActivity] = []
            for _ in 0..<7 {
                if currentDate <= today {
                    if let existing = dataByDate[currentDate] {
                        week.append(existing)
                    } else {
                        week.append(DayActivity(date: currentDate, count: 0, level: .none))
                    }
                } else {
                    week.append(DayActivity(date: currentDate, count: -1, level: .none))
                }
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
            }
            grid.append(week)
        }

        return grid
    }
}

// MARK: - Heatmap Tooltip State

@Observable
@MainActor
final class HeatmapTooltipState {
    static let shared = HeatmapTooltipState()
    var day: DayActivity?
    var anchor: CGPoint = .zero  // in "heatmapGrid" coordinate space
    private var dismissTask: Task<Void, Never>?
    private init() {}

    func show(day: DayActivity, anchor: CGPoint) {
        dismissTask?.cancel()
        self.day = day
        self.anchor = anchor
    }

    func dismiss(matching date: Date) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            if self.day?.date == date {
                self.day = nil
            }
        }
    }

    private static let tooltipFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var tooltipText: String? {
        guard let day else { return nil }
        let dateStr = Self.tooltipFormatter.string(from: day.date)
        if day.count == 0 {
            return "No contributions — \(dateStr)"
        } else if day.count == 1 {
            return "1 contribution — \(dateStr)"
        } else {
            return "\(day.count) contributions — \(dateStr)"
        }
    }
}

private struct ActivityHeatmapCell: View {
    let day: DayActivity
    let cellSize: CGFloat

    @State private var isHovered = false

    var body: some View {
        if day.count < 0 {
            Color.clear
                .frame(width: cellSize, height: cellSize)
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(day.level.color)
                .frame(width: cellSize, height: cellSize)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.white.opacity(isHovered ? 0.3 : 0), lineWidth: 1)
                )
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: isHovered) { _, hovered in
                                if hovered {
                                    let frame = geo.frame(in: .named("heatmapGrid"))
                                    HeatmapTooltipState.shared.show(
                                        day: day,
                                        anchor: CGPoint(x: frame.midX, y: frame.minY)
                                    )
                                } else {
                                    HeatmapTooltipState.shared.dismiss(matching: day.date)
                                }
                            }
                    }
                }
                .onHover { isHovered = $0 }
                .onTapGesture {
                    NavigationState.shared.navigateToDate(day.date)
                }
        }
    }
}

/// Tooltip overlay rendered above the entire heatmap grid — never clipped by cells.
private struct HeatmapTooltipOverlay: View {
    private var state: HeatmapTooltipState { HeatmapTooltipState.shared }
    @State private var tooltipSize: CGSize = .zero
    private var tune: TooltipTuning { TooltipTuning.shared }

    var body: some View {
        GeometryReader { geo in
            if let text = state.tooltipText {
                let containerWidth = geo.size.width
                let idealX = state.anchor.x - tooltipSize.width / 2
                let margin: CGFloat = 4
                // Clamp so tooltip doesn't overflow left or right edge
                let clampedX = min(max(idealX, margin), containerWidth - tooltipSize.width - margin)
                // Arrow stays centered on the cell regardless of pill shift
                let arrowX = state.anchor.x - clampedX - tune.arrowSize

                VStack(spacing: 0) {
                    Text(text)
                        .font(.system(size: tune.fontSize, weight: .medium))
                        .foregroundStyle(Theme.current.foreground)
                        .padding(.horizontal, tune.horizontalPadding)
                        .padding(.vertical, tune.verticalPadding)
                        .background(
                            RoundedRectangle(cornerRadius: tune.cornerRadius)
                                .fill(Theme.current.surfaceBase)
                                .shadow(color: .black.opacity(tune.shadowOpacity), radius: tune.shadowRadius, x: 0, y: 2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: tune.cornerRadius)
                                .stroke(Theme.current.foreground.opacity(0.12), lineWidth: 0.5)
                        )

                    // Down-pointing arrow — offset to stay centered on cell
                    HStack(spacing: 0) {
                        Spacer().frame(width: max(0, arrowX))
                        TooltipArrow(direction: .down)
                            .fill(Theme.current.surfaceBase)
                            .frame(width: tune.arrowSize * 2, height: tune.arrowSize)
                        Spacer().frame(minWidth: 0)
                    }
                    .frame(width: tooltipSize.width > 0 ? tooltipSize.width : nil)
                }
                .fixedSize(horizontal: true, vertical: true)
                .background {
                    GeometryReader { tipGeo in
                        Color.clear.onAppear { tooltipSize = tipGeo.size }
                            .onChange(of: tipGeo.size) { _, s in tooltipSize = s }
                    }
                }
                .offset(
                    x: clampedX,
                    y: state.anchor.y - tooltipSize.height - tune.offsetDistance
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.1), value: state.day?.date)
            }
        }
    }
}
