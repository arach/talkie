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
    var body: some View {
        HStack(spacing: 2) {
            KeyCapView(symbol: "⌥")
            KeyCapView(symbol: "⌘")
            KeyCapView(symbol: "L")
        }
    }
}

struct KeyCapView: View {
    let symbol: String

    var body: some View {
        Text(symbol)
            .font(.system(size: 7, weight: .medium))
            .foregroundColor(.white.opacity(0.9))
            .frame(width: 12, height: 12)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
            )
    }
}
