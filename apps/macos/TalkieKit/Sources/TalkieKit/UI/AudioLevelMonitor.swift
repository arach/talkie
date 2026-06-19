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

    private let recordingPublishInterval: TimeInterval = 1.0 / 60.0
    private let idlePublishInterval: TimeInterval = 1.0 / 15.0
    private let minimumLevelDelta: Float = 0.002
    private var lastPublishedLevel: Float = 0
    private var lastPublishTime: TimeInterval = 0

    private init() {}

    /// Update the audio level for UI visualization
    /// Note: Silence detection is handled by AudioCaptureService which sets isSilent directly
    public func updateLevel(_ newLevel: Float, isRecording: Bool) {
        let clampedLevel = min(1, max(0, newLevel))
        let now = ProcessInfo.processInfo.systemUptime
        let interval = isRecording ? recordingPublishInterval : idlePublishInterval
        let elapsed = now - lastPublishTime

        guard clampedLevel == 0 || elapsed >= interval else { return }
        guard clampedLevel == 0 || abs(clampedLevel - lastPublishedLevel) >= minimumLevelDelta else { return }

        lastPublishTime = now
        lastPublishedLevel = clampedLevel
        level = clampedLevel
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
