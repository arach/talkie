//
//  PaletteCommand.swift
//  Talkie macOS
//
//  Command model and registry for the command palette
//

import SwiftUI
import TalkieKit

// MARK: - Notification Names

extension NSNotification.Name {
    static let navigateToSection = NSNotification.Name("navigateToSection")
    static let showCommandPalette = NSNotification.Name("showCommandPalette")
    static let showContentSearch = NSNotification.Name("showContentSearch")
    static let showKeyboardHelp = NSNotification.Name("showKeyboardHelp")
    static let toggleKeyboardHintOverlay = NSNotification.Name("toggleKeyboardHintOverlay")
    static let showReportSheet = NSNotification.Name("showReportSheet")
}

// MARK: - Command Model

struct PaletteCommand: Identifiable {
    let id: String
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
        self.id = "\(subtitle)-\(title)".lowercased().replacingOccurrences(of: " ", with: "-")
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.shortcut = shortcut
        self.keywords = keywords
        self.action = action
    }

    /// Match query against title, subtitle, and keywords.
    /// Supports multi-word queries: each word must match somewhere.
    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }

        let tokens = trimmed.lowercased().split(separator: " ").map(String.init)
        let searchable = ([title, subtitle] + keywords).joined(separator: " ").lowercased()

        return tokens.allSatisfy { searchable.contains($0) }
    }
}

// MARK: - Palette Registration Protocol

/// Conform to this protocol to auto-register commands in the command palette.
/// NavigationSection and SettingsSection conform by default — any new section
/// with palette metadata automatically appears in the palette.
protocol PaletteRegistrable {
    var paletteTitle: String { get }
    var paletteSubtitle: String { get }
    var paletteIcon: String { get }
    var paletteShortcut: String? { get }
    var paletteKeywords: [String] { get }
    var paletteAction: () -> Void { get }
}

extension PaletteRegistrable {
    var paletteShortcut: String? { nil }
    var paletteKeywords: [String] { [] }
}

// MARK: - NavigationSection Auto-Registration

extension NavigationSection: PaletteRegistrable {
    /// All sections that should appear in the command palette.
    /// Add a case here = it shows up in the palette. Remove it = gone.
    static var paletteEntries: [NavigationSection] {
        var entries: [NavigationSection] = [
            .home, .recordings, .allMemos, .dictations,
            .drafts, .notes, .aiResults, .workflows,
            .liveDashboard, .models,
            .activityLog, .systemConsole, .settings,
        ]
        #if DEBUG
        entries += [.designHome, .designAudit, .designComponents]
        #endif
        return entries
    }

    var paletteTitle: String {
        switch self {
        case .home: return "Go to Home"
        case .recordings: return "Go to Library"
        case .allMemos: return "Go to Memos"
        case .dictations: return "Go to Dictations"
        case .drafts: return "Go to Compose"
        case .notes: return "Go to Notes"
        case .aiResults: return "Go to Actions"
        case .workflows: return "Go to Workflows"
        case .liveDashboard: return "Go to Stats"
        case .models: return "Go to Models"
        case .contextRules: return "Go to Context Rules"
        case .activityLog: return "Go to Activity Log"
        case .systemConsole: return "Go to Console"
        case .settings: return "Open Settings"
        #if DEBUG
        case .designHome: return "Design Home"
        case .designAudit: return "Design Audit"
        case .designComponents: return "Design Components"
        #endif
        default: return ""
        }
    }

    var paletteSubtitle: String {
        switch self {
        case .settings: return "App"
        #if DEBUG
        case .designHome, .designAudit, .designComponents: return "Debug"
        #endif
        default: return "Navigation"
        }
    }

    var paletteIcon: String {
        switch self {
        case .home: return "house"
        case .recordings: return "record.circle"
        case .allMemos: return "square.stack"
        case .dictations: return "waveform.badge.mic"
        case .drafts: return "square.and.pencil"
        case .notes: return "note.text"
        case .aiResults: return "chart.line.uptrend.xyaxis"
        case .workflows: return "wand.and.stars"
        case .liveDashboard: return "waveform.path.ecg"
        case .models: return "brain"
        case .contextRules: return "text.badge.star"
        case .activityLog: return "list.bullet.rectangle"
        case .systemConsole: return "terminal"
        case .settings: return "gear"
        #if DEBUG
        case .designHome: return "paintbrush"
        case .designAudit: return "checkmark.seal"
        case .designComponents: return "square.grid.2x2"
        #endif
        default: return "questionmark"
        }
    }

    var paletteShortcut: String? {
        switch self {
        case .settings: return "⌘,"
        default: return nil
        }
    }

    var paletteKeywords: [String] {
        switch self {
        case .home: return ["dashboard", "main"]
        case .recordings: return ["library", "all", "browse"]
        case .allMemos: return ["recordings", "voice"]
        case .dictations: return ["dictation", "utterances", "speech", "transcription"]
        case .drafts: return ["text", "editor", "compose", "drafts"]
        case .notes: return ["notes", "screenshots", "snippets"]
        case .aiResults: return ["ai", "results", "commands"]
        case .workflows: return ["automations", "pipelines"]
        case .liveDashboard: return ["stats", "insights"]
        case .models: return ["llm", "ai", "providers"]
        case .contextRules: return ["prompts", "apps", "rules"]
        case .activityLog: return ["events", "history"]
        case .systemConsole: return ["console", "terminal", "agent", "playground"]
        case .settings: return ["preferences", "config"]
        #if DEBUG
        case .designHome: return ["tokens", "theme"]
        case .designAudit: return ["ui", "compliance"]
        case .designComponents: return ["showcase", "library"]
        #endif
        default: return []
        }
    }

    var paletteAction: () -> Void {
        let section = self
        return {
            Task { @MainActor in NavigationState.shared.navigate(to: section) }
        }
    }
}

// MARK: - SettingsSection Auto-Registration

extension SettingsSection: PaletteRegistrable {
    static var paletteEntries: [SettingsSection] {
        [.context, .aiProviders, .appearance, .voiceIO]
    }

    var paletteTitle: String {
        switch self {
        case .context: return "Context Settings"
        case .aiProviders: return "API Keys"
        case .appearance: return "Appearance Settings"
        case .voiceIO: return "Dictation Settings"
        default: return "\(self) Settings"
        }
    }

    var paletteSubtitle: String { "Settings" }

    var paletteIcon: String {
        switch self {
        case .context: return "square.stack.3d.forward.dottedline"
        case .aiProviders: return "key"
        case .appearance: return "paintbrush"
        case .voiceIO: return "mic.and.signal.meter"
        default: return "gear"
        }
    }

    var paletteKeywords: [String] {
        switch self {
        case .context: return ["apps", "processing", "dictionary", "actions", "playground", "simulation"]
        case .aiProviders: return ["openai", "anthropic", "providers"]
        case .appearance: return ["theme", "colors", "dark", "light"]
        case .voiceIO: return ["voice", "hotkey", "capture"]
        default: return []
        }
    }

    var paletteAction: () -> Void {
        let section = self
        return {
            Task { @MainActor in NavigationState.shared.navigateToSettings(section) }
        }
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

        // MARK: Auto-registered navigation commands
        for section in NavigationSection.paletteEntries {
            guard !section.paletteTitle.isEmpty else { continue }
            cmds.append(PaletteCommand(
                title: section.paletteTitle,
                subtitle: section.paletteSubtitle,
                icon: section.paletteIcon,
                shortcut: section.paletteShortcut,
                keywords: section.paletteKeywords,
                action: section.paletteAction
            ))
        }

        // MARK: Auto-registered settings commands
        for section in SettingsSection.paletteEntries {
            cmds.append(PaletteCommand(
                title: section.paletteTitle,
                subtitle: section.paletteSubtitle,
                icon: section.paletteIcon,
                keywords: section.paletteKeywords,
                action: section.paletteAction
            ))
        }

        // MARK: Action commands (not tied to navigation)

        cmds.append(PaletteCommand(
            title: "Voice Command",
            subtitle: "Speak a navigation command",
            icon: "mic.fill",
            keywords: ["voice", "speak", "navigate", "command"]
        ) {
            Task { @MainActor in
                SettingsManager.shared.isCommandPalettePresented = false
                SettingsManager.shared.isVoiceCommandPresented = true
            }
        })

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

        if TalkieSharedSettings.bool(forKey: AgentSettingsKey.featureCaptureEnabled) {
            cmds.append(PaletteCommand(
                title: "Toggle Camera Bubble",
                subtitle: "Capture",
                icon: "video.circle",
                shortcut: "⇧⌘C",
                keywords: ["camera", "face", "video", "bubble", "loom", "webcam"]
            ) {
                Task { @MainActor in
                    CameraBubbleController.shared.toggle()
                }
            })
        }

        cmds.append(PaletteCommand(
            title: "Submit Report",
            subtitle: "Help & Feedback",
            icon: "exclamationmark.bubble",
            keywords: ["report", "bug", "feedback", "issue", "problem", "help", "support", "error", "broken", "crash"]
        ) {
            NotificationCenter.default.post(name: .showReportSheet, object: nil)
        })

        #if DEBUG
        cmds.append(PaletteCommand(
            title: "Performance Monitor",
            subtitle: "Debug",
            icon: "gauge",
            shortcut: "⇧⌘P",
            keywords: ["profiler", "metrics"]
        ) {
            NSApp.sendAction(Selector(("showPerformanceMonitor")), to: nil, from: nil)
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
