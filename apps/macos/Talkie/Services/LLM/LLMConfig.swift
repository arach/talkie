//
//  LLMConfig.swift
//  Talkie
//
//  Bundled fallback model catalog with remote override support.
//  The published catalog lives at api.usetalkie.com/llms/supported.json (talkie-server);
//  Talkie ships `Resources/LLMConfig.json` as fallback for offline/first-launch.
//

import Foundation
import TalkieKit

private let log = Log(.system)

final class LLMConfig {
    static let shared = LLMConfig()
    static let didRefreshNotification = Notification.Name("LLMConfig.didRefresh")

    struct Snapshot: Codable, Equatable {
        let schemaVersion: Int?
        let providers: [String: ProviderConfig]
        let preferredProviderOrder: [String]

        func isValid() -> Bool {
            guard !providers.isEmpty else { return false }

            return providers.allSatisfy { providerId, provider in
                guard provider.id == providerId else { return false }
                guard !provider.defaultModel.isEmpty else { return false }
                if provider.models.isEmpty {
                    return true
                }
                return provider.models.contains(where: { $0.id == provider.defaultModel })
            }
        }
    }

    struct ProviderConfig: Codable, Equatable {
        let id: String
        let name: String
        let defaultModel: String
        let models: [ModelConfig]
    }

    struct ModelConfig: Codable, Equatable {
        let id: String
        let displayName: String
        let description: String?
        let recommended: Bool?
        let contextWindow: Int?
        let workflowCostTier: LLMCostTier?
        let inputCostPer1M: Double?
        let outputCostPer1M: Double?
        let maxOutputTokens: Int?
    }

    var providers: [String: ProviderConfig] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return snapshot.providers
    }

    var preferredProviderOrder: [String] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return snapshot.preferredProviderOrder
    }

    var lastFetchDate: Date? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedLastFetchDate
    }

    var lastError: Error? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedLastError
    }

    private let stateLock = NSLock()
    // Public source-of-truth served by talkie-server at api.usetalkie.com.
    private let remoteCatalogURL = URL(string: "https://api.usetalkie.com/llms/supported.json")!
    private let fetchTimeout: TimeInterval = 5
    private let cacheDuration: TimeInterval = 30 * 24 * 60 * 60
    private let persistedConfigKey = "llmConfig.remote"
    private let lastFetchKey = "llmConfig.lastFetch"

    private var snapshot: Snapshot
    private var storedLastFetchDate: Date?
    private var storedLastError: Error?
    private var isRefreshing = false

    private init() {
        snapshot = Self.loadBundledSnapshot()
        loadPersistedSnapshot()

        Task {
            await refresh()
        }
    }

    func config(for providerId: String) -> ProviderConfig? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return snapshot.providers[providerId]
    }

    func defaultModel(for providerId: String) -> String? {
        config(for: providerId)?.defaultModel
    }

    func models(for providerId: String) -> [ModelConfig] {
        config(for: providerId)?.models ?? []
    }

    func recommendedModelIDs(for providerId: String) -> Set<String> {
        Set(models(for: providerId).compactMap { model in
            (model.recommended ?? false) ? model.id : nil
        })
    }

    func workflowModels(for providerId: String) -> [WorkflowModelOption] {
        models(for: providerId).map { $0.workflowModelOption(for: providerId) }
    }

    func refresh(force: Bool = false) async {
        guard beginRefresh(force: force) else { return }
        defer { finishRefresh() }

        do {
            let remoteSnapshot = try await fetchRemoteSnapshot()
            apply(snapshot: remoteSnapshot, source: "remote")
        } catch {
            recordRefreshError(error)
            log.warning("Failed to refresh LLM catalog: \(error.localizedDescription)")
        }
    }

    private func beginRefresh(force: Bool) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        if isRefreshing {
            return false
        }

        if !force,
           let lastFetchDate = storedLastFetchDate,
           Date().timeIntervalSince(lastFetchDate) < cacheDuration {
            return false
        }

        isRefreshing = true
        return true
    }

    private func finishRefresh() {
        stateLock.lock()
        isRefreshing = false
        stateLock.unlock()
    }

    private func recordRefreshError(_ error: Error) {
        stateLock.lock()
        storedLastError = error
        stateLock.unlock()
    }

    private func fetchRemoteSnapshot() async throws -> Snapshot {
        var request = URLRequest(url: remoteCatalogURL)
        request.timeoutInterval = fetchTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CatalogError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw CatalogError.serverError(httpResponse.statusCode)
        }

        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        guard snapshot.isValid() else {
            throw CatalogError.invalidPayload
        }

        return snapshot
    }

    private func loadPersistedSnapshot() {
        if let data = UserDefaults.standard.data(forKey: persistedConfigKey),
           let persisted = try? JSONDecoder().decode(Snapshot.self, from: data),
           persisted.isValid() {
            let bundledVersion = snapshot.schemaVersion ?? 0
            let persistedVersion = persisted.schemaVersion ?? 0

            if persistedVersion >= bundledVersion {
                snapshot = persisted
                log.debug("Loaded persisted LLM catalog with \(persisted.providers.count) providers")
            } else {
                log.info(
                    "Ignoring persisted LLM catalog schema v\(persistedVersion) in favor of bundled v\(bundledVersion)"
                )
            }
        }

        if let lastFetch = UserDefaults.standard.object(forKey: lastFetchKey) as? Date {
            storedLastFetchDate = lastFetch
        }
    }

    private func persistSnapshot() {
        stateLock.lock()
        let snapshot = self.snapshot
        let lastFetchDate = storedLastFetchDate
        stateLock.unlock()

        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: persistedConfigKey)
        }
        UserDefaults.standard.set(lastFetchDate, forKey: lastFetchKey)
    }

    private func apply(snapshot newSnapshot: Snapshot, source: String) {
        stateLock.lock()
        let didChange = snapshot != newSnapshot
        snapshot = newSnapshot
        storedLastFetchDate = Date()
        storedLastError = nil
        stateLock.unlock()

        persistSnapshot()
        log.info("Loaded \(source) LLM catalog with \(newSnapshot.providers.count) providers")

        if didChange {
            NotificationCenter.default.post(name: Self.didRefreshNotification, object: nil)
        }
    }

    private static func loadBundledSnapshot() -> Snapshot {
        let decoder = JSONDecoder()

        if let url = Bundle.main.url(forResource: "LLMConfig", withExtension: "json", subdirectory: "Resources"),
           let data = try? Data(contentsOf: url),
           let snapshot = try? decoder.decode(Snapshot.self, from: data),
           snapshot.isValid() {
            return snapshot
        }

        if let url = Bundle.main.url(forResource: "LLMConfig", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let snapshot = try? decoder.decode(Snapshot.self, from: data),
           snapshot.isValid() {
            return snapshot
        }

        log.warning("Failed to load bundled LLM catalog, falling back to empty snapshot")
        return Snapshot(schemaVersion: 1, providers: [:], preferredProviderOrder: [])
    }

    private enum CatalogError: LocalizedError {
        case invalidResponse
        case serverError(Int)
        case invalidPayload

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid response while loading model catalog"
            case .serverError(let statusCode):
                return "Model catalog server returned \(statusCode)"
            case .invalidPayload:
                return "Model catalog payload failed validation"
            }
        }
    }
}

extension LLMConfig.ModelConfig {
    func llmModel(for providerId: String) -> LLMModel {
        LLMModel(
            id: id,
            name: id,
            displayName: displayName,
            size: "Cloud",
            type: .cloud,
            provider: providerId,
            downloadURL: nil,
            isInstalled: true
        )
    }

    func workflowModelOption(for providerId: String) -> WorkflowModelOption {
        let defaultContextWindow: Int = switch providerId {
        case "gemini":
            1_000_000
        case "anthropic":
            200_000
        case "groq":
            128_000
        default:
            128_000
        }

        return WorkflowModelOption(
            id: id,
            name: displayName,
            contextWindow: contextWindow ?? defaultContextWindow,
            costTier: workflowCostTier ?? .balanced,
            inputCostPer1M: inputCostPer1M,
            outputCostPer1M: outputCostPer1M,
            maxOutputTokens: maxOutputTokens
        )
    }
}
