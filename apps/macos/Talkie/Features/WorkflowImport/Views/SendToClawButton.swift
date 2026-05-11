//
//  SendToClawButton.swift
//  Talkie
//
//  Quick action button to send a memo to the user's Claw.
//  Uses imported workflows from WorkflowFileRepository.
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

struct SendToClawButton: View {

    let memo: MemoRecord

    @State private var isLoading: Bool = false
    @State private var showSuccess: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showWorkflowPicker: Bool = false
    @State private var workflows: [WorkflowDefinition] = []

    var body: some View {
        Button(action: sendToClaw) {
            HStack(spacing: 6) {
                if isLoading {
                    BrailleSpinner(size: 12)
                } else if showSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "paperplane.fill")
                }
                Text("Send to Claw")
            }
        }
        .disabled(isLoading)
        .help("Send this memo to your connected Claw")
        .onAppear(perform: loadWorkflows)
        .sheet(isPresented: $showWorkflowPicker) {
            ImportedWorkflowPickerSheet(
                workflows: workflows,
                onSelect: { workflow in
                    showWorkflowPicker = false
                    Task {
                        await executeWorkflow(workflow)
                    }
                }
            )
        }
        .alert("Failed to Send", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Actions

    private func loadWorkflows() {
        Task {
            // Load only imported workflows
            let allWorkflows = await WorkflowFileRepository.shared.loadedWorkflows
            workflows = allWorkflows.filter { $0.definition.source.isImported }.map { $0.definition }
        }
    }

    private func sendToClaw() {
        Task {
            // Get imported workflows
            let allWorkflows = await WorkflowFileRepository.shared.loadedWorkflows
            let importedWorkflows = allWorkflows.filter { $0.definition.source.isImported }.map { $0.definition }

            if importedWorkflows.isEmpty {
                // No workflows configured - show import sheet?
                errorMessage = "No Claw connected. Import a workflow first."
                showError = true
                return
            }

            if importedWorkflows.count == 1 {
                // Single workflow - use it directly
                await executeWorkflow(importedWorkflows[0])
            } else {
                // Multiple workflows - show picker
                workflows = importedWorkflows
                showWorkflowPicker = true
            }
        }
    }

    private func executeWorkflow(_ workflow: WorkflowDefinition) async {
        await MainActor.run {
            isLoading = true
            showSuccess = false
        }

        do {
            // Convert MemoRecord to MemoModel for WorkflowExecutor
            let memoModel = MemoModel(
                id: memo.id,
                createdAt: memo.createdAt,
                lastModified: memo.lastModified,
                title: memo.title,
                duration: memo.duration,
                sortOrder: memo.sortOrder,
                transcription: memo.transcription,
                notes: memo.notes,
                summary: memo.summary,
                tasks: memo.tasks,
                reminders: memo.reminders,
                audioFilePath: memo.audioFilePath,
                waveformData: memo.waveformData,
                isTranscribing: memo.isTranscribing,
                isProcessingSummary: memo.isProcessingSummary,
                isProcessingTasks: memo.isProcessingTasks,
                isProcessingReminders: memo.isProcessingReminders,
                autoProcessed: memo.autoProcessed,
                originDeviceId: memo.originDeviceId,
                macReceivedAt: memo.macReceivedAt,
                cloudSyncedAt: memo.cloudSyncedAt,
                deletedAt: memo.deletedAt,
                pendingWorkflowIds: memo.pendingWorkflowIds,
                revisionHistoryJSON: memo.revisionHistoryJSON
            )

            // Execute the workflow using the unified WorkflowExecutor
            let executor = WorkflowExecutor.shared
            _ = try await executor.executeWorkflow(workflow, for: memoModel)

            await MainActor.run {
                isLoading = false
                showSuccess = true
                log.info("Sent memo to \(workflow.name)")

                // Reset success indicator after delay
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    await MainActor.run {
                        showSuccess = false
                    }
                }
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
                showError = true
                log.error("Failed to send memo: \(error)")
            }
        }
    }
}

// MARK: - Workflow Picker

struct ImportedWorkflowPickerSheet: View {

    let workflows: [WorkflowDefinition]
    let onSelect: (WorkflowDefinition) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose Destination")
                .font(.headline)

            ForEach(workflows) { workflow in
                Button(action: { onSelect(workflow) }) {
                    HStack {
                        Image(systemName: workflow.icon)
                        Text(workflow.name)
                        Spacer()
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            Button("Cancel") {
                dismiss()
            }
            .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(width: 300)
    }
}

// MARK: - Toolbar Modifier

extension View {

    /// Adds "Send to Claw" button to toolbar if workflows are configured
    func sendToClawToolbarItem(memo: MemoRecord) -> some View {
        self.toolbar {
            ToolbarItem(placement: .automatic) {
                SendToClawButton(memo: memo)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SendToClawButton(memo: MemoRecord(title: "Preview Memo", duration: 60.0, transcription: "Sample transcription for preview"))
        .padding()
}
