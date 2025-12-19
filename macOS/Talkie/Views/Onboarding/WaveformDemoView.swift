//
//  WaveformDemoView.swift
//  Talkie macOS
//
//  Waveform visualization ported from TalkieLive onboarding
//  Shows animated audio levels during recording
//

import SwiftUI

// MARK: - Waveform Demo (simplified bars visualization)

struct WaveformDemoView: View {
    let levels: [CGFloat]

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<levels.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color.white.opacity(0.35 + Double(levels[i]) * 0.4))
                    .frame(width: 1.5, height: max(2, 10 * levels[i]))
            }
        }
        .padding(.horizontal, 10)  // More horizontal padding
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.4))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}
