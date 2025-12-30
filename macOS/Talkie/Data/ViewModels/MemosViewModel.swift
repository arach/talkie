//
//  MemosViewModel.swift
//  Talkie
//
//  ViewModel for All Memos view
//  Handles pagination, sorting, search - all backed by efficient GRDB queries
//

import Foundation
import SwiftUI
import CoreData
import TalkieKit

private let log = Log(.database)

// MARK: - Memo Filters

enum MemoFilter: Hashable, Identifiable {
    case shortRecordings  // Under 30 seconds
    case source(MemoModel.Source)

    var id: String {
        switch self {
        case .shortRecordings: return "short"
        case .source(let source): return "source-\(source.displayName)"
        }
    }

    var displayName: String {
        switch self {
        case .shortRecordings: return "Short"
        case .source(let source): return source.displayName
        }
    }

    var icon: String {
        switch self {
        case .shortRecordings: return "clock"
        case .source(let source): return source.icon
        }
    }

    var color: Color {
        switch self {
        case .shortRecordings: return .orange
        case .source(let source): return source.color
        }
    }
}

// MARK: - Memos ViewModel

@MainActor
@Observable
final class MemosViewModel {
    // MARK: - Singleton

    /// Shared instance for views to use
    static let shared = MemosViewModel()

    // MARK: - Published State

    var memos: [MemoModel] = []
    var isLoading = false
    var error: Error?

    // Sort & Filter
    var sortField: MemoModel.SortField = .timestamp
    var sortAscending = false
    var searchQuery = ""
    var activeFilters: Set<MemoFilter> = []

    // Pagination
    var totalCount = 0
    private var currentOffset = 0
    private let pageSize = 50

    // MARK: - Aggregation Stats (for dashboards)

    var todayCount = 0
    var thisWeekCount = 0
    var totalDuration: Double = 0  // seconds
    var heatmapData: [String: Int] = [:]  // yyyy-MM-dd → count

    // MARK: - Filtered Memo Lists (for workflows)

    var transcribedMemos: [MemoModel] = []
    var untranscribedMemos: [MemoModel] = []

    // MARK: - Dependencies

    private let repository: any MemoRepository

    // MARK: - Computed Properties

    var hasMorePages: Bool {
        memos.count < totalCount
    }

    var displayedCount: Int {
        memos.count
    }

    /// Formatted total duration (HH:mm:ss)
    var formattedTotalDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        let seconds = Int(totalDuration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    // MARK: - Init

    init(repository: any MemoRepository = LocalRepository()) {
        self.repository = repository
    }

    // MARK: - Actions

    /// Load first page of memos
    func loadMemos() async {
        isLoading = true
        error = nil
        currentOffset = 0

        do {
            // Fetch in parallel: count + first page
            async let count = repository.countMemos(
                searchQuery: searchQuery.isEmpty ? nil : searchQuery,
                filters: activeFilters
            )
            async let firstPage = repository.fetchMemos(
                sortBy: sortField,
                ascending: sortAscending,
                limit: pageSize,
                offset: 0,
                searchQuery: searchQuery.isEmpty ? nil : searchQuery,
                filters: activeFilters
            )

            totalCount = try await count
            memos = try await firstPage
        } catch {
            self.error = error
            self.memos = []
        }

        isLoading = false
    }

    /// Load next page (infinite scroll)
    func loadNextPage() async {
        guard !isLoading, hasMorePages else { return }

        isLoading = true
        currentOffset += pageSize

        do {
            let nextPage = try await repository.fetchMemos(
                sortBy: sortField,
                ascending: sortAscending,
                limit: pageSize,
                offset: currentOffset,
                searchQuery: searchQuery.isEmpty ? nil : searchQuery,
                filters: activeFilters
            )

            memos.append(contentsOf: nextPage)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// Change sort field
    func changeSortField(_ field: MemoModel.SortField) async {
        guard field != sortField else {
            // Same field - toggle direction
            sortAscending.toggle()
            await loadMemos()
            return
        }

        sortField = field
        sortAscending = false  // Default to descending for new field
        await loadMemos()
    }

    /// Refresh (pull-to-refresh style)
    func refresh() async {
        await loadMemos()
    }

    /// Delete memo from both GRDB and CoreData (triggers CloudKit sync)
    func deleteMemo(_ memo: MemoModel) async {
        await deleteMemos([memo.id])
    }

    /// Soft delete memos (marks for deletion, requires approval in Cloud Manager)
    func deleteMemos(_ ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }

        log.info("Soft deleting \(ids.count) memo(s): \(ids.map { $0.uuidString.prefix(8) }.joined(separator: ", "))")

        do {
            // Soft delete in GRDB (set deletedAt timestamp)
            try await repository.softDeleteMemos(ids: ids)
            log.info("  Marked \(ids.count) memo(s) for deletion")

            // Remove from local array (they're now filtered out)
            let beforeCount = memos.count
            memos.removeAll { ids.contains($0.id) }
            let removed = beforeCount - memos.count
            totalCount -= removed

            log.info("  UI: removed \(removed) from view, total now \(self.totalCount)")
            log.info("  Pending deletion - approve in Cloud Manager to permanently delete")
        } catch {
            log.error("Soft delete failed: \(error.localizedDescription)")
            self.error = error
        }
    }

    /// Permanently delete memos (called from Cloud Manager after approval)
    func permanentlyDeleteMemos(_ ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }

        log.info("Permanently deleting \(ids.count) memo(s)")

        do {
            // 1. Delete from CoreData (triggers CloudKit sync)
            let coreDataDeleted = await deleteFromCoreData(ids: ids)
            log.info("  CoreData: deleted \(coreDataDeleted) record(s)")

            // 2. Hard delete from GRDB
            for id in ids {
                try await repository.hardDeleteMemo(id: id)
            }
            log.info("  GRDB: hard deleted \(ids.count) record(s)")
        } catch {
            log.error("Permanent delete failed: \(error.localizedDescription)")
            self.error = error
        }
    }

    /// Restore soft-deleted memos
    func restoreMemos(_ ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }

        log.info("Restoring \(ids.count) memo(s)")

        do {
            for id in ids {
                try await repository.restoreMemo(id: id)
            }
            log.info("  Restored \(ids.count) memo(s)")

            // Refresh to show restored memos
            await loadMemos()
        } catch {
            log.error("Restore failed: \(error.localizedDescription)")
            self.error = error
        }
    }

    /// Fetch memos pending deletion (for Cloud Manager)
    func fetchPendingDeletions() async -> [MemoModel] {
        do {
            return try await repository.fetchPendingDeletions()
        } catch {
            log.error("Failed to fetch pending deletions: \(error.localizedDescription)")
            return []
        }
    }

    /// Count memos pending deletion
    func countPendingDeletions() async -> Int {
        do {
            return try await repository.countPendingDeletions()
        } catch {
            return 0
        }
    }

    /// Delete from CoreData (triggers CloudKit sync for remote deletion)
    /// Returns number of records deleted
    private func deleteFromCoreData(ids: Set<UUID>) async -> Int {
        let context = PersistenceController.shared.container.viewContext

        var deletedCount = 0

        await context.perform {
            for id in ids {
                let fetchRequest: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                fetchRequest.fetchLimit = 1

                if let results = try? context.fetch(fetchRequest),
                   let memo = results.first {
                    log.debug("  Deleting CoreData memo: \(memo.title ?? "untitled")")
                    context.delete(memo)
                    deletedCount += 1
                } else {
                    log.debug("  CoreData memo not found for id: \(id.uuidString.prefix(8))")
                }
            }

            do {
                try context.save()
                log.debug("  CoreData context saved successfully")
            } catch {
                log.error("  CoreData save failed: \(error.localizedDescription)")
            }
        }

        return deletedCount
    }

    /// Search (debounced via Combine in view)
    func search(query: String) async {
        searchQuery = query
        await loadMemos()
    }

    // MARK: - Aggregation Stats

    /// Load dashboard stats (today, week, duration, heatmap)
    func loadStats() async {
        do {
            async let today = repository.countMemosToday()
            async let week = repository.countMemosThisWeek()
            async let duration = repository.totalDuration()
            async let heatmap = repository.fetchHeatmapData(days: 365)

            todayCount = try await today
            thisWeekCount = try await week
            totalDuration = try await duration
            heatmapData = try await heatmap
        } catch {
            log.error("Failed to load stats: \(error.localizedDescription)")
        }
    }

    /// Load just memo count (lighter weight for views that only need count)
    func loadCount() async {
        do {
            totalCount = try await repository.countMemos(searchQuery: nil, filters: [])
        } catch {
            log.error("Failed to load count: \(error.localizedDescription)")
        }
    }

    /// Load transcribed memos (for workflow memo selection)
    func loadTranscribedMemos() async {
        do {
            transcribedMemos = try await repository.fetchTranscribedMemos(limit: 100)
        } catch {
            log.error("Failed to load transcribed memos: \(error.localizedDescription)")
        }
    }

    /// Load untranscribed memos (for transcription workflows)
    func loadUntranscribedMemos() async {
        do {
            untranscribedMemos = try await repository.fetchUntranscribedMemos(limit: 100)
        } catch {
            log.error("Failed to load untranscribed memos: \(error.localizedDescription)")
        }
    }

    /// Load both transcribed and untranscribed memos (for workflow views)
    func loadWorkflowMemos() async {
        async let transcribed: () = loadTranscribedMemos()
        async let untranscribed: () = loadUntranscribedMemos()
        await transcribed
        await untranscribed
    }

    // MARK: - Filter Management

    /// Toggle a filter on/off
    func toggleFilter(_ filter: MemoFilter) async {
        if activeFilters.contains(filter) {
            activeFilters.remove(filter)
        } else {
            activeFilters.insert(filter)
        }
        await loadMemos()
    }

    /// Clear all filters
    func clearFilters() async {
        activeFilters.removeAll()
        await loadMemos()
    }

    /// Check if a filter is active
    func isFilterActive(_ filter: MemoFilter) -> Bool {
        activeFilters.contains(filter)
    }

    /// Get count of active filters
    var activeFilterCount: Int {
        activeFilters.count
    }

    /// Has any active filters
    var hasActiveFilters: Bool {
        !activeFilters.isEmpty
    }
}

// MARK: - Static Formatters (Performance)

extension MemosViewModel {
    /// Shared date formatter (created once, reused for all rows)
    static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        return f
    }()

    /// Shared duration formatter
    static func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Shared relative date formatter
    static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
