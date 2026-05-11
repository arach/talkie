//
//  TORefinementSection.swift
//  Talkie
//
//  Refinement info section — shows context rule applied, model, prompt, original text.
//  Self-gates: renders nothing if no refinement info.
//

import SwiftUI
import TalkieKit

struct TORefinementSection: View {
    let slot: SectionSlot
    let recording: TalkieObject
    let settings: SettingsManager
    @Binding var showOriginalText: Bool

    private var refinement: RefinementInfo? {
        recording.metadata?.refinement
    }

    var body: some View {
        if let refinement = refinement {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Section header
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(.purple)
                    Text("REFINEMENT")
                        .font(settings.fontXSMedium)
                        .tracking(Tracking.wide)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                // Context cards
                HStack(spacing: Spacing.sm) {
                    if let ruleName = refinement.ruleName {
                        contextCard(label: "RULE", value: ruleName, icon: "text.badge.star", color: .purple)
                    }
                    if let model = refinement.model {
                        contextCard(label: "MODEL", value: model, icon: "cpu", color: .purple)
                    }
                }

                // Prompt
                if let prompt = refinement.prompt, !prompt.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("PROMPT")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Text(prompt)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.current.foreground)
                            .padding(Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: CornerRadius.sm)
                                    .fill(Color.purple.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.sm)
                                    .stroke(Color.purple.opacity(0.15), lineWidth: 0.5)
                            )
                    }
                }

                // Original text (collapsible)
                if let rawText = refinement.rawText, !rawText.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showOriginalText.toggle()
                            }
                        } label: {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: showOriginalText ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 8, weight: .semibold))
                                Text("Show original text")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(Theme.current.foregroundSecondary)
                        }
                        .buttonStyle(.plain)

                        if showOriginalText {
                            Text(rawText)
                                .font(.system(size: 12))
                                .foregroundColor(Theme.current.foregroundSecondary)
                                .padding(Spacing.sm)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                                        .fill(Theme.current.foreground.opacity(0.04))
                                )
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func contextCard(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Theme.current.foregroundSecondary)

            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color)

                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.current.foreground)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(Theme.current.foreground.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(color.opacity(0.2), lineWidth: 0.5)
        )
    }
}
