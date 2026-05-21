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

    struct Item: Identifiable {
        let id: String
        let source: Source
        let title: String
        let preview: String?
        let relativeTime: String
    }

    @Published private(set) var memos: [Item]
    @Published private(set) var dictations: [Item]
    @Published private(set) var items: [Item]

    @Published private(set) var memosTotal: Int
    @Published private(set) var dictationsTotal: Int
    @Published private(set) var itemsTotal: Int

    @Published private(set) var earlierMemos: Int
    @Published private(set) var earlierDictations: Int
    @Published private(set) var earlierItems: Int

    init() {
        self.memos = []
        self.dictations = []
        self.items = []
        self.memosTotal = 0
        self.dictationsTotal = 0
        self.itemsTotal = 0
        self.earlierMemos = 0
        self.earlierDictations = 0
        self.earlierItems = 0
        reload()
    }

    func reload() {
        let context = PersistenceController.shared.container.viewContext
        let memos = Self.fetchVoiceMemos(context: context)
        let notes = Self.fetchComposeNotes(context: context)

        KeyboardDictationStore.shared.reload()
        CaptureStore.shared.reload()
        let keyboardDictations = KeyboardDictationStore.shared.all()
        let captures = CaptureStore.shared.all()

        let memoBucket = Self.bucket(Self.memoEntries(from: memos), limit: Self.visibleLimit)
        let dictationBucket = Self.bucket(
            Self.noteEntries(from: notes) + Self.keyboardEntries(from: keyboardDictations),
            limit: Self.visibleLimit
        )
        let itemBucket = Self.bucket(Self.captureItemEntries(from: captures), limit: Self.visibleLimit)

        self.memos = memoBucket.visible
        self.dictations = dictationBucket.visible
        self.items = itemBucket.visible

        self.memosTotal = memoBucket.total
        self.dictationsTotal = dictationBucket.total
        self.itemsTotal = itemBucket.total

        self.earlierMemos = memoBucket.earlier
        self.earlierDictations = dictationBucket.earlier
        self.earlierItems = itemBucket.earlier
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

    func items(for tab: LibraryTab) -> [Item] {
        switch tab {
        case .memos:      return memos
        case .dictations: return dictations
        case .items:      return items
        }
    }

    func totalCount(for tab: LibraryTab) -> Int {
        switch tab {
        case .memos:      return memosTotal
        case .dictations: return dictationsTotal
        case .items:      return itemsTotal
        }
    }

    func earlierCount(for tab: LibraryTab) -> Int {
        switch tab {
        case .memos:      return earlierMemos
        case .dictations: return earlierDictations
        case .items:      return earlierItems
        }
    }

    // MARK: - Persistence-backed feed

    private static let visibleLimit = 8
    private static let recentWindow: TimeInterval = 7 * 24 * 60 * 60

    private struct Entry {
        let item: Item
        let updatedAt: Date
    }

    private static func bucket(_ entries: [Entry], limit: Int) -> (visible: [Item], total: Int, earlier: Int) {
        let cutoff = Date().addingTimeInterval(-recentWindow)
        let recent = entries
            .filter { $0.updatedAt >= cutoff }
            .sorted { $0.updatedAt > $1.updatedAt }
        let visible = recent.prefix(limit).map(\.item)
        return (Array(visible), recent.count, max(0, recent.count - limit))
    }

    private static func fetchVoiceMemos(context: NSManagedObjectContext) -> [VoiceMemo] {
        let request: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \VoiceMemo.lastModified, ascending: false),
            NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false),
        ]
        request.fetchLimit = 200
        return (try? context.fetch(request)) ?? []
    }

    private static func fetchComposeNotes(context: NSManagedObjectContext) -> [ComposeNote] {
        let request: NSFetchRequest<ComposeNote> = ComposeNote.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ComposeNote.lastModified, ascending: false),
            NSSortDescriptor(keyPath: \ComposeNote.createdAt, ascending: false),
        ]
        request.fetchLimit = 200
        return (try? context.fetch(request)) ?? []
    }

    private static func memoEntries(from memos: [VoiceMemo]) -> [Entry] {
        memos.map { memo in
            let updatedAt = memo.lastModified ?? memo.createdAt ?? .distantPast
            let body = firstNonEmpty([memo.transcription, memo.summary, memo.notes])
            return Entry(
                item: Item(
                    id: memo.id?.uuidString ?? memo.objectID.uriRepresentation().absoluteString,
                    source: .dictation,
                    title: cleanTitle(memo.title, fallback: "Untitled memo"),
                    preview: preview(body),
                    relativeTime: relativeListTime(from: updatedAt)
                ),
                updatedAt: updatedAt
            )
        }
    }

    private static func noteEntries(from notes: [ComposeNote]) -> [Entry] {
        notes.map { note in
            let updatedAt = note.lastModified ?? note.createdAt ?? .distantPast
            let title = cleanTitle(note.title, fallback: title(from: note.content ?? "", fallback: "Untitled note"))
            return Entry(
                item: Item(
                    id: note.id?.uuidString ?? note.objectID.uriRepresentation().absoluteString,
                    source: .typed,
                    title: title,
                    preview: preview(note.content),
                    relativeTime: relativeListTime(from: updatedAt)
                ),
                updatedAt: updatedAt
            )
        }
    }

    private static func keyboardEntries(from dictations: [KeyboardDictation]) -> [Entry] {
        dictations.map { dictation in
            Entry(
                item: Item(
                    id: dictation.id.uuidString,
                    source: .typed,
                    title: title(from: dictation.text, fallback: "Keyboard dictation"),
                    preview: preview(dictation.text),
                    relativeTime: relativeListTime(from: dictation.timestamp)
                ),
                updatedAt: dictation.timestamp
            )
        }
    }

    private static func captureItemEntries(from captures: [Capture]) -> [Entry] {
        captures.compactMap { capture in
            guard let source = itemSource(for: capture) else { return nil }
            let fallback = fallbackTitle(for: capture, source: source)
            return Entry(
                item: Item(
                    id: capture.id.uuidString,
                    source: source,
                    title: cleanTitle(capture.title, fallback: title(from: capture.text, fallback: fallback)),
                    preview: capturePreview(for: capture, source: source),
                    relativeTime: relativeListTime(from: capture.timestamp)
                ),
                updatedAt: capture.timestamp
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
