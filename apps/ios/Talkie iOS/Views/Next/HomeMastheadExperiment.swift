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

/// The band itself: one painted plane running full bleed and up under the status
/// bar, with a highlight at the top to give it somewhere to start.
///
/// Both Home and the deck draw this, because the experiment is one idea about
/// where a screen begins rather than two treatments that happen to rhyme. If
/// they diverged, the second one to be edited would be the one that stops
/// looking like the first.
struct MastheadSurface: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let base = theme.colors.cardBackground
        // A whisper of the theme's own accent, so the crest belongs to the
        // theme rather than being a generic lightening. 7% is under the
        // threshold where it reads as a colour and over the one where it reads
        // as nothing. Flattened rather than translucent: a gradient between two
        // opaque colours is a painted surface, and one with alpha in it is a
        // film over whatever happens to be behind — which on the deck is
        // brushed metal, and would show through as a smear.
        let crest = theme.currentTheme.chrome.accent.flattened(0.07, over: base)

        LinearGradient(
            stops: [
                .init(color: crest, location: 0),
                .init(color: base, location: 0.62),
                .init(color: base, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        // Run up under the status bar. Measured off the window rather than
        // guessed at, because the number is different on every phone and a
        // masthead that stops one point short of the top is worse than one that
        // never tried.
        .padding(.top, -Self.statusBarInset)
    }

    static var statusBarInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow?.safeAreaInsets.top ?? 0
    }
}

/// A division inside the band. Hairline-thick, full width, no inset — an inset
/// rule is a fourth box outline, which is the thing the band exists to remove.
struct MastheadRule: View {
    let color: Color

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: theme.currentTheme.chrome.hairlineWidth)
    }
}
