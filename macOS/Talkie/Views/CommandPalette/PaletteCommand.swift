//
//  PaletteCommand.swift
//  Talkie macOS
//
//  Command model and registry for the command palette
//

import SwiftUI

// MARK: - Notification Names

extension NSNotification.Name {
    static let navigateToSection = NSNotification.Name("navigateToSection")
    static let showCommandPalette = NSNotification.Name("showCommandPalette")
    static let showKeyboardHelp = NSNotification.Name("showKeyboardHelp")
}

// MARK: - Command Model

struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let shortcut: String?
    let keywords: [String]
    let action: () -> Void

    init(
        title: String,
        subtitle: String,
        icon: String,
        shortcut: String? = nil,
        keywords: [String] = [],
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.shortcut = shortcut
        self.keywords = keywords
        self.action = action
    }

    func matches(_ query: String) -> Bool {
        let lowercasedQuery = query.lowercased()
        return title.localizedCaseInsensitiveContains(query)
            || subtitle.localizedCaseInsensitiveContains(query)
            || keywords.contains { $0.localizedCaseInsensitiveContains(lowercasedQuery) }
    }
}

// MARK: - Command Registry

struct CommandRegistry {
    static let shared = CommandRegistry()

    let commands: [PaletteCommand]

    private init() {
        commands = Self.buildCommands()
    }

    private static func buildCommands() -> [PaletteCommand] {
        var cmds: [PaletteCommand] = []

        // MARK: Navigation Commands

        cmds.append(PaletteCommand(
            title: "Go to Home",
            subtitle: "Navigation",
            icon: "house",
            keywords: ["dashboard", "main"]
        ) {
            NotificationCenter.default.post(name: .navigateToSection, object: NavigationSection.home)
        })

        cmds.append(PaletteCommand(
            title: "Go to Memos",
            subtitle: "Navigation",
            icon: "doc.text",
            keywords: ["recordings", "voice", "notes"]
        ) {
            NotificationCenter.default.post(name: .navigateToSection, object: NavigationSection.allMemos)
        })

        cmds.append(PaletteCommand(
            title: "Go to Dictations",
            subtitle: "Navigation",
            icon: "waveform",
            keywords: ["live", "utterances", "speech"]
        ) {
            NotificationCenter.default.post(name: .navigateToSection, object: NavigationSection.liveRecent)
        })

        cmds.append(PaletteCommand(
            title: "Go to Actions",
            subtitle: "Navigation",
            icon: "bolt",
            keywords: ["ai", "results", "commands"]
        ) {
            NotificationCenter.default.post(name: .navigateToSection, object: NavigationSection.aiResults)
        })

        cmds.append(PaletteCommand(
            title: "Go to Workflows",
            subtitle: "Navigation",
            icon: "arrow.triangle.branch",
            keywords: ["automations", "pipelines"]
        ) {
            NotificationCenter.default.post(name: .navigateToSection, object: NavigationSection.workflows)
        })

        cmds.append(PaletteCommand(
            title: "Go to Drafts",
            subtitle: "Navigation",
            icon: "doc.text",
            keywords: ["text", "editor", "notes", "drafts"]
        ) {
            NotificationCenter.default.post(name: .navigateToSection, object: NavigationSection.drafts)
        })

        cmds.append(PaletteCommand(
            title: "Go to Models",
            subtitle: "Navigation",
            icon: "cube",
            keywords: ["llm", "ai", "providers"]
        ) {
            NotificationCenter.default.post(name: .navigateToSection, object: NavigationSection.models)
        })

        cmds.append(PaletteCommand(
            title: "Go to Activity Log",
            subtitle: "Navigation",
            icon: "list.bullet.rectangle",
            keywords: ["events", "history"]
        ) {
            NotificationCenter.default.post(name: .navigateToSection, object: NavigationSection.activityLog)
        })

        cmds.append(PaletteCommand(
            title: "Go to System Console",
            subtitle: "Navigation",
            icon: "terminal",
            keywords: ["logs", "debug"]
        ) {
            NotificationCenter.default.post(name: .navigateToSection, object: NavigationSection.systemConsole)
        })

        // MARK: Settings Commands

        cmds.append(PaletteCommand(
            title: "Open Settings",
            subtitle: "App",
            icon: "gear",
            shortcut: "⌘,",
            keywords: ["preferences", "config"]
        ) {
            NotificationCenter.default.post(name: .navigateToSettings, object: nil)
        })

        cmds.append(PaletteCommand(
            title: "Dictionary Settings",
            subtitle: "Settings",
            icon: "text.book.closed",
            keywords: ["words", "replacements", "autocorrect"]
        ) {
            NotificationCenter.default.post(name: .navigateToSettings, object: "dictionary")
        })

        cmds.append(PaletteCommand(
            title: "API Keys",
            subtitle: "Settings",
            icon: "key",
            keywords: ["openai", "anthropic", "providers"]
        ) {
            NotificationCenter.default.post(name: .navigateToSettings, object: "apiKeys")
        })

        cmds.append(PaletteCommand(
            title: "Appearance Settings",
            subtitle: "Settings",
            icon: "paintbrush",
            keywords: ["theme", "colors", "dark", "light"]
        ) {
            NotificationCenter.default.post(name: .navigateToSettings, object: "appearance")
        })

        cmds.append(PaletteCommand(
            title: "Dictation Settings",
            subtitle: "Settings",
            icon: "mic",
            keywords: ["voice", "hotkey", "capture"]
        ) {
            NotificationCenter.default.post(name: .navigateToSettings, object: "dictationCapture")
        })

        // MARK: View Commands

        cmds.append(PaletteCommand(
            title: "Toggle Sidebar",
            subtitle: "View",
            icon: "sidebar.left",
            shortcut: "⌃⌘S",
            keywords: ["hide", "show", "navigation"]
        ) {
            NSApp.keyWindow?.firstResponder?.tryToPerform(
                #selector(NSSplitViewController.toggleSidebar(_:)),
                with: nil
            )
        })

        cmds.append(PaletteCommand(
            title: "Keyboard Shortcuts",
            subtitle: "Help",
            icon: "keyboard",
            shortcut: "?",
            keywords: ["help", "keys", "hotkeys"]
        ) {
            NotificationCenter.default.post(name: .showKeyboardHelp, object: nil)
        })

        #if DEBUG
        // MARK: Debug Commands

        cmds.append(PaletteCommand(
            title: "Performance Monitor",
            subtitle: "Debug",
            icon: "gauge",
            shortcut: "⇧⌘P",
            keywords: ["profiler", "metrics"]
        ) {
            // Handled via menu command
            NSApp.sendAction(Selector(("showPerformanceMonitor")), to: nil, from: nil)
        })

        cmds.append(PaletteCommand(
            title: "Design Audit",
            subtitle: "Debug",
            icon: "checkmark.seal",
            keywords: ["ui", "compliance"]
        ) {
            NotificationCenter.default.post(name: .navigateToSection, object: NavigationSection.designAudit)
        })
        #endif

        return cmds
    }

    func search(_ query: String) -> [PaletteCommand] {
        if query.isEmpty {
            return commands
        }
        return commands.filter { $0.matches(query) }
    }
}
