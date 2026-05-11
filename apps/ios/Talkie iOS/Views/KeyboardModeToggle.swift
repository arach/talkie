//
//  KeyboardModeToggle.swift
//  Talkie iOS
//
//  Shared keyboard-mode control used inside keyboard-focused screens.
//

import SwiftUI
import TalkieMobileKit
import UIKit

struct KeyboardModeToggle: View {
    @Binding var isEnabled: Bool

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isEnabled ? Color.success : Color.textTertiary.opacity(0.45))
                    .frame(width: 8, height: 8)

                Text(isEnabled ? "Keyboard On" : "Keyboard Off")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.surfaceSecondary)
            .clipShape(.capsule)
            .overlay(
                Capsule()
                    .stroke(Color.borderPrimary, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isEnabled ? "Keyboard mode on" : "Keyboard mode off")
        .accessibilityHint("Toggle the Talkie keyboard mode for this device.")
    }

    private func toggle() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        if isEnabled {
            HeadlessDictationService.shared.deactivate(explicit: true)
            AppLogger.app.info("Keyboard mode disabled")
        } else {
            HeadlessDictationService.shared.activate()
            AppLogger.app.info("Keyboard mode enabled")
        }
    }
}
