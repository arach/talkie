//
//  RecentMemosView.swift
//  TalkieWatch
//
//  One chronological timeline of everything captured from the wrist. Asks and
//  memos sit in it as peers: the wearer pressed a button and said something,
//  and what happened next differs only in what came back.
//
//  Deliberately not a reader. A long memo cannot be scanned on a 40mm screen —
//  scrolling one is worse than not having it — so a row commits to what is
//  answerable at a glance: when, how long, where it got to, and whether there
//  is something to press play on. The full text lives on the phone.
//

import SwiftUI

struct RecentMemosView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager

    var body: some View {
        ZStack {
            WatchInstrumentBackground()

            if sessionManager.recentMemos.isEmpty {
                emptySurface
            } else {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(sessionManager.recentMemos) { memo in
                            RecentCaptureRow(memo: memo)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
            }
        }
        .navigationTitle("Recent")
    }

    private var emptySurface: some View {
        let chrome = WatchTheme.current
        return VStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(chrome.accent.opacity(0.55))

            Text("NOTHING YET")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(chrome.panelInkFaint)

            Text("Anything you capture lands here")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(chrome.panelInkFaint.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 14)
    }
}

// MARK: - Row

/// One capture. Two lines: an instrument strip, and whatever text the phone has
/// sent back so far.
private struct RecentCaptureRow: View {
    @EnvironmentObject private var sessionManager: WatchSessionManager

    let memo: WatchMemo

    var body: some View {
        let chrome = WatchTheme.current
        let hasAudio = sessionManager.hasAnswerAudio(for: memo.id)

        HStack(spacing: 6) {
            // Asks have somewhere to go; a memo's detail is the transcript, and
            // this surface has already decided not to be a reader. Linking one
            // and not the other is honest — a row that opens an empty page is
            // worse than a row that does not open.
            if memo.isAsk {
                // Carries its own destination rather than pushing a value onto
                // the root stack's typed path. This screen sits two plain view
                // links deep (More → Recent), and from down there the value
                // push never resolved — the rows were links that did nothing.
                NavigationLink { AskDetailView(askId: memo.id) } label: { summary }
                    .buttonStyle(.plain)
            } else {
                summary
            }

            if hasAudio {
                // A real control here, unlike the indicator on the Asks page.
                // Playback is the only thing this timeline is for, so it gets
                // its own target rather than making the wearer open a page to
                // reach the button — and it sits beside the link rather than
                // inside it, which is what made a second target a coin toss.
                PlayControl(isPlaying: sessionManager.playingAnswerID == memo.id) {
                    sessionManager.toggleAnswerPlayback(memoID: memo.id)
                }
            }
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
        // Same gesture as the Asks page, on the same kind of row: anything the
        // phone still owes an outcome on can be let go of. A settled capture is
        // left alone — it belongs to the phone's history, and this timeline ages
        // it out on its own.
        .dismissOnLongPress(
            title: memo.isAsk ? "Dismiss this ask?" : "Dismiss this memo?",
            isEnabled: memo.isInFlight
        ) {
            sessionManager.dismissCapture(memoID: memo.id)
        }
    }

    private var summary: some View {
        let chrome = WatchTheme.current

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                WatchStatusDot(
                    diameter: 4,
                    pulses: memo.isInFlight,
                    color: statusColor(chrome: chrome)
                )

                Text(kindLabel)
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(chrome.panelInk.opacity(0.75))
                    .lineLimit(1)

                Text(formattedDuration)
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundStyle(chrome.panelInkFaint)

                Spacer(minLength: 0)

                Text(memo.timestamp, style: .relative)
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundStyle(chrome.panelInkFaint)
                    .lineLimit(1)
            }

            if let text = previewText {
                Text(text)
                    .font(.system(size: 11, weight: memo.isAsk ? .medium : .regular))
                    .foregroundStyle(
                        isFailed ? Color.red.opacity(0.9) : chrome.panelInk.opacity(0.85)
                    )
                    // Two lines, then it stops. Anyone who needs the rest of it
                    // needs a screen, not more taps.
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Deliberately not styled like the line above. Nothing has come
                // back yet, and setting the state in the same type as a
                // transcript makes a row that is still waiting look like a row
                // whose contents happen to read "SENDING".
                Text(statusLabel)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(isFailed ? Color.red.opacity(0.9) : chrome.panelInkFaint)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    // MARK: Presentation

    private var isFailed: Bool { memo.status == .failed }

    /// What kind of capture this was, in the wearer's words rather than the
    /// route's. Asks are named as asks; everything else carries the preset it
    /// was recorded under.
    private var kindLabel: String {
        if memo.isAsk { return "ASK" }
        guard let name = memo.presetName, !name.isEmpty else { return "MEMO" }
        return name.uppercased()
    }

    /// Phase for asks, because the phone sends it explicitly and it is the more
    /// truthful of the two. Status for everything else: the phase mapping is
    /// ask-shaped, and reports a finished memo as "answering".
    private func statusColor(chrome: WatchChromeTokens) -> Color {
        if memo.isAsk { return memo.resolvedPhase.color(chrome: chrome) }

        switch memo.status {
        case .sending, .sent: return .orange
        case .received, .thinking: return chrome.accent
        case .transcribed, .answered: return .green
        case .failed: return .red
        }
    }

    /// Same colors, said in words — used only when there is no text yet, so a
    /// row in flight still reports where it got to instead of sitting blank.
    private var statusLabel: String {
        if memo.isAsk { return memo.resolvedPhase.label }

        switch memo.status {
        case .sending: return "SENDING"
        case .sent: return "SENT"
        case .received: return "ON IPHONE"
        case .thinking: return "TRANSCRIBING"
        case .transcribed: return "TRANSCRIBED"
        case .answered: return "ANSWERED"
        case .failed: return "FAILED"
        }
    }

    /// The question for an ask, the transcript for a memo. An ask's preview slot
    /// is taken over by the answer once one arrives, so showing it here would
    /// turn the timeline into a list of answers with no questions attached.
    ///
    /// Nil until the phone has sent something back, which the row reports as a
    /// state rather than as text.
    private var previewText: String? {
        let text = memo.isAsk
            ? (memo.askQuestion ?? memo.transcriptionPreview)
            : memo.transcriptionPreview

        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private var formattedDuration: String {
        let total = max(0, Int(memo.duration.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Play control

private struct PlayControl: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        let chrome = WatchTheme.current

        Button(action: action) {
            ZStack {
                Circle()
                    .fill(chrome.accent.opacity(isPlaying ? 0.34 : 0.16))
                    .overlay(
                        Circle()
                            .stroke(chrome.accent.opacity(0.55), lineWidth: chrome.hairlineWidth)
                    )

                // Stop, not pause: `toggleAnswerPlayback` ends playback rather
                // than holding a position, and there is no scrubber to resume
                // from — labelling it pause would promise something the wrist
                // cannot do.
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(chrome.accent)
            }
            .frame(width: 30, height: 30)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Stop answer" : "Play answer")
    }
}

#Preview {
    RecentMemosView()
        .environmentObject(WatchSessionManager.shared)
}
