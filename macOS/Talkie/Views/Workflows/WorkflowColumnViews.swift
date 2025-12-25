//
//  WorkflowColumnViews.swift
//  Talkie macOS
//
//  Extracted from NavigationView.swift
//

import SwiftUI
import CoreData
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

// MARK: - Workflow Column Views

struct WorkflowListColumn: View {
    @Binding var selectedWorkflowID: UUID?
    @Binding var editingWorkflow: WorkflowDefinition?
    private let workflowManager = WorkflowManager.shared
    private let settings = SettingsManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WORKFLOWS")
                        .font(Theme.current.fontSMBold)
                    Text("\(workflowManager.workflows.count) total")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                Spacer()
                Button(action: createNewWorkflow) {
                    Image(systemName: "plus")
                        .font(SettingsManager.shared.fontBody)
                        .foregroundColor(Theme.current.foreground)
                        .frame(width: 24, height: 24)
                        .background(Theme.current.surfaceSelected)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Theme.current.surface1)

            Divider()

            // Workflow List
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(workflowManager.workflows) { workflow in
                        WorkflowListItem(
                            workflow: workflow,
                            isSelected: selectedWorkflowID == workflow.id,
                            isSystem: false,
                            onSelect: { selectWorkflow(workflow) },
                            onEdit: { selectWorkflow(workflow) }
                        )
                    }
                }
                .padding(8)
            }
        }
    }

    private func createNewWorkflow() {
        let newWorkflow = WorkflowDefinition(
            name: "Untitled Workflow",
            description: ""
        )
        editingWorkflow = newWorkflow
        selectedWorkflowID = newWorkflow.id
    }

    private func selectWorkflow(_ workflow: WorkflowDefinition) {
        // Only update editingWorkflow if selecting a different workflow
        // This prevents overwriting unsaved edits when clicking the same item
        if selectedWorkflowID != workflow.id {
            selectedWorkflowID = workflow.id
            editingWorkflow = workflow
        }
    }
}

struct WorkflowDetailColumn: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var editingWorkflow: WorkflowDefinition?
    @Binding var selectedWorkflowID: UUID?
    private let workflowManager = WorkflowManager.shared
    private let settings = SettingsManager.shared
    @State private var showingMemoSelector = false

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)]
    )
    private var allMemos: FetchedResults<VoiceMemo>

    private var transcribedMemos: [VoiceMemo] {
        allMemos.filter { $0.transcription != nil && !$0.transcription!.isEmpty }
    }

    /// Memos that need transcription (for TRANSCRIBE workflows like HQ Transcribe)
    private var untranscribedMemos: [VoiceMemo] {
        allMemos.filter { ($0.transcription == nil || $0.transcription!.isEmpty) && !$0.isTranscribing }
    }

    // Get fresh workflow from manager (source of truth)
    private var currentWorkflow: WorkflowDefinition? {
        guard let id = editingWorkflow?.id else { return nil }
        return workflowManager.workflows.first { $0.id == id }
    }

    var body: some View {
        Group {
            if editingWorkflow != nil {
                WorkflowInlineEditor(
                    workflow: $editingWorkflow,
                    onSave: saveWorkflow,
                    onDelete: deleteCurrentWorkflow,
                    onDuplicate: duplicateCurrentWorkflow,
                    onRun: { showingMemoSelector = true }
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.stack")
                        .font(SettingsManager.shared.fontDisplay)
                        .foregroundColor(.secondary.opacity(0.2))

                    Text("SELECT OR CREATE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary.opacity(0.5))

                    Button(action: createNewWorkflow) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(SettingsManager.shared.fontXS)
                            Text("NEW WORKFLOW")
                                .font(Theme.current.fontXSBold)
                        }
                        .foregroundColor(Theme.current.foreground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.current.surfaceSelected)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.current.surfaceInput)
            }
        }
        .sheet(isPresented: $showingMemoSelector) {
            // Use currentWorkflow from manager for fresh data
            if let workflow = currentWorkflow ?? editingWorkflow {
                // Use untranscribed memos for TRANSCRIBE workflows, transcribed for others
                let memosToShow = workflow.startsWithTranscribe ? untranscribedMemos : transcribedMemos
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
    }

    private func createNewWorkflow() {
        let newWorkflow = WorkflowDefinition(
            name: "Untitled Workflow",
            description: ""
        )
        editingWorkflow = newWorkflow
        selectedWorkflowID = newWorkflow.id
    }

    private func saveWorkflow() {
        // Use currentWorkflow from manager if available, otherwise fall back to binding
        guard var workflow = currentWorkflow ?? editingWorkflow else { return }
        workflow.modifiedAt = Date()

        if workflowManager.workflows.contains(where: { $0.id == workflow.id }) {
            workflowManager.updateWorkflow(workflow)
        } else {
            workflowManager.addWorkflow(workflow)
        }
        // Sync binding from manager
        editingWorkflow = workflowManager.workflows.first { $0.id == workflow.id }
    }

    private func deleteCurrentWorkflow() {
        guard let workflow = currentWorkflow ?? editingWorkflow else { return }
        workflowManager.deleteWorkflow(workflow)
        editingWorkflow = nil
        selectedWorkflowID = nil
    }

    private func duplicateCurrentWorkflow() {
        guard let workflow = currentWorkflow ?? editingWorkflow else { return }
        let duplicate = workflowManager.duplicateWorkflow(workflow)
        editingWorkflow = duplicate
        selectedWorkflowID = duplicate.id
    }

    private func runWorkflow(_ workflow: WorkflowDefinition, on memo: VoiceMemo) {
        Task {
            do {
                let _ = try await WorkflowExecutor.shared.executeWorkflow(
                    workflow,
                    for: memo,
                    context: viewContext
                )
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

