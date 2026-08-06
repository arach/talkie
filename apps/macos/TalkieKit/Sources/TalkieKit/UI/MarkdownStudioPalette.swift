//
//  MarkdownStudioPalette.swift
//  TalkieKit
//
//  The colours the Markdown Studio web bundle draws itself with.
//
//  The studio is a WKWebView, so its palette lives in CSS custom properties
//  rather than in `Theme`. It also lives in TalkieKit, which cannot see the
//  app's `Theme` type at all — which is why the studio shipped with one
//  hardcoded warm palette baked into `:root` and stayed on it no matter what
//  theme the rest of the app was wearing.
//
//  This is the seam: a plain value the host fills in from whatever theme is
//  current, and which knows how to write itself onto the page. TalkieKit
//  still owns no opinion about which colours are right.
//

#if os(macOS)
import AppKit
import SwiftUI

public struct MarkdownStudioPalette: Equatable, Sendable {
    // Text ramp, darkest to lightest.
    public var ink: Color
    public var inkSecondary: Color
    public var inkDim: Color
    public var inkFaint: Color
    /// Source-pane text. Sits a step softer than `ink` so the raw markdown
    /// reads as working material rather than as the finished document.
    public var sourceInk: Color

    public var accent: Color
    public var accentBright: Color
    public var trace: Color

    // Surfaces, back to front.
    public var canvas: Color
    public var surface: Color
    public var source: Color
    public var panel: Color
    public var status: Color

    public var edge: Color

    public init(
        ink: Color,
        inkSecondary: Color,
        inkDim: Color,
        inkFaint: Color,
        sourceInk: Color,
        accent: Color,
        accentBright: Color,
        trace: Color,
        canvas: Color,
        surface: Color,
        source: Color,
        panel: Color,
        status: Color,
        edge: Color
    ) {
        self.ink = ink
        self.inkSecondary = inkSecondary
        self.inkDim = inkDim
        self.inkFaint = inkFaint
        self.sourceInk = sourceInk
        self.accent = accent
        self.accentBright = accentBright
        self.trace = trace
        self.canvas = canvas
        self.surface = surface
        self.source = source
        self.panel = panel
        self.status = status
        self.edge = edge
    }

    /// The studio's original palette, transcribed from the `:root` block it
    /// used to hardcode. Kept as the default so a host that says nothing gets
    /// exactly what shipped before, and so there is something to fall back to
    /// if a theme ever fails to supply one.
    public static let manuscript = MarkdownStudioPalette(
        ink: Color(hex: 0x1A1612),
        inkSecondary: Color(hex: 0x3D342A),
        inkDim: Color(hex: 0x6A5D4E),
        inkFaint: Color(hex: 0x93856C),
        sourceInk: Color(hex: 0x4A3F31),
        accent: Color(hex: 0xC47D1C),
        accentBright: Color(hex: 0xE5AC4F),
        trace: Color(hex: 0xFFB84D),
        canvas: Color(hex: 0xF4F1E9),
        surface: Color(hex: 0xFFFDF8),
        source: Color(hex: 0xF3EFE4),
        panel: Color(hex: 0xFAF6EC),
        status: Color(hex: 0xEEEAE1),
        edge: Color(hex: 0x402E16)
    )

    // MARK: - Emitting

    /// JavaScript that stamps this palette onto the live page.
    ///
    /// Written as custom-property overrides on `:root` rather than as a
    /// stylesheet swap, so every rule in `studio.css` keeps working untouched
    /// and re-theming a page that is already open costs one `evaluate`.
    ///
    /// The alpha-derived variables reuse the ratios the original palette
    /// chose — 0.12 / 0.20 / 0.42 for accent washes, 0.14 / 0.07 for edges —
    /// so a new accent lands with the same weight the warm one had rather
    /// than needing every tint re-picked by hand.
    public func stylesheetScript() -> String {
        var assignments: [(String, String)] = [
            ("--ink", ink.cssHex),
            ("--ink2", inkSecondary.cssHex),
            ("--dim", inkDim.cssHex),
            ("--faint", inkFaint.cssHex),
            ("--srcink", sourceInk.cssHex),

            ("--acc", accent.cssHex),
            ("--acc2", accentBright.cssHex),
            ("--trace", trace.cssHex),
            ("--soft", accent.cssRGBA(0.12)),
            ("--soft2", accent.cssRGBA(0.20)),
            ("--accline", accent.cssRGBA(0.42)),

            ("--surface", surface.cssHex),
            ("--source", source.cssHex),
            ("--canvas", canvas.cssHex),
            ("--panel", panel.cssHex),
            ("--status", status.cssHex),

            ("--edge", edge.cssRGBA(0.14)),
            ("--edge2", edge.cssRGBA(0.07)),
        ]

        // Revision ink follows the accent for additions, because "new voice"
        // and "the accent" are the same idea. Deletions keep their terracotta
        // wherever the theme goes: it is a semantic colour, not a decorative
        // one, and a deletion that adopts a blue accent stops reading as a
        // strike at all.
        assignments.append(("--rev-add", accent.cssHex))
        assignments.append(("--rev-add-wash", accent.cssRGBA(0.16)))
        assignments.append(("--rev-add-soft", accent.cssRGBA(0.10)))
        assignments.append(("--rev-del-ink", inkDim.cssHex))

        let body = assignments
            .map { "r.setProperty('\($0.0)','\($0.1)');" }
            .joined()

        return "(function(){var r=document.documentElement.style;\(body)})();"
    }
}

// MARK: - CSS colour formatting

extension Color {
    fileprivate init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// `#RRGGBB` in device RGB.
    ///
    /// Themes may hand over colours in any space — including catalog colours
    /// that resolve per appearance — so this converts rather than assuming
    /// components are readable, and falls back rather than trapping.
    var cssHex: String {
        guard let rgb = NSColor(self).usingColorSpace(.deviceRGB) else { return "#000000" }
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
    }

    func cssRGBA(_ alpha: Double) -> String {
        guard let rgb = NSColor(self).usingColorSpace(.deviceRGB) else {
            return "rgba(0,0,0,\(alpha))"
        }
        return String(
            format: "rgba(%d,%d,%d,%.2f)",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded()),
            alpha
        )
    }
}
#endif
