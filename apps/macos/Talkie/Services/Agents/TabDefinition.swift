//
//  TabDefinition.swift
//  Talkie
//
//  A single console tab preset: harness + model + prompt + env + cwd.
//

import Foundation
import TalkieKit

struct TabDefinition: Identifiable, Hashable, Sendable {
    let id: String
    var label: String
    var icon: String
    var order: Int
    var harness: TabHarness
    var model: String?
    var provider: String?
    var systemPrompt: String
    var cwd: String
    var launchArgs: [String]
    var readOnly: Bool
    var useTmux: Bool
    var tmuxSessionName: String?
    var env: [String: String]
    var shell: ShellConfig?
    var sourceURL: URL?

    struct ShellConfig: Hashable, Sendable {
        var program: String
        var initScript: String?
    }

    var isValid: Bool { true }

    var resolvedCwd: URL {
        URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath)
    }

    var symbolName: String {
        switch icon {
        case "sparkles", "terminal", "chevron.left.forwardslash.chevron.right",
             "apple.terminal", "wand.and.stars", "bolt", "gear",
             "doc.text.magnifyingglass":
            return icon
        default:
            return TabHarnessIcon.symbolName(for: harness)
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TabDefinition, rhs: TabDefinition) -> Bool {
        lhs.id == rhs.id
    }

    func structurallyEquals(_ other: TabDefinition) -> Bool {
        harness == other.harness &&
        model == other.model &&
        provider == other.provider &&
        systemPrompt == other.systemPrompt &&
        cwd == other.cwd &&
        launchArgs == other.launchArgs &&
        useTmux == other.useTmux &&
        tmuxSessionName == other.tmuxSessionName &&
        env == other.env &&
        shell?.program == other.shell?.program &&
        shell?.initScript == other.shell?.initScript
    }
}

enum TabHarness: String, CaseIterable, Codable, Hashable, Sendable {
    case claudeCode = "claude-code"
    case pi = "pi"
    case shell = "shell"
    case opencode = "opencode"

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .pi: "Pi"
        case .shell: "Shell"
        case .opencode: "OpenCode"
        }
    }

    var isAvailable: Bool {
        switch self {
        case .claudeCode:
            AgentHarnessProfile.claude.isAvailable
        case .pi:
            Self.locatePi() != nil
        case .shell:
            true
        case .opencode:
            AgentHarnessProfile.openCode.isAvailable
        }
    }

    var comingSoon: Bool {
        self == .opencode
    }

    static func locatePi() -> URL? {
        ExecutableResolver.resolve("pi")
    }
}

enum TabHarnessIcon {
    static func symbolName(for harness: TabHarness) -> String {
        switch harness {
        case .claudeCode: "sparkles"
        case .pi: "circle.grid.cross"
        case .shell: "apple.terminal"
        case .opencode: "terminal"
        }
    }
}
