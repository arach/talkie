//
//  AgentInstrumentStyle.swift
//  TalkieAgent
//
//  Reusable pearl/steel component recipes built from AgentTheme roles.
//

import SwiftUI

/// Agent's fabricated instrument treatment.
///
/// `AgentTheme` owns semantic palette values. This layer combines those values
/// into reusable component recipes, mirroring Talkie's theme → style boundary.
/// Feature views remain responsible for their layout and one-off decoration.
enum AgentInstrumentStyle {
    static let surface = AgentTheme.instrumentSurface
    static let card = AgentTheme.instrumentCard
    static let prominentCard = AgentTheme.instrumentCardProminent
    static let text = AgentTheme.instrumentText
    static let mutedText = AgentTheme.instrumentTextMuted

    static let action = AgentTheme.instrumentAction
    static let actionSoft = AgentTheme.instrumentActionSoft
    static let actionBorder = AgentTheme.instrumentActionBorder
    static let brandEdge = opsAdaptive(
        light: AgentTheme.brandAccent.opacity(0.24),
        dark: AgentTheme.border
    )

    private static let commandChromeHighlight = opsAdaptive(
        light: AgentTheme.instrumentChromeHighlight,
        dark: AgentTheme.instrumentChromeHighlight.opacity(0.96)
    )

    static let commandChrome = LinearGradient(
        stops: [
            .init(color: commandChromeHighlight, location: 0),
            .init(color: AgentTheme.instrumentChrome, location: 0.58),
            .init(color: AgentTheme.instrumentChromeLow, location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let conversationChrome = LinearGradient(
        colors: [
            AgentTheme.instrumentChromeHighlight,
            AgentTheme.instrumentChromeSecondary,
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}
