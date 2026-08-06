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
                                    .dismissOnLongPress(title: "Dismiss this ask?") {
                                        sessionManager.dismissCapture(memoID: ask.id)
                                    }
                            }

                            ForEach(settledAsks) { ask in
                                // By value rather than by destination, so a
                                // notification can push the same page without a
                                // row on screen to have been tapped.
                                NavigationLink(value: ask.id) {
                                    SettledAskRow(
                                        ask: ask,
                                        hasAudio: sessionManager.hasAnswerAudio(for: ask.id)
                                    )
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

            Text("Swipe right, tap Ask")
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
    /// Whether the audio for this answer is still on the wrist. An indicator
    /// rather than a control: the row is already a navigation link, and a second
    /// tap target inside one is a coin toss on a 40mm screen.
    let hasAudio: Bool

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

                if hasAudio {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(chrome.accent)
                        .accessibilityLabel("Has audio you can play")
                }

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
/// Not private: the root `NavigationStack` owns the destination now, so a
/// notification opened from the watch face lands here directly.
struct AskDetailView: View {
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

                    // The capture key offers playback for exactly one ask — the
                    // newest unseen one — and opening this view is what marks it
                    // seen. Without a control here, reading an answer destroyed
                    // the only way to ever hear it.
                    if sessionManager.hasAnswerAudio(for: askId) {
                        playButton(chrome: chrome)
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

    /// Full width, because on this screen it is the only thing to press and
    /// aiming is done with a fingertip on a moving wrist.
    private func playButton(chrome: WatchChromeTokens) -> some View {
        let isPlaying = sessionManager.playingAnswerID == askId

        return Button {
            sessionManager.toggleAnswerPlayback(memoID: askId)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 10, weight: .semibold))

                Text(isPlaying ? "STOP" : "PLAY ANSWER")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.9)
            }
            .foregroundStyle(chrome.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: chrome.chromeCorner + 3, style: .continuous)
                    .fill(chrome.panelAlt.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: chrome.chromeCorner + 3, style: .continuous)
                            .strokeBorder(
                                chrome.accent.opacity(0.38),
                                lineWidth: chrome.hairlineWidth
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Stop the answer" : "Play the answer")
    }
}

// MARK: - Capture-face ask state

/// What the capture face has to say about asks, resolved once and read by both
/// surfaces that show it: the status strip under the wordmark and the primary
/// key itself.
///
/// It describes at most one ask, in priority order: one in flight, then a
/// settled one the wearer has not opened yet. Anything older is the Asks page's
/// job, not the face's.
enum WatchAskFace {
    case waiting(WatchAskPhase)
    case inFlight(WatchAskPhase)
    case stalled
    case ready
    case failed

    /// How far back the capture face will reach for an ask that never settled.
    ///
    /// `recentMemos` is persisted, and nothing on the phone can retroactively
    /// close out an ask the wrist recorded before it was last killed — so those
    /// come back from disk still marked in flight, already long past
    /// `silenceTolerance`, and the face used to open on NO RESPONSE about
    /// something the wearer very likely settled on the phone hours ago. Past
    /// this horizon the ask is history rather than news: the Asks page still
    /// lists it with its real state, which is where a dead ask belongs.
    static let horizon: TimeInterval = 20 * 60

    @MainActor
    static func resolve(_ sessionManager: WatchSessionManager, asOf now: Date) -> WatchAskFace? {
        if let active = sessionManager.activeAsk,
           now.timeIntervalSince(active.lastHeardAt) <= horizon {
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

    /// Whether this state is worth the primary key.
    ///
    /// `waiting` and `stalled` are deliberately excluded even though they are
    /// the most visible: both can persist indefinitely — a queued ask until the
    /// phone comes back, a stalled one forever, since a stalled ask never
    /// reaches a terminal phase — and either would hold the record key hostage.
    /// They stay in the strip, where they cost nothing.
    var takesCaptureKey: Bool {
        switch self {
        case .inFlight, .ready, .failed: return true
        case .waiting, .stalled: return false
        }
    }

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

// MARK: - Capture-face strip

/// The one line of state the capture face carries, and the caption under its
/// signal field. Its height is reserved unconditionally so the record key never
/// moves.
///
/// An ask in flight owns the line whenever there is one. Failing that, the line
/// reports captures the phone has stopped acknowledging — the one thing this
/// face cannot otherwise tell you, and the only reason a memo you spoke never
/// turns up anywhere.
///
/// Silent the rest of the time, deliberately. It briefly said how long ago the
/// last capture was, which is true, decorative, and acted on by nobody; a line
/// that is always saying something teaches the wearer to stop reading it. The
/// signal field above already carries recency, in a form you can take in without
/// parsing. Empty here means nothing needs you.
struct AskStrip: View {
    @EnvironmentObject private var sessionManager: WatchSessionManager
    @Environment(\.watchThemeName) private var themeName

    /// Tall enough for a 9pt mono label, short enough that reserving it costs
    /// the face little at rest. The capture face solves its own value against
    /// the watch it is running on.
    var height: CGFloat = 22

    let onOpen: () -> Void

    /// The strip is padded out to a real tap target and then pulled back, so
    /// the face's layout still only spends `height` on it.
    private var targetInset: CGFloat { max(0, (44 - height) / 2) }

    var body: some View {
        // Same reason as the Asks page: a phone that has gone quiet announces
        // itself only by the clock advancing, so the strip has to re-read it.
        TimelineView(.periodic(from: .now, by: WatchMemo.silenceTolerance / 2)) { context in
            Group {
                if let state = WatchAskFace.resolve(sessionManager, asOf: context.date) {
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        onOpen()
                    } label: {
                        label(state)
                            .frame(height: height)
                            .padding(.vertical, targetInset)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, -targetInset)
                    .accessibilityLabel("\(state.spokenText). Open asks.")
                } else if let waiting = waitingText(asOf: context.date) {
                    // Not a button. What it names is a memo, and memos live two
                    // pushes away under Recent rather than on the Asks page this
                    // strip opens — a tap target that lands somewhere else is
                    // worse than a label that stays put.
                    waitingLabel(waiting)
                        .frame(height: height)
                } else {
                    Color.clear
                }
            }
            .frame(height: height)
        }
        .frame(height: height)
    }

    private func label(_ state: WatchAskFace) -> some View {
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

    /// Shaped like the ask line above it, because it means the same kind of
    /// thing: something the wearer said is not where they think it is.
    ///
    /// The theme's trace, not a literal orange. Trace *is* amber on every dark
    /// finish, which is why the hardcoded colour looked right for as long as it
    /// did — but on light mineral the theme runs blue, and a lone orange dot
    /// there is the one mark on the face that belongs to no theme at all.
    private func waitingLabel(_ text: String) -> some View {
        let capture = themeName.captureStyle
        return HStack(spacing: 5) {
            Circle()
                .fill(capture.trace)
                .frame(width: 5, height: 5)

            Text(text)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(capture.material.ink.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    /// Memos the phone has gone quiet on, or nil when everything has landed.
    ///
    /// Non-asks only: an ask in this state is already the branch above, and
    /// counting it twice would put the same capture on the line under two
    /// different names.
    ///
    /// Gated on the same silence tolerance the ask face uses rather than firing
    /// the moment a memo starts sending. A capture in flight for two seconds is
    /// the system working; one still in flight minutes later is the phone having
    /// stopped answering, and only the second is worth a line.
    private func waitingText(asOf now: Date) -> String? {
        let stranded = sessionManager.recentMemos.filter { memo in
            guard !memo.isAsk, memo.isInFlight else { return false }
            let heardFrom = memo.lastUpdatedAt ?? memo.timestamp
            return now.timeIntervalSince(heardFrom) > WatchMemo.silenceTolerance
        }

        guard !stranded.isEmpty else { return nil }
        return stranded.count == 1 ? "1 MEMO WAITING" : "\(stranded.count) MEMOS WAITING"
    }
}

// MARK: - Capture-face key

/// The primary key while an ask owns the face.
///
/// The record key is the right primary action only when nothing else is
/// happening. With an answer in flight it was the loudest thing on a screen
/// whose actual subject was an AI conversation — a signal trace over a mic
/// glyph, which reads as "memo" no matter what the strip above it says.
///
/// It borrows the record key's exact chassis and footprint, so what changes is
/// what the key is *for*, not where anything sits.
struct AskCaptureKey: View {
    @EnvironmentObject private var sessionManager: WatchSessionManager
    @Environment(\.watchThemeName) private var themeName

    let state: WatchAskFace
    /// Matched to the record key it replaces, so the face's geometry does not
    /// shift underneath the wearer's thumb when an ask takes the slot.
    var keyHeight: CGFloat = 64
    let onOpen: () -> Void

    var body: some View {
        let capture = themeName.captureStyle

        Button(action: activate) {
            TalkieKeyChassis(accent: keyAccent(capture: capture), height: keyHeight) {
                VStack(spacing: 5) {
                    motif(capture: capture)

                    legendText(capture: capture)
                }
                .padding(.horizontal, 8)
            }
        }
        .buttonStyle(TalkieRecordButtonStyle())
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func motif(capture: WatchCaptureStyle) -> some View {
        switch state {
        case .inFlight:
            // A conversation thinking cadence, not a level meter. Nothing here
            // is derived from audio, because nothing here is about audio.
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(capture.trace)

                WatchThinkingDots(color: capture.trace)
            }
            .frame(height: 22)

        case .ready:
            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(capture.trace)
                .frame(height: 22)
                .contentTransition(.symbolEffect(.replace))
                .animation(.easeInOut(duration: 0.16), value: isPlaying)

        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.red.opacity(0.92))
                .frame(height: 22)

        case .waiting, .stalled:
            // Never routed here — these states leave the key to recording.
            EmptyView()
        }
    }

    /// Two different kinds of text share this slot, and they are not
    /// interchangeable. Fixed tokens are mono and tracked out, matching the REC
    /// legend they replace. The wearer's own question is prose — uppercasing it
    /// or spacing it out would make the one human sentence on the face the
    /// hardest thing on it to read.
    @ViewBuilder
    private func legendText(capture: WatchCaptureStyle) -> some View {
        if case .inFlight = state, let question = questionSummary {
            Text(question)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(capture.material.keyInk.opacity(0.78))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        } else {
            Text(token)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(capture.material.keyInk.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    /// The question, once the phone has transcribed it, is the most reassuring
    /// thing the key can hold: proof of what is actually being answered.
    private var questionSummary: String? {
        guard let question = sessionManager.activeAsk?.askQuestion else { return nil }
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var token: String {
        switch state {
        case .inFlight:
            return "THINKING"
        case .ready:
            if isPlaying { return "STOP" }
            return canPlay ? "PLAY ANSWER" : "READ ANSWER"
        case .failed:
            return "SEE WHY"
        case .waiting, .stalled:
            return ""
        }
    }

    private var accessibilityText: String {
        switch state {
        case .inFlight:
            if let questionSummary {
                return "Answering: \(questionSummary). Open asks."
            }
            return "\(state.spokenText). Open asks."
        case .ready:
            if isPlaying { return "Stop the answer" }
            return canPlay ? "Play the answer" : "Answer ready. Read it."
        case .failed:
            return "Ask failed. See why."
        case .waiting, .stalled:
            return state.spokenText
        }
    }

    /// Only the readable answer glows green; work in progress and failure keep
    /// the key's own accent so the chassis does not flash a verdict mid-flight.
    private func keyAccent(capture: WatchCaptureStyle) -> Color {
        switch state {
        case .ready: return capture.trace
        case .failed: return Color.red.opacity(0.55)
        default: return capture.trace
        }
    }

    private var readyAsk: WatchMemo? {
        sessionManager.unseenAsk
    }

    private var canPlay: Bool {
        guard let readyAsk else { return false }
        return sessionManager.hasAnswerAudio(for: readyAsk.id)
    }

    private var isPlaying: Bool {
        guard let readyAsk else { return false }
        return sessionManager.playingAnswerID == readyAsk.id
    }

    private func activate() {
        // Playback is the whole point of the ready key: an answer you can hear
        // without navigating anywhere. Everything else opens the Asks page,
        // which is where text lives.
        if case .ready = state, canPlay, let readyAsk {
            sessionManager.toggleAnswerPlayback(memoID: readyAsk.id)
            return
        }
        WKInterfaceDevice.current().play(.click)
        onOpen()
    }
}

/// Three dots in a conversational cadence. Deliberately not a waveform: the
/// wrist is waiting on a reply, and every other animation on this face is
/// already about sound going in.
struct WatchThinkingDots: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0

    private static let count = 3
    private static let cadence: TimeInterval = 0.34

    var body: some View {
        HStack(spacing: 3.5) {
            ForEach(0..<Self.count, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
                    .opacity(opacity(for: index))
                    .scaleEffect(index == phase && !reduceMotion ? 1.25 : 1)
            }
        }
        .animation(.easeInOut(duration: Self.cadence), value: phase)
        // A `Timer` here would outlive the view — the key swaps out the moment
        // the answer lands, and nothing would invalidate it. The publisher is
        // torn down with the subscription.
        .onReceive(Timer.publish(every: Self.cadence, on: .main, in: .common).autoconnect()) { _ in
            guard !reduceMotion else { return }
            phase = (phase + 1) % Self.count
        }
    }

    private func opacity(for index: Int) -> Double {
        guard !reduceMotion else { return 0.62 }
        return index == phase ? 1 : 0.34
    }
}

#Preview {
    AsksWatchView(isActive: true)
        .environmentObject(WatchSessionManager.shared)
}
