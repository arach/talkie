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

    /// VoiceOver reads ALLCAPS mono tokens letter by letter, so what is spoken
    /// is deliberately not the string that is drawn.
    var spokenLabel: String {
        switch self {
        case .watchAudio: return "Spoken on this watch"
        case .phoneAudio: return "Spoken on iPhone"
        case .silent: return "Not spoken aloud"
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
                            ForEach(inFlightAsks) { ask in
                                InFlightAskPanel(ask: ask)
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

    /// Asks the phone still owes an outcome on. Partitioned on `isInFlight`
    /// rather than on identity with `activeAsk`, which is only ever the *first*
    /// one: a second ask spoken before the first settled used to fall through to
    /// the settled list and draw as a static row, reading as finished when it
    /// was not.
    private var inFlightAsks: [WatchMemo] {
        sessionManager.asks.filter(\.isInFlight)
    }

    /// Everything the phone has finished with. In-flight asks are lifted out
    /// into panels above, so they must not also appear in the list.
    private var settledAsks: [WatchMemo] {
        sessionManager.asks.filter { !$0.isInFlight }
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

            Text("Swipe right, tap Ask AI")
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
        // The phone cannot report that it has stopped reporting, so the only
        // way the wrist ever notices is by re-reading the clock on its own.
        // Half the tolerance keeps the worst-case lag to ~45s.
        TimelineView(.periodic(from: .now, by: WatchMemo.silenceTolerance / 2)) { context in
            panel(stalled: ask.isStalled(asOf: context.date))
        }
    }

    private func panel(stalled: Bool) -> some View {
        let chrome = WatchTheme.current
        let phase = ask.resolvedPhase
        // Orange is already "waiting on the link" everywhere else on this page,
        // and a silent phone is the same category of problem.
        let tint = stalled ? Color.orange : phase.color(chrome: chrome)

        return WatchInstrumentPanel {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    if stalled {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(tint)
                            .frame(width: 11, height: 11)
                    } else {
                        BrailleSpinner(size: 11, color: tint)
                    }

                    Text(stalled ? "NO RESPONSE" : phase.label)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(stalled ? tint : chrome.panelInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 0)

                    Text(ask.timestamp, style: .relative)
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundStyle(chrome.panelInkFaint)
                        .lineLimit(1)
                }

                if stalled {
                    Text("Check iPhone")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(chrome.panelInkFaint)
                }

                // Once the phone has transcribed, the preview holds the question
                // itself — the most reassuring thing to show while the answer is
                // still outstanding.
                if let question = ask.transcriptionPreview, !question.isEmpty {
                    Text(question)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(chrome.panelInk.opacity(0.85))
                        .lineLimit(stalled ? 2 : 3)
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
                        .accessibilityLabel(delivery.spokenLabel)
                }
            }

            // The question leads. This page answers "what did I ask", and
            // scanning it for that is the only reason to open it — a list of
            // answers with the questions overwritten is unreadable.
            if let question = ask.askQuestion, !question.isEmpty {
                Text(question)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(chrome.panelInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(rowText)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(
                    phase == .failed
                        ? Color.red.opacity(0.9)
                        : chrome.panelInk.opacity(0.85)
                )
                // The question above already carries the row; the outcome under
                // it is a confirmation, not the content.
                .lineLimit(ask.askQuestion == nil ? 2 : 1)
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

                    // What was asked, above what came back. On a failure this is
                    // the only surviving record of the ask, since the preview
                    // slot has been taken over by the failure reason.
                    if let question = ask.askQuestion, !question.isEmpty {
                        Text(question)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(chrome.panelInk)
                            .fixedSize(horizontal: false, vertical: true)

                        WatchDivider()
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

                    // Only an answer can be continued on the phone. A long
                    // question, or a wordy failure, used to trip this and point
                    // the wearer at an answer that does not exist.
                    if phase == .answered, WatchAskPreview.isTruncated(text) {
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
        .padding(.horizontal, 10)
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
        // Same reason as the Asks page: a phone that has gone quiet announces
        // itself only by the clock advancing, so the strip has to re-read it.
        TimelineView(.periodic(from: .now, by: WatchMemo.silenceTolerance / 2)) { context in
            Group {
                if let state = state(asOf: context.date) {
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
                    .accessibilityLabel("\(state.spokenText). Open asks.")
                } else {
                    Color.clear
                }
            }
            .frame(height: Self.stripHeight)
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
                .foregroundStyle(state.inkColor(capture: capture))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func state(asOf now: Date) -> StripState? {
        if let active = sessionManager.activeAsk {
            if active.isStalled(asOf: now) { return .stalled }
            switch active.resolvedPhase {
            // The wrist has not handed this off yet — a materially different
            // situation from the phone working on it, and one the wearer can
            // actually do something about.
            case .queued, .sending: return .waiting(active.resolvedPhase)
            default: return .inFlight(active.resolvedPhase)
            }
        }
        if let unseen = sessionManager.unseenAsk {
            return unseen.resolvedPhase == .failed ? .failed : .ready
        }
        return nil
    }

    private enum StripState {
        case waiting(WatchAskPhase)
        case inFlight(WatchAskPhase)
        case stalled
        case ready
        case failed

        var text: String {
            switch self {
            case .waiting(let phase), .inFlight(let phase): return phase.label
            case .stalled: return "NO RESPONSE"
            case .ready: return "ANSWER READY"
            case .failed: return "ASK FAILED"
            }
        }

        /// Spoken, not displayed: VoiceOver spells out ALLCAPS mono tokens.
        var spokenText: String {
            switch self {
            case .waiting: return "Ask waiting to send"
            case .inFlight: return "Ask in progress"
            case .stalled: return "No response from iPhone"
            case .ready: return "Answer ready"
            case .failed: return "Ask failed"
            }
        }

        var spins: Bool {
            if case .inFlight = self { return true }
            return false
        }

        func color(capture: WatchCaptureStyle) -> Color {
            switch self {
            case .inFlight: return capture.trace
            case .waiting, .stalled: return .orange
            case .ready: return .green
            case .failed: return .red
            }
        }

        /// The dot alone is a 5pt speck. On the face you actually look at, an
        /// outcome worth reacting to has to carry its color in the text too.
        func inkColor(capture: WatchCaptureStyle) -> Color {
            switch self {
            case .waiting, .inFlight: return capture.material.inkFaint
            case .stalled, .ready, .failed: return color(capture: capture)
            }
        }
    }
}

#Preview {
    AsksWatchView(isActive: true)
        .environmentObject(WatchSessionManager.shared)
}
