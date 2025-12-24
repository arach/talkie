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
    private let quickOpenService = QuickOpenService.shared

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "arrow.up.forward.app",
                title: "QUICK OPEN",
                subtitle: "Configure apps for quickly sending transcripts. Use ⌘1-⌘9 shortcuts to open content in your favorite apps."
            )
        } content: {
            // Enabled targets
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("ENABLED APPS")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                if quickOpenService.enabledTargets.isEmpty {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "app.badge.checkmark")
                            .foregroundColor(Theme.current.foregroundSecondary)
                        Text("No apps enabled")
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                    .font(Theme.current.fontSM)
                    .padding(Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)
                } else {
                    VStack(spacing: Spacing.xxs) {
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
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("AVAILABLE APPS")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                let disabledTargets = quickOpenService.targets.filter { !$0.isEnabled }
                if disabledTargets.isEmpty {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(SemanticColor.success)
                        Text("All apps are enabled")
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                    .font(Theme.current.fontSM)
                    .padding(Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)
                } else {
                    VStack(spacing: Spacing.xxs) {
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
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("HOW IT WORKS")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    infoRow(icon: "doc.on.clipboard", text: "Content is copied to clipboard")
                    infoRow(icon: "arrow.up.forward.app", text: "Target app is opened automatically")
                    infoRow(icon: "command", text: "Use ⌘1-⌘9 shortcuts for quick access")
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
        }
    }

    @ViewBuilder
    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(width: 16)

            Text(text)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
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
        HStack(spacing: Spacing.sm) {
            // Icon
            targetIcon
                .frame(width: 28, height: 28)
                .background(iconBackgroundColor)
                .cornerRadius(CornerRadius.xs)

            // Name
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(target.name)
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)

                Text(openMethodDescription)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
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
        .padding(Spacing.sm)
        .background(isHovered ? Theme.current.surfaceHover : Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var targetIcon: some View {
        if let bundleId = target.bundleId {
            AppIconView(bundleIdentifier: bundleId, size: 22)
                .opacity(target.isInstalled ? 1.0 : Opacity.strong)
        } else {
            Image(systemName: "app")
                .font(Theme.current.fontBody)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
    }

    private var iconBackgroundColor: Color {
        Color.clear // Real app icons don't need a background
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
            HStack(spacing: Spacing.xxs) {
                if let shortcut = currentShortcut {
                    Text("⌘\(shortcut)")
                        .font(Theme.current.fontXSMedium)
                        .foregroundColor(.accentColor)
                } else {
                    Text("—")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                Image(systemName: "chevron.down")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(Theme.current.foregroundSecondary.opacity(Opacity.light))
            .cornerRadius(CornerRadius.xs)
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
