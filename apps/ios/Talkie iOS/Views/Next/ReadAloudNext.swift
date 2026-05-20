//
//  ReadAloudNext.swift
//  Talkie iOS
//
//  STUB — Phase-2 placeholder. To be implemented by codex-talkie-readaloud.
//
//  TTS playback surface. Wires to:
//    - `SpeechSynthesisService.shared` — primary playback engine.
//    - `AVSpeechSynthesizerDelegate.willSpeakRangeOfSpeechString` —
//      drives the chunk-highlight in the source viewer (each chunk
//      is a sub-utterance range; the chunk whose range is firing
//      gets the leading-amber active bar).
//    - `AVSpeechSynthesisVoice.speechVoices()` — voice picker.
//
//  Studio reference: design/studio/components/studies/ReadAloudStudy.tsx
//  + design/studio/app/read-aloud/page.tsx. Three states (idle /
//  playing / queue) × four source kinds (text / image / url / pdf).
//
//  Non-text sources (image / url / pdf) render a "source stamp" row
//  (type glyph + filename/URL + OPEN ›) + a short excerpt of the
//  spoken text — no embedded preview. The OPEN › link hands off to
//  the system's owning viewer (Photos / Safari / Files).
//

import SwiftUI

struct ReadAloudNext: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("READ ALOUD")
                    .talkieType(.channelLabel)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Text("Stub — implementation pending")
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
    }
}
