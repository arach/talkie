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
            // Give clipboard time to settle before simulating paste
            try? await Task.sleep(for: .milliseconds(100))
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
        // Simulate ⌘V with explicit key sequence for better reliability
        let source = CGEventSource(stateID: .combinedSessionState)

        // Command key down
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)

        // V key down (keycode 9)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)

        // V key up
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand
        vUp?.post(tap: .cghidEventTap)

        // Command key up
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        cmdUp?.post(tap: .cghidEventTap)

        logger.info("Simulated paste (⌘V)")
    }
}
