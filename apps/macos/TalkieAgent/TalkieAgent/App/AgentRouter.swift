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
    private static let modifierReleasePoll: Duration = .milliseconds(20)
    private static let blockingModifierFlags: NSEvent.ModifierFlags = [
        .command,
        .option,
        .control,
        .shift
    ]

    var mode: RoutingMode = .paste

    @MainActor @discardableResult
    func handle(transcript: String) async -> Bool {
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        // Filter noise
        guard !Self.isSkippableNoise(cleaned) else {
            log.info("Skipping noise: \(transcript)")
            return false
        }

        // Validate: Ensure valid UTF-8 and reasonable length
        guard cleaned.utf8.count < 1_000_000,  // 1MB limit
              cleaned.canBeConverted(to: .utf8) else {
            log.error("Invalid text - cannot copy to clipboard")
            return false
        }

        // Copy to clipboard (required for both modes)
        let copySuccess = copyToClipboard(cleaned)
        guard copySuccess else {
            log.error("Clipboard copy failed")
            return false
        }

        if mode == .paste {
            // Cache setting before paste to avoid async hop after
            let shouldPressEnter = await MainActor.run { LiveSettings.shared.pressEnterAfterPaste }

            let modifiersReleased = await waitForModifierReleaseBeforePaste()
            guard modifiersReleased else { return false }
            guard !Task.isCancelled else { return false }

            // Paste: clipboard + simulated Cmd+V
            let pasted = simulatePaste()
            guard pasted else { return false }

            // Optionally press Enter after paste (for chat apps, terminals)
            if shouldPressEnter {
                await submitAfterPaste()
            }
        }

        return true
    }

    static func isSkippableNoise(_ cleaned: String) -> Bool {
        cleaned.isEmpty || cleaned == "(silence)"
    }

    private func copyToClipboard(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        pb.declareTypes([.string], owner: nil)

        guard pb.setString(text, forType: .string) else {
            return false
        }

        guard pb.string(forType: .string) == text else {
            log.error("Clipboard readback mismatch after copy")
            return false
        }

        log.info("Copied: \(text.prefix(50))...")
        return true
    }

    private func waitForModifierReleaseBeforePaste() async -> Bool {
        let startedAt = Date()
        var lastFlags = Self.currentBlockingModifierFlags()
        guard !lastFlags.isEmpty else { return true }

        log.info("Waiting for physical hotkey modifiers to release before paste: \(Self.describeModifiers(lastFlags))")
        while !Task.isCancelled {
            let activeFlags = Self.currentBlockingModifierFlags()

            if activeFlags.isEmpty {
                let waitedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                if waitedMs > 40 {
                    log.info("Waited \(waitedMs)ms for hotkey modifiers to release before paste")
                }
                return true
            }

            lastFlags = activeFlags
            try? await Task.sleep(for: Self.modifierReleasePoll)
        }

        log.warning("Cancelled synthetic paste while physical modifiers remain active: \(Self.describeModifiers(lastFlags))")
        return false
    }

    private static func currentBlockingModifierFlags() -> NSEvent.ModifierFlags {
        // NSEvent.modifierFlags can retain synthetic flags from a global hotkey
        // event. Read the HID state so Caps Lock -> Hyper transports don't
        // make paste wait forever after the physical key is released.
        let flags = CGEventSource.flagsState(.hidSystemState)
        var modifiers: NSEvent.ModifierFlags = []
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        return modifiers.intersection(Self.blockingModifierFlags)
    }

    private static func describeModifiers(_ flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.control) { parts.append("control") }
        if flags.contains(.option) { parts.append("option") }
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.command) { parts.append("command") }
        return parts.isEmpty ? "none" : parts.joined(separator: "+")
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
