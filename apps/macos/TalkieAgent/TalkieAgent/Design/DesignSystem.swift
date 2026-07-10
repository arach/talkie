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
// The Agent shares Talkie's cool Scope chassis and ink hierarchy, then adds a
// restrained steel-blue signal color for active agent state. That keeps both
// apps in one visual family without making Agent Home look like another Talkie
// library window. Scoped to the Agent target: the shared kit (and the views
// that depend on it, e.g. LivePill) is untouched.
enum TalkieTheme {
    // Shared family foundation.
    static let textPrimary   = ScopeInk.primary
    static let textSecondary = ScopeInk.muted
    static let textTertiary  = ScopeInk.faint
    static let textMuted     = ScopeInk.subtle

    static let background      = ScopeCanvas.canvas
    static let surface         = opsAdaptive(light: .white, dark: ScopeCanvas.surface)
    static let surfaceCard     = surface
    static let surfaceElevated = ScopeCanvas.pane

    // Agent chrome is one cool step beyond Talkie's neutral chassis. The tint
    // is deliberately low-chroma: it should read as equipment, not a blue app.
    static let chrome = opsAdaptive(
        light: Color(red: 231.0/255, green: 235.0/255, blue: 238.0/255),
        dark: Color(red: 21.0/255, green: 27.0/255, blue: 31.0/255)
    )
    static let instrument = opsAdaptive(
        light: Color(red: 234.0/255, green: 240.0/255, blue: 243.0/255),
        dark: Color(red: 17.0/255, green: 26.0/255, blue: 33.0/255)
    )
    static let instrumentChrome = opsAdaptive(
        light: Color(red: 225.0/255, green: 233.0/255, blue: 237.0/255),
        dark: Color(red: 24.0/255, green: 36.0/255, blue: 45.0/255)
    )

    // Structure & interaction.
    static let border = opsAdaptive(
        light: Color(red: 205.0/255, green: 214.0/255, blue: 220.0/255),
        dark: Color(red: 43.0/255, green: 57.0/255, blue: 67.0/255)
    )
    static let divider = border.opacity(0.78)
    static let hover = ScopeInk.primary.opacity(0.045)

    // Agent signal: a desaturated blue that remains readable at small sizes.
    // Brass stays available as the shared Talkie brand cue, not as a competing
    // interaction color inside Agent Home.
    static let accent = opsAdaptive(
        light: Color(red: 72.0/255, green: 104.0/255, blue: 136.0/255),
        dark: Color(red: 130.0/255, green: 169.0/255, blue: 203.0/255)
    )
    static let accentStrong = opsAdaptive(
        light: Color(red: 49.0/255, green: 78.0/255, blue: 107.0/255),
        dark: Color(red: 166.0/255, green: 197.0/255, blue: 220.0/255)
    )
    static let accentSoft = accent.opacity(0.10)
    static let accentBorder = accent.opacity(0.28)
    static let accentGlow = accent.opacity(0.22)
    static let brandAccent = ScopeAmber.solid
}
