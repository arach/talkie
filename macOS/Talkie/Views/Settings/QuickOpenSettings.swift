//
//  QuickOpenSettings.swift
//  Talkie
//
//  Settings for configuring Quick Open targets (external apps)
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "QuickOpenSettings")

// MARK: - Quick Open Settings View

struct QuickOpenSettingsView: View {
    @StateObject private var quickOpenService = QuickOpenService.shared

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "arrow.up.forward.app",
                title: "QUICK OPEN",
                subtitle: "Configure apps for quickly sending transcripts. Use ⌘1-⌘9 shortcuts to open content in your favorite apps."
            )
        } content: {
            // Enabled targets
            VStack(alignment: .leading, spacing: 12) {
                Text("ENABLED APPS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary)

                if quickOpenService.enabledTargets.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "app.badge.checkmark")
                            .foregroundColor(Theme.current.foregroundSecondary)
                        Text("No apps enabled")
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.current.surface1)
                    .cornerRadius(8)
                } else {
                    VStack(spacing: 4) {
                        ForEach(quickOpenService.enabledTargets) { target in
                            QuickOpenTargetRow(
                                target: target,
                                onToggle: { toggleTarget(target) },
                                onShortcutChange: { shortcut in setShortcut(target, shortcut: shortcut) }
                            )
                        }
                    }
                }
            }

            Divider()
                .background(Theme.current.divider)

            // Disabled targets
            VStack(alignment: .leading, spacing: 12) {
                Text("AVAILABLE APPS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary)

                let disabledTargets = quickOpenService.targets.filter { !$0.isEnabled }
                if disabledTargets.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                        Text("All apps are enabled")
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.current.surface1)
                    .cornerRadius(8)
                } else {
                    VStack(spacing: 4) {
                        ForEach(disabledTargets) { target in
                            QuickOpenTargetRow(
                                target: target,
                                onToggle: { toggleTarget(target) },
                                onShortcutChange: { shortcut in setShortcut(target, shortcut: shortcut) }
                            )
                        }
                    }
                }
            }

            Divider()
                .background(Theme.current.divider)

            // Info section
            VStack(alignment: .leading, spacing: 8) {
                Text("HOW IT WORKS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary)

                VStack(alignment: .leading, spacing: 6) {
                    infoRow(icon: "doc.on.clipboard", text: "Content is copied to clipboard")
                    infoRow(icon: "arrow.up.forward.app", text: "Target app is opened automatically")
                    infoRow(icon: "command", text: "Use ⌘1-⌘9 shortcuts for quick access")
                }
                .padding(12)
                .background(Theme.current.surface1)
                .cornerRadius(8)
            }
        }
    }

    @ViewBuilder
    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 16)

            Text(text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private func toggleTarget(_ target: QuickOpenTarget) {
        quickOpenService.toggleTarget(target.id, enabled: !target.isEnabled)
    }

    private func setShortcut(_ target: QuickOpenTarget, shortcut: Int?) {
        quickOpenService.setShortcut(target.id, shortcut: shortcut)
    }
}

// MARK: - Quick Open Target Row

private struct QuickOpenTargetRow: View {
    let target: QuickOpenTarget
    let onToggle: () -> Void
    let onShortcutChange: (Int?) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            targetIcon
                .frame(width: 28, height: 28)
                .background(iconBackgroundColor)
                .cornerRadius(6)

            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(target.name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)

                Text(openMethodDescription)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Keyboard shortcut picker
            if target.isEnabled {
                ShortcutPicker(
                    currentShortcut: target.keyboardShortcut,
                    onChange: onShortcutChange
                )
            }

            // Enable/disable toggle
            Toggle("", isOn: Binding(
                get: { target.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(10)
        .background(isHovered ? Theme.current.surfaceHover : Theme.current.surface1)
        .cornerRadius(8)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var targetIcon: some View {
        switch target.icon {
        case .asset(let name):
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)

        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 14))
                .foregroundColor(.secondary)

        case .initials(let text, let color):
            Text(text)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(color)
                .cornerRadius(4)
        }
    }

    private var iconBackgroundColor: Color {
        switch target.icon {
        case .initials(_, let color):
            return color.opacity(0.15)
        default:
            return Color.secondary.opacity(0.1)
        }
    }

    private var openMethodDescription: String {
        switch target.openMethod {
        case .urlScheme(let scheme):
            return "URL: \(scheme.prefix(20))..."
        case .bundleId(let bundleId):
            return bundleId
        case .applescript:
            return "AppleScript"
        case .custom:
            return "Custom command"
        }
    }
}

// MARK: - Shortcut Picker

private struct ShortcutPicker: View {
    let currentShortcut: Int?
    let onChange: (Int?) -> Void

    var body: some View {
        Menu {
            Button("None") {
                onChange(nil)
            }

            Divider()

            ForEach(1...9, id: \.self) { number in
                Button("⌘\(number)") {
                    onChange(number)
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let shortcut = currentShortcut {
                    Text("⌘\(shortcut)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.accentColor)
                } else {
                    Text("—")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(4)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - Preview

#Preview("Quick Open Settings") {
    QuickOpenSettingsView()
        .frame(width: 400, height: 600)
}
