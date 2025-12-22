//
//  SidebarComponents.swift
//  TalkieLive
//
//  Sidebar navigation UI components
//

import SwiftUI

// MARK: - Navigation Section

enum LiveNavigationSection: Hashable {
    case home
    case history      // All items (Recent)
    case queue        // Items waiting to be pasted
    case today        // Today's items
    case logs
    case settings

    /// Whether this section shows the history list (with filters)
    var isHistoryBased: Bool {
        switch self {
        case .history, .queue, .today: return true
        default: return false
        }
    }
}

// MARK: - Sidebar Navigation Item (with hover feedback + collapsed support)

struct SidebarNavItem: View {
    let isSelected: Bool
    let isCollapsed: Bool
    let icon: String
    let title: String
    var badge: String? = nil
    var badgeColor: Color = .secondary
    var isSubtle: Bool = false  // For settings - more muted
    var iconSize: CGFloat = 13  // Default icon size, can be customized
    let action: () -> Void

    @State private var isHovered = false

    private var foregroundColor: Color {
        if isSubtle {
            if isSelected { return TalkieTheme.textSecondary }
            if isHovered { return TalkieTheme.textTertiary }
            return TalkieTheme.textMuted
        } else {
            if isSelected { return TalkieTheme.textPrimary }
            if isHovered { return TalkieTheme.textSecondary }
            return TalkieTheme.textTertiary
        }
    }

    private var backgroundColor: Color {
        if isSelected { return TalkieTheme.hover }
        if isHovered { return TalkieTheme.hover.opacity(0.5) }
        return Color.clear
    }

    var body: some View {
        Button(action: action) {
            if isCollapsed {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: iconSize))
                        .foregroundColor(foregroundColor)
                        .frame(width: 32, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(backgroundColor)
                        )

                    // Badge dot for collapsed mode
                    if badge != nil {
                        Circle()
                            .fill(badgeColor)
                            .frame(width: 6, height: 6)
                            .offset(x: -2, y: 2)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: iconSize))
                        .foregroundColor(foregroundColor)
                        .frame(width: 20)

                    Text(title)
                        .font(.system(size: 12))
                        .foregroundColor(foregroundColor)

                    Spacer()

                    if let badge = badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(badgeColor)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(backgroundColor)
                )
                .padding(.horizontal, 6)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(title)
    }
}

// MARK: - Collapsed Navigation Button

struct CollapsedNavButton: View {
    let icon: String
    var isSelected: Bool = false
    var badge: Int? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .white : (isHovered ? TalkieTheme.textSecondary : TalkieTheme.textTertiary))
                    .frame(width: 36, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Color.accentColor.opacity(0.3) : (isHovered ? TalkieTheme.border : Color.clear))
                    )

                if let badge = badge, badge > 0 {
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor)
                        .cornerRadius(6)
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
