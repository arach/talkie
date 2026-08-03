//
//  AskLiveActivityController.swift
//  Talkie iOS
//
//  Starts / updates / ends the Ask AI Live Activity around an ask
//  spoken from the Watch.
//
//  This is the off-screen half of the visibility work: AskInFlightRegistry
//  covers the case where the phone is open and in front of you, and this
//  covers the far more common one where it is face-down on a table while
//  you wait on your wrist. Both are driven from the same registry so the
//  lock screen and the in-app pill cannot disagree.
//
//  NOTE ON THE DUPLICATED TYPE: `AskActivityAttributes` and
//  `AskActivityPhase` are also declared in TalkieWidget/AskLiveActivity.swift,
//  which is filesystem-synced to the TalkieWidgetExtension target only —
//  the app can't import it. ActivityKit matches app ↔ extension activities
//  by the attributes type NAME and round-trips the payload through Codable,
//  so the standard pattern is an identical declaration in each target. The
//  two must stay field-for-field identical. Same arrangement as
//  TalkieWidgetAttributes in RecordingLiveActivityController.
//

import ActivityKit
import Foundation

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
}

@MainActor
final class AskLiveActivityController {
    static let shared = AskLiveActivityController()
    private init() {}

    /// Keyed by memo id: a second ask arriving before the first settles
    /// gets its own banner rather than hijacking the first one's.
    private var activities: [String: Activity<AskActivityAttributes>] = [:]

    /// How long a settled banner stays on the lock screen. An answer is
    /// short-lived — you glance and open it — but a failure is the whole
    /// reason this surface exists, so it lingers long enough to be seen
    /// on a phone you come back to.
    private static let answeredDismissal: TimeInterval = 60
    private static let failedDismissal: TimeInterval = 8 * 60

    /// If the phone stops reporting, say so rather than showing a
    /// confident "ANSWERING" forever. ActivityKit dims the banner past
    /// this date.
    private static let staleAfter: TimeInterval = 3 * 60

    /// Drive the banner from a lifecycle update. Unknown phases (the
    /// wrist-side ones) are ignored, and a terminal phase for an ask we
    /// never started a banner for is not resurrected.
    func record(memoId: String, phase: WatchSessionManager.AskPhase, text: String?) {
        guard !memoId.isEmpty else { return }
        guard let activityPhase = AskActivityPhase(rawValue: phase.rawValue) else { return }

        if let existing = activities[memoId] {
            update(existing, memoId: memoId, phase: activityPhase, text: text)
        } else {
            start(memoId: memoId, phase: activityPhase, text: text)
        }
    }

    /// Drop this ask's banner now. Called when the ask is dismissed in
    /// the app: having swatted it away on one surface, finding it still
    /// sitting on the lock screen would read as the dismissal failing.
    func end(_ memoId: String) {
        guard let activity = activities.removeValue(forKey: memoId) else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func start(memoId: String, phase: AskActivityPhase, text: String?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // A terminal phase with no banner in flight means we missed the
        // whole ask (app launched late, activities were off). Starting a
        // banner that immediately expires is just noise.
        guard !phase.isTerminal else { return }

        endOrphans()

        do {
            let activity = try Activity.request(
                attributes: AskActivityAttributes(askId: memoId, startedAt: Date()),
                content: ActivityContent(
                    state: .init(phase: phase, text: text, updatedAt: Date()),
                    staleDate: Date().addingTimeInterval(Self.staleAfter)
                )
            )
            activities[memoId] = activity
            AppLogger.ai.info("Ask Live Activity started")
        } catch {
            // Nice-to-have surface — never let it interfere with the ask.
            AppLogger.ai.debug("Ask Live Activity unavailable: \(error.localizedDescription)")
        }
    }

    private func update(
        _ activity: Activity<AskActivityAttributes>,
        memoId: String,
        phase: AskActivityPhase,
        text: String?
    ) {
        // A phase carrying no text must not blank out text an earlier
        // phase supplied: `answering` sends the question and the banner
        // keeps showing it until the answer replaces it.
        let resolvedText: String? = {
            if let text, !text.isEmpty { return text }
            return activity.content.state.text
        }()

        let content = ActivityContent(
            state: AskActivityAttributes.ContentState(phase: phase, text: resolvedText, updatedAt: Date()),
            staleDate: phase.isTerminal ? nil : Date().addingTimeInterval(Self.staleAfter)
        )

        guard phase.isTerminal else {
            Task { await activity.update(content) }
            return
        }

        // Deliberately still tracked: a settled banner lingers on the lock
        // screen, and `end(_:)` has to be able to find it if the ask is
        // dismissed in the app before that linger runs out. It is dropped
        // from the map once the banner is actually gone.
        let linger = phase == .failed ? Self.failedDismissal : Self.answeredDismissal
        Task { [weak self] in
            // Push the final state first so the banner shows the outcome,
            // then hand it a dismissal date rather than yanking it — the
            // answer is the one thing here worth reading.
            await activity.update(content)
            await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(linger)))
            try? await Task.sleep(for: .seconds(linger))
            await MainActor.run {
                // Only clear our own entry: a re-asked memo id would have
                // installed a fresh activity under the same key.
                guard self?.activities[memoId]?.id == activity.id else { return }
                self?.activities.removeValue(forKey: memoId)
            }
        }
    }

    /// Sweep banners left behind by a previous run that never ended
    /// (crash, force-quit mid-ask) so stale asks don't accumulate.
    private func endOrphans() {
        let live = Set(activities.values.map(\.id))
        for orphan in Activity<AskActivityAttributes>.activities where !live.contains(orphan.id) {
            Task { await orphan.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
