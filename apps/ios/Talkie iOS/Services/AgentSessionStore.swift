//
//  AgentSessionStore.swift
//  Talkie iOS
//
//  Persists agent conversations tied to memos.
//  Stores remote agent session IDs for multi-turn follow-ups.
//  JSON-based persistence in App Group, similar to BrowseHistory.
//

import Foundation
import TalkieMobileKit

struct AgentTurn: Codable, Identifiable {
    let id: UUID
    let role: String  // "user" or "assistant"
    let content: String
    let timestamp: Date

    init(role: String, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

struct AgentSession: Codable, Identifiable {
    let id: UUID
    let memoId: String
    let memoTitle: String
    var claudeSessionId: String?  // Historical key; now stores the Codex thread id for Ask Agent.
    var turns: [AgentTurn]
    let createdAt: Date
    var updatedAt: Date

    init(memoId: String, memoTitle: String) {
        self.id = UUID()
        self.memoId = memoId
        self.memoTitle = memoTitle
        self.claudeSessionId = nil
        self.turns = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@MainActor
final class AgentSessionStore: ObservableObject {
    static let shared = AgentSessionStore()

    @Published private(set) var sessions: [AgentSession] = []

    private let maxSessions = 100
    private let fileManager = FileManager.default

    private init() {
        sessions = load()
    }

    // MARK: - Public API

    /// Get or create a session for a memo
    func session(forMemoId memoId: String, memoTitle: String) -> AgentSession {
        if let existing = sessions.first(where: { $0.memoId == memoId }) {
            return existing
        }
        let session = AgentSession(memoId: memoId, memoTitle: memoTitle)
        sessions.insert(session, at: 0)
        save()
        return session
    }

    /// Get existing session for a memo (nil if none)
    func existingSession(forMemoId memoId: String) -> AgentSession? {
        sessions.first(where: { $0.memoId == memoId })
    }

    /// Add a user turn
    func addUserTurn(memoId: String, content: String) {
        guard let index = sessions.firstIndex(where: { $0.memoId == memoId }) else { return }
        let turn = AgentTurn(role: "user", content: content)
        sessions[index].turns.append(turn)
        sessions[index].updatedAt = Date()
        save()
    }

    /// Add an assistant turn
    func addAssistantTurn(memoId: String, content: String) {
        guard let index = sessions.firstIndex(where: { $0.memoId == memoId }) else { return }
        let turn = AgentTurn(role: "assistant", content: content)
        sessions[index].turns.append(turn)
        sessions[index].updatedAt = Date()
        save()
    }

    /// Store the remote agent session ID for follow-ups.
    func setClaudeSessionId(_ sessionId: String, forMemoId memoId: String) {
        guard let index = sessions.firstIndex(where: { $0.memoId == memoId }) else { return }
        sessions[index].claudeSessionId = sessionId
        save()
    }

    /// Check if a memo has an active agent conversation
    func hasConversation(forMemoId memoId: String) -> Bool {
        sessions.first(where: { $0.memoId == memoId && !$0.turns.isEmpty }) != nil
    }

    /// Delete a session
    func delete(memoId: String) {
        sessions.removeAll { $0.memoId == memoId }
        save()
    }

    // MARK: - Persistence

    private var storageURL: URL? {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: TalkieMobileRuntimeIdentifiers.appGroupIdentifier
        ) else { return nil }
        return container.appendingPathComponent("agent-sessions.json")
    }

    private func load() -> [AgentSession] {
        guard let url = storageURL,
              let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([AgentSession].self, from: data)) ?? []
    }

    private func save() {
        // Trim old sessions
        if sessions.count > maxSessions {
            sessions = Array(sessions.prefix(maxSessions))
        }

        guard let url = storageURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
