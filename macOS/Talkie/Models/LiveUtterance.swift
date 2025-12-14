//
//  LiveUtterance.swift
//  Talkie
//
//  Read-only model for displaying TalkieLive utterances
//  Mirrors the structure in TalkieLive's PastLives.sqlite
//

import Foundation

// MARK: - Promotion Status (mirrors TalkieLive)

enum LivePromotionStatus: String, Codable {
    case none       // Just a Live, no follow-up
    case memo       // Promoted to a Talkie memo
    case command    // Turned into a workflow/command
    case ignored    // Explicitly marked as "don't bother me again"

    var displayName: String {
        switch self {
        case .none: return "Raw"
        case .memo: return "Memo"
        case .command: return "Command"
        case .ignored: return "Ignored"
        }
    }

    var icon: String {
        switch self {
        case .none: return "circle"
        case .memo: return "doc.text"
        case .command: return "terminal"
        case .ignored: return "eye.slash"
        }
    }
}

// MARK: - Transcription Status (mirrors TalkieLive)

enum LiveTranscriptionStatus: String, Codable {
    case pending
    case failed
    case success

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .failed: return "Failed"
        case .success: return "Complete"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "clock"
        case .failed: return "exclamationmark.triangle"
        case .success: return "checkmark.circle"
        }
    }
}

// MARK: - Live Utterance Model

struct LiveUtterance: Identifiable, Hashable {
    let id: Int64
    let createdAt: Date
    let text: String
    let mode: String
    let appBundleID: String?
    let appName: String?
    let windowTitle: String?
    let durationSeconds: Double?
    let wordCount: Int?
    let whisperModel: String?
    let audioFilename: String?
    let transcriptionStatus: LiveTranscriptionStatus
    let promotionStatus: LivePromotionStatus
    let talkieMemoID: String?

    /// Whether this Live can still be promoted
    var canPromote: Bool {
        promotionStatus == .none
    }

    /// Formatted duration string
    var durationString: String? {
        guard let duration = durationSeconds else { return nil }
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
    }

    /// Relative time string (e.g., "2 min ago")
    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }

    /// Preview of the text (first line, truncated)
    var preview: String {
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        if firstLine.count > 100 {
            return String(firstLine.prefix(100)) + "..."
        }
        return firstLine
    }
}
