//
//  TextInserter.swift
//  TalkieLive
//
//  Robust text insertion service.
//  Primary: Direct Accessibility API insertion (no clipboard pollution)
//  Fallback: Clipboard + simulated Cmd+V paste
//
//  History:
//  - Pre-2025: Used simulatePaste() with fixed timing delays (see legacySimulatePaste below)
//  - 2025-12: Added direct AX insertion with notification-based timing fallback
//

import AppKit
import ApplicationServices
import TalkieKit

private let log = Log(.system)

/// Result of attempting AX insertion
private enum AXInsertionResult {
    case success           // Text was inserted via AX
    case notSupported      // AX not available (element not editable, etc.)
    case claimedButFailed  // AX claimed success but verification failed
}

/// Centralized text insertion service for TalkieLive
@MainActor
final class TextInserter {
    static let shared = TextInserter()

    // MARK: - Constants

    /// Number of AX failures required before disabling AX for an app
    private static let axFailureThreshold = 3

    /// Apps where AX insertion works - skip verification
    private var axEnabledApps: Set<String> = []

    /// Apps where AX insertion doesn't work - use clipboard paste
    private var axDisabledApps: Set<String> = []

    /// Failure counts for apps (not persisted - resets on restart)
    private var axFailureCounts: [String: Int] = [:]

    private init() {
        // Load persisted lists from UserDefaults
        if let enabled = UserDefaults.standard.stringArray(forKey: "TextInserter.axEnabledApps") {
            axEnabledApps = Set(enabled)
        }
        if let disabled = UserDefaults.standard.stringArray(forKey: "TextInserter.axDisabledApps") {
            axDisabledApps = Set(disabled)
        }
        if !axEnabledApps.isEmpty || !axDisabledApps.isEmpty {
            log.debug("Loaded AX state: \(axEnabledApps.count) enabled, \(axDisabledApps.count) disabled")
        }
    }

    private func markAsAXEnabled(_ bundleID: String) {
        axEnabledApps.insert(bundleID)
        UserDefaults.standard.set(Array(axEnabledApps), forKey: "TextInserter.axEnabledApps")
        log.info("✅ \(bundleID) AX verified (persisted)")
    }

    /// Record an AX failure for an app. Returns true if threshold reached and app is now disabled.
    private func recordAXFailure(_ bundleID: String) -> Bool {
        let count = (axFailureCounts[bundleID] ?? 0) + 1
        axFailureCounts[bundleID] = count

        if count >= Self.axFailureThreshold {
            axDisabledApps.insert(bundleID)
            UserDefaults.standard.set(Array(axDisabledApps), forKey: "TextInserter.axDisabledApps")
            log.info("📋 \(bundleID) AX disabled after \(count) failures (persisted)")
            return true
        } else {
            log.info("⚠️ \(bundleID) AX failure \(count)/\(Self.axFailureThreshold)")
            return false
        }
    }

    // MARK: - Public API

    /// Insert text into the target application
    /// - Parameters:
    ///   - text: The text to insert
    ///   - bundleID: Target app bundle ID (nil = frontmost app)
    ///   - replaceSelection: If true, replaces current selection; if false, inserts at cursor
    /// - Returns: True if insertion succeeded
    func insert(_ text: String, intoAppWithBundleID bundleID: String?, replaceSelection: Bool = true) async -> Bool {
        guard AXIsProcessTrusted() else {
            log.error("Accessibility permission not granted - cannot insert text")
            return false
        }

        // Find target app
        let targetApp: NSRunningApplication?
        if let bundleID {
            targetApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        } else {
            targetApp = NSWorkspace.shared.frontmostApplication
        }

        guard let app = targetApp else {
            log.warning("Target app not found: \(bundleID ?? "frontmost")")
            return false
        }

        log.info("🎯 Target app: \(app.localizedName ?? "?") (\(app.bundleIdentifier ?? "?"))")

        // Activate the app first if it's not frontmost
        if app != NSWorkspace.shared.frontmostApplication {
            app.activate(options: [.activateIgnoringOtherApps])
            // Wait for activation
            if await waitForAppActivation(bundleID: app.bundleIdentifier) == false {
                log.warning("App activation timed out, proceeding anyway")
            }
        }

        let bundleID = app.bundleIdentifier ?? ""

        // Skip AX for apps we've learned don't support it
        if axDisabledApps.contains(bundleID) {
            log.debug("📋 Using clipboard paste for \(app.localizedName ?? bundleID) (AX disabled)")
            return await clipboardPaste(text)
        }

        // Use AX without verification for apps we've verified
        if axEnabledApps.contains(bundleID) {
            let axResult = tryDirectAXInsertion(text, app: app, replaceSelection: replaceSelection, verify: false)
            if axResult == .success {
                log.debug("✅ AX insertion (\(text.count) chars)")
                return true
            }
            // Shouldn't happen for verified apps, but fall back just in case
            return await clipboardPaste(text)
        }

        // Unknown app - try AX with verification to learn
        let axResult = tryDirectAXInsertion(text, app: app, replaceSelection: replaceSelection, verify: true)

        switch axResult {
        case .success:
            // Verified working - remember for next time
            if !bundleID.isEmpty {
                markAsAXEnabled(bundleID)
            }
            log.info("✅ Direct AX insertion succeeded (\(text.count) chars)")
            return true

        case .claimedButFailed:
            // App claimed success but verification failed - track failures
            if !bundleID.isEmpty {
                _ = recordAXFailure(bundleID)
            }
            return await clipboardPaste(text)

        case .notSupported:
            // AX not available (not editable, etc.) - just fall back, don't count as failure
            log.info("📋 AX not available, using clipboard paste")
            return await clipboardPaste(text)
        }
    }

    // MARK: - Direct AX Insertion

    private func tryDirectAXInsertion(_ text: String, app: NSRunningApplication, replaceSelection: Bool, verify: Bool) -> AXInsertionResult {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Get focused UI element
        var focusedRef: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)

        // Some apps need us to look at the focused window first
        if result != .success {
            var windowRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
               let window = windowRef {
                result = AXUIElementCopyAttributeValue(window as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)
            }
        }

        guard result == .success, let focusedElement = focusedRef else {
            log.debug("Could not get focused element for AX insertion")
            return .notSupported
        }

        let focused = focusedElement as! AXUIElement

        // Log element role for debugging
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &roleRef)
        let role = (roleRef as? String) ?? "unknown"
        log.info("📍 Focused element role: \(role)")

        // Check if element is editable (has kAXValueAttribute and is writable)
        var settableRef: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(focused, kAXValueAttribute as CFString, &settableRef) == .success,
              settableRef.boolValue else {
            log.debug("Focused element is not editable via AX")
            return .notSupported
        }

        // Get current value and selection range
        var valueRef: CFTypeRef?
        var rangeRef: CFTypeRef?

        AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &valueRef)
        AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef)

        let currentValue = (valueRef as? String) ?? ""

        if replaceSelection, let range = rangeRef {
            // Replace selected text
            var cfRange = CFRange()
            if AXValueGetValue(range as! AXValue, .cfRange, &cfRange) {
                let nsRange = NSRange(location: cfRange.location, length: cfRange.length)
                if let swiftRange = Range(nsRange, in: currentValue) {
                    var newValue = currentValue
                    newValue.replaceSubrange(swiftRange, with: text)

                    let setResult = AXUIElementSetAttributeValue(focused, kAXValueAttribute as CFString, newValue as CFTypeRef)
                    if setResult == .success {
                        // Verify it actually worked (if requested)
                        if verify && !verifyInsertion(focused, contains: text) {
                            log.info("⚠️ AX reported success but text not found")
                            return .claimedButFailed
                        }

                        // Move cursor to end of inserted text
                        let newCursorPos = nsRange.location + text.count
                        var newRange = CFRangeMake(newCursorPos, 0)
                        if let rangeValue = AXValueCreate(.cfRange, &newRange) {
                            AXUIElementSetAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, rangeValue)
                        }
                        return .success
                    }
                }
            }
        }

        // Simple value replacement (insert at end or replace all)
        let setResult = AXUIElementSetAttributeValue(focused, kAXValueAttribute as CFString, text as CFTypeRef)
        if setResult == .success {
            // Verify it actually worked (if requested)
            if verify && !verifyInsertion(focused, contains: text) {
                log.info("⚠️ AX reported success but text not found")
                return .claimedButFailed
            }
            return .success
        }
        return .notSupported
    }

    /// Verify that the text was actually inserted by reading it back
    private func verifyInsertion(_ element: AXUIElement, contains text: String) -> Bool {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let currentValue = valueRef as? String else {
            return false
        }
        return currentValue.contains(text)
    }

    // MARK: - Clipboard Fallback

    private func clipboardPaste(_ text: String) async -> Bool {
        // Copy to clipboard
        let pb = NSPasteboard.general
        pb.prepareForNewContents()
        guard pb.setString(text, forType: .string) else {
            log.error("Failed to copy text to clipboard")
            return false
        }

        // Small delay to ensure clipboard is ready
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms

        // Simulate Cmd+V
        return simulatePaste()
    }

    private func simulatePaste() -> Bool {
        guard let src = CGEventSource(stateID: .combinedSessionState) else {
            log.error("Failed to create CGEventSource")
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

        log.info("Clipboard paste: \(eventsPosted)/4 events posted")
        return eventsPosted == 4
    }

    // MARK: - App Activation

    private func waitForAppActivation(bundleID: String?, timeout: TimeInterval = 1.0) async -> Bool {
        guard let bundleID else { return true }

        return await withCheckedContinuation { continuation in
            var observer: NSObjectProtocol?
            var didResume = false

            // Set up timeout
            let timeoutTask = DispatchWorkItem {
                if !didResume {
                    didResume = true
                    if let obs = observer {
                        NotificationCenter.default.removeObserver(obs)
                    }
                    continuation.resume(returning: false)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutTask)

            // Listen for activation
            observer = NotificationCenter.default.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == bundleID else { return }

                if !didResume {
                    didResume = true
                    timeoutTask.cancel()
                    if let obs = observer {
                        NotificationCenter.default.removeObserver(obs)
                    }
                    continuation.resume(returning: true)
                }
            }

            // Check if already active
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID {
                if !didResume {
                    didResume = true
                    timeoutTask.cancel()
                    if let obs = observer {
                        NotificationCenter.default.removeObserver(obs)
                    }
                    continuation.resume(returning: true)
                }
            }
        }
    }
}
