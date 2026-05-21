//
//  AskAISessionStore.swift
//  Talkie iOS
//
//  JSON persistence for the Ask AI multi-turn session.
//

import Foundation

struct AskAISessionSnapshot: Codable, Equatable {
    let turns: [AskAITurn]
    let lastPreset: AskAIPreset?
    let lastModel: String?
    let lastTurnID: AskAITurn.ID?
}

@MainActor
final class AskAISessionStore {
    static let shared = AskAISessionStore()

    private let stateURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var cachedSnapshot: AskAISessionSnapshot?

    private init() {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.applicationSupportDirectory
        stateURL = supportDirectory.appending(path: "ask-ai-session.json")
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        cachedSnapshot = Self.readSnapshot(from: stateURL, decoder: decoder)
    }

    func load() -> AskAISessionSnapshot? {
        cachedSnapshot
    }

    func save(_ snapshot: AskAISessionSnapshot) async {
        let stableSnapshot = AskAISessionSnapshot(
            turns: snapshot.turns.filter { !$0.isThinking },
            lastPreset: snapshot.lastPreset,
            lastModel: snapshot.lastModel,
            lastTurnID: snapshot.lastTurnID
        )
        cachedSnapshot = stableSnapshot

        do {
            let directory = stateURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(stableSnapshot)
            try data.write(to: stateURL, options: [.atomic])
        } catch {
            AppLogger.persistence.warning("Ask AI session persist failed", detail: error.localizedDescription)
        }
    }

    func clear() {
        cachedSnapshot = nil
        do {
            try FileManager.default.removeItem(at: stateURL)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            AppLogger.persistence.warning("Ask AI session clear failed", detail: error.localizedDescription)
        }
    }

    private static func readSnapshot(from url: URL, decoder: JSONDecoder) -> AskAISessionSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(AskAISessionSnapshot.self, from: data)
        } catch {
            AppLogger.persistence.warning("Ask AI session decode failed", detail: error.localizedDescription)
            return nil
        }
    }
}
