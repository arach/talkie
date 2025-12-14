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
    func applyTo(_ metadata: inout UtteranceMetadata) {
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
        "com.vivaldi.Vivaldi"
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

    /// Capture rich context for the current frontmost app
    func captureCurrentContext() -> CapturedContext {
        var context = CapturedContext()

        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            logger.debug("No frontmost application")
            return context
        }

        context.appBundleID = frontApp.bundleIdentifier
        context.appName = frontApp.localizedName

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        // Get focused window
        if let (windowTitle, documentURL) = getFocusedWindowInfo(appElement) {
            context.windowTitle = windowTitle
            context.documentURL = documentURL
        }

        // Get focused element details
        if let focusedInfo = getFocusedElementInfo(appElement) {
            context.focusedRole = focusedInfo.role
            context.focusedDescription = focusedInfo.description

            // Capture value with app-specific truncation
            if let value = focusedInfo.value {
                context.focusedValue = truncateValue(value, forApp: frontApp.bundleIdentifier)
            }
        }

        // App-specific enrichment
        if let bundleID = frontApp.bundleIdentifier {
            // Browser: extract URL
            if browserBundleIDs.contains(bundleID) {
                context.browserURL = extractBrowserURL(appElement) ?? context.documentURL
            }

            // Terminal: extract working directory and detect Claude Code
            if terminalBundleIDs.contains(bundleID) {
                if let windowTitle = context.windowTitle {
                    context.terminalWorkingDir = extractWorkingDirectory(from: windowTitle)
                    context.isClaudeCodeSession = windowTitle.hasPrefix("✳")
                }
            }
        }

        logger.debug("Captured context: \(context.appName ?? "?") - \(context.windowTitle ?? "no title")")
        return context
    }

    // MARK: - Private Helpers

    private func getFocusedWindowInfo(_ appElement: AXUIElement) -> (title: String?, documentURL: String?)? {
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success else {
            return nil
        }

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

    private func getFocusedElementInfo(_ appElement: AXUIElement) -> (role: String?, description: String?, value: String?)? {
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success else {
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

        // Value (text content)
        var valueRef: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &valueRef)
        let value = valueRef as? String

        return (role, description, value)
    }

    private func extractBrowserURL(_ appElement: AXUIElement) -> String? {
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
    /// Capture rich context using the new ContextCaptureService
    static func captureRichContext() -> UtteranceMetadata {
        var metadata = UtteranceMetadata()
        let context = ContextCaptureService.shared.captureCurrentContext()
        context.applyTo(&metadata)
        return metadata
    }
}
