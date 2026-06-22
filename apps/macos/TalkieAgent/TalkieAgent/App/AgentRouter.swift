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

struct TranscriptInsertionTarget {
    let app: NSRunningApplication
    let processIdentifier: pid_t
    let focusedElement: AXUIElement?
    let selectedTextRange: CFRange?

    var label: String {
        app.localizedName ?? app.bundleIdentifier ?? "\(processIdentifier)"
    }

    @MainActor
    static func capture(from app: NSRunningApplication?) -> TranscriptInsertionTarget? {
        guard let app else { return nil }

        var focusedElement: AXUIElement?
        var selectedTextRange: CFRange?

        if AXIsProcessTrusted() {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            focusedElement = Self.focusedElement(in: appElement)

            if let focusedElement {
                selectedTextRange = Self.selectedTextRange(in: focusedElement)
            }
        }

        return TranscriptInsertionTarget(
            app: app,
            processIdentifier: app.processIdentifier,
            focusedElement: focusedElement,
            selectedTextRange: selectedTextRange
        )
    }

    @MainActor
    func prepareForPaste() async -> Bool {
        guard !app.isTerminated else {
            log.warning("Origin app is no longer running: \(label)")
            return false
        }

        app.activate()
        let activated = await waitForActivation()
        if !activated {
            log.warning("Timed out activating origin app: \(label)")
        }

        guard let focusedElement else {
            log.info("Origin app restored without focused AX element: \(label)")
            return activated
        }

        let focusResult = AXUIElementSetAttributeValue(
            focusedElement,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )

        if focusResult != .success {
            log.debug("Could not restore origin focused element (\(focusResult.rawValue)) for \(label)")
        }

        var restoredTextRange = false
        if var range = selectedTextRange,
           let rangeValue = AXValueCreate(.cfRange, &range) {
            let rangeResult = AXUIElementSetAttributeValue(
                focusedElement,
                kAXSelectedTextRangeAttribute as CFString,
                rangeValue
            )
            restoredTextRange = rangeResult == .success
            if rangeResult != .success {
                log.debug("Could not restore origin text range (\(rangeResult.rawValue)) for \(label)")
            }
        }

        guard activated else {
            log.warning("Origin app is not frontmost after activation attempt: \(label)")
            return false
        }

        guard focusResult == .success || restoredTextRange else {
            log.warning("Could not restore origin focused input for \(label)")
            return false
        }

        log.info("Prepared origin paste target: \(label)")
        return true
    }

    @MainActor
    private func waitForActivation(timeout: TimeInterval = 0.75) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier {
                return true
            }
            try? await Task.sleep(for: .milliseconds(25))
        }

        return NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier
    }

    private static func focusedElement(in appElement: AXUIElement) -> AXUIElement? {
        var focusedRef: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )

        if result != .success {
            var windowRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
               let windowRef {
                let window = windowRef as! AXUIElement
                result = AXUIElementCopyAttributeValue(
                    window,
                    kAXFocusedUIElementAttribute as CFString,
                    &focusedRef
                )
            }
        }

        guard result == .success else { return nil }
        guard let focusedRef else { return nil }
        return (focusedRef as! AXUIElement)
    }

    private static func selectedTextRange(in element: AXUIElement) -> CFRange? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success,
              let rangeRef else {
            return nil
        }

        let rangeValue = rangeRef as! AXValue
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue, .cfRange, &range) else { return nil }
        return range
    }

}

struct TranscriptRouter: AgentRouter {
    private static let postPasteSubmitDelay: Duration = .milliseconds(180)

    var mode: RoutingMode = .paste

    @MainActor @discardableResult
    func handle(transcript: String, target: TranscriptInsertionTarget?) async -> Bool {
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

            guard !Task.isCancelled else { return false }

            if let target {
                let prepared = await target.prepareForPaste()
                guard prepared else {
                    log.error("Could not restore origin paste target; leaving transcript on clipboard")
                    return false
                }
            }

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

    @MainActor
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

        let posted = postSyntheticShortcut(keyCode: 0x09, modifiers: .maskCommand)
        guard posted else {
            log.warning("Paste shortcut failed to post - possible accessibility issue")
            PermissionManager.shared.reportAccessibilityFailure()
            return false
        }

        log.info("Pasted via private shortcut event source")
        return true
    }

    private func submitAfterPaste() async {
        try? await Task.sleep(for: Self.postPasteSubmitDelay)
        if simulateEnter() {
            log.info("Submitted pasted transcript with Enter")
        }
    }

    private func simulateEnter() -> Bool {
        // Return/Enter key = 0x24. Use the same private event source as paste
        // so a just-released hotkey cannot turn this into a modified Enter.
        if postSyntheticShortcut(keyCode: 0x24, modifiers: []) {
            log.info("Sent Enter key")
            return true
        } else {
            log.warning("Enter key failed to post")
            return false
        }
    }

    private func postSyntheticShortcut(keyCode: UInt16, modifiers: CGEventFlags) -> Bool {
        guard let source = CGEventSource(stateID: .privateState) else {
            log.error("Failed to create private CGEventSource")
            return false
        }

        let modifierEvents = modifierKeyEvents(for: modifiers, source: source)

        for event in modifierEvents.down {
            event.post(tap: .cghidEventTap)
        }

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            log.error("Failed to create synthetic shortcut events", detail: "keyCode=\(keyCode)")
            for event in modifierEvents.up {
                event.post(tap: .cghidEventTap)
            }
            return false
        }

        keyDown.flags = modifiers
        keyUp.flags = modifiers
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        for event in modifierEvents.up {
            event.post(tap: .cghidEventTap)
        }

        return true
    }

    private func modifierKeyEvents(
        for modifiers: CGEventFlags,
        source: CGEventSource
    ) -> (down: [CGEvent], up: [CGEvent]) {
        let modifierKeyCodes: [(flag: CGEventFlags, keyCode: UInt16)] = [
            (.maskCommand, 55),
            (.maskShift, 56),
            (.maskAlternate, 58),
            (.maskControl, 59),
        ]

        let active = modifierKeyCodes.filter { modifiers.contains($0.flag) }
        let down = active.compactMap { item in
            let event = CGEvent(keyboardEventSource: source, virtualKey: item.keyCode, keyDown: true)
            event?.flags = modifiers
            return event
        }
        let up = active.reversed().compactMap { item in
            let event = CGEvent(keyboardEventSource: source, virtualKey: item.keyCode, keyDown: false)
            event?.flags = modifiers
            return event
        }

        return (down, up)
    }
}
