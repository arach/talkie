//
//  HotkeyRegistry.swift
//  Talkie
//
//  Unified hotkey registry — single source of truth for all configurable shortcuts.
//  Every action that can be triggered by a global hotkey is declared here.
//
//  Usage:
//    HotkeyRegistry.shared.config(for: .captureFullscreen)
//    HotkeyRegistry.shared.setConfig(.captureFullscreen, config)
//    HotkeyRegistry.shared.allActions  // introspect everything
//

import Foundation
import Carbon.HIToolbox
import TalkieKit

// MARK: - Hotkey Action

/// Every global-hotkey-able action in Talkie.
enum HotkeyAction: String, CaseIterable, Identifiable {
    // Recording
    case toggleRecording        // ⌥⌘L
    case pushToTalk             // ⌥⌘;

    // Capture — chords (open the HUD)
    case captureChord           // Hyper+S
    case screenRecordChord      // Hyper+R

    // Capture — direct actions
    case captureFullscreen      // ⌘⇧3
    case captureRegion          // ⌘⇧4
    case captureWindow          // ⌘⇧6
    case openTrayViewer         // ⌘⇧5
    case pasteLastScreenshot    // ⌘⇧V

    // Paste
    case pasteChord             // Hyper+V

    // Selection
    case selectionQuickAction   // ⌥⌘Y

    var id: String { rawValue }

    // MARK: - Display

    var label: String {
        switch self {
        case .toggleRecording:     return "Toggle Recording"
        case .pushToTalk:          return "Push to Talk"
        case .captureChord:        return "Screenshot HUD"
        case .screenRecordChord:   return "Screen Record HUD"
        case .captureFullscreen:   return "Fullscreen Capture"
        case .captureRegion:       return "Region Capture"
        case .captureWindow:       return "Window Capture"
        case .openTrayViewer:      return "Open Tray Viewer"
        case .pasteLastScreenshot: return "Paste Last Screenshot"
        case .pasteChord:          return "Quick Paste HUD"
        case .selectionQuickAction: return "Quick Selection"
        }
    }

    var group: HotkeyGroup {
        switch self {
        case .toggleRecording, .pushToTalk:
            return .recording
        case .captureChord, .screenRecordChord, .captureFullscreen, .captureRegion, .captureWindow, .openTrayViewer, .pasteLastScreenshot, .pasteChord:
            return .capture
        case .selectionQuickAction:
            return .selection
        }
    }

    // MARK: - Defaults

    var defaultConfig: HotkeyConfig {
        switch self {
        case .toggleRecording:
            return HotkeyConfig(keyCode: 37, modifiers: UInt32(cmdKey | optionKey))               // ⌥⌘L
        case .pushToTalk:
            return HotkeyConfig(keyCode: 41, modifiers: UInt32(cmdKey | optionKey))               // ⌥⌘;
        case .captureChord:
            return .defaultCaptureChord                                                            // Hyper+S
        case .screenRecordChord:
            return .defaultScreenRecordChord                                                       // Hyper+R
        case .pasteChord:
            return .defaultPasteChord                                                              // Hyper+V
        case .captureFullscreen:
            return HotkeyConfig(keyCode: 20, modifiers: UInt32(cmdKey | shiftKey))                // ⌘⇧3
        case .captureRegion:
            return HotkeyConfig(keyCode: 21, modifiers: UInt32(cmdKey | shiftKey))                // ⌘⇧4
        case .captureWindow:
            return HotkeyConfig(keyCode: 22, modifiers: UInt32(cmdKey | shiftKey))                // ⌘⇧6
        case .openTrayViewer:
            return HotkeyConfig(keyCode: 23, modifiers: UInt32(cmdKey | shiftKey))                // ⌘⇧5
        case .pasteLastScreenshot:
            return HotkeyConfig(keyCode: 9, modifiers: UInt32(cmdKey | shiftKey))                 // ⌘⇧V
        case .selectionQuickAction:
            return .defaultSelectionQuick                                                           // ⌥⌘Y
        }
    }

    // MARK: - Storage

    /// UserDefaults key in TalkieSharedSettings.
    var storageKey: String {
        switch self {
        case .toggleRecording:      return AgentSettingsKey.hotkey
        case .pushToTalk:           return AgentSettingsKey.pttHotkey
        case .captureChord:         return AgentSettingsKey.captureChordHotkey
        case .screenRecordChord:    return AgentSettingsKey.screenRecordChordHotkey
        case .pasteChord:           return AgentSettingsKey.pasteChordHotkey
        case .pasteLastScreenshot:  return AgentSettingsKey.pasteLastScreenshotHotkey
        case .selectionQuickAction: return AgentSettingsKey.selectionQuickHotkey
        // New keys for direct capture shortcuts
        case .captureFullscreen:    return "hotkeyCapture.fullscreen"
        case .captureRegion:        return "hotkeyCapture.region"
        case .captureWindow:        return "hotkeyCapture.window"
        case .openTrayViewer:       return "hotkeyCapture.trayViewer"
        }
    }
}

// MARK: - Groups

enum HotkeyGroup: String, CaseIterable, Identifiable {
    case recording
    case capture
    case selection

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recording:  return "RECORDING"
        case .capture:    return "CAPTURE"
        case .selection:  return "SELECTION"
        }
    }

    var actions: [HotkeyAction] {
        HotkeyAction.allCases.filter { $0.group == self }
    }
}

// MARK: - Registry

@MainActor
@Observable
final class HotkeyRegistry {
    static let shared = HotkeyRegistry()

    private var configs: [HotkeyAction: HotkeyConfig] = [:]
    private let storage = TalkieSharedSettings

    private init() {
        // Load all configs from storage, falling back to defaults
        for action in HotkeyAction.allCases {
            if let data = storage.data(forKey: action.storageKey),
               let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
                configs[action] = config
            } else {
                configs[action] = action.defaultConfig
            }
        }
    }

    // MARK: - Read

    func config(for action: HotkeyAction) -> HotkeyConfig {
        configs[action] ?? action.defaultConfig
    }

    /// All registered actions and their current configs.
    var allActions: [(action: HotkeyAction, config: HotkeyConfig)] {
        HotkeyAction.allCases.map { ($0, config(for: $0)) }
    }

    /// Actions within a specific group.
    func actions(in group: HotkeyGroup) -> [(action: HotkeyAction, config: HotkeyConfig)] {
        group.actions.map { ($0, config(for: $0)) }
    }

    // MARK: - Write

    func setConfig(_ action: HotkeyAction, _ config: HotkeyConfig) {
        configs[action] = config
        if let data = try? JSONEncoder().encode(config) {
            storage.set(data, forKey: action.storageKey)
        }
        // Sync back to AgentSettings for actions it manages
        syncToAgentSettings(action, config)
        NotificationCenter.default.post(name: .hotkeyDidChange, object: action.rawValue)
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("to.talkie.app.agentHotkeysDidChange"),
            object: action.rawValue,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    func resetToDefault(_ action: HotkeyAction) {
        setConfig(action, action.defaultConfig)
    }

    func isDefault(_ action: HotkeyAction) -> Bool {
        config(for: action) == action.defaultConfig
    }

    // MARK: - Binding helper for SwiftUI

    func binding(for action: HotkeyAction) -> (get: HotkeyConfig, set: (HotkeyConfig) -> Void) {
        (
            get: config(for: action),
            set: { [weak self] newConfig in self?.setConfig(action, newConfig) }
        )
    }

    // MARK: - Lookup

    /// Find which action matches a given keyCode + modifiers, if any.
    func action(forKeyCode keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> HotkeyAction? {
        let cleaned = modifiers.intersection(.deviceIndependentFlagsMask)
        return HotkeyAction.allCases.first { action in
            let cfg = config(for: action)
            return cfg.keyCode == UInt32(keyCode) && cfg.nsModifierFlags == cleaned
        }
    }

    // MARK: - Private

    private func syncToAgentSettings(_ action: HotkeyAction, _ config: HotkeyConfig) {
        let settings = AgentSettings.shared
        switch action {
        case .toggleRecording:      settings.hotkey = config
        case .pushToTalk:           settings.pttHotkey = config
        case .captureChord:         settings.captureChordHotkey = config
        case .screenRecordChord:    settings.screenRecordChordHotkey = config
        case .selectionQuickAction: settings.selectionQuickHotkey = config
        default: break // Direct capture shortcuts are new — not in AgentSettings
        }
    }
}
