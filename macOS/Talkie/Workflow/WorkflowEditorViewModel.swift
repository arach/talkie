//
//  WorkflowEditorViewModel.swift
//  Talkie macOS
//
//  ViewModel for workflow editing - fixes state management issues
//  Uses WorkflowService as the single source of truth
//

import Foundation
import Observation
import SwiftUI
import TalkieKit

private let log = Log(.workflow)

/// ViewModel for workflow list and editing
@MainActor
@Observable
final class WorkflowEditorViewModel {
    // MARK: - Singleton

    static let shared = WorkflowEditorViewModel()

    // MARK: - State

    /// Currently selected workflow ID (source of truth for selection)
    var selectedWorkflowID: UUID?

    /// Editing state - local draft that hasn't been saved yet
    /// nil = viewing (no unsaved changes), non-nil = editing mode
    private(set) var editingDraft: WorkflowDefinition?

    /// True if there are unsaved changes
    var hasUnsavedChanges: Bool {
        guard let draft = editingDraft else { return false }
        guard let original = workflowService.workflow(byID: draft.id) else {
            return true  // New workflow that hasn't been saved
        }
        // Compare key fields
        return draft.name != original.definition.name ||
               draft.description != original.definition.description ||
               draft.icon != original.definition.icon ||
               draft.color != original.definition.color ||
               draft.steps.count != original.definition.steps.count
    }

    /// Is the currently selected workflow a system workflow?
    var isSystemWorkflow: Bool {
        guard let id = selectedWorkflowID,
              let workflow = workflowService.workflow(byID: id) else {
            return false
        }
        return workflow.isSystem
    }

    // MARK: - Dependencies

    private let workflowService = WorkflowService.shared

    // MARK: - Computed Properties

    /// All workflows from the service
    var workflows: [Workflow] {
        workflowService.workflows
    }

    /// The currently selected workflow (from service, not draft)
    var selectedWorkflow: Workflow? {
        guard let id = selectedWorkflowID else { return nil }
        return workflowService.workflow(byID: id)
    }

    /// The workflow being displayed - draft if editing, otherwise from service
    var displayedWorkflow: WorkflowDefinition? {
        if let draft = editingDraft {
            return draft
        }
        return selectedWorkflow?.definition
    }

    // MARK: - Init

    private init() {}

    // MARK: - Selection

    /// Select a workflow
    func select(_ workflowID: UUID?) {
        // If changing selection with unsaved changes, discard them
        if workflowID != selectedWorkflowID && hasUnsavedChanges {
            log.warning("Discarding unsaved changes when selecting new workflow")
            editingDraft = nil
        }

        selectedWorkflowID = workflowID
    }

    /// Select a workflow by Workflow object
    func select(_ workflow: Workflow) {
        select(workflow.id)
    }

    // MARK: - Editing

    /// Start editing the current workflow (creates a draft copy)
    func startEditing() {
        guard let workflow = selectedWorkflow else { return }
        editingDraft = workflow.definition
    }

    /// Update the draft (call when user makes changes)
    func updateDraft(_ draft: WorkflowDefinition) {
        editingDraft = draft
    }

    /// Update a specific field on the draft
    func updateDraftName(_ name: String) {
        guard var draft = editingDraft else { return }
        draft = WorkflowDefinition(
            id: draft.id,
            name: name,
            description: draft.description,
            icon: draft.icon,
            color: draft.color,
            steps: draft.steps,
            isEnabled: draft.isEnabled,
            isPinned: draft.isPinned,
            autoRun: draft.autoRun,
            autoRunOrder: draft.autoRunOrder,
            createdAt: draft.createdAt,
            modifiedAt: Date()
        )
        editingDraft = draft
    }

    func updateDraftDescription(_ description: String) {
        guard var draft = editingDraft else { return }
        draft = WorkflowDefinition(
            id: draft.id,
            name: draft.name,
            description: description,
            icon: draft.icon,
            color: draft.color,
            steps: draft.steps,
            isEnabled: draft.isEnabled,
            isPinned: draft.isPinned,
            autoRun: draft.autoRun,
            autoRunOrder: draft.autoRunOrder,
            createdAt: draft.createdAt,
            modifiedAt: Date()
        )
        editingDraft = draft
    }

    func updateDraftIcon(_ icon: String) {
        guard var draft = editingDraft else { return }
        draft = WorkflowDefinition(
            id: draft.id,
            name: draft.name,
            description: draft.description,
            icon: icon,
            color: draft.color,
            steps: draft.steps,
            isEnabled: draft.isEnabled,
            isPinned: draft.isPinned,
            autoRun: draft.autoRun,
            autoRunOrder: draft.autoRunOrder,
            createdAt: draft.createdAt,
            modifiedAt: Date()
        )
        editingDraft = draft
    }

    func updateDraftColor(_ color: WorkflowColor) {
        guard var draft = editingDraft else { return }
        draft = WorkflowDefinition(
            id: draft.id,
            name: draft.name,
            description: draft.description,
            icon: draft.icon,
            color: color,
            steps: draft.steps,
            isEnabled: draft.isEnabled,
            isPinned: draft.isPinned,
            autoRun: draft.autoRun,
            autoRunOrder: draft.autoRunOrder,
            createdAt: draft.createdAt,
            modifiedAt: Date()
        )
        editingDraft = draft
    }

    /// Cancel editing and discard changes
    func cancelEditing() {
        editingDraft = nil
    }

    // MARK: - CRUD Operations

    /// Create a new workflow and start editing it
    func createNewWorkflow() {
        let newWorkflow = WorkflowDefinition(
            name: "Untitled Workflow",
            description: ""
        )
        selectedWorkflowID = newWorkflow.id
        editingDraft = newWorkflow
    }

    /// Save the current draft
    func save() async throws {
        guard let draft = editingDraft else {
            log.warning("No draft to save")
            return
        }

        var updated = draft
        updated = WorkflowDefinition(
            id: draft.id,
            name: draft.name,
            description: draft.description,
            icon: draft.icon,
            color: draft.color,
            steps: draft.steps,
            isEnabled: draft.isEnabled,
            isPinned: draft.isPinned,
            autoRun: draft.autoRun,
            autoRunOrder: draft.autoRunOrder,
            createdAt: draft.createdAt,
            modifiedAt: Date()
        )

        try await workflowService.save(updated)
        editingDraft = nil
        log.info("Saved workflow: \(updated.name)")
    }

    /// Delete the selected workflow
    func delete() async throws {
        guard let workflow = selectedWorkflow else {
            log.warning("No workflow selected to delete")
            return
        }

        guard !workflow.isSystem else {
            log.warning("Cannot delete system workflow")
            return
        }

        try await workflowService.delete(workflow)
        editingDraft = nil
        selectedWorkflowID = nil
        log.info("Deleted workflow: \(workflow.name)")
    }

    /// Duplicate the selected workflow
    func duplicate() async throws {
        guard let workflow = selectedWorkflow else {
            log.warning("No workflow selected to duplicate")
            return
        }

        let duplicate = try await workflowService.duplicate(workflow)
        selectedWorkflowID = duplicate.id
        editingDraft = nil  // Don't start editing the duplicate immediately
        log.info("Duplicated workflow: \(workflow.name) -> \(duplicate.name)")
    }

    // MARK: - Preferences

    /// Toggle enabled state
    func toggleEnabled() async throws {
        guard let workflow = selectedWorkflow else { return }
        try await workflowService.setEnabled(!workflow.isEnabled, for: workflow.id)
    }

    /// Toggle pinned state
    func togglePinned() async throws {
        guard let workflow = selectedWorkflow else { return }
        try await workflowService.setPinned(!workflow.isPinned, for: workflow.id)
    }

    /// Toggle auto-run state
    func toggleAutoRun() async throws {
        guard let workflow = selectedWorkflow else { return }
        try await workflowService.setAutoRun(!workflow.autoRun, for: workflow.id)
    }

    // MARK: - Step Operations

    /// Add a step to the draft
    func addStep(_ step: WorkflowStep) {
        guard var draft = editingDraft else { return }
        var steps = draft.steps
        steps.append(step)
        draft = WorkflowDefinition(
            id: draft.id,
            name: draft.name,
            description: draft.description,
            icon: draft.icon,
            color: draft.color,
            steps: steps,
            isEnabled: draft.isEnabled,
            isPinned: draft.isPinned,
            autoRun: draft.autoRun,
            autoRunOrder: draft.autoRunOrder,
            createdAt: draft.createdAt,
            modifiedAt: Date()
        )
        editingDraft = draft
    }

    /// Remove a step from the draft
    func removeStep(at index: Int) {
        guard var draft = editingDraft else { return }
        var steps = draft.steps
        guard index >= 0 && index < steps.count else { return }
        steps.remove(at: index)
        draft = WorkflowDefinition(
            id: draft.id,
            name: draft.name,
            description: draft.description,
            icon: draft.icon,
            color: draft.color,
            steps: steps,
            isEnabled: draft.isEnabled,
            isPinned: draft.isPinned,
            autoRun: draft.autoRun,
            autoRunOrder: draft.autoRunOrder,
            createdAt: draft.createdAt,
            modifiedAt: Date()
        )
        editingDraft = draft
    }

    /// Move a step within the draft
    func moveStep(from source: IndexSet, to destination: Int) {
        guard var draft = editingDraft else { return }
        var steps = draft.steps
        steps.move(fromOffsets: source, toOffset: destination)
        draft = WorkflowDefinition(
            id: draft.id,
            name: draft.name,
            description: draft.description,
            icon: draft.icon,
            color: draft.color,
            steps: steps,
            isEnabled: draft.isEnabled,
            isPinned: draft.isPinned,
            autoRun: draft.autoRun,
            autoRunOrder: draft.autoRunOrder,
            createdAt: draft.createdAt,
            modifiedAt: Date()
        )
        editingDraft = draft
    }
}
