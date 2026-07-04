//
//  ShortcutsSettingsSection.swift
//  TalkieAgent
//
//  Shortcuts settings: hotkey configuration for recording modes
//

import SwiftUI
import TalkieKit

// MARK: - Shortcuts Settings Section

struct ShortcutsSettingsSection: View {
    @ObservedObject private var settings = LiveSettings.shared
    @StateObject private var captureShortcuts = CaptureShortcutsModel()
    @State private var isRecordingHotkey = false
    @State private var isRecordingPTTHotkey = false
    @State private var recordingCaptureKey: String?
    @State private var isRestoreHovered = false

    /// Check if any shortcuts have been modified from defaults
    private var hasModifiedShortcuts: Bool {
        settings.hotkey != .default ||
        settings.pttHotkey != .defaultPTT ||
        captureShortcuts.hasModifiedShortcuts
    }

    private var captureEnabled: Bool {
        if TalkieEnvironment.current == .production {
            return true
        }
        return TalkieSharedSettings.bool(forKey: AgentSettingsKey.featureCaptureEnabled)
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

                    Text("Recordings made while Talkie Agent is the active app are queued instead of auto-pasted. Use this shortcut to select and paste from your queue.")
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsCard(title: "CAPTURE") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if !captureEnabled {
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 11))
                            Text("Capture is disabled in this environment. Shortcuts are saved here, but Agent will not register them until Capture is enabled.")
                                .font(.system(size: 10))
                                .foregroundColor(TalkieTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                        .padding(.bottom, Spacing.xs)
                    }

                    captureShortcutRows(CaptureShortcuts.all)
                }
            }

            // Hotkey Registration Status
            SettingsCard(title: "HOTKEY STATUS") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Registration status only. Edit shortcuts in the sections above.")
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    let managers = AppDelegate.hotkeyManagers

                    if managers.isEmpty {
                        Text("No hotkeys loaded")
                            .font(.system(size: 10))
                            .foregroundColor(TalkieTheme.textTertiary)
                    } else {
                        ForEach(Array(managers.enumerated()), id: \.offset) { _, entry in
                            HStack(spacing: Spacing.sm) {
                                Circle()
                                    .fill(entry.manager.isRegistered ? Color.green : Color.red.opacity(0.7))
                                    .frame(width: 6, height: 6)

                                Text(entry.label)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(TalkieTheme.textPrimary)

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    if let display = hotkeyDisplay(for: entry.manager) {
                                        Text(display)
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(entry.manager.isRegistered ? TalkieTheme.textTertiary : .orange)
                                    }

                                    if !entry.manager.isRegistered {
                                        Text(registrationIssueText(for: entry.manager))
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(.red.opacity(0.8))
                                    }
                                }
                            }
                        }
                    }

                    let unregistered = managers.filter { !$0.manager.isRegistered }
                    if !unregistered.isEmpty {
                        Divider()
                            .background(Color.white.opacity(0.1))

                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 10))
                            Text("\(unregistered.count) hotkey\(unregistered.count == 1 ? "" : "s") not registered — try restarting Agent")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.orange)
                        }
                    }
                }
            }

            // Restore defaults (only show if shortcuts have been modified)
            if hasModifiedShortcuts {
                HStack {
                    Spacer()

                    Button(action: {
                        settings.hotkey = .default
                        settings.pttHotkey = .defaultPTT
                        captureShortcuts.restoreDefaults()
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
        .onAppear {
            captureShortcuts.reload()
        }
    }

    private func hotkeyDisplay(for manager: HotKeyManager) -> String? {
        let keyCode = manager.configuredKeyCode ?? manager.registeredKeyCode
        let modifiers = manager.configuredModifiers ?? manager.registeredModifiers
        guard let keyCode, let modifiers else { return nil }
        return HotkeyConfig(keyCode: keyCode, modifiers: modifiers).displayString
    }

    private func registrationIssueText(for manager: HotKeyManager) -> String {
        let keyCode = manager.configuredKeyCode ?? manager.registeredKeyCode
        let modifiers = manager.configuredModifiers ?? manager.registeredModifiers

        if let keyCode,
           let modifiers,
           SystemReservedHotkeys.isAppleScreenshotShortcut(keyCode: keyCode, modifiers: modifiers) {
            return "macOS may own this"
        }

        if let status = manager.lastRegistrationStatus {
            return "not registered (\(status))"
        }

        return "not registered"
    }

    @ViewBuilder
    private func captureShortcutRows(_ shortcuts: [CaptureShortcut]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(Array(shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                if index > 0 {
                    Rectangle()
                        .fill(Design.divider)
                        .frame(height: 0.5)
                }
                captureShortcutRow(shortcut)
            }
        }
    }

    private func captureShortcutRow(_ shortcut: CaptureShortcut) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(shortcut.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TalkieTheme.textPrimary)
                Text(shortcut.subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(TalkieTheme.textTertiary)
            }

            Spacer()

            HotkeyRecorderButton(
                hotkey: captureShortcuts.binding(for: shortcut),
                isRecording: Binding(
                    get: { recordingCaptureKey == shortcut.id },
                    set: { recordingCaptureKey = $0 ? shortcut.id : nil }
                ),
                showReset: false
            )
        }
    }
}
