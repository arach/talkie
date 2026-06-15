//
//  WorkflowContentViews.swift
//  Talkie macOS
//
//  Extracted from NavigationView.swift
//

import SwiftUI
import TalkieKit

private let logger = Log(.ui)

// MARK: - Legacy Tool Content Views (keeping for reference)

struct WorkflowsContentView: View {
    private let workflowService = WorkflowService.shared
    private let fileRepo = WorkflowFileRepository.shared
    private let settings = SettingsManager.shared
    private var memosVM: MemosViewModel { MemosViewModel.shared }
    @State private var selectedWorkflowID: UUID?
    @State private var editingWorkflow: WorkflowDefinition?
    @State private var showingMemoSelector = false
    @State private var showingTemplatePicker = false

    // Get current workflow from service
    private var currentWorkflow: Workflow? {
        guard let id = selectedWorkflowID else { return nil }
        return workflowService.workflow(byID: id)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: Workflow List
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

                Divider()
                    .opacity(0.5)

                // Workflow List - unified, no sections
                ScrollView {
                    VStack(spacing: 4) {
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
            .frame(width: 280)
            .background(Theme.current.surface1)

            Divider()
                .opacity(0.5)

            // Right: Inline Editor - expands to fill
            if let workflow = editingWorkflow {
                WorkflowInlineEditor(
                    workflow: editableWorkflowBinding(fallback: workflow),
                    onSave: saveWorkflow,
                    onDelete: deleteCurrentWorkflow,
                    onDuplicate: duplicateCurrentWorkflow,
                    onRun: { showingMemoSelector = true },
                    onBack: clearWorkflowSelection
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.secondary.opacity(0.2))

                    Text("SELECT OR CREATE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary.opacity(0.5))

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await memosVM.loadWorkflowMemos()
        }
        .sheet(isPresented: $showingMemoSelector) {
            if let workflow = editingWorkflow {
                // Use untranscribed memos for TRANSCRIBE workflows, transcribed for others
                let memosToShow = workflow.startsWithTranscribe ? memosVM.untranscribedMemos : memosVM.transcribedMemos
                WorkflowMemoSelectorSheet(
                    workflow: workflow,
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
                maintainer: template.maintainer,
                inputs: template.inputs,
                steps: template.steps.map { step in
                    // Give each step a fresh UUID too
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
            // Create blank workflow
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

    private func saveWorkflow() {
        guard var definition = editingWorkflow else { return }
        definition.modifiedAt = Date()

        Task {
            do {
                try await workflowService.save(definition)
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
        let deletedID = workflow.id

        if selectedWorkflowID == deletedID {
            clearWorkflowSelection()
        }

        Task {
            do {
                try await workflowService.delete(workflow)
            } catch {
                logger.error("Failed to delete workflow: \(error)")
            }
        }
    }

    private func clearWorkflowSelection() {
        editingWorkflow = nil
        selectedWorkflowID = nil
    }

    private func editableWorkflowBinding(fallback workflow: WorkflowDefinition) -> Binding<WorkflowDefinition> {
        Binding(
            get: { editingWorkflow ?? workflow },
            set: { updated in
                editingWorkflow = updated
                selectedWorkflowID = updated.id
            }
        )
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

    private func runWorkflow(_ workflow: WorkflowDefinition, on memo: MemoModel) {
        Task {
            do {
                let _ = try await WorkflowExecutor.shared.executeWorkflow(workflow, for: memo)
            } catch {
                await SystemEventManager.shared.log(.error, "Workflow failed: \(workflow.name)", detail: error.localizedDescription)
            }
        }
    }
}

struct WorkflowCard: View {
    private let settings = SettingsManager.shared
    private var memosVM: MemosViewModel { MemosViewModel.shared }
    let icon: String
    let title: String
    let description: String
    let actionType: WorkflowActionType
    let provider: String
    let model: String

    @State private var showingMemoSelector = false
    @State private var isExecuting = false
    @State private var errorMessage: String?

    var body: some View {
        Button(action: {
            if !memosVM.transcribedMemos.isEmpty {
                showingMemoSelector = true
            } else {
                errorMessage = "No transcribed memos available"
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(Theme.current.fontTitle)
                    .foregroundColor(.primary.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .background(Theme.current.surfaceHover)
                    .cornerRadius(CornerRadius.xs)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(Theme.current.fontSMBold)

                    Text(description)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    if isExecuting {
                        HStack(spacing: 4) {
                            BrailleSpinner(size: 10)
                            Text("RUNNING...")
                                .font(Theme.current.fontXSMedium)
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(Theme.current.fontSM)
                    .foregroundColor(.secondary.opacity(0.3))
            }
            .padding(Spacing.md)
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.xs)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isExecuting)
        .task {
            await memosVM.loadTranscribedMemos()
        }
        .sheet(isPresented: $showingMemoSelector) {
            MemoSelectorSheet(
                memos: memosVM.transcribedMemos,
                actionType: actionType,
                provider: provider,
                model: model,
                onExecute: { memo in
                    executeWorkflow(for: memo)
                }
            )
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
            Button("OK") { errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private func executeWorkflow(for memo: MemoModel) {
        isExecuting = true
        showingMemoSelector = false

        Task {
            do {
                // Use the new MemoModel-based execution
                let workflow = WorkflowDefinition(
                    name: title,
                    description: description,
                    steps: [
                        WorkflowStep(
                            type: actionType == .summarize ? .llm : .llm,
                            config: .llm(LLMStepConfig(
                                provider: WorkflowLLMProvider.fromDisplayName(provider),
                                modelId: model,
                                prompt: actionType.systemPrompt.replacingOccurrences(of: "{{TRANSCRIPT}}", with: "{{transcript}}")
                            )),
                            outputKey: "result"
                        )
                    ]
                )
                let _ = try await WorkflowExecutor.shared.executeWorkflow(workflow, for: memo)
                await MainActor.run {
                    isExecuting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isExecuting = false
                }
            }
        }
    }
}

struct MemoSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let settings = SettingsManager.shared
    let memos: [MemoModel]
    let actionType: WorkflowActionType
    let provider: String
    let model: String
    let onExecute: (MemoModel) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Memo")
                    .font(Theme.current.fontTitleBold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(Theme.current.fontHeadline)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.lg)

            Divider()

            // Memo list
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(memos) { memo in
                        Button(action: {
                            onExecute(memo)
                            dismiss()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "waveform")
                                    .font(Theme.current.fontTitle)
                                    .foregroundColor(.blue)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(memo.displayTitle)
                                        .font(Theme.current.fontBodyMedium)
                                        .lineLimit(1)

                                    Text(memo.createdAt, style: .relative)
                                        .font(Theme.current.fontXS)
                                        .foregroundColor(Theme.current.foregroundSecondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(Theme.current.fontSM)
                                    .foregroundColor(Theme.current.foregroundSecondary)
                            }
                            .padding(Spacing.md)
                            .background(Theme.current.surface1)
                            .cornerRadius(CornerRadius.xs)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.lg)
            }
        }
        .frame(width: 400, height: 500)
        .background(Theme.current.surfaceInput)
    }
}
