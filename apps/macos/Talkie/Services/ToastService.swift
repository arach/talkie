//
//  ToastService.swift
//  Talkie
//
//  Lightweight app-wide snackbar service for user-action feedback.
//  Surfaces transient messages with an optional action (e.g. Undo) so
//  destructive operations like Delete don't feel terminal.
//
//  Distinct from `ExtensionToast` (milestones/celebrations) which is
//  heavyweight, queued, and lives in ExtensionManager.
//

import Foundation
import SwiftUI

// MARK: - Toast model

/// A single in-flight toast message.
struct Toast: Identifiable, Equatable {
    enum Tone {
        case info
        case success
        case error
    }

    struct Action: Equatable {
        let label: String
        let perform: () -> Void
        static func == (lhs: Action, rhs: Action) -> Bool { lhs.label == rhs.label }
    }

    let id: UUID
    let message: String
    let tone: Tone
    let action: Action?
    let duration: TimeInterval
    let createdAt: Date

    init(
        id: UUID = UUID(),
        message: String,
        tone: Tone = .info,
        action: Action? = nil,
        duration: TimeInterval = 5
    ) {
        self.id = id
        self.message = message
        self.tone = tone
        self.action = action
        self.duration = duration
        self.createdAt = Date()
    }
}

/// App-wide snackbar service. Single toast at a time; the latest
/// replaces any in-flight one (matches the "you just did something,
/// here's the result" UX).
@MainActor
@Observable
final class ToastService {
    static let shared = ToastService()

    /// The currently visible toast. `nil` means the host is empty.
    var current: Toast?

    /// Pending dismiss timer for the current toast.
    private var dismissTask: Task<Void, Never>?

    private init() {}

    // MARK: - Public API

    func show(_ toast: Toast) {
        dismissTask?.cancel()
        current = toast
        scheduleDismiss(after: toast.duration, for: toast.id)
    }

    func showInfo(_ message: String, duration: TimeInterval = 4) {
        show(Toast(message: message, tone: .info, duration: duration))
    }

    func showSuccess(_ message: String, duration: TimeInterval = 4) {
        show(Toast(message: message, tone: .success, duration: duration))
    }

    func showError(_ message: String, duration: TimeInterval = 6) {
        show(Toast(message: message, tone: .error, duration: duration))
    }

    /// Show a toast with an action button (typically Undo).
    func showUndoable(
        _ message: String,
        actionLabel: String = "Undo",
        duration: TimeInterval = 6,
        action: @escaping () -> Void
    ) {
        show(
            Toast(
                message: message,
                tone: .info,
                action: Toast.Action(label: actionLabel, perform: action),
                duration: duration
            )
        )
    }

    /// Dismiss the current toast immediately.
    func dismiss() {
        dismissTask?.cancel()
        current = nil
    }

    /// Invoke the current toast's action (if any) and dismiss.
    func performAction() {
        guard let toast = current, let action = toast.action else { return }
        action.perform()
        dismiss()
    }

    // MARK: - Private

    private func scheduleDismiss(after seconds: TimeInterval, for toastId: UUID) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            // Only dismiss if the in-flight toast is still the one we
            // scheduled for — a newer `show()` might have replaced it.
            if self.current?.id == toastId {
                self.current = nil
            }
        }
    }
}

// MARK: - Host view
//
// Mounted once at the app root (see TalkieApp / TalkieRootWindow).
// Bottom-leading snackbar; auto-dismisses; respects accessibility.

struct ToastHost: View {
    @State private var service = ToastService.shared

    var body: some View {
        VStack {
            Spacer()
            HStack {
                if let toast = service.current {
                    ToastBanner(toast: toast)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                        .padding(.leading, 20)
                        .padding(.bottom, 22)
                }
                Spacer()
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: service.current)
        .allowsHitTesting(service.current != nil)
    }
}

private struct ToastBanner: View {
    let toast: Toast

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconTint)

            Text(toast.message)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.current.foreground)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let action = toast.action {
                Button {
                    ToastService.shared.performAction()
                } label: {
                    Text(action.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.current.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Theme.current.accent.opacity(hovered ? 0.18 : 0.12))
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("z", modifiers: .command)
                .onHover { hovered = $0 }
            }

            Button {
                ToastService.shared.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.current.foregroundMuted)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.current.surface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.current.border.opacity(0.6), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconName: String {
        switch toast.tone {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var iconTint: Color {
        switch toast.tone {
        case .info: return Theme.current.accent
        case .success: return .green
        case .error: return .orange
        }
    }

    private var accessibilityLabel: String {
        if let action = toast.action {
            return "\(toast.message). \(action.label) available."
        }
        return toast.message
    }
}
