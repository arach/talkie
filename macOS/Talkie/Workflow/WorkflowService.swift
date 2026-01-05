//
//  WorkflowService.swift
//  Talkie macOS
//
//  Single entry point for workflow operations.
//  Combines WorkflowFileRepository (JSON files) + WorkflowPreferencesRepository (GRDB).
//  Replaces WorkflowManager.
//

import Foundation
import Observation
import TalkieKit

private let log = Log(.workflow)

// MARK: - Unified Workflow

/// A workflow with its preferences merged (what the UI sees)
struct Workflow: Identifiable, Hashable {
    let id: UUID
    let definition: WorkflowDefinition
    let source: WorkflowSource
    let filePath: URL

    // Preferences (from GRDB)
    var isEnabled: Bool
    var isPinned: Bool
    var autoRun: Bool
    var autoRunOrder: Int
    var sortOrder: Int

    var slug: String { filePath.deletingPathExtension().lastPathComponent }

    // Convenience accessors
    var name: String { definition.name }
    var description: String { definition.description }
    var icon: String { definition.icon }
    var color: WorkflowColor { definition.color }
    var maintainer: String? { definition.maintainer }
    var steps: [WorkflowStep] { definition.steps }
    var createdAt: Date { definition.createdAt }
    var modifiedAt: Date { definition.modifiedAt }

    var isEditable: Bool { source.isEditable }
    var isSystem: Bool { source == .system }
    var isTalkieMaintained: Bool { definition.isTalkieMaintained }
    var hasMaintainer: Bool { definition.hasMaintainer }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Workflow, rhs: Workflow) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Workflow Service

@MainActor
@Observable
final class WorkflowService {
    static let shared = WorkflowService()

    // MARK: - State

    /// All workflows (merged definition + preferences)
    private(set) var workflows: [Workflow] = []

    /// Quick access by ID
    private var workflowsByID: [UUID: Workflow] = [:]

    // MARK: - Dependencies

    private let fileRepo = WorkflowFileRepository.shared
    private let prefsRepo = WorkflowPreferencesRepository()

    // MARK: - Initialization

    private init() {}

    /// Initialize the service (call on app launch)
    func initialize() async {
        log.info("Initializing WorkflowService")

        // Initialize file repository (creates directories, syncs bundled files, loads)
        await fileRepo.initialize()

        // Migrate from old WorkflowManager if needed
        await migrateFromLegacy()

        // Merge file data with preferences
        await reload()

        log.info("WorkflowService ready with \(workflows.count) workflows")
    }

    // MARK: - Reload

    /// Reload all workflows (merges file data with preferences)
    func reload() async {
        // Get all loaded workflows from files
        let loaded = fileRepo.loadedWorkflows

        // Ensure preferences exist for all workflows
        let ids = loaded.map { $0.id }
        try? prefsRepo.ensureExists(for: ids)

        // Fetch all preferences
        let allPrefs = (try? prefsRepo.fetch(for: ids)) ?? [:]

        // Merge into unified Workflow objects
        workflows = loaded.map { loaded in
            let prefs = allPrefs[loaded.id] ?? WorkflowPreference.defaults(for: loaded.id)
            return Workflow(
                id: loaded.id,
                definition: loaded.definition,
                source: loaded.source,
                filePath: loaded.filePath,
                isEnabled: prefs.isEnabled,
                isPinned: prefs.isPinned,
                autoRun: prefs.autoRun,
                autoRunOrder: prefs.autoRunOrder,
                sortOrder: prefs.sortOrder
            )
        }

        // Sort: pinned first, then by sortOrder, then by name
        workflows.sort { a, b in
            if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
            if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        workflowsByID = Dictionary(uniqueKeysWithValues: workflows.map { ($0.id, $0) })
    }

    // MARK: - Read

    /// Get a workflow by ID
    func workflow(byID id: UUID) -> Workflow? {
        workflowsByID[id]
    }

    /// Get all workflows for a specific source
    func workflows(for source: WorkflowSource) -> [Workflow] {
        workflows.filter { $0.source == source }
    }

    /// Get all pinned workflows
    var pinnedWorkflows: [Workflow] {
        workflows.filter { $0.isPinned }
    }

    /// Get all auto-run workflows in order
    var autoRunWorkflows: [Workflow] {
        workflows
            .filter { $0.autoRun && $0.isEnabled }
            .sorted { $0.autoRunOrder < $1.autoRunOrder }
    }

    /// Get all enabled workflows
    var enabledWorkflows: [Workflow] {
        workflows.filter { $0.isEnabled }
    }

    // MARK: - Create/Update/Delete

    /// Save a workflow definition (creates or updates in user/ directory)
    func save(_ definition: WorkflowDefinition, slug: String? = nil) async throws {
        try await fileRepo.save(definition, slug: slug)
        await reload()
    }

    /// Delete a workflow (only works for user/ workflows)
    func delete(_ workflow: Workflow) async throws {
        guard let loaded = fileRepo.workflow(byID: workflow.id) else {
            throw WorkflowFileError.workflowNotFound(workflow.id)
        }
        try await fileRepo.delete(loaded)
        try? prefsRepo.delete(for: workflow.id)
        await reload()
    }

    /// Duplicate a workflow to user/ directory
    func duplicate(_ workflow: Workflow, newName: String? = nil) async throws -> Workflow {
        guard let loaded = fileRepo.workflow(byID: workflow.id) else {
            throw WorkflowFileError.workflowNotFound(workflow.id)
        }
        _ = try await fileRepo.duplicate(loaded, newName: newName)
        await reload()

        // Find the new workflow (it will have the new name)
        let name = newName ?? "\(workflow.name) Copy"
        return workflows.first { $0.name == name } ?? workflow
    }

    // MARK: - Preferences

    /// Update enabled state
    func setEnabled(_ enabled: Bool, for workflowId: UUID) async throws {
        try prefsRepo.update(workflowId: workflowId, isEnabled: enabled)
        await reload()
        syncPinnedToiCloud()
    }

    /// Update pinned state
    func setPinned(_ pinned: Bool, for workflowId: UUID) async throws {
        try prefsRepo.update(workflowId: workflowId, isPinned: pinned)
        await reload()
        syncPinnedToiCloud()
    }

    /// Update auto-run state
    func setAutoRun(_ autoRun: Bool, for workflowId: UUID, order: Int = 0) async throws {
        try prefsRepo.update(workflowId: workflowId, autoRun: autoRun, autoRunOrder: order)
        await reload()
    }

    /// Update sort order
    func setSortOrder(_ order: Int, for workflowId: UUID) async throws {
        try prefsRepo.update(workflowId: workflowId, sortOrder: order)
        await reload()
    }

    // MARK: - iCloud Sync

    private let iCloudPinnedKey = "pinnedWorkflows"

    /// Sync pinned workflow info to iCloud Key-Value Store
    /// iOS reads this to show pinned workflows in MAC ACTIONS section
    private func syncPinnedToiCloud() {
        let pinnedInfo: [[String: String]] = pinnedWorkflows.map { workflow in
            [
                "id": workflow.id.uuidString,
                "name": workflow.name,
                "icon": workflow.icon
            ]
        }

        if let data = try? JSONEncoder().encode(pinnedInfo) {
            NSUbiquitousKeyValueStore.default.set(data, forKey: iCloudPinnedKey)
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    // MARK: - Legacy Migration

    private let legacyMigrationKey = "workflowService_migrated_v1"

    /// Migrate from old WorkflowManager (UserDefaults blob)
    private func migrateFromLegacy() async {
        // Check if already migrated
        guard !UserDefaults.standard.bool(forKey: legacyMigrationKey) else {
            return
        }

        log.info("Migrating from legacy WorkflowManager...")

        // Load legacy workflows from UserDefaults
        let legacyKey = "workflows_v2"
        guard let data = UserDefaults.standard.data(forKey: legacyKey),
              let legacyWorkflows = try? JSONDecoder().decode([WorkflowDefinition].self, from: data),
              !legacyWorkflows.isEmpty else {
            log.info("No legacy workflows to migrate")
            UserDefaults.standard.set(true, forKey: legacyMigrationKey)
            return
        }

        var migratedCount = 0

        for workflow in legacyWorkflows {
            // Skip system workflows (they're bundled now)
            if workflow.id == WorkflowDefinition.systemTranscribeWorkflowId ||
               workflow.id == WorkflowDefinition.heyTalkieWorkflowId {
                // Just migrate preferences
                try? prefsRepo.migrateFromDefinition(workflow)
                continue
            }

            // Save user workflows to user/ directory
            do {
                try await fileRepo.save(workflow)
                try? prefsRepo.migrateFromDefinition(workflow)
                migratedCount += 1
            } catch {
                log.error("Failed to migrate workflow '\(workflow.name)': \(error)")
            }
        }

        log.info("Migrated \(migratedCount) workflows from legacy storage")
        UserDefaults.standard.set(true, forKey: legacyMigrationKey)
    }
}
