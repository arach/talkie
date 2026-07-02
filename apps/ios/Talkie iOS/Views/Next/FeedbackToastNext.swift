//
//  FeedbackToastNext.swift
//  Talkie iOS
//
//  One shared, transient failure toast for the shell. The voice loop must
//  never fail silently: when a dictation, voice command, or save falls
//  through, the user gets an error haptic and a banner instead of nothing.
//  Styled after NetworkStatusBanner so failures speak one visual language.
//

import SwiftUI

@MainActor
final class FeedbackToastCenter: ObservableObject {
    static let shared = FeedbackToastCenter()

    struct Toast: Equatable {
        let message: String
        let actionLabel: String?
        let action: (() -> Void)?

        static func == (lhs: Toast, rhs: Toast) -> Bool {
            lhs.message == rhs.message && lhs.actionLabel == rhs.actionLabel
        }
    }

    @Published private(set) var current: Toast?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    /// Failure the user should feel: error haptic + banner.
    func showError(_ message: String, actionLabel: String? = nil, action: (() -> Void)? = nil) {
        Haptics.error.fire()
        show(message, actionLabel: actionLabel, action: action)
    }

    func show(_ message: String, actionLabel: String? = nil, action: (() -> Void)? = nil) {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.22)) {
            current = Toast(message: message, actionLabel: actionLabel, action: action)
        }
        // Toasts with an action linger a little longer.
        let lifetime: Duration = .seconds(action == nil ? 4 : 6)
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: lifetime)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) { self?.current = nil }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeIn(duration: 0.2)) { current = nil }
    }
}

/// Shell-level overlay that renders the current toast at the top edge,
/// clear of the bottom chrome (tray, pivot, MicFAB).
struct FeedbackToastOverlay: View {
    @ObservedObject private var center = FeedbackToastCenter.shared
    @ObservedObject private var theme = ThemeManager.shared

    // Same terracotta as NetworkStatusBanner — failures share one accent.
    private var accent: Color {
        Color(red: 0.85, green: 0.46, blue: 0.34)
    }

    var body: some View {
        VStack {
            if let toast = center.current {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(accent)

                    Text(toast.message)
                        .talkieType(.preview)
                        .foregroundStyle(theme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    if let label = toast.actionLabel {
                        Button {
                            let action = toast.action
                            center.dismiss()
                            action?()
                        } label: {
                            Text(label)
                                .talkieType(.chipLabel)
                                .foregroundStyle(accent)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(accent.opacity(0.55),
                                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.colors.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(accent.opacity(0.45),
                                              lineWidth: theme.currentTheme.chrome.hairlineWidth)
                        )
                )
                .padding(.horizontal, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .onTapGesture { center.dismiss() }
                .accessibilityAddTraits(.isStaticText)
                .accessibilityLabel(toast.message)
            }
            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.22), value: center.current)
        .allowsHitTesting(center.current != nil)
    }
}
