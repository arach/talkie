//
//  CodexReadout.swift
//  Talkie iOS
//

import Foundation

/// One agent-report notification retained in Talkie's private CloudKit zone.
struct CodexReadout: Identifiable, Sendable {
    let id: String
    let title: String
    let body: String
    let detail: String?
    let sessionID: String
    let source: String?
    let createdAt: Date

    var spokenText: String {
        if let detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines),
           !detail.isEmpty {
            return detail
        }
        return body
    }
}
