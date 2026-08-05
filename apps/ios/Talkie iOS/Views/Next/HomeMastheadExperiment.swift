//
//  HomeMastheadExperiment.swift
//  Talkie iOS
//
//  A switch, not a decision.
//
//  Home's top is currently three separate objects stacked with gaps between
//  them: a header row floating on the page, then a 12pt inset, then a cockpit
//  sitting on a raised bezel with its own rounded screen inside it. Each is
//  well made on its own, and together they read as a list of components rather
//  than as the top of a page — the eye counts four nested rounded rectangles
//  before it reaches the first word.
//
//  The experiment asks what happens if that whole region is one surface
//  instead: full bleed to both edges and up under the status bar, its parts
//  separated by hairlines rather than by gaps and corners, with a single
//  painted highlight at the top to give it somewhere to start.
//
//  It ships behind this flag rather than as a rewrite because it is a question,
//  not an answer, and the only way to judge it is next to what it replaces:
//
//      talkie://experiment?masthead=on
//      talkie://experiment?masthead=off
//

import SwiftUI

@MainActor
final class HomeMastheadExperiment: ObservableObject {
    static let shared = HomeMastheadExperiment()

    private static let defaultsKey = "experiment.home.masthead.fullBleed"

    /// Whether Home's top region draws as one full-bleed band.
    ///
    /// Persisted, so the answer survives a relaunch — a treatment you can only
    /// see for as long as you don't background the app isn't one you can live
    /// with for a day and then form an opinion about.
    @Published var isOn: Bool {
        didSet {
            UserDefaults.standard.set(isOn, forKey: Self.defaultsKey)
            Self.isFlush = isOn
        }
    }

    /// Nonisolated mirror of `isOn`, for the static colour tables.
    ///
    /// The cockpit palette is a plain static lookup read from a dozen call
    /// sites during body evaluation; it can't hop to the main actor to ask, and
    /// threading a flag through every one of them to answer a question they all
    /// share an answer to would cost more than it explains. Same reasoning, and
    /// same shape, as `ActiveTheme.current`.
    nonisolated(unsafe) static private(set) var isFlush = false

    private init() {
        let on = UserDefaults.standard.bool(forKey: Self.defaultsKey)
        isOn = on
        Self.isFlush = on
    }
}
