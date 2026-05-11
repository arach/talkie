//
//  RecordingSidecarStore.swift
//  Talkie iOS
//
//  JSON-backed local persistence for memo sidecar requests and outputs.
//

import Combine
import Foundation
import TalkieMobileKit

@MainActor
final class RecordingSidecarStore: ObservableObject {
    static let shared = RecordingSidecarStore()

    @Published private(set) var sessions: [String: RecordingSidecarSession] = [:]

    private let fileManager = FileManager.default

    private init() {
        sessions = load()
    }

    func requests(for memoId: String) -> [RecordingSidecarRequest] {
        let requests = sessions[memoId]?.requests ?? []
        return requests.sorted { $0.createdAt < $1.createdAt }
    }

    func attachRequests(_ requests: [RecordingSidecarRequest], to memoId: String, memoTitle: String) {
        guard !requests.isEmpty else { return }

        let now = Date()
        var session = sessions[memoId] ?? RecordingSidecarSession(memoId: memoId, memoTitle: memoTitle)
        session.memoTitle = memoTitle
        session.updatedAt = now
        session.requests.append(contentsOf: requests)
        session.requests.sort { $0.createdAt < $1.createdAt }
        sessions[memoId] = session
        save()
    }

    func updateRequest(
        memoId: String,
        requestId: UUID,
        update: (inout RecordingSidecarRequest) -> Void
    ) {
        guard var session = sessions[memoId],
              let index = session.requests.firstIndex(where: { $0.id == requestId }) else {
            return
        }

        update(&session.requests[index])
        session.updatedAt = Date()
        sessions[memoId] = session
        save()
    }

    func deleteSession(for memoId: String) {
        sessions.removeValue(forKey: memoId)
        save()
    }

    private var storageURL: URL? {
        if let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: TalkieMobileRuntimeIdentifiers.appGroupIdentifier
        ) {
            return containerURL.appending(path: "recording-sidecars.json")
        }

        return URL.documentsDirectory.appending(path: "recording-sidecars.json")
    }

    private func load() -> [String: RecordingSidecarSession] {
        guard let url = storageURL,
              let data = try? Data(contentsOf: url) else {
            return [:]
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: RecordingSidecarSession].self, from: data)) ?? [:]
    }

    private func save() {
        guard let url = storageURL else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(sessions) else { return }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            AppLogger.persistence.error("Failed to save recording sidecars: \(error.localizedDescription)")
        }
    }
}
