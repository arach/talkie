//
//  CaptureUnderside.swift
//  TalkieWatch
//
//  What the crown finds under the capture face.
//
//  The face above is deliberately finished — one key, one pair of routes, and
//  a roll. Everything that did not earn a place up there had, until now, no
//  place at all: three of the app's five capture presets were reachable only
//  from a phone deep link, and whether the phone was even listening was
//  something the watch knew and never said.
//
//  So this is not a second page. A second page is a thing you navigate to; this
//  is the same page continuing past the fold, and it is written in the face's
//  own vocabulary — capture materials, the key's bevel, the same gutters —
//  rather than the instrument chrome the pushed screens use. Scrolling down
//  should feel like more of the object, not like arriving somewhere else.
//

import SwiftUI
import WatchKit

struct CaptureUnderside: View {
    @EnvironmentObject private var sessionManager: WatchSessionManager
    @Environment(\.watchThemeName) private var themeName
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    /// Starts a capture with a preset the face above has no room for.
    let onCapture: (WatchPreset) -> Void

    /// The gutter the face's key and quick row share. Matched exactly: the
    /// underside is the same column of objects, continued.
    private static let inset = CaptureFaceMetrics.bodyInset
    /// Between the fold and the first thing under it — and the *only* thing
    /// telling the eye it has crossed one, since there is no divider, no header
    /// and no change of ground.
    ///
    /// Small because it is not the whole gap. The face ends with its own bottom
    /// clearance, which exists to keep the quick row off the page dots at rest
    /// and becomes dead air the moment the crown moves; the fold inherits it.
    /// 19 + 8 is the separation, and 8 is all this has to add.
    private static let foldGap: CGFloat = 8
    private static let sectionGap: CGFloat = 10

    var body: some View {
        let capture = themeName.captureStyle

        // The fold gap is padding, not a spacer child. As a child it collected
        // the stack's own spacing on top of itself, which is how a gap declared
        // at 14 measured 43 on the glass.
        VStack(spacing: Self.sectionGap) {
            UndersidePresets(capture: capture, onCapture: onCapture)

            // Only when there is one. An empty slot here would be the face
            // promising a history it does not have, on a surface whose whole
            // argument is that it says only what it knows.
            if let latest = sessionManager.recentMemos.first {
                UndersideLatest(memo: latest, capture: capture)
            }

            UndersideFooter(capture: capture, dim: isLuminanceReduced)
        }
        .padding(.top, Self.foldGap)
        .padding(.horizontal, Self.inset)
        // The page dots sit here too. Same job the face's bottom clearance
        // does, for the same reason — this is just the other end of the scroll.
        .padding(.bottom, 20)
    }
}

// MARK: - Presets

/// The capture verbs the face above cannot hold.
///
/// `go` is the key and `ai` is the ask route, which leaves thought, meeting and
/// task with no route from the wrist at all — they existed only as deep-link
/// targets the phone could fire. Three cells, derived from the preset list
/// rather than typed out, so adding a sixth preset puts it here instead of
/// nowhere.
private struct UndersidePresets: View {
    let capture: WatchCaptureStyle
    let onCapture: (WatchPreset) -> Void

    /// Whatever the key and the ask route are not already doing.
    private var spilled: [WatchPreset] {
        let claimed = [WatchPreset.go.id, WatchPreset.ai.id]
        return WatchPreset.presets.filter { !claimed.contains($0.id) }
    }

    private static let corner: CGFloat = 8
    private static let height: CGFloat = 44

    var body: some View {
        let material = capture.material

        HStack(spacing: 0) {
            ForEach(Array(spilled.enumerated()), id: \.element.id) { index, preset in
                if index > 0 {
                    Rectangle()
                        .fill(material.ink.opacity(0.10))
                        .frame(width: WatchEdgeWeight.hairline)
                        .padding(.vertical, 7)
                }

                Button {
                    onCapture(preset)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: preset.icon)
                            // A shade under the quick row's 12. These are the
                            // same kind of object one tier down, and saying so
                            // in size costs nothing and needs no label.
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(material.ink.opacity(0.72))

                        Text(preset.name.uppercased())
                            .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(material.ink.opacity(0.6))
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(UndersideCellStyle())
                .accessibilityLabel("Record a \(preset.name.lowercased())")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background {
            let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
            shape
                .fill(material.fieldLift)
                .overlay {
                    shape.strokeBorder(material.keyEdgeRing, lineWidth: WatchEdgeWeight.bevel)
                }
                .compositingGroup()
                // Shallower again than the quick row's. Depth is the face's
                // ranking system, and this panel is below the fold — it should
                // read as the least raised thing the wearer can press.
                .shadow(color: material.shadow, radius: 3, y: 2)
        }
    }
}

// MARK: - Latest

/// The last thing captured, and a way to hear it back.
///
/// One row, not a list — REVIEW above is the list, and repeating it here would
/// make the crown a slower way to reach the same screen. What this answers is
/// the question the list is overkill for: did the last one land, and is there
/// something to play.
private struct UndersideLatest: View {
    @EnvironmentObject private var sessionManager: WatchSessionManager

    let memo: WatchMemo
    let capture: WatchCaptureStyle

    var body: some View {
        let material = capture.material
        let hasAudio = sessionManager.hasAnswerAudio(for: memo.id)

        HStack(spacing: 7) {
            WatchStatusDot(
                diameter: 4,
                pulses: memo.isInFlight,
                color: memo.isInFlight ? capture.trace : material.inkFaint
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(memo.isAsk ? "ASK" : "MEMO")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(0.9)
                        .foregroundStyle(material.ink.opacity(0.7))

                    Text(memo.timestamp, style: .relative)
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundStyle(material.inkFaint)
                        .lineLimit(1)
                }

                // One line and no more. This surface already decided it is not
                // a reader; a preview that wraps turns a glance into a page.
                Text(caption)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(material.ink.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            if hasAudio {
                Button {
                    sessionManager.toggleAnswerPlayback(memoID: memo.id)
                } label: {
                    Image(
                        systemName: sessionManager.playingAnswerID == memo.id
                            ? "stop.fill"
                            : "play.fill"
                    )
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(capture.trace)
                    .frame(width: 26, height: 26)
                    .background {
                        Circle().strokeBorder(
                            capture.secondaryAccentEdge,
                            lineWidth: WatchEdgeWeight.hairline
                        )
                    }
                    .contentShape(.circle)
                }
                .buttonStyle(UndersideCellStyle())
                .accessibilityLabel(
                    sessionManager.playingAnswerID == memo.id ? "Stop" : "Play the answer"
                )
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            // Printed, not raised. It is a readout that happens to carry one
            // control, and giving it the panels' bevel would claim it is
            // pressable everywhere it is not.
            shape
                .fill(material.fieldShade.opacity(0.6))
                .overlay {
                    shape.strokeBorder(
                        material.secondaryEdge,
                        lineWidth: WatchEdgeWeight.hairline
                    )
                }
        }
    }

    private var caption: String {
        if let preview = memo.transcriptionPreview?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preview.isEmpty {
            return preview
        }
        if let question = memo.askQuestion?.trimmingCharacters(in: .whitespacesAndNewlines),
           !question.isEmpty {
            return question
        }
        // Nothing has come back yet, so say where it got to. An ask has a phase
        // that describes an ask; a memo does not, and borrowing one would have
        // a dictation reporting "ANSWER READY".
        return memo.isAsk ? memo.resolvedPhase.label : memo.status.rawValue.uppercased()
    }
}

// MARK: - Footer

/// Where the page ends, and the only place the face admits the phone is gone.
///
/// A capture that never reached the phone looks exactly like one that did —
/// same roll cell, same row above — which makes this the one readout the rest
/// of the surface genuinely cannot give. It stays quiet when there is nothing
/// wrong, and takes the trace colour when there is.
private struct UndersideFooter: View {
    @EnvironmentObject private var sessionManager: WatchSessionManager

    let capture: WatchCaptureStyle
    let dim: Bool

    var body: some View {
        let material = capture.material
        let linked = sessionManager.isReachable

        HStack(spacing: 5) {
            Circle()
                .fill(linked ? material.inkFaint : capture.trace)
                .frame(width: 3.5, height: 3.5)

            Text(linked ? "LINKED" : "PHONE AWAY")
                .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(
                    linked ? material.inkFaint.opacity(dim ? 0.5 : 0.8) : capture.trace
                )

            Spacer(minLength: 4)

            if let streak = sessionManager.activity?.streak, streak > 0 {
                // The roll draws the days; it never says how many in a row.
                Text("\(streak)D STREAK")
                    .font(
                        .system(size: 6.5, weight: .medium, design: .monospaced)
                            .monospacedDigit()
                    )
                    .tracking(0.9)
                    .foregroundStyle(material.inkFaint.opacity(dim ? 0.5 : 0.8))
                    .fixedSize()
            }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Press

/// The underside's travel. Less than the quick row's again, for the same
/// reason: these sit closest to the page, so they have the least room to move
/// before the press reads as a glitch rather than as a button.
private struct UndersideCellStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1)
            .offset(y: configuration.isPressed ? 0.5 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
