//
//  CaptureAICommandStore.swift
//  Talkie iOS
//
//  Persists one-shot AI command runs for captures.
//

import Foundation
import TalkieMobileKit

struct CaptureAICommandRun: Codable, Identifiable {
    let id: UUID
    let captureId: UUID
    let instruction: String
    let responseText: String
    let providerName: String
    let modelId: String
    let fallbackReason: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        captureId: UUID,
        instruction: String,
        responseText: String,
        providerName: String,
        modelId: String,
        fallbackReason: String?,
        createdAt: Date = .now
    ) {
        self.id = id
        self.captureId = captureId
        self.instruction = instruction
        self.responseText = responseText
        self.providerName = providerName
        self.modelId = modelId
        self.fallbackReason = fallbackReason
        self.createdAt = createdAt
    }
}

@MainActor
final class CaptureAICommandStore {
    static let shared = CaptureAICommandStore()

    private let fileManager = FileManager.default
    private let maxRuns = 200
    private var runs: [CaptureAICommandRun] = []

    private init() {
        runs = load()
    }

    func latestRun(for captureId: UUID) -> CaptureAICommandRun? {
        runs.first(where: { $0.captureId == captureId })
    }

    func runs(for captureId: UUID) -> [CaptureAICommandRun] {
        runs.filter { $0.captureId == captureId }
    }

    func addRun(_ run: CaptureAICommandRun) {
        runs.removeAll { existing in
            existing.captureId == run.captureId && existing.id == run.id
        }
        runs.insert(run, at: 0)

        if runs.count > maxRuns {
            runs = Array(runs.prefix(maxRuns))
        }

        save()
    }

    private var storageURL: URL? {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: kTalkieAppGroup
        ) else { return nil }
        return container.appendingPathComponent("capture-ai-commands.json")
    }

    private func load() -> [CaptureAICommandRun] {
        guard let url = storageURL,
              let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = (try? decoder.decode([CaptureAICommandRun].self, from: data)) ?? []
        return decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        guard let url = storageURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(runs) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
