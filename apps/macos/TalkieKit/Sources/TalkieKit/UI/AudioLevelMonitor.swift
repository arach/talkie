//
//  AudioLevelMonitor.swift
//  TalkieKit
//
//  Real-time audio level monitoring for UI visualization
//

import Foundation
import Combine
import AppKit

@MainActor
public final class AudioLevelMonitor: ObservableObject {
    public static let shared = AudioLevelMonitor()

    @Published public var level: Float = 0
    @Published public var isSilent: Bool = false

    private init() {}

    /// Update the audio level for UI visualization
    /// Note: Silence detection is handled by AudioCaptureService which sets isSilent directly
    public func updateLevel(_ newLevel: Float, isRecording: Bool) {
        level = newLevel
    }

    /// Reset silence tracking when recording starts/stops
    public func resetSilenceTracking() {
        isSilent = false
    }

    /// Refresh the current microphone name (no-op placeholder for API compatibility)
    public func refreshMicName() {
        // No-op - microphone name is managed elsewhere
    }
}
