//
//  MemosSettings.swift
//  Talkie
//
//  Memos-specific settings
//

import SwiftUI

struct MemosSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager

    var body: some View {
        @Bindable var settings = settingsManager

        SettingsPageContainer {
            SettingsPageHeader(
                icon: "doc.text",
                title: "MEMOS",
                subtitle: "Configure memo display and behavior."
            )
        } content: {
            // MARK: - Display Options
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.blue)
                        .frame(width: 3, height: 14)

                    Text("DISPLAY")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()
                }

                VStack(spacing: 12) {
                    // Default sort order
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 16))
                            .foregroundColor(.blue)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Default Sort Order")
                                .font(Theme.current.fontSMMedium)
                            Text("How memos are sorted by default")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }

                        Spacer()

                        Picker("", selection: .constant("newest")) {
                            Text("Newest First").tag("newest")
                            Text("Oldest First").tag("oldest")
                            Text("By Title").tag("title")
                            Text("By Duration").tag("duration")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 130)
                    }
                    .padding(12)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)

                    // Show timestamps
                    HStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 16))
                            .foregroundColor(.orange)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Relative Timestamps")
                                .font(Theme.current.fontSMMedium)
                            Text("Show \"2 hours ago\" instead of exact times")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }

                        Spacer()

                        Toggle("", isOn: .constant(true))
                            .toggleStyle(.switch)
                            .tint(settingsManager.resolvedAccentColor)
                    }
                    .padding(12)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)
                }
            }
            .settingsSectionCard(padding: 16, cornerRadius: 8)

            // MARK: - Transcription Display
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple)
                        .frame(width: 3, height: 14)

                    Text("TRANSCRIPTION")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()
                }

                VStack(spacing: 12) {
                    // Show raw transcript
                    HStack(spacing: 12) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 16))
                            .foregroundColor(.purple)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show Raw Transcript")
                                .font(Theme.current.fontSMMedium)
                            Text("Display unprocessed transcript alongside cleaned version")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }

                        Spacer()

                        Toggle("", isOn: .constant(false))
                            .toggleStyle(.switch)
                            .tint(settingsManager.resolvedAccentColor)
                    }
                    .padding(12)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)

                    // Word-level timestamps
                    HStack(spacing: 12) {
                        Image(systemName: "clock.badge.checkmark")
                            .font(.system(size: 16))
                            .foregroundColor(.green)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Word-Level Timestamps")
                                .font(Theme.current.fontSMMedium)
                            Text("Show precise timing for each word (when available)")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }

                        Spacer()

                        Toggle("", isOn: .constant(false))
                            .toggleStyle(.switch)
                            .tint(settingsManager.resolvedAccentColor)
                    }
                    .padding(12)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)
                }
            }
            .settingsSectionCard(padding: 16, cornerRadius: 8)

            // MARK: - List Behavior
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.cyan)
                        .frame(width: 3, height: 14)

                    Text("LIST BEHAVIOR")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()
                }

                VStack(spacing: 12) {
                    // Confirm before delete
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 16))
                            .foregroundColor(.orange)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Confirm Before Delete")
                                .font(Theme.current.fontSMMedium)
                            Text("Ask for confirmation when deleting memos")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }

                        Spacer()

                        Toggle("", isOn: .constant(true))
                            .toggleStyle(.switch)
                            .tint(settingsManager.resolvedAccentColor)
                    }
                    .padding(12)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)

                    // Auto-select newest
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.cyan)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-Select Newest")
                                .font(Theme.current.fontSMMedium)
                            Text("Automatically select the newest memo when syncing")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }

                        Spacer()

                        Toggle("", isOn: .constant(false))
                            .toggleStyle(.switch)
                            .tint(settingsManager.resolvedAccentColor)
                    }
                    .padding(12)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)
                }
            }
            .settingsSectionCard(padding: 16, cornerRadius: 8)
        }
    }
}

#Preview {
    MemosSettingsView()
        .environment(SettingsManager.shared)
        .frame(width: 600, height: 700)
}
