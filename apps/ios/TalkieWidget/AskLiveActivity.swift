//
//  AskLiveActivity.swift
//  TalkieWidget
//
//  Ask AI Live Activity — lock screen + Dynamic Island for an ask
//  spoken from the Watch while the phone works on it.
//
//  NOTE ON THE DUPLICATED TYPE: `AskActivityAttributes` and
//  `AskActivityPhase` are also declared in
//  "Talkie iOS"/Models/AskLiveActivityController.swift for the app
//  target — this folder syncs to the extension only. ActivityKit
//  matches by type name and round-trips the payload through Codable,
//  so the two declarations must stay field-for-field identical. Same
//  arrangement as TalkieWidgetAttributes next door.
//
//  Unlike the recording activity, this one cannot derive its display
//  from a fixed start date: an ask's progress is not a function of
//  elapsed time, it is a function of what the phone has finished. So
//  every step is a content-state push.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct AskActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var phase: AskActivityPhase
        /// The question while it is being answered, then the answer.
        var text: String?
        var updatedAt: Date
    }

    /// The memo id the Watch minted — also the deep-link target.
    var askId: String
    var startedAt: Date
}

/// The subset of the ask lifecycle worth a lock-screen banner. The
/// wrist-side phases (`queued`, `sending`) are deliberately absent:
/// the phone cannot observe them, since it only learns of an ask when
/// one arrives.
enum AskActivityPhase: String, Codable, Hashable {
    case received
    case transcribing
    case answering
    case answered
    case failed

    /// The working phases, in the order they occur. This doubles as the
    /// source of truth for the progress track's segment count — the
    /// track cannot fall out of step with the lifecycle because it is
    /// drawn from it.
    static let workingOrder: [AskActivityPhase] = [.received, .transcribing, .answering]

    var isTerminal: Bool { self == .answered || self == .failed }

    var label: String {
        switch self {
        case .received: return "RECEIVED"
        case .transcribing: return "TRANSCRIBING"
        case .answering: return "ANSWERING"
        case .answered: return "ANSWER READY"
        case .failed: return "ASK FAILED"
        }
    }

    /// Short form for the Dynamic Island's compact regions, where there
    /// is room for a word and not a phrase.
    var shortLabel: String {
        switch self {
        case .received: return "ASK"
        case .transcribing: return "HEARD"
        case .answering: return "THINKING"
        case .answered: return "READY"
        case .failed: return "FAILED"
        }
    }

    var glyph: String {
        switch self {
        case .received: return "applewatch.radiowaves.left.and.right"
        case .transcribing: return "waveform"
        case .answering: return "sparkles"
        case .answered: return "checkmark"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

struct AskLiveActivity: Widget {
    /// Asks get their own hue rather than borrowing the recording
    /// activity's amber — two Talkie banners can be on the lock screen
    /// at once, and they must not read as the same thing at a glance.
    private let askAccent = Color(red: 0.44, green: 0.72, blue: 1.0)

    /// Deep link into the memo the ask became. `askId` is the memo id the
    /// Watch minted, and DeepLinkManager only accepts a well-formed UUID,
    /// so a malformed id yields no link rather than a dead tap.
    private func memoURL(_ askId: String) -> URL? {
        var components = URLComponents()
        components.scheme = "talkie"
        components.host = "memo"
        components.queryItems = [URLQueryItem(name: "id", value: askId)]
        return components.url
    }

    private func tint(_ phase: AskActivityPhase) -> Color {
        switch phase {
        case .answered: return .green
        case .failed: return .red
        default: return askAccent
        }
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AskActivityAttributes.self) { context in
            lockScreen(context)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.86))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(memoURL(context.attributes.askId))

        } dynamicIsland: { context in
            let phase = context.state.phase
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(tint(phase))
                            .frame(width: 8, height: 8)
                        Text(phase.shortLabel)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .tracking(1.6)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: phase.glyph)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tint(phase))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let text = context.state.text, !text.isEmpty {
                            Text(text)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.88))
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !phase.isTerminal {
                            progressTrack(phase)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: phase.glyph)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tint(phase))
            } compactTrailing: {
                Text(phase.shortLabel)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tint(phase))
                    .frame(maxWidth: 62)
            } minimal: {
                Image(systemName: phase.glyph)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tint(phase))
            }
            // Matches DeepLinkManager's existing `talkie://memo?id=<uuid>`
            // contract — the ask id is the memo id.
            .widgetURL(memoURL(context.attributes.askId))
            .keylineTint(tint(phase))
        }
    }

    @ViewBuilder
    private func lockScreen(_ context: ActivityViewContext<AskActivityAttributes>) -> some View {
        let phase = context.state.phase

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tint(phase).opacity(0.16))
                        .frame(width: 36, height: 36)
                    Image(systemName: phase.glyph)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(tint(phase))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(phase.label)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(tint(phase))
                    Text("ASK AI")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(2.0)
                        .foregroundStyle(.white.opacity(0.45))
                }

                Spacer()

                Text("TALKIE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2.6)
                    .foregroundStyle(.white.opacity(0.38))
            }

            if let text = context.state.text, !text.isEmpty {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.9))
                    // Answers run long; the banner shows the head of it
                    // and the app holds the rest.
                    .lineLimit(phase == .answered ? 4 : 2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !phase.isTerminal {
                progressTrack(phase)
            }
        }
    }

    /// A segment per working phase, filled up to the current one. Reads
    /// as motion between pushes without pretending to know a duration
    /// we do not have.
    private func progressTrack(_ phase: AskActivityPhase) -> some View {
        let order = AskActivityPhase.workingOrder
        // A terminal phase is not in `workingOrder`; treat it as past
        // the end so the track reads full rather than empty.
        let reached = order.firstIndex(of: phase) ?? order.count - 1

        return HStack(spacing: 4) {
            ForEach(Array(order.enumerated()), id: \.offset) { index, _ in
                Capsule()
                    .fill(index <= reached ? tint(phase) : Color.white.opacity(0.18))
                    .frame(height: 3)
            }
        }
    }
}

extension AskActivityAttributes {
    fileprivate static var preview: AskActivityAttributes {
        AskActivityAttributes(askId: "preview", startedAt: Date().addingTimeInterval(-6))
    }
}

extension AskActivityAttributes.ContentState {
    fileprivate static var answering: AskActivityAttributes.ContentState {
        .init(phase: .answering, text: "What's the tide doing in Half Moon Bay tomorrow morning?", updatedAt: Date())
    }

    fileprivate static var answered: AskActivityAttributes.ContentState {
        .init(phase: .answered, text: "Low tide is at 6:42am at about 0.4 ft, high tide at 1:10pm around 5.1 ft.", updatedAt: Date())
    }

    fileprivate static var failed: AskActivityAttributes.ContentState {
        .init(phase: .failed, text: "Couldn't reach the model.", updatedAt: Date())
    }
}

#Preview("Ask", as: .content, using: AskActivityAttributes.preview) {
    AskLiveActivity()
} contentStates: {
    AskActivityAttributes.ContentState.answering
    AskActivityAttributes.ContentState.answered
    AskActivityAttributes.ContentState.failed
}
