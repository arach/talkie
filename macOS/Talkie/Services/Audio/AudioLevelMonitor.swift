//
//  AudioLevelMonitor.swift
//  Talkie
//
//  Real-time audio level monitoring for UI visualization
//  Adapted from TalkieLive
//

import Foundation
import Combine
import AppKit

@MainActor
final class AudioLevelMonitor: ObservableObject {
    static let shared = AudioLevelMonitor()

    @Published var level: Float = 0
    @Published var isSilent: Bool = false

    // Silent detection settings
    private let silenceThreshold: Float = 0.02
    private let silenceWindowSeconds: TimeInterval = 2.0
    private var silentSampleCount: Int = 0
    private var totalSampleCount: Int = 0
    private let samplesPerSecond: Int = 10

    private init() {}

    /// Call on each level update during recording
    func updateLevel(_ newLevel: Float, isRecording: Bool) {
        level = newLevel

        if isRecording {
            totalSampleCount += 1

            if newLevel < silenceThreshold {
                silentSampleCount += 1
            } else {
                // Reset if we get any audio
                silentSampleCount = 0
                if isSilent {
                    isSilent = false
                }
            }

            // Check if we've been silent for the window duration
            let windowSamples = Int(silenceWindowSeconds) * samplesPerSecond
            if silentSampleCount >= windowSamples && !isSilent {
                isSilent = true
                playAlertSound()
            }
        }
    }

    /// Reset silence tracking when recording starts/stops
    func resetSilenceTracking() {
        silentSampleCount = 0
        totalSampleCount = 0
        isSilent = false
    }

    private func playAlertSound() {
        // Play system alert sound
        NSSound.beep()
    }
}
