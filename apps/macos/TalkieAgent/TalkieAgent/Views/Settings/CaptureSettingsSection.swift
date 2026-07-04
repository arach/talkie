//
//  CaptureSettingsSection.swift
//  TalkieAgent
//
//  Capture shortcuts: a configurable hotkey for each individual capture
//  action — the screenshot/recording HUD chords and the direct (no-HUD)
//  capture tools.
//
//  Each row writes its HotkeyConfig to the shared AgentSettingsKey that
//  AppDelegate.registerCaptureHotkeys reads, then HotkeyRecorderButton posts
//  .hotkeyDidChange so the agent re-registers from the value we just wrote.
//

import SwiftUI
import Carbon.HIToolbox
import TalkieKit

// MARK: - Capture action catalog

struct CaptureShortcut: Identifiable {
    /// The shared-settings key AppDelegate loads this hotkey from.
    let id: String
    let title: String
    let subtitle: String
    let defaultConfig: HotkeyConfig
}

enum CaptureShortcuts {
    /// The Hyper layer (⌃⌥⇧⌘) — the default modifier for every capture action.
    static let hyper = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    /// Chords that open the capture HUD on a given tab.
    static let chords: [CaptureShortcut] = [
        CaptureShortcut(
            id: AgentSettingsKey.captureChordHotkey,
            title: "Screenshot",
            subtitle: "Open the capture HUD on the screenshot tab",
            defaultConfig: HotkeyConfig(keyCode: 1, modifiers: hyper)   // Hyper+S
        ),
        CaptureShortcut(
            id: AgentSettingsKey.markupCaptureChordHotkey,
            title: "Screenshot to markup",
            subtitle: "Open the screenshot HUD with Markup already enabled",
            defaultConfig: HotkeyConfig(keyCode: 46, modifiers: hyper)  // Hyper+M
        ),
        CaptureShortcut(
            id: AgentSettingsKey.screenRecordChordHotkey,
            title: "Screen recording",
            subtitle: "Open the capture HUD on the recording tab",
            defaultConfig: HotkeyConfig(keyCode: 15, modifiers: hyper)  // Hyper+R
        ),
    ]

    /// Direct, no-HUD shortcuts that fire a capture tool without opening the HUD.
    static let direct: [CaptureShortcut] = [
        CaptureShortcut(
            id: "hotkeyCapture.fullscreen",
            title: "Fullscreen",
            subtitle: "Capture the whole screen immediately",
            defaultConfig: HotkeyConfig(keyCode: 20, modifiers: hyper)  // Hyper+3
        ),
        CaptureShortcut(
            id: "hotkeyCapture.region",
            title: "Region",
            subtitle: "Drag to capture a selection",
            defaultConfig: HotkeyConfig(keyCode: 21, modifiers: hyper)  // Hyper+4
        ),
        CaptureShortcut(
            id: "hotkeyCapture.window",
            title: "Window",
            subtitle: "Capture a single window",
            defaultConfig: HotkeyConfig(keyCode: 22, modifiers: hyper)  // Hyper+6
        ),
        CaptureShortcut(
            id: "hotkeyCapture.desktopMagnifier",
            title: "Desktop magnifier",
            subtitle: "Freeze a region and place a magnified copy on the desktop",
            defaultConfig: HotkeyConfig(keyCode: 6, modifiers: hyper)   // Hyper+Z
        ),
    ]

    static var all: [CaptureShortcut] { chords + direct }
}

// MARK: - Model

@MainActor
final class CaptureShortcutsModel: ObservableObject {
    @Published private var configs: [String: HotkeyConfig] = [:]

    init() { reload() }

    func reload() {
        var loaded: [String: HotkeyConfig] = [:]
        for shortcut in CaptureShortcuts.all {
            let rawConfig = Self.load(key: shortcut.id) ?? shortcut.defaultConfig
            let config = Self.sanitized(rawConfig, for: shortcut)
            loaded[shortcut.id] = config
            if config != rawConfig {
                Self.persist(config, key: shortcut.id)
            }
        }
        configs = loaded
    }

    func binding(for shortcut: CaptureShortcut) -> Binding<HotkeyConfig> {
        Binding(
            get: { [weak self] in self?.configs[shortcut.id] ?? shortcut.defaultConfig },
            set: { [weak self] newValue in self?.set(newValue, for: shortcut.id) }
        )
    }

    private func isModified(_ shortcut: CaptureShortcut) -> Bool {
        (configs[shortcut.id] ?? shortcut.defaultConfig) != shortcut.defaultConfig
    }

    var hasModifiedShortcuts: Bool {
        CaptureShortcuts.all.contains { isModified($0) }
    }

    func restoreDefaults() {
        for shortcut in CaptureShortcuts.all {
            configs[shortcut.id] = shortcut.defaultConfig
            Self.persist(shortcut.defaultConfig, key: shortcut.id)
        }
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
    }

    /// Writes the new config through to shared settings synchronously. The
    /// HotkeyRecorderButton posts .hotkeyDidChange immediately after this
    /// returns, so AppDelegate re-registers from the freshly-written value.
    private func set(_ config: HotkeyConfig, for key: String) {
        guard let shortcut = CaptureShortcuts.all.first(where: { $0.id == key }) else {
            configs[key] = config
            Self.persist(config, key: key)
            return
        }

        let sanitized = Self.sanitized(config, for: shortcut)
        configs[key] = sanitized
        Self.persist(sanitized, key: key)
    }

    private static func load(key: String) -> HotkeyConfig? {
        guard let data = TalkieSharedSettings.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotkeyConfig.self, from: data)
    }

    private static func persist(_ config: HotkeyConfig, key: String) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        TalkieSharedSettings.set(data, forKey: key)
    }

    private static func sanitized(_ config: HotkeyConfig, for shortcut: CaptureShortcut) -> HotkeyConfig {
        guard SystemReservedHotkeys.isAppleScreenshotShortcut(
            keyCode: config.keyCode,
            modifiers: config.modifiers
        ) else {
            return config
        }

        Log(.system).warning(
            "Saved Apple screenshot shortcut for capture; registration may fail if macOS still owns it",
            detail: "key=\(shortcut.id) keyCode=\(config.keyCode) modifiers=\(config.modifiers)"
        )
        return config
    }
}

// MARK: - Section

struct CaptureSettingsSection: View {
    @StateObject private var model = CaptureShortcutsModel()
    @ObservedObject private var settings = LiveSettings.shared
    @State private var recordingKey: String?

    private var captureEnabled: Bool {
        if TalkieEnvironment.current == .production {
            return true
        }
        return TalkieSharedSettings.bool(forKey: AgentSettingsKey.featureCaptureEnabled)
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "viewfinder",
                title: "CAPTURE",
                subtitle: "A shortcut for each capture action — the HUD chords and direct capture tools."
            )
        } content: {
            if !captureEnabled {
                captureDisabledNotice
            }

            SettingsCard(title: "SCREEN RECORDING") {
                screenRecordingSettings
            }

            SettingsCard(title: "CAPTURE HUD") {
                shortcutRows(CaptureShortcuts.chords)
            }

            SettingsCard(title: "DIRECT CAPTURE TOOLS") {
                shortcutRows(CaptureShortcuts.direct)
            }

            Text("Defaults use the Hyper layer (⌃⌥⇧⌘). Direct capture tools skip the HUD; screenshot rows fire immediately. A shortcut that collides with a HUD chord is skipped when hotkeys register.")
                .font(.system(size: 9))
                .foregroundColor(TalkieTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if model.hasModifiedShortcuts {
                restoreDefaultsButton
            }
        }
        .onAppear { model.reload() }
    }

    private var screenRecordingSettings: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("QUALITY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(TalkieTheme.textTertiary)

                HStack(spacing: Spacing.sm) {
                    ForEach(ScreenRecordingQualityPreset.allCases, id: \.self) { preset in
                        screenRecordingQualityButton(preset)
                    }
                }
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("COUNTDOWN")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(TalkieTheme.textTertiary)

                HStack(spacing: Spacing.sm) {
                    ForEach([0, 1, 3, 5], id: \.self) { seconds in
                        screenRecordingCountdownButton(seconds)
                    }
                }
            }

            Rectangle()
                .fill(Design.divider)
                .frame(height: 0.5)

            SettingsToggleRow(
                icon: "speaker.wave.2",
                title: "System audio",
                description: "Capture app and system audio in screen clips",
                isOn: $settings.screenRecordingIncludesSystemAudio
            )

            SettingsToggleRow(
                icon: "mic",
                title: "Microphone",
                description: "Add voiceover from the selected input device",
                isOn: $settings.screenRecordingIncludesMicrophone
            )

            SettingsToggleRow(
                icon: "video.circle",
                title: "Camera bubble",
                description: "Show the face camera bubble while screen recording",
                isOn: $settings.screenRecordingShowsCameraBubble
            )
        }
    }

    private func screenRecordingQualityButton(_ preset: ScreenRecordingQualityPreset) -> some View {
        let isSelected = settings.screenRecordingQualityPreset == preset

        return Button {
            settings.screenRecordingQualityPreset = preset
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isSelected ? TalkieTheme.textPrimary : TalkieTheme.textSecondary)

                Text("\(preset.bitrateSummary) / \(preset.fpsSummary)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(TalkieTheme.textTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(isSelected ? OpsTint.amber.color.opacity(0.14) : TalkieTheme.surfaceElevated.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .stroke(isSelected ? OpsTint.amber.color.opacity(0.35) : Design.divider, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func screenRecordingCountdownButton(_ seconds: Int) -> some View {
        let isSelected = settings.screenRecordingCountdownSeconds == seconds
        let title = seconds == 0 ? "Off" : "\(seconds)s"

        return Button {
            settings.screenRecordingCountdownSeconds = seconds
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isSelected ? TalkieTheme.textPrimary : TalkieTheme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .fill(isSelected ? OpsTint.amber.color.opacity(0.14) : TalkieTheme.surfaceElevated.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .stroke(isSelected ? OpsTint.amber.color.opacity(0.35) : Design.divider, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func shortcutRows(_ shortcuts: [CaptureShortcut]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(Array(shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                if index > 0 {
                    Rectangle()
                        .fill(Design.divider)
                        .frame(height: 0.5)
                }
                shortcutRow(shortcut)
            }
        }
    }

    private func shortcutRow(_ shortcut: CaptureShortcut) -> some View {
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
                hotkey: model.binding(for: shortcut),
                isRecording: recordingBinding(for: shortcut.id),
                showReset: false
            )
        }
    }

    private func recordingBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { recordingKey == key },
            set: { recordingKey = $0 ? key : nil }
        )
    }

    private var captureDisabledNotice: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 11))
                Text("Capture is currently disabled by a feature flag. Shortcuts here are saved but won’t fire until capture is enabled.")
                    .font(.system(size: 10))
                    .foregroundColor(TalkieTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        }
    }

    private var restoreDefaultsButton: some View {
        HStack {
            Spacer()

            RestoreCaptureDefaultsButton { model.restoreDefaults() }

            Spacer()
        }
        .padding(.top, Spacing.sm)
    }
}

private struct RestoreCaptureDefaultsButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10))
                Text("Restore Default Capture Shortcuts")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isHovered ? .white : TalkieTheme.textTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? TalkieTheme.surfaceElevated : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
