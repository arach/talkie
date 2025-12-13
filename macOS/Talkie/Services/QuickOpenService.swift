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
    var icon: QuickOpenIcon           // Icon type
    var openMethod: OpenMethod        // How to open content in this app
    var isEnabled: Bool               // Whether to show in quick open bar
    var keyboardShortcut: Int?        // 1-9 for ⌘1-⌘9, nil for no shortcut
    var promptPrefix: String?         // Optional prefix (e.g., "Please help me with:")

    /// How to open content in the target app
    enum OpenMethod: Codable, Equatable {
        case urlScheme(String)                    // URL scheme (e.g., "claude://")
        case bundleId(String)                     // Just open app, content via clipboard
        case applescript(String)                  // AppleScript to run
        case custom(String)                       // Custom shell command
    }

    /// Icon representation
    enum QuickOpenIcon: Codable, Equatable {
        case asset(String)                        // Asset catalog image name
        case symbol(String)                       // SF Symbol name
        case initials(String, Color)              // Text initials with background color

        // Codable support for Color
        enum CodingKeys: String, CodingKey {
            case type, value, color
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "asset":
                self = .asset(try container.decode(String.self, forKey: .value))
            case "symbol":
                self = .symbol(try container.decode(String.self, forKey: .value))
            case "initials":
                let value = try container.decode(String.self, forKey: .value)
                let colorHex = try container.decode(String.self, forKey: .color)
                self = .initials(value, Color(hex: colorHex) ?? .gray)
            default:
                self = .symbol("questionmark.app")
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .asset(let name):
                try container.encode("asset", forKey: .type)
                try container.encode(name, forKey: .value)
            case .symbol(let name):
                try container.encode("symbol", forKey: .type)
                try container.encode(name, forKey: .value)
            case .initials(let text, let color):
                try container.encode("initials", forKey: .type)
                try container.encode(text, forKey: .value)
                try container.encode(color.hexString, forKey: .color)
            }
        }
    }
}

// MARK: - Default Targets

extension QuickOpenTarget {
    /// Built-in quick open targets
    static let builtInTargets: [QuickOpenTarget] = [
        QuickOpenTarget(
            id: "claude",
            name: "Claude",
            icon: .initials("C", .orange),
            openMethod: .bundleId("com.anthropic.claudefordesktop"),
            isEnabled: true,
            keyboardShortcut: 1,
            promptPrefix: nil
        ),
        QuickOpenTarget(
            id: "chatgpt",
            name: "ChatGPT",
            icon: .initials("G", Color(hex: "#10a37f") ?? .green),
            openMethod: .bundleId("com.openai.chat"),
            isEnabled: true,
            keyboardShortcut: 2,
            promptPrefix: nil
        ),
        QuickOpenTarget(
            id: "notes",
            name: "Notes",
            icon: .symbol("note.text"),
            openMethod: .bundleId("com.apple.Notes"),
            isEnabled: true,
            keyboardShortcut: 3,
            promptPrefix: nil
        ),
        QuickOpenTarget(
            id: "obsidian",
            name: "Obsidian",
            icon: .initials("O", .purple),
            openMethod: .urlScheme("obsidian://new?content="),
            isEnabled: false,
            keyboardShortcut: 4,
            promptPrefix: nil
        ),
        QuickOpenTarget(
            id: "bear",
            name: "Bear",
            icon: .initials("B", Color(hex: "#c0392b") ?? .red),
            openMethod: .urlScheme("bear://x-callback-url/create?text="),
            isEnabled: false,
            keyboardShortcut: nil,
            promptPrefix: nil
        ),
        QuickOpenTarget(
            id: "notion",
            name: "Notion",
            icon: .initials("N", .primary),
            openMethod: .bundleId("notion.id"),
            isEnabled: false,
            keyboardShortcut: nil,
            promptPrefix: nil
        ),
        QuickOpenTarget(
            id: "things",
            name: "Things",
            icon: .symbol("checkmark.circle"),
            openMethod: .urlScheme("things:///add?title=From Talkie&notes="),
            isEnabled: false,
            keyboardShortcut: nil,
            promptPrefix: nil
        ),
        QuickOpenTarget(
            id: "reminders",
            name: "Reminders",
            icon: .symbol("checklist"),
            openMethod: .bundleId("com.apple.reminders"),
            isEnabled: false,
            keyboardShortcut: nil,
            promptPrefix: nil
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
            openViaBundleId(bundleId, content: finalContent)

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

    private func openViaBundleId(_ bundleId: String, content: String) {
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

        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
            if let error = error {
                logger.error("Failed to open app: \(error.localizedDescription)")
            } else {
                logger.info("Opened app, content in clipboard")
            }
        }
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

// MARK: - Color Hex Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    var hexString: String {
        guard let components = NSColor(self).cgColor.components, components.count >= 3 else {
            return "#808080"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
