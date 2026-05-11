//
//  TalkieObjectTypes.swift
//  TalkieKit
//
//  Enums and filter/sort types for TalkieObject.
//  Shared across all targets: main app, Agent, CLI.
//

import Foundation
import SwiftUI

// MARK: - TalkieObject Type

/// Determines behavior: sync, TTL, AI processing, editability
public enum TalkieObjectType: String, Codable, CaseIterable, Sendable {
    case memo       // Syncs to CloudKit, no TTL, AI available, editable
    case dictation  // Local only, TTL cleanup, no AI, read-only
    case note       // Local only, no TTL, AI available, editable, promotable to memo
    case segment    // Child of a note — local, no TTL, invisible in lists
    case selection  // Local only, TTL cleanup, read-only — captured via Quick Selection
    case capture    // Local only, no TTL, editable — screenshot + optional OCR/user text

    public var displayName: String {
        switch self {
        case .memo: return "Memo"
        case .dictation: return "Dictation"
        case .note: return "Note"
        case .segment: return "Segment"
        case .selection: return "Selection"
        case .capture: return "Capture"
        }
    }

    public var icon: String {
        switch self {
        case .memo: return "doc.text"
        case .dictation: return "waveform"
        case .note: return "note.text"
        case .segment: return "waveform.badge.plus"
        case .selection: return "tray.and.arrow.down"
        case .capture: return "camera.viewfinder"
        }
    }
}

// MARK: - Recording Source

/// Provenance: where the recording originated (immutable)
public enum RecordingSource: String, Codable, CaseIterable, Sendable {
    case mac        // Recorded on Mac via Talkie
    case iphone     // Recorded on iPhone
    case watch      // Recorded on Apple Watch
    case live       // Recorded via TalkieAgent (always-on dictation)

    public var displayName: String {
        switch self {
        case .mac: return "Mac"
        case .iphone: return "iPhone"
        case .watch: return "Watch"
        case .live: return "Agent"
        }
    }

    public var icon: String {
        switch self {
        case .mac: return "desktopcomputer"
        case .iphone: return "iphone"
        case .watch: return "applewatch"
        case .live: return "waveform.circle.fill"
        }
    }

    public var color: Color {
        switch self {
        case .mac: return .purple
        case .iphone: return .blue
        case .watch: return .orange
        case .live: return .cyan
        }
    }

    /// Parse from legacy originDeviceId string
    public static func from(originDeviceId: String?) -> RecordingSource {
        guard let id = originDeviceId, !id.isEmpty else {
            return .mac // Default to mac for unknown
        }

        if id.hasPrefix("watch-") { return .watch }
        if id.hasPrefix("mac-") { return .mac }
        if id.hasPrefix("live-") { return .live }

        // No prefix = iPhone (legacy format)
        return .iphone
    }
}

// MARK: - Transcription Status

public enum RecordingTranscriptionStatus: String, Codable, CaseIterable, Sendable {
    case pending    // Audio saved, transcription not yet attempted
    case success    // Transcription completed successfully
    case failed     // Transcription failed

    public var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .success: return "Complete"
        case .failed: return "Failed"
        }
    }

    public var icon: String {
        switch self {
        case .pending: return "clock"
        case .success: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Recording Filter

public enum RecordingFilter: Hashable, Sendable {
    case type(TalkieObjectType)        // Filter by memo/dictation
    case source(RecordingSource)       // Filter by origin device
    case hasAudio                      // Only recordings with audio
    case shortRecordings               // Under 30 seconds
    case pendingTranscription          // Transcription pending or failed
    case hasWorkflows                  // Has workflow runs
}

// MARK: - Recording Sort Field

public enum RecordingSortField: Sendable {
    case createdAt      // Sort by creation date
    case title          // Sort by title (alphabetically)
    case duration       // Sort by duration
    case type           // Sort by type (memos first or dictations first)
}
