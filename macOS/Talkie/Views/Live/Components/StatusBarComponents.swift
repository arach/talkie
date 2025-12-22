//
//  StatusBarComponents.swift
//  Talkie
//
//  Helper components for the status bar
//  Extracted from StatusBar.swift for better organization
//

import SwiftUI
import AppKit
import TalkieKit

// MARK: - Shortcut Hint

struct ShortcutHint: View {
    let label: String
    let shortcut: String

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(TalkieTheme.textMuted.opacity(0.7))

            Text(shortcut)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.5)  // Subtle letter spacing
                .foregroundColor(TalkieTheme.textMuted)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .offset(y: -1)  // Move up 1 pixel
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(TalkieTheme.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
                .offset(y: -1)  // Background moves with content
        )
    }
}

// MARK: - Live Offline Icon

struct LiveOfflineIcon: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image("LiveMenuBarIcon")
                .renderingMode(.template)
                .foregroundColor(TalkieTheme.textMuted.opacity(isHovered ? 0.8 : 0.4))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help("Live Mode is inactive. Click to enable.")
    }
}

// MARK: - Live Environment Badge

struct LiveEnvironmentBadge: View {
    let environment: TalkieEnvironment
    @State private var isHovered = false

    private var badgeColor: Color {
        // Use same color scheme as engine badge for consistency
        switch environment {
        case .production: return .green
        case .staging: return .orange
        case .dev: return .purple
        }
    }

    private var badgeText: String {
        if isHovered {
            return environment.badge  // "STAGE" or "DEV"
        } else {
            // Compact mode: just first letter
            switch environment {
            case .staging: return "S"
            case .dev: return "D"
            case .production: return "P"
            }
        }
    }

    var body: some View {
        Text(badgeText)
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(badgeColor)
            .padding(.horizontal, isHovered ? 4 : 3)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.2))
            .cornerRadius(3)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
            .help("TalkieLive: \(environment.displayName)")
    }
}

// MARK: - Delayed Tooltip Modifier

struct DelayedTooltip: ViewModifier {
    let text: String
    let delay: TimeInterval

    @State private var isHovered = false
    @State private var showTooltip = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        if isHovered {
                            showTooltip = true
                        }
                    }
                } else {
                    showTooltip = false
                }
            }
            .help(showTooltip ? text : "")
    }
}

extension View {
    func delayedHelp(_ text: String, delay: TimeInterval = 0.5) -> some View {
        modifier(DelayedTooltip(text: text, delay: delay))
    }
}

// MARK: - Notification Names

extension Notification.Name {
    // Note: switchToLogs is defined in HistoryViewStubs.swift
    static let switchToSettingsModel = Notification.Name("switchToSettingsModel")
    static let switchToSettingsiCloud = Notification.Name("switchToSettingsiCloud")
    static let switchToSupportingApps = Notification.Name("switchToSupportingApps")

    // Live Settings navigation
    static let switchToLiveSettingsAudio = Notification.Name("switchToLiveSettingsAudio")
    static let switchToLiveSettingsTranscription = Notification.Name("switchToLiveSettingsTranscription")
    static let switchToLiveSettingsOverview = Notification.Name("switchToLiveSettingsOverview")
}
