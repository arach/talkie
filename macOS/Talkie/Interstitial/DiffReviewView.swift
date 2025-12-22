//
//  DiffReviewView.swift
//  Talkie
//
//  Side-by-side diff view for reviewing LLM polish changes
//  Original on left (deletions in red), Proposed on right (insertions in green)
//

import SwiftUI

struct DiffReviewView: View {
    let diff: TextDiff
    let onAccept: () -> Void
    let onReject: () -> Void

    // Access manager for prompt info
    @State var manager = InterstitialManager.shared
    @Environment(SettingsManager.self) private var settings
    @State private var showPromptDetails = false

    // MARK: - Theme colors

    private var isDark: Bool { settings.isDarkMode }

    private var panelBackground: Color {
        isDark ? Color(white: 0.1) : Color(white: 0.98)
    }

    private var contentBackground: Color {
        isDark ? Color(white: 0.12) : Color.white
    }

    private var headerBackground: Color {
        isDark ? Color(white: 0.08) : Color(white: 0.94)
    }

    private var inputBackground: Color {
        isDark ? Color(white: 0.15) : Color(white: 0.95)
    }

    private var borderColor: Color {
        isDark ? Color(white: 0.2) : Color(white: 0.88)
    }

    private var textPrimary: Color {
        isDark ? Color.white : Color(white: 0.1)
    }

    private var textMuted: Color {
        isDark ? Color(white: 0.5) : Color(white: 0.55)
    }

    private var deleteColor: Color {
        isDark ? Color(red: 1.0, green: 0.4, blue: 0.4) : Color(red: 0.8, green: 0.2, blue: 0.2)
    }

    private var insertColor: Color {
        isDark ? Color(red: 0.4, green: 0.9, blue: 0.5) : Color(red: 0.15, green: 0.65, blue: 0.25)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar

            // Side-by-side diff
            diffContent

            // Footer with actions
            footerBar
        }
        .background(panelBackground)
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: 0) {
            // Title row
            HStack(spacing: Spacing.sm) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(textMuted)

                Text("REVIEW CHANGES")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(textMuted)

                Spacer()

                // Change count badge
                if diff.changeCount > 0 {
                    Text("\(diff.changeCount) change\(diff.changeCount == 1 ? "" : "s")")
                        .font(Theme.current.fontXS)
                        .foregroundColor(textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(headerBackground)
                        )
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)

            // Model and prompt info (expandable) - at the top where users expect it
            if let lastPrompt = manager.lastPrompt {
                DisclosureGroup(isExpanded: $showPromptDetails) {
                    VStack(alignment: .leading, spacing: 4) {
                        // Full prompt
                        ScrollView {
                            Text(lastPrompt)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(textMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 60)
                        .padding(Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                .fill(inputBackground)
                        )
                    }
                } label: {
                    HStack(spacing: 6) {
                        // Provider icon
                        providerIcon
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(providerColor)

                        // Model name
                        if let provider = manager.lastUsedProvider, let model = manager.lastUsedModel {
                            Text("\(provider) / \(model)")
                                .font(Theme.current.fontXS)
                                .foregroundColor(textMuted)
                        }

                        Image(systemName: showPromptDetails ? "chevron.up" : "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundColor(textMuted)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.sm)
            }
        }
    }

    // MARK: - Provider Icon/Color (duplicated from editor for consistency)

    private var providerIcon: Image {
        guard let providerId = manager.llmProviderId else {
            return Image(systemName: "cpu")
        }
        switch providerId {
        case "openai": return Image(systemName: "sparkle")
        case "anthropic": return Image(systemName: "brain")
        case "google", "gemini": return Image(systemName: "diamond")
        case "groq": return Image(systemName: "bolt")
        case "mlx": return Image(systemName: "laptopcomputer")
        default: return Image(systemName: "cpu")
        }
    }

    private var providerColor: Color {
        guard let providerId = manager.llmProviderId else { return textMuted }
        switch providerId {
        case "openai": return Color(red: 0.3, green: 0.7, blue: 0.5)
        case "anthropic": return Color(red: 0.85, green: 0.55, blue: 0.35)
        case "google", "gemini": return Color(red: 0.3, green: 0.5, blue: 0.9)
        case "groq": return Color(red: 0.9, green: 0.4, blue: 0.3)
        case "mlx": return Color(red: 0.6, green: 0.4, blue: 0.8)
        default: return textMuted
        }
    }

    // MARK: - Diff Content

    private var diffContent: some View {
        HStack(spacing: 0) {
            // Original (left)
            diffPane(
                title: "ORIGINAL",
                indicatorColor: deleteColor,
                content: diff.attributedOriginal(baseColor: textPrimary, deleteColor: deleteColor)
            )

            // Divider
            Rectangle()
                .fill(borderColor)
                .frame(width: 1)

            // Proposed (right)
            diffPane(
                title: "PROPOSED",
                indicatorColor: insertColor,
                content: diff.attributedProposed(baseColor: textPrimary, insertColor: insertColor)
            )
        }
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(contentBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.sm)
    }

    private func diffPane(title: String, indicatorColor: Color, content: AttributedString) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pane header
            HStack(spacing: 6) {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(textMuted)
                Spacer()
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs + 2)
            .background(headerBackground)

            // Pane content
            ScrollView {
                Text(content)
                    .font(Theme.current.contentFontBody)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var accentColor: Color { SettingsManager.shared.resolvedAccentColor }

    private var footerBar: some View {
        VStack(spacing: Spacing.sm) {
            // Voice instruction feedback - show what was spoken to the LLM
            if let voiceInstruction = manager.voiceInstruction {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10))
                        .foregroundColor(accentColor)

                    Text("You said:")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(textMuted)

                    Text(voiceInstruction)
                        .font(Theme.current.fontSM)
                        .foregroundColor(textPrimary)
                        .lineLimit(2)

                    Spacer()
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs + 2)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(accentColor.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .stroke(accentColor.opacity(0.3), lineWidth: 1)
                        )
                )
                .padding(.horizontal, Spacing.lg)
            }

            // Action buttons row
            HStack(spacing: Spacing.sm) {
                Spacer()

                // Reject button
                Button(action: onReject) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                        Text("REJECT")
                            .font(Theme.current.fontXSBold)
                    }
                    .foregroundColor(deleteColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .stroke(deleteColor, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // Accept button
                Button(action: onAccept) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .semibold))
                        Text("ACCEPT")
                            .font(Theme.current.fontXSBold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(insertColor)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.lg)
        }
        .padding(.vertical, Spacing.sm + 2)
    }
}

#Preview {
    let testDiff = DiffEngine.diff(
        original: "The quick brown fox jumps over the lazy dog and runs away quickly",
        proposed: "The fast brown fox leaps over the sleepy dog and runs away"
    )

    return DiffReviewView(
        diff: testDiff,
        onAccept: { print("Accept") },
        onReject: { print("Reject") }
    )
    .frame(width: 600, height: 350)
}
