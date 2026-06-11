//
//  DesignSystem.swift
//  TalkieAgent
//
//  Re-exports shared design tokens from TalkieKit.
//  Overlay-specific styling can be added here if needed.
//

import SwiftUI
@_exported import TalkieKit

// MARK: - TalkieTheme (Agent-local shadow)
//
// Repoints the `TalkieTheme` tokens the Agent uses at the shared Ops palette so
// the settings panes match the console shell exactly. The Ops tokens are now
// appearance-adaptive (see `opsAdaptive` in OpsKit), so these follow the user's
// light/dark setting too. Scoped to the Agent target: the shared kit (and the
// views that depend on it, e.g. LivePill) is untouched.
enum TalkieTheme {
    // Text — Hudson ink / muted / dim, with a fourth faint step for `textMuted`.
    static let textPrimary   = OpsInk.ink            // #E5E5E5
    static let textSecondary = OpsInk.muted          // #A3A3A3
    static let textTertiary  = OpsInk.dim            // #737373
    static let textMuted     = OpsInk.dim.opacity(0.7)

    // Surfaces — card == Hudson surface; elevated sits a hair above it.
    static let background      = OpsInk.bg           // #0A0A0A
    static let surface         = OpsInk.surface      // #171717
    static let surfaceCard     = OpsInk.surface      // #171717
    static let surfaceElevated = opsAdaptive(
        light: Color(red: 248.0/255, green: 248.0/255, blue: 250.0/255),
        dark: Color(red: 32.0/255, green: 32.0/255, blue: 32.0/255)
    )

    // Structure & interaction.
    static let border  = OpsInk.border               // #272727
    static let divider = OpsHairline.standard            // #262626
    static let hover   = OpsSurface.hover                 // white @ 4.5%

    // Accent follows the user's chosen accent color (appearance-independent).
    static let accent  = Color.accentColor
}
