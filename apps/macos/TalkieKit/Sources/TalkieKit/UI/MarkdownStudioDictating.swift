//
//  MarkdownStudioDictating.swift
//  TalkieKit
//
//  The voice-capture seam for the Talkie Markdown editor. The real recording
//  engines live in the app targets (Talkie's `DictationInput`, the Agent's
//  `AgentVoiceAudioMeter` + `EngineClient`), which TalkieKit can't import, so
//  the studio host talks to them through this protocol. The host owns the
//  record → transcribe → insert lifecycle and the HUD; the provider only has
//  to start a capture, surface a live level, and hand back a transcript plus
//  the audio file when asked to stop.
//

import Foundation

@MainActor
public protocol MarkdownStudioDictating: AnyObject {
    /// Live input amplitude in 0…1, polled by the host to drive the HUD meter.
    var audioLevel: Float { get }

    /// Begin capturing microphone audio. Resolves once recording is actually
    /// live (so the host can flip the HUD from "starting" to "listening").
    func start() async throws

    /// Stop capturing and transcribe. Returns the transcript and an audio file
    /// the caller now owns — the host either moves it into the document's
    /// assets (dictation block) or discards it (prose).
    func stop() async throws -> (text: String, audioURL: URL)

    /// Abort an in-flight capture without transcribing.
    func cancel()
}
