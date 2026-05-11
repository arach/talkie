//
//  LiquidGlassTabs.swift
//  Talkie
//
//  Beautiful liquid glass tab selector with smooth animations.
//  Designed for filter toggles like All/Memos/Dictations.
//

import SwiftUI
import TalkieKit

// MARK: - Liquid Glass Tabs

/// A beautiful tab selector with liquid glass styling
/// Use for switching between filter modes (e.g., All/Memos/Dictations)
struct LiquidGlassTabs<T: Hashable & Identifiable>: View where T: CaseIterable, T.AllCases: RandomAccessCollection {
    @Binding var selection: T
    let labelForItem: (T) -> String
    let iconForItem: ((T) -> String)?

    @Namespace private var animation
    @State private var hoveredItem: T? = nil

    init(
        selection: Binding<T>,
        label: @escaping (T) -> String,
        icon: ((T) -> String)? = nil
    ) {
        self._selection = selection
        self.labelForItem = label
        self.iconForItem = icon
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(T.allCases)) { item in
                tabButton(for: item)
            }
        }
        .padding(3)
        .background(
            ZStack {
                // Outer glass container
                Capsule()
                    .fill(.ultraThinMaterial)

                // Subtle gradient overlay
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.02),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Border
                Capsule()
                    .strokeBorder(Theme.current.border.opacity(0.15), lineWidth: 0.5)
            }
        )
    }

    private func tabButton(for item: T) -> some View {
        let isSelected = selection == item
        let isHovered = hoveredItem == item && !isSelected

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selection = item
            }
        } label: {
            HStack(spacing: 5) {
                if let iconForItem = iconForItem {
                    Image(systemName: iconForItem(item))
                        .font(.system(size: 10, weight: .medium))
                }

                Text(labelForItem(item))
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    // Selected pill background
                    ZStack {
                        Capsule()
                            .fill(Theme.current.foreground.opacity(0.12))

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.15),
                                        Color.white.opacity(0.05),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .matchedGeometryEffect(id: "selectedTab", in: animation)
                } else if isHovered {
                    // Hover state
                    Capsule()
                        .fill(Theme.current.foreground.opacity(0.06))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hoveredItem = $0 ? item : nil }
    }
}

// MARK: - Simplified String-Based Tabs

/// Simplified tab selector using strings as items
struct LiquidGlassStringTabs: View {
    let items: [String]
    @Binding var selection: String
    let icons: [String: String]?

    @Namespace private var animation
    @State private var hoveredItem: String? = nil

    init(items: [String], selection: Binding<String>, icons: [String: String]? = nil) {
        self.items = items
        self._selection = selection
        self.icons = icons
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                tabButton(for: item)
            }
        }
        .padding(3)
        .background(
            ZStack {
                Capsule()
                    .fill(.ultraThinMaterial)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.02),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Capsule()
                    .strokeBorder(Theme.current.border.opacity(0.15), lineWidth: 0.5)
            }
        )
    }

    private func tabButton(for item: String) -> some View {
        let isSelected = selection == item
        let isHovered = hoveredItem == item && !isSelected

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selection = item
            }
        } label: {
            HStack(spacing: 5) {
                if let icon = icons?[item] {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .medium))
                }

                Text(item)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    ZStack {
                        Capsule()
                            .fill(Theme.current.foreground.opacity(0.12))

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.15),
                                        Color.white.opacity(0.05),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .matchedGeometryEffect(id: "selectedStringTab", in: animation)
                } else if isHovered {
                    Capsule()
                        .fill(Theme.current.foreground.opacity(0.06))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hoveredItem = $0 ? item : nil }
    }
}

// MARK: - Filter Divider

/// Subtle vertical divider for separating filter groups
struct FilterDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.current.border.opacity(0.2))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 8)
    }
}

// MARK: - Preview

#Preview("Liquid Glass Tabs") {
    struct PreviewWrapper: View {
        @State private var selection = RecordingsFilterType.all

        var body: some View {
            VStack(spacing: 30) {
                // With the enum
                LiquidGlassTabs(
                    selection: $selection,
                    label: { $0.rawValue },
                    icon: { $0.icon }
                )

                // Show all states
                HStack(spacing: 20) {
                    Text("Selected: \(selection.rawValue)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding(40)
            .background(Theme.current.background)
        }
    }

    return PreviewWrapper()
}
