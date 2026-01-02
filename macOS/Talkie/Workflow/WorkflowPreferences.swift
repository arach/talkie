//
//  WorkflowPreferences.swift
//  Talkie macOS
//
//  GRDB model for workflow preferences (pins, order, enabled state)
//  The workflow definitions are stored as JSON files; this table stores
//  user preferences that shouldn't be in the JSON files.
//

import Foundation
import GRDB

// MARK: - Workflow Preferences Model

struct WorkflowPreference: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "workflow_preferences"

    var workflowId: String  // UUID as string
    var isEnabled: Bool
    var isPinned: Bool
    var autoRun: Bool
    var autoRunOrder: Int
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    /// Create with defaults
    static func defaults(for workflowId: UUID) -> WorkflowPreference {
        WorkflowPreference(
            workflowId: workflowId.uuidString,
            isEnabled: true,
            isPinned: false,
            autoRun: false,
            autoRunOrder: 0,
            sortOrder: 0,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// MARK: - Workflow Preferences Repository

/// Repository for workflow preference CRUD operations
struct WorkflowPreferencesRepository {
    private let dbManager = DatabaseManager.shared

    // MARK: - Read

    /// Fetch preferences for a workflow
    func fetch(for workflowId: UUID) throws -> WorkflowPreference? {
        let db = try dbManager.database()
        return try db.read { db in
            try WorkflowPreference.fetchOne(db, key: workflowId.uuidString)
        }
    }

    /// Fetch preferences for multiple workflows
    func fetch(for workflowIds: [UUID]) throws -> [UUID: WorkflowPreference] {
        let db = try dbManager.database()
        let ids = workflowIds.map { $0.uuidString }

        return try db.read { db in
            let prefs = try WorkflowPreference
                .filter(ids.contains(Column("workflowId")))
                .fetchAll(db)

            return Dictionary(uniqueKeysWithValues: prefs.compactMap { pref in
                guard let uuid = UUID(uuidString: pref.workflowId) else { return nil }
                return (uuid, pref)
            })
        }
    }

    /// Fetch all preferences
    func fetchAll() throws -> [WorkflowPreference] {
        let db = try dbManager.database()
        return try db.read { db in
            try WorkflowPreference.fetchAll(db)
        }
    }

    /// Fetch all pinned workflow IDs
    func fetchPinnedIDs() throws -> [UUID] {
        let db = try dbManager.database()
        return try db.read { db in
            let prefs = try WorkflowPreference
                .filter(Column("isPinned") == true)
                .fetchAll(db)
            return prefs.compactMap { UUID(uuidString: $0.workflowId) }
        }
    }

    /// Fetch auto-run workflows in order
    func fetchAutoRunIDs() throws -> [UUID] {
        let db = try dbManager.database()
        return try db.read { db in
            let prefs = try WorkflowPreference
                .filter(Column("autoRun") == true)
                .order(Column("autoRunOrder"))
                .fetchAll(db)
            return prefs.compactMap { UUID(uuidString: $0.workflowId) }
        }
    }

    // MARK: - Write

    /// Save preferences (insert or update)
    func save(_ pref: WorkflowPreference) throws {
        let db = try dbManager.database()
        var updated = pref
        updated.updatedAt = Date()

        try db.write { db in
            try updated.save(db)
        }
    }

    /// Get or create preferences for a workflow
    func getOrCreate(for workflowId: UUID) throws -> WorkflowPreference {
        if let existing = try fetch(for: workflowId) {
            return existing
        }

        let new = WorkflowPreference.defaults(for: workflowId)
        try save(new)
        return new
    }

    /// Update a single field
    func update(workflowId: UUID, isEnabled: Bool? = nil, isPinned: Bool? = nil, autoRun: Bool? = nil, autoRunOrder: Int? = nil, sortOrder: Int? = nil) throws {
        var pref = try getOrCreate(for: workflowId)

        if let isEnabled = isEnabled { pref.isEnabled = isEnabled }
        if let isPinned = isPinned { pref.isPinned = isPinned }
        if let autoRun = autoRun { pref.autoRun = autoRun }
        if let autoRunOrder = autoRunOrder { pref.autoRunOrder = autoRunOrder }
        if let sortOrder = sortOrder { pref.sortOrder = sortOrder }

        try save(pref)
    }

    /// Delete preferences for a workflow
    func delete(for workflowId: UUID) throws {
        let db = try dbManager.database()
        try db.write { db in
            try WorkflowPreference.deleteOne(db, key: workflowId.uuidString)
        }
    }

    // MARK: - Batch Operations

    /// Ensure preferences exist for all given workflows (creates defaults for missing)
    func ensureExists(for workflowIds: [UUID]) throws {
        let existing = try fetch(for: workflowIds)
        let missing = workflowIds.filter { existing[$0] == nil }

        let db = try dbManager.database()
        try db.write { db in
            for id in missing {
                try WorkflowPreference.defaults(for: id).insert(db)
            }
        }
    }

    /// Migrate from WorkflowDefinition (one-time migration)
    func migrateFromDefinition(_ workflow: WorkflowDefinition) throws {
        // Only migrate if preferences don't already exist
        if try fetch(for: workflow.id) != nil { return }

        let pref = WorkflowPreference(
            workflowId: workflow.id.uuidString,
            isEnabled: workflow.isEnabled,
            isPinned: workflow.isPinned,
            autoRun: workflow.autoRun,
            autoRunOrder: workflow.autoRunOrder,
            sortOrder: 0,
            createdAt: Date(),
            updatedAt: Date()
        )
        try save(pref)
    }
}
