//
//  AgentTheme.swift
//  TalkieAgent
//
//  Agent-specific semantic theme roles built on TalkieKit foundations.
//

import SwiftUI
@_exported import TalkieKit

// MARK: - Agent theme
//
// This mirrors Talkie's semantic theme vocabulary (backgrounds, surfaces, ink,
// structure, and accent) while resolving those roles to an Agent-specific
// palette. Raw palette values belong here; feature views compose these roles
// into gradients, shadows, and component treatments without minting colors.
enum AgentTheme {
    // Shared family foundation: same roles as Talkie, Agent-specific mapping.
    static let textPrimary   = ScopeInk.primary
    static let textSecondary = ScopeInk.muted
    static let textTertiary  = ScopeInk.faint
    static let textMuted     = ScopeInk.subtle

    static let background          = ScopeCanvas.canvas
    static let backgroundSecondary = ScopeCanvas.canvasAlt
    static let backgroundTertiary  = ScopeCanvas.pane
    static let surface             = opsAdaptive(light: .white, dark: ScopeCanvas.surface)
    static let surfaceElevated     = ScopeCanvas.pane
    static let surfaceCard         = surface

    // Agent chrome is one cool step beyond Talkie's neutral chassis. The tint
    // is deliberately low-chroma: it should read as equipment, not a blue app.
    static let chrome = opsAdaptive(
        light: Color(red: 231.0/255, green: 235.0/255, blue: 238.0/255),
        dark: Color(red: 21.0/255, green: 27.0/255, blue: 31.0/255)
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
    static let brandAccent = ScopeAmber.solid
    static let brandAccentStrong = ScopeBrass.solid

    // MARK: Instrument surfaces

    // Agent's fabricated pearl/steel material family. These are semantic
    // surface roles; AgentInstrumentStyle owns the reusable recipes.
    static let instrumentSurface = opsAdaptive(
        light: Color.hex("F5F8FA"),
        dark: Color(red: 17.0/255, green: 26.0/255, blue: 33.0/255)
    )
    static let instrumentChromeHighlight = opsAdaptive(
        light: Color.hex("FBFCFE"),
        dark: Color(red: 24.0/255, green: 36.0/255, blue: 45.0/255)
    )
    static let instrumentChrome = opsAdaptive(
        light: Color.hex("F2F5F7"),
        dark: Color(red: 24.0/255, green: 36.0/255, blue: 45.0/255)
    )
    static let instrumentChromeLow = opsAdaptive(
        light: Color.hex("E5E9ED"),
        dark: Color(red: 17.0/255, green: 26.0/255, blue: 33.0/255).opacity(0.92)
    )
    static let instrumentChromeSecondary = opsAdaptive(
        light: Color.hex("E8EDF0"),
        dark: Color(red: 17.0/255, green: 26.0/255, blue: 33.0/255)
    )
    static let instrumentCard = opsAdaptive(
        light: Color.white.opacity(0.74),
        dark: Color.white.opacity(0.035)
    )
    static let instrumentCardProminent = opsAdaptive(
        light: Color.white.opacity(0.80),
        dark: Color.white.opacity(0.035)
    )
    static let instrumentText = opsAdaptive(
        light: Color.hex("2A2E32"),
        dark: ScopeInk.primary
    )
    static let instrumentTextMuted = opsAdaptive(
        light: Color.hex("6E737B"),
        dark: ScopeInk.muted
    )
    static let instrumentAction = opsAdaptive(
        light: Color.hex("D49236"),
        dark: accent
    )
    static let instrumentActionSoft = instrumentAction.opacity(0.08)
    static let instrumentActionBorder = opsAdaptive(
        light: Color.hex("D49236").opacity(0.25),
        dark: border
    )
}
