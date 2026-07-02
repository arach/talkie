//
//  RecordingLiveActivityController.swift
//  Talkie iOS
//
//  Starts / updates / ends the recording Live Activity (Dynamic
//  Island + lock screen) around the recording sheet's lifecycle.
//
//  NOTE ON THE DUPLICATED TYPE: `TalkieWidgetAttributes` is also
//  declared in TalkieWidget/TalkieWidgetLiveActivity.swift, which is
//  filesystem-synced to the TalkieWidgetExtension target only — the
//  app can't import it. ActivityKit matches app ↔ extension
//  activities by the attributes type NAME and round-trips the
//  payload through Codable, so the standard pattern is an identical
//  declaration in each target. The two must stay field-for-field
//  identical.
//
//  Elapsed time renders in the widget via Text(timerInterval:) off
//  the fixed `startedAt` attribute, so a running recording needs no
//  content-state pushes at all. The only update we ever send is
//  `endedAt` when the tape stops, which freezes the readout.
//

import ActivityKit
import Foundation

struct TalkieWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Set when the tape stops — freezes the elapsed readout.
        var endedAt: Date?
    }

    /// Recording start. The widget derives the ticking elapsed
    /// readout from this, no pushes required.
    var startedAt: Date
}

@MainActor
final class RecordingLiveActivityController {
    static let shared = RecordingLiveActivityController()
    private var activity: Activity<TalkieWidgetAttributes>?
    private init() {}

    /// Begin the Live Activity for a recording started at `startedAt`.
    /// Silent no-op when Live Activities are disabled or one is
    /// already running.
    func start(startedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Sweep orphans from a previous run that never ended (crash,
        // force-quit mid-recording) so stale islands don't linger.
        endOrphans()
        guard activity == nil else { return }
        do {
            activity = try Activity.request(
                attributes: TalkieWidgetAttributes(startedAt: startedAt),
                content: ActivityContent(state: .init(endedAt: nil), staleDate: nil)
            )
            AppLogger.recording.info("Recording Live Activity started")
        } catch {
            // Nice-to-have surface — never block recording over it.
            AppLogger.recording.debug("Live Activity unavailable: \(error.localizedDescription)")
        }
    }

    /// Freeze the elapsed readout when the tape stops (pre-save).
    func markStopped(at endedAt: Date = Date()) {
        guard let activity else { return }
        Task {
            await activity.update(
                ActivityContent(state: .init(endedAt: endedAt), staleDate: nil)
            )
        }
    }

    /// End and dismiss the activity. Idempotent — safe to call from
    /// every exit path (save, discard, cancel, failure, onDisappear).
    func end() {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(
                ActivityContent(state: .init(endedAt: Date()), staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }

    private func endOrphans() {
        for orphan in Activity<TalkieWidgetAttributes>.activities where orphan.id != activity?.id {
            Task {
                await orphan.end(
                    ActivityContent(state: .init(endedAt: Date()), staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
        }
    }
}
