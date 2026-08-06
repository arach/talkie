//
//  DeckPhoneDictation.swift
//  Talkie iOS
//
//  The phone-mic half of the deck's dictate key.
//
//  Host mode is a remote control: press the key, the Mac opens its own
//  microphone, and the deck watches the result come back. This is the other
//  case — you can see the screen but you are not near it — so the phone does
//  the listening and the transcribing itself, and only the finished words
//  cross the bridge. The audio never leaves the device.
//
//  Recording and transcription are `InlineDictationController`, the same path
//  the SSH terminal and the Codex deck already use, so this file is only about
//  where the words go afterwards: `TextInserter` on the Mac, via
//  `/companion/paste-text`.
//

import Foundation
import SwiftUI

@MainActor
final class DeckPhoneDictation: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        /// Words in hand, on their way to the Mac.
        case sending
    }

    @Published private(set) var phase: Phase = .idle
    /// The last transcript, kept after `.sending` so the cockpit card has
    /// something to show instead of blanking the moment the words land.
    @Published private(set) var transcript: String = ""
    @Published private(set) var errorMessage: String?
    /// Mic level, 0…1, for whatever wants to look alive while recording.
    @Published private(set) var level: Float = 0

    /// Press return on the Mac after inserting. A deck key that dictates into
    /// whatever has focus should not decide to submit it — that is the caller's
    /// call, and for the board deck the answer is no.
    var submitAfterInsert = false

    private lazy var controller: InlineDictationController = makeController()

    var isActive: Bool { phase != .idle }

    func toggle() {
        switch phase {
        case .idle:
            start()
        case .recording:
            controller.stop(insertTranscript: true)
        case .transcribing, .sending:
            // Mid-flight. Tapping again should not start a second recording on
            // top of the one still being written up.
            break
        }
    }

    func cancel() {
        controller.cancel()
        phase = .idle
        level = 0
    }

    private func start() {
        errorMessage = nil
        transcript = ""
        Task { await controller.start() }
    }

    private func makeController() -> InlineDictationController {
        let controller = InlineDictationController()

        controller.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .idle:
                // Only fall back to idle if we aren't already carrying the
                // transcript to the Mac — the controller finishes before the
                // network does.
                if self.phase != .sending { self.phase = .idle }
                self.level = 0
            case .recording:
                self.phase = .recording
            case .transcribing:
                self.phase = .transcribing
            }
        }

        controller.onTranscript = { [weak self] text in
            guard let self else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                self.phase = .idle
                return
            }
            self.transcript = trimmed
            self.deliver(trimmed)
        }

        controller.onError = { [weak self] message in
            guard let self else { return }
            self.errorMessage = message
            self.phase = .idle
            self.level = 0
        }

        controller.onAudioLevel = { [weak self] level in
            self?.level = level
        }

        return controller
    }

    private func deliver(_ text: String) {
        phase = .sending
        Task { @MainActor in
            do {
                let response = try await BridgeManager.shared.sendCompanionTextToMac(
                    text,
                    submit: submitAfterInsert
                )
                if !response.ok {
                    errorMessage = response.error ?? "The Mac couldn’t take that text"
                }
            } catch {
                // The words are still in `transcript`, so a failed delivery
                // leaves something readable on screen rather than swallowing a
                // recording the user just made.
                errorMessage = "Couldn’t reach the Mac: \(error.localizedDescription)"
            }
            phase = .idle
            level = 0
        }
    }
}
