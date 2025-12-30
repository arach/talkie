//
//  RepositoryInstrumentation.swift
//  Talkie
//
//  Automatic performance instrumentation for database repositories
//  Convention-based signposting for all database operations
//

import Foundation
import OSLog

// MARK: - Repository Signposting

/// Signposter specifically for database repository operations
let repositorySignposter = OSSignposter(subsystem: "live.talkie.performance", category: "Database")

/// Instrument a repository read operation
///
/// Automatically creates signposts with convention-based naming.
/// Pattern: `RepositoryName.methodName`
///
/// Usage (in LocalRepository):
/// ```swift
/// func fetchMemos(...) async throws -> [MemoModel] {
///     try await instrumentRepositoryRead("fetchMemos") {
///         // Your query logic
///     }
/// }
/// ```
func instrumentRepositoryRead<T>(
    _ operation: String,
    repository: String = "LocalRepository",
    _ work: () async throws -> T
) async rethrows -> T {
    let id = repositorySignposter.makeSignpostID()
    let state = repositorySignposter.beginInterval("DatabaseRead", id: id)

    let startTime = Date()
    let result = try await work()
    let duration = Date().timeIntervalSince(startTime)

    repositorySignposter.endInterval("DatabaseRead", state, "\(repository).\(operation)")

    // Report to Performance Monitor for in-app breakdown
    await PerformanceMonitor.shared.addEvent(
        category: "Database",
        name: operation,
        message: repository,
        duration: duration
    )

    return result
}

/// Instrument a repository write operation
///
/// Automatically creates signposts for insert/update/delete operations.
///
/// Usage (in LocalRepository):
/// ```swift
/// func saveMemo(_ memo: MemoModel) async throws {
///     try await instrumentRepositoryWrite("saveMemo") {
///         // Your write logic
///     }
/// }
/// ```
func instrumentRepositoryWrite<T>(
    _ operation: String,
    repository: String = "LocalRepository",
    _ work: () async throws -> T
) async rethrows -> T {
    let id = repositorySignposter.makeSignpostID()
    let state = repositorySignposter.beginInterval("DatabaseWrite", id: id)

    let startTime = Date()
    let result = try await work()
    let duration = Date().timeIntervalSince(startTime)

    repositorySignposter.endInterval("DatabaseWrite", state, "\(repository).\(operation)")

    // Report to Performance Monitor for in-app breakdown
    await PerformanceMonitor.shared.addEvent(
        category: "Database",
        name: operation,
        message: repository,
        duration: duration
    )

    return result
}

/// Instrument a database transaction
///
/// Use this for multi-step operations that should be tracked as a single unit.
///
/// Usage:
/// ```swift
/// try await instrumentRepositoryTransaction("importMemos") {
///     for memo in memos {
///         try await saveMemo(memo)
///     }
/// }
/// ```
func instrumentRepositoryTransaction<T>(
    _ name: String,
    repository: String = "LocalRepository",
    _ work: () async throws -> T
) async rethrows -> T {
    let id = repositorySignposter.makeSignpostID()
    let state = repositorySignposter.beginInterval("DatabaseTransaction", id: id)

    let result = try await work()

    repositorySignposter.endInterval("DatabaseTransaction", state, "\(repository).\(name)")

    return result
}

// MARK: - Development Helpers

/// Mark transaction completion point
///
/// Use this to signal when a logical transaction is complete,
/// even if it spans multiple repository calls.
///
/// Usage:
/// ```swift
/// try await saveMemo(memo)
/// try await saveWorkflowRun(run)
/// markTransactionComplete("saveMemoWithWorkflow")
/// ```
func markTransactionComplete(_ name: String, repository: String = "LocalRepository") {
    let id = repositorySignposter.makeSignpostID()

    repositorySignposter.emitEvent("TransactionCheckpoint", id: id, "\(repository).\(name)")
}

// MARK: - Usage Example

/*
 EXAMPLE: How to instrument LocalRepository

 actor LocalRepository: MemoRepository {
     // READ operations - automatic signposting
     func fetchMemos(...) async throws -> [MemoModel] {
         try await instrumentRepositoryRead("fetchMemos") {
             let db = try await dbManager.database()
             return try await db.read { db in
                 // Your query logic
             }
         }
     }

     // WRITE operations - automatic signposting
     func saveMemo(_ memo: MemoModel) async throws {
         try await instrumentRepositoryWrite("saveMemo") {
             let db = try await dbManager.database()
             try await db.write { db in
                 try memo.save(db)
             }
         }
     }

     // TRANSACTIONS - group multiple operations
     func saveMemoWithWorkflow(memo: MemoModel, workflow: WorkflowRunModel) async throws {
         try await instrumentRepositoryTransaction("saveMemoWithWorkflow") {
             try await saveMemo(memo)
             try await saveWorkflowRun(workflow)
         }
     }

     // COUNT operations - also a read
     func countMemos(...) async throws -> Int {
         try await instrumentRepositoryRead("countMemos") {
             let db = try await dbManager.database()
             return try await db.read { db in
                 try MemoModel.fetchCount(db)
             }
         }
     }
 }

 SIGNPOSTS EMITTED (automatically):
 - LocalRepository.fetchMemos (interval with duration)
 - LocalRepository.saveMemo (interval with duration)
 - LocalRepository.saveMemoWithWorkflow (transaction interval)
 - LocalRepository.countMemos (interval with duration)

 IN INSTRUMENTS:
 You'll see a timeline with:
 - "DB Read Complete" events for queries
 - "DB Write Complete" events for updates
 - "DB Transaction Complete" events for multi-step operations
 - All named: LocalRepository.methodName
 */
