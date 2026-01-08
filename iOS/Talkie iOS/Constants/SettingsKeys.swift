//
//  SettingsKeys.swift
//  Talkie iOS
//
//  Centralized UserDefaults keys for settings
//

import Foundation

/// Sync-related settings keys
/// Must match macOS TalkieKit.SyncSettingsKey for iCloud sync compatibility
enum SyncSettingsKey {
    static let iCloudEnabled = "sync_icloud_enabled"
}
