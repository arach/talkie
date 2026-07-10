//
//  HomeFeed.swift
//  Talkie iOS
//
//  Persistence-backed data source for HomeNextView (M1).
//

import CoreData
import Foundation
import SwiftUI
import TalkieMobileKit

@MainActor
final class HomeFeed: ObservableObject {
    enum ContentFilter: String, CaseIterable {
        case all = "All"
        case memos = "Memos"
        case dictations = "Dictations"
        case captures = "Items"

        var label: String { rawValue }

        var icon: String {
            switch self {
            case .all: return "tray.full"
            case .memos: return "waveform"
            case .dictations: return "keyboard"
            case .captures: return "tray.and.arrow.down"
            }
        }
    }

    enum SortOption: String, CaseIterable {
        case dateNewest = "Newest First"
        case dateOldest = "Oldest First"
        case title = "Title (A-Z)"
        case duration = "Duration"

        var label: String { rawValue }

        var menuIcon: String {
            switch self {
            case .dateNewest: return "arrow.down"
            case .dateOldest: return "arrow.up"
            case .title: return "textformat"
            case .duration: return "clock"
            }
        }
    }

    @Published var recentItems: [RecentItem]
    @Published private(set) var totalRecentCount: Int
    @Published private(set) var isLoading: Bool
    @Published private(set) var errorMessage: String?

    @Published var searchText: String = "" {
        didSet {
            guard searchText != oldValue else { return }
            displayLimit = Self.defaultDisplayLimit
            reload()
        }
    }

    @Published var contentFilter: ContentFilter = .all {
        didSet {
            guard contentFilter != oldValue else { return }
            displayLimit = Self.defaultDisplayLimit
            refreshRecentItems()
        }
    }

    @Published var sortOption: SortOption = .dateNewest {
        didSet {
            guard sortOption != oldValue else { return }
            refreshRecentItems()
        }
    }

    @Published private(set) var displayLimit: Int

    struct RecentItem: Identifiable {
        let id: String
        let source: Source
        let title: String
        let preview: String?
        let meta: String?
        let relativeTime: String   // "9:34 AM", "Yesterday", "Mon"
        let syncStatus: SyncStatus?
        let canPromoteToMemo: Bool
        // True only while the background transcription pass is running for
        // this memo (VoiceMemo.isTranscribing). Non-memo sources never are.
        var isTranscribing: Bool = false

        enum Source { case dictation, typed, link, scan }
    }

    enum SyncStatus { case synced, pending }

    struct TodayStats: Equatable {
        let memos: Int
        let dictations: Int
        let items: Int

        static let empty = TodayStats(memos: 0, dictations: 0, items: 0)
    }

    /// Derived instrument model for the Home cockpit (Message Line · Take Log ·
    /// the Roll). Computed once per `reload()` from the SAME unfiltered fetch the
    /// feed already runs — no second feed, no extra fetch, and independent of the
    /// search box / content filter. "Takes" = the tape universe: voice memos +
    /// keyboard dictations + captures (typed compose notes are not takes).
    struct CockpitModel: Equatable {
        /// Every take on the tape (drives the milestone + empty-library facts).
        var totalTakes: Int
        /// The freshest take's date (drives the recency fact); nil when empty.
        var lastTakeDate: Date?
        /// `rollWeeks * rollDaysPerWeek` day intensities (0 = none · 1–3), oldest→newest.
        var rollDays: [Int]
        /// Index of today's cell inside `rollDays` (its real weekday column slot).
        var todayIndex: Int
        /// Trailing consecutive capture-day run ending on today (or yesterday).
        var streak: Int

        // ── GAUGES · derived in the SAME reload pass (no extra fetch) ──
        /// Takes captured today (uncapped — the TAKES gauge readout).
        var todayTakes: Int
        /// Σ capture seconds today (the TIME gauge readout, m:ss).
        var todayDurationSeconds: Double
        /// Trailing 7-day mean takes/day, EXCLUDING today — the TAKES meter baseline tick.
        var avgTakes: Double
        /// Trailing 7-day mean seconds/day, EXCLUDING today — the TIME meter baseline tick.
        var avgDurationSeconds: Double
        /// Last 12 days' activity (oldest→newest, newest = today) — the STRK Life-in-Dots.
        var last12Days: [Bool]

        var isEmpty: Bool { totalTakes == 0 }

        static let empty = CockpitModel(
            totalTakes: 0, lastTakeDate: nil, rollDays: [], todayIndex: 0, streak: 0,
            todayTakes: 0, todayDurationSeconds: 0, avgTakes: 0, avgDurationSeconds: 0, last12Days: []
        )
    }

    @Published private(set) var todayStats: TodayStats

    /// See `CockpitModel`. Consumed by `HomeCockpit`; recomputed each `reload()`.
    @Published private(set) var cockpit: CockpitModel = .empty
    var hasMoreRecentItems: Bool { totalRecentCount > displayLimit }
    var remainingRecentItems: Int { max(0, totalRecentCount - displayLimit) }
    var isSearching: Bool { !normalizedSearchText.isEmpty }

    private static let defaultDisplayLimit = 10
    private static let pageSize = 10

    private var entries: [Entry] = []

    init() {
        self.recentItems = []
        self.totalRecentCount = 0
        self.isLoading = false
        self.errorMessage = nil
        self.displayLimit = Self.defaultDisplayLimit
        self.todayStats = .empty
        reload()
    }

    func reload() {
        isLoading = true
        defer { isLoading = false }

        let context = PersistenceController.shared.container.viewContext

        do {
            let unfilteredMemos = try Self.fetchVoiceMemos(context: context)
            let unfilteredNotes = try Self.fetchComposeNotes(context: context)
            let filteredMemos = try Self.fetchVoiceMemos(context: context, matching: normalizedSearchText)
            let filteredNotes = try Self.fetchComposeNotes(context: context, matching: normalizedSearchText)

            KeyboardDictationStore.shared.reload()
            CaptureStore.shared.reload()
            let dictations = KeyboardDictationStore.shared.all()
            let captures = CaptureStore.shared.all()

            let matchingDictations = Self.filter(dictations: dictations, matching: normalizedSearchText)
            let matchingCaptures = Self.filter(captures: captures, matching: normalizedSearchText)
            todayStats = Self.makeTodayStats(
                memos: unfilteredMemos,
                notes: unfilteredNotes,
                dictations: dictations,
                captures: captures
            )
            cockpit = Self.makeCockpit(
                memos: unfilteredMemos,
                dictations: dictations,
                captures: captures
            )

            entries = Self.makeEntries(
                memos: filteredMemos,
                notes: filteredNotes,
                dictations: matchingDictations,
                captures: matchingCaptures
            )

            errorMessage = nil
            refreshRecentItems()
        } catch {
            errorMessage = "Couldn’t load recent items."
            entries = []
            recentItems = []
            totalRecentCount = 0
            cockpit = .empty
            AppLogger.persistence.error("Failed to load home feed: \(error.localizedDescription)")
        }
    }

    func loadMoreRecentItems() {
        displayLimit += Self.pageSize
        refreshRecentItems()
    }

    func delete(_ item: RecentItem) {
        switch item.source {
        case .dictation:
            VoiceMemoStore.shared.delete(id: item.id)
        case .typed:
            if ComposeNoteStore.delete(id: item.id) {
                // ComposeNoteStore posts .composeNotesDidChange.
            } else if let uuid = UUID(uuidString: item.id) {
                KeyboardDictationStore.shared.delete(uuid)
            }
        case .link, .scan:
            if let uuid = UUID(uuidString: item.id),
               let capture = CaptureStore.shared.all().first(where: { $0.id == uuid }) {
                CaptureStore.shared.delete(capture)
            }
        }

        reload()
    }

    func promoteToMemo(_ item: RecentItem) {
        guard item.canPromoteToMemo,
              let uuid = UUID(uuidString: item.id),
              let dictation = KeyboardDictationStore.shared.all().first(where: { $0.id == uuid }) else {
            return
        }
        if VoiceMemoStore.shared.promoteKeyboardDictation(dictation) {
            reload()
        }
    }

    private func refreshRecentItems() {
        let filtered = entries
            .filter { entry in contentFilter.matches(entry.origin) }
            .sorted(using: sortOption)

        totalRecentCount = filtered.count
        recentItems = filtered
            .prefix(displayLimit)
            .map { entry in
                RecentItem(
                    id: entry.id,
                    source: entry.source,
                    title: entry.title,
                    preview: entry.preview,
                    meta: entry.meta,
                    relativeTime: Self.relativeListTime(from: entry.updatedAt),
                    syncStatus: entry.syncStatus,
                    canPromoteToMemo: entry.origin == .keyboardDictation,
                    isTranscribing: entry.isTranscribing
                )
            }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Cockpit constants + shared formatters

extension HomeFeed {
    // ── The Roll geometry — mirrors the studio grid (CockpitGrid.tsx). ──
    /// Week columns in the Roll.
    static let rollWeeks = 18
    /// Day rows per column (Sun→Sat).
    static let rollDaysPerWeek = 7

    /// Compact uppercase relative age for terminal readouts — "NOW" · "20M" ·
    /// "2H" · "1D" · "3W" · "2MO". No "ago" suffix (the Take Log lane is fixed-width).
    nonisolated static func compactAge(from date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "NOW" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)M" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)H" }
        let days = hours / 24
        if days < 7 { return "\(days)D" }
        let weeks = days / 7
        if weeks < 5 { return "\(weeks)W" }
        let months = days / 30
        return "\(max(1, months))MO"
    }

    /// Duration as "m:ss" — "0:42", "6:30".
    nonisolated static func compactDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}

private extension HomeFeed.ContentFilter {
    func matches(_ origin: HomeFeed.Entry.Origin) -> Bool {
        switch self {
        case .all:
            return true
        case .memos:
            return origin == .memo
        case .dictations:
            return origin == .composeNote || origin == .keyboardDictation
        case .captures:
            return origin == .capture
        }
    }
}

private extension Array where Element == HomeFeed.Entry {
    func sorted(using option: HomeFeed.SortOption) -> [HomeFeed.Entry] {
        switch option {
        case .dateNewest:
            return sorted { $0.updatedAt > $1.updatedAt }
        case .dateOldest:
            return sorted { $0.updatedAt < $1.updatedAt }
        case .title:
            return sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .duration:
            return sorted { $0.durationSeconds > $1.durationSeconds }
        }
    }
}

private extension HomeFeed {
    struct Entry {
        enum Origin { case memo, composeNote, keyboardDictation, capture }

        let id: String
        let kind: String
        let origin: Origin
        let source: RecentItem.Source
        let title: String
        let preview: String?
        let meta: String?
        let syncStatus: SyncStatus?
        let wordCount: Int
        let durationSeconds: Double
        let updatedAt: Date
        var isTranscribing: Bool = false
    }

    static func fetchVoiceMemos(
        context: NSManagedObjectContext,
        matching query: String = ""
    ) throws -> [VoiceMemo] {
        let request: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
        if !query.isEmpty {
            request.predicate = NSPredicate(
                format: "title CONTAINS[cd] %@ OR transcription CONTAINS[cd] %@ OR summary CONTAINS[cd] %@ OR notes CONTAINS[cd] %@",
                query,
                query,
                query,
                query
            )
        }
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \VoiceMemo.lastModified, ascending: false),
            NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false),
        ]
        request.fetchLimit = 200
        return try context.fetch(request)
    }

    static func fetchComposeNotes(
        context: NSManagedObjectContext,
        matching query: String = ""
    ) throws -> [ComposeNote] {
        let request: NSFetchRequest<ComposeNote> = ComposeNote.fetchRequest()
        if !query.isEmpty {
            request.predicate = NSPredicate(
                format: "title CONTAINS[cd] %@ OR content CONTAINS[cd] %@",
                query,
                query
            )
        }
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ComposeNote.lastModified, ascending: false),
            NSSortDescriptor(keyPath: \ComposeNote.createdAt, ascending: false),
        ]
        request.fetchLimit = 200
        return try context.fetch(request)
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
                origin: .memo,
                source: .dictation,
                title: title,
                preview: preview(body),
                meta: memoMeta(for: memo),
                syncStatus: memo.cloudSyncedAt == nil ? .pending : .synced,
                wordCount: wordCount(body ?? title),
                durationSeconds: memo.duration,
                updatedAt: memo.lastModified ?? memo.createdAt ?? .distantPast,
                isTranscribing: memo.isTranscribing
            )
        }

        let noteEntries = notes.map { note in
            let title = cleanTitle(note.title, fallback: "Untitled note")
            return Entry(
                id: note.id?.uuidString ?? note.objectID.uriRepresentation().absoluteString,
                kind: "Compose",
                origin: .composeNote,
                source: .typed,
                title: title,
                preview: preview(note.content),
                meta: nil,
                syncStatus: nil,
                wordCount: wordCount(note.content ?? title),
                durationSeconds: 0,
                updatedAt: note.lastModified ?? note.createdAt ?? .distantPast
            )
        }

        let dictationEntries = dictations.map { dictation in
            Entry(
                id: dictation.id.uuidString,
                kind: "Type",
                origin: .keyboardDictation,
                source: .typed,
                title: title(from: dictation.text, fallback: "Keyboard dictation"),
                preview: preview(dictation.text),
                meta: dictationMeta(for: dictation),
                syncStatus: nil,
                wordCount: dictation.wordCount,
                durationSeconds: dictation.durationSeconds ?? 0,
                updatedAt: dictation.timestamp
            )
        }

        let captureEntries = captures.map { capture in
            let source = source(for: capture)
            return Entry(
                id: capture.id.uuidString,
                kind: kind(for: capture),
                origin: .capture,
                source: source,
                title: cleanTitle(capture.title, fallback: title(from: capture.text, fallback: fallbackTitle(for: capture))),
                preview: capture.sourceURL?.isEmpty == false ? capture.sourceURL : preview(capture.text),
                meta: capture.syncedToMac ? "Synced to Mac" : "Not synced",
                syncStatus: capture.syncedToMac ? .synced : .pending,
                wordCount: capture.wordCount,
                durationSeconds: 0,
                updatedAt: capture.timestamp
            )
        }

        return memoEntries + noteEntries + dictationEntries + captureEntries
    }

    static func filter(dictations: [KeyboardDictation], matching query: String) -> [KeyboardDictation] {
        guard !query.isEmpty else { return dictations }
        return dictations.filter { dictation in
            dictation.text.localizedStandardContains(query)
                || (dictation.appContext?.localizedStandardContains(query) ?? false)
        }
    }

    static func filter(captures: [Capture], matching query: String) -> [Capture] {
        guard !query.isEmpty else { return captures }
        return captures.filter { capture in
            capture.title?.localizedStandardContains(query) == true
                || capture.text.localizedStandardContains(query)
                || capture.sourceURL?.localizedStandardContains(query) == true
                || capture.sourceType.localizedStandardContains(query)
        }
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

    static func memoMeta(for memo: VoiceMemo) -> String? {
        guard memo.duration > 0 || (memo.fileURL?.isEmpty == false) else { return nil }
        var parts: [String] = []
        if memo.duration > 0 {
            parts.append(estimatedFileSize(forDuration: memo.duration))
        }
        if let format = audioFormat(from: memo.fileURL) {
            parts.append(format)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func dictationMeta(for dictation: KeyboardDictation) -> String? {
        var parts: [String] = [formatWordCount(dictation.wordCount)]
        if let duration = dictation.durationSeconds, duration > 0 {
            parts.append(formatDuration(duration))
        }
        if let context = dictation.appContext?.trimmingCharacters(in: .whitespacesAndNewlines), !context.isEmpty {
            parts.append(context)
        }
        return parts.joined(separator: " · ")
    }

    static func estimatedFileSize(forDuration duration: Double) -> String {
        let bytes = Int(max(1, duration) * 16 * 1024)
        return formatBytes(bytes)
    }

    static func audioFormat(from fileURL: String?) -> String? {
        guard let fileURL, !fileURL.isEmpty else { return nil }
        let ext = URL(fileURLWithPath: fileURL).pathExtension
        return ext.isEmpty ? "Audio" : ext.uppercased()
    }

    static func formatBytes(_ bytes: Int) -> String {
        if bytes >= 1_048_576 {
            let tenths = (bytes * 10) / 1_048_576
            let whole = tenths / 10
            let fraction = tenths % 10
            return fraction == 0 ? "~\(whole) MB" : "~\(whole).\(fraction) MB"
        }
        let kb = max(1, bytes / 1024)
        return "~\(kb) KB"
    }

    static func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
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

    static func makeTodayStats(
        memos: [VoiceMemo],
        notes: [ComposeNote],
        dictations: [KeyboardDictation],
        captures: [Capture]
    ) -> TodayStats {
        let calendar = Calendar.current
        return TodayStats(
            memos: memos.filter { calendar.isDateInToday($0.createdAt ?? $0.lastModified ?? .distantPast) }.count,
            dictations: notes.filter { calendar.isDateInToday($0.createdAt ?? $0.lastModified ?? .distantPast) }.count
                + dictations.filter { calendar.isDateInToday($0.timestamp) }.count,
            items: captures.filter { calendar.isDateInToday($0.timestamp) }.count
        )
    }

    /// Build the cockpit instrument model from the tape universe (memos +
    /// dictations + captures). One pass over each already-fetched array — the
    /// Roll day buckets, the streak, the gauge totals, and the message-line facts
    /// all derive from the same raw list. Notes are excluded (they aren't "takes").
    static func makeCockpit(
        memos: [VoiceMemo],
        dictations: [KeyboardDictation],
        captures: [Capture],
        now: Date = Date()
    ) -> CockpitModel {
        struct Raw { let date: Date; let duration: Double }
        var raws: [Raw] = []
        raws.reserveCapacity(memos.count + dictations.count + captures.count)

        for memo in memos {
            raws.append(Raw(date: memo.createdAt ?? memo.lastModified ?? .distantPast, duration: memo.duration))
        }
        for dictation in dictations {
            raws.append(Raw(date: dictation.timestamp, duration: dictation.durationSeconds ?? 0))
        }
        for capture in captures {
            raws.append(Raw(date: capture.timestamp, duration: 0))
        }

        // Newest-first only for the freshest-take fact (the Take Log is retired).
        let sorted = raws.sorted { $0.date > $1.date }

        // The Roll — bucket each take's day into the trailing 18-week grid.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let weekdayRow = calendar.component(.weekday, from: today) - 1 // 0 = Sunday
        let todayIndex = (rollWeeks - 1) * rollDaysPerWeek + weekdayRow
        var days = [Int](repeating: 0, count: rollWeeks * rollDaysPerWeek)

        // GAUGES — today's totals + the trailing 7-day (pre-today) daily totals,
        // derived in this SAME pass over `raws`.
        var todayTakes = 0
        var todayDuration = 0.0
        var prevTakes = 0
        var prevDuration = 0.0
        for raw in raws {
            let day = calendar.startOfDay(for: raw.date)
            guard let offset = calendar.dateComponents([.day], from: day, to: today).day else { continue }
            // Roll bucket (in-window, not future).
            let index = todayIndex - offset
            if index >= 0, index <= todayIndex {
                days[index] = min(3, days[index] + 1)
            }
            // Gauge buckets — today vs the trailing 7 days before today.
            if offset == 0 {
                todayTakes += 1
                todayDuration += raw.duration
            } else if offset >= 1, offset <= 7 {
                prevTakes += 1
                prevDuration += raw.duration
            }
        }
        let avgTakes = Double(prevTakes) / 7.0
        let avgDuration = prevDuration / 7.0

        // Last 12 days' activity (oldest→newest, newest = today) from the Roll grid.
        var last12 = [Bool](repeating: false, count: 12)
        for i in 0..<12 {
            let index = todayIndex - (11 - i)
            last12[i] = index >= 0 && index < days.count && days[index] > 0
        }

        return CockpitModel(
            totalTakes: raws.count,
            lastTakeDate: sorted.first?.date,
            rollDays: days,
            todayIndex: todayIndex,
            streak: rollStreak(days: days, todayIndex: todayIndex),
            todayTakes: todayTakes,
            todayDurationSeconds: todayDuration,
            avgTakes: avgTakes,
            avgDurationSeconds: avgDuration,
            last12Days: last12
        )
    }

    /// Length of the trailing consecutive capture-day run ending on today — or on
    /// yesterday when today has no take yet (the streak is still alive). Mirrors
    /// the studio `streakRun` derivation exactly.
    static func rollStreak(days: [Int], todayIndex: Int) -> Int {
        var end = -1
        if todayIndex < days.count, days[todayIndex] > 0 { end = todayIndex }
        else if todayIndex - 1 >= 0, days[todayIndex - 1] > 0 { end = todayIndex - 1 }
        guard end >= 0 else { return 0 }
        var count = 0
        var i = end
        while i >= 0, days[i] > 0 { count += 1; i -= 1 }
        return count
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
