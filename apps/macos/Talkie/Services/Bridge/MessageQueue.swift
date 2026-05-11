//
//  MessageQueue.swift
//  Talkie
//
//  Persistent data store for Bridge messages.
//  Records all incoming messages from iOS with full metadata.
//

import Foundation
import SwiftUI

/// Source of the message
enum MessageSource: String, Codable {
    case bridge      // Incoming from iOS via Bridge
    case localUI     // Sent from Talkie's Claude Sessions view
    case xpc         // Direct XPC call
}

/// A queued message destined for a Claude session
struct QueuedMessage: Identifiable, Codable {
    let id: UUID
    let sessionId: String
    let projectPath: String?
    let text: String
    let createdAt: Date
    var status: MessageStatus
    var lastError: String?
    var attempts: Int

    // Extended metadata
    let source: MessageSource
    var completedAt: Date?
    var xpcDurationMs: Int?
    var metadata: [String: String]?

    init(sessionId: String, projectPath: String?, text: String, source: MessageSource = .bridge, metadata: [String: String]? = nil) {
        self.id = UUID()
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.text = text
        self.createdAt = Date()
        self.status = .pending
        self.lastError = nil
        self.attempts = 0
        self.source = source
        self.completedAt = nil
        self.xpcDurationMs = nil
        self.metadata = metadata
    }

    enum MessageStatus: String, Codable {
        case pending
        case sending
        case sent
        case failed
    }
}

/// Manages the message queue for Bridge
@MainActor
@Observable
final class MessageQueue {
    static let shared = MessageQueue()

    private(set) var messages: [QueuedMessage] = []

    private let storageURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let talkieDir = appSupport.appendingPathComponent("Talkie")
        try? FileManager.default.createDirectory(at: talkieDir, withIntermediateDirectories: true)
        return talkieDir.appendingPathComponent("message-queue.json")
    }()

    private init() {
        load()
    }

    // MARK: - Public API

    /// Add a message to the queue (legacy, defaults to localUI source)
    func enqueue(sessionId: String, projectPath: String?, text: String, source: MessageSource = .localUI, metadata: [String: String]? = nil) {
        let message = QueuedMessage(sessionId: sessionId, projectPath: projectPath, text: text, source: source, metadata: metadata)
        messages.insert(message, at: 0)
        save()
    }

    /// Record an incoming message with full metadata
    /// Returns the message ID for status tracking
    @discardableResult
    func recordIncoming(
        sessionId: String,
        projectPath: String?,
        text: String,
        source: MessageSource = .bridge,
        metadata: [String: String]? = nil
    ) -> UUID {
        let message = QueuedMessage(sessionId: sessionId, projectPath: projectPath, text: text, source: source, metadata: metadata)
        messages.insert(message, at: 0)
        save()
        return message.id
    }

    /// Update message status with optional completion metadata
    func updateStatus(_ id: UUID, status: QueuedMessage.MessageStatus, error: String? = nil, xpcDurationMs: Int? = nil) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].status = status
        messages[index].lastError = error
        if status == .sending {
            messages[index].attempts += 1
        }
        if status == .sent || status == .failed {
            messages[index].completedAt = Date()
        }
        if let duration = xpcDurationMs {
            messages[index].xpcDurationMs = duration
        }
        save()
    }

    /// Remove a message from the queue
    func remove(_ id: UUID) {
        messages.removeAll { $0.id == id }
        save()
    }

    /// Clear all sent messages
    func clearSent() {
        messages.removeAll { $0.status == .sent }
        save()
    }

    /// Clear all messages
    func clearAll() {
        messages.removeAll()
        save()
    }

    /// Get pending/failed messages (for retry)
    var retryable: [QueuedMessage] {
        messages.filter { $0.status == .pending || $0.status == .failed }
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(messages)
            try data.write(to: storageURL)
        } catch {
            print("[MessageQueue] Save error: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            messages = try JSONDecoder().decode([QueuedMessage].self, from: data)
        } catch {
            print("[MessageQueue] Load error: \(error)")
        }
    }
}
