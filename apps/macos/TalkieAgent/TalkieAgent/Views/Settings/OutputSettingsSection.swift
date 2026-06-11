//
//  OutputSettingsSection.swift
//  TalkieAgent
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
                VStack(alignment: .leading, spacing: OpsSpacing.lg) {
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
                    VStack(alignment: .leading, spacing: OpsSpacing.lg) {
                        SettingsToggleRow(
                            icon: "return",
                            title: "Press Enter after paste",
                            description: "Send Return key after pasting (for chat apps, terminals)",
                            isOn: $settings.pressEnterAfterPaste
                        )
                    }
                }
            }

            SettingsCard(title: "SELECTION") {
                VStack(alignment: .leading, spacing: OpsSpacing.lg) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Selected text is replaced in place")
                            .font(OpsType.ui(OpsSize.xs, weight: .medium))
                            .foregroundStyle(OpsInk.ink)

                        Text("Highlight text, start dictation, and Talkie will overwrite the current selection when it pastes.")
                            .font(OpsType.ui(OpsSize.micro))
                            .foregroundStyle(OpsInk.dim)
                    }

                    HStack(spacing: OpsSpacing.xs) {
                        Image(systemName: "square.and.pencil")
                            .font(OpsType.ui(OpsSize.xxs))
                            .foregroundStyle(OpsInk.dim)
                        Text("Hold Shift while recording if you want to open Scratchpad instead.")
                            .font(OpsType.ui(OpsSize.xxs))
                            .foregroundStyle(OpsInk.dim)
                    }
                }
            }

            // Context Settings - which app to show in history
            SettingsCard(title: "APP CONTEXT") {
                VStack(alignment: .leading, spacing: OpsSpacing.lg) {
                    Text("Which app to show in history")
                        .font(OpsType.mono(OpsSize.micro, weight: .medium))
                        .foregroundStyle(OpsInk.dim)
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
                VStack(alignment: .leading, spacing: OpsSpacing.lg) {
                    Toggle(isOn: $settings.contextCaptureSessionAllowed) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Capture context this session")
                                .font(OpsType.ui(OpsSize.xs, weight: .medium))
                                .foregroundStyle(OpsInk.ink)
                            Text("Front app, window titles, and (optionally) focused text. Resets when you quit Talkie Agent.")
                                .font(OpsType.ui(OpsSize.micro))
                                .foregroundStyle(OpsInk.dim)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(OpsTint.amber.color)

                    Text("Detail level")
                        .font(OpsType.mono(OpsSize.micro, weight: .medium))
                        .foregroundStyle(OpsInk.dim)
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
                    .font(OpsType.ui(OpsSize.xs, weight: .medium))
                    .foregroundStyle(OpsInk.ink)

                Text(source.description)
                    .font(OpsType.ui(OpsSize.micro))
                    .foregroundStyle(OpsInk.dim)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(OpsTint.amber.color)
            }
        }
        .padding(OpsSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: OpsRadius.standard)
                .fill(isSelected ? OpsSurface.selected(OpsTint.amber.color) : (isHovered ? OpsSurface.hover : Color.clear))
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
                    .font(OpsType.ui(OpsSize.xs, weight: .medium))
                    .foregroundStyle(OpsInk.ink)

                Text(detail.description)
                    .font(OpsType.ui(OpsSize.micro))
                    .foregroundStyle(OpsInk.dim)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(OpsTint.amber.color)
            }
        }
        .padding(OpsSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: OpsRadius.standard)
                .fill(isSelected ? OpsSurface.selected(OpsTint.amber.color) : (isHovered ? OpsSurface.hover : Color.clear))
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
                    .font(OpsType.ui(OpsSize.xs, weight: .medium))
                    .foregroundStyle(OpsInk.ink)

                Text(mode.description)
                    .font(OpsType.ui(OpsSize.micro))
                    .foregroundStyle(OpsInk.dim)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(OpsTint.amber.color)
            }
        }
        .padding(OpsSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: OpsRadius.standard)
                .fill(isSelected ? OpsSurface.selected(OpsTint.amber.color) : (isHovered ? OpsSurface.hover : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}
