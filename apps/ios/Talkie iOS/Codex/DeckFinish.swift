import SwiftUI

/// How the deck is *made*, as distinct from what colour it is.
///
/// Until now this was implicit in `isIconMinimalDeck`, which conflated two
/// unrelated things: whether keys carry captions, and whether the surface is
/// moulded or printed. Carbon happened to want both, so one flag served. A
/// theme that wants captions *and* a flat surface needs them separated.
///
/// The finish owns the two decisions that make small type read hard:
///
/// 1. **Layers over the word.** A gloss gradient on the cap, a sheen on the
///    plate, a drop shadow under both. Each is a light film across the ink,
///    and the eye reads the stack as haze rather than as any one layer.
/// 2. **The letterform itself.** SF Mono at 8.5pt is a narrow face at a
///    fractional size — the stems land between device pixels and get shared
///    across two columns of them. SF Pro Text at 9pt is drawn for exactly
///    this size, and an integer point size puts the stems back on the grid.
enum DeckFinish {
    /// Moulded plastic under glass. Gloss on the caps, sheen on the plates,
    /// shadow beneath, legends screened on in mono. The house style.
    case instrument

    /// Ink on card. No gloss, no lift, no wash — a surface colour, a hairline,
    /// and the word. Type is the system text face at whole point sizes.
    case flat

    /// Whether caps and plates carry their highlight gradients.
    var isGlossy: Bool { self == .instrument }

    /// Multiplier on every drop shadow the deck casts. Flat casts none, so the
    /// call sites keep their radii and offsets and simply arrive at zero.
    var lift: CGFloat { self == .instrument ? 1 : 0 }

    /// Mono legend vs. system text. Flat rounds to a whole point size: the
    /// half-point sizes exist to fit the mono metrics, and once the face
    /// changes there is nothing left for them to fit.
    func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        switch self {
        case .instrument:
            return .system(size: size, weight: weight, design: .monospaced)
        case .flat:
            return .system(size: size.rounded(), weight: weight)
        }
    }

    /// All-caps still wants air, but a proportional face already carries its
    /// own sidebearings — mono tracking on top of them reads as a gap.
    func tracking(_ value: CGFloat) -> CGFloat {
        self == .instrument ? value : value * 0.6
    }
}

extension AppTheme {
    /// The finish a theme is made in. The deck reads it through the environment;
    /// Home's cockpit reads it directly off the theme, because its palette is a
    /// static table rather than a view tree. Both need the same answer — a theme
    /// that argues against films on one screen can't sprout them on the other.
    var finish: DeckFinish {
        switch self {
        case .carbon, .matte: return .flat
        default: return .instrument
        }
    }
}

private struct DeckFinishKey: EnvironmentKey {
    static let defaultValue: DeckFinish = .instrument
}

extension EnvironmentValues {
    var deckFinish: DeckFinish {
        get { self[DeckFinishKey.self] }
        set { self[DeckFinishKey.self] = newValue }
    }
}

/// `.font()` and `.tracking()` can't read the environment inline, so the two
/// travel as modifiers instead. Call sites keep the shape they had — the
/// instrument numbers stay written down as the instrument numbers — and the
/// finish decides what they mean.
private struct DeckFontModifier: ViewModifier {
    @Environment(\.deckFinish) private var finish
    let size: CGFloat
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content.font(finish.font(size, weight))
    }
}

private struct DeckTrackingModifier: ViewModifier {
    @Environment(\.deckFinish) private var finish
    let value: CGFloat

    func body(content: Content) -> some View {
        content.tracking(finish.tracking(value))
    }
}

extension View {
    func deckFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        modifier(DeckFontModifier(size: size, weight: weight))
    }

    func deckTracking(_ value: CGFloat) -> some View {
        modifier(DeckTrackingModifier(value: value))
    }
}
