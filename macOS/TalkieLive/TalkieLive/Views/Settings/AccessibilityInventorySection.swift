//
//  AccessibilityInventorySection.swift
//  TalkieLive
//
//  Deep sonar scan of accessibility data - shows everything we can capture.
//  Useful for debugging and understanding what context is available.
//

import SwiftUI
import AppKit
import ApplicationServices
import TalkieKit

private let log = Log(.system)

// MARK: - Data Models

struct AccessibilityApp: Identifiable {
    let id: pid_t
    let name: String
    let bundleId: String?
    let isFrontmost: Bool
    let windows: [AccessibilityWindow]
    let menuBar: [AccessibilityMenuItem]
    let icon: NSImage?
}

struct AccessibilityMenuItem: Identifiable {
    let id = UUID()
    let title: String
    let children: [AccessibilityMenuItem]
    let enabled: Bool
    let shortcut: String?
}

struct AccessibilityWindow: Identifiable {
    var id: String { "\(pid)-\(index)" }
    let pid: pid_t
    let index: Int
    let title: String
    let role: String?
    let subrole: String?
    let isMain: Bool
    let isFocused: Bool
    let isMinimized: Bool
    let isFullScreen: Bool
    let documentURL: String?
    let url: String?  // For browsers
    let position: CGPoint?
    let size: CGSize?
    let toolbar: [String]
    let focusedElement: AccessibilityElement?
    let allAttributes: [String]  // Raw list of available attributes

    // Terminal-specific deep content
    let terminalContent: TerminalContent?
}

/// Deep-extracted content from terminal windows
struct TerminalContent {
    let visibleText: String?          // Terminal buffer (truncated)
    let lastLines: [String]           // Last N lines (for prompt detection)
    let detectedPrompt: String?       // e.g., "arach@mbp ~/dev/talkie $"
    let detectedCwd: String?          // Extracted working directory
    let detectedCommand: String?      // Last command if visible
    let tabs: [TerminalTab]           // All tabs in this terminal window
}

struct TerminalTab: Identifiable {
    let id = UUID()
    let title: String
    let isSelected: Bool
}

struct AccessibilityElement: Identifiable {
    let id = UUID()
    let role: String
    let subrole: String?
    let roleDescription: String?
    let description: String?
    let value: String?
    let selectedText: String?
    let selectedTextRange: String?
    let title: String?
    let label: String?
    let help: String?
    let placeholder: String?
    let url: String?
    let linkURL: String?
    let numberOfCharacters: Int?
    let insertionPointLineNumber: Int?
    let visibleCharacterRange: String?
    let children: Int
    let actions: [String]
    let allAttributes: [String]
    let parentChain: [String]  // Role hierarchy up to window
}

struct AccessibilityScan {
    let timestamp: Date
    let durationMs: Int
    let isAccessibilityTrusted: Bool
    let apps: [AccessibilityApp]
    let totalWindows: Int
    let totalAttributes: Int
}

// MARK: - Scanner

final class AccessibilityScanner {
    static let shared = AccessibilityScanner()

    // Common AX attributes to query
    private let windowAttributes: [String] = [
        kAXTitleAttribute,
        kAXRoleAttribute,
        kAXSubroleAttribute,
        kAXDocumentAttribute,
        kAXURLAttribute,
        kAXPositionAttribute,
        kAXSizeAttribute,
        kAXMinimizedAttribute,
        "AXFullScreen",
        "AXToolbar",
        kAXMainAttribute,
        kAXFocusedAttribute,
        kAXCloseButtonAttribute,
        kAXZoomButtonAttribute,
        kAXMinimizeButtonAttribute,
        kAXFullScreenButtonAttribute,
        kAXGrowAreaAttribute,
        kAXProxyAttribute,
        kAXDefaultButtonAttribute,
        kAXCancelButtonAttribute,
    ]

    private let elementAttributes: [String] = [
        kAXRoleAttribute,
        kAXSubroleAttribute,
        kAXRoleDescriptionAttribute,
        kAXDescriptionAttribute,
        kAXValueAttribute,
        kAXSelectedTextAttribute,
        kAXSelectedTextRangeAttribute,
        kAXTitleAttribute,
        kAXLabelValueAttribute,
        kAXHelpAttribute,
        kAXPlaceholderValueAttribute,
        kAXURLAttribute,
        kAXLinkUIElementsAttribute,
        kAXNumberOfCharactersAttribute,
        kAXInsertionPointLineNumberAttribute,
        kAXVisibleCharacterRangeAttribute,
        kAXChildrenAttribute,
        kAXParentAttribute,
        kAXEnabledAttribute,
        kAXFocusedAttribute,
        kAXSelectedAttribute,
    ]

    private init() {}

    @MainActor
    func performDeepScan() -> AccessibilityScan {
        let startTime = Date()
        var scannedApps: [AccessibilityApp] = []
        var totalWindows = 0
        var totalAttributes = 0

        let isTrusted = AXIsProcessTrusted()

        guard isTrusted else {
            return AccessibilityScan(
                timestamp: startTime,
                durationMs: 0,
                isAccessibilityTrusted: false,
                apps: [],
                totalWindows: 0,
                totalAttributes: 0
            )
        }

        let runningApps = NSWorkspace.shared.runningApplications
        let frontmostApp = NSWorkspace.shared.frontmostApplication

        // Filter to apps with UI
        let uiApps = runningApps.filter { app in
            app.activationPolicy == .regular || app.activationPolicy == .accessory
        }

        for app in uiApps {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var windows: [AccessibilityWindow] = []
            var menuBar: [AccessibilityMenuItem] = []

            // Get menu bar
            menuBar = scanMenuBar(appElement)

            // Get all windows
            var windowsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let windowList = windowsRef as? [AXUIElement] {

                // Get focused window for comparison
                var focusedWindowRef: CFTypeRef?
                AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)
                let focusedTitle = focusedWindowRef.flatMap { getStringAttribute($0 as! AXUIElement, kAXTitleAttribute) }

                // Get main window
                var mainWindowRef: CFTypeRef?
                AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindowRef)
                let mainTitle = mainWindowRef.flatMap { getStringAttribute($0 as! AXUIElement, kAXTitleAttribute) }

                for (index, window) in windowList.enumerated() {
                    let windowInfo = scanWindow(window, index: index, pid: app.processIdentifier)
                    totalAttributes += windowInfo.allAttributes.count
                    if let focused = windowInfo.focusedElement {
                        totalAttributes += focused.allAttributes.count
                    }

                    let isFocused = windowInfo.title == focusedTitle
                    let isMain = windowInfo.title == mainTitle

                    let finalWindow = AccessibilityWindow(
                        pid: windowInfo.pid,
                        index: windowInfo.index,
                        title: windowInfo.title,
                        role: windowInfo.role,
                        subrole: windowInfo.subrole,
                        isMain: isMain,
                        isFocused: isFocused,
                        isMinimized: windowInfo.isMinimized,
                        isFullScreen: windowInfo.isFullScreen,
                        documentURL: windowInfo.documentURL,
                        url: windowInfo.url,
                        position: windowInfo.position,
                        size: windowInfo.size,
                        toolbar: windowInfo.toolbar,
                        focusedElement: windowInfo.focusedElement,
                        allAttributes: windowInfo.allAttributes,
                        terminalContent: windowInfo.terminalContent
                    )

                    windows.append(finalWindow)
                    totalWindows += 1
                }
            }

            // Only include apps that have windows or are frontmost
            if !windows.isEmpty || app == frontmostApp {
                let accessibilityApp = AccessibilityApp(
                    id: app.processIdentifier,
                    name: app.localizedName ?? "Unknown",
                    bundleId: app.bundleIdentifier,
                    isFrontmost: app == frontmostApp,
                    windows: windows,
                    menuBar: menuBar,
                    icon: app.icon
                )
                scannedApps.append(accessibilityApp)
            }
        }

        // Sort: frontmost first, then by name
        scannedApps.sort { a, b in
            if a.isFrontmost { return true }
            if b.isFrontmost { return false }
            return a.name < b.name
        }

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        log.info("Accessibility scan complete: \(scannedApps.count) apps, \(totalWindows) windows, \(totalAttributes) attributes in \(durationMs)ms")

        return AccessibilityScan(
            timestamp: startTime,
            durationMs: durationMs,
            isAccessibilityTrusted: true,
            apps: scannedApps,
            totalWindows: totalWindows,
            totalAttributes: totalAttributes
        )
    }

    // MARK: - Menu Bar Scanning

    private func scanMenuBar(_ appElement: AXUIElement) -> [AccessibilityMenuItem] {
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef else {
            return []
        }

        return scanMenuChildren(menuBar as! AXUIElement, depth: 0)
    }

    private func scanMenuChildren(_ element: AXUIElement, depth: Int) -> [AccessibilityMenuItem] {
        guard depth < 2 else { return [] }  // Limit depth to avoid too much data

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return []
        }

        var items: [AccessibilityMenuItem] = []

        for child in children.prefix(20) {  // Limit items
            let title = getStringAttribute(child, kAXTitleAttribute) ?? ""
            guard !title.isEmpty else { continue }

            var enabledRef: CFTypeRef?
            let enabled = AXUIElementCopyAttributeValue(child, kAXEnabledAttribute as CFString, &enabledRef) == .success
                ? (enabledRef as? Bool ?? true)
                : true

            // Get keyboard shortcut
            var shortcut: String?
            var cmdCharRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, "AXMenuItemCmdChar" as CFString, &cmdCharRef) == .success,
               let cmdChar = cmdCharRef as? String, !cmdChar.isEmpty {
                shortcut = "⌘\(cmdChar)"
            }

            // Get submenu children
            var submenuChildren: [AccessibilityMenuItem] = []
            var submenuRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &submenuRef) == .success,
               let submenu = submenuRef as? [AXUIElement], !submenu.isEmpty {
                submenuChildren = scanMenuChildren(child, depth: depth + 1)
            }

            items.append(AccessibilityMenuItem(
                title: title,
                children: submenuChildren,
                enabled: enabled,
                shortcut: shortcut
            ))
        }

        return items
    }

    // MARK: - Window Scanning

    private func scanWindow(_ window: AXUIElement, index: Int, pid: pid_t) -> AccessibilityWindow {
        // Get all available attributes for this window
        var attrNamesRef: CFArray?
        var allAttributes: [String] = []
        if AXUIElementCopyAttributeNames(window, &attrNamesRef) == .success,
           let attrNames = attrNamesRef as? [String] {
            allAttributes = attrNames
        }

        // Title
        let title = getStringAttribute(window, kAXTitleAttribute) ?? "(untitled)"

        // Role & Subrole
        let role = getStringAttribute(window, kAXRoleAttribute)
        let subrole = getStringAttribute(window, kAXSubroleAttribute)

        // Document URL
        let documentURL = getStringAttribute(window, kAXDocumentAttribute)

        // URL (for browsers)
        let url = getStringAttribute(window, kAXURLAttribute)

        // Minimized
        var minimizedRef: CFTypeRef?
        let isMinimized = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success
            ? (minimizedRef as? Bool ?? false)
            : false

        // Full Screen
        var fullScreenRef: CFTypeRef?
        let isFullScreen = AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullScreenRef) == .success
            ? (fullScreenRef as? Bool ?? false)
            : false

        // Position
        var positionRef: CFTypeRef?
        var position: CGPoint?
        if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success {
            var point = CGPoint.zero
            if AXValueGetValue(positionRef as! AXValue, .cgPoint, &point) {
                position = point
            }
        }

        // Size
        var sizeRef: CFTypeRef?
        var size: CGSize?
        if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success {
            var s = CGSize.zero
            if AXValueGetValue(sizeRef as! AXValue, .cgSize, &s) {
                size = s
            }
        }

        // Toolbar items
        var toolbar: [String] = []
        var toolbarRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, "AXToolbar" as CFString, &toolbarRef) == .success,
           let toolbarElement = toolbarRef {
            var toolbarChildrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(toolbarElement as! AXUIElement, kAXChildrenAttribute as CFString, &toolbarChildrenRef) == .success,
               let toolbarChildren = toolbarChildrenRef as? [AXUIElement] {
                for item in toolbarChildren.prefix(10) {
                    if let itemTitle = getStringAttribute(item, kAXTitleAttribute) ?? getStringAttribute(item, kAXDescriptionAttribute) {
                        toolbar.append(itemTitle)
                    }
                }
            }
        }

        // Focused element in this window
        var focusedRef: CFTypeRef?
        var focusedElement: AccessibilityElement?
        if AXUIElementCopyAttributeValue(window, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
           let focused = focusedRef {
            focusedElement = scanElement(focused as! AXUIElement)
        }

        // Terminal-specific deep content extraction
        let terminalContent = extractTerminalContent(window)

        return AccessibilityWindow(
            pid: pid,
            index: index,
            title: title,
            role: role,
            subrole: subrole,
            isMain: false,
            isFocused: false,
            isMinimized: isMinimized,
            isFullScreen: isFullScreen,
            documentURL: documentURL,
            url: url,
            position: position,
            size: size,
            toolbar: toolbar,
            focusedElement: focusedElement,
            allAttributes: allAttributes,
            terminalContent: terminalContent
        )
    }

    // MARK: - Terminal Content Extraction

    private func extractTerminalContent(_ window: AXUIElement) -> TerminalContent? {
        // Try to find text areas, scroll areas, or web areas that contain terminal content
        var visibleText: String?
        var tabs: [TerminalTab] = []

        // Search for terminal text content in children
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            visibleText = findTerminalText(in: children, depth: 0)
            tabs = findTabs(in: children)
        }

        // If no content found, check focused element's value
        if visibleText == nil {
            var focusedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
               let focused = focusedRef as! AXUIElement? {
                visibleText = getStringAttribute(focused, kAXValueAttribute)
            }
        }

        // If we found text, extract useful info
        guard let text = visibleText, !text.isEmpty else {
            // Still return tabs if we found them
            if !tabs.isEmpty {
                return TerminalContent(
                    visibleText: nil,
                    lastLines: [],
                    detectedPrompt: nil,
                    detectedCwd: nil,
                    detectedCommand: nil,
                    tabs: tabs
                )
            }
            return nil
        }

        // Get last lines
        let allLines = text.components(separatedBy: .newlines)
        let lastLines = Array(allLines.suffix(20))

        // Detect prompt and cwd
        let (prompt, cwd) = detectPromptAndCwd(from: lastLines)

        // Detect last command (line before prompt that isn't empty)
        var detectedCommand: String?
        if let promptLine = lastLines.last(where: { isPromptLine($0) }),
           let promptIndex = lastLines.lastIndex(of: promptLine),
           promptIndex > 0 {
            let commandLine = lastLines[promptIndex - 1].trimmingCharacters(in: .whitespaces)
            if !commandLine.isEmpty && !isPromptLine(commandLine) {
                detectedCommand = commandLine
            }
        }

        return TerminalContent(
            visibleText: String(text.suffix(2000)), // Truncate to last 2000 chars
            lastLines: lastLines,
            detectedPrompt: prompt,
            detectedCwd: cwd,
            detectedCommand: detectedCommand,
            tabs: tabs
        )
    }

    private func findTerminalText(in elements: [AXUIElement], depth: Int) -> String? {
        guard depth < 5 else { return nil } // Limit recursion

        for element in elements {
            let role = getStringAttribute(element, kAXRoleAttribute)

            // Text areas often contain terminal content
            if role == "AXTextArea" || role == "AXStaticText" || role == "AXWebArea" {
                if let value = getStringAttribute(element, kAXValueAttribute), !value.isEmpty {
                    return value
                }
            }

            // Check for AXScrollArea which often wraps terminal content
            if role == "AXScrollArea" || role == "AXGroup" || role == "AXSplitGroup" {
                var childrenRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                   let children = childrenRef as? [AXUIElement] {
                    if let text = findTerminalText(in: children, depth: depth + 1) {
                        return text
                    }
                }
            }
        }

        return nil
    }

    private func findTabs(in elements: [AXUIElement]) -> [TerminalTab] {
        var tabs: [TerminalTab] = []

        for element in elements {
            let role = getStringAttribute(element, kAXRoleAttribute)

            // Tab groups contain tabs
            if role == "AXTabGroup" {
                var childrenRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                   let children = childrenRef as? [AXUIElement] {
                    for child in children {
                        if getStringAttribute(child, kAXRoleAttribute) == "AXRadioButton" {
                            let title = getStringAttribute(child, kAXTitleAttribute) ?? getStringAttribute(child, kAXDescriptionAttribute) ?? ""

                            var selectedRef: CFTypeRef?
                            let isSelected = AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &selectedRef) == .success
                                ? (selectedRef as? Int == 1)
                                : false

                            tabs.append(TerminalTab(title: title, isSelected: isSelected))
                        }
                    }
                }
            }

            // Recurse into groups
            if role == "AXGroup" || role == "AXSplitGroup" || role == "AXToolbar" {
                var childrenRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                   let children = childrenRef as? [AXUIElement] {
                    tabs.append(contentsOf: findTabs(in: children))
                }
            }
        }

        return tabs
    }

    private func detectPromptAndCwd(from lines: [String]) -> (prompt: String?, cwd: String?) {
        // Common prompt patterns:
        // "user@host:~/dev/project$"
        // "user@host ~/dev/project %"
        // "~/dev/project $"
        // "[user@host project]$"

        let promptPatterns: [(regex: String, cwdGroup: Int)] = [
            // user@host:~/path$
            (#"([a-zA-Z0-9_-]+@[a-zA-Z0-9_.-]+):?(~?/[^\s$%#>]+)[\s]*[$%#>]"#, 2),
            // ~/path $ or /path $
            (#"(~?/[^\s$%#>]+)\s*[$%#>]\s*$"#, 1),
            // [user@host path]$
            (#"\[[a-zA-Z0-9_-]+@[a-zA-Z0-9_.-]+\s+([^\]]+)\][$%#>]"#, 1),
        ]

        // Check last few lines for prompts
        for line in lines.reversed().prefix(5) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            for (pattern, cwdGroup) in promptPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) {
                    if let cwdRange = Range(match.range(at: cwdGroup), in: trimmed) {
                        let cwd = String(trimmed[cwdRange])
                        return (trimmed, cwd)
                    }
                }
            }

            // Check if this looks like a prompt line
            if isPromptLine(trimmed) {
                return (trimmed, nil)
            }
        }

        return (nil, nil)
    }

    private func isPromptLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Ends with common prompt chars
        return trimmed.hasSuffix("$") || trimmed.hasSuffix("%") || trimmed.hasSuffix("#") || trimmed.hasSuffix(">")
    }

    // MARK: - Element Scanning

    private func scanElement(_ element: AXUIElement) -> AccessibilityElement {
        // Get all available attributes
        var attrNamesRef: CFArray?
        var allAttributes: [String] = []
        if AXUIElementCopyAttributeNames(element, &attrNamesRef) == .success,
           let attrNames = attrNamesRef as? [String] {
            allAttributes = attrNames
        }

        // Role
        let role = getStringAttribute(element, kAXRoleAttribute) ?? "Unknown"
        let subrole = getStringAttribute(element, kAXSubroleAttribute)
        let roleDescription = getStringAttribute(element, kAXRoleDescriptionAttribute)

        // Description & Title
        let description = getStringAttribute(element, kAXDescriptionAttribute)
        let title = getStringAttribute(element, kAXTitleAttribute)
        let label = getStringAttribute(element, kAXLabelValueAttribute)
        let help = getStringAttribute(element, kAXHelpAttribute)
        let placeholder = getStringAttribute(element, kAXPlaceholderValueAttribute)

        // Value (truncated)
        var value: String?
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success {
            if let v = valueRef as? String {
                value = v.count > 500 ? String(v.prefix(500)) + "..." : v
            } else if let n = valueRef as? NSNumber {
                value = n.stringValue
            }
        }

        // Selected text
        var selectedText: String?
        var selectedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
           let s = selectedRef as? String, !s.isEmpty {
            selectedText = s.count > 500 ? String(s.prefix(500)) + "..." : s
        }

        // Selected text range
        var selectedTextRange: String?
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success {
            var range = CFRange()
            if AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) {
                selectedTextRange = "loc: \(range.location), len: \(range.length)"
            }
        }

        // URL
        let url = getStringAttribute(element, kAXURLAttribute)

        // Link URL (for link elements)
        var linkURL: String?
        var linkRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXLinkedUIElements" as CFString, &linkRef) == .success,
           let links = linkRef as? [AXUIElement], let first = links.first {
            linkURL = getStringAttribute(first, kAXURLAttribute)
        }

        // Number of characters
        var numberOfCharacters: Int?
        var numCharsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &numCharsRef) == .success,
           let n = numCharsRef as? Int {
            numberOfCharacters = n
        }

        // Insertion point line number
        var insertionPointLineNumber: Int?
        var lineRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXInsertionPointLineNumberAttribute as CFString, &lineRef) == .success,
           let n = lineRef as? Int {
            insertionPointLineNumber = n
        }

        // Visible character range
        var visibleCharacterRange: String?
        var visRangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXVisibleCharacterRangeAttribute as CFString, &visRangeRef) == .success {
            var range = CFRange()
            if AXValueGetValue(visRangeRef as! AXValue, .cfRange, &range) {
                visibleCharacterRange = "loc: \(range.location), len: \(range.length)"
            }
        }

        // Children count
        var childrenCount = 0
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            childrenCount = children.count
        }

        // Available actions
        var actions: [String] = []
        var actionNamesRef: CFArray?
        if AXUIElementCopyActionNames(element, &actionNamesRef) == .success,
           let actionNames = actionNamesRef as? [String] {
            actions = actionNames
        }

        // Parent chain (roles up to window)
        var parentChain: [String] = []
        var currentElement = element
        for _ in 0..<10 {  // Limit depth
            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(currentElement, kAXParentAttribute as CFString, &parentRef) == .success,
               let parent = (parentRef as! AXUIElement?) {
                if let parentRole = getStringAttribute(parent, kAXRoleAttribute) {
                    parentChain.append(parentRole)
                    if parentRole == "AXWindow" { break }
                }
                currentElement = parent
            } else {
                break
            }
        }

        return AccessibilityElement(
            role: role,
            subrole: subrole,
            roleDescription: roleDescription,
            description: description,
            value: value,
            selectedText: selectedText,
            selectedTextRange: selectedTextRange,
            title: title,
            label: label,
            help: help,
            placeholder: placeholder,
            url: url,
            linkURL: linkURL,
            numberOfCharacters: numberOfCharacters,
            insertionPointLineNumber: insertionPointLineNumber,
            visibleCharacterRange: visibleCharacterRange,
            children: childrenCount,
            actions: actions,
            allAttributes: allAttributes,
            parentChain: parentChain
        )
    }

    // MARK: - Helpers

    private func getStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else {
            return nil
        }
        return ref as? String
    }
}

// MARK: - Settings View

struct AccessibilityInventorySection: View {
    @State private var scan: AccessibilityScan?
    @State private var isScanning = false
    @State private var expandedApps: Set<pid_t> = []
    @State private var expandedWindows: Set<String> = []
    @State private var expandedMenus: Set<pid_t> = []
    @State private var showRawAttributes = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Header
            headerSection

            // Scan button & stats
            controlsSection

            // Results
            if let scan = scan {
                if !scan.isAccessibilityTrusted {
                    accessibilityWarning
                } else {
                    resultsSection(scan)
                }
            } else {
                emptyState
            }
        }
        .padding(Spacing.lg)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(Color.purple.opacity(0.12))
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .strokeBorder(Color.purple.opacity(0.2), lineWidth: 0.5)
                    Image(systemName: "accessibility")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.purple)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("ACCESSIBILITY INVENTORY")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(Tracking.normal)
                        .foregroundColor(TalkieTheme.textPrimary)

                    Text("Deep scan of all apps, windows, menus, and focused elements.")
                        .font(.system(size: 11))
                        .foregroundColor(TalkieTheme.textTertiary)
                }

                Spacer()
            }

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.08), Color.white.opacity(0.02), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.top, Spacing.md)
        }
    }

    private var controlsSection: some View {
        HStack(spacing: Spacing.md) {
            Button(action: performScan) {
                HStack(spacing: 6) {
                    if isScanning {
                        BrailleSpinner()
                            .font(.system(size: 12))
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 12))
                    }
                    Text(isScanning ? "Scanning..." : "Deep Scan")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isScanning)

            Toggle("Show raw attributes", isOn: $showRawAttributes)
                .toggleStyle(.switch)
                .scaleEffect(0.8)
                .font(.system(size: 10))
                .foregroundColor(TalkieTheme.textSecondary)

            if let scan = scan {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(scan.apps.count) apps • \(scan.totalWindows) windows • \(scan.totalAttributes) attrs")
                        .font(.system(size: 11))
                        .foregroundColor(TalkieTheme.textSecondary)
                    Text("Scanned in \(scan.durationMs)ms")
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
            }

            Spacer()
        }
    }

    private var accessibilityWarning: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("Accessibility Permission Required")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TalkieTheme.textPrimary)
                Text("Enable TalkieLive in System Settings > Privacy & Security > Accessibility")
                    .font(.system(size: 11))
                    .foregroundColor(TalkieTheme.textSecondary)
            }

            Spacer()

            Button("Open Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            .font(.system(size: 11))
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(TalkieTheme.textTertiary)
            Text("Run a deep scan to see all accessible data")
                .font(.system(size: 12))
                .foregroundColor(TalkieTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private func resultsSection(_ scan: AccessibilityScan) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(scan.apps) { app in
                    appRow(app)
                }
            }
        }
        .frame(maxHeight: 500)
    }

    @ViewBuilder
    private func appRow(_ app: AccessibilityApp) -> some View {
        let isExpanded = expandedApps.contains(app.id)
        let isMenuExpanded = expandedMenus.contains(app.id)

        VStack(alignment: .leading, spacing: 0) {
            // App header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedApps.remove(app.id)
                    } else {
                        expandedApps.insert(app.id)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(TalkieTheme.textTertiary)
                        .frame(width: 10)

                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "app.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                    }

                    Text(app.name)
                        .font(.system(size: 12, weight: app.isFrontmost ? .semibold : .regular))
                        .foregroundColor(TalkieTheme.textPrimary)

                    if app.isFrontmost {
                        Text("ACTIVE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(3)
                    }

                    Spacer()

                    if !app.menuBar.isEmpty {
                        Button {
                            withAnimation {
                                if isMenuExpanded {
                                    expandedMenus.remove(app.id)
                                } else {
                                    expandedMenus.insert(app.id)
                                }
                            }
                        } label: {
                            Text("\(app.menuBar.count) menus")
                                .font(.system(size: 9))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(3)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("\(app.windows.count) window\(app.windows.count == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textTertiary)

                    if let bundleId = app.bundleId {
                        Text(bundleId)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(TalkieTheme.textTertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Menu bar (if expanded)
            if isMenuExpanded && !app.menuBar.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MENU BAR")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(TalkieTheme.textTertiary)
                        .padding(.leading, 32)

                    ForEach(app.menuBar) { menuItem in
                        menuItemRow(menuItem, depth: 0)
                    }
                }
                .padding(.vertical, 4)
                .padding(.leading, 24)
                .background(Color.blue.opacity(0.03))
            }

            // Windows (if expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(app.windows) { window in
                        windowRow(window)
                    }
                }
                .padding(.leading, 32)
                .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(app.isFrontmost ? Color.green.opacity(0.05) : Color.white.opacity(0.02))
        )
    }

    private func menuItemRow(_ item: AccessibilityMenuItem, depth: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(String(repeating: "  ", count: depth))
                    .font(.system(size: 9, design: .monospaced))
                Image(systemName: item.children.isEmpty ? "minus" : "folder")
                    .font(.system(size: 8))
                    .foregroundColor(item.enabled ? .secondary : .secondary.opacity(0.5))
                Text(item.title)
                    .font(.system(size: 10))
                    .foregroundColor(item.enabled ? TalkieTheme.textPrimary : TalkieTheme.textTertiary)
                if let shortcut = item.shortcut {
                    Text(shortcut)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.blue)
                }
                Spacer()
            }
            .padding(.leading, CGFloat(depth * 12) + 32)

            // Show children inline (flattened)
            ForEach(item.children) { child in
                HStack(spacing: 6) {
                    Text(String(repeating: "  ", count: depth + 1))
                        .font(.system(size: 9, design: .monospaced))
                    Image(systemName: "minus")
                        .font(.system(size: 8))
                        .foregroundColor(child.enabled ? .secondary : .secondary.opacity(0.5))
                    Text(child.title)
                        .font(.system(size: 10))
                        .foregroundColor(child.enabled ? TalkieTheme.textPrimary : TalkieTheme.textTertiary)
                    if let shortcut = child.shortcut {
                        Text(shortcut)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                    Spacer()
                }
                .padding(.leading, CGFloat((depth + 1) * 12) + 32)
            }
        }
    }

    @ViewBuilder
    private func windowRow(_ window: AccessibilityWindow) -> some View {
        let isExpanded = expandedWindows.contains(window.id)

        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedWindows.remove(window.id)
                    } else {
                        expandedWindows.insert(window.id)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(TalkieTheme.textTertiary)
                        .frame(width: 8)

                    Image(systemName: window.isFocused ? "macwindow.badge.plus" : "macwindow")
                        .font(.system(size: 11))
                        .foregroundColor(window.isFocused ? .blue : .secondary)

                    Text(window.title)
                        .font(.system(size: 11))
                        .foregroundColor(TalkieTheme.textPrimary)
                        .lineLimit(1)

                    if window.isMain {
                        badge("main", .orange)
                    }
                    if window.isFocused {
                        badge("focused", .blue)
                    }
                    if window.isMinimized {
                        badge("minimized", .gray)
                    }
                    if window.isFullScreen {
                        badge("fullscreen", .purple)
                    }

                    Spacer()

                    Text("\(window.allAttributes.count) attrs")
                        .font(.system(size: 9))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    // Window details
                    if let role = window.role {
                        detailRow("Role", role + (window.subrole.map { " / \($0)" } ?? ""))
                    }
                    if let pos = window.position, let size = window.size {
                        detailRow("Frame", "\(Int(pos.x)),\(Int(pos.y)) \(Int(size.width))x\(Int(size.height))")
                    }
                    if let doc = window.documentURL {
                        detailRow("Document", doc)
                    }
                    if let url = window.url {
                        detailRow("URL", url)
                    }
                    if !window.toolbar.isEmpty {
                        detailRow("Toolbar", window.toolbar.joined(separator: ", "))
                    }

                    // Terminal Content (the gold!)
                    if let terminal = window.terminalContent {
                        Divider()
                        Text("TERMINAL CONTENT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green)

                        if !terminal.tabs.isEmpty {
                            HStack(spacing: 4) {
                                Text("Tabs:")
                                    .font(.system(size: 9))
                                    .foregroundColor(TalkieTheme.textTertiary)
                                ForEach(terminal.tabs) { tab in
                                    Text(tab.title)
                                        .font(.system(size: 8, design: .monospaced))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(tab.isSelected ? Color.green.opacity(0.3) : Color.white.opacity(0.1))
                                        .cornerRadius(3)
                                }
                            }
                        }

                        if let cwd = terminal.detectedCwd {
                            detailRow("Detected CWD", cwd)
                        }
                        if let prompt = terminal.detectedPrompt {
                            detailRow("Prompt", prompt)
                        }
                        if let cmd = terminal.detectedCommand {
                            detailRow("Last Cmd", cmd)
                        }
                        if !terminal.lastLines.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Last \(terminal.lastLines.count) lines:")
                                    .font(.system(size: 9))
                                    .foregroundColor(TalkieTheme.textTertiary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    Text(terminal.lastLines.joined(separator: "\n"))
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(TalkieTheme.textSecondary)
                                        .textSelection(.enabled)
                                }
                                .frame(maxHeight: 100)
                            }
                        }
                    }

                    // Raw attributes
                    if showRawAttributes && !window.allAttributes.isEmpty {
                        Divider()
                        Text("All Attributes (\(window.allAttributes.count))")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(TalkieTheme.textTertiary)
                        Text(window.allAttributes.joined(separator: ", "))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(TalkieTheme.textTertiary)
                            .textSelection(.enabled)
                    }

                    // Focused element
                    if let element = window.focusedElement {
                        Divider()
                        Text("FOCUSED ELEMENT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.blue)

                        detailRow("Role", element.role + (element.subrole.map { " / \($0)" } ?? ""))
                        if let roleDesc = element.roleDescription {
                            detailRow("Role Desc", roleDesc)
                        }
                        if let title = element.title {
                            detailRow("Title", title)
                        }
                        if let label = element.label {
                            detailRow("Label", label)
                        }
                        if let desc = element.description {
                            detailRow("Description", desc)
                        }
                        if let help = element.help {
                            detailRow("Help", help)
                        }
                        if let placeholder = element.placeholder {
                            detailRow("Placeholder", placeholder)
                        }
                        if let value = element.value {
                            detailRow("Value", value)
                        }
                        if let selected = element.selectedText {
                            detailRow("Selected", selected)
                        }
                        if let range = element.selectedTextRange {
                            detailRow("Selection Range", range)
                        }
                        if let url = element.url {
                            detailRow("URL", url)
                        }
                        if let linkURL = element.linkURL {
                            detailRow("Link URL", linkURL)
                        }
                        if let numChars = element.numberOfCharacters {
                            detailRow("Characters", "\(numChars)")
                        }
                        if let line = element.insertionPointLineNumber {
                            detailRow("Cursor Line", "\(line)")
                        }
                        if let visRange = element.visibleCharacterRange {
                            detailRow("Visible Range", visRange)
                        }
                        detailRow("Children", "\(element.children)")
                        if !element.actions.isEmpty {
                            detailRow("Actions", element.actions.joined(separator: ", "))
                        }
                        if !element.parentChain.isEmpty {
                            detailRow("Parent Chain", element.parentChain.joined(separator: " → "))
                        }

                        // Raw attributes for element
                        if showRawAttributes && !element.allAttributes.isEmpty {
                            Divider()
                            Text("Element Attributes (\(element.allAttributes.count))")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(TalkieTheme.textTertiary)
                            Text(element.allAttributes.joined(separator: ", "))
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(TalkieTheme.textTertiary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.leading, 24)
                .padding(.vertical, 4)
                .padding(.trailing, 8)
                .background(Color.white.opacity(0.02))
                .cornerRadius(4)
            }
        }
    }

    @ViewBuilder
    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 8))
            .foregroundColor(color)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .cornerRadius(2)
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(TalkieTheme.textTertiary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(TalkieTheme.textSecondary)
                .textSelection(.enabled)
                .lineLimit(4)
            Spacer()
        }
    }

    private func performScan() {
        isScanning = true
        DispatchQueue.main.async {
            self.scan = AccessibilityScanner.shared.performDeepScan()
            // Auto-expand frontmost app
            if let frontmost = self.scan?.apps.first(where: { $0.isFrontmost }) {
                self.expandedApps.insert(frontmost.id)
            }
            self.isScanning = false
        }
    }
}

#Preview {
    AccessibilityInventorySection()
        .frame(width: 700, height: 600)
        .background(Color.black.opacity(0.9))
}
