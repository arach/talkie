//
//  EmptyStateView.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI

struct EmptyStateView: View {
    let onRecordTapped: () -> Void
    var showsSyncPrompt: Bool = false
    var onSyncTapped: (() -> Void)? = nil
    var onDismissSyncPrompt: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer(minLength: Spacing.xxl)

            VStack(spacing: Spacing.xl) {
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Color.surfaceSecondary.opacity(0.9))
                        .frame(width: 132, height: 132)
                        .overlay(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .stroke(Color.borderPrimary, lineWidth: 1)
                        )

                    VStack(spacing: 10) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(Color.textSecondary)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.memoAccent)
                                .frame(width: 8, height: 8)

                            Text("READY")
                                .font(.techLabel)
                                .tracking(1.5)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }

                VStack(spacing: Spacing.sm) {
                    Text("READY FOR YOUR FIRST NOTE")
                        .font(.techLabel)
                        .tracking(2)
                        .foregroundStyle(Color.textPrimary)

                    Text("Record something quick, dictate hands-free, and bring your Mac online whenever you want sync and terminal access.")
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: 320)
                }

                HStack(spacing: Spacing.sm) {
                    Button(action: onRecordTapped) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 14, weight: .semibold))

                            Text("Record")
                                .font(.labelLarge)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [Color.memoAccent, Color.memoAccentGlow],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(.rect(cornerRadius: 16))
                    }

                    if showsSyncPrompt, let onSyncTapped {
                        Button(action: onSyncTapped) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "icloud")
                                    .font(.system(size: 13, weight: .semibold))

                                Text("Sync")
                                    .font(.labelLarge)
                            }
                            .foregroundStyle(Color.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.surfacePrimary.opacity(0.75))
                            .clipShape(.rect(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.borderPrimary, lineWidth: 1)
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, 36)
            .frame(maxWidth: 420)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.borderSecondary, lineWidth: 1)
            )
            .padding(.horizontal, Spacing.lg)

            if showsSyncPrompt {
                syncPromptCard
                    .padding(.horizontal, Spacing.xl)
            }

            Spacer()
        }
        .padding(.bottom, 108)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfacePrimary)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(Color.clear)
            .glassEffect(.regular.tint(Color.white.opacity(0.08)))
    }

    private var syncPromptCard: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.active.opacity(0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: "icloud")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.active)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Keep your Mac in sync")
                    .font(.headlineSmall)
                    .foregroundStyle(Color.textPrimary)

                Text("Turn on iCloud later if you want memos and device state to follow you across Talkie.")
                    .font(.labelLarge)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let onDismissSyncPrompt {
                Button(action: onDismissSyncPrompt) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(Color.surfaceSecondary)
                        .clipShape(.circle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.md)
        .background(Color.surfaceSecondary.opacity(0.9))
        .clipShape(.rect(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.borderPrimary, lineWidth: 1)
        )
    }
}

#Preview {
    EmptyStateView(onRecordTapped: {}, showsSyncPrompt: true)
}
