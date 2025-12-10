//
//  WorkflowContentViews.swift
//  Talkie macOS
//
//  Extracted from NavigationView.swift
//

import SwiftUI
import CoreData
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

// MARK: - Legacy Tool Content Views (keeping for reference)

struct WorkflowsContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var workflowManager = WorkflowManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    @State private var selectedWorkflowID: UUID?
    @State private var editingWorkflow: WorkflowDefinition?
    @State private var showingMemoSelector = false

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)],
        animation: .default
    )
    private var allMemos: FetchedResults<VoiceMemo>

    private var transcribedMemos: [VoiceMemo] {
        allMemos.filter { $0.transcription != nil && !$0.transcription!.isEmpty }
    }

    /// Memos that need transcription (for TRANSCRIBE workflows like HQ Transcribe)
    private var untranscribedMemos: [VoiceMemo] {
        allMemos.filter { ($0.transcription == nil || $0.transcription!.isEmpty) && !$0.isTranscribing }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: Workflow List
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WORKFLOWS")
                            .font(SettingsManager.shared.fontSMBold)
                            .tracking(1.5)
                        Text("\(workflowManager.workflows.count) total")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: createNewWorkflow) {
                        Image(systemName: "plus")
                            .font(SettingsManager.shared.fontBody)
                            .foregroundColor(.primary)
                            .frame(width: 24, height: 24)
                            .background(settings.surfaceSelected)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)

                Divider()
                    .opacity(0.5)

                // Workflow List - unified, no sections
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
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
            .background(settings.surface1)

            Divider()
                .opacity(0.5)

            // Right: Inline Editor - expands to fill
            if editingWorkflow != nil {
                WorkflowInlineEditor(
                    workflow: $editingWorkflow,
                    onSave: saveWorkflow,
                    onDelete: deleteCurrentWorkflow,
                    onDuplicate: duplicateCurrentWorkflow,
                    onRun: { showingMemoSelector = true }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.stack")
                        .font(SettingsManager.shared.fontDisplay)
                        .foregroundColor(.secondary.opacity(0.2))

                    Text("SELECT OR CREATE")
                        .font(SettingsManager.shared.fontXSBold)
                        .tracking(1)
                        .foregroundColor(.secondary.opacity(0.5))

                    Button(action: createNewWorkflow) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(SettingsManager.shared.fontXS)
                            Text("NEW WORKFLOW")
                                .font(SettingsManager.shared.fontXSBold)
                                .tracking(0.5)
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(settings.surfaceSelected)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(settings.surfaceInput)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingMemoSelector) {
            if let workflow = editingWorkflow {
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

    private func selectWorkflow(_ workflow: WorkflowDefinition) {
        // Only update editingWorkflow if selecting a different workflow
        // This prevents overwriting unsaved edits when clicking the same item
        if selectedWorkflowID != workflow.id {
            selectedWorkflowID = workflow.id
            editingWorkflow = workflow
        }
    }

    private func saveWorkflow() {
        guard var workflow = editingWorkflow else { return }
        workflow.modifiedAt = Date()

        if workflowManager.workflows.contains(where: { $0.id == workflow.id }) {
            workflowManager.updateWorkflow(workflow)
        } else {
            workflowManager.addWorkflow(workflow)
        }
        editingWorkflow = workflow
    }

    private func deleteCurrentWorkflow() {
        guard let workflow = editingWorkflow else { return }
        workflowManager.deleteWorkflow(workflow)
        editingWorkflow = nil
        selectedWorkflowID = nil
    }

    private func duplicateCurrentWorkflow() {
        guard let workflow = editingWorkflow else { return }
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

// MARK: - Workflow Memo Selector Sheet

struct WorkflowMemoSelectorSheet: View {
    let workflow: WorkflowDefinition
    let memos: [VoiceMemo]
    let onSelect: (VoiceMemo) -> Void
    let onCancel: () -> Void
    @ObservedObject private var settings = SettingsManager.shared

    @State private var selectedMemo: VoiceMemo?
    @State private var searchText = ""

    private var filteredMemos: [VoiceMemo] {
        if searchText.isEmpty {
            return memos
        }
        let query = searchText.lowercased()
        return memos.filter {
            ($0.title?.lowercased().contains(query) ?? false) ||
            ($0.transcription?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Run Workflow")
                        .font(SettingsManager.shared.fontTitleBold)
                    HStack(spacing: 6) {
                        Image(systemName: workflow.icon)
                            .foregroundColor(workflow.color.color)
                        Text(workflow.name)
                            .font(SettingsManager.shared.fontBody)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(SettingsManager.shared.fontHeadline)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(.secondary)

                TextField("Search memos...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(SettingsManager.shared.fontBody)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(SettingsManager.shared.fontSM)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(settings.surface1)
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            if memos.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "waveform.slash")
                        .font(SettingsManager.shared.fontDisplay)
                        .foregroundColor(.secondary.opacity(0.4))

                    Text("No Transcribed Memos")
                        .font(SettingsManager.shared.fontBodyMedium)
                        .foregroundColor(.secondary)

                    Text("Record and transcribe a voice memo first")
                        .font(SettingsManager.shared.fontSM)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredMemos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(SettingsManager.shared.fontTitle)
                        .foregroundColor(.secondary.opacity(0.4))

                    Text("No matching memos")
                        .font(SettingsManager.shared.fontBody)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedMemo) {
                    ForEach(filteredMemos) { memo in
                        MemoRowView(memo: memo)
                            .tag(memo)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                onSelect(memo)
                            }
                            .onTapGesture(count: 1) {
                                selectedMemo = memo
                            }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            // Footer with action button
            HStack {
                Text("\(filteredMemos.count) memo\(filteredMemos.count == 1 ? "" : "s")")
                    .font(SettingsManager.shared.fontXS)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Run") {
                    if let memo = selectedMemo {
                        onSelect(memo)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedMemo == nil)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(16)
        }
        .frame(width: 500, height: 500)
        .background(settings.surfaceInput)
    }
}

struct WorkflowCard: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var settings = SettingsManager.shared
    let icon: String
    let title: String
    let description: String
    let actionType: WorkflowActionType
    let provider: String
    let model: String

    @State private var showingMemoSelector = false
    @State private var isExecuting = false
    @State private var errorMessage: String?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)],
        animation: .default
    )
    private var allMemos: FetchedResults<VoiceMemo>

    private var transcribedMemos: [VoiceMemo] {
        allMemos.filter { $0.transcription != nil && !$0.transcription!.isEmpty }
    }

    var body: some View {
        Button(action: {
            if !transcribedMemos.isEmpty {
                showingMemoSelector = true
            } else {
                errorMessage = "No transcribed memos available"
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(SettingsManager.shared.fontTitle)
                    .foregroundColor(.primary.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .background(settings.surfaceHover)
                    .cornerRadius(4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(SettingsManager.shared.fontSMBold)
                        .tracking(0.5)

                    Text(description)
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary)

                    if isExecuting {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.5)
                            Text("RUNNING...")
                                .font(SettingsManager.shared.fontXSMedium)
                                .tracking(0.5)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(.secondary.opacity(0.3))
            }
            .padding(12)
            .background(settings.surface1)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isExecuting)
        .sheet(isPresented: $showingMemoSelector) {
            MemoSelectorSheet(
                memos: transcribedMemos,
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

    private func executeWorkflow(for memo: VoiceMemo) {
        isExecuting = true
        showingMemoSelector = false

        Task {
            do {
                try await WorkflowExecutor.shared.execute(
                    action: actionType,
                    for: memo,
                    providerName: provider,
                    modelId: model,
                    context: viewContext
                )
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
    @ObservedObject private var settings = SettingsManager.shared
    let memos: [VoiceMemo]
    let actionType: WorkflowActionType
    let provider: String
    let model: String
    let onExecute: (VoiceMemo) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Memo")
                    .font(SettingsManager.shared.fontTitleBold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(SettingsManager.shared.fontHeadline)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

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
                                    .font(SettingsManager.shared.fontTitle)
                                    .foregroundColor(.blue)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(memo.title ?? "Untitled")
                                        .font(SettingsManager.shared.fontBodyMedium)
                                        .lineLimit(1)

                                    if let date = memo.createdAt {
                                        Text(date, style: .relative)
                                            .font(SettingsManager.shared.fontXS)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(SettingsManager.shared.fontSM)
                                    .foregroundColor(.secondary)
                            }
                            .padding(12)
                            .background(settings.surface1)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 400, height: 500)
        .background(settings.surfaceInput)
    }
}

