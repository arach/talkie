//
//  RecordingSidecarKind.swift
//  Talkie iOS
//
//  Lightweight sidecar task kinds that can be queued while recording
//  and resolved after transcription is available.
//

import Foundation

enum RecordingSidecarKind: String, Codable, CaseIterable {
    case feedback
    case research

    var displayName: String {
        switch self {
        case .feedback:
            return "Feedback"
        case .research:
            return "Research"
        }
    }

    var iconName: String {
        switch self {
        case .feedback:
            return "bubble.left.and.sparkles"
        case .research:
            return "magnifyingglass"
        }
    }

    var hint: String {
        switch self {
        case .feedback:
            return "Bookmark this moment for critique, blind spots, and stronger framing."
        case .research:
            return "Bookmark this moment for follow-up questions, terms, and next research threads."
        }
    }
}
