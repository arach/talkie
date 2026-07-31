//
//  CodexPendingTurn.swift
//  Talkie iOS
//
//  Durable receipt for a Codex turn started from the iPhone. The Mac owns the
//  actual job; this record lets the phone resume polling after suspension,
//  termination, or an app update instead of losing the eventual reply.
//

import Foundation

struct CodexPendingTurn: Codable, Identifiable, Equatable {
    let id: UUID
    let hostID: String?
    let task: CodexTaskSummary
    let instruction: String
    let laneNumber: Int?
    let createdAt: Date
    var updatedAt: Date
    var job: CodexTurnJob

    struct Store {
        let url: URL

        func load() throws -> [CodexPendingTurn] {
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            return try JSONDecoder().decode(
                [CodexPendingTurn].self,
                from: Data(contentsOf: url)
            )
        }

        func save(_ pending: [CodexPendingTurn]) throws {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(pending).write(
                to: url,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        }
    }
}
