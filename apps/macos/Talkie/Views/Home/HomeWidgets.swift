//
//  HomeWidgets.swift
//  Talkie
//
//  Lightweight widget system for home page cards.
//  Provides consistent styling and reusable components.
//

import SwiftUI
import TalkieKit

// MARK: - Widget Container

/// Container that provides consistent card styling for all home widgets
struct WidgetCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = Spacing.md

    private var isTechnical: Bool { TechnicalStyle.isActive }

    init(padding: CGFloat = Spacing.md, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        let radius = CornerRadius.card
        let borderWidth = SettingsManager.shared.currentBorderWidth

        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(Theme.current.surface1)

                    // Matte highlight for Technical theme, glass shimmer for others
                    if isTechnical {
                        RoundedRectangle(cornerRadius: radius)
                            .fill(TechnicalStyle.matteHighlight(surfaceLevel: 1))
                    } else {
                        RoundedRectangle(cornerRadius: radius)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.03),
                                        Color.white.opacity(0.01),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }

                    // Border - more visible for Technical theme
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(
                            isTechnical
                                ? TechnicalStyle.borderLevel1
                                : Theme.current.border.opacity(0.1),
                            lineWidth: borderWidth
                        )
                }
            )
    }
}

// MARK: - Stat Widget

/// Displays a single statistic with icon, value, label, and optional detail
struct StatWidget: View {
    let icon: String
    let value: String
    let label: String
    var detail: String? = nil

    private let settings = SettingsManager.shared
    private var isTechnical: Bool { TechnicalStyle.isActive }

    var body: some View {
        let radius = CornerRadius.card

        VStack(spacing: Spacing.sm) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.current.foregroundSecondary)

            // Value - monospace for Technical, serif for others
            Text(value)
                .font(isTechnical ? .system(size: 28, weight: .light, design: .monospaced) : settings.fontStat)
                .foregroundColor(Theme.current.foreground)

            // Label & Detail
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .textCase(settings.uiTextCase)

                if let detail = detail {
                    Text(detail)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(Theme.current.foregroundMuted)
                        .lineLimit(1)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity)
        .liquidGlassCard(
            cornerRadius: radius,
            isInteractive: true,
            fallbackFill: Theme.current.surface2,
            fallbackStroke: Theme.current.divider
        )
    }
}

// MARK: - Streak Widget

/// Special widget for displaying streak with flame icon
struct StreakWidget: View {
    let days: Int

    private let settings = SettingsManager.shared

    private var flameIcon: String {
        days >= 7 ? "flame.fill" : "flame"
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: flameIcon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(days > 0 ? .orange : Theme.current.foregroundMuted)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(days)")
                    .font(settings.fontStat)
                    .foregroundColor(Theme.current.foreground)

                Text("day streak")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            Spacer()
        }
        .padding(Spacing.md)
        .liquidGlassCard(
            cornerRadius: CornerRadius.md,
            isInteractive: true,
            fallbackFill: Theme.current.surface2,
            fallbackStroke: Theme.current.divider
        )
    }
}

// MARK: - Action Widget

/// Compact action button widget
struct ActionWidget: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Theme.current.foreground)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .liquidGlassCard(
                cornerRadius: CornerRadius.md,
                isInteractive: true,
                fallbackFill: Theme.current.surface2,
                fallbackStroke: Theme.current.divider
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section Header

/// Consistent section header for widget groups
struct WidgetSectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var actionLabel: String = "View All"

    private let settings = SettingsManager.shared

    var body: some View {
        HStack {
            Text(settings.uiAllCaps ? title.uppercased() : title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(settings.uiAllCaps ? 1 : 0)
                .foregroundColor(Theme.current.foregroundMuted)

            Spacer()

            if let action = action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.current.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: Spacing.lg) {
        WidgetSectionHeader(title: "Statistics", action: {})

        HStack(spacing: Spacing.md) {
            StatWidget(icon: "calendar", value: "12", label: "Today", detail: "5 memos, 7 dictations")
            StatWidget(icon: "doc.text.fill", value: "254", label: "Memos", detail: "Voice recordings")
            StatWidget(icon: "waveform", value: "6,829", label: "Dictations", detail: "Quick captures")
            StatWidget(icon: "text.word.spacing", value: "142K", label: "Words", detail: "Total transcribed")
        }

        StreakWidget(days: 39)

        WidgetSectionHeader(title: "Quick Actions")

        HStack(spacing: Spacing.md) {
            ActionWidget(icon: "mic.fill", title: "Record") {}
            ActionWidget(icon: "doc.badge.plus", title: "New Memo") {}
            ActionWidget(icon: "wand.and.stars", title: "Workflows") {}
        }
    }
    .padding()
    .frame(width: 600)
    .background(Theme.current.background)
}
