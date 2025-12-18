//
//  MemosViewModel.swift
//  Talkie
//
//  ViewModel for All Memos view
//  Handles pagination, sorting, search - all backed by efficient GRDB queries
//

import Foundation
import SwiftUI

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
final class MemosViewModel: ObservableObject {
    // MARK: - Published State

    @Published var memos: [MemoModel] = []
    @Published var isLoading = false
    @Published var error: Error?

    // Sort & Filter
    @Published var sortField: MemoModel.SortField = .timestamp
    @Published var sortAscending = false
    @Published var searchQuery = ""
    @Published var activeFilters: Set<MemoFilter> = []

    // Pagination
    @Published var totalCount = 0
    private var currentOffset = 0
    private let pageSize = 50

    // MARK: - Dependencies

    private let repository: any MemoRepository

    // MARK: - Computed Properties

    var hasMorePages: Bool {
        memos.count < totalCount
    }

    var displayedCount: Int {
        memos.count
    }

    // MARK: - Init

    init(repository: any MemoRepository = GRDBRepository()) {
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

    /// Delete memo
    func deleteMemo(_ memo: MemoModel) async {
        do {
            try await repository.deleteMemo(id: memo.id)

            // Remove from local array
            memos.removeAll { $0.id == memo.id }
            totalCount -= 1
        } catch {
            self.error = error
        }
    }

    /// Search (debounced via Combine in view)
    func search(query: String) async {
        searchQuery = query
        await loadMemos()
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
