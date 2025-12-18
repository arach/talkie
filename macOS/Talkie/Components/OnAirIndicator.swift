//
//  OnAirIndicator.swift
//  Talkie
//
//  Neon-style "ON AIR" indicator for Live recording
//  Shows in top-left during active recording
//

import SwiftUI

struct OnAirIndicator: View {
    @State private var glowPhase: CGFloat = 0

    var body: some View {
        HStack(spacing: 6) {
            Text("ON AIR")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundColor(.white)
                .shadow(color: .red.opacity(0.8), radius: 4, x: 0, y: 0)
                .shadow(color: .red.opacity(0.6), radius: 8, x: 0, y: 0)
                .shadow(color: .orange.opacity(0.4), radius: 12, x: 0, y: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            ZStack {
                // Outer glow
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.red.opacity(0.3),
                                Color.orange.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blur(radius: 8)
                    .opacity(0.6 + glowPhase * 0.4)

                // Inner background
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.red.opacity(0.15),
                                Color.red.opacity(0.25)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Border glow
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.red,
                                Color.orange
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .shadow(color: .red.opacity(0.6), radius: 4)
            }
        )
        .onAppear {
            startGlowAnimation()
        }
    }

    private func startGlowAnimation() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            glowPhase = 1.0
        }
    }
}

// MARK: - Preview

#Preview("ON AIR") {
    VStack(spacing: 40) {
        OnAirIndicator()

        // Context preview
        HStack {
            OnAirIndicator()
            Spacer()
            Text("Recording...")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 400)
        .background(Color.black.opacity(0.9))
    }
    .padding()
    .frame(width: 500, height: 300)
    .background(Color.black)
}
