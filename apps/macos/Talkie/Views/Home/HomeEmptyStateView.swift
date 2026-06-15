//
//  HomeEmptyStateView.swift
//  Talkie
//
//  Empty state used by Home cards.
//

import SwiftUI
import TalkieKit

// MARK: - Empty State View

struct EmptyStateView: View {
    let icon: String
    let gradientColors: [Color]
    let title: String
    let subtitle: String
    let buttonTitle: String
    let buttonAction: () -> Void

    @State private var isHovered = false
    @State private var isButtonHovered = false

    var body: some View {
        VStack(spacing: Spacing.md) {
            // Animated icon with gradient
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [gradientColors[0].opacity(0.2), gradientColors[1].opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 64, height: 64)
                    .scaleEffect(isHovered ? 1.1 : 1.0)

                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(isHovered ? 1.05 : 1.0)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isHovered)

            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(Theme.current.fontBodyMedium)
                    .foregroundStyle(Theme.current.foreground)

                Text(subtitle)
                    .font(Theme.current.fontSM)
                    .foregroundStyle(Theme.current.foregroundMuted)
            }

            Button(action: buttonAction) {
                Text(buttonTitle)
                    .font(Theme.current.fontSMMedium)
                    .foregroundStyle(.white)
                    .scaleEffect(isButtonHovered ? 1.05 : 1.0)
            }
            .buttonStyle(.adaptiveGlassProminent)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isButtonHovered)
            .onHover { hovering in
                isButtonHovered = hovering
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
