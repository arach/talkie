//
//  ShortcutsSettingsSection.swift
//  TalkieLive
//
//  Shortcuts settings: hotkey configuration for recording modes
//

import SwiftUI
import TalkieKit

// MARK: - Shortcuts Settings Section

struct ShortcutsSettingsSection: View {
    @ObservedObject private var settings = LiveSettings.shared
    @State private var isRecordingHotkey = false
    @State private var isRecordingPTTHotkey = false
    @State private var isRestoreHovered = false

    /// Check if any shortcuts have been modified from defaults
    private var hasModifiedShortcuts: Bool {
        settings.hotkey != .default || settings.pttHotkey != .defaultPTT
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "command",
                title: "SHORTCUTS",
                subtitle: "Global keyboard shortcuts for recording and dictation"
            )
        } content: {
            // Toggle mode shortcut
            SettingsCard(title: "TOGGLE RECORD") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Toggle Recording")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(TalkieTheme.textPrimary)
                            Text("Press to start, press again to stop and transcribe")
                                .font(.system(size: 9))
                                .foregroundColor(TalkieTheme.textTertiary)
                        }

                        Spacer()

                        HotkeyRecorderButton(
                            hotkey: $settings.hotkey,
                            isRecording: $isRecordingHotkey,
                            showReset: false
                        )
                    }

                    if isRecordingHotkey {
                        Text("Press any key combination with ⌘, ⌥, ⌃, or ⇧")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor.opacity(0.8))
                    }
                }
            }

            // Push-to-talk shortcut
            SettingsCard(title: "PUSH-TO-TALK") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Enable toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Push-to-Talk")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(TalkieTheme.textPrimary)
                            Text("Hold to record, release to stop and transcribe")
                                .font(.system(size: 9))
                                .foregroundColor(TalkieTheme.textTertiary)
                        }

                        Spacer()

                        Toggle("", isOn: $settings.pttEnabled)
                            .toggleStyle(.switch)
                            .tint(.accentColor)
                            .labelsHidden()
                    }

                    if settings.pttEnabled {
                        Divider()
                            .background(TalkieTheme.surfaceElevated)

                        HStack {
                            Text("PTT Shortcut")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(TalkieTheme.textSecondary)

                            Spacer()

                            HotkeyRecorderButton(
                                hotkey: $settings.pttHotkey,
                                isRecording: $isRecordingPTTHotkey,
                                showReset: false
                            )
                        }

                        if isRecordingPTTHotkey {
                            Text("Press any key combination with ⌘, ⌥, ⌃, or ⇧")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor.opacity(0.8))
                        }
                    }
                }
                .onChange(of: settings.pttEnabled) { _, _ in
                    // Notify to re-register hotkeys
                    NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
                }
            }

            // Queue Paste shortcut
            SettingsCard(title: "QUEUE PASTE") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Paste from Queue")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(TalkieTheme.textPrimary)
                            Text("Show picker to paste queued transcriptions")
                                .font(.system(size: 9))
                                .foregroundColor(TalkieTheme.textTertiary)
                        }

                        Spacer()

                        Text("⌥⌘V")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: CornerRadius.xs)
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                    }

                    Text("Recordings made while Talkie Live is the active app are queued instead of auto-pasted. Use this shortcut to select and paste from your queue.")
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Restore defaults (only show if shortcuts have been modified)
            if hasModifiedShortcuts {
                HStack {
                    Spacer()

                    Button(action: {
                        settings.hotkey = .default
                        settings.pttHotkey = .defaultPTT
                        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10))
                            Text("Restore Default Shortcuts")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(isRestoreHovered ? .white : TalkieTheme.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isRestoreHovered ? TalkieTheme.surfaceElevated : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { isRestoreHovered = $0 }

                    Spacer()
                }
                .padding(.top, Spacing.sm)
            }
        }
    }
}
