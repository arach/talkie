//
//  ScopeBayScheme.swift
//  Talkie macOS
//

import SwiftUI
import TalkieKit

// MARK: - Bay color schemes
//
// Each scheme swaps the phosphor / accent family inside the agent bay
// - the gunmetal bg + rails stay constant, so the bay always reads as
// "instrument bay sunk into cream desk" regardless of which tube color
// is fitted.

enum BayScheme: String, CaseIterable {
    // Aligned with `design/studio/lib/schemes.ts` as of 2026-05-17.
    // The intermediate gray gradient (graphite/pewter/ash/stone) was
    // dropped after the studio review - read as "filtered" rather
    // than designed. New light-mode canonicals from the studio's
    // light-touch sibling work:
    //
    //   Modern theme -> PEARL    (cool family, canonical = lightest)
    //   Scope theme  -> CHIFFON  (warm family, canonical = lightest)
    //
    // Sibling ladder within each family for fine-tuning bay presence.
    // AMBER kept as the reference for the original lit-electronics
    // identity. See design/studio/app/mac-home/NOTES.md for rationale.
    case amber       // Reference dark (original electronics bay)
    case pearl       // Modern canonical - cool lightest
    case porcelain   // Cool mid
    case aluminum    // Cool saturated
    case chiffon     // Scope canonical - warm lightest
    case vellum      // Warm mid
    case paper       // Warm saturated

    var displayName: String {
        switch self {
        case .amber:     return "AMBER"
        case .pearl:     return "PEARL"
        case .porcelain: return "PORCELAIN"
        case .aluminum:  return "ALUMINUM"
        case .chiffon:   return "CHIFFON"
        case .vellum:    return "VELLUM"
        case .paper:     return "PAPER"
        }
    }

    /// True when the surface is light enough to need dark text on it.
    /// Toggles glow off, switches stat numbers to graphite ink, and
    /// bumps edge contrast. All current non-AMBER schemes are light.
    var isLight: Bool { self != .amber }

    /// Canonical accent. Dark schemes use it as the phosphor for stat
    /// numbers + dot + sparkline; light schemes use it as the edge /
    /// sparkline accent only (stat numbers fall back to `statInk`).
    /// Cool-family accents pull slightly cooler (#D49236); warm-family
    /// stays at the canonical copper (#9A6A22). AMBER is the original
    /// phosphor.
    var trace: Color {
        switch self {
        case .amber:                              return ScopeKind.dict
        case .pearl, .porcelain, .aluminum:       return Color.hex("D49236")
        case .chiffon, .vellum, .paper:           return ScopeBrass.solid
        }
    }

    /// Glow halo. Light schemes disable glow - printed surfaces don't
    /// emit light, so the halo would just look smudgy.
    var traceGlow: Color { isLight ? .clear : trace.opacity(0.50) }

    /// Background graticule tint - barely-there.
    var traceFaint: Color { trace.opacity(isLight ? 0.06 : 0.08) }

    /// Edge / divider color - same hue as trace, very low alpha.
    /// Lighter schemes need slightly more contrast to read.
    var edge: Color {
        switch self {
        case .amber:                 return trace.opacity(0.10)
        case .pearl, .chiffon:       return trace.opacity(0.10)   // lightest - kept restrained
        case .porcelain, .vellum:    return trace.opacity(0.12)
        case .aluminum, .paper:      return trace.opacity(0.18)   // most saturated of the light family
        }
    }

    /// Edge for crisper marks (corner brackets).
    var edgeStrong: Color {
        switch self {
        case .amber:                 return trace.opacity(0.28)
        case .pearl, .chiffon:       return trace.opacity(0.28)
        case .porcelain, .vellum:    return trace.opacity(0.34)
        case .aluminum, .paper:      return trace.opacity(0.40)
        }
    }

    /// Cell color for the activity heatmap. Intensity-scaled at call site.
    func cell(intensity: Double) -> Color {
        let base = isLight ? 0.12 : 0.10
        let span = isLight ? 0.55 : 0.60
        return trace.opacity(base + span * intensity)
    }

    // MARK: Surface tokens

    /// Bay panel base fill. Mirrors `--scheme-bg` from studio.
    var panelBg: Color {
        switch self {
        case .amber:      return Color.hex("14181A")
        case .pearl:      return Color.hex("F5F8FA")
        case .porcelain:  return Color.hex("EAEEF1")
        case .aluminum:   return Color.hex("D6DBE0")
        case .chiffon:    return Color.hex("FAF5E8")
        case .vellum:     return Color.hex("F4EFE0")
        case .paper:      return Color.hex("EEE7D6")
        }
    }

    /// Stat number color. Dark -> phosphor; light -> deep neutral ink
    /// tuned to the scheme's warmth.
    var statInk: Color {
        switch self {
        case .amber:                                    return trace
        case .pearl, .porcelain, .aluminum:             return Color.hex("2A2E32")   // cool charcoal
        case .chiffon, .vellum, .paper:                 return Color.hex("2A2520")   // warm espresso
        }
    }

    /// Chrome label color (status text, captions).
    var inkFaint: Color {
        switch self {
        case .amber:      return Color.hex("7A8B85")
        case .pearl:      return Color.hex("6E737B")
        case .porcelain:  return Color.hex("5C6168")
        case .aluminum:   return Color.hex("5C6168")
        case .chiffon:    return Color.hex("7B6E60")
        case .vellum:     return Color.hex("6B5D4F")
        case .paper:      return Color.hex("6B5D4F")
        }
    }

    /// Subtle chrome (timestamps, secondary metadata).
    var inkSubtle: Color {
        switch self {
        case .amber:      return Color.hex("6B7A75")
        case .pearl:      return Color.hex("8A8F96")
        case .porcelain:  return Color.hex("787D84")
        case .aluminum:   return Color.hex("4F545B")
        case .chiffon:    return Color.hex("928576")
        case .vellum:     return Color.hex("857664")
        case .paper:      return Color.hex("5C4F42")
        }
    }

    /// Top control rail - brushed cover. Tuned per scheme; lightest
    /// at top, darker into the body so the strip reads as a separate
    /// fabricated piece.
    var stripTopFill: LinearGradient {
        let stops: [(String, Double)] = {
            switch self {
            case .amber:
                return [("1F2426", 0.0), ("1A1F22", 0.35), ("0F1416", 1.0)]
            case .pearl:
                return [("FBFCFE", 0.0), ("F2F5F7", 0.60), ("E5E9ED", 1.0)]
            case .porcelain:
                return [("F2F5F7", 0.0), ("E8ECEF", 0.60), ("DCE0E4", 1.0)]
            case .aluminum:
                return [("DFE3E8", 0.0), ("D4D8DD", 0.60), ("C8CDD2", 1.0)]
            case .chiffon:
                return [("FDF8EB", 0.0), ("F5F0E2", 0.60), ("ECE7D6", 1.0)]
            case .vellum:
                return [("F8F3E5", 0.0), ("F0EBDB", 0.60), ("E8E2D0", 1.0)]
            case .paper:
                return [("F2ECDB", 0.0), ("EAE3D0", 0.60), ("E2DBC6", 1.0)]
            }
        }()
        return LinearGradient(
            stops: stops.map { .init(color: Color.hex($0.0), location: $0.1) },
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Bottom rail - recessed feel. Asymmetric with stripTop.
    var stripBottomFill: LinearGradient {
        let stops: [(String, Double)] = {
            switch self {
            case .amber:
                return [("0D1113", 0.0), ("161B1E", 0.55), ("1E2528", 1.0)]
            case .pearl:
                return [("ECEFF2", 0.0), ("F5F8FA", 0.55), ("FBFDFE", 1.0)]
            case .porcelain:
                return [("E0E4E8", 0.0), ("EAEEF1", 0.55), ("F0F3F6", 1.0)]
            case .aluminum:
                return [("CFD4D9", 0.0), ("D6DBE0", 0.55), ("DDE2E7", 1.0)]
            case .chiffon:
                return [("F0ECDE", 0.0), ("F8F3E6", 0.55), ("FDF9EC", 1.0)]
            case .vellum:
                return [("ECE6D6", 0.0), ("F4EFE0", 0.55), ("F9F4E6", 1.0)]
            case .paper:
                return [("E2DAC4", 0.0), ("EBE3CD", 0.55), ("F3ECD8", 1.0)]
            }
        }()
        return LinearGradient(
            stops: stops.map { .init(color: Color.hex($0.0), location: $0.1) },
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: Theme bindings

    /// Canonical scheme for a given Talkie theme. Used by the bay's
    /// default state when no user-set value is stored.
    static func canonical(for theme: ThemePreset?) -> BayScheme {
        switch theme {
        case .scope:       return .chiffon
        // case .modern:   return .pearl     // future - when modern theme lands
        default:           return .amber
        }
    }
}
