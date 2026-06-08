//
//  Haptics.swift
//  Talkie iOS
//
//  One tactile vocabulary for the whole app. Before this, call sites
//  reached for `UIImpactFeedbackGenerator(style: .light)` ad hoc, so
//  every interaction felt the same regardless of weight. Here the app
//  speaks in INTENT — confirm / toggle / transition / stop / success —
//  keyed to the *class* of interaction, so the feel stays consistent and
//  can be retuned in exactly one place.
//
//  Generators are cached and `prepare()`-able so the first tap of a burst
//  isn't late (the Taptic Engine spins up ~150ms after a cold prepare).
//

import UIKit

/// A small, opinionated haptic vocabulary. Fire with `Haptics.confirm.fire()`
/// or `Haptics.play(.confirm)`; warm the engine ahead of an expected tap with
/// `Haptics.prepare(.transition)`.
@MainActor
enum Haptics {
    /// Light tap — the default "yes, got it" for taps and confirmations,
    /// and the gentle "go" at the start of a capture.
    case confirm
    /// Selection tick — neutral switches: segmented toggles, cancel/dismiss,
    /// joystick direction flips.
    case toggle
    /// Medium thud — a significant state change you want the hand to feel:
    /// record stop ("caught it"), playback start, sheet detent expansion.
    case transition
    /// Rigid knock — a hard boundary or mechanical stop. Reserved; use for
    /// edges (e.g. a tape-head marker crossing the centerline), not routine taps.
    case stop
    /// Earned success — first save, sync complete, pairing linked. Sparingly.
    case success
    /// Something went sideways but recoverable.
    case warning
    /// A failure the user should feel.
    case error

    /// Play this haptic now.
    func fire() { Haptics.play(self) }

    // MARK: - Cached generators

    private static let impactLight = UIImpactFeedbackGenerator(style: .light)
    private static let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private static let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    /// Warm the generator behind `kind` so the next `play` lands immediately.
    /// Cheap and idempotent — safe to call on `onAppear`/button press-down.
    static func prepare(_ kind: Haptics) {
        switch kind {
        case .confirm:                    impactLight.prepare()
        case .toggle:                     selection.prepare()
        case .transition:                 impactMedium.prepare()
        case .stop:                       impactRigid.prepare()
        case .success, .warning, .error:  notification.prepare()
        }
    }

    /// Fire `kind`. Equivalent to `kind.fire()`.
    static func play(_ kind: Haptics) {
        switch kind {
        case .confirm:     impactLight.impactOccurred()
        case .toggle:      selection.selectionChanged()
        case .transition:  impactMedium.impactOccurred()
        case .stop:        impactRigid.impactOccurred()
        case .success:     notification.notificationOccurred(.success)
        case .warning:     notification.notificationOccurred(.warning)
        case .error:       notification.notificationOccurred(.error)
        }
    }
}
