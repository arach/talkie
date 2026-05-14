//
//  RecordingsViewModel.swift
//  Talkie
//
//  ViewModel for unified Recordings view
//  Handles both memos and dictations from the unified recordings table
//

import Foundation
import SwiftUI
import TalkieKit
import GRDB

private let log = Log(.database)

// MARK: - Legacy Filter Type (for backwards compatibility)

enum RecordingsFilterType: String, CaseIterable, Identifiable {
    case all = "All"
    case memos = "Memos"
    case dictations = "Dictations"
    case notes = "Notes"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .memos: return "doc.text"
        case .dictations: return "waveform"
        case .notes: return "note.text"
        }
    }
}

// MARK: - Recordings ViewModel

@MainActor
@Observable
final class RecordingsViewModel {

    // MARK: - Singleton

    static let shared = RecordingsViewModel()

    // MARK: - Published State

    var recordings: [TalkieObject] = []
    var isLoading = false
    var error: Error?

    // Semantic filter state
    var filterState = RecordingFilterState()

    // Legacy type filter (for backwards compatibility during transition)
    var filterType: RecordingsFilterType = .all

    // Sort
    var sortField: RecordingSortField = .createdAt
    var sortAscending = false

    // Legacy (kept for backwards compatibility)
    var searchQuery = ""
    var activeFilters: Set<RecordingFilter> = []

    // Pagination
    var totalCount = 0
    private var currentLimit = 50
    private let pageSize = 50

    // MARK: - Dependencies

    private let repository: TalkieObjectRepository
    private let dbManager: DatabaseManager

    // MARK: - Observation

    private var observationCancellable: AnyDatabaseCancellable?

    // MARK: - Computed Properties

    var hasMorePages: Bool {
        recordings.count < totalCount
    }

    var displayedCount: Int {
        recordings.count
    }

    var memosCount: Int {
        recordings.filter { $0.type == .memo }.count
    }

    var dictationsCount: Int {
        recordings.filter { $0.type == .dictation }.count
    }

    // MARK: - Init

    init(repository: TalkieObjectRepository = TalkieObjectRepository(), dbManager: DatabaseManager = .shared) {
        self.repository = repository
        self.dbManager = dbManager
    }

    // MARK: - Actions

    /// Start observing recordings. Call once on app launch or when the view appears.
    func loadRecordings() async {
        await startObservation()
    }

    /// Load next page (expands the observation window)
    func loadNextPage() async {
        guard hasMorePages else { return }
        currentLimit += pageSize
        await startObservation()
    }

    /// Change type filter (legacy - now uses semantic filter)
    func setFilterType(_ type: RecordingsFilterType) async {
        filterType = type
        let semanticFilter: SemanticFilter = {
            switch type {
            case .all: return .all
            case .memos: return .memos
            case .dictations: return .dictations
            case .notes: return .notes
            }
        }()
        await toggleSemanticFilter(semanticFilter)
    }

    /// Refresh (re-subscribes the observation)
    func refresh() async {
        await startObservation()
    }

    /// Search
    func search(query: String) async {
        searchQuery = query
        filterState.searchQuery = query
        currentLimit = pageSize
        await startObservation()
    }

    /// Toggle a filter on/off (legacy)
    func toggleFilter(_ filter: RecordingFilter) async {
        if activeFilters.contains(filter) {
            activeFilters.remove(filter)
        } else {
            activeFilters.insert(filter)
        }
        currentLimit = pageSize
        await startObservation()
    }

    /// Check if a filter is active (legacy)
    func isFilterActive(_ filter: RecordingFilter) -> Bool {
        activeFilters.contains(filter)
    }

    /// Clear all filters (legacy)
    func clearFilters() async {
        activeFilters.removeAll()
        currentLimit = pageSize
        await startObservation()
    }

    // MARK: - Semantic Filter Actions

    /// Toggle a semantic filter
    func toggleSemanticFilter(_ filter: SemanticFilter) async {
        filterState.toggle(filter)
        currentLimit = pageSize
        await startObservation()
    }

    /// Check if semantic filter is active
    func isSemanticFilterActive(_ filter: SemanticFilter) -> Bool {
        filterState.isActive(filter)
    }

    /// Clear all semantic filters
    func clearSemanticFilters() async {
        filterState.clearAll()
        currentLimit = pageSize
        await startObservation()
    }

    /// Set a date filter and reload
    func setDateFilter(_ date: Date) async {
        filterState.setDateFilter(date)
        currentLimit = pageSize
        await startObservation()
    }

    /// Clear the date filter and reload
    func clearDateFilter() async {
        filterState.clearDateFilter()
        currentLimit = pageSize
        await startObservation()
    }

    // MARK: - GRDB ValueObservation

    /// Start (or restart) the database observation with current filters/sort.
    /// The observation automatically pushes new values whenever the recordings table changes.
    func startObservation() async {
        observationCancellable?.cancel()
        observationCancellable = nil

        isLoading = true
        error = nil

        let whereClause = filterState.toSQL()
        let orderBy = orderByClause()
        let limit = currentLimit

        log.debug("observation.start: \(filterState.description), sort=\(sortField), limit=\(limit)")
        #if DEBUG
        FrameRateMonitor.shared.beginRecordingsObservation(
            filter: filterState.description,
            sort: String(describing: sortField),
            limit: limit
        )
        #endif

        let dbQueue: DatabaseQueue
        do {
            dbQueue = try await dbManager.databaseWhenReady()
            #if DEBUG
            FrameRateMonitor.shared.markRecordingsObservation(stage: "db_ready")
            #endif
        } catch {
            self.error = error
            self.isLoading = false
            log.error("observation.start failed: \(error.localizedDescription)")
            #if DEBUG
            FrameRateMonitor.shared.failRecordingsObservation(error.localizedDescription)
            #endif
            return
        }

        let observation = ValueObservation.tracking { db -> (recordings: [TalkieObject], count: Int) in
            let countSQL = """
                SELECT COUNT(*) FROM recordings
                WHERE deletedAt IS NULL AND type != 'segment' AND (\(whereClause))
                """
            let fetchSQL = """
                SELECT * FROM recordings
                WHERE deletedAt IS NULL AND type != 'segment' AND (\(whereClause))
                ORDER BY \(orderBy)
                LIMIT \(limit)
                """
            let count = try Int.fetchOne(db, sql: countSQL) ?? 0
            let recordings = try TalkieObject.fetchAll(db, sql: fetchSQL)
            return (recordings, count)
        }
        #if DEBUG
        FrameRateMonitor.shared.markRecordingsObservation(stage: "tracking_created")
        #endif

        observationCancellable = observation.start(
            in: dbQueue,
            scheduling: .immediate,
            onError: { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.error = error
                    self.isLoading = false
                    log.error("observation.error: \(error.localizedDescription)")
                    #if DEBUG
                    FrameRateMonitor.shared.failRecordingsObservation(error.localizedDescription)
                    #endif
                }
            },
            onChange: { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.recordings = result.recordings
                    self.totalCount = result.count
                    self.isLoading = false
                    log.debug("observation.update: total=\(result.count), displayed=\(result.recordings.count)")
                    #if DEBUG
                    FrameRateMonitor.shared.finishRecordingsObservation(
                        displayed: result.recordings.count,
                        total: result.count
                    )
                    FrameRateMonitor.shared.markNavigationDataVisible(
                        section: NavigationState.shared.selectedSection?.perfName ?? "Library",
                        source: "RecordingsViewModel",
                        detail: "displayed=\(result.recordings.count) total=\(result.count)"
                    )
                    #endif
                }
            }
        )
        #if DEBUG
        FrameRateMonitor.shared.markRecordingsObservation(stage: "start_returned")
        #endif
    }

    /// Build ORDER BY clause from current sort settings
    private func orderByClause() -> String {
        switch sortField {
        case .createdAt:
            return sortAscending ? "createdAt ASC" : "createdAt DESC"
        case .title:
            return sortAscending ? "title COLLATE NOCASE ASC" : "title COLLATE NOCASE DESC"
        case .duration:
            return sortAscending ? "duration ASC" : "duration DESC"
        case .type:
            return sortAscending ? "type ASC, createdAt DESC" : "type DESC, createdAt DESC"
        }
    }

    // Legacy compatibility aliases
    func loadWithSemanticFilters() async { await startObservation() }
    func loadNextPageWithSemanticFilters() async { await loadNextPage() }

    // MARK: - Delete Operations

    /// Soft delete a recording (for memos)
    func softDeleteRecording(_ recording: TalkieObject) async {
        do {
            try await repository.softDeleteRecording(id: recording.id)
            // ValueObservation will automatically update the list
            log.info("Soft deleted recording: \(recording.id.uuidString.prefix(8))")
        } catch {
            self.error = error
            log.error("Failed to soft delete: \(error.localizedDescription)")
        }
    }

    /// Hard delete a recording (for dictations or permanent delete)
    func hardDeleteRecording(_ recording: TalkieObject) async {
        do {
            try await repository.hardDeleteRecording(id: recording.id)
            // ValueObservation will automatically update the list
            log.info("Hard deleted recording: \(recording.id.uuidString.prefix(8))")
        } catch {
            self.error = error
            log.error("Failed to hard delete: \(error.localizedDescription)")
        }
    }

    /// Delete recording (uses soft delete for memos/notes, hard delete for dictations)
    func deleteRecording(_ recording: TalkieObject) async {
        if recording.type == .memo || recording.type == .note {
            await softDeleteRecording(recording)
        } else {
            await hardDeleteRecording(recording)
        }
    }

    // MARK: - Promotion

    /// Promote a dictation to a memo
    func promoteToMemo(_ recording: TalkieObject) async {
        guard recording.type == .dictation else {
            log.warning("Cannot promote non-dictation: \(recording.id)")
            return
        }

        do {
            _ = try await repository.promoteToMemo(id: recording.id)
            // ValueObservation will automatically update the list
            log.info("Promoted recording to memo: \(recording.id.uuidString.prefix(8))")
        } catch {
            self.error = error
            log.error("Failed to promote: \(error.localizedDescription)")
        }
    }

    // MARK: - Helper

    /// Get a single recording by ID
    func getRecording(id: UUID) -> TalkieObject? {
        recordings.first { $0.id == id }
    }
}
