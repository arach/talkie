//
//  WorkflowContentViews.swift
//  Talkie macOS
//
//  Extracted from NavigationView.swift
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

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
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
            .background(Theme.current.surface1)

            Divider()
                .opacity(0.5)

            // Right: Inline Editor - expands to fill
            if let binding = Binding($editingWorkflow) {
                WorkflowInlineEditor(
                    workflow: binding,
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

// MARK: - Workflow Memo Selector Sheet

struct WorkflowMemoSelectorSheet: View {
    let workflow: WorkflowDefinition
    let memos: [MemoModel]
    let onSelect: (MemoModel) -> Void
    let onCancel: () -> Void
    private let settings = SettingsManager.shared

    @State private var selectedMemo: MemoModel?
    @State private var searchText = ""

    private var filteredMemos: [MemoModel] {
        if searchText.isEmpty {
            return memos
        }
        let query = searchText.lowercased()
        return memos.filter {
            $0.displayTitle.lowercased().contains(query) ||
            ($0.transcription?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Run Workflow")
                        .font(Theme.current.fontTitleBold)
                    HStack(spacing: 6) {
                        Image(systemName: workflow.icon)
                            .foregroundColor(workflow.color.color)
                        Text(workflow.name)
                            .font(Theme.current.fontBody)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                }
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(Theme.current.fontHeadline)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.lg)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)

                TextField("Search memos...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(Theme.current.fontBody)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(Theme.current.fontSM)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.sm)
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.sm)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            if memos.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "waveform.slash")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.secondary.opacity(0.4))

                    Text("No Transcribed Memos")
                        .font(Theme.current.fontBodyMedium)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("Record and transcribe a voice memo first")
                        .font(Theme.current.fontSM)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredMemos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(Theme.current.fontTitle)
                        .foregroundColor(.secondary.opacity(0.4))

                    Text("No matching memos")
                        .font(Theme.current.fontBody)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedMemo) {
                    ForEach(filteredMemos) { memo in
                        WorkflowMemoRow(memo: memo)
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
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)

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
            .padding(Spacing.lg)
        }
        .frame(width: 500, height: 500)
        .background(Theme.current.surfaceInput)
    }
}

// MARK: - Workflow Memo Row (MemoModel-compatible)

private struct WorkflowMemoRow: View {
    let memo: MemoModel

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(memo.displayTitle)
                    .font(Theme.current.fontBodyMedium)
                    .foregroundColor(Theme.current.foreground)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if memo.source != .unknown {
                        Image(systemName: memo.source.icon)
                            .font(.system(size: 9))
                            .foregroundColor(memo.source.color)
                    }

                    Text(formatDuration(memo.duration))
                        .font(Theme.current.fontXS)

                    Text("·")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)

                    Text(memo.createdAt, style: .relative)
                        .font(Theme.current.fontXS)
                }
                .foregroundColor(Theme.current.foregroundSecondary)
            }

            Spacer()

            if memo.isTranscribing {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
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
                            ProgressView()
                                .scaleEffect(0.5)
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

// MARK: - Workflow Template Picker

struct WorkflowTemplatePicker: View {
    let templates: [WorkflowDefinition]
    let onSelectBlank: () -> Void
    let onSelectTemplate: (WorkflowDefinition) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Workflow")
                    .font(Theme.current.fontTitleBold)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(Theme.current.fontHeadline)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.lg)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Blank option
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("START FRESH")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Button(action: onSelectBlank) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.secondary.opacity(0.1))
                                    Image(systemName: "plus")
                                        .font(Theme.current.fontTitle)
                                        .foregroundColor(.secondary)
                                }
                                .frame(width: 44, height: 44)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Blank Workflow")
                                        .font(Theme.current.fontBodyMedium)
                                        .foregroundColor(Theme.current.foreground)
                                    Text("Start from scratch")
                                        .font(Theme.current.fontXS)
                                        .foregroundColor(Theme.current.foregroundSecondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(Theme.current.fontSM)
                                    .foregroundColor(Theme.current.foregroundMuted)
                            }
                            .padding(Spacing.md)
                            .background(Theme.current.surface1)
                            .cornerRadius(CornerRadius.sm)
                        }
                        .buttonStyle(.plain)
                    }

                    // Templates section
                    if !templates.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("TEMPLATES")
                                .font(Theme.current.fontXSBold)
                                .foregroundColor(Theme.current.foregroundSecondary)

                            ForEach(templates) { template in
                                Button(action: { onSelectTemplate(template) }) {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(template.color.color.opacity(0.15))
                                            Image(systemName: template.icon)
                                                .font(Theme.current.fontBody)
                                                .foregroundColor(template.color.color)
                                        }
                                        .frame(width: 44, height: 44)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(template.name)
                                                .font(Theme.current.fontBodyMedium)
                                                .foregroundColor(Theme.current.foreground)
                                            Text(template.description)
                                                .font(Theme.current.fontXS)
                                                .foregroundColor(Theme.current.foregroundSecondary)
                                                .lineLimit(1)
                                        }

                                        Spacer()

                                        Text("\(template.steps.count) step\(template.steps.count == 1 ? "" : "s")")
                                            .font(Theme.current.fontXS)
                                            .foregroundColor(Theme.current.foregroundMuted)

                                        Image(systemName: "chevron.right")
                                            .font(Theme.current.fontSM)
                                            .foregroundColor(Theme.current.foregroundMuted)
                                    }
                                    .padding(Spacing.md)
                                    .background(Theme.current.surface1)
                                    .cornerRadius(CornerRadius.sm)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(Spacing.lg)
            }
        }
        .frame(width: 500, height: 450)
        .background(Theme.current.surfaceInput)
    }
}
