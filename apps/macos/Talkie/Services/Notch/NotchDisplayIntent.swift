//
//  NotchDisplayIntent.swift
//  Talkie
//
//  Priority-based intent system for the notch area.
//  Lower rawValue = higher priority. Highest-priority active intent wins.
//

import Foundation
import TalkieKit

// MARK: - Display Intent

enum NotchDisplayIntent: Int, Comparable, CaseIterable {
    case recording = 0       // Highest — Agent is recording/transcribing
    case cameraLoading = 1   // Camera session initializing
    case screenRecording = 2 // Screen recording stop pill
    case trayBadge = 3       // Tray has items
    case idle = 4            // Nothing active (lowest)

    static func < (lhs: NotchDisplayIntent, rhs: NotchDisplayIntent) -> Bool {
        lhs.rawValue < rhs.rawValue  // Lower rawValue = higher priority
    }
}

// MARK: - Intent Payload

/// Data associated with an active intent.
enum NotchIntentPayload {
    case recording(state: LiveState, audioLevel: Float, elapsedTime: TimeInterval)
    case cameraLoading
    case screenRecording(startTime: Date)
    case trayBadge(screenshotCount: Int, clipCount: Int)
    case idle
}
