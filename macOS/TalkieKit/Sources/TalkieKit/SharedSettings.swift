//
//  SharedSettings.swift
//  TalkieKit
//
//  Shared settings storage for Talkie + TalkieLive
//  Both apps read/write to this shared location for settings sync
//

import Foundation

// MARK: - Shared Settings Storage

/// Shared UserDefaults suite name - derived from TalkieEnvironment
public var kTalkieSharedSuiteName: String {
    TalkieEnvironment.current.sharedSettingsSuite
}

/// Shared settings storage instance
/// Use this for all Live-related settings that need to sync between apps
public var TalkieSharedSettings: UserDefaults {
    UserDefaults(suiteName: TalkieEnvironment.current.sharedSettingsSuite) ?? .standard
}

// MARK: - Settings Keys

/// Sync-related settings keys
public enum SyncSettingsKey {
    public static let iCloudEnabled = "sync_icloud_enabled"
}

/// All settings keys used by LiveSettings
/// Centralized here to ensure consistency between Talkie and TalkieLive
public enum LiveSettingsKey {
    // MARK: Hotkeys
    public static let hotkey = "hotkey"
    public static let pttHotkey = "pttHotkey"
    public static let pttEnabled = "pttEnabled"

    // MARK: Model Selection
    public static let selectedModelId = "selectedModelId"
    public static let whisperModel = "whisperModel"  // Legacy, for migration

    // MARK: Routing & Output
    public static let routingMode = "routingMode"
    public static let returnToOriginAfterPaste = "returnToOriginAfterPaste"
    public static let pressEnterAfterPaste = "pressEnterAfterPaste"
    public static let primaryContextSource = "primaryContextSource"
    public static let contextCaptureDetail = "contextCaptureDetail"
    public static let autoScratchpadOnSelection = "autoScratchpadOnSelection"

    // MARK: Storage
    public static let utteranceTTLHours = "utteranceTTLHours"

    // MARK: Overlay & Pill
    public static let overlayStyle = "overlayStyle"
    public static let overlayPosition = "overlayPosition"
    public static let pillPosition = "pillPosition"
    public static let pillShowOnAllScreens = "pillShowOnAllScreens"
    public static let pillExpandsDuringRecording = "pillExpandsDuringRecording"
    public static let showOnAir = "showOnAir"

    // MARK: Sounds
    public static let startSound = "startSound"
    public static let finishSound = "finishSound"
    public static let pastedSound = "pastedSound"

    // MARK: Audio
    public static let selectedMicrophoneID = "selectedMicrophoneID"

    // MARK: Appearance (for TalkieLive standalone use)
    public static let appearanceMode = "appearanceMode"
    public static let visualTheme = "visualTheme"
    public static let fontSize = "fontSize"
    public static let accentColor = "accentColor"
    // glassMode removed - now a launch arg (--glass-mode)

    // MARK: Dictionary & Text Processing
    public static let dictionaryEnabled = "dictionaryEnabled"
    public static let fillerRemovalEnabled = "fillerRemovalEnabled"

    // MARK: Ambient Mode
    public static let ambientEnabled = "ambientEnabled"
    public static let ambientWakePhrase = "ambientWakePhrase"
    public static let ambientEndPhrase = "ambientEndPhrase"
    public static let ambientCancelPhrase = "ambientCancelPhrase"
    public static let ambientBufferDuration = "ambientBufferDuration"
    public static let ambientEnableChimes = "ambientEnableChimes"
    public static let ambientUseStreamingASR = "ambientUseStreamingASR"
    public static let ambientUseBatchASR = "ambientUseBatchASR"

    // MARK: Legacy
    public static let legacyTheme = "theme"
}

// MARK: - Migration Helper

/// Migrate a value from legacy UserDefaults.standard to shared settings
/// Returns the value (from shared if exists, else migrated from legacy)
public func migrateToSharedDefaults<T>(key: String, defaultValue: T) -> T {
    let shared = TalkieSharedSettings
    let legacy = UserDefaults.standard

    // Already in shared storage?
    if let value = shared.object(forKey: key) as? T {
        return value
    }

    // Migrate from legacy
    if let legacyValue = legacy.object(forKey: key) as? T {
        shared.set(legacyValue, forKey: key)
        legacy.removeObject(forKey: key)
        return legacyValue
    }

    // Use default
    return defaultValue
}

/// Migrate Data values (for Codable types like HotkeyConfig)
public func migrateDataToSharedDefaults(key: String) -> Data? {
    let shared = TalkieSharedSettings
    let legacy = UserDefaults.standard

    // Already in shared storage?
    if let value = shared.data(forKey: key) {
        return value
    }

    // Migrate from legacy
    if let legacyValue = legacy.data(forKey: key) {
        shared.set(legacyValue, forKey: key)
        legacy.removeObject(forKey: key)
        return legacyValue
    }

    return nil
}
