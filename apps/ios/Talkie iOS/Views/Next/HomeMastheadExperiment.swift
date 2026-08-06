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

/// How the console — the band at the top — is finished.
///
/// This used to be called `material` and had a fourth case called `inverted`,
/// which was a modelling mistake worth naming. Three of its cases described a
/// surface treatment and the fourth described a whole arrangement: a gloss
/// console *and* a deck under the page. One word was doing two jobs, so
/// "inverted" could not be reasoned about beside the others — it was not a
/// sibling of `laminate`, it was `gloss` plus a second decision entirely.
///
/// Now there are two independent questions, which is what there always were:
/// how the console is finished (here), and what the page below is made of
/// (`MastheadDeckGrade`). "Inverted" is simply gloss with a deck under it.
///
///     talkie://experiment?masthead=on&finish=gloss&deck=graphite
enum MastheadFinish: String, CaseIterable {
    /// A painted plane. The control — what the band was before any of this.
    case painted
    /// Print under a clear coat: smooth and sealed, with one broad soft
    /// specular raking from the upper left and a lit edge where the coat is cut.
    case laminate
    /// Bead-blasted and brushed. Machined rather than printed — a fine
    /// directional tooth, no specular, and a tighter crest.
    case anodized
    /// Piano black. Almost black everywhere and very bright in one place: a
    /// hard specular and a lit crown under the status bar.
    case gloss

    static let defaultsKey = "experiment.home.masthead.finish"

    static var current: MastheadFinish {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let finish = MastheadFinish(rawValue: raw) else { return .gloss }
        return finish
    }
}

/// The band itself: one plane running full bleed and up under the status bar,
/// finished according to `MastheadFinish`.
///
/// Both Home and the deck draw this, because the experiment is one idea about
/// where a screen begins rather than two treatments that happen to rhyme. If
/// they diverged, the second one to be edited would be the one that stops
/// looking like the first.
struct MastheadSurface: View {
    @ObservedObject private var theme = ThemeManager.shared
    var finish: MastheadFinish = MastheadFinish.current

    var body: some View {
        if finish == .gloss {
            pianoBlack
        } else {
            painted
        }
    }

    /// Deep gloss. Near-black, with one hard specular and a lit crown.
    ///
    /// Piano black is not "dark grey with a gradient" — it is almost black
    /// everywhere and very bright in one place. The base goes below anything in
    /// the palette on purpose: a gloss reads by the distance between its
    /// darkest and its brightest, and a base at the theme's card colour leaves
    /// nowhere for the highlight to travel from.
    private var pianoBlack: some View {
        ZStack {
            Color(red: 0.030, green: 0.030, blue: 0.036)

            // The reflection. Tighter and stronger than the laminate's sweep —
            // a coat scatters its highlight, a gloss returns it.
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.0), location: 0.0),
                    .init(color: .white.opacity(0.10), location: 0.20),
                    .init(color: .white.opacity(0.02), location: 0.44),
                    .init(color: .white.opacity(0.0), location: 0.8),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.plusLighter)

            // The crown. A polished panel is brightest where it turns away at
            // the top, and this one turns away under the status bar — which is
            // the one place on the screen a highlight can sit without competing
            // with anything the app drew.
            LinearGradient(
                colors: [.white.opacity(0.13), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 26)
            .frame(maxHeight: .infinity, alignment: .top)
            .blendMode(.plusLighter)
        }
        .padding(.top, -Self.statusBarInset)
    }

    @ViewBuilder
    private var painted: some View {
        let base = theme.colors.cardBackground
        // A whisper of the theme's own accent, so the crest belongs to the
        // theme rather than being a generic lightening. 7% is under the
        // threshold where it reads as a colour and over the one where it reads
        // as nothing. Flattened rather than translucent: a gradient between two
        // opaque colours is a painted surface, and one with alpha in it is a
        // film over whatever happens to be behind — which on the deck is
        // brushed metal, and would show through as a smear.
        let crest = theme.currentTheme.chrome.accent.flattened(0.07, over: base)

        ZStack {
            LinearGradient(
                stops: [
                    .init(color: crest, location: 0),
                    // Anodized holds its crest tighter. A brushed surface
                    // scatters — the falloff from a lit top edge is short and
                    // then it is one even tone, where a coated one carries the
                    // gradient most of the way down.
                    .init(color: base, location: finish == .anodized ? 0.34 : 0.62),
                    .init(color: base, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            switch finish {
            // `.gloss` never reaches here — it draws `pianoBlack` instead of
            // this whole surface — but the switch still has to say so.
            case .painted, .gloss:
                EmptyView()

            case .laminate:
                // The coat. One broad specular raking across the sheet from
                // upper-left, which is where the crest already says the light
                // is — a second light source would read as a reflection of
                // something in the room rather than as a finish.
                //
                // Wide and weak on purpose: a tight bright streak is glass, and
                // glass over a whole masthead is a phone screen drawn on a
                // phone screen. Laminate is a sealed sheet, and a sealed sheet
                // is mostly matte with one soft sweep in it.
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0), location: 0.0),
                        .init(color: .white.opacity(0.055), location: 0.30),
                        .init(color: .white.opacity(0.015), location: 0.62),
                        .init(color: .white.opacity(0), location: 1.0),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.plusLighter)

            case .anodized:
                // The tooth. Fine horizontal brushing, tiled rather than
                // drawn per frame, at an amplitude that is felt before it is
                // seen — visible grain on a 3x screen is sandpaper, not
                // anodising.
                MaterialTexture.brushed
                    .opacity(0.5)
                    .blendMode(.overlay)
            }
        }
        // Run up under the status bar. Measured off the window rather than
        // guessed at, because the number is different on every phone and a
        // masthead that stops one point short of the top is worse than one that
        // never tried.
        // No `drawingGroup` here, however tempting it is for the blended
        // layers above: it rasterises to the view's bounds, and this view's
        // whole job is to paint outside them.
        .padding(.top, -Self.statusBarInset)
    }

    static var statusBarInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow?.safeAreaInsets.top ?? 0
    }
}

/// How light the machined deck is milled.
///
/// Local comparison only — there is no right answer to read off a spec, and
/// the three are far enough apart that the wrong one is obvious next to the
/// others and invisible on its own:
///
///     talkie://experiment?masthead=on&deck=silver
enum MastheadDeckGrade: String, CaseIterable {
    /// No deck. The page stays the app's own background, which is what every
    /// screen in the app does — this is the option, not the absence of one.
    case off
    /// Dark tool steel. Separates from a gloss console by a hair, so the two
    /// read as one dark assembly caught at different angles to the light.
    case graphite
    /// The middle of the range.
    case space
    /// Bright milled aluminium. Maximum separation, and the grade that most
    /// exposes ink that was chosen against near-black.
    case silver

    static let defaultsKey = "experiment.home.masthead.deck"

    static var current: MastheadDeckGrade {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let grade = MastheadDeckGrade(rawValue: raw) else { return .graphite }
        return grade
    }

    var drawsDeck: Bool { self != .off }

    /// Kept faintly blue rather than neutral all the way up. A pure grey ramp
    /// reads as cardboard at the light end; real anodising keeps a cast.
    var base: Color {
        switch self {
        case .off:      Color.clear
        case .graphite: Color(red: 0.145, green: 0.150, blue: 0.160)
        case .space:    Color(red: 0.235, green: 0.243, blue: 0.255)
        case .silver:   Color(red: 0.335, green: 0.345, blue: 0.360)
        }
    }
}

/// What happens where the console meets the deck.
///
///     talkie://experiment?masthead=on&seam=rebate
enum MastheadSeam: String, CaseIterable {
    /// The two materials simply meet. Reads as one machined assembly with
    /// tolerances too tight to see — which is its own kind of expensive.
    case seamless
    /// A milled groove between the panels: the console's lit cut, a dark
    /// channel, then the deck's own top edge catching light on the way out.
    /// This is how two panels actually meet when nobody is hiding the joint.
    case rebate
    /// A joining strip laid over the butt — a raised extrusion spanning the
    /// full width, lit on top and shadowed below. The most instrument-like
    /// and the most literal: something was fastened here.
    case rail

    static let defaultsKey = "experiment.home.masthead.seam"

    /// Rebate, chosen by comparison rather than by argument. Seamless reads as
    /// tolerances too tight to see, which is a real idea — but next to a milled
    /// groove it reads as two colours meeting, and the groove is the only one of
    /// the three that reads as fabricated rather than rendered.
    static var current: MastheadSeam {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let seam = MastheadSeam(rawValue: raw) else { return .rebate }
        return seam
    }
}

/// The bench the experiment is run from.
///
/// Deep links were fine for turning one flag on once. They are the wrong
/// instrument for a comparison: judging a finish means flicking between two of
/// them while looking at the same screen, and a round trip through a URL, a
/// relaunch and a lost scroll position destroys exactly the thing being judged.
///
/// Reached by pressing and holding the wordmark. Deliberately not a settings
/// row — this is scaffolding for an open question, and it should leave with the
/// question rather than accumulate as a permanent preference nobody remembers
/// agreeing to.
struct MastheadExperimentPanel: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var flag = HomeMastheadExperiment.shared

    @State private var finish = MastheadFinish.current
    @State private var deck = MastheadDeckGrade.current
    @State private var seam = MastheadSeam.current

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Full-bleed masthead", isOn: $flag.isOn)
                } footer: {
                    Text("Off restores the original header and cockpit, unchanged.")
                }

                Section {
                    picker("Finish", selection: $finish, cases: MastheadFinish.allCases)
                } header: {
                    Text("Console")
                } footer: {
                    Text("How the band at the top is surfaced. Gloss is piano black; "
                         + "painted is what it was before any of this.")
                }

                Section {
                    picker("Grade", selection: $deck, cases: MastheadDeckGrade.allCases)
                } header: {
                    Text("Deck")
                } footer: {
                    Text("What the page below is made of. Off leaves it as the app "
                         + "background, which is what every other screen does.")
                }

                Section("Joint") {
                    picker("Seam", selection: $seam, cases: MastheadSeam.allCases)
                }
            }
            .navigationTitle("Masthead lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Written on change rather than on dismiss, so the screen behind the
        // sheet is already showing the answer by the time it is swiped away.
        .onChange(of: finish) { _, new in store(MastheadFinish.defaultsKey, new.rawValue) }
        .onChange(of: deck) { _, new in store(MastheadDeckGrade.defaultsKey, new.rawValue) }
        .onChange(of: seam) { _, new in store(MastheadSeam.defaultsKey, new.rawValue) }
    }

    private func picker<T: RawRepresentable & Hashable>(
        _ title: String,
        selection: Binding<T>,
        cases: [T]
    ) -> some View where T.RawValue == String {
        Picker(title, selection: selection) {
            ForEach(cases, id: \.self) { value in
                Text(value.rawValue.capitalized).tag(value)
            }
        }
        .pickerStyle(.segmented)
    }

    /// These are read at body evaluation rather than observed, so something has
    /// to tell SwiftUI the answer changed. The flag is the object every masthead
    /// view already watches, which makes re-stamping it the cheapest true signal
    /// available — the same path the deep link takes.
    private func store(_ key: String, _ value: String) {
        UserDefaults.standard.set(value, forKey: key)
        HomeMastheadExperiment.shared.objectWillChange.send()
    }
}

/// The deck the console is bolted to — machined space grey, brushed and matte.
///
/// Only `.gloss` draws this. Every other treatment leaves the page as the
/// app's own background, which is the right default: giving the page a
/// material is a claim that the whole screen is an object, and that is a much
/// larger claim than a masthead makes.
///
/// It does not scroll. A surface that scrolls is wallpaper; a deck the content
/// travels across is a deck.
struct MastheadDeck: View {
    var grade: MastheadDeckGrade = MastheadDeckGrade.current

    var body: some View {
        ZStack {
            grade.base

            // Lit from above, like everything else on this screen. Shallow —
            // machined aluminium is close to one even tone, and a strong ramp
            // would read as a painted panel again.
            LinearGradient(
                colors: [.white.opacity(0.05), .clear, .black.opacity(0.10)],
                startPoint: .top,
                endPoint: .bottom
            )

            MaterialTexture.brushed
                .opacity(0.55)
                .blendMode(.overlay)
        }
        .ignoresSafeArea()
    }
}

/// Tiled surface textures, rendered once and reused.
///
/// Drawn into a bitmap rather than composed from views: a brushed finish is
/// hundreds of lines, and hundreds of `Rectangle`s in a `ZStack` is a view tree
/// the size of a small app for something that never changes. One 4×64 tile,
/// resized by the tiling drawer, costs a texture lookup.
enum MaterialTexture {
    /// Fine horizontal brushing. Deterministic — a seeded sequence, not
    /// `random()`, so the grain is identical on every launch. Noise that
    /// reshuffles between launches is the one kind a person notices.
    static let brushed: Image = {
        // One image pixel has to land on exactly one device pixel.
        //
        // Tiling happens in points, so a tile rendered at 1x turns every brush
        // line into a 3pt band on a 3x screen. That is not a fine finish, it is
        // corduroy: measured off the first attempt, the deck read 54,54,54 then
        // 62,62,62 — three-pixel stripes with a nine-level swing, which is
        // visible as banding from arm's length.
        //
        // Rendering at the display's own scale and stepping by 1/scale of a
        // point puts each line back on a single pixel, where a tooth belongs.
        let scale = max(UIScreen.main.scale, 1)
        let lines = 64
        let size = CGSize(width: 2, height: CGFloat(lines) / scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true

        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            let step = 1 / scale
            for row in 0..<lines {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                // Centred on mid-grey so `.overlay` blending lightens and
                // darkens in equal measure — a texture that only lightens is a
                // haze sitting on the surface rather than a finish in it.
                let value = 0.5 + (Double((seed >> 33) % 1000) / 1000.0 - 0.5) * 0.16
                context.cgContext.setFillColor(
                    UIColor(white: value, alpha: 1).cgColor
                )
                context.cgContext.fill(
                    CGRect(x: 0, y: CGFloat(row) * step, width: size.width, height: step)
                )
            }
        }
        return Image(uiImage: image).resizable(resizingMode: .tile)
    }()
}

/// The lit edge where the coat is cut.
///
/// This is the whole tell. A painted plane that stops is a colour change; a
/// finished sheet that stops has a bright line along the cut where the coat
/// catches light, immediately above the shade of its own thickness. Bright line
/// over dark line is how every laminated panel, anodised bezel and moulded
/// fascia announces its edge, and it is two hairlines of drawing.
///
/// Nothing here for a painted band, which has no coat to cut.
struct MastheadCoatEdge: View {
    let finish: MastheadFinish
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        if finish != .painted {
            Rectangle()
                .fill(Color.white.opacity(finish == .laminate ? 0.11 : 0.07))
                .frame(height: theme.currentTheme.chrome.hairlineWidth)
        }
    }
}

/// The joint, in whichever way it is being made this run.
///
/// Composed to hang below the band: everything here draws downward from the
/// console's bottom edge, and the caller lifts it back with negative padding so
/// only the overhang lands on the page.
struct MastheadJoint: View {
    let finish: MastheadFinish
    let seam: MastheadSeam
    @ObservedObject private var theme = ThemeManager.shared

    /// The milled channel's depth, and the strip's thickness. Both small: a
    /// joint that reads at a glance from across a room is a moulding, and this
    /// is supposed to be machined.
    private static let grooveDepth: CGFloat = 3
    private static let railHeight: CGFloat = 5

    var body: some View {
        switch seam {
        case .seamless:
            VStack(spacing: 0) {
                MastheadCoatEdge(finish: finish)
                if finish == .painted {
                    MastheadRule(color: theme.currentTheme.chrome.edge)
                }
                MastheadStep()
            }

        case .rebate:
            VStack(spacing: 0) {
                // The console's cut, then the channel it was cut back to.
                MastheadCoatEdge(finish: finish)

                Rectangle()
                    .fill(Color.black.opacity(0.55))
                    .frame(height: Self.grooveDepth)

                // The deck's own edge, coming back up out of the groove into
                // the light. Without this the channel is just a dark line and
                // the deck looks printed on rather than milled.
                Rectangle()
                    .fill(Color.white.opacity(0.13))
                    .frame(height: theme.currentTheme.chrome.hairlineWidth)

                MastheadStep()
            }

        case .rail:
            VStack(spacing: 0) {
                // A strip laid over the butt joint. Lit along the top, its own
                // body slightly proud of both panels, shadow underneath — the
                // three things that make a piece of extrusion read as a
                // separate object rather than as a thick line.
                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(height: theme.currentTheme.chrome.hairlineWidth)

                LinearGradient(
                    colors: [
                        Color(white: 0.42),
                        Color(white: 0.30),
                        Color(white: 0.20),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Self.railHeight)
                .overlay { MaterialTexture.brushed.opacity(0.5).blendMode(.overlay) }

                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(height: theme.currentTheme.chrome.hairlineWidth)

                MastheadStep()
            }
        }
    }

    /// How far the joint hangs past the band, so the caller can lift it back.
    static func overhang(seam: MastheadSeam) -> CGFloat {
        switch seam {
        case .seamless: MastheadStep.drop
        case .rebate:   MastheadStep.drop + grooveDepth
        case .rail:     MastheadStep.drop + railHeight
        }
    }
}

/// The step down from the band to the page.
///
/// The rule at the band's bottom edge is a division: it says these are two
/// things. It does not say which one is on top, and a masthead that reads as a
/// panel lying flat next to the page is a weaker idea than one that reads as a
/// plane the page is recessed under.
///
/// So the band casts. The surface above is lit from its own top — that is what
/// the crest gradient is — and a plane lit from above throws its shade
/// downward onto whatever it overhangs. This is that shade: darkest right
/// under the lip, gone within a few points, drawn over the page rather than
/// inside the band.
///
/// Black, not a theme token. The `edge` tokens are all derived from theme ink,
/// which inverts on dark finishes — an occlusion built from ink would be a
/// shadow on porcelain and a glow on matte. Shade is shade on every theme; it
/// simply has less to say on a dark page, which is also true of real ones.
struct MastheadStep: View {
    /// How far the shade reaches onto the page. Short on purpose: a long
    /// falloff is a vignette, and a vignette is atmosphere rather than
    /// structure. This has to read as an edge with a thickness.
    static let drop: CGFloat = 14

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.13), location: 0),
                // Most of the falloff spent early, the way contact shadows
                // actually behave — a linear ramp to clear reads as a wash.
                .init(color: .black.opacity(0.045), location: 0.4),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: Self.drop)
        // It shades the page; it does not take taps from it.
        .allowsHitTesting(false)
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
