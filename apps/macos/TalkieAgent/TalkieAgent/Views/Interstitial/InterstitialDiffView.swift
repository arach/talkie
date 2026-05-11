//
//  InterstitialDiffView.swift
//  TalkieAgent
//
//  Diff review view for comparing original and polished text
//

import SwiftUI
import TalkieKit

struct InterstitialDiffView: View {
    let diff: TextDiff
    let onAccept: () -> Void
    let onReject: () -> Void

    private var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var panelBackground: Color {
        isDark ? Color(white: 0.1) : Color(white: 0.98)
    }

    private var contentBackground: Color {
        isDark ? Color(white: 0.12) : Color.white
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

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar

            // Diff content
            diffContent

            // Footer with actions
            footerBar
        }
    }

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("REVIEW CHANGES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(textMuted)

                Text("\(diff.changeCount) changes")
                    .font(.system(size: 11))
                    .foregroundColor(textMuted)
            }

            Spacer()

            Button {
                onReject()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(textMuted)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(isDark ? Color(white: 0.15) : Color(white: 0.95)))
            }
            .buttonStyle(.plain)
            .help("Discard changes (Esc)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var diffContent: some View {
        HStack(spacing: 1) {
            // Original (left)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                    Text("ORIGINAL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                ScrollView {
                    Text(diff.attributedOriginal(baseColor: textPrimary, deleteColor: .red))
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(contentBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(borderColor, lineWidth: 1)
                    )
            )

            // Proposed (right)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    Text("PROPOSED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                ScrollView {
                    Text(diff.attributedProposed(baseColor: textPrimary, insertColor: .green))
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(contentBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var footerBar: some View {
        HStack {
            Button {
                onReject()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .medium))
                    Text("Undo")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(textMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isDark ? Color(white: 0.15) : Color(white: 0.95))
                )
            }
            .buttonStyle(.plain)
            .help("Reject changes")

            Spacer()

            Button {
                onAccept()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Accept")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.green)
                )
            }
            .buttonStyle(.plain)
            .help("Accept changes")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
