//
//  AgentRouter.swift
//  TalkieAgent
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

struct TranscriptRouter: AgentRouter {
    private static let postPasteSubmitDelay: Duration = .milliseconds(180)

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
            // Cache setting before paste to avoid async hop after
            let shouldPressEnter = await MainActor.run { LiveSettings.shared.pressEnterAfterPaste }

            // Paste: clipboard + simulated Cmd+V
            let pasted = simulatePaste()
            guard pasted else { return }

            // Optionally press Enter after paste (for chat apps, terminals)
            if shouldPressEnter {
                await submitAfterPaste()
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

    private func simulatePaste() -> Bool {
        // Use cached accessibility check (pre-warmed on boot) for fast path.
        // If permission is missing, report failure to invalidate cache and force re-check.
        guard PermissionManager.shared.hasAccessibilityPermission else {
            log.error("Accessibility permission NOT granted - cannot paste")
            // Report failure so cache is invalidated and we re-check next time
            PermissionManager.shared.reportAccessibilityFailure()
            // Audible + visual feedback so user knows paste was blocked
            Task { @MainActor in
                SoundManager.shared.playPasteBlocked()
                NotificationCenter.default.post(name: .pasteBlockedByPermission, object: nil)
            }
            return false
        }

        guard let src = CGEventSource(stateID: .combinedSessionState) else {
            log.error("Failed to create CGEventSource - cannot paste")
            // This could indicate an accessibility issue - report it
            PermissionManager.shared.reportAccessibilityFailure()
            return false
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

        // If not all events posted, report potential accessibility issue
        if eventsPosted < 4 {
            log.warning("Paste incomplete (\(eventsPosted)/4 events) - possible accessibility issue")
            PermissionManager.shared.reportAccessibilityFailure()
            return false
        } else {
            log.info("Pasted (\(eventsPosted)/4 events posted)")
            return true
        }
    }

    private func submitAfterPaste() async {
        try? await Task.sleep(for: Self.postPasteSubmitDelay)
        if simulateEnter() {
            log.info("Submitted pasted transcript with Enter")
        }
    }

    private func simulateEnter() -> Bool {
        guard let src = CGEventSource(stateID: .combinedSessionState) else {
            log.error("Failed to create CGEventSource - cannot send Enter")
            return false
        }

        // Return/Enter key = 0x24
        let events: [(UInt16, Bool)] = [
            (0x24, true),   // Return down
            (0x24, false)   // Return up
        ]

        var eventsPosted = 0
        for (key, down) in events {
            if let evt = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down) {
                evt.post(tap: .cghidEventTap)
                eventsPosted += 1
            }
        }

        if eventsPosted == events.count {
            log.info("Sent Enter key")
            return true
        } else {
            log.warning("Enter incomplete (\(eventsPosted)/\(events.count) events)")
            return false
        }
    }
}
