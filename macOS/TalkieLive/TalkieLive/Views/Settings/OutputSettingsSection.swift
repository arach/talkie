//
//  OutputSettingsSection.swift
//  TalkieLive
//
//  Output settings: routing mode, paste options, context capture
//

import SwiftUI
import TalkieKit

// MARK: - Output Settings Section

struct OutputSettingsSection: View {
    @ObservedObject private var settings = LiveSettings.shared

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "arrow.right.doc.on.clipboard",
                title: "OUTPUT",
                subtitle: "Configure how transcribed text is delivered."
            )
        } content: {
            SettingsCard(title: "ROUTING MODE") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(RoutingMode.allCases, id: \.rawValue) { mode in
                        RoutingModeRow(
                            mode: mode,
                            isSelected: settings.routingMode == mode
                        ) {
                            settings.routingMode = mode
                        }
                    }
                }
            }

            // Paste options (only shown when paste mode is enabled)
            if settings.routingMode == .paste {
                SettingsCard(title: "PASTE OPTIONS") {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        SettingsToggleRow(
                            icon: "return",
                            title: "Press Enter after paste",
                            description: "Send Return key after pasting (for chat apps, terminals)",
                            isOn: $settings.pressEnterAfterPaste
                        )
                    }
                }
            }

            // Scratchpad options
            SettingsCard(title: "SCRATCHPAD") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SettingsToggleRow(
                        icon: "text.cursor",
                        title: "Auto-open with selection",
                        description: "When text is selected, open in Scratchpad to edit or transform it",
                        isOn: $settings.autoScratchpadOnSelection
                    )

                    if settings.autoScratchpadOnSelection {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 10))
                                .foregroundColor(TalkieTheme.textTertiary)
                            Text("Select text → press hotkey → dictate your edit")
                                .font(.system(size: 10))
                                .foregroundColor(TalkieTheme.textTertiary)
                        }
                        .padding(.leading, 24)
                    }
                }
            }

            // Context Settings - which app to show in history
            SettingsCard(title: "APP CONTEXT") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Which app to show in history")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(TalkieTheme.textTertiary)
                        .textCase(.uppercase)

                    ForEach(PrimaryContextSource.allCases, id: \.rawValue) { source in
                        PrimaryContextRow(
                            source: source,
                            isSelected: settings.primaryContextSource == source
                        ) {
                            settings.primaryContextSource = source
                        }
                    }
                }
            }

            SettingsCard(title: "CONTEXT CAPTURE") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Toggle(isOn: $settings.contextCaptureSessionAllowed) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Capture context this session")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(TalkieTheme.textPrimary)
                            Text("Front app, window titles, and (optionally) focused text. Resets when you quit Talkie Live.")
                                .font(.system(size: 9))
                                .foregroundColor(TalkieTheme.textTertiary)
                        }
                    }
                    .toggleStyle(.switch)

                    Text("Detail level")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(TalkieTheme.textTertiary)
                        .textCase(.uppercase)

                    ForEach(ContextCaptureDetail.allCases, id: \.rawValue) { detail in
                        ContextCaptureDetailRow(
                            detail: detail,
                            isSelected: settings.contextCaptureDetail == detail
                        ) {
                            settings.contextCaptureDetail = detail
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Primary Context Row

struct PrimaryContextRow: View {
    let source: PrimaryContextSource
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text(source.description)
                    .font(.system(size: 9))
                    .foregroundColor(TalkieTheme.textTertiary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? TalkieTheme.hover : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Context Capture Detail Row

struct ContextCaptureDetailRow: View {
    let detail: ContextCaptureDetail
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(detail.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text(detail.description)
                    .font(.system(size: 9))
                    .foregroundColor(TalkieTheme.textTertiary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? TalkieTheme.hover : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Routing Mode Row

struct RoutingModeRow: View {
    let mode: RoutingMode
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text(mode.description)
                    .font(.system(size: 9))
                    .foregroundColor(TalkieTheme.textTertiary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? TalkieTheme.hover : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}
