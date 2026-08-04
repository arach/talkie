//
//  WatchSharedStateReader.swift
//  TalkieWatchWidget
//
//  The read half of the watch app's shared snapshot.
//

import Foundation

// The writer lives in `TalkieWatch Watch App/WatchSharedState.swift`. It is not
// shared code: each watch target is a synchronized folder, so a file dropped in
// one belongs to that target alone. The key strings below are the contract,
// duplicated the same way `ComplicationPreset` and `WatchAskPhase` already are.
// Reading with `UserDefaults` primitives rather than decoding a blob means a
// field added on one side reads as absent here instead of failing the whole
// snapshot.

/// What the watch app last published about itself.
struct WatchSharedState: Equatable {
    var askID: String?
    /// Raw `WatchAskPhase`.
    var askPhase: String?
    /// The app's verdict at publish time: the phone had already gone quiet.
    var askIsStalled = false
    /// When an in-flight ask crosses into silence. The complication schedules a
    /// timeline entry here so the face stops claiming to be working even if the
    /// app never runs again.
    var askStaleAt: Date?
    /// An answer landed that the wearer has not opened the Asks page since.
    var askIsUnseen = false
    var askChangedAt: Date?
    var askQuestion: String?
    var lastCaptureAt: Date?
    var captureCount = 0
    var isReachable = false

    /// Nothing has happened on this watch yet — read as an invitation to
    /// record, not as a broken empty state.
    var isEmpty: Bool {
        askPhase == nil && lastCaptureAt == nil && captureCount == 0
    }

    /// An answer is waiting and has not been looked at.
    ///
    /// Phase compared by raw value: `WatchAskPhase` is likewise declared once
    /// per target, so the string is what actually crosses.
    var hasWaitingAnswer: Bool {
        askIsUnseen && askPhase == "answered"
    }

    /// Still working, as far as anyone here knows.
    func isWorking(asOf now: Date) -> Bool {
        guard let askPhase, askPhase != "answered", askPhase != "failed" else { return false }
        return !isStalled(asOf: now)
    }

    /// Stale either because it already was when published, or because the
    /// crossing the app scheduled for us has since passed.
    func isStalled(asOf now: Date) -> Bool {
        if askIsStalled { return true }
        guard let askStaleAt else { return false }
        return now >= askStaleAt
    }
}

/// Reads ``WatchSharedState`` out of the app-group container.
struct WatchSharedStateReader {
    /// Read from the bundle rather than hardcoded, so the extension and the app
    /// cannot drift onto different containers. A mismatch would show as a
    /// permanently empty complication rather than as an error, which is exactly
    /// the kind of failure worth designing out.
    static var appGroupIdentifier: String {
        let fallback = "group.to.talkie.app"
        guard let value = Bundle.main
            .object(forInfoDictionaryKey: "TalkieAppGroupIdentifier") as? String
        else { return fallback }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private enum Key {
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

    private let defaults: UserDefaults?

    init(appGroupIdentifier: String = WatchSharedStateReader.appGroupIdentifier) {
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

    /// A missing key reads as `0`, which as a reference date is 2001 — a
    /// timestamp that would render as "24 years ago" on the face. Absent has to
    /// stay absent.
    private static func date(_ interval: TimeInterval) -> Date? {
        interval > 0 ? Date(timeIntervalSinceReferenceDate: interval) : nil
    }
}
