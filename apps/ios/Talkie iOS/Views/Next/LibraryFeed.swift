//
//  LibraryFeed.swift
//  Talkie iOS
//
//  Persistence-backed data source for LibraryNextView.
//

import CoreData
import Foundation
import SwiftUI
import TalkieMobileKit

@MainActor
final class LibraryFeed: ObservableObject {
    enum Source { case dictation, typed, link, scan }
    enum SyncStatus { case synced, pending }

    struct Item: Identifiable {
        let id: String
        let source: Source
        let title: String
        let preview: String?
        let relativeTime: String
        let syncStatus: SyncStatus?
        let canPromoteToMemo: Bool
        // True only while the background transcription pass is running for
        // this memo (VoiceMemo.isTranscribing). Non-memo sources are never
        // transcribing.
        var isTranscribing: Bool = false
    }

    @Published private(set) var memos: [Item]
    @Published private(set) var dictations: [Item]
    @Published private(set) var items: [Item]
    @Published private(set) var isLoading: Bool
    @Published private(set) var errorMessage: String?

    init() {
        self.memos = []
        self.dictations = []
        self.items = []
        self.isLoading = false
        self.errorMessage = nil
        reload()
    }

    func reload() {
        isLoading = true
        defer { isLoading = false }

        let context = PersistenceController.shared.container.viewContext
        do {
            let memos = try Self.fetchVoiceMemos(context: context)
            let notes = try Self.fetchComposeNotes(context: context)

            KeyboardDictationStore.shared.reload()
            CaptureStore.shared.reload()
            let keyboardDictations = KeyboardDictationStore.shared.all()
            let captures = CaptureStore.shared.all()

            self.memoEntries = Self.memoEntries(from: memos)
            self.dictationEntries = Self.noteEntries(from: notes) + Self.keyboardEntries(from: keyboardDictations)
            self.itemEntries = Self.captureItemEntries(from: captures)
            rebuildVisible()
            self.errorMessage = nil
        } catch {
            self.memoEntries = []
            self.dictationEntries = []
            self.itemEntries = []
            self.memos = []
            self.dictations = []
            self.items = []
            self.errorMessage = "Couldn’t load library items."
            AppLogger.persistence.error("Failed to load library feed: \(error.localizedDescription)")
        }
    }

    func delete(_ item: Item, in tab: LibraryTab) {
        switch tab {
        case .memos:
            VoiceMemoStore.shared.delete(id: item.id)
        case .dictations:
            if ComposeNoteStore.delete(id: item.id) {
                // ComposeNoteStore posts .composeNotesDidChange.
            } else if let uuid = UUID(uuidString: item.id) {
                KeyboardDictationStore.shared.delete(uuid)
            }
        case .items:
            if let uuid = UUID(uuidString: item.id),
               let capture = CaptureStore.shared.all().first(where: { $0.id == uuid }) {
                CaptureStore.shared.delete(capture)
            }
        }

        reload()
    }

    func promoteToMemo(_ item: Item) {
        guard item.canPromoteToMemo,
              let uuid = UUID(uuidString: item.id),
              let dictation = KeyboardDictationStore.shared.all().first(where: { $0.id == uuid }) else {
            return
        }
        if VoiceMemoStore.shared.promoteKeyboardDictation(dictation) {
            reload()
        }
    }

    func items(for tab: LibraryTab, matching query: String = "") -> [Item] {
        Self.bucket(filteredEntries(for: tab, matching: query), limit: visibleLimit(for: tab)).visible
    }

    func totalCount(for tab: LibraryTab, matching query: String = "") -> Int {
        Self.bucket(filteredEntries(for: tab, matching: query), limit: visibleLimit(for: tab)).total
    }

    func earlierCount(for tab: LibraryTab, matching query: String = "") -> Int {
        Self.bucket(filteredEntries(for: tab, matching: query), limit: visibleLimit(for: tab)).earlier
    }

    /// Reveal the next page of a tab's items (everything stays reachable, Home-style).
    func loadMore(for tab: LibraryTab) {
        visibleLimits[tab] = visibleLimit(for: tab) + Self.loadMoreStep
        rebuildVisible()
    }

    // MARK: - Persistence-backed feed

    private static let initialVisibleLimit = 8
    private static let loadMoreStep = 10

    private var visibleLimits: [LibraryTab: Int] = [:]

    private func visibleLimit(for tab: LibraryTab) -> Int {
        visibleLimits[tab] ?? Self.initialVisibleLimit
    }

    private func rebuildVisible() {
        memos = Self.bucket(memoEntries, limit: visibleLimit(for: .memos)).visible
        dictations = Self.bucket(dictationEntries, limit: visibleLimit(for: .dictations)).visible
        items = Self.bucket(itemEntries, limit: visibleLimit(for: .items)).visible
    }
    private static let recentWindow: TimeInterval = 7 * 24 * 60 * 60

    private struct Entry {
        let item: Item
        let updatedAt: Date
        let searchableText: String
    }

    private var memoEntries: [Entry] = []
    private var dictationEntries: [Entry] = []
    private var itemEntries: [Entry] = []

    private func filteredEntries(for tab: LibraryTab, matching query: String) -> [Entry] {
        let entries: [Entry]
        switch tab {
        case .memos: entries = memoEntries
        case .dictations: entries = dictationEntries
        case .items: entries = itemEntries
        }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return entries }
        return entries.filter { entry in
            entry.searchableText.localizedStandardContains(normalizedQuery)
        }
    }

    private static func bucket(_ entries: [Entry], limit: Int) -> (visible: [Item], total: Int, earlier: Int) {
        let cutoff = Date().addingTimeInterval(-recentWindow)
        let recent = entries
            .filter { $0.updatedAt >= cutoff }
            .sorted { $0.updatedAt > $1.updatedAt }
        let visible = recent.prefix(limit).map(\.item)
        return (Array(visible), recent.count, max(0, recent.count - limit))
    }

    private static func fetchVoiceMemos(context: NSManagedObjectContext) throws -> [VoiceMemo] {
        let request: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \VoiceMemo.lastModified, ascending: false),
            NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false),
        ]
        request.fetchLimit = 200
        return try context.fetch(request)
    }

    private static func fetchComposeNotes(context: NSManagedObjectContext) throws -> [ComposeNote] {
        let request: NSFetchRequest<ComposeNote> = ComposeNote.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ComposeNote.lastModified, ascending: false),
            NSSortDescriptor(keyPath: \ComposeNote.createdAt, ascending: false),
        ]
        request.fetchLimit = 200
        return try context.fetch(request)
    }

    private static func memoEntries(from memos: [VoiceMemo]) -> [Entry] {
        memos.map { memo in
            let updatedAt = memo.lastModified ?? memo.createdAt ?? .distantPast
            let body = firstNonEmpty([memo.transcription, memo.summary, memo.notes])
            let item = Item(
                id: memo.id?.uuidString ?? memo.objectID.uriRepresentation().absoluteString,
                source: .dictation,
                title: cleanTitle(memo.title, fallback: "Untitled memo"),
                preview: preview(body),
                relativeTime: relativeListTime(from: updatedAt),
                syncStatus: nil,
                canPromoteToMemo: false,
                isTranscribing: memo.isTranscribing
            )
            return Entry(
                item: item,
                updatedAt: updatedAt,
                searchableText: searchableText(title: item.title, preview: item.preview)
            )
        }
    }

    private static func noteEntries(from notes: [ComposeNote]) -> [Entry] {
        notes.map { note in
            let updatedAt = note.lastModified ?? note.createdAt ?? .distantPast
            let item = Item(
                id: note.id?.uuidString ?? note.objectID.uriRepresentation().absoluteString,
                source: .typed,
                title: ComposeNoteStore.displayText(from: note.content),
                preview: preview(note.content),
                relativeTime: relativeListTime(from: updatedAt),
                syncStatus: nil,
                canPromoteToMemo: false
            )
            return Entry(
                item: item,
                updatedAt: updatedAt,
                searchableText: searchableText(title: item.title, preview: item.preview)
            )
        }
    }

    private static func keyboardEntries(from dictations: [KeyboardDictation]) -> [Entry] {
        dictations.map { dictation in
            let item = Item(
                id: dictation.id.uuidString,
                source: .typed,
                title: title(from: dictation.text, fallback: "Keyboard dictation"),
                preview: preview(dictation.text),
                relativeTime: relativeListTime(from: dictation.timestamp),
                syncStatus: nil,
                canPromoteToMemo: true
            )
            return Entry(
                item: item,
                updatedAt: dictation.timestamp,
                searchableText: searchableText(title: item.title, preview: item.preview, extra: dictation.appContext)
            )
        }
    }

    private static func captureItemEntries(from captures: [Capture]) -> [Entry] {
        captures.compactMap { capture in
            guard let source = itemSource(for: capture) else { return nil }
            let fallback = fallbackTitle(for: capture, source: source)
            let item = Item(
                id: capture.id.uuidString,
                source: source,
                title: cleanTitle(capture.title, fallback: title(from: capture.text, fallback: fallback)),
                preview: capturePreview(for: capture, source: source),
                relativeTime: relativeListTime(from: capture.timestamp),
                syncStatus: capture.syncedToMac ? .synced : .pending,
                canPromoteToMemo: false
            )
            return Entry(
                item: item,
                updatedAt: capture.timestamp,
                searchableText: searchableText(title: item.title, preview: item.preview, extra: capture.sourceType)
            )
        }
    }

    private static func itemSource(for capture: Capture) -> Source? {
        switch capture.sourceType.lowercased() {
        case "url", "link", "web": return .link
        case "photo", "scan", "image", "document": return .scan
        default: return nil
        }
    }

    private static func fallbackTitle(for capture: Capture, source: Source) -> String {
        switch source {
        case .link: return capture.sourceURL ?? "Shared link"
        case .scan: return "Scan capture"
        case .dictation: return "Voice memo"
        case .typed: return "Text capture"
        }
    }

    private static func capturePreview(for capture: Capture, source: Source) -> String? {
        if source == .link, let sourceURL = capture.sourceURL, !sourceURL.isEmpty {
            return sourceURL
        }
        return preview(capture.text)
    }

    private static func searchableText(title: String, preview: String?, extra: String? = nil) -> String {
        [title, preview, extra]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        values.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }.first
    }

    private static func cleanTitle(_ value: String?, fallback: String) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return fallback
        }
        return value
    }

    private static func title(from text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(64))
    }

    private static func preview(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return String(text.prefix(96))
    }

    private static func relativeListTime(from date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        if let weekAgo = calendar.date(byAdding: .day, value: -6, to: Date()), date >= weekAgo {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
