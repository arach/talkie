//
//  HomeShortcutsWidget.swift
//  Talkie
//
//  Keyboard shortcuts reference widget for the Home page.
//  Shows essential shortcuts: Command Palette, Voice Command, Dictation Toggle.
//

import SwiftUI
import TalkieKit

struct HomeShortcutsWidget: View, HomeWidget {
    let widgetID = "shortcuts"
    let title = "Shortcuts"
    let size: HomeWidgetSize = .half

    private let settings = SettingsManager.shared
    private let shortcuts = SingleKeyShortcutAction.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Title outside the card
            Text(settings.uiAllCaps ? "SHORTCUTS" : "Shortcuts")
                .font(Theme.current.fontSMMedium)
                .tracking(settings.uiAllCaps ? 1 : 0)
                .foregroundColor(Theme.current.foregroundMuted)

            // Card content — fills height to align with sibling widgets
            VStack(spacing: Spacing.xs) {
                ForEach(shortcuts) { action in
                    ShortcutRow(action: action)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .cardStyle(cornerRadius: CornerRadius.cardLarge)
        }
    }
}

// MARK: - Shortcut Row

private struct ShortcutRow: View {
    let action: SingleKeyShortcutAction

    var body: some View {
        Button {
            Task { @MainActor in
                action.perform()
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Text(action.title)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.current.foreground)
                    .lineLimit(1)

                Spacer()

                Text(action.shortcutKey)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.current.foregroundMuted)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Theme.current.surface2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(
                                Theme.current.border.opacity(0.14),
                                lineWidth: 0.5
                            )
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(HomeHoverChrome(style: .standardRow(cornerRadius: 8)))
        }
        .buttonStyle(ShortcutRowButtonStyle())
        .help("\(action.title) (\(action.shortcutKey))")
    }
}

private struct ShortcutRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.clear, lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.84), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Theme.current.surface3.opacity(0.9)
        }
        return Color.clear
    }
}
