//
//  MinimalDictationOverlayNext.swift
//  Talkie iOS
//
//  Phase 3+ paint — the live floating overlay shown during keyboard
//  dictation. Sits over whatever app the user is in. Pulse +
//  smallcap "LISTENING" + dismissible. Donor is
//  MinimalDictationOverlay (138 lines).
//

import SwiftUI

@MainActor
final class MinimalDictationOverlayController: ObservableObject {
    static let shared = MinimalDictationOverlayController()
    @Published var isVisible: Bool = false
    @Published var partialText: String = ""
    private init() {}
}

struct MinimalDictationOverlayNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var controller = MinimalDictationOverlayController.shared

    var body: some View {
        if controller.isVisible {
            VStack {
                Spacer()
                pill
                    .padding(.bottom, 100)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeOut(duration: 0.22), value: controller.isVisible)
        }
    }

    private var pill: some View {
        HStack(spacing: 10) {
            // Pulsing red dot — universal recording signal
            RecordingPulse(color: .red, size: 8)
                .frame(width: 8, height: 8)

            Text("LISTENING")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(theme.colors.textPrimary)

            if !controller.partialText.isEmpty {
                Text("·")
                    .foregroundStyle(theme.colors.textTertiary)
                Text(controller.partialText)
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: 200, alignment: .leading)
            }

            Button(action: { controller.isVisible = false }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(theme.colors.textTertiary.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            ZStack {
                Capsule()
                    .fill(theme.colors.cardBackground.opacity(0.88))
                    .background(.ultraThinMaterial, in: Capsule())
                Capsule()
                    .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                  lineWidth: theme.currentTheme.chrome.hairlineWidth)
            }
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .padding(.horizontal, 24)
    }
}

/// Demo wrapper — only rendered on Next surfaces that explicitly
/// want to preview the overlay (e.g. via `--dictationOverlay`
/// launch arg). Real overlay is summoned by the keyboard extension.
struct MinimalDictationOverlayDemoSurface: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()
                Text("Demo surface")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(theme.colors.textTertiary)
                Text("Tap to toggle the overlay")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.colors.textSecondary)
                Button(action: {
                    if MinimalDictationOverlayController.shared.isVisible {
                        MinimalDictationOverlayController.shared.isVisible = false
                    } else {
                        MinimalDictationOverlayController.shared.partialText = "and what i meant to say was"
                        MinimalDictationOverlayController.shared.isVisible = true
                    }
                }) {
                    Text("Toggle overlay")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.colors.cardBackground)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(theme.currentTheme.chrome.accent))
                }
                .buttonStyle(.plain)
                Spacer()
            }

            MinimalDictationOverlayNext()
        }
    }
}
