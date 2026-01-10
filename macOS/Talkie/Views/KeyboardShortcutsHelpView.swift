//
//  KeyboardShortcutsHelpView.swift
//  Talkie macOS
//
//  Keyboard shortcuts reference overlay
//

import SwiftUI

struct KeyboardShortcutsHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
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

            Divider()

            // Shortcuts content
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    ShortcutSection(
                        title: "Global",
                        icon: "globe",
                        shortcuts: [
                            ShortcutItem(keys: "⌥⌘K", description: "Command Palette"),
                            ShortcutItem(keys: "⌘,", description: "Settings"),
                            ShortcutItem(keys: "⌃⌘S", description: "Toggle Sidebar"),
                            ShortcutItem(keys: "?", description: "This Help"),
                        ]
                    )

                    ShortcutSection(
                        title: "Navigation",
                        icon: "arrow.triangle.branch",
                        shortcuts: [
                            ShortcutItem(keys: "⌥⌘K → type", description: "Jump to any section"),
                            ShortcutItem(keys: "⌘[", description: "Go Back"),
                            ShortcutItem(keys: "⌘]", description: "Go Forward"),
                        ]
                    )

                    ShortcutSection(
                        title: "List Navigation",
                        icon: "list.bullet",
                        shortcuts: [
                            ShortcutItem(keys: "↑↓", description: "Navigate items"),
                            ShortcutItem(keys: "⇧↑↓", description: "Extend selection"),
                            ShortcutItem(keys: "↵", description: "Open selected item"),
                            ShortcutItem(keys: "⌘A", description: "Select all"),
                            ShortcutItem(keys: "⇥", description: "Next section"),
                            ShortcutItem(keys: "⇧⇥", description: "Previous section"),
                        ]
                    )

                    ShortcutSection(
                        title: "Editing",
                        icon: "pencil",
                        shortcuts: [
                            ShortcutItem(keys: "⌘↵", description: "Save"),
                            ShortcutItem(keys: "⎋", description: "Cancel / Close"),
                            ShortcutItem(keys: "⇥", description: "Next Field"),
                            ShortcutItem(keys: "⇧⇥", description: "Previous Field"),
                        ]
                    )

                    ShortcutSection(
                        title: "Quick Open",
                        icon: "arrow.up.forward.app",
                        shortcuts: [
                            ShortcutItem(keys: "⌘1-9", description: "Open in configured app"),
                        ]
                    )

                    #if DEBUG
                    ShortcutSection(
                        title: "Debug",
                        icon: "ant",
                        shortcuts: [
                            ShortcutItem(keys: "⇧⌘P", description: "Performance Monitor"),
                            ShortcutItem(keys: "⇧⌘T", description: "E2E Trace Viewer"),
                        ]
                    )
                    #endif
                }
                .padding(Spacing.lg)
            }
        }
        .frame(width: 400, height: 500)
        .background(Theme.current.background)
    }
}

// MARK: - Shortcut Section

private struct ShortcutSection: View {
    let title: String
    let icon: String
    let shortcuts: [ShortcutItem]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Section header
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

            // Shortcuts list
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
    let id = UUID()
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
        // Split compound shortcuts like "⌥⌘K" into ["⌥", "⌘", "K"]
        // But keep things like "↵" or "⎋" as single keys
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

#Preview {
    KeyboardShortcutsHelpView()
}
