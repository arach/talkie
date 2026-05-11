//
//  ExtensionToastOverlay.swift
//  Talkie
//
//  Toast notification component for extensions.
//  Reads from ExtensionManager and displays ExtensionToast messages.
//

import SwiftUI
import TalkieKit

// MARK: - Extension Toast View

struct ExtensionToastView: View {
    let toast: ExtensionToast
    let onDismiss: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Icon
            Image(systemName: toast.icon)
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.accentColor)
                .frame(width: 40, height: 40)

            // Content
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(toast.title)
                    .font(Theme.current.fontBodyBold)
                    .foregroundColor(Theme.current.foreground)

                Text(toast.subtitle)
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)

                // Optional tip
                if let tip = toast.tip {
                    Text(tip)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                        .padding(.top, Spacing.xxs)
                }

                // Optional metadata (e.g., word count, duration)
                if let wordCount = toast.metadata["wordCount"] {
                    Text("Transcribed \(wordCount) words")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundMuted)
                        .padding(.top, Spacing.xxs)
                }
            }

            Spacer()

            // Dismiss button
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(isHovered ? Theme.current.foregroundMuted.opacity(0.2) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
        }
        .padding(Spacing.md)
        .frame(width: 320)
        .background(toastBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
        .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 4)
    }

    @ViewBuilder
    private var toastBackground: some View {
        ZStack {
            // Glass material base
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(.ultraThinMaterial)

            // Subtle gradient overlay
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.05),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Border
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .strokeBorder(
                    Color.white.opacity(0.12),
                    lineWidth: 1
                )
        }
    }
}

// MARK: - Extension Toast Overlay Container

struct ExtensionToastOverlay: View {
    @State private var manager = ExtensionManager.shared

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear

            if let toast = manager.currentToast {
                ExtensionToastView(toast: toast) {
                    manager.dismissCurrentToast()
                }
                .padding(.top, Spacing.lg)
                .padding(.trailing, Spacing.lg)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: manager.currentToast?.id)
    }
}

// MARK: - Preview

#Preview("Extension Toast") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: Spacing.lg) {
            ExtensionToastView(
                toast: ExtensionToast(
                    title: "Your first memo!",
                    subtitle: "You've captured your first thought",
                    icon: "mic.fill",
                    tip: "Tip: Hold \u{2325} to dictate anywhere",
                    metadata: ["wordCount": "47"]
                ),
                onDismiss: {}
            )

            ExtensionToastView(
                toast: ExtensionToast(
                    title: "Double digits!",
                    subtitle: "10 memos recorded",
                    icon: "square.stack.3d.up.fill"
                ),
                onDismiss: {}
            )

            ExtensionToastView(
                toast: ExtensionToast(
                    title: "One week streak!",
                    subtitle: "Recording for 7 days straight",
                    icon: "flame.fill"
                ),
                onDismiss: {}
            )
        }
        .padding()
    }
    .frame(width: 400, height: 500)
}

#Preview("Extension Toast Overlay") {
    ZStack {
        Color.black.ignoresSafeArea()

        Text("Main App Content")
            .foregroundColor(.white)

        ExtensionToastOverlay()
    }
    .frame(width: 600, height: 400)
}
