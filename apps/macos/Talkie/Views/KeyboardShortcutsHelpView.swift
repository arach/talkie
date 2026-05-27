//
//  KeyboardShortcutsHelpView.swift
//  Talkie macOS
//
//  Keyboard shortcuts: ? opens this sheet (Navigation-first); ⌘⇧? / ⌃⇧? toggles corner hints.
//

import SwiftUI

// MARK: - Catalog

private enum KeyboardShortcutCatalog {
    /// Primary sheet tab — what you need for moving around and acting on lists.
    static let navigationTabSections: [(title: String, icon: String, items: [ShortcutItem])] = [
        (
            "Lists & focus",
            "list.bullet",
            [
                ShortcutItem(keys: "J", description: "Move down"),
                ShortcutItem(keys: "K", description: "Move up"),
                ShortcutItem(keys: "O", description: "Open selection"),
                ShortcutItem(keys: "↑↓", description: "Navigate rows"),
                ShortcutItem(keys: "⇧↑↓", description: "Extend selection"),
                ShortcutItem(keys: "↵", description: "Open item"),
                ShortcutItem(keys: "⇥", description: "Next section"),
                ShortcutItem(keys: "⇧⇥", description: "Previous section"),
                ShortcutItem(keys: "⌘A", description: "Select all"),
            ]
        ),
        (
            "Go to",
            "arrow.turn.up.right",
            [
                ShortcutItem(keys: "C", description: "Compose"),
                ShortcutItem(keys: "R", description: "Record"),
                ShortcutItem(keys: "D", description: "Dictations"),
                ShortcutItem(keys: "N", description: "Notes"),
                ShortcutItem(keys: "S", description: "Screenshots"),
            ]
        ),
        (
            "Search & commands",
            "command",
            [
                ShortcutItem(keys: "⌥⌘K", description: "Command palette"),
                ShortcutItem(keys: "⌥⌘K → type", description: "Jump to a screen"),
                ShortcutItem(keys: "⇧⌘V", description: "Voice command"),
                ShortcutItem(keys: "⌥⌘L", description: "Toggle dictation"),
                ShortcutItem(keys: "⌃⌥⇧⌘F", description: "Paste last screenshot"),
                ShortcutItem(keys: "⌘,", description: "Settings"),
                ShortcutItem(keys: "⌃⌘S", description: "Toggle sidebar"),
            ]
        ),
        (
            "Windows & history",
            "arrow.uturn.backward",
            [
                ShortcutItem(keys: "⌘[", description: "Back"),
                ShortcutItem(keys: "⌘]", description: "Forward"),
            ]
        ),
        (
            "Help",
            "questionmark.circle",
            [
                ShortcutItem(keys: "?", description: "This cheat sheet"),
                ShortcutItem(keys: "⌘⇧?", description: "Shortcut hints (corner)"),
                ShortcutItem(keys: "⌃⇧?", description: "Shortcut hints (corner)"),
            ]
        ),
    ]

    static let allShortcutsScroll: [(title: String, icon: String, items: [ShortcutItem])] = [
        (
            "Quick actions",
            "bolt",
            [
                ShortcutItem(keys: "C", description: "Compose"),
                ShortcutItem(keys: "R", description: "Record"),
                ShortcutItem(keys: "D", description: "Dictations"),
                ShortcutItem(keys: "N", description: "Notes"),
                ShortcutItem(keys: "S", description: "Screenshots"),
                ShortcutItem(keys: "J", description: "Navigate down"),
                ShortcutItem(keys: "K", description: "Navigate up"),
                ShortcutItem(keys: "O", description: "Open selected item"),
                ShortcutItem(keys: "?", description: "This cheat sheet"),
            ]
        ),
        (
            "Global",
            "globe",
            [
                ShortcutItem(keys: "⌥⌘K", description: "Command palette"),
                ShortcutItem(keys: "⇧⌘V", description: "Voice command"),
                ShortcutItem(keys: "⌥⌘L", description: "Toggle dictation"),
                ShortcutItem(keys: "⌃⌥⇧⌘F", description: "Paste last screenshot"),
                ShortcutItem(keys: "⌘,", description: "Settings"),
                ShortcutItem(keys: "⌃⌘S", description: "Toggle sidebar"),
            ]
        ),
        (
            "Navigation",
            "arrow.triangle.branch",
            [
                ShortcutItem(keys: "⌥⌘K → type", description: "Jump to any section"),
                ShortcutItem(keys: "⌘[", description: "Go back"),
                ShortcutItem(keys: "⌘]", description: "Go forward"),
            ]
        ),
        (
            "List navigation",
            "list.bullet",
            [
                ShortcutItem(keys: "↑↓", description: "Navigate items"),
                ShortcutItem(keys: "⇧↑↓", description: "Extend selection"),
                ShortcutItem(keys: "↵", description: "Open selected item"),
                ShortcutItem(keys: "⌘A", description: "Select all"),
                ShortcutItem(keys: "⇥", description: "Next section"),
                ShortcutItem(keys: "⇧⇥", description: "Previous section"),
            ]
        ),
        (
            "Editing",
            "pencil",
            [
                ShortcutItem(keys: "⌘↵", description: "Save"),
                ShortcutItem(keys: "⎋", description: "Cancel / close"),
                ShortcutItem(keys: "⇥", description: "Next field"),
                ShortcutItem(keys: "⇧⇥", description: "Previous field"),
            ]
        ),
        (
            "Quick open",
            "arrow.up.forward.app",
            [
                ShortcutItem(keys: "⌘1-9", description: "Open in configured app"),
            ]
        ),
    ]

    /// Compact rows for the non-modal corner panel.
    static let inlineHintRows: [ShortcutItem] = [
        ShortcutItem(keys: "J K O", description: "List move / open"),
        ShortcutItem(keys: "↑↓ ↵", description: "List navigate"),
        ShortcutItem(keys: "C R D N S", description: "Jump screens"),
        ShortcutItem(keys: "⌥⌘K", description: "Command palette"),
        ShortcutItem(keys: "?", description: "Cheat sheet"),
        ShortcutItem(keys: "⌘⇧?", description: "These hints"),
    ]
}

// MARK: - Help sheet

private enum KeyboardHelpTab: String, CaseIterable, Identifiable {
    case navigation = "Navigation"
    case all = "All shortcuts"

    var id: String { rawValue }
}

struct KeyboardShortcutsHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var helpTab: KeyboardHelpTab = .navigation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.current.foreground)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Theme.current.foregroundMuted)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(Spacing.lg)
            .background(Theme.current.backgroundSecondary)

            Picker("View", selection: $helpTab) {
                ForEach(KeyboardHelpTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    switch helpTab {
                    case .navigation:
                        Text("Use these when a list or the main window is focused—no need to open the full reference.")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.current.foregroundSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(Array(KeyboardShortcutCatalog.navigationTabSections.enumerated()), id: \.offset) { _, section in
                            ShortcutSection(title: section.title, icon: section.icon, shortcuts: section.items)
                        }

                    case .all:
                        ForEach(Array(KeyboardShortcutCatalog.allShortcutsScroll.enumerated()), id: \.offset) { _, section in
                            ShortcutSection(title: section.title, icon: section.icon, shortcuts: section.items)
                        }

                        #if DEBUG
                        ShortcutSection(
                            title: "Debug",
                            icon: "ant",
                            shortcuts: [
                                ShortcutItem(keys: "⇧⌘T", description: "E2E trace viewer"),
                            ]
                        )
                        #endif
                    }
                }
                .padding(Spacing.lg)
            }
        }
        .frame(
            minWidth: 420, idealWidth: 560, maxWidth: 760,
            minHeight: 520, idealHeight: 680, maxHeight: 880
        )
        .background(Theme.current.background)
    }
}

// MARK: - Corner hint panel

struct KeyboardHintOverlay: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shortcut hints")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.current.foreground)
                    Text("Stays on screen while you work. ⌘⇧? or ⌃⇧? toggles.")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.current.foregroundMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Spacing.sm)

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.current.foregroundMuted)
                }
                .buttonStyle(.plain)
                .help("Hide hints")
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(KeyboardShortcutCatalog.inlineHintRows) { item in
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.description)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.current.foreground)

                        Spacer(minLength: 8)

                        KeyboardShortcutBadge(keys: item.keys)
                    }
                }
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(Theme.current.backgroundSecondary)
            )
        }
        .padding(Spacing.md)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Theme.current.surface1)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .strokeBorder(Theme.current.border.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Keyboard shortcut hints")
    }
}

// MARK: - Shortcut Section

private struct ShortcutSection: View {
    let title: String
    let icon: String
    let shortcuts: [ShortcutItem]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.current.accent)

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            VStack(spacing: Spacing.xs) {
                ForEach(shortcuts) { shortcut in
                    ShortcutRow(item: shortcut)
                }
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(Theme.current.backgroundSecondary)
            )
        }
    }
}

// MARK: - Shortcut Item

private struct ShortcutItem: Identifiable {
    var id: String { "\(keys)|\(description)" }
    let keys: String
    let description: String
}

private struct ShortcutRow: View {
    let item: ShortcutItem

    var body: some View {
        HStack {
            Text(item.description)
                .font(.system(size: 13))
                .foregroundColor(Theme.current.foreground)

            Spacer()

            KeyboardShortcutBadge(keys: item.keys)
        }
    }
}

// MARK: - Keyboard Shortcut Badge

private struct KeyboardShortcutBadge: View {
    let keys: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(parseKeys(keys).enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.current.backgroundTertiary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Theme.current.border, lineWidth: 0.5)
                    )
            }
        }
    }

    private func parseKeys(_ keys: String) -> [String] {
        var result: [String] = []
        var current = ""

        for char in keys {
            if "⌘⌥⌃⇧".contains(char) {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                result.append(String(char))
            } else if char == " " || char == "+" {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }

        if !current.isEmpty {
            result.append(current)
        }

        return result.isEmpty ? [keys] : result
    }
}

#Preview("Sheet") {
    KeyboardShortcutsHelpView()
}

#Preview("Hints") {
    KeyboardHintOverlay(onClose: {})
        .padding()
        .background(Color.black.opacity(0.5))
}
