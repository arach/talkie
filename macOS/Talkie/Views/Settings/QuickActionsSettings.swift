//
//  QuickActionsSettings.swift
//  Talkie macOS
//
//  Extracted from SettingsView.swift
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

// MARK: - Quick Actions Settings View

struct QuickActionsSettingsView: View {
    @State private var workflowManager = WorkflowManager.shared
    @State private var selectedWorkflow: WorkflowDefinition?
    @State private var showingWorkflowEditor = false

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "bolt",
                title: "QUICK ACTIONS",
                subtitle: "Pin workflows to show them as quick actions when viewing a memo. Pinned workflows sync to iOS via iCloud."
            )
        } content: {
            // Pinned workflows
            VStack(alignment: .leading, spacing: 12) {
                Text("PINNED WORKFLOWS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary)

                if pinnedWorkflows.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "pin.slash")
                            .foregroundColor(Theme.current.foregroundSecondary)
                        Text("No workflows pinned")
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.current.surface1)
                    .cornerRadius(8)
                } else {
                    VStack(spacing: 4) {
                        ForEach(pinnedWorkflows) { workflow in
                            workflowRow(workflow)
                        }
                    }
                }
            }

            Divider()
                .background(Theme.current.divider)

            // Available workflows
            VStack(alignment: .leading, spacing: 12) {
                Text("AVAILABLE WORKFLOWS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary)

                if unpinnedWorkflows.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                        Text("All workflows are pinned")
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.current.surface1)
                    .cornerRadius(8)
                } else {
                    VStack(spacing: 4) {
                        ForEach(unpinnedWorkflows) { workflow in
                            workflowRow(workflow)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingWorkflowEditor) {
            if let workflow = selectedWorkflow {
                WorkflowEditorSheet(
                    workflow: workflow,
                    isNew: false,
                    onSave: { updatedWorkflow in
                        workflowManager.updateWorkflow(updatedWorkflow)
                        showingWorkflowEditor = false
                    },
                    onCancel: {
                        showingWorkflowEditor = false
                    }
                )
                .frame(minWidth: 600, minHeight: 500)
            }
        }
    }

    private var pinnedWorkflows: [WorkflowDefinition] {
        workflowManager.workflows.filter { $0.isPinned }
    }

    private var unpinnedWorkflows: [WorkflowDefinition] {
        workflowManager.workflows.filter { !$0.isPinned }
    }

    @ViewBuilder
    private func workflowRow(_ workflow: WorkflowDefinition) -> some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: workflow.icon)
                .font(SettingsManager.shared.fontTitle)
                .foregroundColor(workflow.color.color)
                .frame(width: 24, height: 24)
                .background(workflow.color.color.opacity(0.15))
                .cornerRadius(6)

            // Name and description
            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                Text(workflow.description)
                    .font(SettingsManager.shared.fontXS)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Edit button
            Button(action: { editWorkflow(workflow) }) {
                Image(systemName: "pencil")
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Edit workflow")

            // Pin/unpin button
            TalkieButtonSync("TogglePin", section: "Settings") {
                togglePin(workflow)
            } label: {
                Image(systemName: workflow.isPinned ? "pin.fill" : "pin")
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(workflow.isPinned ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .help(workflow.isPinned ? "Unpin from quick actions" : "Pin to quick actions")
        }
        .padding(10)
        .background(Theme.current.surface1)
        .cornerRadius(8)
    }

    private func editWorkflow(_ workflow: WorkflowDefinition) {
        selectedWorkflow = workflow
        showingWorkflowEditor = true
    }

    private func togglePin(_ workflow: WorkflowDefinition) {
        var updated = workflow
        updated.isPinned.toggle()
        updated.modifiedAt = Date()
        workflowManager.updateWorkflow(updated)
    }
}

