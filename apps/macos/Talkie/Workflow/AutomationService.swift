//
//  AutomationService.swift
//  Talkie macOS
//
//  Service for managing automations - event-triggered or scheduled workflow execution.
//  Provides CRUD operations and event handling for automations.
//

import Foundation
import Observation
import GRDB
import TalkieKit

private let log = Log(.workflow)

// MARK: - Automation Service

@MainActor
@Observable
final class AutomationService {
    static let shared = AutomationService()

    // MARK: - State

    /// All automations
    private(set) var automations: [Automation] = []

    /// Quick access by ID
    private var automationsById: [UUID: Automation] = [:]

    // MARK: - Dependencies

    private let repository = AutomationRepository()

    // MARK: - Initialization

    private init() {}

    /// Initialize the service (call on app launch)
    func initialize() async {
        log.info("Initializing AutomationService")
        await reload()
        log.info("AutomationService ready with \(automations.count) automation(s)")
    }

    // MARK: - Reload

    /// Reload all automations from database
    func reload() async {
        do {
            automations = try repository.fetchAll()
            automationsById = Dictionary(uniqueKeysWithValues: automations.map { ($0.id, $0) })
        } catch {
            log.error("Failed to load automations: \(error)")
            automations = []
            automationsById = [:]
        }
    }

    // MARK: - Read

    /// Get an automation by ID
    func automation(byID id: UUID) -> Automation? {
        automationsById[id]
    }

    /// Get all enabled automations
    var enabledAutomations: [Automation] {
        automations.filter { $0.isEnabled }
    }

    /// Get automations for a specific event trigger
    func automations(for event: EventTrigger) -> [Automation] {
        enabledAutomations.filter { automation in
            if case .event(let triggerEvent) = automation.trigger {
                return triggerEvent == event
            }
            return false
        }
    }

    /// Get all scheduled automations
    var scheduledAutomations: [Automation] {
        enabledAutomations.filter { automation in
            if case .schedule = automation.trigger {
                return true
            }
            return false
        }
    }

    // MARK: - CRUD

    /// Create a new automation
    func create(_ automation: Automation) async throws {
        try repository.save(automation)
        await reload()
        log.info("Created automation: \(automation.name)")

        // Notify scheduler if this is a scheduled automation
        if case .schedule = automation.trigger {
            await AutomationScheduler.shared.refreshSchedules()
        }
    }

    /// Update an existing automation
    func update(_ automation: Automation) async throws {
        var updated = automation
        updated.updatedAt = Date()
        try repository.save(updated)
        await reload()
        log.info("Updated automation: \(automation.name)")

        // Notify scheduler to refresh
        await AutomationScheduler.shared.refreshSchedules()
    }

    /// Delete an automation
    func delete(_ automation: Automation) async throws {
        try repository.delete(automation.id)
        await reload()
        log.info("Deleted automation: \(automation.name)")

        // Notify scheduler to refresh
        await AutomationScheduler.shared.refreshSchedules()
    }

    /// Toggle enabled state
    func setEnabled(_ enabled: Bool, for automationId: UUID) async throws {
        guard var automation = automationsById[automationId] else {
            throw AutomationError.automationNotFound(automationId)
        }
        automation.isEnabled = enabled
        automation.updatedAt = Date()
        try repository.save(automation)
        await reload()

        // Notify scheduler to refresh
        await AutomationScheduler.shared.refreshSchedules()
    }

    // MARK: - Event Handling

    /// Run all enabled automations for a given event
    /// - Parameters:
    ///   - event: The event that triggered this call
    ///   - memo: The memo associated with the event (optional, for memo-related events)
    func runAutomationsForEvent(_ event: EventTrigger, memo: MemoModel? = nil) async {
        let matchingAutomations = automations(for: event)

        if matchingAutomations.isEmpty {
            log.debug("No automations configured for event: \(event.rawValue)")
            return
        }

        log.info("[AUTOMATION] Running \(matchingAutomations.count) automation(s) for event: \(event.rawValue)")

        for automation in matchingAutomations {
            await runAutomation(automation, memo: memo)
        }
    }

    /// Run a single automation
    /// - Parameters:
    ///   - automation: The automation to run
    ///   - memo: The memo to run against (optional)
    func runAutomation(_ automation: Automation, memo: MemoModel? = nil) async {
        log.info("[AUTOMATION] Executing: \(automation.name)")

        // Get the workflow
        guard let workflow = WorkflowService.shared.workflow(byID: automation.workflowId) else {
            log.error("[AUTOMATION] Workflow not found for automation '\(automation.name)': \(automation.workflowId)")
            return
        }

        // Check if workflow is enabled
        guard workflow.isEnabled else {
            log.info("[AUTOMATION] Skipping '\(automation.name)' - workflow '\(workflow.name)' is disabled")
            return
        }

        // Execute the workflow
        do {
            if let memo = memo {
                // Run workflow on the memo
                _ = try await WorkflowExecutor.shared.executeWorkflow(workflow.definition, for: memo)
                log.info("[AUTOMATION] Completed: \(automation.name) on memo '\(memo.displayTitle)'")
            } else {
                // For scheduled automations without a specific memo, run on recent memos or skip
                // Future: Could run on "all unprocessed" or fetch latest memo
                log.info("[AUTOMATION] Completed: \(automation.name) (no memo context)")
            }
        } catch is WorkflowExecutor.TriggerNotMatchedError {
            log.info("[AUTOMATION] Skipped: \(automation.name) - trigger condition not matched")
        } catch {
            log.error("[AUTOMATION] Failed: \(automation.name) - \(error.localizedDescription)")
        }
    }
}

// MARK: - Automation Repository

/// Repository for automation CRUD operations
struct AutomationRepository {
    private let dbManager = DatabaseManager.shared

    // MARK: - Read

    /// Fetch all automations
    func fetchAll() throws -> [Automation] {
        let db = try dbManager.database()
        return try db.read { db in
            let records = try AutomationRecord
                .order(Column("createdAt").desc)
                .fetchAll(db)
            return try records.map { try $0.toAutomation() }
        }
    }

    /// Fetch an automation by ID
    func fetch(id: UUID) throws -> Automation? {
        let db = try dbManager.database()
        return try db.read { db in
            guard let record = try AutomationRecord.fetchOne(db, key: id.uuidString) else {
                return nil
            }
            return try record.toAutomation()
        }
    }

    /// Fetch enabled automations
    func fetchEnabled() throws -> [Automation] {
        let db = try dbManager.database()
        return try db.read { db in
            let records = try AutomationRecord
                .filter(Column("isEnabled") == true)
                .order(Column("createdAt").desc)
                .fetchAll(db)
            return try records.map { try $0.toAutomation() }
        }
    }

    /// Fetch automations for a specific workflow
    func fetchByWorkflow(id: UUID) throws -> [Automation] {
        let db = try dbManager.database()
        return try db.read { db in
            let records = try AutomationRecord
                .filter(Column("workflowId") == id.uuidString)
                .fetchAll(db)
            return try records.map { try $0.toAutomation() }
        }
    }

    // MARK: - Write

    /// Save an automation (insert or update)
    func save(_ automation: Automation) throws {
        let db = try dbManager.database()
        let record = try AutomationRecord(from: automation)
        try db.write { db in
            try record.save(db)
        }
    }

    /// Delete an automation
    func delete(_ id: UUID) throws {
        let db = try dbManager.database()
        try db.write { db in
            _ = try AutomationRecord.deleteOne(db, key: id.uuidString)
        }
    }

    /// Delete all automations for a workflow
    func deleteByWorkflow(id: UUID) throws {
        let db = try dbManager.database()
        try db.write { db in
            _ = try AutomationRecord
                .filter(Column("workflowId") == id.uuidString)
                .deleteAll(db)
        }
    }
}
