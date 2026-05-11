//
//  BrowseHistory.swift
//  Talkie iOS
//
//  Talkie-local browsing history for WebCaptureBrowser.
//  WKWebView doesn't share Safari's history, so we track our own.
//  Persisted in App Group for cross-extension access.
//

import Foundation
import TalkieMobileKit

struct BrowseHistoryEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let url: String
    let title: String?
    let domain: String?
    let visitedAt: Date

    init(url: String, title: String?) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.domain = URL(string: url)?.host
        self.visitedAt = Date()
    }
}

@MainActor
final class BrowseHistory: ObservableObject {
    static let shared = BrowseHistory()

    @Published private(set) var entries: [BrowseHistoryEntry] = []

    private let maxEntries = 500
    private let fileManager = FileManager.default

    private init() {
        entries = load()
    }

    // MARK: - Public API

    /// Record a page visit. Deduplicates recent visits to the same URL.
    func record(url: String, title: String?) {
        // Skip blank/about pages
        guard !url.isEmpty,
              !url.hasPrefix("about:"),
              url != "https://www.google.com/" else { return }

        // Deduplicate: if top entry is the same URL, just update title
        if let first = entries.first, first.url == url {
            if title != nil && title != first.title {
                entries[0] = BrowseHistoryEntry(url: url, title: title)
                save()
            }
            return
        }

        let entry = BrowseHistoryEntry(url: url, title: title)
        entries.insert(entry, at: 0)

        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }

        save()
    }

    /// Autocomplete suggestions matching a query.
    /// Returns unique domains first, then full URLs, ordered by recency.
    func suggestions(for query: String) -> [BrowseHistoryEntry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }

        // Match against URL and title
        let matches = entries.filter { entry in
            entry.url.lowercased().contains(q) ||
            (entry.title?.lowercased().contains(q) ?? false) ||
            (entry.domain?.lowercased().contains(q) ?? false)
        }

        // Deduplicate by domain, keeping the most recent per domain
        var seenDomains = Set<String>()
        var result: [BrowseHistoryEntry] = []
        for entry in matches {
            let key = entry.domain ?? entry.url
            if !seenDomains.contains(key) {
                seenDomains.insert(key)
                result.append(entry)
            }
            if result.count >= 6 { break }
        }

        return result
    }

    /// All entries grouped by day for the history view
    func recentEntries(limit: Int = 50) -> [BrowseHistoryEntry] {
        Array(entries.prefix(limit))
    }

    func clear() {
        entries = []
        save()
    }

    // MARK: - Persistence

    private var storageURL: URL? {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: TalkieMobileRuntimeIdentifiers.appGroupIdentifier
        ) else { return nil }
        return container.appendingPathComponent("browse-history.json")
    }

    private func load() -> [BrowseHistoryEntry] {
        guard let url = storageURL,
              let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([BrowseHistoryEntry].self, from: data)) ?? []
    }

    private func save() {
        guard let url = storageURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
