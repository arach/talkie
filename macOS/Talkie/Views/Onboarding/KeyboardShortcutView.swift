//
//  KeyboardShortcutView.swift
//  Talkie macOS
//
//  Keyboard shortcut display ported from TalkieLive onboarding
//  Shows the hotkey combination (⌥⌘L)
//

import SwiftUI

// MARK: - Keyboard Shortcut Display

struct KeyboardShortcutView: View {
    let colors: OnboardingColors

    var body: some View {
        HStack(spacing: 2) {
            KeyCapView(symbol: "⌥", colors: colors)
            KeyCapView(symbol: "⌘", colors: colors)
            KeyCapView(symbol: "L", colors: colors)
        }
    }
}

struct KeyCapView: View {
    let symbol: String
    let colors: OnboardingColors

    var body: some View {
        Text(symbol)
            .font(.system(size: 7, weight: .medium))
            .foregroundColor(colors.textPrimary.opacity(0.9))
            .frame(width: 12, height: 12)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(colors.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(colors.border, lineWidth: 0.5)
                    )
            )
    }
}
