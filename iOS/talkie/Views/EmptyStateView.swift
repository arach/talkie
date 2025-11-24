//
//  EmptyStateView.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI

struct EmptyStateView: View {
    let onRecordTapped: () -> Void

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Icon with glow
            ZStack {
                // Outer glow
                Circle()
                    .fill(Color.recording)
                    .frame(width: 140, height: 140)
                    .blur(radius: 40)
                    .opacity(0.3)

                // Background circle
                Circle()
                    .fill(Color.surfaceTertiary)
                    .frame(width: 120, height: 120)

                // Icon
                Image(systemName: "waveform")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.recording, Color.recordingGlow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            // Text
            VStack(spacing: Spacing.sm) {
                Text("Ready to Record")
                    .font(.displaySmall)
                    .foregroundColor(.textPrimary)

                Text("Capture your thoughts with a tap.\nTranscriptions happen automatically.")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Spacer()

            // CTA Button
            Button(action: onRecordTapped) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20, weight: .medium))

                    Text("Record First Memo")
                        .font(.bodyMedium)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: 280)
                .padding(.vertical, Spacing.md)
                .background(
                    LinearGradient(
                        colors: [Color.recording, Color.recordingGlow],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(CornerRadius.md)
                .shadow(color: Color.recording.opacity(0.4), radius: 16, x: 0, y: 8)
            }
            .padding(.bottom, 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfacePrimary)
    }
}

#Preview {
    EmptyStateView(onRecordTapped: {})
}
