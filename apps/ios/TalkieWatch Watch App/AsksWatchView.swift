//
//  AsksWatchView.swift
//  TalkieWatch
//
//  The third primary page: what the phone is doing with the asks spoken from
//  the wrist. One swipe left of capture, mirroring Codex one swipe right.
//
//  This is a recent guide, not an archive. It shows exactly the asks still held
//  in `recentMemos` — the durable thread lives on the phone, and the footer on
//  a truncated answer says so rather than pretending the wrist has it all.
//

import SwiftUI
import WatchKit

// MARK: - Preview budget

enum WatchAskPreview {
    /// Mirror of the phone's `WatchSessionManager.previewCharacterBudget`. The
    /// Watch folder is a separate Xcode target, so the number is declared twice
    /// and the two declarations reference each other by comment.
    ///
    /// An answer that lands exactly on this length was cut by the phone, which
    /// is the only signal the wrist gets that there is more to read.
    static let characterBudget = 240

    static func isTruncated(_ text: String) -> Bool {
        text.count >= characterBudget
    }
}

// MARK: - Phase & delivery presentation

extension WatchAskPhase {
    /// Semantic colors stay stable across themes: red is failure, green is a
    /// finished answer, orange is waiting on the link, the theme accent is work
    /// in progress.
    func color(chrome: WatchChromeTokens) -> Color {
        switch self {
        case .queued, .sending: return .orange
        case .received, .transcribing, .answering: return chrome.accent
        case .answered: return .green
        case .failed: return .red
        }
    }

    var pulses: Bool { !isTerminal }
}

extension WatchAnswerDelivery {
    /// How the answer was narrated. Rendered as a glyph so provenance costs no
    /// characters out of the preview budget.
    var glyph: String {
        switch self {
        case .watchAudio: return "applewatch.radiowaves.left.and.right"
        case .phoneAudio: return "iphone.radiowaves.left.and.right"
        case .silent: return "speaker.slash"
        }
    }

    var label: String {
        switch self {
        case .watchAudio: return "SPOKEN HERE"
        case .phoneAudio: return "SPOKEN ON IPHONE"
        case .silent: return "NOT SPOKEN"
        }
    }
}

// MARK: - Asks page

struct AsksWatchView: View {
    @EnvironmentObject private var sessionManager: WatchSessionManager

    let isActive: Bool

    var body: some View {
        ZStack {
            WatchInstrumentBackground()

            VStack(spacing: 6) {
                header

                if sessionManager.asks.isEmpty {
                    emptySurface
                } else {
                    ScrollView {
                        VStack(spacing: 5) {
                            if let active = sessionManager.activeAsk {
                                InFlightAskPanel(ask: active)
                            }

                            ForEach(settledAsks) { ask in
                                NavigationLink {
                                    AskDetailView(askId: ask.id)
                                } label: {
                                    SettledAskRow(ask: ask)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 6)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 18)
            .padding(.bottom, 4)
        }
        .onAppear {
            if isActive { sessionManager.markAsksSeen() }
        }
        .onChange(of: isActive) { _, active in
            if active { sessionManager.markAsksSeen() }
        }
    }

    /// Everything the phone has finished with. The in-flight ask is lifted out
    /// into its own panel above, so it must not also appear in the list.
    private var settledAsks: [WatchMemo] {
        let activeId = sessionManager.activeAsk?.id
        return sessionManager.asks.filter { $0.id != activeId }
    }

    private var header: some View {
        let chrome = WatchTheme.current
        return HStack(spacing: 5) {
            WatchEyebrow(text: "Asks", tint: .panelInk, showLeader: false)

            Spacer(minLength: 0)

            if !sessionManager.asks.isEmpty {
                Text("\(sessionManager.asks.count)")
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundStyle(chrome.panelInkFaint)
            }

            WatchStatusDot(
                diameter: 5,
                pulses: sessionManager.activeAsk != nil,
                color: sessionManager.isReachable ? .green : .orange
            )
        }
    }

    private var emptySurface: some View {
        let chrome = WatchTheme.current
        return VStack(spacing: 6) {
            Spacer(minLength: 0)

            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(chrome.accent.opacity(0.55))

            Text("NO ASKS YET")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(chrome.panelInkFaint)

            Text("Swipe right and hold Ask AI")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(chrome.panelInkFaint.opacity(0.75))
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - In-flight panel

/// The one ask the phone still owes an outcome on. It gets the panel rather
/// than a row because "something is happening right now" is the whole reason
/// this page exists.
private struct InFlightAskPanel: View {
    let ask: WatchMemo

    var body: some View {
        let chrome = WatchTheme.current
        let phase = ask.resolvedPhase

        return WatchInstrumentPanel {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    BrailleSpinner(size: 11, color: phase.color(chrome: chrome))

                    Text(phase.label)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(chrome.panelInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 0)

                    Text(ask.timestamp, style: .relative)
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundStyle(chrome.panelInkFaint)
                        .lineLimit(1)
                }

                // Once the phone has transcribed, the preview holds the question
                // itself — the most reassuring thing to show while the answer is
                // still outstanding.
                if let question = ask.transcriptionPreview, !question.isEmpty {
                    Text(question)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(chrome.panelInk.opacity(0.85))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Settled row

private struct SettledAskRow: View {
    let ask: WatchMemo

    var body: some View {
        let chrome = WatchTheme.current
        let phase = ask.resolvedPhase

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                WatchStatusDot(diameter: 4, pulses: false, color: phase.color(chrome: chrome))

                Text(ask.timestamp, style: .relative)
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundStyle(chrome.panelInkFaint)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let delivery = ask.delivery {
                    Image(systemName: delivery.glyph)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(chrome.panelInkFaint)
                        .accessibilityLabel(delivery.label)
                }
            }

            Text(rowText)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(
                    phase == .failed
                        ? Color.red.opacity(0.9)
                        : chrome.panelInk.opacity(0.85)
                )
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: chrome.chromeCorner + 3, style: .continuous)
                .fill(chrome.panelAlt.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: chrome.chromeCorner + 3, style: .continuous)
                        .stroke(chrome.edgeFaint, lineWidth: chrome.hairlineWidth)
                )
        )
        .contentShape(.rect)
    }

    private var rowText: String {
        if let preview = ask.transcriptionPreview, !preview.isEmpty {
            return preview
        }
        return ask.resolvedPhase == .failed ? "Ask failed" : "No answer text"
    }
}

// MARK: - Detail

/// A settled ask, opened. Keyed by id rather than passed by value so the view
/// keeps tracking the memo if a late update lands while it is on screen.
private struct AskDetailView: View {
    @EnvironmentObject private var sessionManager: WatchSessionManager

    let askId: UUID

    var body: some View {
        let chrome = WatchTheme.current

        ScrollView {
            if let ask = sessionManager.recentMemos.first(where: { $0.id == askId }) {
                let phase = ask.resolvedPhase
                let text = ask.transcriptionPreview ?? ""

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        WatchStatusDot(
                            diameter: 4,
                            pulses: phase.pulses,
                            color: phase.color(chrome: chrome)
                        )

                        Text(phase.label)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(0.7)
                            .foregroundStyle(chrome.panelInkFaint)

                        Spacer(minLength: 0)

                        Text(ask.timestamp, style: .relative)
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundStyle(chrome.panelInkFaint)
                    }

                    if text.isEmpty {
                        Text(phase == .failed ? "The phone could not answer this ask." : "No text arrived with this ask.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(chrome.panelInkFaint)
                    } else {
                        Text(text)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(
                                phase == .failed ? Color.red.opacity(0.9) : chrome.panelInk
                            )
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if WatchAskPreview.isTruncated(text) {
                        WatchDivider()

                        Text("FULL ANSWER ON IPHONE")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(0.9)
                            .foregroundStyle(chrome.accent)
                    }

                    if let delivery = ask.delivery {
                        HStack(spacing: 4) {
                            Image(systemName: delivery.glyph)
                                .font(.system(size: 8, weight: .medium))
                            Text(delivery.label)
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .tracking(0.7)
                        }
                        .foregroundStyle(chrome.panelInkFaint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // The display window is small and the phone keeps pushing; a memo
                // can age out from under an open detail view.
                Text("This ask has aged off the watch.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(chrome.panelInkFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 2)
        .background(WatchInstrumentBackground())
        .navigationTitle("Ask")
    }
}

// MARK: - Capture-face strip

/// The one line of ask state the capture face carries. Its height is reserved
/// unconditionally so the record key never moves; at rest the slot is simply
/// empty.
///
/// It shows at most one thing, in priority order: an ask in flight, then a
/// settled ask the wearer has not opened yet. Anything older is the Asks page's
/// job, not the face's.
struct AskStrip: View {
    @EnvironmentObject private var sessionManager: WatchSessionManager
    @Environment(\.watchThemeName) private var themeName

    /// Matches the wordmark-to-key rhythm: tall enough for a 9pt mono label,
    /// short enough that reserving it costs the face nothing at rest.
    private static let stripHeight: CGFloat = 22

    let onOpen: () -> Void

    var body: some View {
        Group {
            if let state {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    onOpen()
                } label: {
                    label(state)
                        .frame(height: Self.stripHeight)
                        // Padded out to a 44pt target, then pulled back so the
                        // face's layout still only spends `stripHeight` on it.
                        .padding(.vertical, (44 - Self.stripHeight) / 2)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.vertical, -(44 - Self.stripHeight) / 2)
                .accessibilityLabel("\(state.text). Open asks.")
            } else {
                Color.clear
            }
        }
        .frame(height: Self.stripHeight)
    }

    private func label(_ state: StripState) -> some View {
        let capture = themeName.captureStyle
        return HStack(spacing: 5) {
            if state.spins {
                BrailleSpinner(size: 10, color: state.color(capture: capture))
            } else {
                Circle()
                    .fill(state.color(capture: capture))
                    .frame(width: 5, height: 5)
            }

            Text(state.text)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(capture.material.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var state: StripState? {
        if let active = sessionManager.activeAsk {
            return .inFlight(active.resolvedPhase)
        }
        if let unseen = sessionManager.unseenAsk {
            return unseen.resolvedPhase == .failed ? .failed : .ready
        }
        return nil
    }

    private enum StripState {
        case inFlight(WatchAskPhase)
        case ready
        case failed

        var text: String {
            switch self {
            case .inFlight(let phase): return phase.label
            case .ready: return "ANSWER READY"
            case .failed: return "ASK FAILED"
            }
        }

        var spins: Bool {
            if case .inFlight = self { return true }
            return false
        }

        func color(capture: WatchCaptureStyle) -> Color {
            switch self {
            case .inFlight: return capture.trace
            case .ready: return .green
            case .failed: return .red
            }
        }
    }
}

#Preview {
    AsksWatchView(isActive: true)
        .environmentObject(WatchSessionManager.shared)
}
