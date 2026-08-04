//
//  WatchSharedState.swift
//  TalkieWatch
//
//  The one channel between the watch app and its complication extension.
//

import Foundation
import WidgetKit

/// The slice of watch state a complication can render.
///
/// Deliberately flat primitives rather than one `Codable` blob. The extension
/// is a separate target and cannot see this type, so the *keys* are the
/// contract and each side reads them with `UserDefaults` alone — the same
/// arrangement `ComplicationPreset` and `WatchAskPhase` already use. A field
/// added on one side reads as absent on the other rather than failing to
/// decode the whole snapshot.
struct WatchSharedState: Equatable {
    /// The newest ask, so a tap on the face can open that exact answer rather
    /// than dropping the wearer on a list to find it again.
    var askID: String?
    /// Raw `WatchAskPhase`. Nil when nothing has ever been asked from here.
    var askPhase: String?
    /// The ask claims to be working, but the phone has gone quiet past the
    /// tolerance the app itself uses. Resolved here so the complication does
    /// not have to carry a second copy of that threshold.
    var askIsStalled = false
    /// The moment an in-flight ask crosses into silence. Nil when there is
    /// nothing waiting to cross — it already settled, or it already went quiet.
    ///
    /// Published as a date rather than as the tolerance itself so the
    /// complication can schedule the flip without knowing the threshold, and
    /// without the app having to be running when it arrives.
    var askStaleAt: Date?
    /// An answer has landed that the wearer has not opened the Asks page since.
    var askIsUnseen = false
    /// When the ask last changed hands — settled if it has, last heard from
    /// otherwise. The complication renders this as a relative time.
    var askChangedAt: Date?
    /// What was asked, as the phone heard it. Only the wide families show it.
    var askQuestion: String?
    /// Most recent capture of any kind, ask or memo.
    var lastCaptureAt: Date?
    /// How many captures the watch is currently holding.
    var captureCount = 0
    var isReachable = false

    /// Nothing has happened on this watch yet — the complication should read as
    /// an invitation to record rather than as a broken empty state.
    var isEmpty: Bool {
        askPhase == nil && lastCaptureAt == nil && captureCount == 0
    }
}

/// Reads and writes ``WatchSharedState`` in the app-group container.
///
/// Both processes construct their own store; the container is the shared part.
struct WatchSharedStateStore {
    /// Namespaced and versioned. If the shape ever has to change
    /// incompatibly, the new writer moves to `v2` and an extension still on
    /// `v1` renders empty instead of rendering something wrong.
    enum Key {
        static let askID = "watch.shared.v1.askID"
        static let askPhase = "watch.shared.v1.askPhase"
        static let askIsStalled = "watch.shared.v1.askIsStalled"
        static let askStaleAt = "watch.shared.v1.askStaleAt"
        static let askIsUnseen = "watch.shared.v1.askIsUnseen"
        static let askChangedAt = "watch.shared.v1.askChangedAt"
        static let askQuestion = "watch.shared.v1.askQuestion"
        static let lastCaptureAt = "watch.shared.v1.lastCaptureAt"
        static let captureCount = "watch.shared.v1.captureCount"
        static let isReachable = "watch.shared.v1.isReachable"
    }

    /// Read from the bundle rather than hardcoded, so the app and the
    /// extension cannot drift onto different containers.
    static var appGroupIdentifier: String {
        let fallback = "group.to.talkie.app"
        guard let value = Bundle.main
            .object(forInfoDictionaryKey: "TalkieAppGroupIdentifier") as? String
        else { return fallback }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private let defaults: UserDefaults?

    init(appGroupIdentifier: String = WatchSharedStateStore.appGroupIdentifier) {
        defaults = UserDefaults(suiteName: appGroupIdentifier)
    }

    func read() -> WatchSharedState {
        guard let defaults else { return WatchSharedState() }
        return WatchSharedState(
            askID: defaults.string(forKey: Key.askID),
            askPhase: defaults.string(forKey: Key.askPhase),
            askIsStalled: defaults.bool(forKey: Key.askIsStalled),
            askStaleAt: Self.date(defaults.double(forKey: Key.askStaleAt)),
            askIsUnseen: defaults.bool(forKey: Key.askIsUnseen),
            askChangedAt: Self.date(defaults.double(forKey: Key.askChangedAt)),
            askQuestion: defaults.string(forKey: Key.askQuestion),
            lastCaptureAt: Self.date(defaults.double(forKey: Key.lastCaptureAt)),
            captureCount: defaults.integer(forKey: Key.captureCount),
            isReachable: defaults.bool(forKey: Key.isReachable)
        )
    }

    /// Writes the snapshot and returns whether anything the complication draws
    /// actually moved. Callers use that to decide about reloading timelines:
    /// the publish points fire on every proof-of-life update from the phone,
    /// and most of those carry no visible change.
    @discardableResult
    func write(_ state: WatchSharedState) -> Bool {
        guard let defaults else { return false }
        guard read() != state else { return false }

        defaults.set(state.askID, forKey: Key.askID)
        defaults.set(state.askPhase, forKey: Key.askPhase)
        defaults.set(state.askIsStalled, forKey: Key.askIsStalled)
        defaults.set(
            state.askStaleAt?.timeIntervalSinceReferenceDate ?? 0,
            forKey: Key.askStaleAt
        )
        defaults.set(state.askIsUnseen, forKey: Key.askIsUnseen)
        defaults.set(
            state.askChangedAt?.timeIntervalSinceReferenceDate ?? 0,
            forKey: Key.askChangedAt
        )
        defaults.set(state.askQuestion, forKey: Key.askQuestion)
        defaults.set(
            state.lastCaptureAt?.timeIntervalSinceReferenceDate ?? 0,
            forKey: Key.lastCaptureAt
        )
        defaults.set(state.captureCount, forKey: Key.captureCount)
        defaults.set(state.isReachable, forKey: Key.isReachable)
        return true
    }

    /// A missing key reads as `0`, which as a reference date is 2001 — a
    /// timestamp that would render as "24 years ago" on the face. Absent has
    /// to stay absent.
    private static func date(_ interval: TimeInterval) -> Date? {
        interval > 0 ? Date(timeIntervalSinceReferenceDate: interval) : nil
    }
}

extension WatchSharedStateStore {
    /// Push the snapshot and, only if it changed, ask WidgetKit to redraw.
    func publish(_ state: WatchSharedState) {
        guard write(state) else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
