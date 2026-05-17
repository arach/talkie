//
//  HomeFeed.swift
//  Talkie iOS
//
//  Persistence-backed data source for HomeNextView (M1).
//

import CoreData
import SwiftUI
import TalkieMobileKit

@MainActor
final class HomeFeed: ObservableObject {
    @Published var lastDocument: PickUp?
    @Published var recentTally: Tally
    @Published var recentItems: [RecentItem]

    struct PickUp {
        let title: String
        let meta: String   // pre-formatted: "Compose · 31 words · 4m ago"
        let continueAction: () -> Void
    }

    struct Tally {
        let eyebrow: String      // "Last 24h · 9 captures" or "Quiet · long-press to capture"
        let cta: String?         // Optional right-side chip text ("Week ›")
        let cells: [Cell]        // typically 3; empty if no signal

        struct Cell {
            let value: String    // pre-formatted ("6", "1.2k")
            let label: String    // "Memos", "Type", "Grab"
        }
    }

    struct RecentItem: Identifiable {
        let id: String
        let source: Source
        let title: String
        let preview: String?
        let relativeTime: String   // "9:34 AM", "Yesterday", "Mon"

        enum Source { case dictation, typed, link, scan }
    }

    init() {
        let context = PersistenceController.shared.container.viewContext
        let memos = Self.fetchVoiceMemos(context: context)
        let notes = Self.fetchComposeNotes(context: context)

        KeyboardDictationStore.shared.reload()
        CaptureStore.shared.reload()
        let dictations = KeyboardDictationStore.shared.all()
        let captures = CaptureStore.shared.all()

        let entries = Self.makeEntries(
            memos: memos,
            notes: notes,
            dictations: dictations,
            captures: captures
        )

        let pickUpEntry = entries
            .filter { $0.kind == "Compose" }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
            ?? entries.sorted { $0.updatedAt > $1.updatedAt }.first

        self.lastDocument = pickUpEntry
            .map { entry in
                PickUp(
                    title: entry.title,
                    meta: "\(entry.kind) · \(Self.formatWordCount(entry.wordCount)) · \(Self.relativeAge(from: entry.updatedAt))",
                    continueAction: { AppShellRouter.shared.openCompose(documentID: entry.id) }
                )
            }

        self.recentTally = Self.makeTally(
            memos: memos,
            dictations: dictations,
            captures: captures
        )

        self.recentItems = entries
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(5)
            .map { entry in
                RecentItem(
                    id: entry.id,
                    source: entry.source,
                    title: entry.title,
                    preview: entry.preview,
                    relativeTime: Self.relativeListTime(from: entry.updatedAt)
                )
            }
    }
}

private extension HomeFeed {
    struct Entry {
        let id: String
        let kind: String
        let source: RecentItem.Source
        let title: String
        let preview: String?
        let wordCount: Int
        let updatedAt: Date
    }

    static func fetchVoiceMemos(context: NSManagedObjectContext) -> [VoiceMemo] {
        let request: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \VoiceMemo.lastModified, ascending: false),
            NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false),
        ]
        request.fetchLimit = 200
        return (try? context.fetch(request)) ?? []
    }

    static func fetchComposeNotes(context: NSManagedObjectContext) -> [ComposeNote] {
        let request: NSFetchRequest<ComposeNote> = ComposeNote.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ComposeNote.lastModified, ascending: false),
            NSSortDescriptor(keyPath: \ComposeNote.createdAt, ascending: false),
        ]
        request.fetchLimit = 200
        return (try? context.fetch(request)) ?? []
    }

    static func makeEntries(
        memos: [VoiceMemo],
        notes: [ComposeNote],
        dictations: [KeyboardDictation],
        captures: [Capture]
    ) -> [Entry] {
        let memoEntries = memos.map { memo in
            let title = cleanTitle(memo.title, fallback: "Untitled memo")
            let body = firstNonEmpty([memo.transcription, memo.summary, memo.notes])
            return Entry(
                id: memo.id?.uuidString ?? memo.objectID.uriRepresentation().absoluteString,
                kind: "Memo",
                source: .dictation,
                title: title,
                preview: preview(body),
                wordCount: wordCount(body ?? title),
                updatedAt: memo.lastModified ?? memo.createdAt ?? .distantPast
            )
        }

        let noteEntries = notes.map { note in
            let title = cleanTitle(note.title, fallback: "Untitled note")
            return Entry(
                id: note.id?.uuidString ?? note.objectID.uriRepresentation().absoluteString,
                kind: "Compose",
                source: .typed,
                title: title,
                preview: preview(note.content),
                wordCount: wordCount(note.content ?? title),
                updatedAt: note.lastModified ?? note.createdAt ?? .distantPast
            )
        }

        let dictationEntries = dictations.map { dictation in
            Entry(
                id: dictation.id.uuidString,
                kind: "Type",
                source: .typed,
                title: title(from: dictation.text, fallback: "Keyboard dictation"),
                preview: preview(dictation.text),
                wordCount: dictation.wordCount,
                updatedAt: dictation.timestamp
            )
        }

        let captureEntries = captures.map { capture in
            let source = source(for: capture)
            return Entry(
                id: capture.id.uuidString,
                kind: kind(for: capture),
                source: source,
                title: cleanTitle(capture.title, fallback: title(from: capture.text, fallback: fallbackTitle(for: capture))),
                preview: preview(capture.text),
                wordCount: capture.wordCount,
                updatedAt: capture.timestamp
            )
        }

        return memoEntries + noteEntries + dictationEntries + captureEntries
    }

    static func makeTally(memos: [VoiceMemo], dictations: [KeyboardDictation], captures: [Capture]) -> Tally {
        let windows: [(label: String, interval: TimeInterval, cta: String?)] = [
            ("Last 24h", 24 * 60 * 60, "Week ›"),
            ("Last 7 days", 7 * 24 * 60 * 60, "Month ›"),
            ("Last 30 days", 30 * 24 * 60 * 60, nil),
        ]
        let now = Date()

        for window in windows {
            let cutoff = now.addingTimeInterval(-window.interval)
            let memoCount = memos.filter { ($0.createdAt ?? .distantPast) >= cutoff }.count
            let typeCount = dictations.filter { $0.timestamp >= cutoff }.count
            let grabCount = captures.filter { $0.timestamp >= cutoff }.count
            let total = memoCount + typeCount + grabCount

            if total > 0 {
                return Tally(
                    eyebrow: "\(window.label) · \(total) \(total == 1 ? "capture" : "captures")",
                    cta: window.cta,
                    cells: [
                        Tally.Cell(value: compactCount(memoCount), label: "Memos"),
                        Tally.Cell(value: compactCount(typeCount), label: "Type"),
                        Tally.Cell(value: compactCount(grabCount), label: "Grab"),
                    ]
                )
            }
        }

        return Tally(
            eyebrow: "Quiet · long-press to capture",
            cta: nil,
            cells: []
        )
    }

    static func source(for capture: Capture) -> RecentItem.Source {
        switch capture.sourceType.lowercased() {
        case "url", "link", "web": return .link
        case "photo", "scan", "image", "document": return .scan
        default: return .typed
        }
    }

    static func kind(for capture: Capture) -> String {
        switch source(for: capture) {
        case .link: return "Link"
        case .scan: return "Grab"
        case .dictation: return "Memo"
        case .typed: return "Type"
        }
    }

    static func fallbackTitle(for capture: Capture) -> String {
        switch source(for: capture) {
        case .link: return capture.sourceURL ?? "Shared link"
        case .scan: return "Scan capture"
        case .dictation: return "Voice memo"
        case .typed: return "Text capture"
        }
    }

    static func firstNonEmpty(_ values: [String?]) -> String? {
        values.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }.first
    }

    static func cleanTitle(_ value: String?, fallback: String) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return fallback
        }
        return value
    }

    static func title(from text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(64))
    }

    static func preview(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return String(text.prefix(96))
    }

    static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    static func formatWordCount(_ count: Int) -> String {
        "\(count) \(count == 1 ? "word" : "words")"
    }

    static func compactCount(_ count: Int) -> String {
        if count >= 10_000 {
            return "\(count / 1_000)k"
        }
        if count >= 1_000 {
            let tenths = count / 100
            let whole = tenths / 10
            let fraction = tenths % 10
            return fraction == 0 ? "\(whole)k" : "\(whole).\(fraction)k"
        }
        return "\(count)"
    }

    static func relativeAge(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 7 { return "\(days)d ago" }
        let weeks = days / 7
        if weeks < 5 { return "\(weeks)w ago" }
        let months = days / 30
        return "\(max(1, months))mo ago"
    }

    static func relativeListTime(from date: Date) -> String {
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
