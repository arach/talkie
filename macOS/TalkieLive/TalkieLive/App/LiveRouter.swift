//
//  LiveRouter.swift
//  TalkieLive
//
//  Routes transcripts to clipboard, typing, and storage
//

import AppKit
import ApplicationServices  // For AXIsProcessTrusted
import Carbon.HIToolbox
import TalkieKit

private let log = Log(.system)

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
            log.info("Skipping noise: \(transcript)")
            return
        }

        // Validate: Ensure valid UTF-8 and reasonable length
        guard cleaned.utf8.count < 1_000_000,  // 1MB limit
              cleaned.canBeConverted(to: .utf8) else {
            log.error("Invalid text - cannot copy to clipboard")
            return
        }

        // Copy to clipboard (required for both modes)
        let copySuccess = copyToClipboard(cleaned)
        guard copySuccess else {
            log.error("Clipboard copy failed")
            return
        }

        if mode == .paste {
            // Legacy paste: clipboard + simulated Cmd+V (proven reliable)
            // TODO: Switch to TextInserter.shared.insert() once tested
            simulatePaste()

            // Optionally press Enter after paste (for chat apps, terminals)
            let shouldPressEnter = await MainActor.run { LiveSettings.shared.pressEnterAfterPaste }
            if shouldPressEnter {
                simulateEnter()
            }
        }
    }

    private func copyToClipboard(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        pb.prepareForNewContents()

        guard pb.setString(text, forType: .string) else {
            return false
        }

        log.info("Copied: \(text.prefix(50))...")
        return true
    }

    private func simulatePaste() {
        guard AXIsProcessTrusted() else {
            log.error("Accessibility permission NOT granted - cannot paste")
            return
        }

        guard let src = CGEventSource(stateID: .combinedSessionState) else {
            log.error("Failed to create CGEventSource - cannot paste")
            return
        }

        let events: [(UInt16, Bool)] = [
            (0x37, true),   // ⌘ down
            (0x09, true),   // V down
            (0x09, false),  // V up
            (0x37, false)   // ⌘ up
        ]

        var eventsPosted = 0
        for (key, down) in events {
            if let evt = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down) {
                evt.flags = down && key == 0x09 ? .maskCommand : []
                evt.post(tap: .cghidEventTap)
                eventsPosted += 1
            }
        }

        log.info("Pasted (\(eventsPosted)/4 events posted)")
    }

    private func simulateEnter() {
        guard let src = CGEventSource(stateID: .combinedSessionState) else {
            log.error("Failed to create CGEventSource - cannot send Enter")
            return
        }

        // Small delay to ensure paste completes first
        usleep(50_000)  // 50ms

        // Return/Enter key = 0x24
        let events: [(UInt16, Bool)] = [
            (0x24, true),   // Return down
            (0x24, false)   // Return up
        ]

        for (key, down) in events {
            if let evt = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down) {
                evt.post(tap: .cghidEventTap)
            }
        }

        log.info("Sent Enter key")
    }
}
