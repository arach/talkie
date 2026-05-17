//
//  EmptyStateView.swift
//  talkie
//
//  Theme-aware empty state shown when there are no memos yet.
//

import SwiftUI

struct EmptyStateView: View {
    let onRecordTapped: () -> Void
    var showsSyncPrompt: Bool = false
    var onSyncTapped: (() -> Void)? = nil
    var onDismissSyncPrompt: (() -> Void)? = nil

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome

        VStack(spacing: Spacing.xl) {
            Spacer(minLength: Spacing.xxl)

            VStack(spacing: Spacing.xl) {
                // Logo card with status
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(theme.colors.cardBackground.opacity(0.9))
                        .frame(width: 132, height: 132)
                        .overlay(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .stroke(chrome.edge, lineWidth: 1)
                        )

                    VStack(spacing: 10) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(theme.colors.textSecondary)

                        HStack(spacing: 6) {
                            TalkieStatusDot(diameter: 8, pulses: true)
                            Text("READY")
                                .font(.techLabel)
                                .tracking(1.5)
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                    }
                }

                VStack(spacing: Spacing.sm) {
                    TalkieEyebrow(text: "Ready for Your First Note", showLeader: false)

                    Text("Record something quick, dictate hands-free, and bring your Mac online whenever you want sync and terminal access.")
                        .font(.bodyMedium)
                        .foregroundStyle(theme.colors.textSecondary)
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
                        .foregroundStyle(chrome.panelInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [chrome.accent, chrome.accentStrong],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(.rect(cornerRadius: 16))
                        .talkieAccentGlow()
                    }

                    if showsSyncPrompt, let onSyncTapped {
                        Button(action: onSyncTapped) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "icloud")
                                    .font(.system(size: 13, weight: .semibold))

                                Text("Sync")
                                    .font(.labelLarge)
                            }
                            .foregroundStyle(theme.colors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(theme.colors.searchBackground.opacity(0.75))
                            .clipShape(.rect(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(chrome.edge, lineWidth: 1)
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
                    .stroke(chrome.edgeFaint, lineWidth: 1)
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
        .background(theme.colors.background)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(Color.clear)
            .glassEffect(.regular.tint(theme.colors.cardBackground.opacity(0.4)))
    }

    private var syncPromptCard: some View {
        let chrome = theme.chrome
        return HStack(alignment: .center, spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(chrome.accentTint)
                    .frame(width: 44, height: 44)

                Image(systemName: "icloud")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(chrome.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Keep your Mac in sync")
                    .font(.headlineSmall)
                    .foregroundStyle(theme.colors.textPrimary)

                Text("Turn on iCloud later if you want memos and device state to follow you across Talkie.")
                    .font(.labelLarge)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let onDismissSyncPrompt {
                Button(action: onDismissSyncPrompt) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.colors.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(theme.colors.cardBackground)
                        .clipShape(.circle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.md)
        .background(theme.colors.cardBackground.opacity(0.9))
        .clipShape(.rect(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(chrome.edge, lineWidth: 1)
        )
    }
}

#Preview {
    EmptyStateView(onRecordTapped: {}, showsSyncPrompt: true)
}
