//
//  HomeActivityWidget.swift
//  Talkie
//
//  Activity widget for the Home page — stat card style with heatmap.
//

import SwiftUI
import TalkieKit

struct HomeActivityWidget: View, HomeWidget {
    let widgetID = "activity-heatmap"
    let title = "Activity"

    let data: [DayActivity]
    let streak: Int
    let totalCount: Int
    var size: HomeWidgetSize { .half }

    private let settings = SettingsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Title outside the card
            Text(settings.uiAllCaps ? "ACTIVITY" : "Activity")
                .font(Theme.current.fontSMMedium)
                .tracking(settings.uiAllCaps ? 1 : 0)
                .foregroundColor(Theme.current.foregroundMuted)

            // Card content — legend + heatmap
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Legend row (right-aligned)
                HStack {
                    Spacer()

                    HStack(spacing: 3) {
                        Text("Less")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.current.foregroundMuted)

                        ForEach([0, 1, 2, 3, 4], id: \.self) { level in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(activityColor(for: level))
                                .frame(width: 8, height: 8)
                        }

                        Text("More")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                }

                // Heatmap grid
                ActivityHeatmapGrid(data: data, weeksToShow: 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .cardStyle(cornerRadius: CornerRadius.cardLarge)
        }
    }

    private func activityColor(for level: Int) -> Color {
        let baseColor = Theme.current.activityHeatmapColor
        switch level {
        case 0: return Theme.current.surface1.opacity(0.5)
        case 1: return baseColor.opacity(0.2)
        case 2: return baseColor.opacity(0.4)
        case 3: return baseColor.opacity(0.6)
        default: return baseColor.opacity(0.85)
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1000 {
            return String(format: "%.1fk", Double(n) / 1000)
        }
        return "\(n)"
    }
}
