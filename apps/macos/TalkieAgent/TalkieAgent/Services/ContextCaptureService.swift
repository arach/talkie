//
//  ContextCaptureService.swift
//  TalkieAgent
//
//  Captures rich context about what the user is doing using Accessibility API.
//  No screen recording required - uses structured accessibility data.
//

import Foundation
import AppKit
import ApplicationServices
import TalkieKit

private let log = Log(.system)

// MARK: - Configuration

enum ContextCaptureDetail: String, CaseIterable, Codable {
    case off
    case metadataOnly
    case rich

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .metadataOnly: return "Apps & titles only"
        case .rich: return "Full context"
        }
    }

    var description: String {
        switch self {
        case .off: return "Do not capture context"
        case .metadataOnly: return "Capture app name and window title only"
        case .rich: return "Capture URLs and focused content when available"
        }
    }
}

/// Runtime options for a single capture request
struct ContextCaptureOptions {
    var enabled: Bool = true
    var detail: ContextCaptureDetail = .rich
    var includeFocusedValue: Bool = true
    var includeSelectedText: Bool = true
    var includeBrowserURLFallback: Bool = true
    var includeTerminalWorkingDir: Bool = true
    var logFailures: Bool = false
    var timeoutMs: Int = 250

    @MainActor static func fromSettings() -> ContextCaptureOptions {
        let settings = LiveSettings.shared
        // Session switch is the first gate
        guard settings.contextCaptureSessionAllowed else {
            return ContextCaptureOptions(enabled: false, detail: .off, includeFocusedValue: false, includeSelectedText: false, includeBrowserURLFallback: false, includeTerminalWorkingDir: false)
        }

        switch settings.contextCaptureDetail {
        case .off:
            return ContextCaptureOptions(enabled: false, detail: .off, includeFocusedValue: false, includeSelectedText: false, includeBrowserURLFallback: false, includeTerminalWorkingDir: false)
        case .metadataOnly:
            return ContextCaptureOptions(enabled: true, detail: .metadataOnly, includeFocusedValue: false, includeSelectedText: false, includeBrowserURLFallback: true, includeTerminalWorkingDir: false)
        case .rich:
            return ContextCaptureOptions(enabled: true, detail: .rich, includeFocusedValue: true, includeSelectedText: true, includeBrowserURLFallback: true, includeTerminalWorkingDir: true, logFailures: true, timeoutMs: 400)
        }
    }
}

/// Simple baseline metadata capture result
struct ContextCaptureResult {
    let metadata: DictationMetadata
}

/// Rich context snapshot captured at a moment in time
struct CapturedContext {
    // Basic app info
    var appBundleID: String?
    var appName: String?
    var windowTitle: String?

    // Document/URL context
    var documentURL: String?      // File path (Xcode, editors) or web URL (browsers)
    var browserURL: String?       // Full URL for browser tabs

    // Focused element context
    var focusedRole: String?      // AXTextArea, AXWebArea, AXTextField, etc.
    var focusedValue: String?     // Truncated content (code, terminal, form)
    var focusedDescription: String?

    // Terminal-specific
    var terminalWorkingDir: String?
    var isClaudeCodeSession: Bool = false

    /// Convert to metadata fields
    func applyTo(_ metadata: inout DictationMetadata) {
        metadata.activeAppBundleID = appBundleID
        metadata.activeAppName = appName
        metadata.activeWindowTitle = windowTitle
        metadata.documentURL = documentURL
        metadata.browserURL = browserURL
        metadata.focusedElementRole = focusedRole
        metadata.focusedElementValue = focusedValue
        metadata.terminalWorkingDir = terminalWorkingDir
    }
}

/// Service for capturing rich context using Accessibility API
final class ContextCaptureService {
    static let shared = ContextCaptureService()

    // Known browser bundle IDs
    private let browserBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.apple.Safari",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.brave.Browser",
        "com.operasoftware.Opera",
        "company.thebrowser.Browser",  // Arc
        "com.vivaldi.Vivaldi",
        "com.openai.chat" // ChatGPT desktop (Electron)
    ]

    // Known terminal bundle IDs
    private let terminalBundleIDs: Set<String> = [
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper",
        "com.github.wez.wezterm"
    ]

    // Known IDE bundle IDs
    private let ideBundleIDs: Set<String> = [
        "com.apple.dt.Xcode",
        "com.microsoft.VSCode",
        "com.jetbrains.intellij",
        "com.sublimetext.4",
        "com.panic.Nova",
        "md.obsidian"
    ]

    private init() {}

    // MARK: - Public API

    /// Capture baseline context synchronously (fast: ~1ms)
    /// Returns app name, bundle ID, and window title - no blocking AX calls
    @MainActor
    func captureBaseline() -> DictationMetadata {
        let options = ContextCaptureOptions.fromSettings()
        guard options.enabled else {
            return DictationMetadata()
        }
        return captureBaselineInternal()
    }

    /// Fast check for selected text (for auto-scratchpad feature)
    /// Returns true if the specified app (or frontmost app) has text currently selected
    /// This is a lightweight check (~10-50ms) that doesn't capture full context
    /// - Parameter targetApp: Optional app to check. If nil, checks frontmost app.
    @MainActor
    func hasSelectedText(in targetApp: NSRunningApplication? = nil) -> Bool {
        return getSelectedText(in: targetApp) != nil
    }

    /// Capture the currently selected text from the specified app (or frontmost app)
    /// Returns nil if no text is selected or accessibility is not available
    /// - Parameter targetApp: Optional app to check. If nil, checks frontmost app.
    ///
    /// Strategy (tiered within AX):
    /// 1. `kAXSelectedTextAttribute` on focused element
    /// 2. Range-based: `kAXSelectedTextRangeAttribute` + `kAXStringForRangeParameterizedAttribute`
    /// 3. Ancestor walk — same checks on parents (up to 3 hops)
    /// 4. Descendant walk — BFS children of focused element (bounded)
    ///
    /// Keeps AX-only work in this function. Clipboard + OCR live in separate tiers.
    @MainActor
    func getSelectedText(in targetApp: NSRunningApplication? = nil) -> String? {
        guard AXIsProcessTrusted() else {
            log.debug("getSelectedText: AX not trusted, returning nil")
            return nil
        }

        let app: NSRunningApplication
        if let targetApp = targetApp {
            app = targetApp
            log.debug("getSelectedText: Checking target app \(app.localizedName ?? "unknown")")
        } else if let frontApp = NSWorkspace.shared.frontmostApplication {
            app = frontApp
            log.debug("getSelectedText: Checking frontmost app \(app.localizedName ?? "unknown")")
        } else {
            log.debug("getSelectedText: No app to check")
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Get focused element
        var focusedRef: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)

        // Fallback: ask focused window for focused element
        if result != .success {
            var windowRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
               let window = windowRef {
                result = AXUIElementCopyAttributeValue(window as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)
            }
        }

        guard result == .success, let focusedRef else {
            log.debug("getSelectedText: No focused element in \(app.localizedName ?? "unknown")")
            return nil
        }

        let focused = focusedRef as! AXUIElement
        let appLabel = app.localizedName ?? "unknown"

        // Tier 1 + 2: direct reads on focused element
        if let text = readSelectedText(from: focused) {
            log.debug("getSelectedText: Found \(text.count) chars (focused) in \(appLabel)")
            return text
        }

        // Tier 3: ancestor walk (up to 3 parents)
        var current: AXUIElement = focused
        for hop in 1...3 {
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parentRef else { break }
            let parent = parentRef as! AXUIElement
            if let text = readSelectedText(from: parent) {
                log.debug("getSelectedText: Found \(text.count) chars (ancestor hop=\(hop)) in \(appLabel)")
                return text
            }
            current = parent
        }

        // Tier 4: descendant BFS from focused (bounded)
        if let text = bfsSelectedText(rootElement: focused, maxNodes: 24, maxDepth: 3) {
            log.debug("getSelectedText: Found \(text.count) chars (descendant BFS) in \(appLabel)")
            return text
        }

        log.debug("getSelectedText: No selection found in \(appLabel)")
        return nil
    }

    /// Try `kAXSelectedTextAttribute`, falling back to the range-based parameterized read.
    private func readSelectedText(from element: AXUIElement) -> String? {
        // Direct attribute
        var selectedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
           let selected = selectedRef as? String,
           !selected.isEmpty {
            return selected
        }

        // Range-based: some views expose the range even when SelectedText attr is nil/empty
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef else {
            return nil
        }

        var range = CFRange(location: 0, length: 0)
        // kAXValueCFRangeType is the expected AXValue subtype for text ranges
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range),
              range.length > 0 else {
            return nil
        }

        var stringRef: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &stringRef
        )
        guard status == .success, let text = stringRef as? String, !text.isEmpty else {
            return nil
        }
        return text
    }

    /// Breadth-first search children of `rootElement` looking for selected text.
    /// Bounded by `maxNodes` to protect against huge AX trees.
    private func bfsSelectedText(rootElement: AXUIElement, maxNodes: Int, maxDepth: Int) -> String? {
        var queue: [(AXUIElement, Int)] = [(rootElement, 0)]
        var visited = 0

        while !queue.isEmpty && visited < maxNodes {
            let (element, depth) = queue.removeFirst()
            visited += 1

            // Don't re-check the root — caller already did.
            if visited > 1, let text = readSelectedText(from: element) {
                return text
            }

            guard depth < maxDepth else { continue }

            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                for child in children {
                    queue.append((child, depth + 1))
                }
            }
        }
        return nil
    }

    /// Clipboard-based fallback for apps that don't expose selected text via AX.
    /// Simulates Cmd+C, reads the pasteboard, then restores the original clipboard contents.
    ///
    /// Now runs for any frontmost-external app by default — AX-only apps that already
    /// had text selected are unaffected (tier 1 returns first). Apps can be opted out
    /// via the `selectionClipboardFallbackBlocklist` setting (comma-separated bundle IDs).
    @MainActor
    func getSelectedTextViaClipboard(in targetApp: NSRunningApplication? = nil) -> String? {
        let app: NSRunningApplication
        if let targetApp {
            app = targetApp
        } else if let frontApp = NSWorkspace.shared.frontmostApplication {
            app = frontApp
        } else {
            return nil
        }

        let appName = app.localizedName ?? "unknown"
        let bundleID = app.bundleIdentifier ?? ""

        // Don't synth ⌘C into our own process.
        if bundleID == Bundle.main.bundleIdentifier {
            return nil
        }

        if isClipboardFallbackBlocked(bundleID: bundleID) {
            log.debug("getSelectedTextViaClipboard: skipped — \(bundleID) is blocklisted")
            return nil
        }

        log.debug("getSelectedTextViaClipboard: Trying clipboard fallback for \(appName)")

        if NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
            app.activate(options: [])
            usleep(75_000)
        }

        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        let previousContents = pasteboard.string(forType: .string)

        // Simulate Cmd+C
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true),  // 'c' key
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) else {
            return nil
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        // Brief wait for the copy to land on the pasteboard
        usleep(50_000) // 50ms

        // Check if pasteboard changed
        guard pasteboard.changeCount != previousChangeCount,
              let copiedText = pasteboard.string(forType: .string),
              !copiedText.isEmpty else {
            log.debug("getSelectedTextViaClipboard: No new clipboard content from \(appName)")
            // Restore regardless — if something else bumped the pasteboard between our checks
            // we still want the original contents back.
            if let previous = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
            return nil
        }

        log.debug("getSelectedTextViaClipboard: Got \(copiedText.count) chars from \(appName)")

        // Restore original clipboard
        pasteboard.clearContents()
        if let previous = previousContents {
            pasteboard.setString(previous, forType: .string)
        }

        return copiedText
    }

    /// User-configurable opt-out for the clipboard ⌘C simulation.
    /// Stored as a comma-separated bundle ID list in shared settings.
    @MainActor
    private func isClipboardFallbackBlocked(bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return false }
        guard let raw = TalkieSharedSettings.string(forKey: AgentSettingsKey.selectionClipboardFallbackBlocklist),
              !raw.isEmpty else {
            return false
        }
        let blocked = raw.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        return blocked.contains(bundleID)
    }

    /// Schedule background enrichment that updates the DB record after paste
    /// Fire-and-forget: runs in background and updates the record when complete
    func scheduleEnrichment(utteranceId: UUID, baseline: DictationMetadata, dictationText: String? = nil) {
        let options = ContextCaptureOptions(enabled: true, detail: .rich)
        guard options.detail == .rich else { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let enriched = await self.captureRichContext(options: options)
            let merged = baseline.mergingMissing(from: enriched)

            // Convert DictationMetadata to nested JSON format for UnifiedDatabase
            // Must match the format expected by Talkie's RecordingMetadata parser
            let metadataJSON = Self.buildNestedMetadataJSON(from: merged)

            // Update the database record with enriched metadata
            // Preserve existing keys (like refinement) that enrichment doesn't know about
            await MainActor.run {
                UnifiedDatabase.mergeMetadata(id: utteranceId, enrichedJSON: metadataJSON)
                log.debug("Enriched context for utterance \(utteranceId.uuidString.prefix(8))")

                // Update bridge session-context mapping (with dictation text for history)
                BridgeContextMapper.shared.updateAfterDictation(metadata: merged, dictationText: dictationText)

                // Record to fingerprint file for batch session matching
                if let text = dictationText,
                   let bundleId = merged.activeAppBundleID,
                   let windowTitle = merged.activeWindowTitle {
                    FingerprintStore.shared.recordDictation(
                        bundleId: bundleId,
                        windowTitle: windowTitle,
                        text: text
                    )
                }
            }
        }
    }

    // MARK: - Metadata JSON Conversion

    /// Convert DictationMetadata to nested JSON format expected by Talkie
    /// Structure: { app: {...}, performance: {...}, context: {...}, routing: {...} }
    static func buildNestedMetadataJSON(from metadata: DictationMetadata) -> String? {
        var dict: [String: Any] = [:]

        // App context
        var app: [String: Any] = [:]
        if let bundleId = metadata.activeAppBundleID { app["bundleId"] = bundleId }
        if let name = metadata.activeAppName { app["name"] = name }
        if let title = metadata.activeWindowTitle { app["windowTitle"] = title }
        if !app.isEmpty { dict["app"] = app }

        // End app context (if different from start)
        var endApp: [String: Any] = [:]
        if let bundleId = metadata.endAppBundleID { endApp["bundleId"] = bundleId }
        if let name = metadata.endAppName { endApp["name"] = name }
        if let title = metadata.endWindowTitle { endApp["windowTitle"] = title }
        if !endApp.isEmpty { dict["endApp"] = endApp }

        // Performance metrics
        var perf: [String: Any] = [:]
        if let ms = metadata.perfEngineMs { perf["engineMs"] = ms }
        if let ms = metadata.perfEndToEndMs { perf["endToEndMs"] = ms }
        if let ms = metadata.perfInAppMs { perf["inAppMs"] = ms }
        if let sid = metadata.sessionID { perf["sessionId"] = sid }
        if !perf.isEmpty { dict["performance"] = perf }

        // Rich context
        var context: [String: String] = [:]
        if let url = metadata.browserURL { context["browserURL"] = url }
        if let url = metadata.documentURL { context["documentURL"] = url }
        if let dir = metadata.terminalWorkingDir { context["terminalWorkingDir"] = dir }
        if !context.isEmpty { dict["context"] = context }

        // Routing info
        var routing: [String: Any] = [:]
        if let mode = metadata.routingMode { routing["mode"] = mode }
        routing["wasRouted"] = metadata.wasRouted
        if routing.count > 1 || metadata.routingMode != nil { dict["routing"] = routing }

        // Audio metrics
        var audio: [String: Any] = [:]
        if let peak = metadata.peakAmplitude { audio["peakAmplitude"] = peak }
        if let avg = metadata.averageAmplitude { audio["averageAmplitude"] = avg }
        if !audio.isEmpty { dict["audio"] = audio }

        guard !dict.isEmpty else { return nil }

        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return nil
    }

    // MARK: - Private Helpers

    private func captureBaselineInternal() -> DictationMetadata {
        var metadata = DictationMetadata()

        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            log.debug("No frontmost application")
            return metadata
        }

        metadata.activeAppBundleID = frontApp.bundleIdentifier
        metadata.activeAppName = frontApp.localizedName
        metadata.activeAppPID = frontApp.processIdentifier

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        if let (windowTitle, documentURL) = getFocusedWindowInfo(appElement) {
            metadata.activeWindowTitle = windowTitle
            metadata.documentURL = documentURL
        }

        return metadata
    }

    /// Capture richer AX context (runs asynchronously)
    private func captureRichContext(options: ContextCaptureOptions) async -> DictationMetadata {
        var metadata = DictationMetadata()

        if !AXIsProcessTrusted() {
            if options.logFailures {
                log.error("Accessibility permission missing - context capture limited")
            }
            return metadata
        }

        guard let frontApp = await MainActor.run(body: { NSWorkspace.shared.frontmostApplication }) else {
            return metadata
        }

        metadata.activeAppBundleID = frontApp.bundleIdentifier
        metadata.activeAppName = frontApp.localizedName
        metadata.activeAppPID = frontApp.processIdentifier

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        // Window info
        if let (windowTitle, documentURL) = getFocusedWindowInfo(appElement) {
            metadata.activeWindowTitle = windowTitle
            metadata.documentURL = documentURL
        }

        // Browser URL
        if let bundleID = frontApp.bundleIdentifier, browserBundleIDs.contains(bundleID) {
            metadata.browserURL = extractBrowserURL(appElement, allowFallback: options.includeBrowserURLFallback) ?? metadata.documentURL
        }

        // Focused element details
        if options.detail == .rich, let focusedInfo = getFocusedElementInfo(appElement, allowValue: options.includeFocusedValue, allowSelectedText: options.includeSelectedText, bundleID: frontApp.bundleIdentifier) {
            metadata.focusedElementRole = focusedInfo.role
            metadata.focusedElementValue = focusedInfo.value
        }

        // Terminal enrichment
        if options.includeTerminalWorkingDir,
           let bundleID = frontApp.bundleIdentifier,
           terminalBundleIDs.contains(bundleID),
           let title = metadata.activeWindowTitle {
            metadata.terminalWorkingDir = extractWorkingDirectory(from: title)
        }

        log.debug("Enriched context: \(metadata.activeAppName ?? "?") - \(metadata.activeWindowTitle ?? "no title")")
        return metadata
    }

    private func getFocusedWindowInfo(_ appElement: AXUIElement) -> (title: String?, documentURL: String?)? {
        var windowRef: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)

        // Fallback: first window in kAXWindows if no focused window (common for some Electron apps)
        if result != .success {
            var windowsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let windows = windowsRef as? [AXUIElement],
               let first = windows.first {
                windowRef = first
                result = .success
                log.debug("Focused window missing; used first window as fallback")
            }
        }

        guard result == .success, let windowRef else { return nil }
        let window = windowRef as! AXUIElement

        // Get title
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        let title = titleRef as? String

        // Get document URL (file path or web URL)
        var docRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &docRef)
        let documentURL = docRef as? String

        return (title, documentURL)
    }

    private func getFocusedElementInfo(_ appElement: AXUIElement, allowValue: Bool, allowSelectedText: Bool, bundleID: String?) -> (role: String?, description: String?, value: String?)? {
        var focusedRef: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)

        // Fallback: ask focused window for focused element if app-wide attribute fails
        if result != .success {
            var windowRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
               let window = windowRef {
                result = AXUIElementCopyAttributeValue(window as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)
            }
        }

        guard result == .success, let focusedRef else {
            return nil
        }

        let focused = focusedRef as! AXUIElement

        // Role
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String

        // Description
        var descRef: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, kAXDescriptionAttribute as CFString, &descRef)
        let description = descRef as? String

        var chosenValue: String?

        // Selected text is the highest-signal, lowest-noise field
        if allowSelectedText {
            var selectedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
               let selected = selectedRef as? String,
               !selected.isEmpty {
                chosenValue = selected
            }
        }

        // Value (text content)
        if chosenValue == nil, allowValue {
            var valueRef: CFTypeRef?
            AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &valueRef)
            if let value = valueRef as? String {
                chosenValue = truncateValue(value, forApp: bundleID)
            }
        }

        return (role, description, chosenValue)
    }

    private func extractBrowserURL(_ appElement: AXUIElement, allowFallback: Bool) -> String? {
        // For browsers, the URL is often in the focused window's document attribute
        // or in a text field (URL bar)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success else {
            return nil
        }

        let window = windowRef as! AXUIElement

        // Try document attribute first
        var docRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &docRef) == .success {
            if let url = docRef as? String, url.hasPrefix("http") {
                return url
            }
        }

        if !allowFallback {
            return nil
        }

        // Fallback: try URL attribute on the window (Safari exposes this)
        var urlRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXURLAttribute as CFString, &urlRef) == .success,
           let url = urlRef as? String,
           url.hasPrefix("http") {
            return url
        }

        // Could also traverse to find the URL bar, but document usually works
        return nil
    }

    private func extractWorkingDirectory(from windowTitle: String) -> String? {
        // Common patterns in terminal window titles:
        // "user@host:~/dev/project"
        // "~/dev/project"
        // "zsh - ~/dev/project"

        // Look for path-like patterns
        if let colonIndex = windowTitle.lastIndex(of: ":") {
            let afterColon = String(windowTitle[windowTitle.index(after: colonIndex)...])
            let trimmed = afterColon.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("~") || trimmed.hasPrefix("/") {
                return trimmed
            }
        }

        // Look for ~ or / patterns
        let components = windowTitle.components(separatedBy: " ")
        for component in components.reversed() {
            if component.hasPrefix("~") || component.hasPrefix("/") {
                return component
            }
        }

        return nil
    }

    private func truncateValue(_ value: String, forApp bundleID: String?) -> String {
        // Different truncation strategies based on app type
        let maxLength: Int

        if let bundleID = bundleID {
            if terminalBundleIDs.contains(bundleID) {
                // For terminals, capture last ~500 chars (recent output)
                maxLength = 500
                let lines = value.components(separatedBy: "\n")
                let recentLines = lines.suffix(20)
                return recentLines.joined(separator: "\n").suffix(maxLength).description
            } else if ideBundleIDs.contains(bundleID) {
                // For IDEs, capture ~300 chars around cursor
                maxLength = 300
            } else {
                // Default
                maxLength = 200
            }
        } else {
            maxLength = 200
        }

        if value.count <= maxLength {
            return value
        }

        return String(value.prefix(maxLength)) + "..."
    }
}

// MARK: - Integration with existing ContextCapture

extension ContextCapture {
    /// Capture baseline context using the new ContextCaptureService
    @MainActor static func captureRichContext() -> DictationMetadata {
        ContextCaptureService.shared.captureBaseline()
    }
}
