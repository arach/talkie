//
//  AskAINext.swift
//  Talkie iOS
//
//  STUB — Phase-2 placeholder. To be implemented by a dedicated
//  Codex stream:
//    - Agentic loop surface: prompt input (text or voice via the
//      shell's voice button), runs through the AI provider, displays
//      response, supports follow-up turns (multi-step loop).
//    - Reuses the AI service backbone behind `CaptureAICommandsSheet`
//      (the AI commands already wired in CaptureDetailNext).
//    - Optional "agent presets" — Summarize / Extract action items /
//      Rewrite — pre-load common loop patterns.
//    - Visual: editorial body (TalkieTypeStyle .headline / .preview)
//      with mono labels for "turns" / metadata. SF Mono for token
//      counts, latency, etc.
//    - Entry: ChromeOverlay tray "Ask AI" slot (currently routes
//      here) + Home-screen "Ask AI" station (optional).
//

import SwiftUI

struct AskAINext: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("ASK AI")
                    .talkieType(.channelLabel)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Text("Stub — implementation pending")
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
    }
}
