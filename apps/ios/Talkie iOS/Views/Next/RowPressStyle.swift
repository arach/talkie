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
