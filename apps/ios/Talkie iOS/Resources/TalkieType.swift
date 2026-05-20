//
//  TalkieType.swift
//  Talkie iOS
//
//  Type tokens for the Next design language. Each token bundles
//  font + tracking + (optional) textCase + (optional) monospacedDigit
//  so call sites are one line and trackings don't drift between
//  surfaces.
//
//  Two-family voice:
//    - Editorial body / headlines = Newsreader (light/regular)
//      (custom font, shipped in bundle; same face usetalkie.com uses)
//    - Instrument labels / numerals / timestamps = SF Mono
//
//  The serif headline against mono band labels gives the screen
//  a "studio log" character — refined headline + technical labels —
//  without the heaviness of New York or the flatness of mono-only.
//
//  Pair these with chrome tokens from `ChromeTokens` for color.
//
//  Usage:
//      Text("PICK UP").talkieType(.channelLabel)
//      Text(memo.title).talkieType(.headline)
//      Text(count).talkieType(.instrumentReadout)
//
//  Add new tokens here; do not add raw .font(.system(...)) calls in
//  Next surfaces.
//

import SwiftUI

struct TalkieTypeStyle {
    let font: Font
    let tracking: CGFloat
    let textCase: Text.Case?

    init(
        font: Font,
        tracking: CGFloat = 0,
        textCase: Text.Case? = nil
    ) {
        self.font = font
        self.tracking = tracking
        self.textCase = textCase
    }
}

// MARK: - Token catalog
//
// Naming convention:
//   wordmark / channelLabel*    — mono uppercase, the "band" voice
//   headline / listTitle / preview — serif, the "content" voice
//   instrumentReadout*          — serif numerals (counters, levels, etc.)

extension TalkieTypeStyle {

    // ── Channel-label band (SF Mono, uppercase, MEDIUM weight) ───

    /// "TALKIE" wordmark in the header. Medium weight reads light
    /// at 10pt; tracking carries the band feel.
    static let wordmark = TalkieTypeStyle(
        font: .system(size: 10, weight: .medium, design: .monospaced),
        tracking: 2.8
    )

    /// Section eyebrows: "PICK UP", "· RECENT · 4", "INSPECTOR · VOICE".
    static let channelLabel = TalkieTypeStyle(
        font: .system(size: 10, weight: .medium, design: .monospaced),
        tracking: 2.4,
        textCase: .uppercase
    )

    /// Smaller eyebrow for nested context.
    static let channelLabelSmall = TalkieTypeStyle(
        font: .system(size: 9, weight: .medium, design: .monospaced),
        tracking: 2.0,
        textCase: .uppercase
    )

    /// Tiny eyebrow under instrument readouts. Smallest mono size.
    static let channelLabelTiny = TalkieTypeStyle(
        font: .system(size: 9, weight: .medium, design: .monospaced),
        tracking: 2.0,
        textCase: .uppercase
    )

    /// Mono uppercase pill / chip text — "CONTINUE ›", "ALL ›", "RUN".
    static let chipLabel = TalkieTypeStyle(
        font: .system(size: 10, weight: .medium, design: .monospaced),
        tracking: 2.0,
        textCase: .uppercase
    )

    /// Mono meta string under a headline — e.g. "COMPOSE · 31 WORDS · 4M AGO".
    /// Regular weight (not medium) — meta should sit *behind* the
    /// headline visually, not parallel to channel labels.
    static let metaMono = TalkieTypeStyle(
        font: .system(size: 10, weight: .regular, design: .monospaced),
        tracking: 2.0,
        textCase: .uppercase
    )

    /// Relative time stamp in list rows ("Sun", "9:34 AM", "Yesterday").
    static let timestamp = TalkieTypeStyle(
        font: Font.system(size: 10, weight: .regular, design: .monospaced).monospacedDigit(),
        tracking: 0
    )

    // ── Editorial headline (Newsreader serif) ────────────────────
    //
    // Newsreader is reserved as PUNCTUATION — the editorial moment
    // (PICK UP title, section headlines). Lists + previews stay on
    // system sans so the serif doesn't become the body voice.
    // Custom font: Resources/Fonts/Newsreader.ttf (variable opsz/wght).

    /// Primary headline — PICK UP document title, section h1.
    /// Newsreader Regular — the only place serif appears on the
    /// surface. Light weight read too thin; regular gives it the
    /// editorial body the moment deserves.
    static let headline = TalkieTypeStyle(
        font: Font.custom("Newsreader", size: 22).weight(.regular),
        tracking: -0.1
    )

    /// Quieter headline — fallback / empty state ("Nothing recent").
    /// Sans, lighter weight. Serif here would feel mismatched against
    /// the empty/quiet tone.
    static let headlineSecondary = TalkieTypeStyle(
        font: .system(size: 18, weight: .light, design: .default),
        tracking: 0
    )

    // ── List + preview body (system sans) ────────────────────────

    /// List row title (Recent items, library rows). System sans,
    /// regular weight — scans cleanly without competing with the
    /// serif headline above.
    static let listTitle = TalkieTypeStyle(
        font: .system(size: 15, weight: .regular, design: .default),
        tracking: -0.05
    )

    /// Single-line preview / subtitle below a list row title.
    static let preview = TalkieTypeStyle(
        font: .system(size: 13, weight: .regular, design: .default),
        tracking: 0
    )

    // ── Instrument readouts (mono numerals, regular weight) ──────

    /// Big numeric counter — ActionBus cells, telemetry tiles.
    /// Regular mono at 24pt reads like a clean LCD display, not
    /// a heavy panel-mounted gauge.
    static let instrumentReadout = TalkieTypeStyle(
        font: Font.system(size: 24, weight: .regular, design: .monospaced).monospacedDigit(),
        tracking: -0.3
    )

    /// Smaller numeric readout — inspector metric tiles.
    static let instrumentReadoutSmall = TalkieTypeStyle(
        font: Font.system(size: 15, weight: .regular, design: .monospaced).monospacedDigit(),
        tracking: 0
    )

    // ── Inspector / form fields ──────────────────────────────────

    /// Field label in an inspector / form ("Engine", "Sample rate").
    static let fieldLabel = TalkieTypeStyle(
        font: .system(size: 12, weight: .regular, design: .default),
        tracking: 0
    )

    /// Field value (right-aligned, mono so values line up vertically).
    static let fieldValue = TalkieTypeStyle(
        font: .system(size: 12, weight: .regular, design: .monospaced),
        tracking: 0
    )

    /// Helper / hint text beneath a field label.
    static let hint = TalkieTypeStyle(
        font: .system(size: 10, weight: .light, design: .default),
        tracking: 0
    )
}

// MARK: - View modifier

extension View {
    /// Apply a Talkie type token. Bundles font, tracking, and case
    /// transform so callers don't reassemble them per surface.
    func talkieType(_ style: TalkieTypeStyle) -> some View {
        self
            .font(style.font)
            .tracking(style.tracking)
            .textCase(style.textCase)
    }
}
