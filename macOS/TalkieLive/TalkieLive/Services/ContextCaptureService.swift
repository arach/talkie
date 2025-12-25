//
//  ContextCaptureService.swift
//  TalkieLive
//
//  Captures rich context about what the user is doing using Accessibility API.
//  No screen recording required - uses structured accessibility data.
//

import Foundation
import AppKit
import ApplicationServices
import os.log

private let logger = Logger(subsystem: "jdi.talkie.live", category: "ContextCapture")

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

    /// Schedule background enrichment that updates the DB record after paste
    /// Fire-and-forget: runs in background and updates the record when complete
    func scheduleEnrichment(utteranceId: Int64, baseline: DictationMetadata) {
        let options = ContextCaptureOptions(enabled: true, detail: .rich)
        guard options.detail == .rich else { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let enriched = await self.captureRichContext(options: options)
            let merged = baseline.mergingMissing(from: enriched)

            // Update the database record with enriched metadata
            await MainActor.run {
                LiveDatabase.updateMetadata(id: utteranceId, metadata: merged)
                logger.debug("Enriched context for utterance \(utteranceId)")
            }
        }
    }

    // MARK: - Private Helpers

    private func captureBaselineInternal() -> DictationMetadata {
        var metadata = DictationMetadata()

        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            logger.debug("No frontmost application")
            return metadata
        }

        metadata.activeAppBundleID = frontApp.bundleIdentifier
        metadata.activeAppName = frontApp.localizedName

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
                logger.error("Accessibility permission missing - context capture limited")
            }
            return metadata
        }

        guard let frontApp = await MainActor.run(body: { NSWorkspace.shared.frontmostApplication }) else {
            return metadata
        }

        metadata.activeAppBundleID = frontApp.bundleIdentifier
        metadata.activeAppName = frontApp.localizedName

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

        logger.debug("Enriched context: \(metadata.activeAppName ?? "?") - \(metadata.activeWindowTitle ?? "no title")")
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
                logger.debug("Focused window missing; used first window as fallback")
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
