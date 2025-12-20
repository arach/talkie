//
//  SyncMetadata.swift
//  Talkie
//
//  Operational metadata for CloudKit sync management
//  Single-row table tracking current sync state
//

import Foundation
import GRDB
import CloudKit

// MARK: - Sync Metadata Model

struct SyncMetadata: Codable {
    var id: Int  // Always 1 (single row)
    var lastSyncTimestamp: Date?
    var nextScheduledSync: Date?
    var syncInProgress: Bool
    var changeToken: Data?  // Serialized CKServerChangeToken

    init(
        id: Int = 1,
        lastSyncTimestamp: Date? = nil,
        nextScheduledSync: Date? = nil,
        syncInProgress: Bool = false,
        changeToken: Data? = nil
    ) {
        self.id = id
        self.lastSyncTimestamp = lastSyncTimestamp
        self.nextScheduledSync = nextScheduledSync
        self.syncInProgress = syncInProgress
        self.changeToken = changeToken
    }
}

// MARK: - GRDB Persistence

extension SyncMetadata: FetchableRecord, PersistableRecord {
    static let databaseTableName = "sync_metadata"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let lastSyncTimestamp = Column(CodingKeys.lastSyncTimestamp)
        static let nextScheduledSync = Column(CodingKeys.nextScheduledSync)
        static let syncInProgress = Column(CodingKeys.syncInProgress)
        static let changeToken = Column(CodingKeys.changeToken)
    }
}

// MARK: - Helpers

extension SyncMetadata {
    /// Get the singleton metadata record
    static func get(_ db: Database) throws -> SyncMetadata {
        if let existing = try SyncMetadata.fetchOne(db, key: 1) {
            return existing
        }

        // Create initial record if missing
        var metadata = SyncMetadata()
        try metadata.insert(db)
        return metadata
    }

    /// Update the metadata record
    func update(_ db: Database) throws {
        var mutable = self
        try mutable.update(db)
    }

    /// Calculate time since last sync
    var timeSinceLastSync: TimeInterval? {
        guard let last = lastSyncTimestamp else { return nil }
        return Date().timeIntervalSince(last)
    }

    /// Check if enough time has passed to sync again
    func shouldSync(minimumInterval: TimeInterval = 300) -> Bool {
        // Don't sync if already in progress
        guard !syncInProgress else { return false }

        // If never synced, should sync
        guard let timeSince = timeSinceLastSync else { return true }

        // Check if enough time passed
        return timeSince >= minimumInterval
    }
}

// MARK: - Sendable Conformance

extension SyncMetadata: Sendable {}
