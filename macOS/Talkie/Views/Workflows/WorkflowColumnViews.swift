//
//  WorkflowColumnViews.swift
//  Talkie macOS
//
//  Extracted from NavigationView.swift
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

// MARK: - Workflow Column Views

struct WorkflowListColumn: View {
    @Binding var selectedWorkflowID: UUID?
    @Binding var editingWorkflow: WorkflowDefinition?
    private let workflowService = WorkflowService.shared
    private let fileRepo = WorkflowFileRepository.shared
    private let settings = SettingsManager.shared

    @State private var showingTemplatePicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WORKFLOWS")
                        .font(Theme.current.fontSMBold)
                    Text("\(workflowService.workflows.count) total")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                Spacer()
                Button(action: { showingTemplatePicker = true }) {
                    Image(systemName: "plus")
                        .font(Theme.current.fontBody)
                        .foregroundColor(Theme.current.foreground)
                        .frame(width: 24, height: 24)
                        .background(Theme.current.surfaceSelected)
                        .cornerRadius(CornerRadius.xs)
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.md)
            .background(Theme.current.surface1)

            Divider()

            // Workflow List
            ScrollView {
                VStack(spacing: Spacing.xs) {
                    ForEach(workflowService.workflows) { workflow in
                        WorkflowListItem(
                            workflow: workflow.definition,
                            isSelected: selectedWorkflowID == workflow.id,
                            isSystem: workflow.isSystem,
                            onSelect: { selectWorkflow(workflow) },
                            onEdit: { selectWorkflow(workflow) }
                        )
                    }
                }
                .padding(Spacing.sm)
            }
        }
        .sheet(isPresented: $showingTemplatePicker) {
            WorkflowTemplatePicker(
                templates: fileRepo.loadTemplates(),
                onSelectBlank: {
                    createNewWorkflow(from: nil)
                    showingTemplatePicker = false
                },
                onSelectTemplate: { template in
                    createNewWorkflow(from: template)
                    showingTemplatePicker = false
                },
                onCancel: {
                    showingTemplatePicker = false
                }
            )
        }
    }

    private func createNewWorkflow(from template: WorkflowDefinition?) {
        let newWorkflow: WorkflowDefinition
        if let template = template {
            // Create a copy from template with fresh UUID
            newWorkflow = WorkflowDefinition(
                id: UUID(),
                name: template.name,
                description: template.description,
                icon: template.icon,
                color: template.color,
                steps: template.steps.map { step in
                    WorkflowStep(
                        id: UUID(),
                        type: step.type,
                        config: step.config,
                        outputKey: step.outputKey,
                        isEnabled: step.isEnabled,
                        condition: step.condition
                    )
                },
                isEnabled: true,
                isPinned: false,
                autoRun: false,
                autoRunOrder: 0,
                createdAt: Date(),
                modifiedAt: Date()
            )
        } else {
            newWorkflow = WorkflowDefinition(
                name: "Untitled Workflow",
                description: ""
            )
        }
        editingWorkflow = newWorkflow
        selectedWorkflowID = newWorkflow.id
    }

    private func selectWorkflow(_ workflow: Workflow) {
        // Only update editingWorkflow if selecting a different workflow
        // This prevents overwriting unsaved edits when clicking the same item
        if selectedWorkflowID != workflow.id {
            selectedWorkflowID = workflow.id
            editingWorkflow = workflow.definition
        }
    }
}

struct WorkflowDetailColumn: View {
    @Binding var editingWorkflow: WorkflowDefinition?
    @Binding var selectedWorkflowID: UUID?
    private let workflowService = WorkflowService.shared
    private let fileRepo = WorkflowFileRepository.shared
    private let settings = SettingsManager.shared
    private var memosVM: MemosViewModel { MemosViewModel.shared }
    @State private var showingMemoSelector = false
    @State private var showingTemplatePicker = false

    // Get fresh workflow from service (source of truth)
    private var currentWorkflow: Workflow? {
        guard let id = editingWorkflow?.id else { return nil }
        return workflowService.workflow(byID: id)
    }

    var body: some View {
        Group {
            if let binding = Binding($editingWorkflow) {
                WorkflowInlineEditor(
                    workflow: binding,
                    onSave: saveWorkflow,
                    onDelete: deleteCurrentWorkflow,
                    onDuplicate: duplicateCurrentWorkflow,
                    onRun: { showingMemoSelector = true }
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(Theme.current.foregroundMuted)

                    Text("SELECT OR CREATE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Button(action: { showingTemplatePicker = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(Theme.current.fontXS)
                            Text("NEW WORKFLOW")
                                .font(Theme.current.fontXSBold)
                        }
                        .foregroundColor(Theme.current.foreground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.current.surfaceSelected)
                        .cornerRadius(CornerRadius.xs)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.current.surfaceInput)
            }
        }
        .task {
            await memosVM.loadWorkflowMemos()
        }
        .sheet(isPresented: $showingMemoSelector) {
            // Use currentWorkflow from service for fresh data (must be saved to run)
            if let workflow = currentWorkflow {
                // Use untranscribed memos for TRANSCRIBE workflows, transcribed for others
                let memosToShow = workflow.definition.startsWithTranscribe ? memosVM.untranscribedMemos : memosVM.transcribedMemos
                WorkflowMemoSelectorSheet(
                    workflow: workflow.definition,
                    memos: memosToShow,
                    onSelect: { memo in
                        runWorkflow(workflow, on: memo)
                        showingMemoSelector = false
                    },
                    onCancel: {
                        showingMemoSelector = false
                    }
                )
            }
        }
        .sheet(isPresented: $showingTemplatePicker) {
            WorkflowTemplatePicker(
                templates: fileRepo.loadTemplates(),
                onSelectBlank: {
                    createNewWorkflow(from: nil)
                    showingTemplatePicker = false
                },
                onSelectTemplate: { template in
                    createNewWorkflow(from: template)
                    showingTemplatePicker = false
                },
                onCancel: {
                    showingTemplatePicker = false
                }
            )
        }
    }

    private func createNewWorkflow(from template: WorkflowDefinition?) {
        let newWorkflow: WorkflowDefinition
        if let template = template {
            // Create a copy from template with fresh UUID
            newWorkflow = WorkflowDefinition(
                id: UUID(),
                name: template.name,
                description: template.description,
                icon: template.icon,
                color: template.color,
                steps: template.steps.map { step in
                    WorkflowStep(
                        id: UUID(),
                        type: step.type,
                        config: step.config,
                        outputKey: step.outputKey,
                        isEnabled: step.isEnabled,
                        condition: step.condition
                    )
                },
                isEnabled: true,
                isPinned: false,
                autoRun: false,
                autoRunOrder: 0,
                createdAt: Date(),
                modifiedAt: Date()
            )
        } else {
            newWorkflow = WorkflowDefinition(
                name: "Untitled Workflow",
                description: ""
            )
        }
        editingWorkflow = newWorkflow
        selectedWorkflowID = newWorkflow.id
    }

    private func saveWorkflow() {
        // Use editingWorkflow binding (contains user's edits)
        guard var definition = editingWorkflow else { return }
        definition.modifiedAt = Date()

        Task {
            do {
                try await workflowService.save(definition)
                // Sync binding from service
                await MainActor.run {
                    editingWorkflow = workflowService.workflow(byID: definition.id)?.definition
                }
            } catch {
                logger.error("Failed to save workflow: \(error)")
            }
        }
    }

    private func deleteCurrentWorkflow() {
        guard let workflow = currentWorkflow else { return }

        Task {
            do {
                try await workflowService.delete(workflow)
                await MainActor.run {
                    editingWorkflow = nil
                    selectedWorkflowID = nil
                }
            } catch {
                logger.error("Failed to delete workflow: \(error)")
            }
        }
    }

    private func duplicateCurrentWorkflow() {
        guard let workflow = currentWorkflow else { return }

        Task {
            do {
                let duplicate = try await workflowService.duplicate(workflow)
                await MainActor.run {
                    editingWorkflow = duplicate.definition
                    selectedWorkflowID = duplicate.id
                }
            } catch {
                logger.error("Failed to duplicate workflow: \(error)")
            }
        }
    }

    private func runWorkflow(_ workflow: Workflow, on memo: MemoModel) {
        Task {
            do {
                let _ = try await WorkflowExecutor.shared.executeWorkflow(workflow.definition, for: memo)
            } catch {
                await SystemEventManager.shared.log(.error, "Workflow failed: \(workflow.name)", detail: error.localizedDescription)
            }
        }
    }
}

// MARK: - Column Resizer

struct ColumnResizer: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    private let settings = SettingsManager.shared

    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(isDragging ? settings.resolvedAccentColor : (isHovering ? Color.secondary.opacity(0.3) : Color.clear))
            .frame(width: 4)
            .contentShape(Rectangle().inset(by: -4))
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else if !isDragging {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        let newWidth = width + value.translation.width
                        width = min(maxWidth, max(minWidth, newWidth))
                    }
                    .onEnded { _ in
                        isDragging = false
                        NSCursor.pop()
                    }
            )
    }
}

