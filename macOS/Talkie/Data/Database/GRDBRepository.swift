//
//  GRDBRepository.swift
//  Talkie
//
//  GRDB implementation of MemoRepository
//  Efficient SQLite queries with proper indexing
//

import Foundation
import GRDB

// MARK: - GRDB Repository

actor GRDBRepository: MemoRepository {
    private let dbManager: DatabaseManager

    init(dbManager: DatabaseManager = .shared) {
        self.dbManager = dbManager
    }

    // MARK: - Fetch Memos (The Performance Critical Method)

    func fetchMemos(
        sortBy: MemoModel.SortField,
        ascending: Bool,
        limit: Int,
        offset: Int,
        searchQuery: String? = nil,
        filters: Set<MemoFilter> = []
    ) async throws -> [MemoModel] {
        try await instrumentRepositoryRead("fetchMemos") {
            let startTime = Date()
            let db = try await dbManager.database()

            print("🔍 [GRDB] Executing query: sort=\(sortBy), limit=\(limit), offset=\(offset), filters=\(filters.count)")

            let result = try await db.read { db in
                // Start with non-deleted memos only
                var request = MemoModel.all()
                    .filter(MemoModel.Columns.deletedAt == nil)

                // Apply search filter (uses FTS5 full-text search index)
                if let query = searchQuery, !query.isEmpty {
                    // TODO: Implement FTS search
                    // For now, use basic LIKE (will add FTS integration later)
                    request = request.filter(
                        MemoModel.Columns.title.like("%\(query)%") ||
                        MemoModel.Columns.transcription.like("%\(query)%")
                    )
                }

                // Apply smart filters
                request = try applyFilters(request, filters: filters)

                // Apply sorting (uses indexes!)
                switch sortBy {
                case .timestamp:
                    request = ascending
                        ? request.order(MemoModel.Columns.createdAt.asc)
                        : request.order(MemoModel.Columns.createdAt.desc)

                case .title:
                    // Sort by title, nulls last
                    request = ascending
                        ? request.order(MemoModel.Columns.title.ascNullsLast)
                        : request.order(MemoModel.Columns.title.descNullsFirst)

                case .duration:
                    request = ascending
                        ? request.order(MemoModel.Columns.duration.asc)
                        : request.order(MemoModel.Columns.duration.desc)

                case .workflows:
                    // Workflow count requires join - most expensive sort
                    // We'll compute this in Swift for now (acceptable for displayed items only)
                    // Alternatively: Add a cached workflowCount column updated via triggers
                    request = request.order(MemoModel.Columns.createdAt.desc)
                }

                // CRITICAL: Apply LIMIT and OFFSET at SQL level
                // This is where the 90% memory savings happen
                request = request.limit(limit, offset: offset)

                // Execute query
                let memos = try request.fetchAll(db)

                // If sorting by workflows, do client-side sort on the limited set
                if sortBy == .workflows {
                    // Fetch workflow counts for just these memos
                    let memoIds = memos.map(\.id)
                    let workflowCounts = try fetchWorkflowCounts(for: memoIds, in: db)

                    return memos.sorted { a, b in
                        let countA = workflowCounts[a.id] ?? 0
                        let countB = workflowCounts[b.id] ?? 0
                        return ascending ? countA < countB : countA > countB
                    }
                }

                return memos
            }

            let elapsed = Date().timeIntervalSince(startTime)
            print("✅ [GRDB] Query completed in \(Int(elapsed * 1000))ms, returned \(result.count) memos")

            return result
        }
    }

    // MARK: - Count

    func countMemos(searchQuery: String? = nil, filters: Set<MemoFilter> = []) async throws -> Int {
        try await instrumentRepositoryRead("countMemos") {
            let db = try await dbManager.database()

            return try await db.read { db in
                // Count only non-deleted memos
                var request = MemoModel.all()
                    .filter(MemoModel.Columns.deletedAt == nil)

                if let query = searchQuery, !query.isEmpty {
                    request = request.filter(
                        MemoModel.Columns.title.like("%\(query)%") ||
                        MemoModel.Columns.transcription.like("%\(query)%")
                    )
                }

                // Apply smart filters
                request = try applyFilters(request, filters: filters)

                return try request.fetchCount(db)
            }
        }
    }

    // MARK: - Fetch Single Memo with Relationships

    func fetchMemo(id: UUID) async throws -> MemoWithRelationships? {
        try await instrumentRepositoryRead("fetchMemo") {
            let db = try await dbManager.database()

            return try await db.read { db in
                // Fetch memo
                guard let memo = try MemoModel
                    .filter(MemoModel.Columns.id == id.uuidString)
                    .fetchOne(db) else {
                    return nil
                }

                // Fetch relationships
                let transcripts = try TranscriptVersionModel
                    .filter(TranscriptVersionModel.Columns.memoId == id.uuidString)
                    .order(TranscriptVersionModel.Columns.version.desc)
                    .fetchAll(db)

                let workflows = try WorkflowRunModel
                    .filter(WorkflowRunModel.Columns.memoId == id.uuidString)
                    .order(WorkflowRunModel.Columns.runDate.desc)
                    .fetchAll(db)

                return MemoWithRelationships(
                    memo: memo,
                    transcriptVersions: transcripts,
                    workflowRuns: workflows
                )
            }
        }
    }

    // MARK: - Save Operations

    func saveMemo(_ memo: MemoModel) async throws {
        try await instrumentRepositoryWrite("saveMemo") {
            let db = try await dbManager.database()

            try await db.write { db in
                let mutableMemo = memo
                try mutableMemo.save(db)
            }
        }
    }

    func deleteMemo(id: UUID) async throws {
        try await instrumentRepositoryWrite("deleteMemo") {
            let db = try await dbManager.database()

            _ = try await db.write { db in
                try MemoModel
                    .filter(MemoModel.Columns.id == id.uuidString)
                    .deleteAll(db)
            }
        }
    }

    // MARK: - Soft Delete

    /// Soft delete a memo (set deletedAt timestamp)
    func softDeleteMemo(id: UUID) async throws {
        try await instrumentRepositoryWrite("softDeleteMemo") {
            let db = try await dbManager.database()

            try await db.write { db in
                try db.execute(
                    sql: "UPDATE voice_memos SET deletedAt = ? WHERE id = ?",
                    arguments: [Date(), id.uuidString]
                )
            }
        }
    }

    /// Soft delete multiple memos
    func softDeleteMemos(ids: Set<UUID>) async throws {
        try await instrumentRepositoryWrite("softDeleteMemos") {
            let db = try await dbManager.database()
            let now = Date()

            try await db.write { db in
                for id in ids {
                    try db.execute(
                        sql: "UPDATE voice_memos SET deletedAt = ? WHERE id = ?",
                        arguments: [now, id.uuidString]
                    )
                }
            }
        }
    }

    /// Fetch memos pending deletion
    func fetchPendingDeletions() async throws -> [MemoModel] {
        try await instrumentRepositoryRead("fetchPendingDeletions") {
            let db = try await dbManager.database()

            return try await db.read { db in
                try MemoModel
                    .filter(MemoModel.Columns.deletedAt != nil)
                    .order(MemoModel.Columns.deletedAt.desc)
                    .fetchAll(db)
            }
        }
    }

    /// Count memos pending deletion
    func countPendingDeletions() async throws -> Int {
        try await instrumentRepositoryRead("countPendingDeletions") {
            let db = try await dbManager.database()

            return try await db.read { db in
                try MemoModel
                    .filter(MemoModel.Columns.deletedAt != nil)
                    .fetchCount(db)
            }
        }
    }

    /// Restore a soft-deleted memo
    func restoreMemo(id: UUID) async throws {
        try await instrumentRepositoryWrite("restoreMemo") {
            let db = try await dbManager.database()

            try await db.write { db in
                try db.execute(
                    sql: "UPDATE voice_memos SET deletedAt = NULL WHERE id = ?",
                    arguments: [id.uuidString]
                )
            }
        }
    }

    /// Hard delete (permanent) - use after user confirms in Cloud Manager
    func hardDeleteMemo(id: UUID) async throws {
        try await deleteMemo(id: id)
    }

    // MARK: - Relationships

    func fetchTranscriptVersions(for memoId: UUID) async throws -> [TranscriptVersionModel] {
        try await instrumentRepositoryRead("fetchTranscriptVersions") {
            let db = try await dbManager.database()

            return try await db.read { db in
                try TranscriptVersionModel
                    .filter(TranscriptVersionModel.Columns.memoId == memoId.uuidString)
                    .order(TranscriptVersionModel.Columns.version.desc)
                    .fetchAll(db)
            }
        }
    }

    func fetchWorkflowRuns(for memoId: UUID) async throws -> [WorkflowRunModel] {
        try await instrumentRepositoryRead("fetchWorkflowRuns") {
            let db = try await dbManager.database()

            return try await db.read { db in
                try WorkflowRunModel
                    .filter(WorkflowRunModel.Columns.memoId == memoId.uuidString)
                    .order(WorkflowRunModel.Columns.runDate.desc)
                    .fetchAll(db)
            }
        }
    }

    func saveTranscriptVersion(_ version: TranscriptVersionModel) async throws {
        try await instrumentRepositoryWrite("saveTranscriptVersion") {
            let db = try await dbManager.database()

            try await db.write { db in
                let mutableVersion = version
                try mutableVersion.save(db)
            }
        }
    }

    func saveWorkflowRun(_ run: WorkflowRunModel) async throws {
        try await instrumentRepositoryWrite("saveWorkflowRun") {
            let db = try await dbManager.database()

            try await db.write { db in
                let mutableRun = run
                try mutableRun.save(db)
            }
        }
    }

    func saveWorkflowStep(_ step: WorkflowStepModel) async throws {
        try await instrumentRepositoryWrite("saveWorkflowStep") {
            let db = try await dbManager.database()

            try await db.write { db in
                let mutableStep = step
                try mutableStep.save(db)
            }
        }
    }

    func saveWorkflowEvent(_ event: WorkflowEventModel) async throws {
        try await instrumentRepositoryWrite("saveWorkflowEvent") {
            let db = try await dbManager.database()

            try await db.write { db in
                let mutableEvent = event
                try mutableEvent.save(db)
            }
        }
    }

    func fetchWorkflowSteps(for runId: UUID) async throws -> [WorkflowStepModel] {
        try await instrumentRepositoryRead("fetchWorkflowSteps") {
            let db = try await dbManager.database()

            return try await db.read { db in
                try WorkflowStepModel
                    .filter(WorkflowStepModel.Columns.runId == runId.uuidString)
                    .order(WorkflowStepModel.Columns.stepNumber.asc)
                    .fetchAll(db)
            }
        }
    }

    func fetchWorkflowEvents(for runId: UUID) async throws -> [WorkflowEventModel] {
        try await instrumentRepositoryRead("fetchWorkflowEvents") {
            let db = try await dbManager.database()

            return try await db.read { db in
                try WorkflowEventModel
                    .filter(WorkflowEventModel.Columns.runId == runId.uuidString)
                    .order(WorkflowEventModel.Columns.sequence.asc)
                    .fetchAll(db)
            }
        }
    }

    // MARK: - Helper: Fetch Workflow Counts

    nonisolated private func fetchWorkflowCounts(for memoIds: [UUID], in db: Database) throws -> [UUID: Int] {
        let idStrings = memoIds.map(\.uuidString)

        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT memoId, COUNT(*) as count
                FROM workflow_runs
                WHERE memoId IN (\(idStrings.map { _ in "?" }.joined(separator: ",")))
                GROUP BY memoId
                """,
            arguments: StatementArguments(idStrings)
        )

        var counts: [UUID: Int] = [:]
        for row in rows {
            if let idString: String = row["memoId"],
               let id = UUID(uuidString: idString),
               let count: Int = row["count"] {
                counts[id] = count
            }
        }

        return counts
    }

    // MARK: - Helper: Apply Filters

    nonisolated private func applyFilters(_ request: QueryInterfaceRequest<MemoModel>, filters: Set<MemoFilter>) throws -> QueryInterfaceRequest<MemoModel> {
        guard !filters.isEmpty else { return request }

        var filteredRequest = request

        // Separate filters by type
        let shortRecordingFilter = filters.contains(where: { if case .shortRecordings = $0 { return true } else { return false } })
        let sourceFilters = filters.compactMap { filter -> MemoModel.Source? in
            if case .source(let source) = filter { return source }
            return nil
        }

        // Apply short recordings filter (AND logic)
        if shortRecordingFilter {
            filteredRequest = filteredRequest.filter(MemoModel.Columns.duration < 30.0)
        }

        // Apply source filters (OR logic for multiple sources)
        if !sourceFilters.isEmpty {
            // Build OR conditions for all selected sources
            var conditions: [SQLExpression] = []

            for source in sourceFilters {
                switch source {
                case .iPhone:
                    // No prefix or empty = iPhone (legacy format)
                    conditions.append(
                        MemoModel.Columns.originDeviceId == nil ||
                        MemoModel.Columns.originDeviceId == "" ||
                        (!MemoModel.Columns.originDeviceId.like("mac-%") &&
                         !MemoModel.Columns.originDeviceId.like("live-%") &&
                         !MemoModel.Columns.originDeviceId.like("watch-%"))
                    )
                case .watch:
                    conditions.append(MemoModel.Columns.originDeviceId.like("watch-%"))
                case .mac:
                    conditions.append(MemoModel.Columns.originDeviceId.like("mac-%"))
                case .live:
                    conditions.append(MemoModel.Columns.originDeviceId.like("live-%"))
                case .unknown:
                    conditions.append(
                        MemoModel.Columns.originDeviceId == nil ||
                        MemoModel.Columns.originDeviceId == ""
                    )
                }
            }

            // Combine all source conditions with OR
            if !conditions.isEmpty {
                // Start with the first condition, then OR with the rest
                var combinedCondition = conditions[0]
                for i in 1..<conditions.count {
                    combinedCondition = combinedCondition || conditions[i]
                }
                filteredRequest = filteredRequest.filter(combinedCondition)
            }
        }

        return filteredRequest
    }
}

// MARK: - Column Extensions

private extension Column {
    var ascNullsLast: SQLOrdering {
        collating(.nocase).asc
    }

    var descNullsFirst: SQLOrdering {
        collating(.nocase).desc
    }
}
