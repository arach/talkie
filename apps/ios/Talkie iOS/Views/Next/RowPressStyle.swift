//
//  RowPressStyle.swift
//  Talkie iOS
//
//  Shared press-feedback style for tappable list rows across Next
//  surfaces. Subtle background tint + tiny scale on press; eases
//  back smoothly on release. Reads ThemeManager for the right
//  accent tint per theme.
//

import SwiftUI

struct RowPressStyle: ButtonStyle {
    @ObservedObject private var theme = ThemeManager.shared

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Rectangle()
                    .fill(theme.currentTheme.chrome.accentTint)
                    .opacity(configuration.isPressed ? 1 : 0)
                    .animation(.easeOut(duration: configuration.isPressed ? 0 : 0.22),
                               value: configuration.isPressed)
            )
            .scaleEffect(configuration.isPressed ? 0.995 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// Chunkier press feedback for card-shaped buttons (theme preview
/// cards, PICK UP, capture detail hero, etc.). Visible scale +
/// soft shadow lift on press — a more deliberate "this is a card
/// I'm picking up" feel than the rowstyle's whisper of tint.
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.978 : 1.0)
            .brightness(configuration.isPressed ? -0.015 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: configuration.isPressed)
    }
}
