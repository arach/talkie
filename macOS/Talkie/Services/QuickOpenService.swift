//
//  QuickOpenService.swift
//  Talkie
//
//  Quick open content in external apps (Claude, ChatGPT, Notes, etc.)
//

import Foundation
import AppKit
import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "QuickOpen")

// MARK: - Quick Open Target

/// An app that can receive content from Talkie
struct QuickOpenTarget: Identifiable, Codable, Equatable {
    let id: String                    // Unique identifier (e.g., "claude", "chatgpt")
    var name: String                  // Display name
    var bundleId: String?             // Bundle ID for getting real app icon
    var openMethod: OpenMethod        // How to open content in this app
    var isEnabled: Bool               // Whether to show in quick open bar
    var keyboardShortcut: Int?        // 1-9 for ⌘1-⌘9, nil for no shortcut
    var promptPrefix: String?         // Optional prefix (e.g., "Please help me with:")
    var autoPaste: Bool               // Whether to auto-paste using accessibility

    /// How to open content in the target app
    enum OpenMethod: Codable, Equatable {
        case urlScheme(String)                    // URL scheme (e.g., "claude://")
        case bundleId(String)                     // Just open app, content via clipboard
        case applescript(String)                  // AppleScript to run
        case custom(String)                       // Custom shell command
    }

    /// Check if the app is installed
    var isInstalled: Bool {
        if let bundleId = bundleId {
            return AppIconProvider.shared.isAppInstalled(bundleIdentifier: bundleId)
        }
        // For URL scheme targets, assume installed
        return true
    }
}

// MARK: - Default Targets

extension QuickOpenTarget {
    /// Built-in quick open targets
    static let builtInTargets: [QuickOpenTarget] = [
        QuickOpenTarget(
            id: "claude",
            name: "Claude",
            bundleId: "com.anthropic.claudefordesktop",
            openMethod: .bundleId("com.anthropic.claudefordesktop"),
            isEnabled: true,
            keyboardShortcut: 1,
            promptPrefix: nil,
            autoPaste: true
        ),
        QuickOpenTarget(
            id: "chatgpt",
            name: "ChatGPT",
            bundleId: "com.openai.chat",
            openMethod: .bundleId("com.openai.chat"),
            isEnabled: true,
            keyboardShortcut: 2,
            promptPrefix: nil,
            autoPaste: true
        ),
        QuickOpenTarget(
            id: "notes",
            name: "Notes",
            bundleId: "com.apple.Notes",
            openMethod: .bundleId("com.apple.Notes"),
            isEnabled: true,
            keyboardShortcut: 3,
            promptPrefix: nil,
            autoPaste: false
        ),
        QuickOpenTarget(
            id: "obsidian",
            name: "Obsidian",
            bundleId: "md.obsidian",
            openMethod: .urlScheme("obsidian://new?content="),
            isEnabled: false,
            keyboardShortcut: 4,
            promptPrefix: nil,
            autoPaste: false
        ),
        QuickOpenTarget(
            id: "bear",
            name: "Bear",
            bundleId: "net.shinyfrog.bear",
            openMethod: .urlScheme("bear://x-callback-url/create?text="),
            isEnabled: false,
            keyboardShortcut: nil,
            promptPrefix: nil,
            autoPaste: false
        ),
        QuickOpenTarget(
            id: "notion",
            name: "Notion",
            bundleId: "notion.id",
            openMethod: .bundleId("notion.id"),
            isEnabled: false,
            keyboardShortcut: nil,
            promptPrefix: nil,
            autoPaste: true
        ),
        QuickOpenTarget(
            id: "things",
            name: "Things",
            bundleId: "com.culturedcode.ThingsMac",
            openMethod: .urlScheme("things:///add?title=From Talkie&notes="),
            isEnabled: false,
            keyboardShortcut: nil,
            promptPrefix: nil,
            autoPaste: false
        ),
        QuickOpenTarget(
            id: "reminders",
            name: "Reminders",
            bundleId: "com.apple.reminders",
            openMethod: .bundleId("com.apple.reminders"),
            isEnabled: false,
            keyboardShortcut: nil,
            promptPrefix: nil,
            autoPaste: false
        )
    ]
}

// MARK: - Quick Open Service

@MainActor
class QuickOpenService: ObservableObject {
    static let shared = QuickOpenService()

    @Published var targets: [QuickOpenTarget] {
        didSet { saveTargets() }
    }

    /// Only enabled targets, sorted by keyboard shortcut
    var enabledTargets: [QuickOpenTarget] {
        targets
            .filter { $0.isEnabled }
            .sorted { ($0.keyboardShortcut ?? 99) < ($1.keyboardShortcut ?? 99) }
    }

    private let userDefaultsKey = "quickOpenTargets"

    private init() {
        // Load saved targets or use defaults
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode([QuickOpenTarget].self, from: data) {
            // Merge saved with built-in (in case new built-ins were added)
            var merged = saved
            for builtIn in QuickOpenTarget.builtInTargets {
                if !merged.contains(where: { $0.id == builtIn.id }) {
                    merged.append(builtIn)
                }
            }
            self.targets = merged
        } else {
            self.targets = QuickOpenTarget.builtInTargets
        }
    }

    private func saveTargets() {
        if let data = try? JSONEncoder().encode(targets) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    /// Open content in the specified target app
    func open(content: String, in target: QuickOpenTarget) {
        let finalContent: String
        if let prefix = target.promptPrefix, !prefix.isEmpty {
            finalContent = "\(prefix)\n\n\(content)"
        } else {
            finalContent = content
        }

        logger.info("Opening in \(target.name): \(finalContent.prefix(50))...")

        switch target.openMethod {
        case .urlScheme(let scheme):
            openViaURLScheme(scheme, content: finalContent)

        case .bundleId(let bundleId):
            openViaBundleId(bundleId, content: finalContent, autoPaste: target.autoPaste)

        case .applescript(let script):
            openViaAppleScript(script, content: finalContent)

        case .custom(let command):
            openViaCommand(command, content: finalContent)
        }
    }

    /// Open by target ID (for keyboard shortcuts)
    func open(content: String, targetId: String) {
        guard let target = targets.first(where: { $0.id == targetId }) else {
            logger.warning("Unknown target: \(targetId)")
            return
        }
        open(content: content, in: target)
    }

    /// Open by keyboard shortcut number (1-9)
    func open(content: String, shortcut: Int) {
        guard let target = enabledTargets.first(where: { $0.keyboardShortcut == shortcut }) else {
            logger.debug("No target for shortcut ⌘\(shortcut)")
            return
        }
        open(content: content, in: target)
    }

    // MARK: - Opening Methods

    private func openViaURLScheme(_ scheme: String, content: String) {
        guard let encoded = content.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: scheme + encoded) else {
            logger.error("Failed to create URL for scheme: \(scheme)")
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func openViaBundleId(_ bundleId: String, content: String, autoPaste: Bool) {
        // Copy to clipboard first
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)

        // Open the app
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            logger.error("App not found: \(bundleId)")
            // Show alert
            Task { @MainActor in
                let alert = NSAlert()
                alert.messageText = "App Not Found"
                alert.informativeText = "The app is not installed. Content has been copied to clipboard."
                alert.alertStyle = .warning
                alert.runModal()
            }
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { [weak self] app, error in
            if let error = error {
                logger.error("Failed to open app: \(error.localizedDescription)")
            } else {
                logger.info("Opened app, content in clipboard")

                // Auto-paste if enabled
                if autoPaste {
                    Task { @MainActor in
                        // Wait for app to be ready
                        try? await Task.sleep(for: .milliseconds(500))
                        self?.performAutoPaste()
                    }
                }
            }
        }
    }

    /// Auto-paste into the frontmost app's input field
    private func performAutoPaste() {
        // Get the frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            logger.warning("No frontmost application")
            return
        }

        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // Try to find and focus the main text input field
        if focusMainTextInput(in: appElement) {
            // Small delay to ensure focus is set
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.simulatePaste()
            }
        } else {
            // Fallback: just try to paste anyway (might work if input is already focused)
            logger.info("Could not find text input, attempting paste anyway")
            simulatePaste()
        }
    }

    /// Find and focus the main text input field in an app
    private func focusMainTextInput(in appElement: AXUIElement) -> Bool {
        // First try to get the focused window
        var focusedWindow: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)

        let searchElement: AXUIElement
        if windowResult == .success, let window = focusedWindow {
            searchElement = (window as! AXUIElement)
        } else {
            searchElement = appElement
        }

        // Search for text fields/text areas
        if let textInput = findTextInput(in: searchElement) {
            // Focus the text input
            AXUIElementSetAttributeValue(textInput, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            logger.info("Focused text input field")
            return true
        }

        return false
    }

    /// Recursively search for a text input element
    private func findTextInput(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < 15 else { return nil } // Prevent infinite recursion

        // Check the role of this element
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)

        if let role = roleRef as? String {
            // Look for text fields, text areas, or combo boxes
            if role == kAXTextFieldRole as String ||
               role == kAXTextAreaRole as String ||
               role == "AXWebArea" {  // For Electron apps like Claude/ChatGPT

                // Check if it's enabled/editable
                var enabledRef: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledRef)
                if let enabled = enabledRef as? Bool, enabled {
                    return element
                }
                // If no enabled attribute, assume it's editable
                return element
            }
        }

        // Get children and search recursively
        var childrenRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)

        guard result == .success, let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        // For web-based apps, prioritize certain elements
        for child in children {
            if let found = findTextInput(in: child, depth: depth + 1) {
                return found
            }
        }

        return nil
    }

    /// Simulate Cmd+V keystroke
    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down: V with Cmd modifier
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }

        // Key up: V
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
        }

        logger.info("Simulated Cmd+V paste")
    }

    private func openViaAppleScript(_ script: String, content: String) {
        let escapedContent = content.replacingOccurrences(of: "\"", with: "\\\"")
        let finalScript = script.replacingOccurrences(of: "{{CONTENT}}", with: escapedContent)

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: finalScript) {
            scriptObject.executeAndReturnError(&error)
            if let error = error {
                logger.error("AppleScript error: \(error)")
            }
        }
    }

    private func openViaCommand(_ command: String, content: String) {
        let escapedContent = content.replacingOccurrences(of: "'", with: "'\\''")
        let finalCommand = command.replacingOccurrences(of: "{{CONTENT}}", with: escapedContent)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", finalCommand]

        do {
            try process.run()
        } catch {
            logger.error("Command error: \(error.localizedDescription)")
        }
    }

    // MARK: - Configuration

    func toggleTarget(_ id: String, enabled: Bool) {
        if let index = targets.firstIndex(where: { $0.id == id }) {
            targets[index].isEnabled = enabled
        }
    }

    func setShortcut(_ id: String, shortcut: Int?) {
        // Clear any existing target with this shortcut
        if let shortcut = shortcut {
            for i in targets.indices {
                if targets[i].keyboardShortcut == shortcut {
                    targets[i].keyboardShortcut = nil
                }
            }
        }

        // Set the new shortcut
        if let index = targets.firstIndex(where: { $0.id == id }) {
            targets[index].keyboardShortcut = shortcut
        }
    }

    func reorderTargets(_ newOrder: [String]) {
        targets.sort { a, b in
            let indexA = newOrder.firstIndex(of: a.id) ?? Int.max
            let indexB = newOrder.firstIndex(of: b.id) ?? Int.max
            return indexA < indexB
        }
    }
}
