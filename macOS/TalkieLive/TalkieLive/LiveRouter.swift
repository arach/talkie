//
//  LiveRouter.swift
//  TalkieLive
//
//  Routes transcripts to clipboard, typing, and storage
//

import AppKit
import Carbon.HIToolbox
import os.log

private let logger = Logger(subsystem: "jdi.talkie.live", category: "LiveRouter")

enum RoutingMode: String, CaseIterable {
    case clipboardOnly = "clipboardOnly"  // Copy to clipboard only
    case paste = "paste"                  // Copy to clipboard and paste (⌘V)

    var displayName: String {
        switch self {
        case .clipboardOnly: return "Clipboard Only"
        case .paste: return "Copy & Paste"
        }
    }

    var description: String {
        switch self {
        case .clipboardOnly: return "Copy text to clipboard without pasting"
        case .paste: return "Copy to clipboard and automatically paste"
        }
    }
}

struct TranscriptRouter: LiveRouter {
    var mode: RoutingMode = .paste

    func handle(transcript: String) async {
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        // Filter out empty or Whisper noise tokens
        guard !cleaned.isEmpty,
              !cleaned.hasPrefix("["),  // [BLANK_AUDIO], [MUSIC], etc.
              cleaned != "(silence)" else {
            logger.info("Skipping noise/empty transcript: \(transcript)")
            return
        }

        // Copy to clipboard (storage is handled by LiveController with metadata)
        copyToClipboard(cleaned)

        // Paste if requested
        if mode == .paste {
            try? await Task.sleep(for: .milliseconds(50))
            simulatePaste()
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        logger.info("Copied to clipboard: \(text.prefix(50))...")
    }

    private func simulatePaste() {
        // Simulate ⌘V
        let source = CGEventSource(stateID: .hidSystemState)

        // V key = keycode 9
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            logger.error("Failed to create paste events")
            return
        }

        // Add Command modifier
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        logger.info("Simulated paste (⌘V)")
    }
}
