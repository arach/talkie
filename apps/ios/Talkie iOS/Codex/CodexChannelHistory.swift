//
//  CodexChannelHistory.swift
//  Talkie iOS
//

import Foundation

/// Host-backed public history for one exact Codex channel.
struct CodexChannelHistory: Codable, Sendable {
    let task: CodexTaskSummary
    let turns: [Turn]

    struct Turn: Identifiable, Codable, Sendable {
        let id: String
        let status: String
        let startedAt: String?
        let completedAt: String?
        let durationMs: Double?
        let instructions: [String]
        let updates: [Update]
        let response: String?
        let error: String?

        var latestInstruction: String? {
            instructions.last?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var publicResponse: String? {
            guard let response else { return nil }
            let visible = response.components(separatedBy: "<oai-mem-citation>").first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return visible?.isEmpty == false ? visible : nil
        }
    }

    struct Update: Identifiable, Codable, Sendable {
        let id: String
        let kind: String
        let text: String
        let timestamp: String?
    }
}
