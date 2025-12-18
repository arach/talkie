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

        // Filter noise
        guard !cleaned.isEmpty,
              !cleaned.hasPrefix("["),
              cleaned != "(silence)" else {
            logger.info("Skipping noise: \(transcript)")
            return
        }

        // Validate: Ensure valid UTF-8 and reasonable length
        guard cleaned.utf8.count < 1_000_000,  // 1MB limit
              cleaned.canBeConverted(to: .utf8) else {
            logger.error("Invalid text - cannot copy to clipboard")
            return
        }

        // Copy to clipboard on main queue (NSPasteboard requirement)
        let success = await MainActor.run {
            copyToClipboard(cleaned)
        }

        guard success else {
            logger.error("Clipboard copy failed")
            return
        }

        // Paste if enabled
        if mode == .paste {
            simulatePaste()
        }
    }

    private func copyToClipboard(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        pb.prepareForNewContents()

        guard pb.setString(text, forType: .string) else {
            return false
        }

        logger.info("Copied: \(text.prefix(50))...")
        return true
    }

    private func simulatePaste() {
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let src else { return }

        // Post all events as a batch
        let events: [(UInt16, Bool)] = [
            (0x37, true),   // ⌘ down
            (0x09, true),   // V down
            (0x09, false),  // V up
            (0x37, false)   // ⌘ up
        ]

        for (key, down) in events {
            let evt = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
            evt?.flags = down && key == 0x09 ? .maskCommand : []
            evt?.post(tap: .cghidEventTap)
        }

        logger.info("Pasted")
    }
}
