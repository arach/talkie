//
//  FeedbackToastNext.swift
//  Talkie iOS
//
//  One shared, transient failure toast for the shell. The voice loop must
//  never fail silently: when a dictation, voice command, or save falls
//  through, the user gets an error haptic and a banner instead of nothing.
//
//  Carries the same amber-CRT terminal material as the Home Message Line
//  (TerminalMessageStrip) — dark glass, scanlines, phosphor mono — so a dropped
//  turn reads as Talkie's own instrument reporting a dead channel, not as a
//  system alert. The mark is the trace itself: the signal line Talkie always
//  draws, flat.
//

import SwiftUI

@MainActor
final class FeedbackToastCenter: ObservableObject {
    static let shared = FeedbackToastCenter()

    struct Toast: Equatable {
        /// Instrument code in the readout's left lane — the channel that failed,
        /// not a severity word. Short and mono: "NO SIGNAL", "NO INPUT", "MIC".
        let code: String
        let message: String
        let actionLabel: String?
        let action: (() -> Void)?

        static func == (lhs: Toast, rhs: Toast) -> Bool {
            lhs.code == rhs.code && lhs.message == rhs.message && lhs.actionLabel == rhs.actionLabel
        }
    }

    @Published private(set) var current: Toast?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    /// Failure the user should feel: error haptic + readout.
    func showError(_ message: String, code: String = "NO SIGNAL", actionLabel: String? = nil, action: (() -> Void)? = nil) {
        Haptics.error.fire()
        show(message, code: code, actionLabel: actionLabel, action: action)
    }

    func show(_ message: String, code: String = "NO SIGNAL", actionLabel: String? = nil, action: (() -> Void)? = nil) {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.22)) {
            current = Toast(code: code, message: message, actionLabel: actionLabel, action: action)
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
///
/// One glyph row: flatline trace · instrument code · message · optional action.
/// Same glass, scanlines and phosphor as the Home Message Line.
struct FeedbackToastOverlay: View {
    @ObservedObject private var center = FeedbackToastCenter.shared
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack {
            if let toast = center.current {
                readout(toast)
                    .padding(.horizontal, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .onTapGesture { center.dismiss() }
            }
            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.22), value: center.current)
        .allowsHitTesting(center.current != nil)
    }

    @ViewBuilder
    private func readout(_ toast: FeedbackToastCenter.Toast) -> some View {
        let shape = RoundedRectangle(cornerRadius: TerminalStripMetrics.corner, style: .continuous)

        HStack(alignment: .center, spacing: 9) {
            status(toast)

            Spacer(minLength: 6)

            if let label = toast.actionLabel {
                Button {
                    let action = toast.action
                    center.dismiss()
                    action?()
                } label: {
                    Text(label)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.9)
                        .textCase(.uppercase)
                        .foregroundStyle(TerminalStripPalette.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .overlay(
                            Capsule().strokeBorder(
                                TerminalStripPalette.accent.opacity(0.55),
                                lineWidth: theme.currentTheme.chrome.hairlineWidth
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, TerminalStripMetrics.padH)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TerminalGlass())
        .clipShape(shape)
        .overlay(
            ScanlineOverlay()
                .fill(Color.black.opacity(TerminalStripMetrics.scanlineOpacity))
                .clipShape(shape)
                .allowsHitTesting(false)
        )
        .overlay(shape.strokeBorder(TerminalStripPalette.accent.opacity(0.28), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func status(_ toast: FeedbackToastCenter.Toast) -> some View {
        HStack(alignment: .center, spacing: 9) {
            FlatlineTrace()
                .stroke(TerminalStripPalette.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 26, height: 12)
                .shadow(color: TerminalStripPalette.accent.opacity(0.6), radius: 3)
                .accessibilityHidden(true)

            Text(toast.code)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.12) // 0.14em at 8pt — matches the Docked Readout label
                .foregroundStyle(TerminalStripPalette.accent)
                .fixedSize()

            Rectangle()
                .fill(TerminalStripPalette.accent.opacity(0.16))
                .frame(width: 1, height: 14)

            Text(toast.message)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .textCase(.uppercase)
                .tracking(0.55) // ≈ 0.05em at 11pt
                .foregroundStyle(TerminalStripPalette.phosphor)
                .shadow(color: TerminalStripPalette.glowInk.opacity(0.7), radius: 1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(toast.code). \(toast.message)")
    }
}

/// The mark for a dropped turn: Talkie's signal trace, alive for two beats and
/// then dead flat. Drawn, not an SF Symbol — the trace is the brand.
private struct FlatlineTrace: Shape {
    func path(in rect: CGRect) -> Path {
        let midY = rect.midY
        let unit = rect.width / 9
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: midY))
        path.addLine(to: CGPoint(x: rect.minX + unit, y: midY))
        path.addLine(to: CGPoint(x: rect.minX + unit * 1.6, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + unit * 2.2, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + unit * 2.8, y: midY - rect.height * 0.28))
        path.addLine(to: CGPoint(x: rect.minX + unit * 3.4, y: midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: midY))
        return path
    }
}
