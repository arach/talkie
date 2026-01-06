//
//  TextInserter.swift
//  TalkieLive
//
//  Robust text insertion service.
//  Primary: Terminal-specific strategies (AppleScript for iTerm2/Terminal.app)
//  Secondary: Direct Accessibility API insertion (no clipboard pollution)
//  Fallback: Clipboard + simulated Cmd+V paste with click-to-focus
//
//  History:
//  - Pre-2025: Used simulatePaste() with fixed timing delays (see legacySimulatePaste below)
//  - 2025-12: Added direct AX insertion with notification-based timing fallback
//  - 2026-01: Added click-to-focus and terminal-specific AppleScript strategies
//

import AppKit
import ApplicationServices
import TalkieKit

private let log = Log(.system)

/// Terminal insertion strategy
private enum TerminalStrategy {
    case iTerm2Script       // Use AppleScript `write text`
    case terminalAppScript  // Use AppleScript `do script`
    case clipboardPaste     // Universal fallback with click-to-focus
}

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

    /// Known terminal bundle IDs for strategy selection
    private static let terminalBundleIDs: Set<String> = [
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper",
        "com.github.wez.wezterm"
    ]

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

    // MARK: - Terminal Strategy Selection

    /// Determine the best insertion strategy for a given app
    private func terminalStrategy(for bundleID: String) -> TerminalStrategy {
        switch bundleID {
        case "com.googlecode.iterm2":
            return .iTerm2Script
        case "com.apple.Terminal":
            return .terminalAppScript
        default:
            return .clipboardPaste
        }
    }

    /// Check if bundle ID is a known terminal
    private func isTerminal(_ bundleID: String) -> Bool {
        Self.terminalBundleIDs.contains(bundleID)
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

        let bundleID = app.bundleIdentifier ?? ""

        // For known terminals, use terminal-specific strategies first
        if isTerminal(bundleID) {
            let strategy = terminalStrategy(for: bundleID)
            log.info("📺 Terminal detected, strategy: \(strategy)")

            switch strategy {
            case .iTerm2Script:
                if let result = await insertViaiTerm2(text) {
                    log.info("✅ iTerm2 AppleScript insertion succeeded")
                    return result
                }
                log.warning("⚠️ iTerm2 AppleScript failed, falling back to clipboard")
                return await clipboardPasteWithFocus(text, app: app)

            case .terminalAppScript:
                if let result = await insertViaTerminalApp(text) {
                    log.info("✅ Terminal.app AppleScript insertion succeeded")
                    return result
                }
                log.warning("⚠️ Terminal.app AppleScript failed, falling back to clipboard")
                return await clipboardPasteWithFocus(text, app: app)

            case .clipboardPaste:
                // For Ghostty, Warp, etc. - clipboard paste with click-to-focus
                return await clipboardPasteWithFocus(text, app: app)
            }
        }

        // Non-terminal apps: use existing AX + clipboard logic

        // Activate the app first if it's not frontmost
        if app != NSWorkspace.shared.frontmostApplication {
            app.activate(options: [.activateIgnoringOtherApps])
            // Wait for activation
            if await waitForAppActivation(bundleID: app.bundleIdentifier) == false {
                log.warning("App activation timed out, proceeding anyway")
            }
        }

        // Skip AX for apps we've learned don't support it
        if axDisabledApps.contains(bundleID) {
            log.debug("📋 Using clipboard paste for \(app.localizedName ?? bundleID) (AX disabled)")
            return await clipboardPaste(text)
        }

        // Use AX without verification for apps we've verified
        if axEnabledApps.contains(bundleID) {
            log.info("🎯 AX insert (verified app): \(app.localizedName ?? bundleID), text: \(text.prefix(30))...")
            let axResult = tryDirectAXInsertion(text, app: app, replaceSelection: replaceSelection, verify: false)
            if axResult == .success {
                log.info("✅ AX insertion succeeded (\(text.count) chars)")
                return true
            }
            // Shouldn't happen for verified apps, but fall back just in case
            log.warning("⚠️ AX failed for verified app, falling back to clipboard")
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
            log.debug("Direct focused element failed (\(result.rawValue)), trying via focused window...")
            var windowRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
               let window = windowRef {
                result = AXUIElementCopyAttributeValue(window as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)
            }
        }

        guard result == .success, let focusedElement = focusedRef else {
            log.warning("❌ Could not get focused element for AX insertion (result: \(result.rawValue))")
            return .notSupported
        }

        let focused = focusedElement as! AXUIElement

        // Log element role for debugging
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &roleRef)
        let role = (roleRef as? String) ?? "unknown"
        log.info("📍 Focused element: role=\(role), app=\(app.localizedName ?? "?"), pid=\(app.processIdentifier)")

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

    // MARK: - Terminal-Specific Insertion

    /// Insert text using iTerm2 AppleScript
    /// Returns nil if AppleScript fails, true/false based on success
    /// - Parameter withNewline: If true, sends Enter after text (for submit)
    private func insertViaiTerm2(_ text: String, withNewline: Bool = false) async -> Bool? {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                         .replacingOccurrences(of: "\"", with: "\\\"")

        let newlineOption = withNewline ? "YES" : "NO"
        let script = """
        tell application "iTerm2"
            tell current session of current window
                write text "\(escaped)" newline \(newlineOption)
            end tell
        end tell
        """

        return executeAppleScript(script)
    }

    /// Insert text using Terminal.app AppleScript
    /// Returns nil if AppleScript fails, true/false based on success
    private func insertViaTerminalApp(_ text: String) async -> Bool? {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                         .replacingOccurrences(of: "\"", with: "\\\"")

        // Note: Terminal.app's "do script" executes the text, we need a different approach
        // Use keystroke instead for just inserting text
        let script = """
        tell application "Terminal"
            activate
        end tell
        tell application "System Events"
            tell process "Terminal"
                set frontmost to true
                keystroke "\(escaped)"
            end tell
        end tell
        """

        return executeAppleScript(script)
    }

    /// Insert text AND press return using Terminal.app AppleScript (background-safe)
    private func insertViaTerminalAppWithReturn(_ text: String) async -> Bool? {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                         .replacingOccurrences(of: "\"", with: "\\\"")

        // Use System Events keystroke with return key - works without stealing focus
        let script = """
        tell application "System Events"
            tell process "Terminal"
                keystroke "\(escaped)"
                key code 36
            end tell
        end tell
        """

        return executeAppleScript(script)
    }

    /// Execute AppleScript and return result
    private func executeAppleScript(_ source: String) -> Bool? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            log.error("Failed to create AppleScript")
            return nil
        }

        script.executeAndReturnError(&error)

        if let error = error {
            log.error("AppleScript error: \(error)")
            return nil
        }

        return true
    }

    // MARK: - Enhanced Clipboard Paste with Click-to-Focus

    /// Clipboard paste with click-to-focus for terminals like Ghostty
    /// This ensures the input cursor is active before pasting
    private func clipboardPasteWithFocus(_ text: String, app: NSRunningApplication) async -> Bool {
        let bundleID = app.bundleIdentifier ?? ""
        log.info("📋 Clipboard paste with focus: \(app.localizedName ?? bundleID)")

        // 1. Activate the app
        app.activate(options: [.activateIgnoringOtherApps])

        // 2. Wait for activation with verification
        var activated = false
        for _ in 0..<20 {  // 1 second total
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID {
                activated = true
                break
            }
        }

        if !activated {
            log.warning("App activation timeout, proceeding anyway")
        }

        // 3. Click to ensure input focus (key improvement for terminals!)
        await clickTerminalInputArea(app)

        // 4. Set clipboard
        let pb = NSPasteboard.general
        pb.clearContents()
        guard pb.setString(text, forType: .string) else {
            log.error("Failed to copy text to clipboard")
            return false
        }

        // 5. Wait for clipboard to be ready
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms

        // 6. Paste
        let pasteResult = simulatePaste()

        log.info("📋 Clipboard paste with focus completed: \(pasteResult)")
        return pasteResult
    }

    /// Click in the terminal's input area to ensure keyboard focus
    /// This is crucial for terminals like Ghostty that don't respond well to AX focus
    private func clickTerminalInputArea(_ app: NSRunningApplication) async {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Get windows
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              let mainWindow = windows.first else {
            log.debug("Could not get windows for click-to-focus")
            return
        }

        // Get window position and size
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(mainWindow, kAXPositionAttribute as CFString, &positionRef)
        AXUIElementCopyAttributeValue(mainWindow, kAXSizeAttribute as CFString, &sizeRef)

        guard let positionValue = positionRef, let sizeValue = sizeRef else {
            log.debug("Could not get window bounds for click-to-focus")
            return
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

        // Click near bottom-center where terminal input typically is
        // Claude Code's input is at the very bottom of the terminal
        let clickPoint = CGPoint(
            x: position.x + size.width / 2,
            y: position.y + size.height - 40  // 40px from bottom
        )

        log.info("🖱️ Click-to-focus at (\(Int(clickPoint.x)), \(Int(clickPoint.y)))")

        // Simulate click
        guard let clickDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: clickPoint, mouseButton: .left),
              let clickUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: clickPoint, mouseButton: .left) else {
            log.error("Failed to create click events")
            return
        }

        clickDown.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms between down/up
        clickUp.post(tap: .cghidEventTap)

        // Wait for click to register
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
    }

    // MARK: - Key Press Simulation

    /// Simulate pressing the Enter/Return key
    func simulateEnter() -> Bool {
        guard let src = CGEventSource(stateID: .combinedSessionState) else {
            log.error("Failed to create CGEventSource for Enter")
            return false
        }

        // Return key is keycode 0x24 (36)
        let returnKey: UInt16 = 0x24

        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: returnKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: src, virtualKey: returnKey, keyDown: false) else {
            log.error("Failed to create Enter key events")
            return false
        }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        log.info("⏎ Enter key simulated")
        return true
    }

    /// Insert text and then press Enter to submit
    func insertAndSubmit(_ text: String, intoAppWithBundleID bundleID: String?) async -> Bool {
        // For iTerm2, use AppleScript with newline - works in background without focus
        if bundleID == "com.googlecode.iterm2" {
            if let result = await insertViaiTerm2(text, withNewline: true) {
                log.info("✅ iTerm2 insert+submit via AppleScript (background-safe)")
                return result
            }
            log.warning("⚠️ iTerm2 AppleScript failed, falling back to focus+Enter")
        }

        // For Terminal.app, use AppleScript with keystroke + return
        if bundleID == "com.apple.Terminal" {
            if let result = await insertViaTerminalAppWithReturn(text) {
                log.info("✅ Terminal.app insert+submit via AppleScript (background-safe)")
                return result
            }
            log.warning("⚠️ Terminal.app AppleScript failed, falling back to focus+Enter")
        }

        // For other apps: insert text first
        let inserted = await insert(text, intoAppWithBundleID: bundleID)
        guard inserted else {
            log.error("Failed to insert text, skipping Enter")
            return false
        }

        // Small delay to ensure text is fully inserted
        try? await Task.sleep(nanoseconds: 150_000_000)  // 150ms

        // Remember current frontmost app to restore later
        let previousApp = NSWorkspace.shared.frontmostApplication

        // Activate the target app before pressing Enter (CGEvent requires focus)
        if let bundleID {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                app.activate(options: [.activateIgnoringOtherApps])
                // Wait for activation to complete
                try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            }
        }

        // Press Enter to submit
        let result = simulateEnter()

        // Restore previous app focus (minimal disruption)
        if let previousApp, previousApp.bundleIdentifier != bundleID {
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
            previousApp.activate(options: [])
            log.info("↩️ Restored focus to \(previousApp.localizedName ?? "previous app")")
        }

        return result
    }

    /// Activate an app and press Enter key
    /// Used for "force Enter" when the auto-submit didn't work
    func simulateEnterInApp(bundleId: String) async -> Bool {
        // Find and activate the app
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            log.error("App not running: \(bundleId)")
            return false
        }

        // Remember current frontmost app to restore later
        let previousApp = NSWorkspace.shared.frontmostApplication

        // Activate the app
        let activated = app.activate(options: [.activateIgnoringOtherApps])
        if !activated {
            log.warning("Could not activate \(bundleId), proceeding anyway")
        }

        // Wait for app to be frontmost
        try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms

        // Press Enter
        let result = simulateEnter()

        // Restore previous app focus (minimal disruption)
        if let previousApp, previousApp.bundleIdentifier != bundleId {
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
            previousApp.activate(options: [])
            log.info("↩️ Restored focus to \(previousApp.localizedName ?? "previous app")")
        }

        return result
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
