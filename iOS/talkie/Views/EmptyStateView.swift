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

            // Icon - minimal, tactical
            VStack(spacing: Spacing.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .strokeBorder(Color.borderPrimary, lineWidth: 1)
                        .frame(width: 100, height: 100)
                        .background(Color.surfaceSecondary)
                        .cornerRadius(CornerRadius.md)

                    Image(systemName: "waveform")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundColor(.textTertiary)
                }

                // Status text
                VStack(spacing: Spacing.xxs) {
                    Text("NO MEMOS")
                        .font(.techLabel)
                        .tracking(2)
                        .foregroundColor(.textSecondary)

                    Text("SYSTEM READY")
                        .font(.techLabelSmall)
                        .tracking(1.5)
                        .foregroundColor(.textTertiary)
                }
            }

            Spacer()

            // CTA Button - tactical
            Button(action: onRecordTapped) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .medium))

                    Text("START RECORDING")
                        .font(.techLabel)
                        .tracking(1.5)
                }
                .foregroundColor(.white)
                .frame(maxWidth: 240)
                .padding(.vertical, Spacing.md)
                .background(
                    LinearGradient(
                        colors: [Color.recording, Color.recordingGlow],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(CornerRadius.sm)
                .shadow(color: Color.recording.opacity(0.3), radius: 12, x: 0, y: 6)
            }
            .padding(.bottom, 100)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfacePrimary)
    }
}

#Preview {
    EmptyStateView(onRecordTapped: {})
}
