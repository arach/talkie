//
//  MicrophoneSelectionMode.swift
//  TalkieKit
//
//  Defines how the microphone is selected for recording
//

import Foundation

/// How the microphone is selected for recording
///
/// - `systemDefault`: Always use the macOS system default input device.
///   Follows system changes automatically.
/// - `fixedUID`: Use a specific device by its persistent UID.
///   Falls back to system default if device is unavailable.
public enum MicrophoneSelectionMode: String, Codable, Sendable {
    /// Use the macOS system default input device
    case systemDefault

    /// Use a specific device by its persistent UID
    case fixedUID
}
