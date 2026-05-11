//
//  HomeTrendingWidget.swift
//  Talkie
//
//  Top dictation apps widget for the Home page.
//  Shows which apps you dictate into most frequently.
//

import SwiftUI
import TalkieKit

struct HomeTrendingWidget: View, HomeWidget {
    let widgetID = "trending-apps"
    let title = "Top Apps"
    let size: HomeWidgetSize = .half

    let apps: [(name: String, bundleID: String?, count: Int)]

    private let settings = SettingsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Title outside the card
            Text(settings.uiAllCaps ? "TOP APPS" : "Top Apps")
                .font(Theme.current.fontSMMedium)
                .tracking(settings.uiAllCaps ? 1 : 0)
                .foregroundColor(Theme.current.foregroundMuted)

            // Card content — fills height to align with sibling widgets
            Group {
                if apps.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: Spacing.xs) {
                            Image(systemName: "app.dashed")
                                .font(.system(size: 20))
                                .foregroundColor(Theme.current.foregroundMuted)
                            Text("No dictation apps yet")
                                .font(Theme.current.fontSM)
                                .foregroundColor(Theme.current.foregroundMuted)
                        }
                        .padding(.vertical, Spacing.lg)
                        Spacer()
                    }
                } else {
                    VStack(spacing: Spacing.xs) {
                        ForEach(Array(apps.prefix(5).enumerated()), id: \.offset) { _, app in
                            TrendingAppRow(
                                name: app.name,
                                bundleID: app.bundleID,
                                count: app.count,
                                maxCount: apps.first?.count ?? 1
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .cardStyle(cornerRadius: CornerRadius.cardLarge)
        }
    }
}

// MARK: - Trending App Row

private struct TrendingAppRow: View {
    let name: String
    let bundleID: String?
    let count: Int
    let maxCount: Int

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // App icon
            if let bundleID = bundleID {
                AppIconView(bundleIdentifier: bundleID, size: 20)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .frame(width: 20, height: 20)
            }

            // App name
            Text(name)
                .font(.system(size: 12))
                .foregroundColor(Theme.current.foreground)
                .lineLimit(1)

            Spacer()

            // Count
            Text("\(count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.current.foregroundSecondary)

            // Fill bar
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.current.accent.opacity(0.3))
                    .frame(width: geometry.size.width * fillRatio, height: 4)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(width: 40, height: 12)
        }
        .padding(.vertical, 2)
    }

    private var fillRatio: CGFloat {
        guard maxCount > 0 else { return 0 }
        return CGFloat(count) / CGFloat(maxCount)
    }
}
