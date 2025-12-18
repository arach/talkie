//
//  CloudSyncActionModel.swift
//  Talkie
//
//  Tracks sync operations between Core Data and GRDB
//  Audit log for debugging sync issues and understanding sync flow
//

import Foundation
import GRDB

// MARK: - Cloud Sync Action Model

struct CloudSyncActionModel: Identifiable, Codable, Hashable {
    let id: UUID
    let entityId: UUID          // ID of memo or workflow being synced
    let entityType: String       // "memo" or "workflow_run"
    let direction: String        // "coredata_to_grdb" or "grdb_to_coredata"
    let action: String           // "create", "update", "skip"
    var conflictResolution: String?  // "timestamp_coredata_wins", "timestamp_grdb_wins", etc.
    let syncedAt: Date
    var details: String?         // Optional notes or JSON metadata

    init(
        id: UUID = UUID(),
        entityId: UUID,
        entityType: String,
        direction: String,
        action: String,
        conflictResolution: String? = nil,
        syncedAt: Date = Date(),
        details: String? = nil
    ) {
        self.id = id
        self.entityId = entityId
        self.entityType = entityType
        self.direction = direction
        self.action = action
        self.conflictResolution = conflictResolution
        self.syncedAt = syncedAt
        self.details = details
    }
}

// MARK: - GRDB Record

extension CloudSyncActionModel: FetchableRecord, PersistableRecord {
    static let databaseTableName = "cloud_sync_actions"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let entityId = Column(CodingKeys.entityId)
        static let entityType = Column(CodingKeys.entityType)
        static let direction = Column(CodingKeys.direction)
        static let action = Column(CodingKeys.action)
        static let conflictResolution = Column(CodingKeys.conflictResolution)
        static let syncedAt = Column(CodingKeys.syncedAt)
        static let details = Column(CodingKeys.details)
    }
}

// MARK: - Computed Properties

extension CloudSyncActionModel {
    var isCoreDataToGRDB: Bool {
        direction == "coredata_to_grdb"
    }

    var isGRDBToCoreData: Bool {
        direction == "grdb_to_coredata"
    }

    var wasCreated: Bool {
        action == "create"
    }

    var wasUpdated: Bool {
        action == "update"
    }

    var wasSkipped: Bool {
        action == "skip"
    }
}

// MARK: - Sendable Conformance

extension CloudSyncActionModel: Sendable {}
