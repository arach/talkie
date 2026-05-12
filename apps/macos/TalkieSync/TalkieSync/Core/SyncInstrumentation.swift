//
//  SyncInstrumentation.swift
//  TalkieSync
//
//  Performance instrumentation using os_signpost for Instruments profiling.
//  Single source of truth: os_signpost → Instruments
//

import Foundation
import OSLog

// MARK: - Signpost Configuration

/// TalkieSync performance signposting subsystem
let syncPerformanceLog = OSLog(subsystem: "to.talkie.app.sync", category: .pointsOfInterest)

/// Signposter for sync performance tracking (for Instruments)
let syncSignposter = OSSignposter(subsystem: "to.talkie.app.sync", category: "Sync")

/// Signposter for database operations
let dbSignposter = OSSignposter(subsystem: "to.talkie.app.sync", category: "Database")

// MARK: - Sync Interval Tracking

/// Track a complete sync operation
struct SyncInterval {
    let id: OSSignpostID
    let state: OSSignpostIntervalState

    static func begin(_ name: StaticString = "DirectSync") -> SyncInterval {
        let id = syncSignposter.makeSignpostID()
        let state = syncSignposter.beginInterval(name, id: id)
        return SyncInterval(id: id, state: state)
    }

    func end(recordCount: Int) {
        syncSignposter.endInterval("DirectSync", state, "\(recordCount) records")
    }

    func end(error: String) {
        syncSignposter.endInterval("DirectSync", state, "Error: \(error)")
    }
}

/// Track a Core Data fetch operation
struct CoreDataFetchInterval {
    let id: OSSignpostID
    let state: OSSignpostIntervalState

    static func begin(_ entityName: StaticString = "VoiceMemo") -> CoreDataFetchInterval {
        let id = dbSignposter.makeSignpostID()
        let state = dbSignposter.beginInterval("CoreDataFetch", id: id)
        return CoreDataFetchInterval(id: id, state: state)
    }

    func end(count: Int) {
        dbSignposter.endInterval("CoreDataFetch", state, "\(count) fetched")
    }
}

/// Track a GRDB write operation
struct GRDBWriteInterval {
    let id: OSSignpostID
    let state: OSSignpostIntervalState

    static func begin(_ operation: StaticString = "Write") -> GRDBWriteInterval {
        let id = dbSignposter.makeSignpostID()
        let state = dbSignposter.beginInterval("GRDBWrite", id: id)
        return GRDBWriteInterval(id: id, state: state)
    }

    func end(inserted: Int, updated: Int) {
        dbSignposter.endInterval("GRDBWrite", state, "inserted: \(inserted), updated: \(updated)")
    }
}

// MARK: - Point Events

/// Emit a sync event (point in time)
func emitSyncEvent(_ name: StaticString, message: String = "") {
    let id = syncSignposter.makeSignpostID()
    syncSignposter.emitEvent(name, id: id, "\(message)")
}

// MARK: - Instrumented Operations

/// Instrument a sync operation with timing
func instrumentSync<T>(
    _ name: String,
    _ work: () async throws -> T
) async rethrows -> T {
    let interval = SyncInterval.begin()

    do {
        let result = try await work()
        if let count = result as? Int {
            interval.end(recordCount: count)
        } else {
            interval.end(recordCount: 0)
        }
        return result
    } catch {
        interval.end(error: error.localizedDescription)
        throw error
    }
}

/// Instrument a Core Data fetch
func instrumentCoreDataFetch<T>(
    _ work: () throws -> T
) rethrows -> T {
    let interval = CoreDataFetchInterval.begin()
    let result = try work()

    if let array = result as? [Any] {
        interval.end(count: array.count)
    } else {
        interval.end(count: 1)
    }

    return result
}

/// Instrument a GRDB write operation
func instrumentGRDBWrite<T>(
    inserted: Int = 0,
    updated: Int = 0,
    _ work: () throws -> T
) rethrows -> T {
    let interval = GRDBWriteInterval.begin()
    let result = try work()
    interval.end(inserted: inserted, updated: updated)
    return result
}
