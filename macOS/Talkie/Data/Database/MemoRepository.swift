//
//  MemoRepository.swift
//  Talkie
//
//  Repository protocol for accessing voice memos
//  Abstraction layer for storage (currently GRDB, can swap later)
//

import Foundation

// MARK: - Sort Options



// MARK: - Repository Protocol

protocol MemoRepository: Actor {
    /// Fetch memos with pagination and sorting
    /// This is where the SQLite magic happens - LIMIT/OFFSET at query level
    func fetchMemos(
        sortBy: MemoModel.SortField,
        ascending: Bool,
        limit: Int,
        offset: Int,
        searchQuery: String?,
        filters: Set<MemoFilter>
    ) async throws -> [MemoModel]

    /// Count total memos (for pagination UI)
    func countMemos(searchQuery: String?, filters: Set<MemoFilter>) async throws -> Int

    /// Fetch single memo by ID with relationships
    func fetchMemo(id: UUID) async throws -> MemoWithRelationships?

    /// Save or update memo
    func saveMemo(_ memo: MemoModel) async throws

    /// Delete memo
    func deleteMemo(id: UUID) async throws

    /// Fetch transcript versions for a memo
    func fetchTranscriptVersions(for memoId: UUID) async throws -> [TranscriptVersionModel]

    /// Fetch workflow runs for a memo
    func fetchWorkflowRuns(for memoId: UUID) async throws -> [WorkflowRunModel]

    /// Save transcript version
    func saveTranscriptVersion(_ version: TranscriptVersionModel) async throws

    /// Save workflow run
    func saveWorkflowRun(_ run: WorkflowRunModel) async throws
}

// MARK: - Memo with Relationships

struct MemoWithRelationships {
    let memo: MemoModel
    let transcriptVersions: [TranscriptVersionModel]
    let workflowRuns: [WorkflowRunModel]

    /// Computed: workflow count (cached for performance)
    var workflowCount: Int {
        workflowRuns.count
    }

    /// Latest transcript version
    var latestTranscript: TranscriptVersionModel? {
        transcriptVersions.sorted { $0.version > $1.version }.first
    }
}
